const std = @import("std");

const BUFFERED_IO_SIZE  = 4096;
const _BufferedReader   = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader);
const _BufferedWriter   = std.io.BufferedWriter(BUFFERED_IO_SIZE, std.fs.File.Writer);

const TARGA_ENDIANESS            = std.builtin.Endian.Little;
const BYTES_PER_PIXEL_RGBA8888   = 4;

pub fn parseTargaToZigSource(allocator : std.mem.Allocator, input : * _BufferedReader.Reader, output : * _BufferedWriter.Writer) anyerror!void {
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

   const pixels_raw = try _readPixelDataAlloc(allocator, input, &header); 
   defer allocator.free(pixels_raw);

   const pixels_final = try _convertOffsetColorspace(allocator, pixels_raw, &header);
   defer allocator.free(pixels_final);

   try _writeDecodedImageToZigSource(output, pixels_final, header.image_spec.width, header.image_spec.height);

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
      pixel_depth : u8,
      descriptor  : u8,

      pub fn bytesPerPixel(self : * const @This()) u5 {
         return @intCast(std.math.divCeil(u8, self.pixel_depth, 8) catch unreachable);
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
      const image_spec_pixel_depth     = try reader.readInt(u8,   TARGA_ENDIANESS);
      const image_spec_descriptor      = try reader.readInt(u8,   TARGA_ENDIANESS);

      const color_map_type = std.meta.intToEnum(@This().ColorMapType, color_map_type_tag)                            catch return error.UnsupportedColorMapType;
      const image_type     = std.meta.intToEnum(@This().ImageType, image_type_tag)                                   catch return error.UnsupportedImageType;

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

fn _readPixelDataAlloc(allocator : std.mem.Allocator, reader : * _BufferedReader.Reader, header : * const TargaHeader) anyerror![] const u8 {
   const pixels = try allocator.alloc(u8, header.image_spec.bytes());
   errdefer allocator.free(pixels);

   const pfn_read_pixel_data : * const fn(* _BufferedReader.Reader, [] u8, * const TargaHeader) anyerror!void = blk: {
      switch (header.color_map_type) {
         .none          => break :blk _readPixelDataUnmapped,
         .colormapped   => break :blk _readPixelDataColormapped,
      }
   };

   try pfn_read_pixel_data(reader, pixels, header);

   return pixels;
}

fn _readPixelDataUnmapped(reader : * _BufferedReader.Reader, buffer : [] u8, header : * const TargaHeader) anyerror!void {
   // Since our I/O is already buffered, we don't need additional buffering on
   // top.  This is why our buffer size is 1.
   try reader.skipBytes(header.color_map_spec.bytes(), .{.buf_size = 1});

   switch (header.image_type.isCompressed()) {
      true  => try _readPixelDataCompressed(reader, buffer, header),
      false => try _readPixelDataUncompressed(reader, buffer),
   }
   
   return;
}

fn _readPixelDataCompressed(reader : * _BufferedReader.Reader, buffer : [] u8, header : * const TargaHeader) anyerror!void {
   const bytes_per_packet  = header.image_spec.bytesPerPixel();
   const expected_packets  = header.image_spec.pixels();
   return _decodeCompressedPackets(reader, buffer, bytes_per_packet, expected_packets);
}

fn _readPixelDataUncompressed(reader : * _BufferedReader.Reader, buffer : [] u8) anyerror!void {
   const read_count = try reader.readAtLeast(buffer, buffer.len);
   if (read_count != buffer.len) {
      return error.ImageDataTruncated;
   }

   return;
}

fn _readPixelDataColormapped(reader : * _BufferedReader.Reader, buffer : [] u8, header : * const TargaHeader) anyerror!void {
   // TODO: Implement
   _ = reader;
   _ = buffer;
   _ = header;
   return error.ColorMappingNotImplemented;
}

fn _decodeCompressedPackets(reader : * _BufferedReader.Reader, buffer : [] u8, bytes_per_packet : usize, packets_expected : usize) anyerror!void {
   var packets_decoded : usize = 0;
   while (packets_decoded < packets_expected) {
      const count_packet = try reader.readByte();

      // The MSB states whether this signifies a single pixel being repeated
      // or a collection of uncompressed pixels.  The actual count is the lowest
      // 7 bits plus 1, so its in the range 1-128
      const COMPRESSION_BIT   = @as(u8, 1) << 7;
      const is_compressed     = count_packet & COMPRESSION_BIT != 0;
      const count             = (count_packet & ~COMPRESSION_BIT) + 1;

      const buffer_decode = buffer[packets_decoded * bytes_per_packet..][0..count * bytes_per_packet];

      switch (is_compressed) {
         true  => try _decodePacketCompressed(reader, buffer_decode, count, bytes_per_packet),
         false => try _decodePacketUncompressed(reader, buffer_decode, count, bytes_per_packet),
      }

      packets_decoded += count;
   }

   if (packets_decoded != packets_expected) {
      return error.ImageDataCorrupt;
   }

   return;
}

fn _decodePacketCompressed(reader : * _BufferedReader.Reader, buffer : [] u8, count : u8, bytes_per_packet : usize) anyerror!void {
   const bytes_to_read = bytes_per_packet;

   const read_count = try reader.readAtLeast(buffer[0..bytes_to_read], bytes_to_read);
   if (read_count != bytes_to_read) {
      return error.ImageDataTruncated;
   }

   for (1..count) |i| {
      @memcpy(buffer[bytes_per_packet * i..][0..bytes_per_packet], buffer[0..bytes_per_packet]);
   }

   return;
}

fn _decodePacketUncompressed(reader : * _BufferedReader.Reader, buffer : [] u8, count : u8, bytes_per_packet : usize) anyerror!void {
   const bytes_to_read = count * bytes_per_packet;

   const read_count = try reader.readAtLeast(buffer[0..bytes_to_read], bytes_to_read);
   if (read_count != bytes_to_read) {
      return error.ImageDataTruncated;
   }

   return;
}

fn _convertOffsetColorspace(allocator : std.mem.Allocator, pixels_raw : [] const u8, header : * const TargaHeader) anyerror![] const u8 {
   const pixels_final = try allocator.alloc(u8, header.image_spec.pixels() * BYTES_PER_PIXEL_RGBA8888);
   errdefer allocator.free(pixels_final);

   // TODO: Add support for more pixel formats.
   const pfn_convert : * const fn ([] const u8, [] u8, * const TargaHeader) void = blk: {
      switch (header.image_type) {
         .monochrome, .monochrome_compressed => switch (header.image_spec.pixel_depth) {
            8     => break :blk _convertOffsetColorspaceGrayscale8,
            else  => return error.UnsupportedPixelFormat,
         },
         else => switch (header.image_spec.pixel_depth) {
            24    => break :blk _convertOffsetColorspaceBgr888,
            32    => break :blk _convertOffsetColorspaceBgra8888,
            else  => return error.UnsupportedPixelFormat,
         },
      }
   };
   
   pfn_convert(pixels_raw, pixels_final, header);

   return pixels_final;
}

fn _convertOffsetColorspaceGrayscale8(buffer_src : [] const u8, buffer_dst : [] u8, header : * const TargaHeader) void {
   return _convertOffsetColorspaceGeneric(
      1,
      _convertPixelFromGrayscale8,
      buffer_src,
      buffer_dst,
      header,
   );
}

fn _convertPixelFromGrayscale8(pixel : @Vector(1, u8)) @Vector(BYTES_PER_PIXEL_RGBA8888, u8) {
   return .{pixel[0], pixel[0], pixel[0], std.math.maxInt(u8)};
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

