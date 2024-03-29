const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const MEMORY_FLAGS  = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
pub const USAGE_FLAGS   = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;

pub const MemorySourceTransfer = struct {
   memory_source  : root.MemorySource,

   pub fn findSuitable(vk_physical_device_memory_properties : c.VkPhysicalDeviceMemoryProperties) ? @This() {
      const memory_source = root.MemorySource.findSuitable(
         MEMORY_FLAGS,
         vk_physical_device_memory_properties,
      ) orelse return null;

      return @This(){
         .memory_source = memory_source,
      };
   }
};

pub const MemoryHeapTransfer = struct {
   memory_heap : root.MemoryHeap,
   mapping     : * anyopaque,

   pub const CreateInfo = root.MemoryHeap.CreateInfo;

   pub const CreateError = root.MemoryHeap.CreateError;

   pub fn create(allocator : std.mem.Allocator, vk_device : c.VkDevice, create_info : * const CreateInfo, memory_source : * const MemorySourceTransfer) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const MEMORY_INFO = root.MemoryHeap.MemoryInfo{
         .source        = memory_source.memory_source,
         .usage_flags   = USAGE_FLAGS,
      };

      var memory_heap = try root.MemoryHeap.create(allocator, &.{
         .physical_device  = create_info.physical_device,
         .vk_device        = create_info.vk_device,
         .heap_size        = create_info.heap_size,
      }, &MEMORY_INFO);
      errdefer memory_heap.destroy(allocator, create_info.vk_device);

      var vk_mapping : ? * anyopaque = undefined;
      vk_result = c.vkMapMemory(vk_device, memory_heap.vk_device_memory, 0, create_info.heap_size, 0, &vk_mapping);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_MEMORY_MAP_FAILED     => return error.Unknown,
         else                             => unreachable,
      }
      errdefer c.vkUnmapMemory(vk_device, memory_heap.vk_device_memory);

      return @This(){
         .memory_heap   = memory_heap,
         .mapping       = vk_mapping orelse unreachable,
      };
   }

   pub fn destroy(self : * @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice) void {
      c.vkUnmapMemory(vk_device, self.memory_heap.vk_device_memory);
      self.memory_heap.destroy(allocator, vk_device);
      return;
   }
};

