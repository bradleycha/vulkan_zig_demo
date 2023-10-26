const std         = @import("std");
const builtin     = @import("builtin");
const window      = @import("window");
const graphics    = @import("graphics");
const resources   = @import("resources");

const MainError = error {
   OutOfMemory,
};

pub fn main() MainError!void {
   var heap = chooseHeapSettings();
   defer _ = heap.deinit();

   const allocator = heap.allocator();

   return;
}

fn chooseHeapSettings() std.heap.GeneralPurposeAllocator(.{}) {
   const backing_allocator = chooseBackingAllocator();

   return .{.backing_allocator = backing_allocator};
}

fn chooseBackingAllocator() std.mem.Allocator {
   if (builtin.link_libc == false) {
      return std.heap.page_allocator;
   }

   if (builtin.mode == .Debug) {
      return std.heap.page_allocator;
   }

   return std.heap.raw_c_allocator;
}

