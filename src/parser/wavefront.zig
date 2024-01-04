const std      = @import("std");
const math     = @import("math");
const graphics = @import("graphics");

pub fn parseWavefrontComptime(comptime obj : [] const u8, comptime mtl : [] const u8) anyerror!graphics.types.Mesh {
   const obj_items = try ObjItemList.parse(obj);
   const mtl_items = try MtlItemList.parse(mtl);

   // TODO: Implement rest
   _ = obj_items;
   _ = mtl_items;
   return error.NotImplemented;
}

const ObjItemList = struct {
   pub fn parse(comptime text : [] const u8) anyerror!@This() {
      // TODO: Implement
      _ = text;
      unreachable;
   }
};

const ObjItemTag = enum {

};

const ObjItem = union(ObjItemTag) {

};

const MtlItemList = struct {
   pub fn parse(comptime text : [] const u8) anyerror!@This() {
      // TODO: Implement
      _ = text;
      unreachable;
   }
};

const MtlItemTag = enum {

};

const MtlItem = union(MtlItemTag) {

};

