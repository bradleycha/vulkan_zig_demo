const std      = @import("std");
const math     = @import("math");
const graphics = @import("graphics");

pub fn parseWavefrontComptime(comptime obj : [] const u8, comptime mtl : [] const u8) anyerror!graphics.types.Mesh {
   _ = obj;
   _ = mtl;
   return error.NotImplemented;
}

