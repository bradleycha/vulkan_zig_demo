const std   = @import("std");
const targa = @import("targa.zig");

const BUFFERED_IO_SIZE  = 4096;
const _BufferedReader   = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader);
const _BufferedWriter   = std.io.BufferedWriter(BUFFERED_IO_SIZE, std.fs.File.Writer);

pub const ImageParseStep = struct {
   step        : std.Build.Step,
   input_file  : std.Build.LazyPath,
   output_file : std.Build.GeneratedFile,
   format      : Format,

   pub const Format = enum {
      targa,
   };

   pub const CreateInfo = struct {
      path     : std.Build.LazyPath,
      format   : Format,
   };

   pub fn create(owner : * std.Build, create_info : * const CreateInfo) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");
      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = owner.fmt("imageparsestep {} {s}", .{create_info.format, create_info.path.getDisplayName()}),
            .owner   = owner,
            .makeFn  = make,
         }),
         .input_file    = create_info.path,
         .output_file   = .{.step = &self.step},
         .format        = create_info.format,
      };

      create_info.path.addStepDependencies(&self.step);

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

      man.hash.add(@as(u32, 0x9efd4658));
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

      const input_file  = try std.fs.openFileAbsolute(input_path, .{});
      defer input_file.close();

      try b.cache_root.handle.makePath(cache_dir);
      errdefer b.cache_root.handle.deleteTree(cache_dir) catch @panic("failed to delete cache dir on error cleanup");

      const output_file = try std.fs.createFileAbsolute(output_path, .{});
      defer output_file.close();
      errdefer b.cache_root.handle.deleteFile(output_path) catch @panic("failed to delete output file on error cleanup");

      var input_reader_buffer    = _BufferedReader{.unbuffered_reader = input_file.reader()};
      var output_writer_buffer   = _BufferedWriter{.unbuffered_writer = output_file.writer()};

      var input_reader  = input_reader_buffer.reader();
      var output_writer = output_writer_buffer.writer();

      const pfn_parse_image : * const fn(std.mem.Allocator, * _BufferedReader.Reader, * _BufferedWriter.Writer) anyerror!void = blk: {
         switch (self.format) {
            .targa   => break :blk targa.parseTargaToZigSource,
         }
      };

      try pfn_parse_image(b.allocator, &input_reader, &output_writer);

      try output_writer_buffer.flush();

      _ = prog_node;

      self.output_file.path = output_path;
      try man.writeManifest();
      return;
   }
};

pub const ImageBundle = struct {
   step           : std.Build.Step,
   contents       : std.ArrayList(Entry),
   generated_file : std.Build.GeneratedFile,

   const MODULE_NAME_GRAPHICS = "graphics";

   pub const Entry = struct {
      parse_step  : * ImageParseStep,
      identifier  : [] const u8,
   };

   pub fn create(owner : * std.Build) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");
      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = "imagebundle",
            .owner   = owner,
            .makeFn  = make,
         }),
         .contents         = std.ArrayList(Entry).init(owner.allocator),
         .generated_file   = .{.step = &self.step},
      };

      return self;
   }

   pub fn addImage(self : * @This(), image_entry : Entry) void {
      const b = self.step.owner;

      const parse_step  = image_entry.parse_step;
      const identifier  = b.allocator.dupe(u8, image_entry.identifier) catch @panic("out of memory");

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

      const image_entries = self.contents.items;

      var man = b.cache.obtain();
      defer man.deinit();

      man.hash.add(@as(u32, 0x76a260c1));

      for (image_entries) |image_entry| {
         const image_zig_source_path = image_entry.parse_step.getOutput().getPath(b);

         _ = try man.addFile(image_zig_source_path, null);
         man.hash.addBytes(image_entry.identifier);
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

      const basename = "image_bundle.zig";

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

      for (image_entries) |targa_entry| {
         try _concatenateAndNamespaceParsedImage(b, &output_writer, &targa_entry);
      }

      try output_writer_buffer.flush();

      _ = prog_node;

      self.generated_file.path = output_path;
      try man.writeManifest();
      return;
   }

   fn _concatenateAndNamespaceParsedImage(b : * std.Build, output_writer : * _BufferedWriter.Writer, image_entry : * const Entry) anyerror!void {
      const input_path  = image_entry.parse_step.getOutput().getPath(b);
      const input_file  = try std.fs.openFileAbsolute(input_path, .{});
      defer input_file.close();

      var input_reader_buffer = _BufferedReader{.unbuffered_reader = input_file.reader()};
      var input_reader        = input_reader_buffer.reader();

      try output_writer.print("pub const {s} = graphics.ImageSource{{\n", .{image_entry.identifier});

      // This may look bad, but since we are using buffered I/O, this is
      // actually good since we're not loading the entire file into memory
      // at once.
      while (input_reader.readByte()) |byte| {
         try output_writer.writeByte(byte);
      } else |err| switch (err) {
         error.EndOfStream => {},
         else => return err,
      }

      try output_writer.print("\n}};\n\n", .{});

      return;
   }
};

