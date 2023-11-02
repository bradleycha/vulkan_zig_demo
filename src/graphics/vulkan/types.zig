const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

// Most of these types use packed unions for two reasons.  First is to allow
// multiple ways of addressing the same underlying data.  For example, we can
// store a Vec2 with fields X/Y in the same container as a Vec2 with fields S/T
// or U/V.  It basically cuts down on duplicate types.  Second reason is to
// allow SIMD optimizations using @Vector() types without sacrificing on
// syntactic sugar.

pub const Color = struct {
   pub fn Rgba(comptime ty : type) type {
      return packed union {
         vector   : @Vector(4, ty),
         channels : Channels,

         pub const Channels = packed struct {
            r : ty,
            g : ty,
            b : ty,
            a : ty,
         };
      };
   }
};

