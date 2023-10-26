const root  = @import("index.zig");
const std   = @import("std");

pub const Compositor = struct {
   pub fn connect(allocator : std.mem.Allocator) root.CompositorConnectError!@This() {
      _ = allocator;
      unreachable;
   }

   pub fn disconnect(self : @This(), allocator : std.mem.Allocator) void {
      _ = self;
      _ = allocator;
      unreachable;
   }
};

