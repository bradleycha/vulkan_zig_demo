const std      = @import("std");
const f_shared = @import("shared.zig");
const c        = @import("cimports");

pub const VULKAN_REQUIRED_EXTENSIONS = struct {
   pub const Instance = [_] [*:0] const u8 {
      c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
   };

   pub const Device = [_] [*:0] const u8 {

   };
};

pub const Compositor = struct {
   _wl_display    : * c.wl_display,
   _wl_registry   : * c.wl_registry,
   _wl_globals    : WaylandGlobals,

   pub fn connect(allocator : std.mem.Allocator) f_shared.Compositor.ConnectError!@This() {
      _ = allocator;

      const wl_display = c.wl_display_connect(null) orelse return error.Unavailable;
      errdefer c.wl_display_disconnect(wl_display);

      const wl_registry = c.wl_display_get_registry(wl_display) orelse return error.PlatformError;

      const wl_registry_listener = c.wl_registry_listener{
         .global        = _waylandRegistryListenerGlobal,
         .global_remove = _waylandRegistryListenerGlobalRemove,
      };

      var wl_globals_found = WaylandGlobals.Found{};
      _ = c.wl_registry_add_listener(wl_registry, &wl_registry_listener, &wl_globals_found);
      _ = c.wl_display_roundtrip(wl_display);

      const wl_globals = wl_globals_found.unwrap() orelse return error.PlatformError;

      const xdg_wm_base_listener = c.xdg_wm_base_listener{
         .ping = _xdgWmBaseListenerPing,
      };

      _ = c.xdg_wm_base_add_listener(wl_globals.xdg_wm_base, &xdg_wm_base_listener, null);
      
      return @This(){
         ._wl_display   = wl_display,
         ._wl_registry  = wl_registry,
         ._wl_globals   = wl_globals,
      };
   }

   pub const WaylandGlobals = struct {
      compositor  : * c.wl_compositor,
      xdg_wm_base : * c.xdg_wm_base,

      pub const Found = struct {
         compositor  : ? * c.wl_compositor   = null,
         xdg_wm_base : ? * c.xdg_wm_base     = null,

         pub fn unwrap(self : * const @This()) ? WaylandGlobals {
            const globals = WaylandGlobals{
               .compositor    = self.compositor    orelse return null,
               .xdg_wm_base   = self.xdg_wm_base   orelse return null,
            };

            return globals;
         }
      };
   };
   
   fn _waylandRegistryListenerGlobal(p_data : ? * anyopaque, p_wl_registry : ? * c.wl_registry, p_name : u32, p_interface : ? * const u8, p_version : u32) callconv(.C) void {
      const wl_globals_found : * WaylandGlobals.Found = @ptrCast(@alignCast(p_data orelse unreachable));
      const wl_registry = p_wl_registry orelse unreachable;
      const name = p_name;
      const interface = p_interface orelse unreachable;
      const version = p_version;

      blk_compositor: {
         const MINIMUM_VERSION = 1;

         if (c.strcmp(interface, c.wl_compositor_interface.name) != 0) {
            break :blk_compositor;
         }

         if (version < MINIMUM_VERSION) {
            return;
         }

         const wl_interface = c.wl_registry_bind(wl_registry, name, &c.wl_compositor_interface, MINIMUM_VERSION) orelse return;
         const wl_compositor : * c.wl_compositor = @ptrCast(@alignCast(wl_interface));

         wl_globals_found.compositor = wl_compositor;

         return;
      }

      blk_xdg_wm_base: {
         const MINIMUM_VERSION = 1;

         if (c.strcmp(interface, c.xdg_wm_base_interface.name) != 0) {
            break :blk_xdg_wm_base;
         }

         if (version < MINIMUM_VERSION) {
            return;
         }

         const wl_interface = c.wl_registry_bind(wl_registry, name, &c.xdg_wm_base_interface, MINIMUM_VERSION) orelse return;
         const xdg_wm_base : * c.xdg_wm_base = @ptrCast(@alignCast(wl_interface));

         wl_globals_found.xdg_wm_base = xdg_wm_base;

         return;
      }

      return;
   }

   fn _waylandRegistryListenerGlobalRemove(p_data : ? * anyopaque, p_wl_registry : ? * c.wl_registry, p_name : u32) callconv(.C) void {
      _ = p_data;
      _ = p_wl_registry;
      _ = p_name;
      return;
   }

   fn _xdgWmBaseListenerPing(_ : ? * anyopaque, p_xdg_wm_base : ? * c.xdg_wm_base, p_serial : u32) callconv(.C) void {
      const xdg_wm_base = p_xdg_wm_base orelse unreachable;
      const serial = p_serial;

      c.xdg_wm_base_pong(xdg_wm_base, serial);

      return;
   }

   pub fn disconnect(self : @This(), allocator : std.mem.Allocator) void {
      _ = allocator;

      c.wl_display_disconnect(self._wl_display);
      return;
   }

   pub fn createWindow(self : * @This(), allocator : std.mem.Allocator, create_info : * const f_shared.Window.CreateInfo) f_shared.Window.CreateError!Window {
      return Window.create(self, allocator, create_info);
   }

   pub fn vulkanGetPhysicalDevicePresentationSupport(self : * const @This(), vk_physical_device : c.VkPhysicalDevice, vk_queue_family_index : u32) c.VkBool32 {
      return c.vkGetPhysicalDeviceWaylandPresentationSupportKHR(vk_physical_device, vk_queue_family_index, self._wl_display);
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

