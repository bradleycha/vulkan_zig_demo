const std      = @import("std");
const graphics = @import("graphics");

pub fn parseWavefrontComptime(comptime reader : * std.io.FixedBufferStream([] const u8).Reader) anyerror!graphics.types.Mesh {
   _ = reader;
   return error.NotImplemented;
}

