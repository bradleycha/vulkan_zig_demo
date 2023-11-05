const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const MemoryHeap = struct {
   vk_buffer         : c.VkBuffer,
   vk_device_memory  : c.VkDeviceMemory,

   pub const Allocation = struct {
      offset   : u32,
      length   : u32,
   };

   pub const CreateInfo = struct {
      physical_device   : * const root.PhysicalDevice,
      vk_device         : c.VkDevice,
      heap_size         : u32,
      memory_flags      : c.VkMemoryPropertyFlags,
   };

   pub const CreateError = error {
      OutOfMemory,
   };

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      _ = allocator;
      _ = create_info;
      unreachable;
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice) void {
      _ = self;
      _ = allocator;
      _ = vk_device;
      unreachable;
   }
};

pub const MemoryHeapDraw = struct {
   memory_heap : MemoryHeap,

   pub const CreateInfo = struct {
      physical_device   : * const root.PhysicalDevice,
      vk_device         : c.VkDevice,
      heap_size         : u32,
   };

   pub const CreateError = MemoryHeap.CreateError;

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      _ = allocator;
      _ = create_info;
      unreachable;
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice) void {
      self.memory_heap.destroy(allocator, vk_device);
      return;
   }
};

pub const MemoryHeapTransfer = struct {
   memory_heap : MemoryHeap,

   pub const CreateInfo = struct {
      physical_device   : * const root.PhysicalDevice,
      vk_device         : c.VkDevice,
      heap_size         : u32,
   };

   pub const CreateError = MemoryHeap.CreateError;

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      _ = allocator;
      _ = create_info;
      unreachable;
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice) void {
      self.memory_heap.destroy(allocator, vk_device);
      return;
   }
};

