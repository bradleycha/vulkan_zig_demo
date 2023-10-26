const std      = @import("std");
const f_shared = @import("shared.zig");

pub const Compositor = struct {
   pub const ConnectError = f_shared.Compositor.ConnectError;

   pub fn connect(allocator : std.mem.Allocator) ConnectError!@This() {
      _ = allocator;
      unreachable;
   }

   pub fn disconnect(self : @This(), allocator : std.mem.Allocator) void {
      _ = self;
      _ = allocator;
      unreachable;
   }
};

