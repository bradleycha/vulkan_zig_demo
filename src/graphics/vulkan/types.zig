const root  = @import("index.zig");
const std   = @import("std");
const math  = @import("math");
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

pub const Vertex = packed struct {
   // We order the fields in this strange way to ensure we can get proper
   // field alignment without any padding.  It's like a game of Tetris!
   color    : Color.Rgba(f32),   // 16 bytes | offset +0
   sample   : math.Vector2(f32), // 8 bytes  | offset +16
   position : math.Vector3(f32), // 12 bytes | offset +24
   normal   : math.Vector3(f32), // 12 bytes | offset +36
   
   pub const INFO = struct {
      pub const Count = @typeInfo(Vertex).Struct.fields.len;
      pub const Index = struct {
         pub const Color      = 0;
         pub const Sample     = 1;
         pub const Position   = 2;
         pub const Normal     = 3;
      };
   };
};

pub const Mesh = struct {
   vertices : [] const Vertex,
   indices  : [] const IndexElement,

   pub const IndexElement = u16;
};

pub const PushConstants = struct {
   transform_mesh : math.Matrix4(f32), // 64 bytes   | offset +0
};

pub const UniformBufferObject = struct {
   transform_view_projection : math.Matrix4(f32), // 0 bytes | offset +0
};

