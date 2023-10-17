const std         = @import("std");
const f_input     = @import("input.zig");
const f_renderer  = @import("renderer.zig");
const c           = @cImport({
   @cInclude("vulkan/vulkan.h");
   @cInclude("GLFW/glfw3.h");
});

pub const Compositor = struct {
   pub const ConnectError = error {
      PlatformError,
   };

   pub fn connect_default() ConnectError!@This() {
      if (c.glfwInit() != c.GLFW_FALSE) {
         return @This(){};
      }

      switch (c.glfwGetError(null)) {
         c.GLFW_PLATFORM_ERROR   => return error.PlatformError,
         else                    => unreachable,
      }

      unreachable;
   }

   pub fn disconnect(self : @This()) void {
      c.glfwTerminate();
      _ = self;
      return;
   }

   pub fn createWindow(self : * const @This(), allocator : std.mem.Allocator, create_options : Window.CreateOptions) Window.CreateError!Window {
      return Window.create(self, allocator, create_options);
   }
};

pub const Window = struct {
   _allocator     : std.mem.Allocator,
   _glfw_window   : * c.GLFWwindow,
   _input         : f_input.InputState,

   pub const CreateOptions = struct {
      title          : [*:0] const u8,
      resolution     : Resolution,
      display_mode   : DisplayMode,
      decorations    : bool,
   };

   pub const Resolution = struct {
      width    : u32,
      height   : u32,
   };

   pub const DisplayMode = enum {
      Windowed,
      Fullscreen,
   };

   pub const CreateError = error {
      OutOfMemory,
      WindowDimensionsOutOfBounds,
      NoFullscreenMonitorAvailable,
      GraphicsApiUnavailable,
      PixelFormatUnavailable,
      PlatformError,
   };

   pub const EventPollError = error {
      PlatformError,
   };

   pub fn create(compositor : * const Compositor, allocator : std.mem.Allocator, create_options : CreateOptions) CreateError!@This() {
      _ = compositor;

      if (create_options.resolution.width > std.math.maxInt(c_int)) {
         return error.WindowDimensionsOutOfBounds;
      }
      if (create_options.resolution.height > std.math.maxInt(c_int)) {
         return error.WindowDimensionsOutOfBounds;
      }

      const glfw_window_width    : c_int = @intCast(create_options.resolution.width);
      const glfw_window_height   : c_int = @intCast(create_options.resolution.height);

      const glfw_monitor = blk: {
         switch (create_options.display_mode) {
            .Windowed   => break :blk null,
            .Fullscreen => break :blk c.glfwGetPrimaryMonitor() orelse return error.NoFullscreenMonitorAvailable,
         }
      };

      _ = c.glfwWindowHint(c.GLFW_DECORATED, blk: {
         switch (create_options.decorations) {
            true  => break :blk c.GLFW_TRUE,
            false => break :blk c.GLFW_FALSE,
         }
      });

      _ = c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
      _ = c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_TRUE);

      const glfw_window = c.glfwCreateWindow(
         glfw_window_width,
         glfw_window_height,
         create_options.title,
         glfw_monitor,
         null,
      ) orelse {
         switch (c.glfwGetError(null)) {
            c.GLFW_NOT_INITIALIZED     => unreachable,
            c.GLFW_INVALID_ENUM        => unreachable,
            c.GLFW_INVALID_VALUE       => unreachable,
            c.GLFW_API_UNAVAILABLE     => return error.GraphicsApiUnavailable,
            c.GLFW_VERSION_UNAVAILABLE => return error.GraphicsApiUnavailable,
            c.GLFW_FORMAT_UNAVAILABLE  => return error.PixelFormatUnavailable,
            c.GLFW_PLATFORM_ERROR      => return error.PlatformError,
            else                       => unreachable,
         }
      };

      const input = f_input.InputState.create();

      return @This(){
         ._allocator    = allocator,
         ._glfw_window  = glfw_window,
         ._input        = input,
      };
   }

   pub fn destroy(self : @This()) void {
      c.glfwDestroyWindow(self._glfw_window);
      return;
   }

   pub fn getFramebufferSize(self : * const @This()) Resolution {
      var width   : c_int = undefined;
      var height  : c_int = undefined;
      c.glfwGetFramebufferSize(self._glfw_window, &width, &height);

      return Resolution{
         .width   = @intCast(width),
         .height  = @intCast(height),
      };
   }

   pub fn shouldClose(self : * const @This()) bool {
      switch (c.glfwWindowShouldClose(self._glfw_window)) {
         c.GLFW_FALSE   => return false,
         c.GLFW_TRUE    => return true,
         else           => unreachable,
      }

      unreachable;
   }

   pub fn setShouldClose(self : * @This(), should_close : bool) void {
      c.glfwSetWindowShouldClose(self._glfw_window, blk: {
         switch (should_close) {
            false => break :blk c.GLFW_FALSE,
            true  => break :blk c.GLFW_TRUE,
         }
      });

      return;
   }

   pub fn createVulkanSurface(
      self        : * const @This(),
      instance    : c.VkInstance,
      allocator   : * const c.VkAllocationCallbacks,
      surface     : * c.VkSurfaceKHR,
   ) c.VkResult {
      return c.glfwCreateWindowSurface(instance, self._glfw_window, allocator, surface);
   }

   pub fn pollEvents(self : * @This()) EventPollError!void {
      c.glfwPollEvents();
      switch (c.glfwGetError(null)) {
         c.GLFW_NO_ERROR         => {},
         c.GLFW_PLATFORM_ERROR   => return error.PlatformError,
         else                    => unreachable,
      }

      self._input.advance();

      // Ideally we would have runtime bindings for keys, but hard-coding it
      // works for our use-case.

      const KeyBinding = struct {
         button   : f_input.Button,
         bind     : c_int,
      };

      const GLFW_KEYBINDS = [_] KeyBinding {
         .{
            .button  = .exit,
            .bind    = c.GLFW_KEY_ESCAPE,
         },
      };

      for (GLFW_KEYBINDS) |mapping| {
         switch (c.glfwGetKey(self._glfw_window, mapping.bind)) {
            c.GLFW_PRESS   => self._input.buttons.press(mapping.button),
            c.GLFW_RELEASE => self._input.buttons.release(mapping.button),
            else           => unreachable,
         }
      }

      return;
   }

   pub fn getInput(self : * const @This()) * const f_input.InputState {
      return &self._input;
   }

   pub fn createRenderer(self : * const @This(), allocator : std.mem.Allocator, create_options : f_renderer.Renderer.CreateOptions) f_renderer.Renderer.CreateError!f_renderer.Renderer {
      return f_renderer.Renderer.create(self, allocator, create_options);
   }
};

