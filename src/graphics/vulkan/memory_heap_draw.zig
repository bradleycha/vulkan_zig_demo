const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

const MEMORY_FLAGS   = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
const USAGE_FLAGS    = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT | c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;

pub const MemorySourceDraw = struct {
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

pub const MemoryHeapDraw = struct {
   memory_heap : root.MemoryHeap,

   pub const CreateInfo = root.MemoryHeap.CreateInfo;

   pub const CreateError = root.MemoryHeap.CreateError;

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo, memory_source : * const MemorySourceDraw) CreateError!@This() {
      const MEMORY_INFO = root.MemoryHeap.MemoryInfo{
         .source        = memory_source.memory_source,
         .usage_flags   = USAGE_FLAGS,
      };

      const memory_heap = try root.MemoryHeap.create(allocator, &.{
         .physical_device  = create_info.physical_device,
         .vk_device        = create_info.vk_device,
         .heap_size        = create_info.heap_size,
      }, &MEMORY_INFO);
      errdefer memory_heap.destroy(allocator, create_info.vk_device);

      return @This(){
         .memory_heap   = memory_heap,
      };
   }

   pub fn destroy(self : * @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice) void {
      self.memory_heap.destroy(allocator, vk_device);
      return;
   }
};

