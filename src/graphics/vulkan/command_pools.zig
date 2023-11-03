const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const CommandPools = struct {
   graphics : c.VkCommandPool,
   transfer : c.VkCommandPool,

   pub const CreateError = error {
      OutOfMemory,
   };

   pub fn create(vk_device : c.VkDevice, queue_family_indices : * const root.QueueFamilyIndices) CreateError!@This() {
      const vk_command_pool_graphics = try _createCommandPool(vk_device, queue_family_indices.graphics);
      errdefer c.vkDestroyCommandPool(vk_device, vk_command_pool_graphics, null);

      const vk_command_pool_transfer = try _createCommandPool(vk_device, queue_family_indices.transfer);
      errdefer c.vkDestroyCommandPool(vk_device, vk_command_pool_transfer, null);

      return @This(){
         .graphics   = vk_command_pool_graphics,
         .transfer   = vk_command_pool_transfer,
      };
   }

   pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
      c.vkDestroyCommandPool(vk_device, self.graphics, null);
      return;
   }
};

fn _createCommandPool(vk_device : c.VkDevice, vk_queue_family_index : u32) CommandPools.CreateError!c.VkCommandPool {
   var vk_result : c.VkResult = undefined;

   const vk_info_create_command_pool = c.VkCommandPoolCreateInfo{
      .sType            = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .pNext            = null,
      .flags            = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
      .queueFamilyIndex = vk_queue_family_index,
   };

   var vk_command_pool : c.VkCommandPool = undefined;
   vk_result = c.vkCreateCommandPool(vk_device, &vk_info_create_command_pool, null, &vk_command_pool);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }
   errdefer c.vkDestroyCommandPool(vk_device, vk_command_pool, null);

   return vk_command_pool;
}

