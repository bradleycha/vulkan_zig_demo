const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub fn UniformAllocations(comptime count : comptime_int) type {
   return struct {
      allocation_transfer  : root.MemoryHeap.Allocation,
      allocations_draw     : [count] root.MemoryHeap.Allocation,

      pub const CreateInfo = struct {
         memory_heap_transfer : * root.MemoryHeapTransfer,
         memory_heap_draw     : * root.MemoryHeapDraw,
      };

      pub const CreateError = error {
         OutOfMemory,
      };

      pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
         const allocate_info = root.MemoryHeap.AllocateInfo{
            .alignment  = @sizeOf(root.types.UniformBufferObject),
            .bytes      = @sizeOf(root.types.UniformBufferObject),
         };

         const heap_transfer  = &create_info.memory_heap_transfer.memory_heap;
         const heap_draw      = &create_info.memory_heap_draw.memory_heap;

         const allocation_transfer = try heap_transfer.allocate(allocator, &allocate_info);
         errdefer heap_transfer.free(allocator, allocation_transfer);

         var allocations_draw : [count] root.MemoryHeap.Allocation = undefined;
         for (&allocations_draw, 0..count) |*allocation_draw_dest, i| {
            errdefer for (allocations_draw[0..i]) |allocation_draw_old| {
               heap_draw.free(allocator, allocation_draw_old);
            };

            const allocation_draw = try heap_draw.allocate(allocator, &allocate_info);
            errdefer heap_draw.free(allocator, allocation_draw);

            allocation_draw_dest.* = allocation_draw;
         }
         errdefer for (&allocations_draw) |allocation_draw| {
            heap_draw.free(allocator, allocation_draw);
         };

         return @This(){
            .allocation_transfer = allocation_transfer,
            .allocations_draw    = allocations_draw,
         };
      }

      pub fn destroy(self : @This(), allocator : std.mem.Allocator, memory_heap_transfer : * root.MemoryHeapTransfer, memory_heap_draw : * root.MemoryHeapDraw) void {
         for (&self.allocations_draw) |allocation_draw| {
            memory_heap_draw.memory_heap.free(allocator, allocation_draw);
         }

         memory_heap_transfer.memory_heap.free(allocator, self.allocation_transfer);

         return;
      }

      pub fn getUniformBufferObject(self : * const @This(), memory_heap_transfer : * const root.MemoryHeapTransfer) * const root.types.UniformBufferObject {
         return @ptrFromInt((@intFromPtr(memory_heap_transfer.mapping) + self.allocation_transfer.offset));
      }

      pub fn getUniformBufferObjectMut(self : * @This(), memory_heap_transfer : * const root.MemoryHeapTransfer) * root.types.UniformBufferObject {
         return @ptrFromInt((@intFromPtr(memory_heap_transfer.mapping) + self.allocation_transfer.offset));
      }
   };
}

