const std      = @import("std");
const options  = @import("options");
const wayland  = @import("wayland.zig");

pub const CompositorConnectError = error {
   Unavailable,
   OutOfMemory,
   PlatformSpecificError,
};

fn CompositorPlatformImplementation(comptime container_type : type) type {
   return struct {
      container_type : type = container_type,
      pfn_connect    : * const fn(allocator : std.mem.Allocator) CompositorConnectError!container_type,
      pfn_disconnect : * const fn(container : container_type, allocator : std.mem.Allocator) void,
   };
}

fn _makeCompositorPlatformImplementation(comptime implementation : anytype) type {
   return struct {
      _container  : implementation.container_type,

      pub const ConnectError = CompositorConnectError;

      pub fn connect(allocator : std.mem.Allocator) ConnectError!@This() {
         return @This(){._container = try implementation.pfn_connect(allocator)};
      }

      pub fn disconnect(self : @This(), allocator : std.mem.Allocator) void {
         implementation.pfn_disconnect(self._container, allocator);
         return;
      }
   };
}

pub const Compositor = blk: {
   switch (options.window_backend) {
      .wayland => break :blk _makeCompositorPlatformImplementation(CompositorPlatformImplementation(wayland.Compositor){
         .pfn_connect      = wayland.Compositor.connect,
         .pfn_disconnect   = wayland.Compositor.disconnect,
      }),
   }
};

