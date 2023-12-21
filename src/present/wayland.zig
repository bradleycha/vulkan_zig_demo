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
   _wl_display          : * c.wl_display,
   _wl_registry         : * c.wl_registry,
   _wl_globals          : WaylandGlobals,
   _wl_inputs           : WaylandInputs,
   _wl_input_callbacks  : * WaylandInputCallbacks,

   pub fn connect(allocator : std.mem.Allocator) f_shared.Compositor.ConnectError!@This() {
      const wl_input_callbacks = try allocator.create(WaylandInputCallbacks);
      errdefer allocator.destroy(wl_input_callbacks);
      wl_input_callbacks.* = .{};

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

      const wl_seat_listener = c.wl_seat_listener{
         .capabilities  = _waylandSeatListenerCapabilities,
         .name          = _waylandSeatListenerName,
      };

      var wl_inputs = WaylandInputs{};
      _ = c.wl_seat_add_listener(wl_globals.seat, &wl_seat_listener, &wl_inputs);
      _ = c.wl_display_roundtrip(wl_display);

      if (wl_inputs.pointer) |wl_pointer| {
         const wl_pointer_listener = c.wl_pointer_listener{
            .enter                     = _waylandPointerListenerEnter,
            .leave                     = _waylandPointerListenerLeave,
            .motion                    = _waylandPointerListenerMotion,
            .button                    = _waylandPointerListenerButton,
            .axis                      = _waylandPointerListenerAxis,
            .frame                     = _waylandPointerListenerFrame,
            .axis_source               = _waylandPointerListenerAxisSource,
            .axis_stop                 = _waylandPointerListenerAxisStop,
            .axis_discrete             = _waylandPointerListenerAxisDiscrete,
            .axis_value120             = _waylandPointerListenerAxisValue120,
            .axis_relative_direction   = _waylandPointerListenerAxisRelativeDirection,
         };

         _ = c.wl_pointer_add_listener(wl_pointer, &wl_pointer_listener, wl_input_callbacks);
      }
      
      return @This(){
         ._wl_display         = wl_display,
         ._wl_registry        = wl_registry,
         ._wl_globals         = wl_globals,
         ._wl_inputs          = wl_inputs,
         ._wl_input_callbacks = wl_input_callbacks,
      };
   }

   pub const WaylandGlobals = struct {
      compositor           : * c.wl_compositor,
      xdg_wm_base          : * c.xdg_wm_base,
      seat                 : * c.wl_seat,
      pointer_constraints  : * c.zwp_pointer_constraints_v1,

      pub const Found = struct {
         compositor           : ? * c.wl_compositor               = null,
         xdg_wm_base          : ? * c.xdg_wm_base                 = null,
         seat                 : ? * c.wl_seat                     = null,
         pointer_constraints  : ? * c.zwp_pointer_constraints_v1  = null,

         pub fn unwrap(self : * const @This()) ? WaylandGlobals {
            const globals = WaylandGlobals{
               .compositor          = self.compositor          orelse return null,
               .xdg_wm_base         = self.xdg_wm_base         orelse return null,
               .seat                = self.seat                orelse return null,
               .pointer_constraints = self.pointer_constraints orelse return null,
            };

            return globals;
         }
      };
   };

   const WaylandInputs = struct {
      pointer  : ? * c.wl_pointer = null,
   };

   // Unfortunately we need to store a map of windows and their callback info
   // inside compositor since libwayland input event handlers only give us an
   // affected surface.  TL:DR - This is mitigation for a poorly designed C API.
   // Key is a wl_surface casted with @intFromPtr() so it can work with the
   // hash map.  Synchronization is required since an event could access while
   // a window is being inserted.
   const WaylandInputCallbacks = struct {
      mutex       : std.Thread.Mutex = .{},
      surface_map : std.AutoHashMapUnmanaged(usize, * Window._Callbacks) = .{},
      pointer     : WaylandPointerInputCallbacks = .{},
   };

   const WaylandPointerInputCallbacks = struct {
      enter_serial   : u32 = undefined,
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

      blk_seat: {
         const MINIMUM_VERSION = 1;

         if (c.strcmp(interface, c.wl_seat_interface.name) != 0) {
            break :blk_seat;
         }

         if (version < MINIMUM_VERSION) {
            return;
         }

         const wl_interface = c.wl_registry_bind(wl_registry, name, &c.wl_seat_interface, MINIMUM_VERSION) orelse return;
         const wl_seat : * c.wl_seat = @ptrCast(@alignCast(wl_interface));

         wl_globals_found.seat = wl_seat;

         return;
      }

      blk_pointer_constraints: {
         const MINIMUM_VERSION = 1;

         if (c.strcmp(interface, c.zwp_pointer_constraints_v1_interface.name) != 0) {
            break :blk_pointer_constraints;
         }

         if (version < MINIMUM_VERSION) {
            return;
         }

         const wl_interface = c.wl_registry_bind(wl_registry, name, &c.zwp_pointer_constraints_v1_interface, MINIMUM_VERSION) orelse return;
         const zwp_pointer_constraints_v1 : * c.zwp_pointer_constraints_v1 = @ptrCast(@alignCast(wl_interface));

         wl_globals_found.pointer_constraints = zwp_pointer_constraints_v1;

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

   fn _waylandSeatListenerCapabilities(p_data : ? * anyopaque, p_wl_seat : ? * c.wl_seat, p_capabilities : u32) callconv(.C) void {
      const wl_inputs      = @as(* WaylandInputs, @ptrCast(@alignCast(p_data orelse unreachable)));
      const wl_seat        = p_wl_seat orelse unreachable;
      const capabilities   = p_capabilities;

      if (capabilities & c.WL_SEAT_CAPABILITY_POINTER != 0) blk: {
         const wl_pointer = c.wl_seat_get_pointer(wl_seat) orelse break :blk;
         wl_inputs.pointer = wl_pointer;
      }

      return;
   }

   fn _waylandSeatListenerName(p_data : ? * anyopaque, p_wl_seat : ? * c.wl_seat, p_name : [*c] const u8) callconv(.C) void {
      _ = p_data;
      _ = p_wl_seat;
      _ = p_name;
      return;
   }
   
   fn _waylandPointerListenerEnter(p_data : ? * anyopaque, p_wl_pointer : ? * c.wl_pointer, p_serial : u32, p_wl_surface : ? * c.wl_surface, p_wl_surface_x : c.wl_fixed_t, p_wl_surface_y : c.wl_fixed_t) callconv(.C) void {
      const wl_input_callbacks   = @as(* WaylandInputCallbacks, @ptrCast(@alignCast(p_data orelse unreachable)));
      const wl_pointer           = p_wl_pointer orelse unreachable;
      const serial               = p_serial;
      const wl_surface           = p_wl_surface orelse unreachable;
      const wl_surface_x         = p_wl_surface_x;
      const wl_surface_y         = p_wl_surface_y;

      wl_input_callbacks.mutex.lock();
      defer wl_input_callbacks.mutex.unlock();

      wl_input_callbacks.pointer.enter_serial = serial;

      const window_callbacks = wl_input_callbacks.surface_map.get(@intFromPtr(wl_surface)) orelse unreachable;

      window_callbacks.mutex.lock();
      defer window_callbacks.mutex.unlock();

      window_callbacks.focused = true;

      _ = wl_pointer;
      _ = wl_surface_x;
      _ = wl_surface_y;

      return;
   }

   fn _waylandPointerListenerLeave(p_data : ? * anyopaque, p_wl_pointer : ? * c.wl_pointer, p_serial : u32, p_wl_surface : ? * c.wl_surface) callconv(.C) void {
      const wl_input_callbacks   = @as(* WaylandInputCallbacks, @ptrCast(@alignCast(p_data orelse unreachable)));
      const wl_pointer           = p_wl_pointer orelse unreachable;
      const serial               = p_serial;
      const wl_surface           = p_wl_surface orelse unreachable;

      wl_input_callbacks.mutex.lock();
      defer wl_input_callbacks.mutex.unlock();

      const window_callbacks = wl_input_callbacks.surface_map.get(@intFromPtr(wl_surface)) orelse unreachable;

      window_callbacks.mutex.lock();
      defer window_callbacks.mutex.unlock();

      window_callbacks.focused = false;

      _ = wl_pointer;
      _ = serial;

      return;
   }

   fn _waylandPointerListenerMotion(p_data : ? * anyopaque, p_wl_pointer : ? * c.wl_pointer, p_time : u32, p_wl_surface_x : c.wl_fixed_t, p_wl_surface_y : c.wl_fixed_t) callconv(.C) void {
      _ = p_data;
      _ = p_wl_pointer;
      _ = p_time;
      _ = p_wl_surface_x;
      _ = p_wl_surface_y;
      return;
   }

   fn _waylandPointerListenerButton(p_data : ? * anyopaque, p_wl_pointer : ? * c.wl_pointer, p_serial : u32, p_time : u32, p_button : u32, p_state : u32) callconv(.C) void {
      _ = p_data;
      _ = p_wl_pointer;
      _ = p_serial;
      _ = p_time;
      _ = p_button;
      _ = p_state;
      return;
   }

   fn _waylandPointerListenerAxis(p_data : ? * anyopaque, p_wl_pointer : ? * c.wl_pointer, p_time : u32, p_axis : u32, p_value : c.wl_fixed_t) callconv(.C) void {
      _ = p_data;
      _ = p_wl_pointer;
      _ = p_time;
      _ = p_axis;
      _ = p_value;
      return;
   }

   fn _waylandPointerListenerFrame(p_data : ? * anyopaque, p_wl_pointer : ? * c.wl_pointer) callconv(.C) void {
      _ = p_data;
      _ = p_wl_pointer;
      return;
   }

   fn _waylandPointerListenerAxisSource(p_data : ? * anyopaque, p_wl_pointer : ? * c.wl_pointer, p_axis_source : u32) callconv(.C) void {
      _ = p_data;
      _ = p_wl_pointer;
      _ = p_axis_source;
      return;
   }

   fn _waylandPointerListenerAxisStop(p_data : ? * anyopaque, p_wl_pointer : ? * c.wl_pointer, p_time : u32, p_axis : u32) callconv(.C) void {
      _ = p_data;
      _ = p_wl_pointer;
      _ = p_time;
      _ = p_axis;
      return;
   }

   fn _waylandPointerListenerAxisDiscrete(p_data : ? * anyopaque, p_wl_pointer : ? * c.wl_pointer, p_axis : u32, p_discrete : i32) callconv(.C) void {
      _ = p_data;
      _ = p_wl_pointer;
      _ = p_axis;
      _ = p_discrete;
      return;
   }

   fn _waylandPointerListenerAxisValue120(p_data : ? * anyopaque, p_wl_pointer : ? * c.wl_pointer, p_axis : u32, p_discrete : i32) callconv(.C) void {
      _ = p_data;
      _ = p_wl_pointer;
      _ = p_axis;
      _ = p_discrete;
      return;
   }

   fn _waylandPointerListenerAxisRelativeDirection(p_data : ? * anyopaque, p_wl_pointer : ? * c.wl_pointer, p_axis : u32, p_direction : u32) callconv(.C) void {
      _ = p_data;
      _ = p_wl_pointer;
      _ = p_axis;
      _ = p_direction;
      return;
   }

   pub fn disconnect(self : @This(), allocator : std.mem.Allocator) void {
      self._wl_input_callbacks.surface_map.deinit(allocator);
      allocator.destroy(self._wl_input_callbacks);
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
   _compositor          : * Compositor,
   _wl_surface          : * c.wl_surface,
   _xdg_surface         : * c.xdg_surface,
   _xdg_toplevel        : * c.xdg_toplevel,
   _callbacks           : * _Callbacks,
   _cursor_grabbed_old  : bool,
   _cursor_grabbed      : bool,

   const _Callbacks = struct {
      mutex                : std.Thread.Mutex = .{},
      current_resolution   : f_shared.Window.Resolution = .{.width = 0, .height = 0},
      should_close         : bool = false,
      focused_old          : bool = false,
      focused              : bool = false,
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

      switch (create_info.display_mode) {
         .windowed   => |resolution| {
            _ = c.xdg_toplevel_unset_fullscreen(xdg_toplevel);
            
            // TODO: Initial resolution?
            _ = resolution;
         },
        .fullscreen => {
            _ = c.xdg_toplevel_set_fullscreen(xdg_toplevel, null);
         },
      }

      c.xdg_toplevel_set_title(xdg_toplevel, create_info.title.ptr);
      c.xdg_toplevel_set_app_id(xdg_toplevel, create_info.title.ptr);

      _ = c.wl_surface_commit(wl_surface);
      _ = c.wl_display_roundtrip(compositor._wl_display);
      _ = c.wl_surface_commit(wl_surface);

      compositor._wl_input_callbacks.mutex.lock();
      defer compositor._wl_input_callbacks.mutex.unlock();

      const surface_map_key = @intFromPtr(wl_surface);

      try compositor._wl_input_callbacks.surface_map.put(allocator, surface_map_key, callbacks);

      return @This(){
         ._compositor         = compositor,
         ._wl_surface         = wl_surface,
         ._xdg_surface        = xdg_surface,
         ._xdg_toplevel       = xdg_toplevel,
         ._callbacks          = callbacks,
         ._cursor_grabbed_old = false,
         ._cursor_grabbed     = false,
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
      const surface_removed = self._compositor._wl_input_callbacks.surface_map.remove(@intFromPtr(self._wl_surface));
      if (std.debug.runtime_safety == true and surface_removed == false) {
         @panic("attempted to remove nonexistent surface from compositor surface map");
      }

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

   pub fn setCursorGrabbed(self : * @This(), grabbed : bool) void {
      if (self._cursor_grabbed == grabbed) {
         return;
      }

      // Since we have to wait for the cursor to enter our window (to get a
      // valid serial), we defer the cursor setting to pollEvents() and check
      // if the window is focused, which garuntees a valid serial.
      self._cursor_grabbed_old   = self._cursor_grabbed;
      self._cursor_grabbed       = grabbed;

      return;
   }

   pub fn shouldClose(self : * const @This()) bool {
      self._callbacks.mutex.lock();
      defer self._callbacks.mutex.unlock();

      return self._callbacks.should_close;
   }

   pub fn isCursorGrabbed(self : * const @This()) bool {
      return self._cursor_grabbed;
   }

   pub fn isFocused(self : * const @This()) bool {
      self._callbacks.mutex.lock();
      defer self._callbacks.mutex.unlock();

      return self._callbacks.focused;
   }

   pub fn pollEvents(self : * @This()) f_shared.Window.PollEventsError!void {
      _ = c.wl_display_roundtrip(self._compositor._wl_display);

      self._callbacks.mutex.lock();
      defer self._callbacks.mutex.unlock();

      if (self._callbacks.focused == true) {
         // If the cursor re-entered the window while grabbed, we have to
         // update the cursor icon to be hidden again.
         if (self._callbacks.focused_old == false and self._cursor_grabbed == true) {
            _changeCursorVisibility(self, true);
         }

         // If a cursor state change was issued, run it
         if (self._cursor_grabbed_old != self._cursor_grabbed) {
            _changeCursorVisibility(self, self._cursor_grabbed);
         }

         // TODO: Cursor locking?  Lock to center of surface
      }

      self._callbacks.focused_old = self._callbacks.focused;
      self._cursor_grabbed_old = self._cursor_grabbed;

      return;
   }

   fn _changeCursorVisibility(self : * const @This(), hidden : bool) void {
      self._compositor._wl_input_callbacks.mutex.lock();
      defer self._compositor._wl_input_callbacks.mutex.unlock();
      
      // We use 'orelse unreachable' on wl_pointer because this function should
      // only ever be called when the cursor is entered into a window, thus we
      // know wl_pointer is not null.
      const wl_pointer              = self._compositor._wl_inputs.pointer orelse unreachable;
      const wl_pointer_enter_serial = self._compositor._wl_input_callbacks.pointer.enter_serial;

      // TODO: Implement the unhiding part.  This is made annoying as we need
      // to create a wl_surface and wl_buffer to then populate with the default
      // cursor's pixel data.  Passing 'null' for the surface hides the cursor.
      switch (hidden) {
         true  => c.wl_pointer_set_cursor(wl_pointer, wl_pointer_enter_serial, null, 0, 0),
         false => c.wl_pointer_set_cursor(wl_pointer, wl_pointer_enter_serial, null, 0, 0),
      }

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
};

