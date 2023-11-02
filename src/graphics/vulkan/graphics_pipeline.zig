const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const ShaderSource = struct {
   bytecode          : [] align(@sizeOf(u32)) const u8,
   entrypoint        : [*:0] const u8,
};

