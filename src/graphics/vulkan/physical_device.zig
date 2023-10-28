const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const QueueFamilyIndices = struct {
   graphics : u32,
   transfer : u32,

   pub const INFO = struct {
      pub const Count = 2;
      pub const Index = struct {
         pub const Graphics   = 0;
         pub const Transfer   = 1;
      };
   };
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
      var vk_physical_device_properties : c.VkPhysicalDeviceProperties = undefined;
      c.vkGetPhysicalDeviceProperties(vk_physical_device, &vk_physical_device_properties);

      var vk_physical_device_features : c.VkPhysicalDeviceFeatures = undefined;
      c.vkGetPhysicalDeviceFeatures(vk_physical_device, &vk_physical_device_features);

      var vk_physical_device_memory_properties : c.VkPhysicalDeviceMemoryProperties = undefined;
      c.vkGetPhysicalDeviceMemoryProperties(vk_physical_device, &vk_physical_device_memory_properties);

      const vk_physical_device_name = &vk_physical_device_properties.deviceName;

      std.log.info("attempting to enumerate vulkan physical device \"{s}\"", .{vk_physical_device_name});

      if (try _checkExtensionsPresent(allocator, vk_physical_device, enabled_extensions) == false) {
         std.log.info("vulkan physical device \"{s}\" does not support enabled extensions, choosing new device", .{vk_physical_device_name});
         return null;
      }

      const queue_family_indices = try _selectQueueFamilyIndices(allocator, vk_physical_device) orelse {
         std.log.info("vulkan physical device \"{s}\" does not support required queue families, choosing new device" , .{vk_physical_device_name});
         return null;
      };

      return @This(){
         .vk_physical_device                    = vk_physical_device,
         .vk_physical_device_properties         = vk_physical_device_properties,
         .vk_physical_device_features           = vk_physical_device_features,
         .vk_physical_device_memory_properties  = vk_physical_device_memory_properties,
         .queue_family_indices                  = queue_family_indices,
      };
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

fn _checkExtensionsPresent(allocator : std.mem.Allocator, vk_physical_device : c.VkPhysicalDevice, enabled_extensions : [] const [*:0] const u8) PhysicalDevice.SelectError!bool {
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

fn _selectQueueFamilyIndices(allocator : std.mem.Allocator, vk_physical_device : c.VkPhysicalDevice) PhysicalDevice.SelectError!?QueueFamilyIndices {
   var vk_physical_device_queue_families_count : u32 = undefined;
   c.vkGetPhysicalDeviceQueueFamilyProperties(vk_physical_device, &vk_physical_device_queue_families_count, null);

   var vk_physical_device_queue_families = try allocator.alloc(c.VkQueueFamilyProperties, @as(usize, vk_physical_device_queue_families_count));
   defer allocator.free(vk_physical_device_queue_families);
   c.vkGetPhysicalDeviceQueueFamilyProperties(vk_physical_device, &vk_physical_device_queue_families_count, vk_physical_device_queue_families.ptr);

   var queue_family_indices_found = [1] ? u32 {null} ** QueueFamilyIndices.INFO.Count;

   for (vk_physical_device_queue_families, 0..vk_physical_device_queue_families_count) |vk_physical_device_queue_family, vk_physical_device_queue_family_index_raw| {
      const vk_physical_device_queue_family_index : u32 = @intCast(vk_physical_device_queue_family_index_raw);

      var queue_families_found = [1] bool {false} ** QueueFamilyIndices.INFO.Count;

      if (vk_physical_device_queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
         queue_families_found[QueueFamilyIndices.INFO.Index.Graphics] = true;
      }
      if (vk_physical_device_queue_family.queueFlags & c.VK_QUEUE_TRANSFER_BIT != 0) {
         queue_families_found[QueueFamilyIndices.INFO.Index.Transfer] = true;
      }

      _assignUniqueQueueFamilyIndices(vk_physical_device_queue_family_index, &queue_families_found, &queue_family_indices_found);
   }

   const queue_family_indices = QueueFamilyIndices{
      .graphics   = queue_family_indices_found[QueueFamilyIndices.INFO.Index.Graphics] orelse return null,
      .transfer   = queue_family_indices_found[QueueFamilyIndices.INFO.Index.Transfer] orelse return null,
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

