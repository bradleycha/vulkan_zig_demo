const std   = @import("std");
const c     = @import("cimports");

pub const Instance = struct {
   pub const CreateInfo = struct {
      extensions  : [] const [*:0] const u8,
      debugging   : bool,
   };

   pub const CreateError = error {

   };

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      _ = allocator;
      _ = create_info;
      unreachable;
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator) void {
      _ = self;
      _ = allocator;
      unreachable;
   }
};

