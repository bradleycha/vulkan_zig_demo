const std = @import("std");

pub const Color = struct {
   pub fn Rgba(comptime ty : type) type {
      return packed struct {
         r : ty,
         g : ty,
         b : ty,
         a : ty,
      };
   }
};

pub fn Vector2(comptime ty : type) type {
   return packed union {
      vec   : @Vector(2, ty),
      xy    : Format.Xy,
      uv    : Format.Uv,
      st    : Format.St,

      pub const Format = struct {
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
   };
}

pub fn Vector3(comptime ty : type) type {
   return packed union {
      vec   : @Vector(3, ty),
      xyz   : Format.Xyz,
      ypr   : Format.Ypr,

      pub const Format = struct {
         pub const Xyz = packed struct {
            x : ty,
            y : ty,
            z : ty,
         };

         pub const Ypr = packed struct {
            y : ty,
            p : ty,
            r : ty,
         };
      };
   };
}

pub fn Vector4(comptime ty : type) type {
   return packed union {
      vec   : @Vector(4, ty),
      xyzw  : Format.Xyzw,

      pub const Format = struct {
         pub const Xyzw = packed struct {
            x : ty,
            y : ty,
            z : ty,
            w : ty,
         };
      };
   };
}

pub const Vertex = struct {
   color    : Color.Rgba(f32),
   sample   : Vector2(f32),
   position : Vector3(f32),
};

