const root     = @import("index.zig");
const std      = @import("std");
const builtin  = @import("builtin");
const c        = @import("cimports");

pub const MemoryHeap = struct {
   vk_buffer               : c.VkBuffer,
   vk_device_memory        : c.VkDeviceMemory,
   allocation_nodes        : std.ArrayListUnmanaged(? AllocationNode),
   allocation_nodes_head   : u32,
   heap_size               : u32,
   
   const AllocationNode = struct {
      next        : u32,
      allocation  : Allocation,

      pub const NULL_INDEX = std.math.maxInt(u32);
   };

   pub const Allocation = struct {
      offset   : u32,
      length   : u32,
   };

   pub const CreateInfo = struct {
      physical_device   : * const root.PhysicalDevice,
      vk_device         : c.VkDevice,
      heap_size         : u32,
   };

   pub const MemoryInfo = struct {
      memory_flags   : c.VkMemoryPropertyFlags,
      usage_flags    : c.VkBufferUsageFlags,
   };

   pub const CreateError = error {
      OutOfMemory,
      Unknown,
      NoSuitableMemoryAvailable,
   };

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo, memory_info : * const MemoryInfo) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const physical_device   = create_info.physical_device;
      const vk_device         = create_info.vk_device;
      const heap_size         = create_info.heap_size;
      const memory_flags      = memory_info.memory_flags;
      const usage_flags       = memory_info.usage_flags;

      var concurrency_mode_queue_family_indices_buffer : [_ConcurrencyMode.INFO.Count] u32 = undefined;
      const concurrency_mode = _chooseConcurrencyMode(&physical_device.queue_family_indices, &concurrency_mode_queue_family_indices_buffer);

      const vk_info_create_buffer = c.VkBufferCreateInfo{
         .sType                  = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
         .pNext                  = null,
         .flags                  = 0x00000000,
         .size                   = heap_size,
         .usage                  = usage_flags,
         .sharingMode            = concurrency_mode.sharing_mode,
         .queueFamilyIndexCount  = concurrency_mode.queue_family_indices_count,
         .pQueueFamilyIndices    = concurrency_mode.queue_family_indices_ptr,
      };

      var vk_buffer : c.VkBuffer = undefined;
      vk_result = c.vkCreateBuffer(vk_device, &vk_info_create_buffer, null, &vk_buffer);
      switch (vk_result) {
         c.VK_SUCCESS                                    => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY                   => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY                 => return error.OutOfMemory,
         c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR   => return error.Unknown,
         else                                            => unreachable,
      }
      errdefer c.vkDestroyBuffer(vk_device, vk_buffer, null);

      const vk_memory_type_index = _chooseMemoryTypeIndex(
         memory_flags,
         physical_device.vk_physical_device_memory_properties,
      ) orelse return error.NoSuitableMemoryAvailable;

      const vk_info_memory_allocate = c.VkMemoryAllocateInfo{
         .sType            = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
         .pNext            = null,
         .allocationSize   = heap_size,
         .memoryTypeIndex  = vk_memory_type_index,
      };

      var vk_device_memory : c.VkDeviceMemory = undefined;
      vk_result = c.vkAllocateMemory(vk_device, &vk_info_memory_allocate, null, &vk_device_memory);
      switch (vk_result) {
         c.VK_SUCCESS                                    => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY                   => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY                 => return error.OutOfMemory,
         c.VK_ERROR_INVALID_EXTERNAL_HANDLE              => return error.Unknown,
         c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR   => return error.Unknown,
         else                                            => unreachable,
      }
      errdefer c.vkFreeMemory(vk_device, vk_device_memory, null);

      vk_result = c.vkBindBufferMemory(vk_device, vk_buffer, vk_device_memory, 0);
      switch (vk_result) {
         c.VK_SUCCESS                                    => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY                   => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY                 => return error.OutOfMemory,
         c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR   => return error.Unknown,
         else                                            => unreachable,
      }

      _ = allocator;

      return @This(){
         .vk_buffer              = vk_buffer,
         .vk_device_memory       = vk_device_memory,
         .allocation_nodes       = .{},
         .allocation_nodes_head  = AllocationNode.NULL_INDEX,
         .heap_size              = heap_size,
      };
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice) void {
      var self_mut = self;

      self_mut.allocation_nodes.deinit(allocator);
      c.vkFreeMemory(vk_device, self.vk_device_memory, null);
      c.vkDestroyBuffer(vk_device, self.vk_buffer, null);
      return;
   }

   pub const TransferInfo = struct {
      heap_source                : * const MemoryHeap,
      heap_destination           : * const MemoryHeap,
      allocation_source          : Allocation,
      allocation_destination     : Allocation,
      device                     : * const root.Device,
      vk_command_buffer_transfer : c.VkCommandBuffer,
   };
   
   pub const TransferError = error {
      DestinationAllocationTooSmall,
      OutOfMemory,
      Unknown,
      DeviceLost,
   };

   pub fn transferFromStaging(transfer_info : * const TransferInfo) TransferError!void {
      var vk_result : c.VkResult = undefined;

      const heap_source                = transfer_info.heap_source;
      const heap_destination           = transfer_info.heap_destination;
      const allocation_source          = transfer_info.allocation_source;
      const allocation_destination     = transfer_info.allocation_destination;
      const device                     = transfer_info.device;
      const vk_command_buffer_transfer = transfer_info.vk_command_buffer_transfer;

      if (allocation_source.length > allocation_destination.length) {
         return error.DestinationAllocationTooSmall;
      }

      const vk_info_command_buffer_begin = c.VkCommandBufferBeginInfo{
         .sType            = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
         .pNext            = null,
         .flags            = 0x00000000,
         .pInheritanceInfo = null,
      };

      vk_result = c.vkBeginCommandBuffer(vk_command_buffer_transfer, &vk_info_command_buffer_begin);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }

      const vk_buffer_copy = c.VkBufferCopy{
         .srcOffset  = allocation_source.offset,
         .dstOffset  = allocation_destination.offset,
         .size       = allocation_source.length,
      };

      c.vkCmdCopyBuffer(vk_command_buffer_transfer, heap_source.vk_buffer, heap_destination.vk_buffer, 1, &vk_buffer_copy);

      vk_result = c.vkEndCommandBuffer(vk_command_buffer_transfer);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => return error.Unknown,
      }

      const vk_info_submit = c.VkSubmitInfo{
         .sType                  = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
         .pNext                  = null,
         .waitSemaphoreCount     = 0,
         .pWaitSemaphores        = undefined,
         .pWaitDstStageMask      = null,
         .commandBufferCount     = 1,
         .pCommandBuffers        = &vk_command_buffer_transfer,
         .signalSemaphoreCount   = 0,
         .pSignalSemaphores      = undefined,
      };

      vk_result = c.vkQueueSubmit(device.queues.transfer, 1, &vk_info_submit, @ptrCast(@alignCast(c.VK_NULL_HANDLE)));
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_DEVICE_LOST           => return error.DeviceLost,
         else                             => unreachable,        
      }

      vk_result = c.vkQueueWaitIdle(device.queues.transfer);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_DEVICE_LOST           => return error.DeviceLost,
         else                             => unreachable,        
      }

      return;
   }

   pub const AllocateInfo = struct {
      bytes       : u32,
      alignment   : u32,
   };

   pub const AllocateError = error {
      OutOfMemory,
   };

   fn _getAllocationNode(self : * @This(), index : u32) * AllocationNode {
      const allocation_node_fallible = &self.allocation_nodes.items[index];

      if (builtin.mode == .Debug and allocation_node_fallible.* == null) {
         @panic("attempted to access nonexistant allocation node");
      }

      return @ptrCast(allocation_node_fallible);
   }

   pub fn allocate(self : * @This(), allocator : std.mem.Allocator, allocate_info : * const AllocateInfo) AllocateError!Allocation {
      const bytes       = allocate_info.bytes;
      const alignment   = allocate_info.alignment;

      if (bytes > self.heap_size) {
         return error.OutOfMemory;
      }

      const allocation_nodes_head = self.allocation_nodes_head;

      // Is this the first allocation?
      if (allocation_nodes_head == AllocationNode.NULL_INDEX) {
         const allocation = Allocation{
            .offset  = 0,
            .length  = bytes,
         };

         try self.allocation_nodes.append(allocator, .{
            .next       = AllocationNode.NULL_INDEX,
            .allocation = allocation,
         });

         self.allocation_nodes_head = 0;

         return allocation;
      }

      // Search for a free block of memory in the middle of the heap
      var allocation_node_curr_index = self.allocation_nodes_head;
      var allocation_node_next_index = self._getAllocationNode(self.allocation_nodes_head).next;
      while (allocation_node_next_index != AllocationNode.NULL_INDEX) {
         const allocation_node_curr = self._getAllocationNode(allocation_node_curr_index);
         const allocation_node_next = self._getAllocationNode(allocation_node_next_index);

         const allocation_curr = &allocation_node_curr.allocation;
         const allocation_next = &allocation_node_next.allocation;

         const block_size_unaligned = allocation_next.offset - allocation_curr.offset - allocation_curr.length;
         const block_size = block_size_unaligned - @rem(block_size_unaligned, alignment);

         if (block_size >= bytes) {
            break;
         }

         allocation_node_curr_index = allocation_node_next_index;
         allocation_node_next_index = allocation_node_next.next;
      }

      const allocation_node_prev = self._getAllocationNode(allocation_node_curr_index);

      // If we reached the end of the heap, make sure some memory is still available
      if (allocation_node_next_index == AllocationNode.NULL_INDEX) {
         const allocation_node   = self._getAllocationNode(allocation_node_curr_index);
         const allocation        = &allocation_node.allocation;

         const block_size_unaligned = self.heap_size - allocation.offset - allocation.length;
         const block_size = block_size_unaligned - @rem(block_size_unaligned, alignment);

         if (block_size < bytes) {
            return error.OutOfMemory;
         }
      }

      // Find the index into the allocation nodes storage to insert if available
      var allocation_node_insert_index : ? u32 = null;
      for (self.allocation_nodes.items, 0..self.allocation_nodes.items.len) |allocation_node, i| {
         if (allocation_node == null) {
            allocation_node_insert_index = @intCast(i);
            break;
         }
      }

      const allocation_node_new_index = blk: {
         if (allocation_node_insert_index) |index| {
            break :blk index;
         } else {
            break :blk @as(u32, @intCast(self.allocation_nodes.items.len));
         }
      };

      if (allocation_node_insert_index == null) {
         try self.allocation_nodes.resize(allocator, self.allocation_nodes.items.len + 1);
      }

      // Create the allocation
      const offset_unaligned = allocation_node_prev.allocation.offset + allocation_node_prev.allocation.length;
      const offset = offset_unaligned + (alignment - @rem(offset_unaligned, alignment));
      const allocation = Allocation{
         .offset  = offset,
         .length  = bytes,
      };

      // Insert the allocation into the list
      const next = blk: {
         if (allocation_node_next_index == AllocationNode.NULL_INDEX) {
            break :blk AllocationNode.NULL_INDEX;
         } else {
            break :blk self._getAllocationNode(allocation_node_next_index).next;
         }
      };

      const allocation_node = AllocationNode{
         .next       = next,
         .allocation = allocation,
      };

      self.allocation_nodes.items[allocation_node_new_index] = allocation_node;
      allocation_node_prev.next = allocation_node_new_index;

      return allocation;
   }

   pub fn free(self : * @This(), allocator : std.mem.Allocator, allocation : Allocation) void {
      var allocation_node_index_prev : u32 = undefined;
      var allocation_node_index = self.allocation_nodes_head;
      while (allocation_node_index != AllocationNode.NULL_INDEX) {
         const allocation_node = self.allocation_nodes.items[allocation_node_index] orelse unreachable;
         
         if (allocation_node.allocation.offset == allocation.offset) {
            break;
         }

         allocation_node_index_prev = allocation_node_index;
         allocation_node_index      = allocation_node.next;
      }

      // We assume an invalid block isn't used because remember...
      // "If you just program well, you don't need safety checks" - Kaze Emanuar 2021
      if (builtin.mode == .Debug and allocation_node_index == AllocationNode.NULL_INDEX) {
         @panic("attempted to free a non-existant allocation");
      }

      // Do we stitch together the previous with the next or are we freeing the head?
      if (allocation_node_index != self.allocation_nodes_head) {
         (self.allocation_nodes.items[allocation_node_index_prev] orelse unreachable).next = (self.allocation_nodes.items[allocation_node_index] orelse unreachable).next;
      } else {
         @setCold(true);
         self.allocation_nodes_head = (self.allocation_nodes.items[allocation_node_index] orelse unreachable).next;
      }

      // Remove from storage
      self.allocation_nodes.items[allocation_node_index] = null;

      // Trim off as many nulls off the end of the array as possible
      var trimmed_length = self.allocation_nodes.items.len;
      while (trimmed_length != 0 and self.allocation_nodes.items[trimmed_length - 1] == null) {
         trimmed_length -= 1;
      }
      self.allocation_nodes.shrinkAndFree(allocator, trimmed_length);

      return;
   }
};

const _ConcurrencyMode = struct {
   sharing_mode               : c.VkSharingMode,
   queue_family_indices_count : u32,
   queue_family_indices_ptr   : [*] const u32,

   pub const INFO = struct {
      pub const Count = 2;
      pub const Index = struct {
         pub const Graphics   = 0;
         pub const Transfer   = 1;
      };
   };
};

fn _chooseConcurrencyMode(queue_family_indices : * const root.QueueFamilyIndices, queue_family_indices_array : * [_ConcurrencyMode.INFO.Count] u32) _ConcurrencyMode {
   if (queue_family_indices.graphics == queue_family_indices.transfer) {
      return .{
         .sharing_mode                 = c.VK_SHARING_MODE_EXCLUSIVE,
         .queue_family_indices_count   = undefined,
         .queue_family_indices_ptr     = undefined,
      };
   }

   queue_family_indices_array[_ConcurrencyMode.INFO.Index.Graphics] = queue_family_indices.graphics;
   queue_family_indices_array[_ConcurrencyMode.INFO.Index.Transfer] = queue_family_indices.transfer;

   return .{
      .sharing_mode                 = c.VK_SHARING_MODE_CONCURRENT,
      .queue_family_indices_count   = _ConcurrencyMode.INFO.Count,
      .queue_family_indices_ptr     = queue_family_indices_array.ptr,
   };
}

fn _chooseMemoryTypeIndex(vk_memory_property_flags : c.VkMemoryPropertyFlags, vk_physical_device_memory_properties : c.VkPhysicalDeviceMemoryProperties) ? u32 {
   const vk_memory_types_count   = vk_physical_device_memory_properties.memoryTypeCount;
   const vk_memory_types         = vk_physical_device_memory_properties.memoryTypes[0..vk_memory_types_count];

   for (vk_memory_types, 0..vk_memory_types_count) |vk_memory_type, i| {
      // This differs from the tutorial because I don't have a clue what the
      // tutorial's code is supposed to do and it doesn't work for me.
      if (vk_memory_type.propertyFlags & vk_memory_property_flags != vk_memory_property_flags) {
         continue;
      }

      return @intCast(i);
   }

   return null;
}

pub const MemoryHeapDraw = struct {
   memory_heap : MemoryHeap,

   pub const CreateInfo = MemoryHeap.CreateInfo;

   pub const CreateError = MemoryHeap.CreateError;

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      const MEMORY_INFO = MemoryHeap.MemoryInfo{
         .memory_flags  = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
         .usage_flags   = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT | c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
      };

      const memory_heap = try MemoryHeap.create(allocator, &.{
         .physical_device  = create_info.physical_device,
         .vk_device        = create_info.vk_device,
         .heap_size        = create_info.heap_size,
      }, &MEMORY_INFO);
      errdefer memory_heap.destroy(allocator, create_info.vk_device);

      return @This(){
         .memory_heap   = memory_heap,
      };
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice) void {
      self.memory_heap.destroy(allocator, vk_device);
      return;
   }

   
};

pub const MemoryHeapTransfer = struct {
   memory_heap : MemoryHeap,
   mapping     : * anyopaque,

   pub const CreateInfo = MemoryHeap.CreateInfo;

   pub const CreateError = MemoryHeap.CreateError;

   pub fn create(allocator : std.mem.Allocator, vk_device : c.VkDevice, create_info : * const CreateInfo) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const MEMORY_INFO = MemoryHeap.MemoryInfo{
         .memory_flags  = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
         .usage_flags   = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
      };

      const memory_heap = try MemoryHeap.create(allocator, &.{
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

   pub fn destroy(self : @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice) void {
      c.vkUnmapMemory(vk_device, self.memory_heap.vk_device_memory);
      self.memory_heap.destroy(allocator, vk_device);
      return;
   }
};

