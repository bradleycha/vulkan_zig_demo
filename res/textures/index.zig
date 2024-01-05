const std      = @import("std");
const graphics = @import("graphics");

// TODO: Instead of directly including raw image data, use comptime to parse
// some normal format like bmp, png, etc. into raw image data.

pub const TILE = graphics.ImageSource{
   .data    = @embedFile("tile.raw"),
   .format  = .rgba8888,
   .width   = 32,
   .height  = 32,
};

pub const GRASS = graphics.ImageSource{
   .data    = @embedFile("grass.raw"),
   .format  = .rgba8888,
   .width   = 32,
   .height  = 32,
};

pub const ROCK = graphics.ImageSource{
   .data    = @embedFile("rock.raw"),
   .format  = .rgba8888,
   .width   = 32,
   .height  = 32,
};

// Verifies the byte lengths for every image source in the file.  This may seem
// annoying when compilation fails, but it will save you from mystery crashes
// and memory corruption at runtime.
comptime {
   const decls = @typeInfo(@This()).Struct.decls;

   for (decls) |decl| {
      const value = @field(@This(), decl.name);

      if (std.mem.eql(u8, @typeName(@TypeOf(value)), @typeName(graphics.ImageSource)) == false) {
         continue;
      }

      _verifyTextureDataLength(decl.name, &value);
   }
}

fn _verifyTextureDataLength(comptime identifier : [] const u8, comptime source : * const graphics.ImageSource) void {
   const expected_bytes = source.width * source.height * source.format.bytesPerPixel();
   const found_bytes   = source.data.len;

   if (expected_bytes != found_bytes) {
      @compileError(std.fmt.comptimePrint("expected {} bytes of data for image source \'{s}\', instead found {} bytes", .{expected_bytes, identifier, found_bytes}));
   }

   return;
}

