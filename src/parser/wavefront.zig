const std      = @import("std");
const math     = @import("math");
const graphics = @import("graphics");

pub fn parseWavefrontComptime(comptime bytes_obj : [] const u8) anyerror!graphics.types.Mesh {
   @setEvalBranchQuota(999999); // :(

   const obj = try ObjItemList.deserialize(bytes_obj);

   // TODO: Implement rest
   _ = obj;
   return error.NotImplemented;
}

const ObjItemTag = enum {
   comment,
   vertex,
   parameter_space_vertex,
   texture_coordinate,
   normal,
   face,
   line,
   material,
   material_library,
   surface_shading,
   object_name,
   group_name,

   pub const Face = struct {
      material : [] const u8,
      indices  : [] const @This().Index,

      pub const Index = struct {
         vertex               : usize,
         texture_coordinate   : ? usize,
         normal               : ? usize,
      };
   };
};

const ObjItemList = struct {
   vertices             : [] const math.Vector4(f32),
   texture_coordinates  : [] const math.Vector3(f32),
   normals              : [] const math.Vector3(f32),
   faces                : [] const ObjItemTag.Face,

   pub fn deserialize(comptime text : [] const u8) anyerror!@This() {
      var items = @This(){
         .vertices            = &.{},
         .texture_coordinates = &.{},
         .normals             = &.{},
         .faces               = &.{},
      };

      var current_material : [] const u8  = "";
      var lines = std.mem.splitScalar(u8, text, '\n');
      while (lines.next()) |line| {
         const line_trimmed = std.mem.trim(u8, line, &.{' '});
         if (line_trimmed.len == 0) {
            continue;
         }

         try _deserializeLine(&items, line_trimmed, &current_material);
      }

      return items;
   }

   fn _deserializeLine(comptime self : * @This(), comptime line : [] const u8, comptime current_material : * [] const u8) anyerror!void {
      var tokens = std.mem.splitScalar(u8, line, ' ');

      const element = tokens.next() orelse return error.MissingElementType;

      const TOKEN_MAP = [_] struct {
         tag   : ObjItemTag,
         token : [] const u8,
      } {
         .{.tag = .comment,                  .token = "#"},
         .{.tag = .vertex,                   .token = "v"},
         .{.tag = .parameter_space_vertex,   .token = "vp"},
         .{.tag = .texture_coordinate,       .token = "vt"},
         .{.tag = .normal,                   .token = "vn"},
         .{.tag = .face,                     .token = "f"},
         .{.tag = .line,                     .token = "l"},
         .{.tag = .material,                 .token = "usemtl"},
         .{.tag = .material_library,         .token = "mtllib"},
         .{.tag = .surface_shading,          .token = "s"},
         .{.tag = .object_name,              .token = "o"},
         .{.tag = .group_name,               .token = "g"},
      };

      var obj_item_tag_found : ? ObjItemTag = null;
      for (&TOKEN_MAP) |token_mapping| {
         if (std.mem.eql(u8, element, token_mapping.token) == true) {
            obj_item_tag_found = token_mapping.tag;
            break;
         }
      }

      const obj_item_tag = obj_item_tag_found orelse return error.InvalidItem;

      switch (obj_item_tag) {
         .vertex => {
            const vertex = try _deserializeVertex(&tokens);
            self.vertices = self.vertices ++ .{vertex};
         },
         .texture_coordinate => {
            const texture_coordinate = try _deserializeTextureCoordinate(&tokens);
            self.texture_coordinates = self.texture_coordinates ++ .{texture_coordinate};
         },
         .normal => {
            const normal = try _deserializeNormal(&tokens);
            self.normals = self.normals ++ .{normal};
         },
         .face => {
            const face = try _deserializeFace(&tokens, current_material.*);
            self.faces = self.faces ++ .{face};
         },
         .material => {
            const material = try _deserializeMaterial(&tokens);
            current_material.* = material;
         },
         else => {},
      }

      return;
   }

   fn _deserializeVertex(comptime tokens : * std.mem.SplitIterator(u8, .scalar)) anyerror!math.Vector4(f32) {
      const token_x = tokens.next() orelse return error.MissingVertexCoordinateX;
      const token_y = tokens.next() orelse return error.MissingVertexCoordinateY;
      const token_z = tokens.next() orelse return error.MissingVertexCoordinateZ;
      const token_w = tokens.next();

      if (tokens.next() != null) {
         return error.MalformedParameters;
      }

      const x = try std.fmt.parseFloat(f32, token_x);
      const y = try std.fmt.parseFloat(f32, token_y);
      const z = try std.fmt.parseFloat(f32, token_z);
      const w = blk: {
         if (token_w) |token_w_unwrapped| {
            break :blk try std.fmt.parseFloat(f32, token_w_unwrapped);
         } else {
            break :blk 1.0;
         }
      };

      const vertex = math.Vector4(f32){.xyzw = .{
         .x = x,
         .y = y,
         .z = z,
         .w = w,
      }};

      return vertex;
   }

   fn _deserializeTextureCoordinate(comptime tokens : * std.mem.SplitIterator(u8, .scalar)) anyerror!math.Vector3(f32) {
      const token_u = tokens.next() orelse return error.MissingTextureCoordinateU;
      const token_v = tokens.next();
      const token_w = tokens.next();

      if (tokens.next() != null) {
         return error.MalformedParameters;
      }

      const u = try std.fmt.parseFloat(f32, token_u);
      const v = blk: {
         if (token_v) |token_v_unwrapped| {
            break :blk try std.fmt.parseFloat(f32, token_v_unwrapped);
         } else {
            break :blk 0.0;
         }
      };
      const w = blk: {
         if (token_w) |token_w_unwrapped| {
            break :blk try std.fmt.parseFloat(f32, token_w_unwrapped);
         } else {
            break :blk 0.0;
         }
      };

      const texture_coordinate = math.Vector3(f32){.xyz = .{
         .x = u,
         .y = v,
         .z = w,
      }};
      
      return texture_coordinate;
   }

   fn _deserializeNormal(comptime tokens : * std.mem.SplitIterator(u8, .scalar)) anyerror!math.Vector3(f32) {
      const token_x = tokens.next() orelse return error.MissingNormalComponentX;
      const token_y = tokens.next() orelse return error.MissingNormalComponentY;
      const token_z = tokens.next() orelse return error.MissingNormalComponentZ;

      if (tokens.next() != null) {
         return error.MalformedParameters;
      }

      const x = try std.fmt.parseFloat(f32, token_x);
      const y = try std.fmt.parseFloat(f32, token_y);
      const z = try std.fmt.parseFloat(f32, token_z);

      const normal = math.Vector3(f32){.xyz = .{
         .x = x,
         .y = y,
         .z = z,
      }};

      return normal;
   }

   fn _deserializeFace(comptime tokens : * std.mem.SplitIterator(u8, .scalar), comptime current_material : [] const u8) anyerror!ObjItemTag.Face {
      var indices : [] const ObjItemTag.Face.Index = &.{};

      while (tokens.next()) |token| {
         var index_tokens = std.mem.splitScalar(u8, token, '/');
         const index = try _deserializeFaceIndex(&index_tokens);
         indices = indices ++ .{index};
      }

      if (indices.len == 0) {
         return error.MissingFaceVertexData;
      }

      return .{
         .material   = current_material,
         .indices    = indices,
      };
   }

   fn _deserializeFaceIndex(comptime tokens : * std.mem.SplitIterator(u8, .scalar)) anyerror!ObjItemTag.Face.Index {
      const token_vertex               = tokens.next() orelse return error.MissingRequiredVertexIndex;
      const token_texture_coordinate   = tokens.next();
      const token_normal               = tokens.next();

      if (tokens.next() != null) {
         return error.MalformedParameters;
      }

      const vertex               = try std.fmt.parseInt(usize, token_vertex, 10);
      const texture_coordinate   = blk: {
         if (token_texture_coordinate) |token_texture_coordinate_unwrapped| {
            if (token_texture_coordinate_unwrapped.len == 0) {
               break :blk null;
            } else {
               break :blk try std.fmt.parseInt(usize, token_texture_coordinate_unwrapped, 10);
            }
         } else {
            break :blk null;
         }
      };
      const normal               = blk: {
         if (token_normal) |token_normal_unwrapped| {
            break :blk try std.fmt.parseInt(usize, token_normal_unwrapped, 10);
         } else {
            break :blk null;
         }
      };

      return .{
         .vertex              = vertex,
         .texture_coordinate  = texture_coordinate,
         .normal              = normal,
      };
   }

   fn _deserializeMaterial(comptime tokens : * std.mem.SplitIterator(u8, .scalar)) anyerror![] const u8 {
      const token = tokens.next() orelse return error.MissingMaterialName;

      if (tokens.next() != null) {
         return error.MalformedParameters;
      }

      return token;
   }
};

