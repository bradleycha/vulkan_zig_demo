const std      = @import("std");
const builtin  = @import("builtin");
const dbg      = @import("dbg.zig");

/// The global default allocator to use.  This allocator should be used for
/// large, long-lifetime allocations.  Linking requires libc because in debug
/// builds, the raw libc allocator is used.
pub const allocator = blk: {
   if (dbg.enable == true) {
      break :blk std.heap.page_allocator;
   } else {
      break :blk std.heap.raw_c_allocator;
   }
};

/// Creates a small pool of memory used for accelerating small, temporary
/// allocations which are contained within a single scope, such as a read
/// buffer for a C API.  Since memory is limited to a small amount, it is
/// recommended to use a proper allocator for large allocations which can
/// exist across scopes, such as media resources.  The performance gains
/// can be dramatic, in testing up to 40x faster than the raw libc allocator.
/// If created n a global scope, system memory will still be used in the form
/// of .bss section memory.  If created in a local scope, stack memory will
/// be used.  This can be especially problematic for systems with little stack
/// memory, so it's recommended to create one medium-sized instance with global
/// scope.  This is not thread-safe, so each thread should get its own heap.
pub fn SingleScopeHeap(
   comptime bytes : usize,
) type {
   return struct {
      pub const HEAP_SIZE_BYTES = bytes;

      var _HeapData : [@This().HEAP_SIZE_BYTES] u8 = undefined;
      var _Heap = std.heap.FixedBufferAllocator.init(&@This()._HeapData);

      pub fn allocator() std.mem.Allocator {
         return @This()._Heap.allocator();
      }
   };
}

