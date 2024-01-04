const std      = @import("std");
const graphics = @import("graphics");

pub fn parseWavefrontComptime(comptime reader_obj : * std.io.FixedBufferStream([] const u8).Reader, comptime reader_mtl : * std.io.FixedBufferStream([] const u8).Reader) anyerror!graphics.types.Mesh {
   _ = reader_obj;
   _ = reader_mtl;
   return error.NotImplemented;
}

