const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub fn SemaphoreList(comptime count : u32) type {
   return struct {
      vk_semaphores  : [count] c.VkSemaphore,

      pub const CreateError = error {
         OutOfMemory,
      };

      pub fn create(vk_device : c.VkDevice) CreateError!@This() {
         var vk_semaphores : [count] c.VkSemaphore = undefined;

         for (&vk_semaphores, 0..count) |*vk_semaphore_dest, i| {
            errdefer for (vk_semaphores[0..i]) |vk_semaphore_old| {
               c.vkDestroySemaphore(vk_device, vk_semaphore_old, null);
            };

            const vk_semaphore = try _createSemaphore(vk_device);
            errdefer c.vkDestroySemaphore(vk_device, vk_semaphore, null);

            vk_semaphore_dest.* = vk_semaphore;
         }
         errdefer for (&vk_semaphores) |vk_semaphore| {
            c.vkDestroySemaphore(vk_device, vk_semaphore, null);
         };

         return @This(){
            .vk_semaphores = vk_semaphores,
         };
      }

      fn _createSemaphore(vk_device : c.VkDevice) CreateError!c.VkSemaphore {
         var vk_result : c.VkResult = undefined;

         const vk_info_create_semaphore = c.VkSemaphoreCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = null,
            .flags = 0x000000000,
         };

         var vk_semaphore : c.VkSemaphore = undefined;
         vk_result = c.vkCreateSemaphore(vk_device, &vk_info_create_semaphore, null, &vk_semaphore);
         switch (vk_result) {
            c.VK_SUCCESS                     => {},
            c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
            c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
            else                             => unreachable,
         }
         errdefer c.vkDestroySemaphore(vk_device, vk_semaphore, null);

         return vk_semaphore;
      }

      pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
         for (&self.vk_semaphores) |vk_semaphore| {
            c.vkDestroySemaphore(vk_device, vk_semaphore, null);
         }

         return;
      }
   };
}

pub fn FenceList(comptime count : u32) type {
   return struct {
      vk_fences   : [count] c.VkFence,

      pub const CreateError = error {
         OutOfMemory,
      };

      pub fn create(vk_device : c.VkDevice) CreateError!@This() {
         var vk_fences : [count] c.VkFence = undefined;

         for (&vk_fences, 0..count) |*vk_fence_dest, i| {
            errdefer for (vk_fences[0..i]) |vk_fence_old| {
               c.vkDestroyFence(vk_device, vk_fence_old, null);
            };

            const vk_fence = try _createFence(vk_device);
            errdefer c.vkDestroyFence(vk_device, vk_fence, null);

            vk_fence_dest.* = vk_fence;
         }
         errdefer for (&vk_fences) |vk_fence| {
            c.vkDestroyFence(vk_device, vk_fence, null);
         };

         return @This(){
            .vk_fences  = vk_fences,
         };
      }

      fn _createFence(vk_device : c.VkDevice) CreateError!c.VkFence {
         var vk_result : c.VkResult = undefined;

         const vk_info_create_fence = c.VkFenceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .pNext = null,
            .flags = 0x00000000,
         };

         var vk_fence : c.VkFence = undefined;
         vk_result = c.vkCreateFence(vk_device, &vk_info_create_fence, null, &vk_fence);
         switch (vk_result) {
            c.VK_SUCCESS                     => {},
            c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
            c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
            else                             => unreachable,
         }
         errdefer c.vkDestroyFence(vk_device, vk_fence, null);

         return vk_fence;
      }

      pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
         for (&self.vk_fences) |vk_fence| {
            c.vkDestroyFence(vk_device, vk_fence, null);
         }

         return;
      }
   };
}

