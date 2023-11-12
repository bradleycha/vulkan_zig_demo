const std      = @import("std");
const f_shared = @import("shared.zig");
const c        = @import("cimports");

pub const VULKAN_REQUIRED_EXTENSIONS = struct {
   pub const Instance = [_] [*:0] const u8 {
      c.VK_KHR_XCB_SURFACE_EXTENSION_NAME,
   };

   pub const Device = [_] [*:0] const u8 {

   };
};

pub const Compositor = struct {
   _x_connection  : * c.xcb_connection_t,
   _x_screen      : * c.xcb_screen_t,

   pub fn connect(allocator : std.mem.Allocator) f_shared.Compositor.ConnectError!@This() {
      _ = allocator;

      var x_errno : c_int = undefined;

      var x_screen_index : c_int = undefined;
      const x_connection = c.xcb_connect(null, &x_screen_index) orelse unreachable;
      errdefer c.xcb_disconnect(x_connection);

      x_errno = c.xcb_connection_has_error(x_connection);
      if (x_errno < 0) {
         return error.PlatformError;
      }

      var x_setup = c.xcb_get_setup(x_connection) orelse unreachable;

      var x_screen_iter = c.xcb_setup_roots_iterator(x_setup);
      var x_screen_iter_index : c_int = 0;
      while (x_screen_iter_index < x_screen_index) {
         c.xcb_screen_next(&x_screen_iter);
         x_screen_iter_index += 1;
      }

      const x_screen = x_screen_iter.data;

      return @This(){
         ._x_connection = x_connection,
         ._x_screen     = x_screen,
      };
   }

   pub fn disconnect(self : @This(), allocator : std.mem.Allocator) void {
      _ = allocator;

      c.xcb_disconnect(self._x_connection);
      return;
   }

   pub fn createWindow(self : * @This(), allocator : std.mem.Allocator, create_info : * const f_shared.Window.CreateInfo) f_shared.Window.CreateError!Window {
      return Window.create(self, allocator, create_info);
   }

   pub fn vulkanGetPhysicalDevicePresentationSupport(self : * const @This(), vk_physical_device : c.VkPhysicalDevice, vk_queue_family_index : u32) c.VkBool32 {
      return c.vkGetPhysicalDeviceXcbPresentationSupportKHR(vk_physical_device, vk_queue_family_index, self._x_connection, self._x_screen.*.root_visual);
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

