const std = @import("std");

const BUFFERED_IO_SIZE = 4096;

pub const ShaderCompileStep = struct {
   step        : std.Build.Step,
   input_file  : std.Build.LazyPath,
   output_file : std.Build.GeneratedFile,
   stage       : Stage,
   optimize    : std.builtin.OptimizeMode,

   pub const Stage = enum {
      vertex,
      fragment,
   };

   pub const Options = struct {
      input_file  : std.Build.LazyPath,
      stage       : Stage,
      optimize    : std.builtin.OptimizeMode,
   };

   pub fn create(owner : * std.Build, options : Options) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");
      self.* = .{
         .step          = std.Build.Step.init(.{
            .id      = .custom,
            .name    = owner.fmt("shadercompile {s}", .{options.input_file.getDisplayName()}),
            .owner   = owner,
            .makeFn  = make,
         }),
         .input_file    = options.input_file,
         .output_file   = std.Build.GeneratedFile{.step = &self.step},
         .stage         = options.stage,
         .optimize      = options.optimize,
      };

      options.input_file.addStepDependencies(&self.step);
      return self;
   }

   pub fn getOutput(self : * const @This()) std.Build.LazyPath {
      return .{.generated = &self.output_file};
   }

   fn make(step : * std.Build.Step, prog_node : * std.Progress.Node) anyerror!void {
      const b     = step.owner;
      const self  = @fieldParentPtr(@This(), "step", step);

      const input_path = self.input_file.getPath(b);

      var man = b.cache.obtain();
      defer man.deinit();

      man.hash.add(@as(u32, 0x9c4516dc));
      _ = try man.addFile(input_path, null);
      man.hash.add(self.stage);
      man.hash.add(self.optimize);

      const cache_hit   = try step.cacheHit(&man);
      const digest      = man.final();

      const base_name = blk: {
         switch (self.stage) {
            .vertex     => break :blk "vertex",
            .fragment   => break :blk "fragment",
         }
      };

      const output_path = try b.cache_root.join(b.allocator, &.{
         "o", &digest, b.fmt("{s}.spv", .{base_name}),
      });

      if (cache_hit == true) {
         self.output_file.path = output_path;
         return;
      }

      const output_dir = std.fs.path.dirname(output_path) orelse unreachable;
      std.fs.makeDirAbsolute(output_dir) catch {};

      const ARG_GLSL    = "glslc";
      const ARG_STAGE   = "-fshader-stage=";
      const ARG_OPT     = "-O";
      const ARG_OUTPUT  = "-o";

      const argument_stage = blk: {
         switch (self.stage) {
            .vertex     => break :blk ARG_STAGE ++ "vertex",
            .fragment   => break :blk ARG_STAGE ++ "fragment",
         }
      };

      const argument_optimize = blk: {
         switch (self.optimize) {
            .Debug         => break :blk ARG_OPT ++ "0",
            .ReleaseSafe   => break :blk ARG_OPT ++ "",
            .ReleaseSmall  => break :blk ARG_OPT ++ "s",
            .ReleaseFast   => break :blk ARG_OPT ++ "",
         }
      };

      const argv = &([_] [] const u8 {
         ARG_GLSL,
         argument_stage,
         input_path,
         ARG_OUTPUT,
         output_path,
         argument_optimize,
      });

      _ = try step.evalZigProcess(argv, prog_node);

      self.output_file.path = output_path;
      return;
   }
};

pub const ShaderModuleStep = struct {
   step           : std.Build.Step,
   shaders        : std.ArrayList(ShaderBinary),
   generated_file : std.Build.GeneratedFile,

   pub const ShaderBinary = struct {
      spv_identifier          : [] const u8,
      spv_file                : std.Build.LazyPath,
      entrypoint_identifier   : [] const u8,
      entrypoint              : [] const u8,
   };

   pub fn create(owner : * std.Build) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");
      self.* = .{
         .step          = std.Build.Step.init(.{
            .id      = .custom,
            .name    = "shadermodule",
            .owner   = owner,
            .makeFn  = make,
         }),
         .shaders          = std.ArrayList(ShaderBinary).init(owner.allocator),
         .generated_file   = .{.step = &self.step},
      };

      return self;
   }

   pub fn getOutput(self : * @This()) std.Build.LazyPath {
      return .{.generated = &self.generated_file};
   }

   pub fn addShader(self : * @This(), shader : ShaderBinary) void {
      self.shaders.append(shader) catch @panic("out of memory");

      shader.spv_file.addStepDependencies(&self.step);

      return;
   }

   pub fn createModule(self : * @This()) * std.Build.Module {
      return self.step.owner.createModule(.{
         .source_file   = self.getOutput(),
         .dependencies  = &.{},
      });
   }

   fn make(step : * std.Build.Step, prog_node : * std.Progress.Node) anyerror!void {
      const b     = step.owner;
      const self  = @fieldParentPtr(@This(), "step", step);

      _ = prog_node;

      var man = b.cache.obtain();
      defer man.deinit();

      man.hash.add(@as(u32, 0x0b4fce55));

      for (self.shaders.items) |shader| {
         man.hash.addBytes(shader.spv_identifier);
         man.hash.addBytes(shader.spv_file.getPath(b));
         man.hash.addBytes(shader.entrypoint_identifier);
         man.hash.addBytes(shader.entrypoint);
      }

      const cache_hit   = try step.cacheHit(&man);
      const digest      = man.final();

      const output_path = try b.cache_root.join(b.allocator, &.{
         "o", &digest, "shaders.zig",
      });

      if (cache_hit == true) {
         self.generated_file.path = output_path;
         return;
      }

      const output_dir = std.fs.path.dirname(output_path) orelse unreachable;
      std.fs.makeDirAbsolute(output_dir) catch {};

      var output_file = try std.fs.createFileAbsolute(output_path, .{});
      defer output_file.close();

      var output_file_writer_buffer = std.io.BufferedWriter(BUFFERED_IO_SIZE, std.fs.File.Writer){.unbuffered_writer = output_file.writer()};
      defer output_file_writer_buffer.flush() catch {};
      var output_file_writer = output_file_writer_buffer.writer();

      for (self.shaders.items) |*shader| {
         try _appendShaderCode(b, shader, &output_file_writer);
      }

      self.generated_file.path = output_path;
      return;
   }

   fn _appendShaderCode(b : * std.Build, shader : * const ShaderBinary, output_writer : * std.io.BufferedWriter(BUFFERED_IO_SIZE, std.fs.File.Writer).Writer) anyerror!void {
      const shader_path = shader.spv_file.getPath(b);
      const shader_file = try std.fs.openFileAbsolute(shader_path, .{});
      defer shader_file.close();

      var shader_reader_buffer = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader){.unbuffered_reader = shader_file.reader()};
      var shader_reader        = shader_reader_buffer.reader();

      try output_writer.print("pub const {s} align(@alignOf(u32)) = [_] u8 {{", .{shader.spv_identifier});

      while (shader_reader.readByte()) |byte| {
         try output_writer.print("{},", .{byte});
      } else |err| switch (err) {
         error.EndOfStream => {},
         else              => return err,
      }

      try output_writer.print("}};\n", .{});

      try output_writer.print("pub const {s} = [_:0] u8 {{}} ++ \"{s}\";\n", .{shader.entrypoint_identifier, shader.entrypoint});

      return;
   }
};

