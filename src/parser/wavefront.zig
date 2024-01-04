const std      = @import("std");
const math     = @import("math");
const graphics = @import("graphics");

pub fn parseWavefrontComptime(comptime obj : [] const u8, comptime mtl : [] const u8) anyerror!graphics.types.Mesh {
   const obj_items = try ObjItemList.deserialize(obj);
   const mtl_items = try MtlItemList.deserialize(mtl);

   // TODO: Implement rest
   _ = obj_items;
   _ = mtl_items;
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
      material       : ? [] const u8,
      smooth_shading : bool,
      indices        : [] @This().Index,

      pub const Index = struct {
         vertex               : comptime_int,
         texture_coordinate   : ? comptime_int,
         normal               : ? comptime_int,
      };
   };
};

const ObjItemList = struct {
   vertices             : [] math.Vector4(f32),
   texture_coordinates  : [] math.Vector3(f32),
   normals              : [] math.Vector3(f32),
   faces                : [] ObjItemTag.Face,

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
         try _deserializeLine(&items, line, &current_material);
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
            self.vertices = self.vertices ++ &.{vertex};
         },
         .texture_coordinate => {
            const texture_coordinate = try _deserializeTextureCoordinate(&tokens);
            self.texture_coordinates = self.texture_coordinates ++ &.{texture_coordinate};
         },
         .normal => {
            const normal = try _deserializeNormal(&tokens);
            self.normals = self.normals ++ &.{normal};
         },
         .face => {
            const face = try _deserializeFace(&tokens);
            self.faces = self.faces ++ &.{face};
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
      _ = tokens;
      unreachable;
   }

   fn _deserializeTextureCoordinate(comptime tokens : * std.mem.SplitIterator(u8, .scalar)) anyerror!math.Vector3(f32) {
      _ = tokens;
      unreachable;
   }

   fn _deserializeNormal(comptime tokens : * std.mem.SplitIterator(u8, .scalar)) anyerror!math.Vector3(f32) {
      _ = tokens;
      unreachable;
   }

   fn _deserializeFace(comptime tokens : * std.mem.SplitIterator(u8, .scalar)) anyerror!ObjItemTag.Face {
      _ = tokens;
      unreachable;
   }

   fn _deserializeMaterial(comptime tokens : * std.mem.SplitIterator(u8, .scalar)) anyerror![] const u8 {
      _ = tokens;
      unreachable;
   }
};

const MtlItemList = struct {
   pub fn deserialize(comptime text : [] const u8) anyerror!@This() {
      // TODO: Implement
      _ = text;
      unreachable;
   }
};

const MtlItemTag = enum {

};

const MtlItem = union(MtlItemTag) {

};

