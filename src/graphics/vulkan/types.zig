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
   return struct {
      items : [4] @Vector(4, ty),

      pub const IDENTITY = @This(){.items = .{
         [4] ty {1, 0, 0, 0},
         [4] ty {0, 1, 0, 0},
         [4] ty {0, 0, 1, 0},
         [4] ty {0, 0, 0, 1},
      }};

      pub const ZERO = @This(){.items = .{
         [4] ty {0, 0, 0, 0},
         [4] ty {0, 0, 0, 0},
         [4] ty {0, 0, 0, 0},
         [4] ty {0, 0, 0, 0},
      }};

      pub fn createTranslation(value : * const Vector3(ty)) @This() {
         var mtx = @This().IDENTITY;

         mtx.items[3][0] = value.vector[0];
         mtx.items[3][1] = value.vector[1];
         mtx.items[3][2] = value.vector[2];
         
         return mtx;
      }

      pub fn createScale(value : * const Vector3(ty)) @This() {
         var mtx = @This().IDENTITY;

         mtx.items[0][0] = value.vector[0];
         mtx.items[1][1] = value.vector[1];
         mtx.items[2][2] = value.vector[2];

         return mtx;
      }

      pub fn createRotationX(theta : ty) @This() {
         var mtx = @This().IDENTITY;

         const sin = @sin(theta);
         const cos = @cos(theta);

         mtx.items[1][1] = cos;
         mtx.items[1][2] = sin;
         mtx.items[2][1] = sin * -1.0;
         mtx.items[2][2] = cos;

         return mtx;
      }

      pub fn createRotationY(theta : ty) @This() {
         var mtx = @This().IDENTITY;

         const sin = @sin(theta);
         const cos = @cos(theta);

         mtx.items[0][0] = cos;
         mtx.items[0][2] = sin * -1.0;
         mtx.items[2][0] = sin;
         mtx.items[2][2] = cos;

         return mtx;
      }

      pub fn createRotationZ(theta : ty) @This() {
         var mtx = @This().IDENTITY;

         const sin = @sin(theta);
         const cos = @cos(theta);

         mtx.items[0][0] = cos;
         mtx.items[0][1] = sin;
         mtx.items[1][0] = sin * -1.0;
         mtx.items[1][1] = cos;
         mtx.items[2][2] = 0.0;

         return mtx;
      }

      pub fn createPerspectiveProjection(width : u32, height : u32, near_plane : f32, far_plane : f32, field_of_view : f32) @This() {
         if (width == 0 or height == 0) {
            return @This().ZERO;
         }

         const ratio = @as(f32, @floatFromInt(height)) / @as(f32, @floatFromInt(width));
         const rpdif = 1.0 / (near_plane - far_plane);
         const cot   = 1.0 / @tan(field_of_view * std.math.pi / 360.0);

         var mtx = @This().ZERO;
         mtx.items[0][0] = ratio * cot;
         mtx.items[1][1] = cot;
         mtx.items[2][2] = (near_plane + far_plane) * rpdif;
         mtx.items[3][2] = 2.0 * far_plane * near_plane * rpdif;
         mtx.items[2][3] = -1.0;

         return mtx;
      }

      pub fn multiplyVector(self : * const @This(), rhs : * const Vector4(ty)) Vector4(ty) {
         return .{.vector = _multiplyVectorRaw(&self.items, &rhs.vector)};
      }

      pub fn multiplyMatrix(self : * const @This(), rhs : * const @This()) @This() {
         return .{.items = _multiplyMatrixRaw(&self.items, &rhs.items)};
      }

      fn _multiplyVectorRaw(lhs_matrix : * const [4] @Vector(4, ty), rhs_vector : * const @Vector(4, ty)) @Vector(4, ty) {
         var result_vector : @Vector(4, ty) = .{0, 0, 0, 0};

         for (0..4) |i| {
            const multiply : @Vector(4, ty) = @splat(rhs_vector[i]);
            const column   : @Vector(4, ty) = lhs_matrix[i];

            result_vector += multiply * column;
         }

         return result_vector;
      }

      fn _multiplyMatrixRaw(lhs_matrix : * const [4] @Vector(4, ty), rhs_matrix : * const [4] @Vector(4, ty)) [4] @Vector(4, ty) {
         var result_matrix : [4] @Vector(4, ty) = undefined;

         for (0..4) |i| {
            const vector = &rhs_matrix[i];
            const column = _multiplyVectorRaw(lhs_matrix, vector);

            result_matrix[i] = column;
         }

         return result_matrix;
      }
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

pub const PushConstants = struct {
   transform_mesh : Matrix4(f32), // 64 bytes   | offset +0
};

pub const UniformBufferObject = struct {
   transform_camera     : Matrix4(f32),   // 64 bytes | offset +0
   transform_projection : Matrix4(f32),   // 64 bytes | offset +64
};

