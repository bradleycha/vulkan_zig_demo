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

pub fn Vector2(comptime ty : type) type {
   return packed union {
      vector   : @Vector(2, ty),
      xy       : Xy,
      uv       : Uv,
      st       : St,

      pub const Xy = packed struct {
         x : ty,
         y : ty,
      };

      pub const Uv = packed struct {
         u : ty,
         v : ty,
      };

      pub const St = packed struct {
         s : ty,
         t : ty,
      };
   };
}

pub fn Vector3(comptime ty : type) type {
   return packed union {
      vector   : @Vector(3, ty),
      xyz      : Xyz,

      pub const Xyz = packed struct {
         x : ty,
         y : ty,
         z : ty,
      };
   };
}

pub fn Vector4(comptime ty : type) type {
   return packed union {
      vector   : @Vector(4, ty),
      xyzw     : Xyzw,

      pub const Xyzw = packed struct {
         x : ty,
         y : ty,
         z : ty,
         w : ty,
      };
   };
}

pub fn Matrix4(comptime ty : type) type {
   return packed struct {
      items : @Vector(16, ty),
   };
}

pub const Vertex = packed struct {
   // We order the fields in this strange way to ensure we can get proper
   // field alignment without any padding.  It's like a game of Tetris!
   color    : Color.Rgba(f32),   // 16 bytes | offset +0
   sample   : Vector2(f32),      // 8 bytes  | offset +16
   position : Vector3(f32),      // 12 bytes | offset +24
   
   pub const INFO = struct {
      pub const Count = @typeInfo(Vertex).Struct.fields.len;
      pub const Index = struct {
         pub const Color      = 0;
         pub const Sample     = 1;
         pub const Position   = 2;
      };
   };
};

pub const Mesh = struct {
   vertices : [] const Vertex,
   indices  : [] const IndexElement,

   pub const IndexElement = u16;
};

pub const PushConstants = packed struct {
   transform   : Matrix4(f32),   // 64 bytes
};

