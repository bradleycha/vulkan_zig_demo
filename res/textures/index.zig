const std      = @import("std");
const graphics = @import("graphics");
const parser   = @import("parser");

pub const TILE    = _embedTarga("tile.tga");
pub const GRASS   = _embedTarga("grass.tga");
pub const ROCK    = _embedTarga("rock.tga");

fn _embedTarga(comptime path : [] const u8) graphics.ImageSource {
   @setEvalBranchQuota(10000); // :(

   const bytes = @embedFile(path);
   
   var stream = std.io.FixedBufferStream([] const u8){.buffer = bytes, .pos = 0};
   var reader = stream.reader();

   const image_source = parser.targa.parseTargaComptime(&reader) catch |err| {
      @compileError(std.fmt.comptimePrint("failed to parse image \'{s}\': {s}", .{path, @errorName(err)}));
   };

   return image_source;
}

