const std      = @import("std");
const options  = @import("options");
const f_shared = @import("shared.zig");

const PlatformContainers = struct {
   compositor  : type,
};

fn _platformImplementation(comptime containers : PlatformContainers) type {
   return struct {
      containers                 : PlatformContainers = containers,
      pfn_compositor_connect     : * const fn (allocator : std.mem.Allocator) f_shared.Compositor.ConnectError!containers.compositor,
      pfn_compositor_disconnect  : * const fn (container : containers.compositor, allocator : std.mem.Allocator) void,
   };
}

const IMPLEMENTATION = blk: {
   const wayland = @import("wayland.zig");

   switch (options.window_backend) {
      .wayland => break :blk _platformImplementation(.{
         .compositor = wayland.Compositor,
      }){
         .pfn_compositor_connect    = wayland.Compositor.connect,
         .pfn_compositor_disconnect = wayland.Compositor.disconnect,
      },
   }
};

pub const Compositor = struct {
   _container  : IMPLEMENTATION.containers.compositor,

   pub const ConnectError = f_shared.Compositor.ConnectError;

   pub fn connect(allocator : std.mem.Allocator) ConnectError!@This() {
      return @This(){._container = try IMPLEMENTATION.pfn_compositor_connect(allocator)};
   }

   pub fn disconnect(self : @This(), allocator : std.mem.Allocator) void {
      IMPLEMENTATION.pfn_compositor_disconnect(self._container, allocator);
      return;
   }
};

