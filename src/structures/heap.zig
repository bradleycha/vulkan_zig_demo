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

      pub fn deinit(self : * @This(), allocator : std.mem.Allocator) void {
         if (std.debug.runtime_safety == true) {
            self._checkMemoryLeaks();
         }

         self.nodes.deinit(allocator);
         return;
      }

      pub fn allocate(self : * @This(), allocator : std.mem.Allocator, allocate_info : * const AllocateInfo) AllocateError!Allocation {
         // Start off checking if we can fit the allocation into an empty heap
         // Note that the first allocation into an empty heap will always
         // satisfy the required alignment since we start at address zero.
         if (allocate_info.bytes > self.size) {
            return error.OutOfMemory;
         }

         // If this is the first allocation, create it right away.
         if (self.head == NULL_ALLOCATION_NODE_INDEX) {
            const block = Allocation{
               .offset  = 0,
               .bytes   = allocate_info.bytes,
            };

            const allocation_node = AllocationNode{
               .block   = block,
               .next    = NULL_ALLOCATION_NODE_INDEX,
            };

            try self.nodes.append(allocator, allocation_node);            
            self.head = self.nodes.items.len - 1;

            return block;
         }

         // Attempt to find a free block in the middle of the heap
         var node_index_prev = self.head;
         var node_index_curr = self._getNode(self.head).next;
         while (node_index_curr != NULL_ALLOCATION_NODE_INDEX) {
            const node_prev = self._getNode(node_index_prev);
            const node_curr = self._getNode(node_index_curr);

            const block_prev = &node_prev.block;
            const block_curr = &node_curr.block;

            const free_block_start  = block_prev.offset + block_prev.bytes;
            const free_block_end    = block_curr.offset;
            const free_block_size   = _calculateAlignedBlockSize(free_block_start, free_block_end, allocate_info.alignment);

            if (free_block_size >= allocate_info.bytes) {
               break;
            }

            node_index_prev = node_index_curr;
            node_index_curr = node_curr.next;
         }

         const node_prev   = self._getNodeMut(node_index_prev);
         const block_prev  = &node_prev.block;

         const free_block_start = block_prev.offset + block_prev.bytes;

         // If we reached the end of the heap, make sure we have enough free memory
         if (node_index_curr == NULL_ALLOCATION_NODE_INDEX) {
            const free_block_end    = self.size;
            const free_block_size   = _calculateAlignedBlockSize(free_block_start, free_block_end, allocate_info.alignment);

            if (free_block_size < allocate_info.bytes) {
               return error.OutOfMemory;
            }
         }

         // Calculate the block offset, checking against our special sentinel value
         const block_offset = _alignForward(free_block_start, allocate_info.alignment);
         if (block_offset == NULL_ALLOCATION_OFFSET) {
            return error.OutOfMemory;
         }

         // Create a new index for our node.  Make sure to not use old memory
         // pointers as they may be invalid after this call.  I spent an hour
         // in GDB chasing a bug related to this.
         const node_index = try self._nextAvailableNodeIndex(allocator);

         // Create the allocation block and node
         const block = Allocation{
            .offset  = block_offset,
            .bytes   = allocate_info.bytes,
         };

         const node = AllocationNode{
            .block   = block,
            .next    = node_index_curr,
         };

         // Insert the new node into the list
         _getNodeMut(self, node_index_prev).next = node_index;
         self.nodes.items[node_index] = node;

         // Return the freshly baked allocation
         return block;
      }

      pub fn free(self : * @This(), allocator : std.mem.Allocator, allocation : Allocation) void {
         // Excess free calls can lead to freeing from an empty heap, probably a double-free
         if (std.debug.runtime_safety == true and self.head == NULL_ALLOCATION_NODE_INDEX) {
            @panic("attempted to free allocation from empty heap (double-free?)");
         }

         const node_head   = self._getNodeMut(self.head);
         const block_head  = &node_head.block; // Stupid block-head implementor!

         // We need special attention if we are freeing the head.
         if (_equalBlocks(block_head, &allocation) == true) {
            self.head = node_head.next;

            if (node_head.next == NULL_ALLOCATION_NODE_INDEX) {
               self.nodes.clearAndFree(allocator);
            } else {
               _allocationNodeSetNull(node_head);
               self._drainTrailingFreeNodes(allocator);
            }

            return;
         }

         // If there are no other possible allocations other than the head, we
         // know the allocation is invalid.
         if (std.debug.runtime_safety == true and node_head.next == NULL_ALLOCATION_NODE_INDEX) {
            @panic("attempted to free invalid block");
         }

         // Try to find the node which corresponds with the allocation
         var node_index_prev = self.head;
         var node_index_curr = node_head.next;
         var node_index_next = self._getNode(node_index_curr).next;
         while (node_index_next != NULL_ALLOCATION_NODE_INDEX) {
            const node_curr = self._getNode(node_index_curr);
            const node_next = self._getNode(node_index_next);

            const block_curr = &node_curr.block;

            if (_equalBlocks(block_curr, &allocation) == true) {
               break;
            }

            node_index_prev = node_index_curr;
            node_index_curr = node_index_next;
            node_index_next = node_next.next;
         }

         const node_prev = self._getNodeMut(node_index_prev);
         const node_curr = self._getNodeMut(node_index_curr);

         // Make sure the block was actually found
         if (std.debug.runtime_safety == true and _equalBlocks(&node_curr.block, &allocation) == false) {
            @panic("attempted to free invalid block");
         }

         // Remove from the heap
         _removeNode(node_prev, node_curr);
         self._drainTrailingFreeNodes(allocator);

         // Great success!
         return;
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

      fn _alignForward(value : memory_precision, alignment : memory_precision) memory_precision {
         return value + alignment - @rem(value, alignment);
      }

      fn _calculateAlignedBlockSize(start : memory_precision, end : memory_precision, alignment : memory_precision) memory_precision {
         const start_aligned = _alignForward(start, alignment);

         if (start_aligned >= end) {
            return 0;
         }

         return end - start_aligned;
      }

      fn _nextAvailableNodeIndex(self : * @This(), allocator : std.mem.Allocator) std.mem.Allocator.Error!usize {
         for (self.nodes.items, 0..self.nodes.items.len) |*node, i| {
            if (_allocationNodeIsNull(node) == true) {
               return i;
            }
         }

         try self.nodes.resize(allocator, self.nodes.items.len + 1);

         return self.nodes.items.len - 1;
      }

      fn _equalBlocks(block_lhs : * const Allocation, block_rhs : * const Allocation) bool {
         const comparison = block_lhs.offset == block_rhs.offset;

         if (std.debug.runtime_safety == true and comparison == true and block_lhs.bytes != block_rhs.bytes) {
            @panic("overlapping block detected, this is a bug!");
         }

         return comparison;
      }

      fn _removeNode(node_prev : * AllocationNode, node_curr : * AllocationNode) void {
         node_prev.next = node_curr.next;
         _allocationNodeSetNull(node_curr);

         return;
      }

      fn _checkMemoryLeaks(self : * const @This()) void {
         var node_index_curr = self.head;
         while (node_index_curr != NULL_ALLOCATION_NODE_INDEX) {
            const node  = self._getNode(node_index_curr);
            const block = &node.block;

            std.log.err("heap memory leaked at block 0x{x} - 0x{x}", .{block.offset, block.offset + block.bytes});

            node_index_curr = node.next;
         }

         if (self.head != NULL_ALLOCATION_NODE_INDEX) {
            @panic("heap memory leaked");
         }

         return;
      }

      fn _drainTrailingFreeNodes(self : * @This(), allocator : std.mem.Allocator) void {
         var new_length : usize = self.nodes.items.len;
         while (self._getNodeOptional(new_length - 1) == null) {
            new_length -= 1;
         }

         self.nodes.shrinkAndFree(allocator, new_length);
         return;
      }
   };
}

