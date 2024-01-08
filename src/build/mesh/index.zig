const std = @import("std");
const ply = @import("ply.zig");

const BUFFERED_IO_SIZE  = 4096;
const _BufferedReader   = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader);
const _BufferedWriter   = std.io.BufferedWriter(BUFFERED_IO_SIZE, std.fs.File.Writer);

pub const BuildMesh = struct {
   vertices : [] const Vertex,
   indices  : [] const IndexElement,

   pub const Vertex = struct {
      color    : @Vector(4, f32),
      sample   : @Vector(2, f32),
      position : @Vector(3, f32),
      normal   : @Vector(3, f32),
   };

   pub const IndexElement = u16;
};

pub const MeshParseStep = struct {
   step        : std.Build.Step,
   input       : MeshInput,
   output_file : std.Build.GeneratedFile,

   pub const MeshInputTag = enum {
      ply,
   };

   pub const MeshInput = union(MeshInputTag) {
      ply : PlyInput,
   };

   pub const PlyInput = struct {
      path : std.Build.LazyPath,
   };

   pub fn create(owner : * std.Build, input : MeshInput) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");

      const step_name = blk: {
         switch (input) {
            .ply => |*model| {
               const name = model.path.getDisplayName();
               break :blk owner.fmt("meshparsestep ply {s}", .{name});
            },
         }
      };

      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = step_name,
            .owner   = owner,
            .makeFn  = make,
         }),
         .input         = input,
         .output_file   = .{.step = &self.step},
      };

      switch (input) {
         .ply => |*model| {
            model.path.addStepDependencies(&self.step);
         },
      }

      return self;
   }

   pub fn getOutput(self : * const @This()) std.Build.LazyPath {
      return .{.generated = &self.output_file};
   }

   fn make(step : * std.Build.Step, prog_node : * std.Progress.Node) anyerror!void {
      const self = @fieldParentPtr(@This(), "step", step);
      
      switch (self.input) {
         .ply => |*model| {
            try _makePly(step, prog_node, model);
         },
      }

      return;
   }

   fn _makePly(step : * std.Build.Step, prog_node : * std.Progress.Node, input : * const PlyInput) anyerror!void {
      const b     = step.owner;
      const self  = @fieldParentPtr(@This(), "step", step);

      const input_path = input.path.getPath(b);

      var man = b.cache.obtain();
      defer man.deinit();

      man.hash.add(@as(u32, 0x97000c7e));
      _ = try man.addFile(input_path, null);

      const cache_hit   = try step.cacheHit(&man);
      const digest      = man.final();

      const cache_dir = try std.fs.path.join(b.allocator, &.{
         "o", &digest,
      });
      defer b.allocator.free(cache_dir);

      const output_dir = try b.cache_root.join(b.allocator, &.{
         cache_dir,
      });
      defer b.allocator.free(output_dir);

      const basename = std.fs.path.stem(input_path);

      const output_path = try std.fs.path.join(b.allocator, &.{
         output_dir, b.fmt("{s}.zig", .{basename}),
      });
      errdefer b.allocator.free(output_path);

      if (cache_hit == true) {
         self.output_file.path = output_path;
         return;
      }

      const input_file = try std.fs.openFileAbsolute(input_path, .{});
      defer input_file.close();

      try b.cache_root.handle.makePath(cache_dir);
      errdefer b.cache_root.handle.deleteTree(cache_dir) catch @panic("failed to delete cache dir on error cleanup");

      const output_file = try std.fs.createFileAbsolute(output_path, .{});
      defer output_file.close();
      errdefer std.fs.deleteFileAbsolute(output_path) catch @panic("failed to delete output file on error cleanup");

      var input_reader_buffer    = _BufferedReader{.unbuffered_reader = input_file.reader()};
      var output_writer_buffer   = _BufferedWriter{.unbuffered_writer = output_file.writer()};

      var input_reader  = input_reader_buffer.reader();
      var output_writer = output_writer_buffer.writer();

      const mesh = try ply.parsePly(b.allocator, &input_reader);
      defer b.allocator.free(mesh.indices);
      defer b.allocator.free(mesh.vertices);

      try _writeMeshToZigSource(&output_writer, &mesh);

      try output_writer_buffer.flush();

      _ = prog_node;

      self.output_file.path = output_path;
      try man.writeManifest();
      return;
   }

   fn _writeMeshToZigSource(writer : * _BufferedWriter.Writer, mesh : * const BuildMesh) anyerror!void {
      const INDENT = "   ";

      try writer.writeAll(INDENT ++ ".vertices = &.{");

      for (mesh.vertices) |*vertex| {
         try writer.writeAll(".{");
         try _writeVertexToZigSource(writer, vertex);
         try writer.writeAll("},");
      }

      try writer.writeAll("},\n" ++ INDENT ++ ".indices = &.{");

      for (mesh.indices) |index| {
         try writer.print("{},", .{index});
      }

      try writer.writeAll("},\n");

      return;
   }

   fn _writeVertexToZigSource(writer : * _BufferedWriter.Writer, vertex : * const BuildMesh.Vertex) anyerror!void {
      try writer.writeAll(".color=");
      try _writeVectorToZigSource(4, f32, writer, vertex.color);
      try writer.writeAll(",.sample=");
      try _writeVectorToZigSource(2, f32, writer, vertex.sample);
      try writer.writeAll(",.position=");
      try _writeVectorToZigSource(3, f32, writer, vertex.position);
      try writer.writeAll(",.normal=");
      try _writeVectorToZigSource(3, f32, writer, vertex.normal);
      return;
   }

   fn _writeVectorToZigSource(
      comptime COMPONENTS  : comptime_int,
      comptime T           : type,
      writer : * _BufferedWriter.Writer,
      vector : @Vector(COMPONENTS, T),
   ) anyerror!void {
      try writer.writeAll(".{.vector=.{"); 

      for (0..COMPONENTS) |index| {
         const component = vector[index];
         try writer.print("{},", .{component});
      }

      try writer.writeAll("}}");
      return;
   }
};

pub const MeshBundle = struct {
   step           : std.Build.Step,
   contents       : std.ArrayList(Entry),
   generated_file : std.Build.GeneratedFile,

   const MODULE_NAME_GRAPHICS = "graphics";

   pub const Entry = struct {
      parse_step  : * MeshParseStep,
      identifier  : [] const u8,
   };

   pub fn create(owner : * std.Build) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");
      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = "meshbundle",
            .owner   = owner,
            .makeFn  = make,
         }),
         .contents         = std.ArrayList(Entry).init(owner.allocator),
         .generated_file   = .{.step = &self.step},
      };

      return self;
   }

   pub fn addMesh(self : * @This(), mesh_entry : Entry) void {
      const b = self.step.owner;

      const parse_step  = mesh_entry.parse_step;
      const identifier  = b.allocator.dupe(u8, mesh_entry.identifier) catch @panic("out of memory");

      self.contents.append(.{
         .parse_step = parse_step,
         .identifier = identifier,
      }) catch @panic("out of memory");

      self.step.dependOn(&parse_step.step);

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

   fn make(step : * std.Build.Step, prog_node : * std.Progress.Node) anyerror!void {
      const b     = step.owner;
      const self  = @fieldParentPtr(@This(), "step", step);

      const mesh_entries = self.contents.items;

      var man = b.cache.obtain();
      defer man.deinit();

      man.hash.add(@as(u32, 0x2ae748d8));

      for (mesh_entries) |mesh_entry| {
         const mesh_zig_source_path = mesh_entry.parse_step.getOutput().getPath(b);

         _ = try man.addFile(mesh_zig_source_path, null);
         man.hash.addBytes(mesh_entry.identifier);
      }

      const cache_hit   = try step.cacheHit(&man);
      const digest      = man.final();

      const cache_dir = try std.fs.path.join(b.allocator, &.{
         "o", &digest,
      });
      defer b.allocator.free(cache_dir);

      const output_dir = try b.cache_root.join(b.allocator, &.{
         cache_dir,
      });
      defer b.allocator.free(output_dir);

      const basename = "mesh_bundle.zig";

      const output_path = try std.fs.path.join(b.allocator, &.{
         output_dir, basename,
      });
      errdefer b.allocator.free(output_path);

      if (cache_hit == true) {
         self.generated_file.path = output_path;
         return;
      }

      try b.cache_root.handle.makePath(cache_dir);
      errdefer b.cache_root.handle.deleteTree(cache_dir) catch @panic("failed to delete cache dir on error cleanup");

      const output_file = try std.fs.createFileAbsolute(output_path, .{});
      defer output_file.close();

      var output_writer_buffer   = _BufferedWriter{.unbuffered_writer = output_file.writer()};
      var output_writer          = output_writer_buffer.writer();

      try output_writer.writeAll("const graphics = @import(\"" ++ MODULE_NAME_GRAPHICS ++ "\");\n\n");

      for (mesh_entries) |*mesh_entry| {
         try _concatenateAndNamespaceParsedMesh(b, &output_writer, mesh_entry);
      }

      try output_writer_buffer.flush();

      _ = prog_node;

      self.generated_file.path = output_path;
      try man.writeManifest();
      return;
   }

   fn _concatenateAndNamespaceParsedMesh(b : * std.Build, output_writer : * _BufferedWriter.Writer, mesh_entry : * const Entry) anyerror!void {
      const input_path  = mesh_entry.parse_step.getOutput().getPath(b);
      const input_file  = try std.fs.openFileAbsolute(input_path, .{});
      defer input_file.close();

      var input_reader_buffer = _BufferedReader{.unbuffered_reader = input_file.reader()};
      var input_reader        = input_reader_buffer.reader();

      try output_writer.print("pub const {s} = graphics.types.Mesh{{\n", .{mesh_entry.identifier});

      while (input_reader.readByte()) |byte| {
         try output_writer.writeByte(byte);
      } else |err| switch (err) {
         error.EndOfStream => {},
         else => return err,
      }

      try output_writer.writeAll("};\n\n");

      return;
   }
};

