const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub fn DescriptorSets(comptime descriptor_count : comptime_int) type {
   return struct {
      vk_descriptor_pool   : c.VkDescriptorPool,
      vk_descriptor_sets   : [descriptor_count] c.VkDescriptorSet,

      pub const CreateInfo = struct {
         vk_device                  : c.VkDevice,
         vk_descriptor_set_layout   : c.VkDescriptorSetLayout,
         vk_buffer                  : c.VkBuffer,
         allocations_uniforms       : [descriptor_count] root.MemoryHeap.Allocation,
      };

      pub const CreateError = error {
         OutOfMemory,
         Unknown,
      };

      pub fn create(create_info : * const CreateInfo) CreateError!@This() {
         const vk_device                  = create_info.vk_device;
         const vk_descriptor_set_layout   = create_info.vk_descriptor_set_layout;
         const vk_buffer                  = create_info.vk_buffer;
         const allocations_uniforms       = create_info.allocations_uniforms;

         const vk_descriptor_pool = try _createDescriptorPool(vk_device, descriptor_count);
         errdefer c.vkDestroyDescriptorPool(vk_device, vk_descriptor_pool, null);

         const vk_descriptor_sets = try _createDescriptorSets(vk_device, vk_descriptor_set_layout, vk_descriptor_pool);

         for (&vk_descriptor_sets, &allocations_uniforms) |vk_descriptor_set, allocation_uniform| {
            _writeDescriptorSet(vk_device, vk_descriptor_set, vk_buffer, allocation_uniform);
         }

         return @This(){
            .vk_descriptor_pool  = vk_descriptor_pool,
            .vk_descriptor_sets  = vk_descriptor_sets,
         };
      }

      pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
         c.vkDestroyDescriptorPool(vk_device, self.vk_descriptor_pool, null);
         return;
      }

      fn _createDescriptorPool(vk_device : c.VkDevice, descriptor_sets : u32) CreateError!c.VkDescriptorPool {
         var vk_result : c.VkResult = undefined;

         const vk_descriptor_pool_size_uniforms = c.VkDescriptorPoolSize {
            .type             = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount  = descriptor_sets,
         };

         const vk_descriptor_pool_sizes = [_] c.VkDescriptorPoolSize {
            vk_descriptor_pool_size_uniforms,
         };

         const vk_info_create_descriptor_pool = c.VkDescriptorPoolCreateInfo{
            .sType         = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .pNext         = null,
            .flags         = 0x00000000,
            .maxSets       = descriptor_sets,
            .poolSizeCount = @intCast(vk_descriptor_pool_sizes.len),
            .pPoolSizes    = &vk_descriptor_pool_sizes,
         };

         var vk_descriptor_pool : c.VkDescriptorPool = undefined;
         vk_result = c.vkCreateDescriptorPool(vk_device, &vk_info_create_descriptor_pool, null, &vk_descriptor_pool);
         switch (vk_result) {
            c.VK_SUCCESS                     => {},
            c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
            c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
            c.VK_ERROR_FRAGMENTATION_EXT     => return error.Unknown,
            else                             => unreachable,
         }
         errdefer c.vkDestroyDescriptorPool(vk_device, vk_descriptor_pool, null);

         return vk_descriptor_pool;
      }

      fn _createDescriptorSets(vk_device : c.VkDevice, vk_descriptor_set_layout : c.VkDescriptorSetLayout, vk_descriptor_pool : c.VkDescriptorPool) CreateError![descriptor_count] c.VkDescriptorSet {
         var vk_result : c.VkResult = undefined;

         var vk_descriptor_set_layouts : [descriptor_count] c.VkDescriptorSetLayout = undefined;
         @memset(&vk_descriptor_set_layouts, vk_descriptor_set_layout);

         const vk_info_allocate_descriptor_sets = c.VkDescriptorSetAllocateInfo{
            .sType               = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext               = null,
            .descriptorPool      = vk_descriptor_pool,
            .descriptorSetCount  = descriptor_count,
            .pSetLayouts         = &vk_descriptor_set_layouts,
         };

         var vk_descriptor_sets : [descriptor_count] c.VkDescriptorSet = undefined;
         vk_result = c.vkAllocateDescriptorSets(vk_device, &vk_info_allocate_descriptor_sets, &vk_descriptor_sets);
         switch (vk_result) {
            c.VK_SUCCESS                     => {},
            c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
            c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
            c.VK_ERROR_FRAGMENTED_POOL       => return error.Unknown,
            c.VK_ERROR_OUT_OF_POOL_MEMORY    => return error.OutOfMemory,
            else                             => unreachable,
         }
         errdefer c.vkFreeDescriptorSets(vk_device, vk_descriptor_pool, descriptor_count, &vk_descriptor_sets);

         return vk_descriptor_sets;
      }

      fn _writeDescriptorSet(vk_device : c.VkDevice, vk_descriptor_set : c.VkDescriptorSet, vk_buffer : c.VkBuffer, allocation_uniform : root.MemoryHeap.Allocation) void {
         const vk_info_descriptor_buffer_uniform = c.VkDescriptorBufferInfo{
            .buffer  = vk_buffer,
            .offset  = allocation_uniform.offset,
            .range   = @sizeOf(root.types.UniformBufferObject),
         };

         const vk_write_descriptor_set_uniform = c.VkWriteDescriptorSet{
            .sType            = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext            = null,
            .dstSet           = vk_descriptor_set,
            .dstBinding       = 0,
            .dstArrayElement  = 0,
            .descriptorCount  = 1,
            .descriptorType   = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .pImageInfo       = null,
            .pBufferInfo      = &vk_info_descriptor_buffer_uniform,
            .pTexelBufferView = null,
         };

         const vk_write_descriptor_sets = [_] c.VkWriteDescriptorSet {
            vk_write_descriptor_set_uniform, 
         };

         c.vkUpdateDescriptorSets(vk_device, @intCast(vk_write_descriptor_sets.len), &vk_write_descriptor_sets , 0, undefined);

         return;
      }
   };
}

