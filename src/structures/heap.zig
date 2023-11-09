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

      const AllocationNode = struct {
         block : Allocation,
         next  : usize,
      };

      pub fn deinit(self : @This(), allocator : std.mem.Allocator) void {
         _ = self;
         _ = allocator;
         unreachable;
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
   };
}

const NULL_ALLOCATION_NODE_INDEX = std.math.maxInt(usize);

