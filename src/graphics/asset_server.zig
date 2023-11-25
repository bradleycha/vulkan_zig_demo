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
      load_status    : LoadStatus,

      pub const LoadStatusTag = enum {
         pending,
         ready,
      };

      pub const LoadStatus = union(LoadStatusTag) {
         pending  : LoadData,
         ready    : void,
      };

      pub const LoadData = struct {
         allocation_transfer  : vulkan.MemoryHeap.Allocation,
      };

      const NULL_INDICES_COUNT = std.math.maxInt(u32);

      pub fn setNull(self : * @This()) void {
         self.indices = NULL_INDICES_COUNT;
         return;
      }

      pub fn isNull(self : * const @This()) bool {
         return self.indices == NULL_INDICES_COUNT;
      }

      pub fn isPending(self : * const @This()) bool {
         return self.load_status == .pending;
      }

      pub fn destroyAndNull(self : * @This(), allocator : std.mem.Allocator, heap_draw : * vulkan.MemoryHeapDraw, heap_transfer : * vulkan.MemoryHeapTransfer) void {
         switch (self.load_status) {
            .pending => |load_data| {
               heap_transfer.memory_heap.free(allocator, load_data.allocation_transfer);
            },
            .ready   => {},
         }

         heap_draw.memory_heap.free(allocator, self.allocation);
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
      meshes                  : [] const * const vulkan.types.Mesh,
      load_buffers_pointers   : * const LoadBuffersPointers,
      vk_device               : c.VkDevice,
      vk_queue_transfer       : c.VkQueue,
      heap_draw               : * vulkan.MemoryHeapDraw,
      heap_transfer           : * vulkan.MemoryHeapTransfer,
   };

   pub fn LoadBuffersStatic(comptime count : comptime_int) type {
      return struct {
         mesh_handles            : [count] Handle,
         vk_buffer_copy_regions  : [count] c.VkBufferCopy,

         pub fn toPointers(self : * @This()) LoadBuffersPointers {
            var pointers : LoadBuffersPointers = undefined;
            pointers.mesh_handles            = &self.mesh_handles;
            pointers.vk_buffer_copy_regions  = &self.vk_buffer_copy_regions;

            if (@hasField(LoadBuffersPointers, "count") == true) {
               pointers.count = count;
            }

            return pointers;
         }
      };
   }

   pub const LoadBuffersDynamic = struct {
      mesh_handles            : [*] Handle,
      vk_buffer_copy_regions  : [*] c.VkBufferCopy,
      count                   : usize,

      pub const InitError = error {
         OutOfMemory,
      };

      pub fn init(allocator : std.mem.Allocator, count : usize) InitError!@This() {
         const mesh_handles = try allocator.alloc(Handle, count);
         errdefer allocator.free(mesh_handles);

         const vk_buffer_copy_regions = try allocator.alloc(c.VkBufferCopy, count);
         errdefer allocator.free(vk_buffer_copy_regions);

         return @This(){
            .mesh_handles           = mesh_handles.ptr,
            .vk_buffer_copy_regions = vk_buffer_copy_regions.ptr,
            .count                  = count,
         };
      }

      pub fn deinit(self : @This(), allocator : std.mem.Allocator) void {
         allocator.free(self.mesh_handles[0..self.count]);
         allocator.free(self.vk_buffer_copy_regions[0..self.count]);
         return;
      }

      pub fn toPointers(self : * @This()) LoadBuffersPointers {
         var pointers : LoadBuffersPointers = undefined;
         pointers.mesh_handles            = self.mesh_handles;
         pointers.vk_buffer_copy_regions  = self.vk_buffer_copy_regions;

         if (@hasField(LoadBuffersPointers, "count") == true) {
            pointers.count = self.count;
         }

         return pointers;
      }
   };

   // We do this so we can have very trim structs in fast release builds while
   // also allowing for runtime safety in debug / release-safe builds.  Raw
   // pointers accompanied by a count field are used instead of slices because
   // it's reduntant to store slices for every field.
   pub const LoadBuffersPointers = blk: {
      switch (std.debug.runtime_safety) {
         true  => break :blk LoadBuffersPointersChecked,
         false => break :blk LoadBuffersPointersUnchecked,
      }
   };

   const LoadBuffersPointersChecked = struct {
      mesh_handles            : [*] Handle,
      vk_buffer_copy_regions  : [*] c.VkBufferCopy,
      count                   : usize,
   };

   const LoadBuffersPointersUnchecked = struct {
      mesh_handles            : [*] Handle,
      vk_buffer_copy_regions  : [*] c.VkBufferCopy,
   };

   pub const LoadError = error {
      OutOfMemory,
      Unknown,
      DeviceLost,
   };

   pub const UnloadInfo = struct {
      meshes         : [] const Handle,
      vk_device      : c.VkDevice,
      heap_draw      : * vulkan.MemoryHeapDraw,
      heap_transfer  : * vulkan.MemoryHeapTransfer,
   };

   pub fn loadMeshMultiple(self : * @This(), allocator : std.mem.Allocator, load_info : * const LoadInfo) LoadError!void {
      const meshes                  = load_info.meshes;
      const mesh_handles            = load_info.load_buffers_pointers.mesh_handles[0..meshes.len];
      const vk_buffer_copy_regions  = load_info.load_buffers_pointers.vk_buffer_copy_regions[0..meshes.len];

      // Debug-only runtime safety checks
      if (std.debug.runtime_safety == true and @hasField(LoadBuffersPointers, "count")) {
         const meshes_count                  = meshes.len;
         const mesh_buffers_pointers_count   = load_info.load_buffers_pointers.count;

         if (meshes_count > mesh_buffers_pointers_count) {
            @panic("mesh load count exceeds mesh buffers length");
         }
      }

      // Assign new handle IDs for each mesh
      const loaded_handles_old_len = self.loaded.items.len;
      try _assignMultipleNewHandleId(self, allocator, mesh_handles);
      errdefer self.loaded.shrinkAndFree(allocator, loaded_handles_old_len);

      // Iterate through every new mesh handle and initialize its associated mesh object
      for (meshes, mesh_handles, vk_buffer_copy_regions, 0..meshes.len) |mesh, handle, *vk_buffer_copy_region_dest, i| {
         errdefer for (mesh_handles[0..i]) |handle_old| {
            const object_old = self.getMut(handle_old);
            object_old.destroyAndNull(allocator, load_info.heap_draw, load_info.heap_transfer);
         };

         const object_dest = self.getMut(handle);

         // Calculate bytes for the current mesh
         const mesh_bytes = _calculateMeshBytes(mesh);

         // Create the transfer and draw heap allocations
         const allocation_info = vulkan.MemoryHeap.AllocateInfo{
            .alignment  = MESH_BYTE_ALIGNMENT,
            .bytes      = mesh_bytes.total,
         };

         const object_allocation_transfer = try load_info.heap_transfer.memory_heap.allocate(allocator, &allocation_info);
         errdefer load_info.heap_transfer.memory_heap.free(allocator, object_allocation_transfer);

         const object_allocation_draw = try load_info.heap_draw.memory_heap.allocate(allocator, &allocation_info);
         errdefer load_info.heap_draw.memory_heap.free(allocator, object_allocation_draw);

         // Calculate pointers for the transfer allocation
         const mesh_pointers = _calculateMeshPointers(&mesh_bytes, load_info.heap_transfer.mapping, object_allocation_transfer.offset);

         // Create the backing object for the mesh
         const object = _createMeshObject(mesh, object_allocation_transfer, object_allocation_draw);
         errdefer object.destroyAndNull(allocator, load_info.heap_draw, load_info.heap_transfer);

         // Copy the mesh data into the transfer buffer
         @memcpy(mesh_pointers.vertices, mesh.vertices);
         @memcpy(mesh_pointers.indices, mesh.indices);

         // Calculate the copy region
         const vk_buffer_copy_region = c.VkBufferCopy{
            .srcOffset  = object_allocation_transfer.offset,
            .dstOffset  = object_allocation_draw.offset,
            .size       = mesh_bytes.total,
         };

         // Write the newly created data
         object_dest.*                 = object;
         vk_buffer_copy_region_dest.*  = vk_buffer_copy_region;
      }
      errdefer for (mesh_handles) |handle| {
         const object = self.getMut(handle);
         object.destroyAndNull(allocator, load_info.heap_draw, load_info.heap_transfer);
      };

      // Wait for the previous transfer command to finish and reset the fence once complete
      try _waitOnFence(load_info.vk_device, self.vk_fence_transfer_finished);
      try _resetFence(load_info.vk_device, self.vk_fence_transfer_finished);

      // Record and send the transfer command
      try _sendTransferCommand(self.vk_command_buffer_transfer, self.vk_fence_transfer_finished, load_info, vk_buffer_copy_regions);

      // Success!
      return;
   }

   pub fn unloadMeshMultiple(self : * @This(), allocator : std.mem.Allocator, unload_info : * const UnloadInfo) void {
      const meshes = unload_info.meshes;

      // Wait for the previous transfer command to finish to prevent race conditions
      _waitOnFence(unload_info.vk_device, self.vk_fence_transfer_finished) catch |err| {
         if (std.debug.runtime_safety == false) {
            unreachable;
         }

         switch (err) {
            inline else => |tag| {
               @panic("failed to wait on vulkan fence: " ++ @errorName(tag));
            },
         }

         unreachable;
      };

      for (meshes) |handle| {
         const object = self.getMut(handle);

         switch (object.load_status) {
            .pending => |load_data| {
               unload_info.heap_transfer.memory_heap.free(allocator, load_data.allocation_transfer);
            },
            .ready   => {},
         }

         unload_info.heap_draw.memory_heap.free(allocator, object.allocation);

         object.setNull();
      }
      
      _freeExcessNullMeshes(self, allocator);

      return;
   }

   pub fn pollMeshLoadStatus(self : * @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice, heap_transfer : * vulkan.MemoryHeapTransfer, meshes : [] const Handle) void {
      const vk_fence_transfer_finished_status = _fenceIsSignaled(vk_device, self.vk_fence_transfer_finished) catch |err| {
         if(std.debug.runtime_safety == false) {
            unreachable;
         }

         switch (err) {
            inline else => |tag| {
               @panic("failed to query vulkan fence status: " ++ @errorName(tag));
            },
         }

         unreachable;
      };

      if (vk_fence_transfer_finished_status == false) {
         return;
      }

      for (meshes) |handle| {
         const object = self.getMut(handle);

         if (object.isNull()) {
            continue;
         }

         if (object.isPending() == false) {
            continue;
         }

         heap_transfer.memory_heap.free(allocator, object.load_status.pending.allocation_transfer);
         object.load_status = .ready;
      }

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

fn _calculateTransferAllocationMappingOffset(heap : * const vulkan.MemoryHeapTransfer, allocation : * const vulkan.MemoryHeap.Allocation) * anyopaque {
   const base_ptr = heap.mapping;
   const offset   = allocation.offset;

   const offset_int_ptr = @intFromPtr(base_ptr) + offset;
   const offset_ptr     = @as(* anyopaque, @ptrFromInt(offset_int_ptr));

   return offset_ptr;
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

const MeshPointers = struct {
   vertices : [*] vulkan.types.Vertex,
   indices  : [*] vulkan.types.Mesh.IndexElement,
};

fn _calculateMeshPointers(bytes : * const MeshBytes, mapping : * anyopaque, offset : u32) MeshPointers {
   const base_int_ptr   = @intFromPtr(mapping) + offset;

   const vertices_int_ptr  = base_int_ptr;
   const indices_int_ptr   = vertices_int_ptr + bytes.vertices;

   const vertices_ptr   = @as([*] vulkan.types.Vertex, @ptrFromInt(vertices_int_ptr));
   const indices_ptr    = @as([*] vulkan.types.Mesh.IndexElement, @ptrFromInt(indices_int_ptr));

   return .{
      .vertices   = vertices_ptr,
      .indices    = indices_ptr,
   };
}

fn _createMeshObject(mesh : * const vulkan.types.Mesh, allocation_transfer : vulkan.MemoryHeap.Allocation, allocation_draw : vulkan.MemoryHeap.Allocation) MeshAssetServer.Object {
   const transform_mesh = math.Matrix4(f32).IDENTITY;

   const push_constants = vulkan.types.PushConstants{
      .transform_mesh   = transform_mesh,
   };

   const indices = @as(u32, @intCast(mesh.indices.len));

   return .{
      .push_constants   = push_constants,
      .allocation       = allocation_draw,
      .indices          = indices,
      .load_status      = .{.pending = .{.allocation_transfer = allocation_transfer}},
   };
}

fn _waitOnFence(vk_device : c.VkDevice, vk_fence : c.VkFence) MeshAssetServer.LoadError!void {
   var vk_result : c.VkResult = undefined;

   vk_result = c.vkWaitForFences(vk_device, 1, &vk_fence, c.VK_FALSE, std.math.maxInt(u64));

   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_TIMEOUT                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_DEVICE_LOST           => return error.DeviceLost,
      else                             => unreachable,
   }

   return;
}

fn _resetFence(vk_device : c.VkDevice, vk_fence : c.VkFence) MeshAssetServer.LoadError!void {
   var vk_result : c.VkResult = undefined;

   vk_result = c.vkResetFences(vk_device, 1, &vk_fence);

   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.DeviceLost,
      else                             => unreachable,
   }

   return;
}

fn _fenceIsSignaled(vk_device : c.VkDevice, vk_fence : c.VkFence) MeshAssetServer.LoadError!bool {
   var vk_result : c.VkResult = undefined;

   vk_result = c.vkGetFenceStatus(vk_device, vk_fence);

   switch (vk_result) {
      c.VK_SUCCESS            => return true,
      c.VK_NOT_READY          => return false,
      c.VK_ERROR_DEVICE_LOST  => return error.DeviceLost,
      else                    => unreachable,
   }

   unreachable;
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

