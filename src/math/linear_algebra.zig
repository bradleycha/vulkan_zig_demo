const std = @import("std");

pub fn Vector2(comptime ty : type) type {
   const COMPONENTS = 2;

   return packed union {
      vector   : @Vector(COMPONENTS, ty),
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

      pub const ZERO = @This(){.vector = @splat(0)};
      pub const ONE  = @This(){.vector = @splat(1)};

      pub fn dotProduct(lhs : * const @This(), rhs : * const @This()) ty {
         return _vectorDotProductGeneric(COMPONENTS, ty, &lhs.vector, &rhs.vector);
      }

      pub fn magnitudeSquare(self : * const @This()) ty {
         return _vectorMagnitudeSquareGeneric(COMPONENTS, ty, &self.vector);
      }

      pub fn magnitude(self : * const @This()) ty {
         return _vectorMagnitudeGeneric(COMPONENTS, ty, &self.vector);
      }

      pub fn normalize(self : * const @This()) @This() {
         return .{.vector = _vectorNormalizeGeneric(COMPONENTS, ty, &self.vector)};
      }

      pub fn normalizeZero(self : * const @This()) @This() {
         return .{.vector = _vectorNormalizeZeroGeneric(COMPONENTS, ty, &self.vector)};
      }
   };
}

pub fn Vector3(comptime ty : type) type {
   const COMPONENTS = 3;

   return packed union {
      vector   : @Vector(COMPONENTS, ty),
      xyz      : Xyz,
      angles   : Angles,

      pub const Xyz = packed struct {
         x : ty,
         y : ty,
         z : ty,
      };

      pub const Angles = packed struct {
         pitch : ty,
         yaw   : ty,
         roll  : ty,
      };

      pub const ZERO = @This(){.vector = @splat(0)};
      pub const ONE  = @This(){.vector = @splat(1)};

      pub fn dotProduct(lhs : * const @This(), rhs : * const @This()) ty {
         return _vectorDotProductGeneric(COMPONENTS, ty, &lhs.vector, &rhs.vector);
      }

      pub fn magnitudeSquare(self : * const @This()) ty {
         return _vectorMagnitudeSquareGeneric(COMPONENTS, ty, &self.vector);
      }

      pub fn magnitude(self : * const @This()) ty {
         return _vectorMagnitudeGeneric(COMPONENTS, ty, &self.vector);
      }

      pub fn normalize(self : * const @This()) @This() {
         return .{.vector = _vectorNormalizeGeneric(COMPONENTS, ty, &self.vector)};
      }

      pub fn normalizeZero(self : * const @This()) @This() {
         return .{.vector = _vectorNormalizeZeroGeneric(COMPONENTS, ty, &self.vector)};
      }
   };
}

pub fn Vector4(comptime ty : type) type {
   const COMPONENTS = 4;
   
   return packed union {
      vector   : @Vector(COMPONENTS, ty),
      xyzw     : Xyzw,

      pub const Xyzw = packed struct {
         x : ty,
         y : ty,
         z : ty,
         w : ty,
      };

      pub const ZERO = @This(){.vector = @splat(0)};
      pub const ONE  = @This(){.vector = @splat(1)};

      pub fn dotProduct(lhs : * const @This(), rhs : * const @This()) ty {
         return _vectorDotProductGeneric(COMPONENTS, ty, &lhs.vector, &rhs.vector);
      }

      pub fn magnitudeSquare(self : * const @This()) ty {
         return _vectorMagnitudeSquareGeneric(COMPONENTS, ty, &self.vector);
      }

      pub fn magnitude(self : * const @This()) ty {
         return _vectorMagnitudeGeneric(COMPONENTS, ty, &self.vector);
      }

      pub fn normalize(self : * const @This()) @This() {
         return .{.vector = _vectorNormalizeGeneric(COMPONENTS, ty, &self.vector)};
      }

      pub fn normalizeZero(self : * const @This()) @This() {
         return .{.vector = _vectorNormalizeZeroGeneric(COMPONENTS, ty, &self.vector)};
      }
   };
}

fn _vectorDotProductGeneric(
   comptime components  : comptime_int,
   comptime ty          : type,
   lhs_vector           : * const @Vector(components, ty),
   rhs_vector           : * const @Vector(components, ty),
) ty {
   const multiply    = lhs_vector.* * rhs_vector.*;
   const dot_product = @reduce(.Add, multiply);

   return dot_product;
}

fn _vectorMagnitudeSquareGeneric(
   comptime components  : comptime_int,
   comptime ty          : type,
   vector               : * const @Vector(components, ty),
) ty {
   return _vectorDotProductGeneric(components, ty, vector, vector);
}

fn _vectorMagnitudeGeneric(
   comptime components  : comptime_int,
   comptime ty          : type,
   vector               : * const @Vector(components, ty),
) ty {
   const magnitude_square  = _vectorMagnitudeSquareGeneric(components, ty, vector);
   const magnitude         = @sqrt(magnitude_square);

   return magnitude;
}

fn _vectorNormalizeGeneric(
   comptime components  : comptime_int,
   comptime ty          : type,
   vector               : * const @Vector(components, ty),
) @Vector(components, ty) {
   const magnitude   = _vectorMagnitudeGeneric(components, ty, vector);

   if (std.debug.runtime_safety == true and magnitude == 0) {
      @panic("attempted to normalize vector with length zero, if intended use normalizeZero()");
   }

   const reciprocal  = 1 / magnitude;
   const multiplier  = @as(@Vector(components, ty), @splat(reciprocal));
   const normalized  = multiplier * vector.*;

   return normalized;
}

fn _vectorNormalizeZeroGeneric(
   comptime components  : comptime_int,
   comptime ty          : type,
   vector               : * const @Vector(components, ty),
) @Vector(components, ty) {
   const magnitude   = _vectorMagnitudeGeneric(components, ty, vector);
   
   if (magnitude == 0) {
      return @splat(0);
   }

   const reciprocal  = 1 / magnitude;
   const multiplier  = @as(@Vector(components, ty), @splat(reciprocal));
   const normalized  = multiplier * vector.*;

   return normalized;
}

// TODO - Refactor below, make more generic like above

pub fn Matrix4(comptime ty : type) type {
   return struct {
      items : [4] @Vector(4, ty),

      pub const ZERO = @This(){.items = .{
         [4] ty {0, 0, 0, 0},
         [4] ty {0, 0, 0, 0},
         [4] ty {0, 0, 0, 0},
         [4] ty {0, 0, 0, 0},
      }};

      pub const IDENTITY = @This(){.items = .{
         [4] ty {1, 0, 0, 0},
         [4] ty {0, 1, 0, 0},
         [4] ty {0, 0, 1, 0},
         [4] ty {0, 0, 0, 1},
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

      pub fn createRotation(angles : * const Vector3(ty)) @This() {
         const sx = std.math.sin(angles.angles.pitch);
         const cx = std.math.cos(angles.angles.pitch);
         const sy = std.math.sin(angles.angles.yaw);
         const cy = std.math.cos(angles.angles.yaw);
         const sz = std.math.sin(angles.angles.roll);
         const cz = std.math.cos(angles.angles.roll);

         return .{.items = .{
            [4] ty {cy * cz, sx * sy * cz - cx * sz, cx * sy * cz + sx * sz, 0.0},
            [4] ty {cy * sz, sx * sy * sz + cx * cz, cx * sy * sz - sx * cz, 0.0},
            [4] ty {-1.0 * sy, sx * cy, cx * cy, 0.0},
            [4] ty {0.0, 0.0, 0.0, 1.0},
         }};
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
         mtx.items[1][1] = -1.0 * cot;
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

pub fn Transform(comptime ty : type) type {
   return struct {
      translation : Vector3(ty),
      rotation    : Vector3(ty),
      scale       : Vector3(ty),

      pub fn toMatrix(self : * const @This()) Matrix4(ty) {
         const mtx_translate  = Matrix4(f32).createTranslation(&self.translation);
         const mtx_rotate     = Matrix4(f32).createRotation(&self.rotation);
         const mtx_scale      = Matrix4(f32).createScale(&self.scale);

         return mtx_translate.multiplyMatrix(&mtx_rotate.multiplyMatrix(&mtx_scale));
      }
   };
}

