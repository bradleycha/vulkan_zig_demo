const std = @import("std");

pub const ShaderCompileStep = struct {
   step        : std.Build.Step,
   input_file  : std.Build.LazyPath,
   output_file : std.Build.GeneratedFile,
   optimize    : std.builtin.OptimizeMode,
   stage       : Stage,

   pub const Stage = enum {
      vertex,
      fragment,
   };

   pub const CreateInfo = struct {
      input_file  : std.Build.LazyPath,
      optimize    : std.builtin.OptimizeMode,
      stage       : Stage,
   };

   pub fn create(owner : * std.Build, create_info : * const CreateInfo) * @This() {
      const self = owner.allocator.create(@This()) catch @panic ("out of memory");
      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = owner.fmt("shadercompile {s}", .{create_info.input_file.getDisplayName()}),
            .owner   = owner,
            .makeFn  = make,
         }),
         .input_file    = create_info.input_file,
         .output_file   = .{.step = &self.step},
         .optimize      = create_info.optimize,
         .stage         = create_info.stage,
      };

      create_info.input_file.addStepDependencies(&self.step);

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

      man.hash.add(@as(u32, 0x56b28b89));
      _ = try man.addFile(input_path, null);
      man.hash.add(self.optimize);
      man.hash.add(self.stage);

      const cache_hit   = try step.cacheHit(&man);
      const digest      = man.final();

      const cache_path = try std.fs.path.join(b.allocator, &.{
         "o", &digest,
      });
      defer b.allocator.free(cache_path);

      const output_dir = try b.cache_root.join(b.allocator, &.{
         cache_path,
      });
      defer b.allocator.free(output_dir);

      const output_basename = blk: {
         switch (self.stage) {
            .vertex     => break :blk "vertex.spv",
            .fragment   => break :blk "fragment.spv",
         }
      };

      const output_path = try std.fs.path.join(b.allocator, &.{
         output_dir, output_basename,
      });

      if (cache_hit == true) {
         self.output_file.path = output_path;
         return;
      }

      try b.cache_root.handle.makePath(cache_path);
      errdefer b.cache_root.handle.deleteTree(cache_path) catch @panic("failed to delete cache dir on error cleanup");

      const CMD_OPT_FLAG_OPTIMIZE   = "-O";
      const CMD_OPT_FLAG_STAGE      = "-fshader-stage=";

      const cmd_opt_optimize = blk: {
         switch (self.optimize) {
            .Debug         => break :blk CMD_OPT_FLAG_OPTIMIZE ++ "0",
            .ReleaseSafe   => break :blk CMD_OPT_FLAG_OPTIMIZE ++ "",
            .ReleaseSmall  => break :blk CMD_OPT_FLAG_OPTIMIZE ++ "s",
            .ReleaseFast   => break :blk CMD_OPT_FLAG_OPTIMIZE ++ "",
         }
      };

      const cmd_opt_stage = blk: {
         switch (self.stage) {
            .vertex     => break :blk CMD_OPT_FLAG_STAGE ++ "vertex",
            .fragment   => break :blk CMD_OPT_FLAG_STAGE ++ "fragment",
         }
      };

      const argv = [_] [] const u8 {
         "glslc",
         cmd_opt_stage,
         input_path,
         "-o",
         output_path,
         cmd_opt_optimize,
      };

      _ = try step.evalZigProcess(&argv, prog_node);

      self.output_file.path = output_path;
      try man.writeManifest();
      return;
   }
};

pub const ShaderBundle = struct {
   step           : std.Build.Step,
   contents       : std.ArrayList(Entry),
   generated_file : std.Build.GeneratedFile,

   const MODULE_NAME_GRAPHICS = "graphics";

   pub const Entry = struct {
      compile_step   : * ShaderCompileStep,
      identifier     : [] const u8,
      entrypoint     : [] const u8,
   };

   pub const CreateInfo = struct {
      module_graphics   : * std.Build.Module,
   };

   pub fn create(owner : * std.Build) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");
      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = "shaderbundle",
            .owner   = owner,
            .makeFn  = make,
         }),
         .contents         = std.ArrayList(Entry).init(owner.allocator),
         .generated_file   = .{.step = &self.step},
      };

      return self;
   }

   pub fn addShader(self : * @This(), shader_entry : Entry) void {
      const b = self.step.owner;

      const compile_step   = shader_entry.compile_step;
      const identifier     = b.allocator.dupe(u8, shader_entry.identifier) catch @panic("out of memory");
      const entrypoint     = b.allocator.dupe(u8, shader_entry.entrypoint) catch @panic("out of memory");

      self.contents.append(.{
         .compile_step  = compile_step,
         .identifier    = identifier,
         .entrypoint    = entrypoint,
      }) catch @panic("out of memory");

      self.step.dependOn(&compile_step.step);

      return;
   }

   pub fn getOutput(self : * const @This()) std.Build.LazyPath {
      return .{.generated = &self.generated_file};
   }

   pub fn createModule(self : * @This(), module_graphics : * std.Build.Module) * std.Build.Module {
      return self.step.owner.createModule(.{
         .source_file   = self.getOutput(),
         .dependencies  = &.{
            .{
               .name    = MODULE_NAME_GRAPHICS,
               .module  = module_graphics,
            },
         },
      });
   }

   const BUFFERED_IO_SIZE  = 4096;
   const _BufferedReader   = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader);
   const _BufferedWriter   = std.io.BufferedWriter(BUFFERED_IO_SIZE, std.fs.File.Writer);

   fn make(step : * std.Build.Step, prog_node : * std.Progress.Node) anyerror!void {
      _ = prog_node;

      const b     = step.owner;
      const self  = @fieldParentPtr(@This(), "step", step);

      const shader_entries = self.contents.items;

      var man = b.cache.obtain();
      defer man.deinit();

      man.hash.add(@as(u32, 0x17bc426b));

      for (shader_entries) |shader_entry| {
         const shader_path = shader_entry.compile_step.getOutput().getPath(b);

         _ = try man.addFile(shader_path, null);
         man.hash.addBytes(shader_entry.identifier);
         man.hash.addBytes(shader_entry.entrypoint);
      }

      const cache_hit   = try step.cacheHit(&man);
      const digest      = man.final();

      const cache_path = try std.fs.path.join(b.allocator, &.{
         "o", &digest,
      });
      defer b.allocator.free(cache_path);

      const output_dir = try b.cache_root.join(b.allocator, &.{
         cache_path,
      });
      defer b.allocator.free(output_dir);

      const output_basename = "shader_bundle.zig";

      const output_path = try std.fs.path.join(b.allocator, &.{
         output_dir, output_basename,
      });

      if (cache_hit == true) {
         self.generated_file.path = output_path;
         return;
      }

      try b.cache_root.handle.makePath(cache_path);
      errdefer b.cache_root.handle.deleteTree(cache_path) catch @panic("failed to delete cache dir on error cleanup");

      var output_file = try std.fs.createFileAbsolute(output_path, .{});
      defer output_file.close();

      var output_writer_buffer   = _BufferedWriter{.unbuffered_writer = output_file.writer()};
      var output_writer          = output_writer_buffer.writer();

      try output_writer.writeAll("const graphics = @import(\"" ++ MODULE_NAME_GRAPHICS ++ "\");\n\n");

      for (shader_entries) |shader_entry| {
         try embedShaderCode(b, &output_writer, &shader_entry);
      }

      try output_writer_buffer.flush();

      self.generated_file.path = output_path;
      try man.writeManifest();
      return;
   }

   fn embedShaderCode(b : * std.Build, output_writer : * _BufferedWriter.Writer, shader_entry : * const Entry) anyerror!void {
      const INDENT = "   ";

      const input_path = shader_entry.compile_step.getOutput().getPath(b);
      const input_file = try std.fs.openFileAbsolute(input_path, .{.mode = .read_only});

      var input_reader_buffer = _BufferedReader{.unbuffered_reader = input_file.reader()};
      var input_reader        = input_reader_buffer.reader();

      try output_writer.print("pub const {s} = graphics.ShaderSource{{\n", .{shader_entry.identifier});

      try output_writer.writeAll(INDENT ++ ".bytecode = blk: {const data align(@alignOf(u32)) = [_] u8 {");

      while (input_reader.readByte()) |byte| {
         try output_writer.print("{},", .{byte});
      } else |err| switch (err) {
         error.EndOfStream => {},
         else              => return err,
      }

      try output_writer.print("}}; break :blk &data;}},\n" ++ INDENT ++ ".entrypoint = \"{s}\",\n}};\n\n", .{shader_entry.entrypoint});

      return;
   }
};

