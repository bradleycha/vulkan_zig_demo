const root     = @import("index.zig");
const std      = @import("std");
const present  = @import("present");
const c        = @import("cimports");

pub const QueueFamilyIndices = struct {
   graphics : u32,
   transfer : u32,
   present  : u32,

   pub const INFO = struct {
      pub const Count = @typeInfo(QueueFamilyIndices).Struct.fields.len;
      pub const Index = struct {
         pub const Graphics   = 0;
         pub const Transfer   = 1;
         pub const Present    = 2;
      };
   };
};

pub const PhysicalDevice = struct {
   vk_physical_device                     : c.VkPhysicalDevice,
   vk_physical_device_properties          : c.VkPhysicalDeviceProperties,
   vk_physical_device_features            : c.VkPhysicalDeviceFeatures,
   vk_physical_device_memory_properties   : c.VkPhysicalDeviceMemoryProperties,
   queue_family_indices                   : QueueFamilyIndices,
   depth_buffer_format                    : c.VkFormat,
};

pub const PhysicalDeviceSelection = struct {
   physical_device         : PhysicalDevice,
   swapchain_configuration : root.SwapchainConfiguration,

   pub const SelectInfo = struct {
      vk_instance          : c.VkInstance,
      vk_surface           : c.VkSurfaceKHR,
      window               : * const present.Window,
      present_mode_desired : c.VkPresentModeKHR,
      extensions           : [] const [*:0] const u8,
   };

   pub const SelectError = error {
      OutOfMemory,
      Unknown,
      SurfaceLost,
      NoneAvailable,
   };

   pub fn selectMostSuitable(allocator : std.mem.Allocator, select_info : * const SelectInfo) SelectError!@This() {
      const vk_physical_devices = try _enumeratePhysicalDevices(allocator, select_info.vk_instance);
      defer allocator.free(vk_physical_devices);

      var chosen_selection : ? @This() = null;
      var chosen_physical_device_score : u32 = undefined;

      for (vk_physical_devices) |vk_physical_device| {
         const selection = try _parseSelection(allocator, vk_physical_device, select_info) orelse continue;

         const physical_device_score = _assignPhysicalDeviceScore(&selection.physical_device);

         if (chosen_selection != null and physical_device_score <= chosen_physical_device_score) {
            continue;
         }

         chosen_selection              = selection;
         chosen_physical_device_score  = physical_device_score;
      }

      const selection = chosen_selection orelse return error.NoneAvailable;

      std.log.info("using vulkan physical device \"{s}\" for rendering", .{selection.physical_device.vk_physical_device_properties.deviceName});

      return selection;
   }

   fn _parseSelection(allocator : std.mem.Allocator, vk_physical_device : c.VkPhysicalDevice, select_info : * const SelectInfo) SelectError!?@This() {
      var vk_physical_device_properties : c.VkPhysicalDeviceProperties = undefined;
      c.vkGetPhysicalDeviceProperties(vk_physical_device, &vk_physical_device_properties);

      var vk_physical_device_features : c.VkPhysicalDeviceFeatures = undefined;
      c.vkGetPhysicalDeviceFeatures(vk_physical_device, &vk_physical_device_features);

      var vk_physical_device_memory_properties : c.VkPhysicalDeviceMemoryProperties = undefined;
      c.vkGetPhysicalDeviceMemoryProperties(vk_physical_device, &vk_physical_device_memory_properties);

      const vk_physical_device_name = &vk_physical_device_properties.deviceName;

      std.log.info("attempting to enumerate vulkan physical device \"{s}\"", .{vk_physical_device_name});

      if (try _checkExtensionsPresent(allocator, vk_physical_device, select_info.extensions) == false) {
         std.log.info("vulkan physical device \"{s}\" does not support enabled extensions, choosing new device", .{vk_physical_device_name});
         return null;
      }

      const queue_family_indices = try _selectQueueFamilyIndices(allocator, vk_physical_device, select_info.vk_surface) orelse {
         std.log.info("vulkan physical device \"{s}\" does not support required queue families, choosing new device" , .{vk_physical_device_name});
         return null;
      };

      const depth_buffer_format = _selectDepthBufferFormat(vk_physical_device) orelse {
         std.log.info("vulkan physical device \"{s}\" does not support a valid depth buffer format, choosing new device", .{vk_physical_device_name});
         return null;
      };

      const physical_device = PhysicalDevice{
         .vk_physical_device                    = vk_physical_device,
         .vk_physical_device_properties         = vk_physical_device_properties,
         .vk_physical_device_features           = vk_physical_device_features,
         .vk_physical_device_memory_properties  = vk_physical_device_memory_properties,
         .queue_family_indices                  = queue_family_indices,
         .depth_buffer_format                   = depth_buffer_format,
      };

      const swapchain_configuration = try root.SwapchainConfiguration.selectMostSuitable(allocator, &.{
         .vk_physical_device     = vk_physical_device,
         .vk_surface             = select_info.vk_surface,
         .window                 = select_info.window,
         .present_mode_desired   = select_info.present_mode_desired,
      }) orelse {
         std.log.info("vulkan physical device \"{s}\" does not support required swapchain configuration, choosing new device", .{vk_physical_device_name});
         return null;
      };

      return PhysicalDeviceSelection{
         .physical_device           = physical_device,
         .swapchain_configuration   = swapchain_configuration,
      };
   }
};

fn _enumeratePhysicalDevices(allocator : std.mem.Allocator, vk_instance : c.VkInstance) PhysicalDeviceSelection.SelectError![] c.VkPhysicalDevice {
   var vk_result : c.VkResult = undefined;

   var vk_physical_devices_count : u32 = undefined;
   vk_result = c.vkEnumeratePhysicalDevices(vk_instance, &vk_physical_devices_count, null);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_INITIALIZATION_FAILED => return error.Unknown,
      else                             => unreachable,
   }

   var vk_physical_devices = try allocator.alloc(c.VkPhysicalDevice, @as(usize, vk_physical_devices_count));
   errdefer allocator.free(vk_physical_devices);
   vk_result = c.vkEnumeratePhysicalDevices(vk_instance, &vk_physical_devices_count, vk_physical_devices.ptr);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_INITIALIZATION_FAILED => return error.Unknown,
      else                             => unreachable,
   }

   return vk_physical_devices;
}

fn _checkExtensionsPresent(allocator : std.mem.Allocator, vk_physical_device : c.VkPhysicalDevice, enabled_extensions : [] const [*:0] const u8) PhysicalDeviceSelection.SelectError!bool {
   var vk_result : c.VkResult = undefined;

   var vk_extensions_available_count : u32 = undefined;
   vk_result = c.vkEnumerateDeviceExtensionProperties(vk_physical_device, null, &vk_extensions_available_count, null);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable,
      else                             => unreachable,
   }

   var vk_extensions_available = try allocator.alloc(c.VkExtensionProperties, @as(usize, vk_extensions_available_count));
   defer allocator.free(vk_extensions_available);
   vk_result = c.vkEnumerateDeviceExtensionProperties(vk_physical_device, null, &vk_extensions_available_count, vk_extensions_available.ptr);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable,
      else                             => unreachable,
   }

   var everything_found = true;
   for (enabled_extensions) |enabled_extension| {
      var found = false;
      for (vk_extensions_available) |vk_extension_available| {
         if (c.strcmp(&vk_extension_available.extensionName, enabled_extension) == 0) {
            found = true;
            break;
         }
      }
      if (found == false) {
         everything_found = false;
         std.log.info("missing required vulkan device extension \"{s}\"", .{enabled_extension});
      }
   }

   return everything_found;
}

fn _selectQueueFamilyIndices(allocator : std.mem.Allocator, vk_physical_device : c.VkPhysicalDevice, vk_surface : c.VkSurfaceKHR) PhysicalDeviceSelection.SelectError!?QueueFamilyIndices {
   var vk_result : c.VkResult = undefined;

   var vk_physical_device_queue_families_count : u32 = undefined;
   c.vkGetPhysicalDeviceQueueFamilyProperties(vk_physical_device, &vk_physical_device_queue_families_count, null);

   var vk_physical_device_queue_families = try allocator.alloc(c.VkQueueFamilyProperties, @as(usize, vk_physical_device_queue_families_count));
   defer allocator.free(vk_physical_device_queue_families);
   c.vkGetPhysicalDeviceQueueFamilyProperties(vk_physical_device, &vk_physical_device_queue_families_count, vk_physical_device_queue_families.ptr);

   var queue_family_indices_found = [1] ? u32 {null} ** QueueFamilyIndices.INFO.Count;

   for (vk_physical_device_queue_families, 0..vk_physical_device_queue_families_count) |vk_physical_device_queue_family, vk_physical_device_queue_family_index_raw| {
      const vk_physical_device_queue_family_index : u32 = @intCast(vk_physical_device_queue_family_index_raw);

      var queue_families_found = [1] bool {false} ** QueueFamilyIndices.INFO.Count;

      var vk_queue_family_supports_presentation : c.VkBool32 = undefined;
      vk_result = c.vkGetPhysicalDeviceSurfaceSupportKHR(vk_physical_device, vk_physical_device_queue_family_index, vk_surface, &vk_queue_family_supports_presentation);
      switch (vk_result) {
         c.VK_SUCCESS => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
         else                             => unreachable,
      }

      if (vk_physical_device_queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
         queue_families_found[QueueFamilyIndices.INFO.Index.Graphics]   = true;
      }
      if (vk_physical_device_queue_family.queueFlags & c.VK_QUEUE_TRANSFER_BIT != 0) {
         queue_families_found[QueueFamilyIndices.INFO.Index.Transfer]   = true;
      }
      if (vk_queue_family_supports_presentation != c.VK_FALSE) {
         queue_families_found[QueueFamilyIndices.INFO.Index.Present]    = true;
      }

      _assignUniqueQueueFamilyIndices(vk_physical_device_queue_family_index, &queue_families_found, &queue_family_indices_found);
   }

   const queue_family_indices = QueueFamilyIndices{
      .graphics   = queue_family_indices_found[QueueFamilyIndices.INFO.Index.Graphics] orelse return null,
      .transfer   = queue_family_indices_found[QueueFamilyIndices.INFO.Index.Transfer] orelse return null,
      .present    = queue_family_indices_found[QueueFamilyIndices.INFO.Index.Present]  orelse return null,
   };

   return queue_family_indices;
}

fn _assignUniqueQueueFamilyIndices(vk_physical_device_queue_family_index : u32, queue_families_found : * const [QueueFamilyIndices.INFO.Count] bool, queue_family_indices_found : * [QueueFamilyIndices.INFO.Count] ? u32) void {
   for (queue_families_found, queue_family_indices_found) |queue_family_found, *queue_family_index| {
      if (queue_family_found == false) {
         continue;
      }

      if (queue_family_index.* == null) {
         queue_family_index.* = vk_physical_device_queue_family_index;
         continue;
      }

      var queue_family_index_already_in_use = false;
      for (queue_family_indices_found) |*queue_family_index_existing| {
         if (queue_family_index_existing == queue_family_index) {
            continue;
         }

         if (queue_family_index_existing.* == null) {
            continue;
         }

         if (queue_family_index_existing.* orelse unreachable == queue_family_index.* orelse unreachable) {
            queue_family_index_already_in_use = true;
            break;
         }
      }

      if (queue_family_index_already_in_use == true) {
         queue_family_index.* = vk_physical_device_queue_family_index;
         continue;
      }
   }

   return;
}

fn _selectDepthBufferFormat(vk_physical_device : c.VkPhysicalDevice) ? c.VkFormat {
   // Desired formats, in order from most to least desireable
   const depth_buffer_formats = [_] c.VkFormat {
      c.VK_FORMAT_D32_SFLOAT,
      c.VK_FORMAT_D32_SFLOAT_S8_UINT,
      c.VK_FORMAT_D24_UNORM_S8_UINT,
   };

   for (&depth_buffer_formats) |depth_buffer_format| {
      if (_imageFormatSupported(
         vk_physical_device,
         depth_buffer_format,
         c.VK_IMAGE_TILING_OPTIMAL,
         c.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT,
      ) == true) {
         return depth_buffer_format;
      }
   }

   return null;
}

fn _imageFormatSupported(vk_physical_device : c.VkPhysicalDevice, vk_format : c.VkFormat, vk_image_tiling : c.VkImageTiling, vk_format_feature_flags : c.VkFormatFeatureFlags) bool {
   var vk_format_properties : c.VkFormatProperties = undefined;
   c.vkGetPhysicalDeviceFormatProperties(vk_physical_device, vk_format, &vk_format_properties);

   switch (vk_image_tiling) {
      c.VK_IMAGE_TILING_LINEAR => {
         return vk_format_properties.linearTilingFeatures & vk_format_feature_flags == vk_format_feature_flags;
      },
      c.VK_IMAGE_TILING_OPTIMAL => {
         return vk_format_properties.optimalTilingFeatures & vk_format_feature_flags == vk_format_feature_flags;
      },
      else => {
         return false;
      },
   }

   unreachable;
}

fn _assignPhysicalDeviceScore(physical_device : * const PhysicalDevice) u32 {
   var score : u32 = 0;

   if (physical_device.vk_physical_device_properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
      score += 1;
   }
   if (physical_device.vk_physical_device_features.samplerAnisotropy == c.VK_TRUE) {
      score += 1;
   }

   return score;
}

