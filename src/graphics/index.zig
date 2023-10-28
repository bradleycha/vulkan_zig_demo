const std      = @import("std");
const builtin  = @import("builtin");
const present  = @import("present");
const vulkan   = @import("vulkan/index.zig");

pub const Renderer = struct {
   pub const CreateInfo = struct {
      debugging   : bool,
   };

   pub const CreateError = error {

   };

   pub fn create(allocator : std.mem.Allocator, window : * present.Window, create_info : * const CreateInfo) CreateError!@This() {
      _ = allocator;
      _ = window;
      _ = create_info;
      
      return @This(){

      };
   }

   pub fn destroy(self : @This()) void {
      _ = self;
      return;
   }
};

