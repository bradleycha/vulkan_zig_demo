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
   _compositor    : * const Compositor,
   _x_window      : c.xcb_window_t,
   _should_close  : bool,

   pub fn create(compositor : * Compositor, allocator : std.mem.Allocator, create_info : * const f_shared.Window.CreateInfo) f_shared.Window.CreateError!@This() {
      _ = allocator;

      const x_connection   = compositor._x_connection;
      const x_screen       = compositor._x_screen;

      const x_window = c.xcb_generate_id(x_connection);
      errdefer _ = c.xcb_destroy_window(x_connection, x_window);

      var width   : u16 = undefined;
      var height  : u16 = undefined;
      switch (create_info.display_mode) {
         .windowed   => |*resolution| {
            width    = @intCast(resolution.width);
            height   = @intCast(resolution.height);
         },
         .fullscreen => {
            width    = x_screen.width_in_pixels;
            height   = x_screen.height_in_pixels;
         },
      }

      const x_value_mask = c.XCB_CW_EVENT_MASK;
      const x_value_list = c.XCB_EVENT_MASK_EXPOSURE | c.XCB_EVENT_MASK_STRUCTURE_NOTIFY;

      const x_cookie_window_create = c.xcb_create_window_checked(
         x_connection,                       // connection
         c.XCB_COPY_FROM_PARENT,             // depth
         x_window,                           // wid
         x_screen.root,                      // parent
         0,                                  // x
         0,                                  // y
         width,                              // width
         height,                             // height
         1,                                  // border_width
         c.XCB_WINDOW_CLASS_INPUT_OUTPUT,    // class
         x_screen.root_visual,               // visual
         x_value_mask,                       // value_mask
         &x_value_list,                      // value_list
      );

      const x_cookie_window_map = c.xcb_map_window_checked(x_connection, x_window);
      errdefer _ = c.xcb_unmap_window(x_connection, x_window);

      const x_cookie_set_title = c.xcb_change_property_checked(
         x_connection,
         c.XCB_PROP_MODE_REPLACE,
         x_window,
         c.XCB_ATOM_WM_NAME,
         c.XCB_ATOM_STRING,
         8,
         @intCast(create_info.title.len),
         create_info.title.ptr,
      );

      // TODO: Set fullscreen mode

      if (c.xcb_request_check(x_connection, x_cookie_window_create) != null) {
         return error.PlatformError;
      }

      if (c.xcb_request_check(x_connection, x_cookie_window_map) != null) {
         return error.PlatformError;
      }

      if (c.xcb_request_check(x_connection, x_cookie_set_title) != null) {
         return error.PlatformError;
      }

      return @This(){
         ._compositor   = compositor,
         ._x_window     = x_window,
         ._should_close = false,
      };
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator) void {
      _ = allocator;

      const x_connection   = self._compositor._x_connection;
      const x_window       = self._x_window;

      _ = c.xcb_unmap_window(x_connection, x_window);
      _ = c.xcb_destroy_window(x_connection, x_window);
      return;
   }

   pub fn getResolution(self : * const @This()) f_shared.Window.Resolution {
      const x_connection   = self._compositor._x_connection;
      const x_window       = self._x_window;

      const x_cookie_window_geometry = c.xcb_get_geometry(
         x_connection,
         x_window,
      );

      const x_window_geometry = c.xcb_get_geometry_reply(
         x_connection,
         x_cookie_window_geometry,
         null,
      ) orelse return .{.width = 0, .height = 0}; // Oh crap!
      defer c.free(x_window_geometry);

      return .{
         .width   = @as(u32, x_window_geometry.*.width),
         .height  = @as(u32, x_window_geometry.*.height),
      };
   }

   pub fn setTitle(self : * @This(), title : [:0] const u8) void {
      _ = c.xcb_change_property(
         self._compositor._x_connection,
         c.XCB_PROP_MODE_REPLACE,
         self._x_window,
         c.XCB_ATOM_WM_NAME,
         c.XCB_ATOM_STRING,
         8,
         @intCast(title.len),
         title.ptr,
      );

      return;
   }

   pub fn shouldClose(self : * const @This()) bool {
      return self._should_close;
   }

   pub fn pollEvents(self : * @This()) f_shared.Window.PollEventsError!void {
      const x_connection = self._compositor._x_connection;

      var x_generic_event_iterator = c.xcb_poll_for_event(x_connection);
      while (x_generic_event_iterator) |x_generic_event| {
         try self._handleXEvent(x_generic_event);

         c.free(x_generic_event);
         x_generic_event_iterator = c.xcb_poll_for_event(x_connection);
      }

      return;
   }

   fn _handleXEvent(self : * @This(), x_generic_event : * const c.xcb_generic_event_t) f_shared.Window.PollEventsError!void {
      // TODO: Implement, specifically WM_DELETE client message
      // https://stackoverflow.com/questions/8776300/how-to-exit-program-with-close-button-in-xcb
      // https://stackoverflow.com/questions/69197575/how-to-handle-xcb-client-messages-properly
      // https://stackoverflow.com/questions/10792361/how-do-i-gracefully-exit-an-x11-event-loop

      _ = self;
      _ = x_generic_event;
      return;
   }

   pub fn vulkanCreateSurface(self : * @This(), vk_instance : c.VkInstance, vk_allocator : ? * const c.VkAllocationCallbacks, vk_surface : * c.VkSurfaceKHR) c.VkResult {
      const vk_info_create_xcb_surface = c.VkXcbSurfaceCreateInfoKHR{
         .sType      = c.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
         .pNext      = null,
         .flags      = 0x00000000,
         .connection = self._compositor._x_connection,
         .window     = self._x_window,
      };

      return c.vkCreateXcbSurfaceKHR(vk_instance, &vk_info_create_xcb_surface, vk_allocator, vk_surface);
   }
};

