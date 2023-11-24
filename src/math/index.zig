pub usingnamespace @import("linear_algebra.zig");

pub fn alignForward(comptime T : type, value : T, alignment : T) T {
   return value + alignment - @rem(value, alignment);
}

