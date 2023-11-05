const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub fn CommandBuffersDraw(comptime count : u32) type {
   return struct {
      vk_command_buffers   : [count] c.VkCommandBuffer,

      pub const CreateInfo = struct {
         vk_device         : c.VkDevice,
         vk_command_pool   : c.VkCommandPool,
      };

      pub const CreateError = error {
         OutOfMemory,
      };   

      pub fn create(create_info : * const CreateInfo) CreateError!@This() {
         var vk_result : c.VkResult = undefined;

         const vk_device         = create_info.vk_device;
         const vk_command_pool   = create_info.vk_command_pool;

         const vk_info_create_command_buffers = c.VkCommandBufferAllocateInfo{
            .sType               = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext               = null,
            .commandPool         = vk_command_pool,
            .level               = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount  = count,
         };

         var vk_command_buffers : [count] c.VkCommandBuffer = undefined;
         vk_result = c.vkAllocateCommandBuffers(vk_device, &vk_info_create_command_buffers, &vk_command_buffers);
         switch (vk_result) {
            c.VK_SUCCESS                     => {},
            c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
            c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
            else                             => unreachable,
         }
         errdefer c.vkFreeCommandBuffers(vk_device, vk_command_pool, count, &vk_command_buffers);
         
         return @This(){
            .vk_command_buffers  = vk_command_buffers,
         };
      }

      pub fn destroy(self : @This(), vk_device : c.VkDevice, vk_command_pool : c.VkCommandPool) void {
         c.vkFreeCommandBuffers(vk_device, vk_command_pool, count, &self.vk_command_buffers);
         return;
      }
   };
}

pub const CommandBufferTransfer = struct {
   vk_command_buffer : c.VkCommandBuffer,

   pub const CreateInfo = struct {
      vk_device         : c.VkDevice,
      vk_command_pool   : c.VkCommandPool,
   };

   pub const CreateError = error {
      OutOfMemory,
   };

   pub fn create(create_info : * const CreateInfo) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const vk_device         = create_info.vk_device;
      const vk_command_pool   = create_info.vk_command_pool;

      const vk_info_create_command_buffer = c.VkCommandBufferAllocateInfo{
         .sType               = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
         .pNext               = null,
         .commandPool         = vk_command_pool,
         .level               = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
         .commandBufferCount  = 1,
      };

      var vk_command_buffer : c.VkCommandBuffer = undefined;
      vk_result = c.vkAllocateCommandBuffers(vk_device, &vk_info_create_command_buffer, &vk_command_buffer);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }
      errdefer c.vkFreeCommandBuffers(vk_device, vk_command_pool, 1, &vk_command_buffer);

      return @This(){
         .vk_command_buffer   = vk_command_buffer,
      };
   }

   pub fn destroy(self : @This(), vk_device : c.VkDevice, vk_command_pool : c.VkCommandPool) void {
      c.vkFreeCommandBuffers(vk_device, vk_command_pool, 1, &self.vk_command_buffer);
      return;
   }
};

