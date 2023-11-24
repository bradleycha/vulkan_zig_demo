const root     = @import("index.zig");
const std      = @import("std");
const builtin  = @import("builtin");
const math     = @import("math");
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

   pub fn loadMeshMultiple(self : * @This(), allocator : std.mem.Allocator, load_info : * const LoadInfo, meshes : [] const * const vulkan.types.Mesh, mesh_handles : [] Handle) LoadError!void {
      var vk_result : c.VkResult = undefined;

      // Quick safety check
      if (std.debug.runtime_safety == true and meshes.len != mesh_handles.len) {
         @panic("mesh handles buffer not the same length as mesh count");
      }

      // Calculate total bytes needed for every transfer operation
      var bytes_transfer_total : u32 = 0;
      for (meshes) |mesh| {
         const bytes = _meshByteCounts(mesh);

         bytes_transfer_total += @intCast(bytes.total_aligned);
      }

      // Create transfer allocation for every transfer operation
      const allocation_transfer = try load_info.heap_transfer.memory_heap.allocate(allocator, &.{
         .alignment  = @alignOf(vulkan.types.Mesh),
         .bytes      = bytes_transfer_total,
      });
      defer load_info.heap_transfer.memory_heap.free(allocator, allocation_transfer);

      // Assign new IDs for each mesh
      const loaded_old_size = self.loaded.items.len;
      for (mesh_handles) |*mesh_handle_out| {
         const new_id = try _assignNewHandleId(self, allocator);

         mesh_handle_out.* = new_id;
      }
      errdefer self.loaded.shrinkAndFree(allocator, loaded_old_size);

      // Start recording of the transfer command buffer
      const vk_info_command_buffer_transfer_begin = c.VkCommandBufferBeginInfo{
         .sType            = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
         .pNext            = null,
         .flags            = 0x00000000,
         .pInheritanceInfo = null,
      };

      vk_result = c.vkBeginCommandBuffer(self.vk_command_buffer_transfer, &vk_info_command_buffer_transfer_begin);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }

      // Initialize each new mesh object and add it to the command pool for transferring
      var bytes_transfer_offset : u32 = 0;
      for (meshes, mesh_handles, 0..meshes.len) |mesh, handle, i| {
         errdefer for (mesh_handles[0..i]) |handle_old| {
            const object_old = self.getMut(handle_old);

            load_info.heap_draw.memory_heap.free(allocator, object_old.allocation);
            object_old.setNull();
         };

         const object   = self.getMut(handle);
         const bytes    = _meshByteCounts(mesh);
         const mapping  = load_info.heap_transfer.mapping;
         const ptrs     = _meshByteOffsetPointers(&bytes, mapping, bytes_transfer_offset);

         const transform_mesh = math.Matrix4(f32).IDENTITY;

         const push_constants = vulkan.types.PushConstants{
            .transform_mesh   = transform_mesh,
         };

         const allocation_draw = try load_info.heap_draw.memory_heap.allocate(allocator, &.{
            .alignment  = @alignOf(vulkan.types.Vertex),
            .bytes      = bytes.total,
         });
         errdefer load_info.heap_draw.memory_heap.free(allocation_draw);

         @memcpy(ptrs.vertices, mesh.vertices);
         @memcpy(ptrs.indices, mesh.indices);

         const vk_buffer_copy_region = c.VkBufferCopy{
            .srcOffset  = allocation_transfer.offset + bytes_transfer_offset,
            .dstOffset  = allocation_draw.offset,
            .size       = bytes.total,
         };

         c.vkCmdCopyBuffer(
            self.vk_command_buffer_transfer,
            load_info.heap_transfer.memory_heap.vk_buffer,
            load_info.heap_draw.memory_heap.vk_buffer,
            1,
            &vk_buffer_copy_region,
         );

         object.* = .{
            .push_constants   = push_constants,
            .allocation       = allocation_draw,
            .indices          = @intCast(mesh.indices.len),
         };

         bytes_transfer_offset += @intCast(bytes.total_aligned);
      }
      errdefer for (mesh_handles) |handle| {
         const object = self.getMut(handle);

         load_info.heap_draw.memory_heap.free(allocator, object.allocation);

         object.setNull();
      };

      vk_result = c.vkEndCommandBuffer(self.vk_command_buffer_transfer);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => return error.Unknown,
      }

      // Submit the transfer command to the GPU
      const vk_info_submit = c.VkSubmitInfo{
         .sType                  = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
         .pNext                  = null,
         .waitSemaphoreCount     = 0,
         .pWaitSemaphores        = undefined,
         .pWaitDstStageMask      = undefined,
         .commandBufferCount     = 1,
         .pCommandBuffers        = &self.vk_command_buffer_transfer,
         .signalSemaphoreCount   = 0,
         .pSignalSemaphores      = undefined,
      };

      vk_result = c.vkQueueSubmit(load_info.vk_queue_transfer, 1, &vk_info_submit, self.vk_fence_transfer_finished);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_DEVICE_LOST           => return error.DeviceLost,
         else                             => unreachable,
      }

      // Wait for the copy command to finish, asynchronous is hard
      vk_result = c.vkWaitForFences(load_info.vk_device, 1, &self.vk_fence_transfer_finished, c.VK_TRUE, std.math.maxInt(u64));
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_TIMEOUT                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_DEVICE_LOST           => return error.DeviceLost,
         else                             => unreachable,
      }

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

const MeshByteCounts = struct {
   vertices       : u32,
   indices        : u32,
   total          : u32,
   total_aligned  : u32,
};

fn _meshByteCounts(mesh : * const vulkan.types.Mesh) MeshByteCounts {
   const ALIGNMENT = @alignOf(vulkan.types.Vertex);

   const bytes_vertices = mesh.vertices.len * @sizeOf(vulkan.types.Vertex);
   const bytes_indices  = mesh.indices.len * @sizeOf(vulkan.types.Mesh.IndexElement);
   const total          = bytes_vertices + bytes_indices;
   const total_aligned  = total + ALIGNMENT - (total % ALIGNMENT);

   return .{
      .vertices      = @intCast(bytes_vertices),
      .indices       = @intCast(bytes_indices),
      .total         = @intCast(total),
      .total_aligned = @intCast(total_aligned),
   };
}

const MeshByteOffsetPointers = struct {
   vertices : [*] vulkan.types.Vertex,
   indices  : [*] vulkan.types.Mesh.IndexElement,
};

fn _meshByteOffsetPointers(bytes : * const MeshByteCounts, base : * anyopaque, offset : u32) MeshByteOffsetPointers {
   const int_ptr_vertices  = @intFromPtr(base) + offset;
   const int_ptr_indices   = @intFromPtr(base) + offset + bytes.vertices;

   const ptr_vertices   = @as([*] vulkan.types.Vertex, @ptrFromInt(int_ptr_vertices));
   const ptr_indices    = @as([*] vulkan.types.Mesh.IndexElement, @ptrFromInt(int_ptr_indices));

   return .{
      .vertices   = ptr_vertices,
      .indices    = ptr_indices,
   };
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

