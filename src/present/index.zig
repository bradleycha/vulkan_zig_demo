const std      = @import("std");
const options  = @import("options");
const f_shared = @import("shared.zig");
const c        = @import("cimports");

const PlatformContainers = struct {
   compositor  : type,
   window      : type,
};

fn _platformImplementation(comptime containers : PlatformContainers) type {
   return struct {
      containers : PlatformContainers = containers,

      vulkan_required_extensions_instance : [] [*:0] const u8,
      vulkan_required_extensions_device   : [] [*:0] const u8,

      pfn_compositor_connect : * const fn (
         allocator : std.mem.Allocator,
      ) f_shared.Compositor.ConnectError!containers.compositor,

      pfn_compositor_disconnect : * const fn (
         container : containers.compositor,
         allocator : std.mem.Allocator,
      ) void,

      pfn_compositor_vulkan_get_physical_device_presentation_support : * const fn (
         container               : * const containers.compositor,
         vk_physical_device      : c.VkPhysicalDevice,
         vk_queue_family_index   : u32,
      ) c.VkBool32,

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

      pfn_window_vulkan_create_surface : * const fn (
         container      : * containers.window,
         vk_instance    : c.VkInstance,
         vk_allocator   : ? * const c.VkAllocationCallbacks,
         vk_surface     : * c.VkSurfaceKHR,
      ) c.VkResult,
   };
}

const IMPLEMENTATION = blk: {
   const wayland  = @import("wayland.zig");
   const xcb      = @import("xcb.zig");

   switch (options.present_backend) {
      .wayland => break :blk _platformImplementation(.{
         .compositor = wayland.Compositor,
         .window     = wayland.Window,
      }){
         .vulkan_required_extensions_instance                              = &wayland.Window.VULKAN_REQUIRED_EXTENSIONS.Instance,
         .vulkan_required_extensions_device                                = &wayland.Window.VULKAN_REQUIRED_EXTENSIONS.Device,
         .pfn_compositor_connect                                           = wayland.Compositor.connect,
         .pfn_compositor_disconnect                                        = wayland.Compositor.disconnect,
         .pfn_compositor_create_window                                     = wayland.Compositor.createWindow,
         .pfn_compositor_vulkan_get_physical_device_presentation_support   = wayland.Compositor.vulkanGetPhysicalDevicePresentationSupport,
         .pfn_window_create                                                = wayland.Window.create,
         .pfn_window_destroy                                               = wayland.Window.destroy,
         .pfn_window_get_resolution                                        = wayland.Window.getResolution,
         .pfn_window_set_title                                             = wayland.Window.setTitle,
         .pfn_window_should_close                                          = wayland.Window.shouldClose,
         .pfn_window_set_should_close                                      = wayland.Window.setShouldClose,
         .pfn_window_poll_events                                           = wayland.Window.pollEvents,
         .pfn_window_vulkan_create_surface                                 = wayland.Window.vulkanCreateSurface,
      },

      .xcb => break :blk _platformImplementation(.{
         .compositor = xcb.Compositor,
         .window     = xcb.Window,
      }){
         .vulkan_required_extensions_instance                              = &xcb.Window.VULKAN_REQUIRED_EXTENSIONS.Instance,
         .vulkan_required_extensions_device                                = &xcb.Window.VULKAN_REQUIRED_EXTENSIONS.Device,
         .pfn_compositor_connect                                           = xcb.Compositor.connect,
         .pfn_compositor_disconnect                                        = xcb.Compositor.disconnect,
         .pfn_compositor_create_window                                     = xcb.Compositor.createWindow,
         .pfn_compositor_vulkan_get_physical_device_presentation_support   = xcb.Compositor.vulkanGetPhysicalDevicePresentationSupport,
         .pfn_window_create                                                = xcb.Window.create,
         .pfn_window_destroy                                               = xcb.Window.destroy,
         .pfn_window_get_resolution                                        = xcb.Window.getResolution,
         .pfn_window_set_title                                             = xcb.Window.setTitle,
         .pfn_window_should_close                                          = xcb.Window.shouldClose,
         .pfn_window_set_should_close                                      = xcb.Window.setShouldClose,
         .pfn_window_poll_events                                           = xcb.Window.pollEvents,
         .pfn_window_vulkan_create_surface                                 = xcb.Window.vulkanCreateSurface,
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

   pub fn vulkanGetPhysicalDevicePresentationSupport(self : * const @This(), vk_physical_device : c.VkPhysicalDevice, vk_queue_family_index : u32) c.VkBool32 {
      return IMPLEMENTATION.pfn_compositor_vulkan_get_physical_device_presentation_support(&self._container, vk_physical_device, vk_queue_family_index);
   }
};

pub const Window = struct {
   _container  : IMPLEMENTATION.containers.window,

   pub const VULKAN_REQUIRED_EXTENSIONS = struct {
      pub const Instance   = IMPLEMENTATION.vulkan_required_extensions_instance;
      pub const Device     = IMPLEMENTATION.vulkan_required_extensions_device;
   };

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

   pub fn vulkanCreateSurface(self : * @This(), vk_instance : c.VkInstance, vk_allocator : ? * const c.VkAllocationCallbacks, vk_surface : * c.VkSurfaceKHR) c.VkResult {
      return IMPLEMENTATION.pfn_window_vulkan_create_surface(self, vk_instance, vk_allocator, vk_surface);
   }
};

