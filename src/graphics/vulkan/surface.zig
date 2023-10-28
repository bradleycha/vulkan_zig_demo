const root     = @import("index.zig");
const std      = @import("std");
const present  = @import("present");
const c        = @import("cimports");

pub const Surface = struct {
   vk_surface : c.VkSurfaceKHR,

   pub const CreateInfo = struct {
      vk_instance : c.VkInstance,
      window      : * present.Window,
   };

   pub const CreateError = error {
      PlatformError,
   };

   pub fn create(create_info : * const CreateInfo) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const vk_instance = create_info.vk_instance;
      const window      = create_info.window;

      var vk_surface : c.VkSurfaceKHR = undefined;
      vk_result = window.vulkanCreateSurface(vk_instance, null, &vk_surface);
      switch (vk_result) {
         c.VK_SUCCESS   => {},
         else           => return error.PlatformError,
      }
      errdefer c.vkDestroySurfaceKHR(vk_instance, vk_surface, null);

      return @This(){
         .vk_surface = vk_surface,
      };
   }

   pub fn destroy(self : @This(), vk_instance : c.VkInstance) void {
      c.vkDestroySurfaceKHR(vk_instance, self.vk_surface, null);
      return;
   }
};

