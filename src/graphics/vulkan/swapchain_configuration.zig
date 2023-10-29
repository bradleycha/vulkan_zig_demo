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
      const vk_physical_device   = select_info.vk_physical_device;
      const vk_surface           = select_info.vk_surface;
      const window               = select_info.window;
      const present_mode_desired = select_info.present_mode_desired;

      const capabilities = try _getPhysicalDeviceSurfaceCapabilities(vk_physical_device, vk_surface);

      const format = try _chooseBestSurfaceFormat(allocator, vk_physical_device, vk_surface) orelse return null;

      const present_mode_available = try _presentModeAvailable(allocator, vk_physical_device, vk_surface, present_mode_desired);

      if (present_mode_available == false) {
         return null;
      }

      const extent = _chooseExtent(&capabilities, window);

      return @This(){
         .capabilities  = capabilities,
         .format        = format,
         .present_mode  = present_mode_desired,
         .extent        = extent,
      };
   }
};

fn _getPhysicalDeviceSurfaceCapabilities(vk_physical_device : c.VkPhysicalDevice, vk_surface : c.VkSurfaceKHR) SwapchainConfiguration.SelectError!c.VkSurfaceCapabilitiesKHR {
   var vk_result : c.VkResult = undefined;

   var vk_surface_capabilities : c.VkSurfaceCapabilitiesKHR = undefined;
   vk_result = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vk_physical_device, vk_surface, &vk_surface_capabilities);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
      else                             => unreachable,
   }

   return vk_surface_capabilities;
}

fn _chooseBestSurfaceFormat(allocator : std.mem.Allocator, vk_physical_device : c.VkPhysicalDevice, vk_surface : c.VkSurfaceKHR) SwapchainConfiguration.SelectError!?c.VkSurfaceFormatKHR {
   var vk_result : c.VkResult = undefined;

   var vk_surface_formats_count : u32 = undefined;
   vk_result = c.vkGetPhysicalDeviceSurfaceFormatsKHR(vk_physical_device, vk_surface, &vk_surface_formats_count, null);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
      else                             => unreachable,
   }

   var vk_surface_formats = try allocator.alloc(c.VkSurfaceFormatKHR, @as(usize, vk_surface_formats_count));
   defer allocator.free(vk_surface_formats);
   vk_result = c.vkGetPhysicalDeviceSurfaceFormatsKHR(vk_physical_device, vk_surface, &vk_surface_formats_count, vk_surface_formats.ptr);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
      else                             => unreachable,
   }

   var chosen_vk_surface_format : ? c.VkSurfaceFormatKHR = null;
   var chosen_vk_surface_format_score : u32 = undefined;
   for (vk_surface_formats) |vk_surface_format| {
      const vk_surface_format_score = _assignSurfaceFormatScore(vk_surface_format);

      if (chosen_vk_surface_format != null and vk_surface_format_score <= chosen_vk_surface_format_score) {
         continue;
      }

      chosen_vk_surface_format         = vk_surface_format;
      chosen_vk_surface_format_score   = vk_surface_format_score;
   }

   const vk_surface_format = chosen_vk_surface_format orelse return null;

   return vk_surface_format;
}

fn _assignSurfaceFormatScore(vk_surface_format : c.VkSurfaceFormatKHR) u32 {
   var score : u32 = 0;

   // For now, we simply highly prefer 8-bit SRGB format with SRGB nonlinear colorspace.
   if (vk_surface_format.format == c.VK_FORMAT_B8G8R8A8_SRGB) {
      score += 1;
   }
   if (vk_surface_format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
      score += 1;
   }
   
   return score;
}

fn _presentModeAvailable(allocator : std.mem.Allocator, vk_physical_device : c.VkPhysicalDevice, vk_surface : c.VkSurfaceKHR, vk_present_mode_desired : c.VkPresentModeKHR) SwapchainConfiguration.SelectError!bool {
   var vk_result : c.VkResult = undefined;

   var vk_present_modes_count : u32 = undefined;
   vk_result = c.vkGetPhysicalDeviceSurfacePresentModesKHR(vk_physical_device, vk_surface, &vk_present_modes_count, null);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
      else                             => unreachable,
   }

   var vk_present_modes = try allocator.alloc(c.VkPresentModeKHR, @as(usize, vk_present_modes_count));
   defer allocator.free(vk_present_modes);
   vk_result = c.vkGetPhysicalDeviceSurfacePresentModesKHR(vk_physical_device, vk_surface, &vk_present_modes_count, vk_present_modes.ptr);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
      else                             => unreachable,
   }

   for (vk_present_modes) |vk_present_mode| {
      if (vk_present_mode == vk_present_mode_desired) {
         return true;
      }
   }

   return false;
}

fn _chooseExtent(vk_surface_capabilities : * const c.VkSurfaceCapabilitiesKHR, window : * const present.Window) c.VkExtent2D {
   const extent_current = &vk_surface_capabilities.currentExtent;
   const extent_minimum = &vk_surface_capabilities.minImageExtent;
   const extent_maximum = &vk_surface_capabilities.maxImageExtent;

   if (extent_current.width != std.math.maxInt(u32) and extent_current.height != std.math.maxInt(u32)) {
      return extent_current.*;
   }

   const window_resolution = window.getResolution();

   const window_extent = c.VkExtent2D{
      .width   = std.math.clamp(window_resolution.width, extent_minimum.width, extent_maximum.width),
      .height  = std.math.clamp(window_resolution.height, extent_minimum.height, extent_maximum.height),
   };

   return window_extent;
}

