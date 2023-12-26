const std      = @import("std");
const math     = @import("math");
const c        = @import("cimports");
const vulkan   = @import("vulkan/index.zig");

const AssetLoader = @This();

load_items                 : std.ArrayList(LoadItem),
vk_command_buffer_transfer : c.VkCommandBuffer,
vk_fence_ready             : c.VkFence,
allocation_transfer        : vulkan.MemoryHeap.Allocation,

pub const LoadItem = struct {
   status   : Status,
   variant  : Variant,

   pub const Status = enum {
      pending,    // currently being loaded
      ready,      // ready for use
      destroyed,  // slot available for use by another item
   };

   pub const VariantTag = enum {
      mesh,
      texture,
   };

   pub const Variant = union(VariantTag) {
      mesh     : Mesh,
      texture  : Texture,
   };
};

pub const Mesh = struct {
   push_constants : vulkan.types.PushConstants,
   allocation     : vulkan.MemoryHeap.Allocation,
   indices        : u32,
};

pub const Texture = struct {
   // TODO: Will need image view, sampler, and descriptor set in the future
   image : vulkan.Image,
};

// Generic handle type associated with all load items.
pub const Handle = usize;

pub const CreateError = error {
   OutOfMemory,
};

pub const CreateInfo = struct {
   vk_device                  : c.VkDevice,
   vk_command_pool_transfer   : c.VkCommandPool,
};

pub fn create(create_info : * const CreateInfo) CreateError!AssetLoader {
   // TODO: Implement
   _ = create_info;
   unreachable;
}

pub const DestroyInfo = struct {
   vk_device                  : c.VkDevice,
   vk_command_pool_transfer   : c.VkCommandPool,
};

pub fn destroy(self : * AssetLoader, allocator : std.mem.Allocator, destroy_info : * const DestroyInfo) void {
   // TODO: Implement
   _ = self;
   _ = allocator;
   _ = destroy_info;
   unreachable;
}

pub const LoadBuffers = blk: {
   switch (std.debug.runtime_safety) {
      true  => break :blk _LoadBuffersChecked,
      false => break :blk _LoadBuffersUnchecked,
   }

   unreachable;
};

const _LoadBuffersChecked = struct {
   counts   : LoadBuffersArraySize,
   handles  : [*] Handle,
};

const _LoadBuffersUnchecked = struct {
   handles  : [*] Handle,
};

pub const LoadBuffersArraySize = struct {
   meshes   : usize,
   textures : usize,
};

pub fn LoadBuffersArrayStatic(comptime COUNTS : * const LoadBuffersArraySize) type {
   return struct {
      handles  : [COUNTS.meshes + COUNTS.textures] Handle,

      pub fn getBuffers(self : * @This()) LoadBuffers {
         var load_buffers : LoadBuffers = undefined;

         load_buffers.handles = &self.handles;

         if (@hasField(LoadBuffers, "counts") == true) {
            load_buffers.counts = COUNTS.*;
         }

         return load_buffers;
      }
   };
}

pub const LoadItems = struct {
   meshes   : [] const @This().Mesh,
   textures : [] const @This().Texture,

   pub const Mesh = struct {
      push_constants : vulkan.types.PushConstants,
      data           : * const vulkan.types.Mesh,
   };

   pub const Texture = struct {
      // TODO: Implement
   };
};

pub const LoadInfo = struct {
   // TODO: Implement
};

pub const LoadError = error {
   // TODO: Implement
};

pub fn load(self : * AssetLoader, load_buffers : * const LoadBuffers, load_items : * const LoadItems, load_info : * const LoadInfo) LoadError!void {
   // TODO: Implement
   _ = self;
   _ = load_buffers;
   _ = load_items;
   _ = load_info;
   unreachable;
}

pub const UnloadInfo = struct {
   // TODO: Implement
};

pub fn unload(self : * AssetLoader, handles : [] const Handle, unload_info : * const UnloadInfo) void {
   _ = self;
   _ = handles;
   _ = unload_info;
   unreachable;
}

pub fn get(self : * const AssetLoader, handle : Handle) * const LoadItem {
   // TODO: Implement
   _ = self;
   _ = handle;
   unreachable;
}

pub fn getMut(self : * AssetLoader, handle : Handle) * LoadItem {
   // TODO: Implement
   _ = self;
   _ = handle;
   unreachable;
}

pub const PollInfo = struct {
   // TODO: Implement
};

pub fn poll(self : * AssetLoader, handle : Handle, poll_info : * const PollInfo) void {
   // TODO: Implement
   _ = self;
   _ = handle;
   _ = poll_info;
   unreachable;
}

