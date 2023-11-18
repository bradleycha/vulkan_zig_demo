const std      = @import("std");
const input    = @import("input");
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
      errdefer c.wl_registry_destroy(wl_registry);

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

      c.wl_registry_destroy(self._wl_registry);
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
   _compositor    : * Compositor,
   _wl_surface    : * c.wl_surface,
   _xdg_surface   : * c.xdg_surface,
   _xdg_toplevel  : * c.xdg_toplevel,
   _callbacks     : * _Callbacks,
   _input_state   : input.InputState,

   const _Callbacks = struct {
      mutex                : std.Thread.Mutex = .{},
      current_resolution   : f_shared.Window.Resolution = .{.width = 0, .height = 0},
      should_close         : bool = false,
   };

   pub fn create(compositor : * Compositor, allocator : std.mem.Allocator, create_info : * const f_shared.Window.CreateInfo) f_shared.Window.CreateError!@This() {
      // Since we are using listeners outside the scope of this function, we
      // unfortunately have to allocate on the heap, otherwise we won't be able
      // to safely move the struct.

      const callbacks = try allocator.create(_Callbacks);
      errdefer allocator.destroy(callbacks);
      callbacks.* = .{};

      const wl_surface = c.wl_compositor_create_surface(compositor._wl_globals.compositor) orelse return error.PlatformError;
      errdefer c.wl_surface_destroy(wl_surface);

      const xdg_surface = c.xdg_wm_base_get_xdg_surface(compositor._wl_globals.xdg_wm_base, wl_surface) orelse return error.PlatformError;
      errdefer c.xdg_surface_destroy(xdg_surface);

      const xdg_surface_listener = c.xdg_surface_listener{
         .configure = _xdgSurfaceListenerConfigure,
      };

      _ = c.xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, null);

      const xdg_toplevel = c.xdg_surface_get_toplevel(xdg_surface) orelse return error.PlatformError;
      errdefer c.xdg_toplevel_destroy(xdg_toplevel);

      const xdg_toplevel_listener = c.xdg_toplevel_listener{
         .configure        = _xdgToplevelListenerConfigure,
         .close            = _xdgToplevelListenerClose,
         .configure_bounds = null,
         .wm_capabilities  = null,
      };

      _ = c.xdg_toplevel_add_listener(xdg_toplevel, &xdg_toplevel_listener, callbacks);

      // TODO: Initial size and fullscreen mode

      c.xdg_toplevel_set_title(xdg_toplevel, create_info.title.ptr);
      c.xdg_toplevel_set_app_id(xdg_toplevel, create_info.title.ptr);

      _ = c.wl_surface_commit(wl_surface);
      _ = c.wl_display_roundtrip(compositor._wl_display);
      _ = c.wl_surface_commit(wl_surface);

      return @This(){
         ._compositor   = compositor,
         ._wl_surface   = wl_surface,
         ._xdg_surface  = xdg_surface,
         ._xdg_toplevel = xdg_toplevel,
         ._callbacks    = callbacks,
         ._input_state  = .{},
      };
   }

   fn _xdgSurfaceListenerConfigure(_ : ? * anyopaque, p_xdg_surface : ? * c.xdg_surface, p_serial : u32) callconv(.C) void {
      const xdg_surface = p_xdg_surface orelse unreachable;
      const serial = p_serial;

      c.xdg_surface_ack_configure(xdg_surface, serial);

      return;
   }

   fn _xdgToplevelListenerConfigure(p_callbacks : ? * anyopaque, p_xdg_toplevel : ? * c.xdg_toplevel, p_width : i32, p_height : i32, _ : ? * c.wl_array) callconv(.C) void {
      const callbacks : * _Callbacks = @ptrCast(@alignCast(p_callbacks orelse unreachable));
      const xdg_toplevel = p_xdg_toplevel orelse unreachable;
      const width : u32 = @intCast(p_width);
      const height : u32 = @intCast(p_height);

      callbacks.mutex.lock();
      defer callbacks.mutex.unlock();

      callbacks.current_resolution = .{.width = width, .height = height};

      _ = xdg_toplevel;

      return;
   }

   fn _xdgToplevelListenerClose(p_callbacks : ? * anyopaque, p_xdg_toplevel : ? * c.xdg_toplevel) callconv(.C) void {
      const callbacks : * _Callbacks = @ptrCast(@alignCast(p_callbacks orelse unreachable));
      const xdg_toplevel = p_xdg_toplevel orelse unreachable;

      callbacks.mutex.lock();
      defer callbacks.mutex.unlock();

      callbacks.should_close = true;

      _ = xdg_toplevel;

      return;
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator) void {
      c.xdg_toplevel_destroy(self._xdg_toplevel);
      c.xdg_surface_destroy(self._xdg_surface);
      c.wl_surface_destroy(self._wl_surface);
      allocator.destroy(self._callbacks);
      return;
   }

   pub fn getResolution(self : * const @This()) f_shared.Window.Resolution {
      self._callbacks.mutex.lock();
      defer self._callbacks.mutex.unlock();

      return self._callbacks.current_resolution;
   }

   pub fn setTitle(self : * @This(), title : [:0] const u8) void {
      c.xdg_toplevel_set_title(self._xdg_toplevel, title.ptr);
      c.xdg_toplevel_set_app_id(self._xdg_toplevel, title.ptr);
      return;
   }

   pub fn shouldClose(self : * const @This()) bool {
      self._callbacks.mutex.lock();
      defer self._callbacks.mutex.unlock();

      return self._callbacks.should_close;
   }

   pub fn pollEvents(self : * @This()) f_shared.Window.PollEventsError!void {
      _ = c.wl_display_roundtrip(self._compositor._wl_display);

      self._input_state.buttons.advance();

      // TODO: Input state

      return;
   }

   pub fn vulkanCreateSurface(self : * @This(), vk_instance : c.VkInstance, vk_allocator : ? * const c.VkAllocationCallbacks, vk_surface : * c.VkSurfaceKHR) c.VkResult {
      const vk_info_create_wayland_surface = c.VkWaylandSurfaceCreateInfoKHR{
         .sType   = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
         .pNext   = null,
         .flags   = 0x00000000,
         .display = self._compositor._wl_display,
         .surface = self._wl_surface,
      };

      return c.vkCreateWaylandSurfaceKHR(vk_instance, &vk_info_create_wayland_surface, vk_allocator, vk_surface);
   }

   pub fn inputState(self : * const @This()) * const input.InputState {
      return &self._input_state;
   }
};

