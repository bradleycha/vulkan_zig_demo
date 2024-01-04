const std      = @import("std");
const math     = @import("math");
const graphics = @import("graphics");

pub const TILE    = _embedTarga("tile.tga");
pub const GRASS   = _embedTarga("grass.tga");
pub const ROCK    = _embedTarga("rock.tga");

// Yes, I wrote an entire targa image parser using comptime just to make my
// program work since I'm too good for abstraction and others' code.

const ENDIANESS = std.builtin.Endian.Little;

fn _embedTarga(comptime path : [] const u8) graphics.ImageSource {
   // My man, Andrew...I understand the purpose of limiting comptime execution,
   // but this kind of sucks.  I'd prefer if I could simply disable comptime
   // execution limits temporarily instead of finding some random magical value
   // which doesn't kill compilation.
   @setEvalBranchQuota(10000);

   const bytes = @embedFile(path);
   
   var stream = std.io.FixedBufferStream([] const u8){.buffer = bytes, .pos = 0};
   var reader = stream.reader();

   const image_source = _parseTarga(&reader) catch |err| {
      @compileError(std.fmt.comptimePrint("failed to parse image \'{s}\': {s}", .{path, @errorName(err)}));
   };

   return image_source;
}

fn _parseTarga(comptime reader : * std.io.FixedBufferStream([] const u8).Reader) anyerror!graphics.ImageSource {
   const header = try TargaHeader.parseFromStream(reader);

   // Skip past the Image ID field.
   try reader.skipBytes(header.image_id_length, .{});

   // For now we don't care to parse monochrome or color-mapped images since
   // we don't live in 1984 and they're much less common.
   switch (header.image_type) {
      .truecolor,
      .truecolor_compressed => {},
      else => return error.UnsupportedImageType,
   }

   // TODO: We shouldn't need these guards.  Implement these features.
   if (header.image_spec.pixel_depth != 32) {
      return error.UnimplementedImagePixelDepth;
   }
   if (header.image_spec.x_offset != 0 or header.image_spec.y_offset != 0) {
      return error.UnimplementedImagePixelOffset;
   }

   // Skip past the color map field, if present.
   // TODO: Actually handle color-mapped data.
   try reader.skipBytes(header.color_map_spec.bytes(), .{});

   // Read in the raw image data, decompressing if needed.
   var image_data : [header.image_spec.bytes()] u8 = undefined;
   switch (header.image_type.isCompressed()) {
      true  => {
         var expected_pixels     = header.image_spec.width * header.image_spec.height;
         var image_data_stream   = std.io.FixedBufferStream([] u8){.buffer = &image_data, .pos = 0};
         var image_data_writer   = image_data_stream.writer();
         try _decompressImageData(reader, &image_data_writer, expected_pixels, header.image_spec.pixel_depth);
      },
      false => {
         _ = try reader.readAtLeast(&image_data, image_data.len);
      },
   }

   // TODO: Perform color format conversion to RGBA8888 here.  Since right now
   // we are only allowing 32-bit truecolor, we can directly use the decompressed
   // image data for our ImageSource.


   // TODO: Apply image offsets.


   // Return the parsed image.
   return graphics.ImageSource{
      .data    = &image_data,
      .format  = .rgba8888,
      .width   = header.image_spec.width,
      .height  = header.image_spec.height,
   };
}

const TargaHeader = packed struct {
   image_id_length   : u8,
   color_map_type    : ColorMapType,
   image_type        : ImageType,
   color_map_spec    : ColorMapSpecification,
   image_spec        : ImageSpecification,

   pub const ColorMapType = enum(u8) {
      none     = 0,
      included = 1,
   };

   pub const ImageType = enum(u8) {
      none                    = 0,
      colormapped             = 1,
      truecolor               = 2,
      monochrome              = 3,
      colormapped_compressed  = 9,
      truecolor_compressed    = 10,
      monochrome_compressed   = 11,

      pub fn isCompressed(comptime self : @This()) bool {
         return @intFromEnum(self) >= 9;
      }
   };

   pub const ColorMapSpecification = packed struct {
      offset   : u16,
      length   : u16,
      depth    : u8,

      pub fn bytes(comptime self : @This()) comptime_int {
         const bits = self.length * self.depth;
         return std.math.divCeil(comptime_int, bits, 8) catch unreachable;
      }
   };

   pub const ImageSpecification = packed struct {
      x_offset    : u16,
      y_offset    : u16,
      width       : u16,
      height      : u16,
      pixel_depth : u8,
      descriptor  : u8,

      pub fn bytes(comptime self : @This()) comptime_int {
         const pixels            = self.width * self.height;
         const bytes_per_pixel   = std.math.divCeil(comptime_int, self.pixel_depth, 8) catch unreachable;
         return pixels * bytes_per_pixel;
      }
   };

   pub fn parseFromStream(comptime reader : * std.io.FixedBufferStream([] const u8).Reader) anyerror!@This() {
      const image_id_length         = try reader.readInt(u8, ENDIANESS);
      const color_map_type_tag      = try reader.readInt(u8, ENDIANESS);
      const image_type_tag          = try reader.readInt(u8, ENDIANESS);
      const color_map_spec_offset   = try reader.readInt(u16, ENDIANESS);
      const color_map_spec_length   = try reader.readInt(u16, ENDIANESS);
      const color_map_spec_depth    = try reader.readInt(u8, ENDIANESS);
      const image_spec_x_offset     = try reader.readInt(u16, ENDIANESS);
      const image_spec_y_offset     = try reader.readInt(u16, ENDIANESS);
      const image_spec_width        = try reader.readInt(u16, ENDIANESS);
      const image_spec_height       = try reader.readInt(u16, ENDIANESS);
      const image_spec_pixel_depth  = try reader.readInt(u8, ENDIANESS);
      const image_spec_descriptor   = try reader.readInt(u8, ENDIANESS);

      const color_map_type = std.meta.intToEnum(ColorMapType, color_map_type_tag) catch return error.UnsupportedColorMapType;
      const image_type     = std.meta.intToEnum(ImageType, image_type_tag) catch return error.UnsupportedImageType;

      return @This(){
         .image_id_length  = image_id_length,
         .color_map_type   = color_map_type,
         .image_type       = image_type,
         .color_map_spec   = .{
            .offset  = color_map_spec_offset,
            .length  = color_map_spec_length,
            .depth   = color_map_spec_depth,
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
   }
};

fn _decompressImageData(comptime reader : * std.io.FixedBufferStream([] const u8).Reader, comptime writer : * std.io.FixedBufferStream([] u8).Writer, comptime expected_pixels : comptime_int, comptime bits_per_pixel : comptime_int) anyerror!void {
   const bytes_per_pixel = std.math.divCeil(comptime_int, bits_per_pixel, 8) catch unreachable;

   var decompressed_pixels : comptime_int = 0;
   while (decompressed_pixels < expected_pixels) {
      const raw_count = try reader.readInt(u8, ENDIANESS) + 1;

      // The actual pixels count is a 7-bit integer.  The 8th bit is a flag for
      // whether the following data is a single run-length encoded pixel or many
      // raw pixels.
      const RLE_BIT  = @as(u8, 1) << 7;
      const is_rle   = raw_count & RLE_BIT != 0;
      const count    = raw_count & ~RLE_BIT;

      switch (is_rle) {
         true  => try _decompressRunLengthPixel(reader, writer, bytes_per_pixel, count),
         false => try _decompressRawPixels(reader, writer, bytes_per_pixel, count),
      }

      decompressed_pixels += @as(comptime_int, count);
   }

   // If we decompressed more pixels than expected, the only reason is because
   // our compressed image data is malformed.
   if (decompressed_pixels > expected_pixels) {
      return error.MalformedImageData;
   }

   return;
}

fn _decompressRunLengthPixel(comptime reader : * std.io.FixedBufferStream([] const u8).Reader, comptime writer : * std.io.FixedBufferStream([] u8).Writer, comptime bytes_per_pixel : comptime_int, comptime pixels : comptime_int) anyerror!void {
   var read_buffer : [bytes_per_pixel] u8 = undefined;
   _ = try reader.readAtLeast(&read_buffer, read_buffer.len);

   for (0..pixels) |_| {
      try writer.writeAll(&read_buffer);
   }

   return;
}

fn _decompressRawPixels(comptime reader : * std.io.FixedBufferStream([] const u8).Reader, comptime writer : * std.io.FixedBufferStream([] u8).Writer, comptime bytes_per_pixel : comptime_int, comptime pixels : comptime_int) anyerror!void {
   var read_buffer : [bytes_per_pixel * pixels] u8 = undefined;
   _ = try reader.readAtLeast(&read_buffer, read_buffer.len);

   try writer.writeAll(&read_buffer);

   return;
}

