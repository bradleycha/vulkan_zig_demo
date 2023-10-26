const std      = @import("std");
const options  = @import("options");
const f_shared = @import("shared.zig");

const PlatformContainers = struct {
   compositor  : type,
   window      : type,
};

fn _platformImplementation(comptime containers : PlatformContainers) type {
   return struct {
      containers                 : PlatformContainers = containers,

      pfn_compositor_connect : * const fn (
         allocator : std.mem.Allocator,
      ) f_shared.Compositor.ConnectError!containers.compositor,

      pfn_compositor_disconnect : * const fn (
         container : containers.compositor,
         allocator : std.mem.Allocator,
      ) void,

      pfn_compositor_create_window : * const fn (
         container   : * containers.compositor,
         allocator   : std.mem.Allocator,
         create_info : * const f_shared.Window.CreateInfo,
      ) f_shared.Window.CreateError!containers.window,

      pfn_window_create : * const fn (
         compositor  : * containers.compositor,
         allocator   : std.mem.Allocator,
         create_info : * const f_shared.Window.CreateInfo,
      ) f_shared.Window.CreateError!containers.window,

      pfn_window_destroy : * const fn (
         container   : containers.window,
         allocator   : std.mem.Allocator,
      ) void,

      pfn_window_get_resolution : * const fn (
         container   : * const containers.window,
      ) f_shared.Window.Resolution,

      pfn_window_set_title : * const fn (
         container   : * containers.window,
         title       : [*:0] const u8,
      ) void,

      pfn_window_should_close : * const fn (
         container   : * const containers.window,
      ) bool,

      pfn_window_set_should_close : * const fn (
         container      : * containers.window,
         should_close   : bool,
      ) void,

      pfn_window_poll_events : * const fn (
         container   : * containers.window,
      ) f_shared.Window.PollEventsError!void,
   };
}

const IMPLEMENTATION = blk: {
   const wayland = @import("wayland.zig");

   switch (options.present_backend) {
      .wayland => break :blk _platformImplementation(.{
         .compositor = wayland.Compositor,
         .window     = wayland.Window,
      }){
         .pfn_compositor_connect          = wayland.Compositor.connect,
         .pfn_compositor_disconnect       = wayland.Compositor.disconnect,
         .pfn_compositor_create_window    = wayland.Compositor.createWindow,
         .pfn_window_create               = wayland.Window.create,
         .pfn_window_destroy              = wayland.Window.destroy,
         .pfn_window_get_resolution       = wayland.Window.getResolution,
         .pfn_window_set_title            = wayland.Window.setTitle,
         .pfn_window_should_close         = wayland.Window.shouldClose,
         .pfn_window_set_should_close     = wayland.Window.setShouldClose,
         .pfn_window_poll_events          = wayland.Window.pollEvents,
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

   pub fn createWindow(self : * @This(), allocator : std.mem.Allocator, create_info : * const f_shared.Window.CreateInfo) f_shared.Window.CreateError!Window {
      return Window.create(self, allocator, create_info);
   }
};

pub const Window = struct {
   _container  : IMPLEMENTATION.containers.window,

   pub fn create(compositor : * Compositor, allocator : std.mem.Allocator, create_info : * const f_shared.Window.CreateInfo) f_shared.Window.CreateError!@This() {
      return @This(){._container = try IMPLEMENTATION.pfn_window_create(&compositor._container, allocator, create_info)};
   }
   
   pub fn destroy(self : @This(), allocator : std.mem.Allocator) void {
      IMPLEMENTATION.pfn_window_destroy(self._container, allocator);
      return;
   }

   pub fn getResolution(self : * const @This()) f_shared.Window.Resolution {
      return IMPLEMENTATION.pfn_window_get_resolution(&self._container);
   }

   pub fn setTitle(self : * @This(), title : [*:0] const u8) void {
      IMPLEMENTATION.pfn_window_set_title(&self._container, title);
      return;
   }

   pub fn shouldClose(self : * const @This()) bool {
      return IMPLEMENTATION.pfn_window_should_close(&self._container);
   }

   pub fn setShouldClose(self : * @This(), should_close : bool) void {
      IMPLEMENTATION.pfn_window_set_should_close(&self._container, should_close);
      return;
   }
   
   pub fn pollEvents(self : * @This()) f_shared.Window.PollEventsError!void {
      try IMPLEMENTATION.pfn_window_poll_events(&self._container);
      return;
   }
};

