const root     = @import("index.zig");
const std      = @import("std");
const builtin  = @import("builtin");
const present  = @import("present");
const vulkan   = @import("vulkan/index.zig");
const c        = @import("cimports");

pub const MeshAssetServer = struct {
   loaded                     : std.ArrayListUnmanaged(Object) = .{},
   vk_command_buffer_transfer : c.VkCommandBuffer,
   vk_fence_transfer_finished : c.VkFence,

   pub const Handle = usize;

   pub const Object = struct {
      push_constants : vulkan.types.PushConstants,
      allocation     : vulkan.MemoryHeap.Allocation,
      indices        : u32,

      const NULL_INDICES_COUNT = std.math.maxInt(u32);

      pub fn setNull(self : * @This()) void {
         self.indices = NULL_INDICES_COUNT;
         return;
      }

      pub fn isNull(self : * const @This()) bool {
         return self.indices == NULL_INDICES_COUNT;
      }
   };

   pub const CreateInfo = struct {
      vk_device                  : c.VkDevice,
      vk_transfer_command_pool   : c.VkCommandPool,
   };

   pub const CreateError = error {
      OutOfMemory,
   };

   pub fn create(create_info : * const CreateInfo) CreateError!@This() {
      const vk_device                  = create_info.vk_device;
      const vk_transfer_command_pool   = create_info.vk_transfer_command_pool;

      const vk_command_buffer_transfer = try _createTransferCommandBuffer(vk_device, vk_transfer_command_pool);
      errdefer c.vkFreeCommandBuffers(vk_device, vk_transfer_command_pool, 1, &vk_command_buffer_transfer);

      const vk_fence_transfer_finished = try _createTransferFence(vk_device);
      errdefer c.vkDestroyFence(vk_device, vk_fence_transfer_finished, null);

      return @This(){
         .loaded                       = .{},
         .vk_command_buffer_transfer   = vk_command_buffer_transfer,
         .vk_fence_transfer_finished   = vk_fence_transfer_finished,
      };
   }

   pub fn destroy(self : * @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice, vk_transfer_command_pool : c.VkCommandPool) void {
      _waitFence(vk_device, self.vk_fence_transfer_finished);

      c.vkDestroyFence(vk_device, self.vk_fence_transfer_finished, null);
      c.vkFreeCommandBuffers(vk_device, vk_transfer_command_pool, 1, &self.vk_command_buffer_transfer);
      self.loaded.deinit(allocator);
      return;
   }

   pub fn get(self : * const @This(), handle : Handle) ? * const Object {
      if (handle >= self.loaded.items.len) {
         return null;
      }

      const object = &self.loaded.items[handle];

      if (object.isNull() == true) {
         return null;
      }

      return object;
   }

   pub fn getMut(self : * @This(), handle : Handle) ? * Object {
      return @constCast(self.get(handle));
   }

   pub const LoadInfo = struct {
      vk_device         : c.VkDevice,
      vk_queue_transfer : c.VkQueue,
      heap_draw         : * vulkan.MemoryHeapDraw,
      heap_transfer     : * vulkan.MemoryHeapTransfer,
   };

   pub const UnloadInfo = struct {
      vk_device   : c.VkDevice,
      heap_draw   : * vulkan.MemoryHeapDraw,
   };

   pub const LoadError = error {
      OutOfMemory,
   };

   pub fn loadMeshMultiple(self : * @This(), allocator : std.mem.Allocator, load_info : * const LoadInfo, meshes : [] const * const vulkan.types.Mesh, mesh_handles : [] Handle) LoadError!void {
      _waitFence(load_info.vk_device, self.vk_fence_transfer_finished);

      _ = allocator;
      _ = meshes;
      _ = mesh_handles;
      unreachable;
   }

   pub fn unloadMeshMultiple(self : * @This(), allocator : std.mem.Allocator, unload_info : * const UnloadInfo, meshes : [] const Handle) void {
      _waitFence(unload_info.vk_device, self.vk_fence_transfer_finished);

      _ = allocator;
      _ = meshes;
      unreachable;
   }
};

fn _createTransferCommandBuffer(vk_device : c.VkDevice, vk_transfer_command_pool : c.VkCommandPool) MeshAssetServer.CreateError!c.VkCommandBuffer {
   var vk_result : c.VkResult = undefined;

   const vk_info_allocate_command_buffer = c.VkCommandBufferAllocateInfo{
      .sType               = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .pNext               = null,
      .commandPool         = vk_transfer_command_pool,
      .level               = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      .commandBufferCount  = 1,
   };

   var vk_command_buffer : c.VkCommandBuffer = undefined;
   vk_result = c.vkAllocateCommandBuffers(vk_device, &vk_info_allocate_command_buffer, &vk_command_buffer);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }
   errdefer c.vkFreeCommandBuffers(vk_device, vk_transfer_command_pool, 1, &vk_command_buffer);

   return vk_command_buffer;
}

fn _createTransferFence(vk_device : c.VkDevice) MeshAssetServer.CreateError!c.VkFence {
   var vk_result : c.VkResult = undefined;

   const vk_info_create_fence = c.VkFenceCreateInfo{
      .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
      .pNext = null,
      .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
   };

   var vk_fence : c.VkFence = undefined;
   vk_result = c.vkCreateFence(vk_device, &vk_info_create_fence, null, &vk_fence);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }
   errdefer c.vkDestroyFence(vk_device, vk_fence, null);

   return vk_fence;
}

fn _waitFence(vk_device : c.VkDevice, vk_fence : c.VkFence) void {
   var vk_result : c.VkResult = undefined;

   vk_result = c.vkWaitForFences(vk_device, 1, &vk_fence, c.VK_TRUE, std.math.maxInt(u64));

   if (std.debug.runtime_safety == false) {
      return;
   }

   const ERRMSG = "failed to wait for vulkan fence: ";
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_TIMEOUT                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => @panic(ERRMSG ++ "out of host memory"),
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => @panic(ERRMSG ++ "out of device memory"),
      c.VK_ERROR_DEVICE_LOST           => @panic(ERRMSG ++ "device lost"),
      else                             => unreachable,
   }

   return;
}

