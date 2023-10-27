const std      = @import("std");
const f_shared = @import("shared.zig");
const c        = @import("cimports");

pub const VULKAN_REQUIRED_EXTENSIONS = struct {
   pub const Instance = [_] [*:0] const u8 {

   };

   pub const Device = [_] [*:0] const u8 {

   };
};

pub const Compositor = struct {
   pub fn connect(allocator : std.mem.Allocator) f_shared.Compositor.ConnectError!@This() {
      _ = allocator;
      unreachable;
   }

   pub fn disconnect(self : @This(), allocator : std.mem.Allocator) void {
      _ = self;
      _ = allocator;
      unreachable;
   }

   pub fn createWindow(self : * @This(), allocator : std.mem.Allocator, create_info : * const f_shared.Window.CreateInfo) f_shared.Window.CreateError!Window {
      return Window.create(self, allocator, create_info);
   }

   pub fn vulkanGetPhysicalDevicePresentationSupport(self : * const @This(), vk_physical_device : c.VkPhysicalDevice, vk_queue_family_index : u32) c.VkBool32 {
      _ = self;
      _ = vk_physical_device;
      _ = vk_queue_family_index;
      unreachable;
   }
};

pub const Window = struct {
   pub fn create(compositor : * Compositor, allocator : std.mem.Allocator, create_info : * const f_shared.Window.CreateInfo) f_shared.Window.CreateError!@This() {
      _ = compositor;
      _ = allocator;
      _ = create_info;
      unreachable;
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator) void {
      _ = self;
      _ = allocator;
      unreachable;
   }

   pub fn getResolution(self : * const @This()) f_shared.Window.Resolution {
      _ = self;
      unreachable;
   }

   pub fn setTitle(self : * @This(), title : [*:0] const u8) void {
      _ = self;
      _ = title;
      unreachable;
   }

   pub fn shouldClose(self : * const @This()) bool {
      _ = self;
      unreachable;
   }

   pub fn setShouldClose(self : * @This(), should_close : bool) void {
      _ = self;
      _ = should_close;
      unreachable;
   }

   pub fn pollEvents(self : * @This()) f_shared.Window.PollEventsError!void {
      _ = self;
      unreachable;
   }

   pub fn vulkanCreateSurface(self : * @This(), vk_instance : c.VkInstance, vk_allocator : ? * const c.VkAllocationCallbacks, vk_surface : * c.VkSurfaceKHR) c.VkResult {
      _ = self;
      _ = vk_instance;
      _ = vk_allocator;
      _ = vk_surface;
      unreachable;
   }
};

