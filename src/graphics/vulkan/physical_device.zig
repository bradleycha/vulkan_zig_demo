const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const QueueFamilyIndices = struct {
   graphics : u32,
};

pub const PhysicalDevice = struct {
   vk_physical_device                     : c.VkPhysicalDevice,
   vk_physical_device_properties          : c.VkPhysicalDeviceProperties,
   vk_physical_device_features            : c.VkPhysicalDeviceFeatures,
   vk_physical_device_memory_properties   : c.VkPhysicalDeviceMemoryProperties,
   queue_family_indices                   : QueueFamilyIndices,

   pub const SelectInfo = struct {
      vk_instance : c.VkInstance,
      extensions  : [] const [*:0] const u8,
   };

   pub const SelectError = error {
      OutOfMemory,
      Unknown,
      NoneAvailable,
   };

   pub fn selectMostSuitable(allocator : std.mem.Allocator, select_info : * const SelectInfo) SelectError!@This() {
      const vk_instance = select_info.vk_instance;

      const vk_physical_devices = try _enumeratePhysicalDevices(allocator, vk_instance);
      defer allocator.free(vk_physical_devices);

      var chosen_physical_device : ? @This() = null;
      var chosen_physical_device_score : u32 = 0;

      for (vk_physical_devices) |vk_physical_device| {
         const physical_device = try _parsePhysicalDevice(
            allocator,
            vk_physical_device,
            select_info.extensions,
         ) orelse continue;

         const physical_device_score = physical_device._assignScore();

         if (chosen_physical_device != null and physical_device_score <= chosen_physical_device_score) {
            continue;
         }

         chosen_physical_device        = physical_device;
         chosen_physical_device_score  = physical_device_score;
      }

      const physical_device = chosen_physical_device orelse return error.NoneAvailable;

      std.log.info("using vulkan physical device \"{s}\" for rendering", .{physical_device.vk_physical_device_properties.deviceName});

      return physical_device;
   }

   fn _parsePhysicalDevice(allocator : std.mem.Allocator, vk_physical_device : c.VkPhysicalDevice, enabled_extensions : [] const [*:0] const u8) SelectError!?@This() {
      _ = allocator;
      _ = vk_physical_device;
      _ = enabled_extensions;
      unreachable;
   }

   fn _assignScore(self : * const @This()) u32 {
      var score : u32 = 0;

      // In the future we will use a more complex scoring method.
      // For now, just simply prefer a discrete GPU.
      if (self.vk_physical_device_properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
         score += 1;
      }

      return score;
   }
};

fn _enumeratePhysicalDevices(allocator : std.mem.Allocator, vk_instance : c.VkInstance) PhysicalDevice.SelectError![] c.VkPhysicalDevice {
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

