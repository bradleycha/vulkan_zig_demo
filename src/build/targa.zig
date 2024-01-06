const std = @import("std");

const TARGA_ENDIANESS            = std.builtin.Endian.Little;
const BYTES_PER_PIXEL_RGBA8888   = 4;

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
   if (header.image_type == .none or header.image_spec.pixels() == 0) {
      return error.NoDataPresent;
   }

   // We don't care about the image identity stuff, skip over it.  We use a
   // buffer size of 1 because I/O is already buffered, we don't need further
   // buffering on top of that.
   try input.skipBytes(header.image_id_length, .{.buf_size = 1});

   // Read in the raw pixel data
   const pixels_raw = try _readPixelDataAlloc(b.allocator, input, &header); 
   defer b.allocator.free(pixels_raw);

   // Convert from the current pixel format to RGBA8888 and apply image offsets.
   const pixels_final = try b.allocator.alloc(u8, header.image_spec.pixels() * BYTES_PER_PIXEL_RGBA8888);
   defer b.allocator.free(pixels_final);
   switch (header.image_spec.pixel_depth) {
      .bgr888     => _convertOffsetColorspaceBgr888(pixels_raw, pixels_final, &header),
      .bgra8888   => _convertOffsetColorspaceBgra8888(pixels_raw, pixels_final, &header),
   }

   // Finally, generate zig source code which embeds the decoded image data.
   try _writeDecodedImageToZigSource(output, pixels_final, header.image_spec.width, header.image_spec.height);

   return;
}

fn _readPixelDataAlloc(allocator : std.mem.Allocator, reader : * _BufferedReader.Reader, header : * const TargaHeader) anyerror![] const u8 {
   // TODO: Support color-mapped and monochrome images.
   if (header.color_map_type != .none) {
      return error.ColorMapUnsupported;
   }
   if (header.image_type == .monochrome or header.image_type == .monochrome_compressed) {
      return error.MonochromeUnsupported;
   }
   try reader.skipBytes(header.color_map_spec.bytes(), .{.buf_size = 1});

   const pixels = try allocator.alloc(u8, header.image_spec.bytes());
   errdefer allocator.free(pixels);
   switch (header.image_type.isCompressed()) {
      true  => try _readPixelDataCompressed(reader, pixels, header),
      false => try _readPixelDataUncompressed(reader, pixels),
   }

   return pixels;
}

fn _readPixelDataCompressed(reader : * _BufferedReader.Reader, buffer : [] u8, header : * const TargaHeader) anyerror!void {
   const bytes_per_pixel   = header.image_spec.bytesPerPixel();
   const pixels_expected   = header.image_spec.pixels();

   var pixels_decoded : usize = 0;
   while (pixels_decoded < pixels_expected) {
      const count_packet = try reader.readByte();

      // The MSB states whether this signifies a single pixel being repeated
      // or a collection of uncompressed pixels.  The actual count is the lowest
      // 7 bits plus 1, so its in the range 1-128
      const COMPRESSION_BIT   = @as(u8, 1) << 7;
      const is_compressed     = count_packet & COMPRESSION_BIT != 0;
      const count             = (count_packet & ~COMPRESSION_BIT) + 1;

      const buffer_decode = buffer[pixels_decoded * bytes_per_pixel..][0..count * bytes_per_pixel];

      switch (is_compressed) {
         true  => try _decodePixelCompressed(reader, buffer_decode, count, bytes_per_pixel),
         false => try _decodePixelUncompressed(reader, buffer_decode, count, bytes_per_pixel),
      }

      pixels_decoded += count;
   }

   if (pixels_decoded != pixels_expected) {
      return error.ImageDataCorrupt;
   }

   return;
}

fn _decodePixelCompressed(reader : * _BufferedReader.Reader, buffer : [] u8, count : u8, bytes_per_pixel : u5) anyerror!void {
   const bytes_to_read = bytes_per_pixel;

   const read_count = try reader.readAtLeast(buffer[0..bytes_to_read], bytes_to_read);
   if (read_count != bytes_to_read) {
      return error.ImageDataTruncated;
   }

   for (1..count) |i| {
      @memcpy(buffer[bytes_per_pixel * i..][0..bytes_per_pixel], buffer[0..bytes_per_pixel]);
   }

   return;
}

fn _decodePixelUncompressed(reader : * _BufferedReader.Reader, buffer : [] u8, count : u8, bytes_per_pixel : u5) anyerror!void {
   const bytes_to_read = count * bytes_per_pixel;

   const read_count = try reader.readAtLeast(buffer[0..bytes_to_read], bytes_to_read);
   if (read_count != bytes_to_read) {
      return error.ImageDataTruncated;
   }

   return;
}

fn _readPixelDataUncompressed(reader : * _BufferedReader.Reader, buffer : [] u8) anyerror!void {
   const read_count = try reader.readAtLeast(buffer, buffer.len);
   if (read_count != buffer.len) {
      return error.ImageDataTruncated;
   }

   return;
}

fn _convertOffsetColorspaceBgr888(buffer_src : [] const u8, buffer_dst : [] u8, header : * const TargaHeader) void {
   return _convertOffsetColorspaceGeneric(
      3,
      _convertPixelFromBgr888,
      buffer_src,
      buffer_dst,
      header,
   );
}

fn _convertPixelFromBgr888(pixel : @Vector(3, u8)) @Vector(BYTES_PER_PIXEL_RGBA8888, u8) {
   return .{pixel[2], pixel[1], pixel[0], std.math.maxInt(u8)};
}

fn _convertOffsetColorspaceBgra8888(buffer_src : [] const u8, buffer_dst : [] u8, header : * const TargaHeader) void {
   return _convertOffsetColorspaceGeneric(
      4,
      _convertPixelFromBgra8888,
      buffer_src,
      buffer_dst,
      header,
   );
}

fn _convertPixelFromBgra8888(pixel : @Vector(4, u8)) @Vector(BYTES_PER_PIXEL_RGBA8888, u8) {
   return .{pixel[2], pixel[1], pixel[0], pixel[3]};
}

fn _convertOffsetColorspaceGeneric(
   comptime VEC_COMPONENTS_SRC   : comptime_int,
   comptime PFN_CONVERT          : * const fn (@Vector(VEC_COMPONENTS_SRC, u8)) @Vector(BYTES_PER_PIXEL_RGBA8888, u8),
   buffer_src                    : [] const u8,
   buffer_dst                    : [] u8,
   header                        : * const TargaHeader,
) void {
   // Pixel count of 0 is checked previously, no need for safety checks
   const pixels         = header.image_spec.pixels();
   const pixels_mul     = pixels * BYTES_PER_PIXEL_RGBA8888;
   const x_offset_mod   = @mod(header.image_spec.x_offset, header.image_spec.width);
   const y_offset_mod   = @mod(header.image_spec.y_offset, header.image_spec.height);

   var index_src : usize = 0;
   var index_dst : usize = ((y_offset_mod * header.image_spec.height) + x_offset_mod) * BYTES_PER_PIXEL_RGBA8888;
   for (0..pixels) |_| {
      // We can do this instead of @mod(...) in the loop since the above code
      // ensures we will always be at most a factor of 1 out of range.  This
      // allows us to avoid a very costly div instruction on most architectures.
      // Hopefully the compiler will use conditional move instructions here.
      // I don't think there's a builtin to do this more explicitly.
      const subtract = blk: {
         switch (index_dst >= pixels_mul) {
            true  => {
               @setCold(true);
               break :blk pixels_mul;
            },
            false => {
               @setCold(false);
               break :blk 0;
            },
         }
      };

      index_dst -= subtract;

      // Before you think you can just @ptrCast(...) the array to an array of
      // vectors, it doesn't work because the vector length will be rounded
      // to the nearest hardware-supported vector length which will destroy
      // offsets and calculations.
      const src_slice = buffer_src[index_src..][0..VEC_COMPONENTS_SRC];
      const dst_slice = buffer_dst[index_dst..][0..BYTES_PER_PIXEL_RGBA8888];

      dst_slice.* = PFN_CONVERT(src_slice.*);

      index_src += VEC_COMPONENTS_SRC;
      index_dst += BYTES_PER_PIXEL_RGBA8888;
   }

   return;
}

fn _writeDecodedImageToZigSource(writer : * _BufferedWriter.Writer, data : [] const u8, width : u32, height : u32) anyerror!void {
   const INDENT            = "   ";
   const IDENTIFIER_DATA   = "data";
   const IDENTIFIER_WIDTH  = "width";
   const IDENTIFIER_HEIGHT = "height";

   try writer.writeAll(
      INDENT ++ "pub const " ++ IDENTIFIER_DATA ++ " : " ++ @typeName(@TypeOf(data)) ++ " = &.{"
   );

   for (data) |byte| {
      try writer.print("{},", .{byte});
   }

   try writer.print(
      "}};\n" ++
      INDENT ++ "pub const " ++ IDENTIFIER_WIDTH ++ " : " ++ @typeName(@TypeOf(width)) ++ " = {};\n" ++
      INDENT ++ "pub const " ++ IDENTIFIER_HEIGHT ++ " : " ++ @typeName(@TypeOf(height)) ++ " = {};"
   , .{width, height});

   return;
}

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
         // TODO: Support more pixel formats
         bgr888   = 24,
         bgra8888 = 32,
      };

      pub fn bytesPerPixel(self : * const @This()) u5 {
         return @intCast(std.math.divCeil(u8, @intFromEnum(self.pixel_depth), 8) catch unreachable);
      }

      pub fn pixels(self : * const @This()) u32 {
         return @as(u32, self.width) * @as(u32, self.height);
      }

      pub fn bytes(self : * const @This()) u37 {
         return @as(u37, self.pixels()) * @as(u37, self.bytesPerPixel());
      }
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

