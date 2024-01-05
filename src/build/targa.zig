const std = @import("std");

const BUFFERED_IO_SIZE  = 4096;
const _BufferedReader   = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader);
const _BufferedWriter   = std.io.BufferedWriter(BUFFERED_IO_SIZE, std.fs.File.Writer);

pub const TargaParseStep = struct {
   step        : std.Build.Step,
   input_file  : std.Build.LazyPath,
   output_file : std.Build.GeneratedFile,

   pub fn create(owner : * std.Build, path : std.Build.LazyPath) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");
      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = owner.fmt("targaparsestep {s}", .{path.getDisplayName()}),
            .owner   = owner,
            .makeFn  = make,
         }),
         .input_file    = path,
         .output_file   = .{.step = &self.step},
      };

      path.addStepDependencies(&self.step);

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

      try _parseTargaToZigSource(b, &input_reader, &output_writer);

      try output_writer_buffer.flush();

      _ = prog_node;

      self.output_file.path = output_path;
      try man.writeManifest();
      return;
   }
};

pub const TargaBundle = struct {
   step           : std.Build.Step,
   contents       : std.ArrayList(Entry),
   generated_file : std.Build.GeneratedFile,

   pub const Entry = struct {
      parse_step  : * TargaParseStep,
      identifier  : [] const u8,
   };

   pub fn create(owner : * std.Build) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");
      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = "targabundle",
            .owner   = owner,
            .makeFn  = make,
         }),
         .contents         = std.ArrayList(Entry).init(owner.allocator),
         .generated_file   = .{.step = &self.step},
      };

      return self;
   }

   pub fn addTarga(self : * @This(), targa_entry : Entry) void {
      const b = self.step.owner;

      const parse_step  = targa_entry.parse_step;
      const identifier  = b.allocator.dupe(u8, targa_entry.identifier) catch @panic("out of memory");

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

   pub fn createModule(self : * @This()) * std.Build.Module {
      return self.step.owner.createModule(.{
         .source_file   = self.getOutput(),
         .dependencies  = &.{},
      });
   }

   fn make(step : * std.Build.Step, prog_node : * std.Progress.Node) anyerror!void {
      const b     = step.owner;
      const self  = @fieldParentPtr(@This(), "step", step);

      const targa_entries = self.contents.items;

      var man = b.cache.obtain();
      defer man.deinit();

      man.hash.add(@as(u32, 0x76a260c1));

      for (targa_entries) |targa_entry| {
         const targa_zig_source_path = targa_entry.parse_step.getOutput().getPath(b);

         _ = try man.addFile(targa_zig_source_path, null);
         man.hash.addBytes(targa_entry.identifier);
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

      const basename = "targa_bundle.zig";

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

      for (targa_entries) |targa_entry| {
         try _concatenateAndNamespaceParsedTarga(b, &output_writer, &targa_entry);
      }

      try output_writer_buffer.flush();

      _ = prog_node;

      self.generated_file.path = output_path;
      try man.writeManifest();
      return;
   }

   fn _concatenateAndNamespaceParsedTarga(b : * std.Build, output_writer : * _BufferedWriter.Writer, targa_entry : * const Entry) anyerror!void {
      const input_path  = targa_entry.parse_step.getOutput().getPath(b);
      const input_file  = try std.fs.openFileAbsolute(input_path, .{});
      defer input_file.close();

      var input_reader_buffer = _BufferedReader{.unbuffered_reader = input_file.reader()};
      var input_reader        = input_reader_buffer.reader();

      try output_writer.print("pub const {s} = struct {{\n", .{targa_entry.identifier});

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

fn _parseTargaToZigSource(b : * std.Build, input : * _BufferedReader.Reader, output : * _BufferedWriter.Writer) anyerror!void {
   const header = try TargaHeader.parse(input);

   // We don't want to allow images with no data included as this will break our
   // asset loader at runtime.
   if (header.image_type == .none or header.image_spec.width == 0 or header.image_spec.height == 0) {
      return error.NoDataPresent;
   }

   // TODO: Color map support, we can get away without it for now since we're
   // not living in 1984 anymore, but this should be supported.
   if (header.color_map_type != .none) {
      return error.ColorMapUnsupported;
   }

   // We don't care about the image identity stuff, skip over it.  We use a
   // buffer size of 1 because I/O is already buffered, we don't need further
   // buffering on top of that.
   try input.skipBytes(header.image_id_length, .{.buf_size = 1});

   // TODO: This shouldn't be here.  For now it is because we're not allowing
   // color-mapped images but for the future we should parse this, not skip it.
   try input.skipBytes(header.color_map_spec.bytes(), .{.buf_size = 1});

   // TODO: Implement rest - decompression and pixel format conversion
   _ = b;
   _ = output;
   return error.NotImplemented;
}

const TARGA_ENDIANESS = std.builtin.Endian.Little;

const TargaHeader = struct {
   image_id_length   : u8,
   color_map_type    : ColorMapType,
   image_type        : ImageType,
   color_map_spec    : ColorMapSpecification,
   image_spec        : ImageSpecification,

   pub const ColorMapType = enum(u8) {
      none        = 0,
      colormapped = 1,
   };

   pub const ImageType = enum(u8) {
      none                    = 0,
      colormapped             = 1,
      truecolor               = 2,
      monochrome              = 3,
      colormapped_compressed  = 9,
      truecolor_compressed    = 10,
      monochrome_compressed   = 11,

      pub fn isCompressed(self : @This()) bool {
         return @intFromEnum(self) >= 9;
      }
   };

   pub const ColorMapSpecification = struct {
      start    : u16,
      length   : u16,
      depth    : u8,

      pub fn bytesPerEntry(self : * const @This()) u5 {
         return @intCast(std.math.divCeil(u8, self.depth, 8) catch unreachable);
      }

      pub fn bytes(self : * const @This()) u24 {
         return @as(u24, self.length) * @as(u24, self.bytesPerEntry());
      }
   };

   pub const ImageSpecification = struct {
      x_offset    : u16,
      y_offset    : u16,
      width       : u16,
      height      : u16,
      pixel_depth : PixelDepth,
      descriptor  : u8,

      pub const PixelDepth = enum(u8) {
         // TODO: The order may be wrong, test this
         // TODO: Support more than 32-bit RGBA
         rgba8888 = 32,
      };
   };

   pub fn parse(reader : * _BufferedReader.Reader) anyerror!@This() {
      const image_id_length            = try reader.readInt(u8,   TARGA_ENDIANESS);
      const color_map_type_tag         = try reader.readInt(u8,   TARGA_ENDIANESS);
      const image_type_tag             = try reader.readInt(u8,   TARGA_ENDIANESS);
      const color_map_spec_start       = try reader.readInt(u16,  TARGA_ENDIANESS);
      const color_map_spec_length      = try reader.readInt(u16,  TARGA_ENDIANESS);
      const color_map_spec_depth       = try reader.readInt(u8,   TARGA_ENDIANESS);
      const image_spec_x_offset        = try reader.readInt(u16,  TARGA_ENDIANESS);
      const image_spec_y_offset        = try reader.readInt(u16,  TARGA_ENDIANESS);
      const image_spec_width           = try reader.readInt(u16,  TARGA_ENDIANESS);
      const image_spec_height          = try reader.readInt(u16,  TARGA_ENDIANESS);
      const image_spec_pixel_depth_tag = try reader.readInt(u8,   TARGA_ENDIANESS);
      const image_spec_descriptor      = try reader.readInt(u8,   TARGA_ENDIANESS);

      const color_map_type          = std.meta.intToEnum(@This().ColorMapType, color_map_type_tag)                            catch return error.UnsupportedColorMapType;
      const image_type              = std.meta.intToEnum(@This().ImageType, image_type_tag)                                   catch return error.UnsupportedImageType;
      const image_spec_pixel_depth  = std.meta.intToEnum(@This().ImageSpecification.PixelDepth, image_spec_pixel_depth_tag)   catch return error.UnsupportedPixelFormat;

      const header = @This(){
         .image_id_length  = image_id_length,
         .color_map_type   = color_map_type,
         .image_type       = image_type,
         .color_map_spec   = .{
            .start         = color_map_spec_start,
            .length        = color_map_spec_length,
            .depth         = color_map_spec_depth,
         },
         .image_spec       = .{
            .x_offset      = image_spec_x_offset,
            .y_offset      = image_spec_y_offset,
            .width         = image_spec_width,
            .height        = image_spec_height,
            .pixel_depth   = image_spec_pixel_depth,
            .descriptor    = image_spec_descriptor,
         },
      };

      return header;
   }
};

