const root     = @import("index.zig");
const std      = @import("std");
const present  = @import("present");
const c        = @import("cimports");

pub const SwapchainConfiguration = struct {
   capabilities   : c.VkSurfaceCapabilitiesKHR,
   format         : c.VkSurfaceFormatKHR,
   present_mode   : c.VkPresentModeKHR,
   extent         : c.VkExtent2D,

   pub const SelectInfo = struct {
      vk_physical_device   : c.VkPhysicalDevice,
      vk_surface           : c.VkSurfaceKHR,
      window               : * const present.Window,
      present_mode_desired : c.VkPresentModeKHR,
   };

   pub const SelectError = error {
      OutOfMemory,
      SurfaceLost,
   };

   pub fn selectMostSuitable(allocator : std.mem.Allocator, select_info : * const SelectInfo) SelectError!?@This() {
      _ = allocator;
      _ = select_info;
      unreachable;
   }
};

