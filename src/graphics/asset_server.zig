const root     = @import("index.zig");
const std      = @import("std");
const builtin  = @import("builtin");
const math     = @import("math");
const present  = @import("present");
const vulkan   = @import("vulkan/index.zig");
const c        = @import("cimports");

// We find the field with the largest alignment so all subsequent fields stored
// next to each other in memory will the garunteed proper alignment.
const MESH_BYTE_ALIGNMENT = blk: {
   var alignment : comptime_int = 0;

   inline for (@typeInfo(vulkan.types.Vertex).Struct.fields) |field| {
      const field_alignment = @alignOf(field.type);

      if (field_alignment > alignment) {
         alignment = field_alignment;
      }
   }

   break :blk alignment;
};

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

      pub fn destroyAndNull(self : * @This(), allocator : std.mem.Allocator, memory_heap : * vulkan.MemoryHeap) void {
         memory_heap.free(allocator, self.allocation);
         self.setNull();
         return;
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
      c.vkDestroyFence(vk_device, self.vk_fence_transfer_finished, null);
      c.vkFreeCommandBuffers(vk_device, vk_transfer_command_pool, 1, &self.vk_command_buffer_transfer);
      self.loaded.deinit(allocator);
      return;
   }

   pub fn get(self : * const @This(), handle : Handle) * const Object {
      const object = _getMeshObjectFallible(self, handle) orelse {
         switch (std.debug.runtime_safety) {
            true  => @panic("attempted to access invalid mesh"),
            false => unreachable,
         }
      };

      return object;
   }

   pub fn getMut(self : * @This(), handle : Handle) * Object {
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
      Unknown,
      DeviceLost,
   };

   pub fn loadMeshMultiple(self : * @This(), allocator : std.mem.Allocator, load_info : * const LoadInfo, meshes : [] const * const vulkan.types.Mesh, mesh_handles : [] Handle, vk_buffer_copy_regions : [] c.VkBufferCopy) LoadError!void {
      // Quick safety check
      if (std.debug.runtime_safety == true and mesh_handles.len != meshes.len) {
         @panic("mesh handles buffer not the same length as mesh count");
      }
      if (std.debug.runtime_safety == true and vk_buffer_copy_regions.len != mesh_handles.len) {
         @panic("vulkan buffer copy regions buffer not the same length as mesh count");
      }

      // Assign new handle IDs for each mesh
      const loaded_handles_old_len = self.loaded.items.len;
      try _assignMultipleNewHandleId(self, allocator, mesh_handles);
      errdefer self.loaded.shrinkAndFree(allocator, loaded_handles_old_len);

      // Create one large transfer allocation for every mesh
      const transfer_allocation_bytes = _calculateTransferAllocationBytes(meshes);
      const transfer_allocation = try load_info.heap_transfer.memory_heap.allocate(allocator, &.{
         .alignment  = MESH_BYTE_ALIGNMENT,
         .bytes      = transfer_allocation_bytes,
      });
      defer load_info.heap_transfer.memory_heap.free(allocator, transfer_allocation);

      // Iterate through every new mesh handle and initialize its associated mesh object
      var transfer_allocation_mesh_offset : u32 = 0;
      for (meshes, mesh_handles, vk_buffer_copy_regions, 0..meshes.len) |mesh, handle, *vk_buffer_copy_region_dest, i| {
         errdefer for (mesh_handles[0..i]) |handle_old| {
            const object_old = self.getMut(handle_old);
            object_old.destroyAndNull(allocator, &load_info.heap_draw.memory_heap);
         };

         const object_dest = self.getMut(handle);

         const mesh_bytes = _calculateMeshBytes(mesh);

         // TODO: Implement object creation and buffer copy region creation, abstract to function
         const object : Object = if (true) unreachable;
         errdefer object.destroyAndNull(allocator, &load_info.heap_draw.memory_heap);

         // Calculate the copy region, be careful here!  We want to copy the
         // entire contents of the transfer buffer *for this one mesh* at once.
         const vk_buffer_copy_region = c.VkBufferCopy{
            .srcOffset  = transfer_allocation.offset + transfer_allocation_mesh_offset,
            .dstOffset  = object.allocation.offset,
            .size       = mesh_bytes.total,
         };

         // Write the newly created data
         object_dest.*                 = object;
         vk_buffer_copy_region_dest.*  = vk_buffer_copy_region;

         // We need to be careful to use total_aligned so the next mesh
         // stays aligned on its required boundary.
         transfer_allocation_mesh_offset += mesh_bytes.total_aligned;
      }
      errdefer for (mesh_handles) |handle| {
         const object = self.getMut(handle);
         object.destroyAndNull(allocator, &load_info.heap_draw.memory_heap);
      };

      // Record and send the transfer command
      try _sendTransferCommand(self.vk_command_buffer_transfer, self.vk_fence_transfer_finished, load_info, vk_buffer_copy_regions);

      // Wait for the copy command to finish, may make async in the future
      _ = c.vkWaitForFences(load_info.vk_device, 1, &self.vk_fence_transfer_finished, c.VK_TRUE, std.math.maxInt(u64));

      // Success!
      return;
   }

   pub fn unloadMeshMultiple(self : * @This(), allocator : std.mem.Allocator, unload_info : * const UnloadInfo, meshes : [] const Handle) void {
      for (meshes) |handle| {
         const object = self.getMut(handle);

         unload_info.heap_draw.memory_heap.free(allocator, object.allocation);

         object.setNull();
      }
      
      _freeExcessNullMeshes(self, allocator);

      return;
   }
};

fn _getMeshObjectFallible(mesh_asset_server : * const MeshAssetServer, handle : MeshAssetServer.Handle) ? * const MeshAssetServer.Object {
   if (handle >= mesh_asset_server.loaded.items.len) {
      return null;
   }

   const object = &mesh_asset_server.loaded.items[handle];

   if (object.isNull() == true) {
      return null;
   }

   return object;
}

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
      .flags = 0x00000000,
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

fn _freeExcessNullMeshes(mesh_asset_server : * MeshAssetServer, allocator : std.mem.Allocator) void {
   var new_length = mesh_asset_server.loaded.items.len;
   while (new_length != 0 and mesh_asset_server.loaded.items[new_length - 1].isNull() == true) {
      new_length -= 1;
   }

   mesh_asset_server.loaded.shrinkAndFree(allocator, new_length);

   return;
}

fn _assignNewHandleId(mesh_asset_server : * MeshAssetServer, allocator : std.mem.Allocator) MeshAssetServer.LoadError!MeshAssetServer.Handle {
   for (mesh_asset_server.loaded.items, 0..mesh_asset_server.loaded.items.len) |object, i| {
      if (object.isNull() == true) {
         return i;
      }
   }

   try mesh_asset_server.loaded.resize(allocator, mesh_asset_server.loaded.items.len + 1);

   return mesh_asset_server.loaded.items.len - 1;
}

fn _assignMultipleNewHandleId(mesh_asset_server : * MeshAssetServer, allocator : std.mem.Allocator, buffer : [] MeshAssetServer.Handle) MeshAssetServer.LoadError!void {
   const old_size = mesh_asset_server.loaded.items.len;
   errdefer mesh_asset_server.loaded.shrinkAndFree(allocator, old_size);

   for (buffer) |*handle_out| {
      handle_out.* = try _assignNewHandleId(mesh_asset_server, allocator);
   }

   return;
}

fn _calculateTransferAllocationBytes(meshes : [] const * const vulkan.types.Mesh) u32 {
   var bytes_total : u32 = 0;

   for (meshes[0..meshes.len - 1]) |mesh| {
      const bytes_mesh = _calculateMeshBytes(mesh);

      bytes_total += bytes_mesh.total_aligned;
   }

   const bytes_mesh = _calculateMeshBytes(meshes[meshes.len - 1]);
   bytes_total += bytes_mesh.total;

   return bytes_total;
}

const MeshBytes = struct {
   vertices       : u32,
   indices        : u32,
   total          : u32,
   total_aligned  : u32,
};

fn _calculateMeshBytes(mesh : * const vulkan.types.Mesh) MeshBytes {
   const bytes_vertices       = mesh.vertices.len * @sizeOf(vulkan.types.Vertex);
   const bytes_indices        = mesh.indices.len * @sizeOf(vulkan.types.Mesh.IndexElement);
   const bytes_total          = bytes_vertices + bytes_indices;
   const bytes_total_aligned  = math.alignForward(usize, bytes_total, MESH_BYTE_ALIGNMENT);

   return .{
      .vertices      = @intCast(bytes_vertices),
      .indices       = @intCast(bytes_indices),
      .total         = @intCast(bytes_total),
      .total_aligned = @intCast(bytes_total_aligned),
   };
}

fn _sendTransferCommand(vk_command_buffer_transfer : c.VkCommandBuffer, vk_fence_transfer_finished : c.VkFence, load_info : * const MeshAssetServer.LoadInfo, vk_buffer_copy_regions : [] c.VkBufferCopy) MeshAssetServer.LoadError!void {
   var vk_result : c.VkResult = undefined;

   const vk_info_command_buffer_transfer_begin = c.VkCommandBufferBeginInfo{
      .sType            = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .pNext            = null,
      .flags            = 0x00000000,
      .pInheritanceInfo = null,
   };

   vk_result = c.vkBeginCommandBuffer(vk_command_buffer_transfer, &vk_info_command_buffer_transfer_begin);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }

   c.vkCmdCopyBuffer(
      vk_command_buffer_transfer,
      load_info.heap_transfer.memory_heap.vk_buffer,
      load_info.heap_draw.memory_heap.vk_buffer,
      @intCast(vk_buffer_copy_regions.len),
      vk_buffer_copy_regions.ptr,
   );

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
      .pWaitDstStageMask      = undefined,
      .commandBufferCount     = 1,
      .pCommandBuffers        = &vk_command_buffer_transfer,
      .signalSemaphoreCount   = 0,
      .pSignalSemaphores      = undefined,
   };

   vk_result = c.vkQueueSubmit(load_info.vk_queue_transfer, 1, &vk_info_submit, vk_fence_transfer_finished);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_DEVICE_LOST           => return error.DeviceLost,
      else                             => unreachable,
   }

   return;
}

