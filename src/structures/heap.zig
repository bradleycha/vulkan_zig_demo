const std      = @import("std");
const builtin  = @import("builtin");

pub fn Heap(comptime memory_precision : type) type {
   return struct {
      nodes : std.ArrayListUnmanaged(AllocationNode) = .{},
      head  : usize = NULL_ALLOCATION_NODE_INDEX,
      size  : memory_precision,

      pub const Allocation = struct {
         offset   : memory_precision,
         bytes    : memory_precision,
      };

      pub const AllocateInfo = struct {
         alignment   : memory_precision,
         bytes       : memory_precision,
      };

      pub const AllocateError = error {
         OutOfMemory,
      };

      pub fn deinit(self : @This(), allocator : std.mem.Allocator) void {
         if (std.debug.runtime_safety == true) {
            self._checkMemoryLeaks();
         }

         var self_mut = self;
         self_mut.nodes.deinit(allocator);
         return;
      }

      pub fn allocate(self : * @This(), allocator : std.mem.Allocator, allocate_info : * const AllocateInfo) AllocateError!Allocation {
         _ = self;
         _ = allocator;
         _ = allocate_info;
         unreachable;
      }

      pub fn free(self : * @This(), allocator : std.mem.Allocator, allocation : Allocation) void {
         _ = self;
         _ = allocator;
         _ = allocation;
         unreachable;
      }

      const AllocationNode = struct {
         block : Allocation,
         next  : usize,
      };

      const NULL_ALLOCATION_NODE_INDEX = std.math.maxInt(usize);
      const NULL_ALLOCATION_OFFSET     = std.math.maxInt(memory_precision);

      fn _allocationNodeIsNull(node : * const AllocationNode) bool {
         return node.block.offset == NULL_ALLOCATION_OFFSET;
      }

      fn _allocationNodeSetNull(node : * AllocationNode) void {
         node.block.offset = NULL_ALLOCATION_OFFSET;
         return;
      }

      fn _checkAllocationNodeIndex(self : * const @This(), index : usize) bool {
         return index < self.nodes.items.len;
      }

      fn _getNodeOptional(self : * const @This(), index : usize) ? * const AllocationNode {
         if (std.debug.runtime_safety == true and self._checkAllocationNodeIndex(index) == false) {
            @panic("attempted to access invalid allocation node index");
         }

         const node = &self.nodes.items[index];

         if (_allocationNodeIsNull(node) == true) {
            return null;
         }

         return node;
      }

      fn _getNodeOptionalMut(self : * @This(), index : usize) ? * AllocationNode {
         if (std.debug.runtime_safety == true and self._checkAllocationNodeIndex(index) == false) {
            @panic("attempted to access invalid allocation node index");
         }

         const node = &self.nodes.items[index];

         if (_allocationNodeIsNull(node) == true) {
            return null;
         }

         return node;
      }

      fn _getNode(self : * const @This(), index : usize) * const AllocationNode {
         if (std.debug.runtime_safety == true and self._checkAllocationNodeIndex(index) == false) {
            @panic("attempted to access invalid allocation node index");
         }

         const node = &self.nodes.items[index];

         if (std.debug.runtime_safety == true and _allocationNodeIsNull(node) == true) {
            @panic("attempted to access null allocation node");
         }

         return node;
      }

      fn _getNodeMut(self : * @This(), index : usize) * AllocationNode {
         if (std.debug.runtime_safety == true and self._checkAllocationNodeIndex(index) == false) {
            @panic("attempted to access invalid allocation node index");
         }

         const node = &self.nodes.items[index];

         if (std.debug.runtime_safety == true and _allocationNodeIsNull(node) == true) {
            @panic("attempted to access null allocation node");
         }

         return node;
      }

      fn _checkMemoryLeaks(self : * const @This()) void {
         var node_index_curr = self.head;
         while (node_index_curr != NULL_ALLOCATION_NODE_INDEX) {
            const node  = self._getNode(node_index_curr);
            const block = &node.block;

            std.log.err("heap memory leaked at {x} - {x}", .{block.offset, block.offset + block.bytes});

            node_index_curr = node.next;
         }

         if (self.head != NULL_ALLOCATION_NODE_INDEX) {
            @panic("heap memory leaked");
         }

         return;
      }
   };
}

