const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const DescriptorSetCounts = struct {
   uniform_buffers   : u32,
   texture_samplers  : u32,
};

pub fn DescriptorSets(comptime counts : DescriptorSetCounts) type {
   return struct {
      vk_descriptor_pool                  : c.VkDescriptorPool,
      vk_descriptor_sets_uniform_buffers  : [counts.uniform_buffers]    c.VkDescriptorSet,
      vk_descriptor_sets_texture_samplers : [counts.texture_samplers]   c.VkDescriptorSet,

      pub const CreateInfo = struct {
         vk_device                                 : c.VkDevice,
         vk_descriptor_set_layout_uniform_buffers  : c.VkDescriptorSetLayout,
         vk_descriptor_set_layout_texture_samplers : c.VkDescriptorSetLayout,
         vk_buffer                                 : c.VkBuffer,
         allocation_uniforms                       : root.MemoryHeap.Allocation,
      };

      pub const CreateError = error {
         OutOfMemory,
         Unknown,
      };

      pub fn create(create_info : * const CreateInfo) CreateError!@This() {
         const vk_device                                 = create_info.vk_device;
         const vk_descriptor_set_layout_uniform_buffers  = create_info.vk_descriptor_set_layout_uniform_buffers;
         const vk_descriptor_set_layout_texture_samplers = create_info.vk_descriptor_set_layout_texture_samplers;
         const vk_buffer                                 = create_info.vk_buffer;
         const allocation_uniforms                       = create_info.allocation_uniforms;

         const vk_descriptor_pool = try _createDescriptorPool(vk_device);
         errdefer c.vkDestroyDescriptorPool(vk_device, vk_descriptor_pool, null);

         const vk_descriptor_sets_uniform_buffers  = try _createDescriptorSets(counts.uniform_buffers, vk_device, vk_descriptor_set_layout_uniform_buffers, vk_descriptor_pool);
         errdefer _ = c.vkFreeDescriptorSets(vk_device, vk_descriptor_pool, counts.uniform_buffers, &vk_descriptor_sets_uniform_buffers);

         const vk_descriptor_sets_texture_samplers = try _createDescriptorSets(counts.texture_samplers, vk_device, vk_descriptor_set_layout_texture_samplers, vk_descriptor_pool);
         errdefer _ = c.vkFreeDescriptorSets(vk_device, vk_descriptor_pool, counts.texture_samplers, &vk_descriptor_sets_texture_samplers);

         for (&vk_descriptor_sets_uniform_buffers, 0..counts.uniform_buffers) |vk_descriptor_set, i| {
            _writeDescriptorSetUniformBuffer(vk_device, vk_descriptor_set, vk_buffer, allocation_uniforms, @intCast(i));
         }

         // Don't worry about writing the image descriptor sets, that will be
         // done by higher-level code for managing the descriptor sets.

         return @This(){
            .vk_descriptor_pool                    = vk_descriptor_pool,
            .vk_descriptor_sets_uniform_buffers    = vk_descriptor_sets_uniform_buffers,
            .vk_descriptor_sets_texture_samplers   = vk_descriptor_sets_texture_samplers,
         };
      }

      pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
         c.vkDestroyDescriptorPool(vk_device, self.vk_descriptor_pool, null);
         return;
      }

      fn _createDescriptorPool(vk_device : c.VkDevice) CreateError!c.VkDescriptorPool {
         var vk_result : c.VkResult = undefined;

         const vk_descriptor_pool_size_uniforms = c.VkDescriptorPoolSize {
            .type             = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount  = counts.uniform_buffers * 2, // two bindings
         };

         const vk_descriptor_pool_size_texture_samplers = c.VkDescriptorPoolSize {
            .type             = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount  = counts.texture_samplers,
         };

         const vk_descriptor_pool_sizes = [_] c.VkDescriptorPoolSize {
            vk_descriptor_pool_size_uniforms,
            vk_descriptor_pool_size_texture_samplers,
         };

         const vk_info_create_descriptor_pool = c.VkDescriptorPoolCreateInfo{
            .sType         = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .pNext         = null,
            .flags         = 0x00000000,
            .maxSets       = counts.uniform_buffers + counts.texture_samplers,
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

      fn _createDescriptorSets(comptime descriptor_sets_count : u32, vk_device : c.VkDevice, vk_descriptor_set_layout : c.VkDescriptorSetLayout, vk_descriptor_pool : c.VkDescriptorPool) CreateError![descriptor_sets_count] c.VkDescriptorSet {
         var vk_result : c.VkResult = undefined;

         var vk_descriptor_set_layouts : [descriptor_sets_count] c.VkDescriptorSetLayout = undefined;
         @memset(&vk_descriptor_set_layouts, vk_descriptor_set_layout);

         const vk_info_allocate_descriptor_sets = c.VkDescriptorSetAllocateInfo{
            .sType               = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext               = null,
            .descriptorPool      = vk_descriptor_pool,
            .descriptorSetCount  = descriptor_sets_count,
            .pSetLayouts         = &vk_descriptor_set_layouts,
         };

         var vk_descriptor_sets : [descriptor_sets_count] c.VkDescriptorSet = undefined;
         vk_result = c.vkAllocateDescriptorSets(vk_device, &vk_info_allocate_descriptor_sets, &vk_descriptor_sets);
         switch (vk_result) {
            c.VK_SUCCESS                     => {},
            c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
            c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
            c.VK_ERROR_FRAGMENTED_POOL       => return error.Unknown,
            c.VK_ERROR_OUT_OF_POOL_MEMORY    => return error.OutOfMemory,
            else                             => unreachable,
         }
         errdefer _ = c.vkFreeDescriptorSets(vk_device, vk_descriptor_pool, descriptor_sets_count, &vk_descriptor_sets);

         return vk_descriptor_sets;
      }

      fn _writeDescriptorSetUniformBuffer(vk_device : c.VkDevice, vk_descriptor_set : c.VkDescriptorSet, vk_buffer : c.VkBuffer, allocation_uniform : root.MemoryHeap.Allocation, allocation_offset : u32) void {
         const buffer_offset = allocation_uniform.offset + allocation_offset * @sizeOf(root.types.UniformBufferObjects);

         const vk_info_descriptor_buffer_uniform_vertex = c.VkDescriptorBufferInfo{
            .buffer  = vk_buffer,
            .offset  = buffer_offset + @offsetOf(root.types.UniformBufferObjects, "vertex"),
            .range   = @sizeOf(root.types.UniformBufferObjects.Vertex),
         };

         const vk_write_descriptor_set_uniform_vertex = c.VkWriteDescriptorSet{
            .sType            = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext            = null,
            .dstSet           = vk_descriptor_set,
            .dstBinding       = 0,
            .dstArrayElement  = 0,
            .descriptorCount  = 1,
            .descriptorType   = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .pImageInfo       = null,
            .pBufferInfo      = &vk_info_descriptor_buffer_uniform_vertex,
            .pTexelBufferView = null,
         };

         const vk_info_descriptor_buffer_uniform_fragment = c.VkDescriptorBufferInfo{
            .buffer  = vk_buffer,
            .offset  = buffer_offset + @offsetOf(root.types.UniformBufferObjects, "fragment"),
            .range   = @sizeOf(root.types.UniformBufferObjects.Fragment),
         };

         const vk_write_descriptor_set_uniform_fragment = c.VkWriteDescriptorSet{
            .sType            = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext            = null,
            .dstSet           = vk_descriptor_set,
            .dstBinding       = 1,
            .dstArrayElement  = 0,
            .descriptorCount  = 1,
            .descriptorType   = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .pImageInfo       = null,
            .pBufferInfo      = &vk_info_descriptor_buffer_uniform_fragment,
            .pTexelBufferView = null,
         };

         const vk_write_descriptor_sets = [_] c.VkWriteDescriptorSet {
            vk_write_descriptor_set_uniform_vertex,
            vk_write_descriptor_set_uniform_fragment,
         };

         c.vkUpdateDescriptorSets(vk_device, @intCast(vk_write_descriptor_sets.len), &vk_write_descriptor_sets , 0, undefined);

         return;
      }
   };
}

