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

pub const AssetServer = struct {
   mesh_objects               : std.ArrayListUnmanaged(MeshObject),
   texture_objects            : std.ArrayListUnmanaged(TextureObject),
   vk_command_buffer_transfer : c.VkCommandBuffer,
   vk_fence_transfer_finished : c.VkFence,
   allocation_transfer        : vulkan.MemoryHeap.Allocation,

   pub const MeshHandle = usize;

   pub const TextureHandle = usize;

   pub const MeshObject = struct {
      push_constants : vulkan.types.PushConstants,
      allocation     : vulkan.MemoryHeap.Allocation,
      indices        : u32,
      load_status    : LoadStatus,

      const NULL_INDICES_COUNT = std.math.maxInt(u32);

      pub fn setNull(self : * @This()) void {
         self.indices = NULL_INDICES_COUNT;
         return;
      }

      pub fn isNull(self : * const @This()) bool {
         return self.indices == NULL_INDICES_COUNT;
      }
   };

   pub const TextureObject = struct {
      image       : vulkan.Image,
      // TODO: Add image view, sampler, descriptor set
      load_status : LoadStatus,

      const NULL_VK_IMAGE = @as(c.VkImage, @ptrCast(c.VK_NULL_HANDLE));

      pub fn setNull(self : * @This()) void {
         self.image.vk_image = NULL_VK_IMAGE;
      }
      
      pub fn isNull(self : * const @This()) bool {
         return self.image.vk_image == NULL_VK_IMAGE;
      }

      pub fn destroy(self : * @This(), vk_device : c.VkDevice) void {
         self.image.destroy(vk_device);
         return;
      }

      pub fn destroyAndNull(self : * @This()) void {
         self.destory();

         self.setNull();
         return;
      }
   };

   pub const LoadStatus = enum {
      pending,
      ready,
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
         .mesh_objects                 = .{},
         .texture_objects              = .{},
         .vk_command_buffer_transfer   = vk_command_buffer_transfer,
         .vk_fence_transfer_finished   = vk_fence_transfer_finished,
         .allocation_transfer          = .{.offset = NULL_ALLOCATION_OFFSET, .bytes = undefined},
      };
   }

   pub fn destroy(self : * @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice, vk_transfer_command_pool : c.VkCommandPool) void {
      c.vkDestroyFence(vk_device, self.vk_fence_transfer_finished, null);
      c.vkFreeCommandBuffers(vk_device, vk_transfer_command_pool, 1, &self.vk_command_buffer_transfer);
      self.texture_objects.deinit(allocator);
      self.mesh_objects.deinit(allocator);
      return;
   }

   pub fn getMesh(self : * const @This(), handle : MeshHandle) * const MeshObject {
      const object = _getMeshObjectFallible(self, handle) orelse {
         switch (std.debug.runtime_safety) {
            true  => @panic("attempted to access invalid mesh"),
            false => unreachable,
         }
      };

      return object;
   }

   pub fn getMeshMut(self : * @This(), handle : MeshHandle) * MeshObject {
      return @constCast(self.getMesh(handle));
   }

   pub fn getTexture(self : * const @This(), handle : TextureHandle) * const TextureObject {
      const object = _getTextureObjectFallible(self, handle) orelse {
         switch (std.debug.runtime_safety) {
            true  => @panic("attempted to access invalid texture"),
            false => unreachable,
         }
      };

      return object;
   }

   pub fn getTextureMut(self : * @This(), handle : TextureHandle) * TextureObject {
      return @constCast(self.getTexture(handle));
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
         mesh_handles            : [count] MeshHandle,
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
      mesh_handles            : [*] MeshHandle,
      vk_buffer_copy_regions  : [*] c.VkBufferCopy,
      count                   : usize,

      pub const InitError = error {
         OutOfMemory,
      };

      pub fn init(allocator : std.mem.Allocator, count : usize) InitError!@This() {
         const mesh_handles = try allocator.alloc(MeshHandle, count);
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
      mesh_handles            : [*] MeshHandle,
      vk_buffer_copy_regions  : [*] c.VkBufferCopy,
      count                   : usize,
   };

   const LoadBuffersPointersUnchecked = struct {
      mesh_handles            : [*] MeshHandle,
      vk_buffer_copy_regions  : [*] c.VkBufferCopy,
   };

   pub const LoadError = error {
      OutOfMemory,
      Unknown,
      DeviceLost,
   };

   pub const UnloadInfo = struct {
      meshes         : [] const MeshHandle,
      vk_device      : c.VkDevice,
      heap_draw      : * vulkan.MemoryHeapDraw,
      heap_transfer  : * vulkan.MemoryHeapTransfer,
   };

   pub fn loadMeshMultiple(self : * @This(), allocator : std.mem.Allocator, load_info : * const LoadInfo) LoadError!void {
      // Debug-only runtime safety checks
      if (std.debug.runtime_safety == true and @hasField(LoadBuffersPointers, "count")) {
         const meshes_count                  = load_info.meshes.len;
         const mesh_buffers_pointers_count   = load_info.load_buffers_pointers.count;

         if (meshes_count > mesh_buffers_pointers_count) {
            @panic("mesh load count exceeds mesh buffers length");
         }
      }

      const meshes                  = load_info.meshes;
      const mesh_handles            = load_info.load_buffers_pointers.mesh_handles[0..meshes.len];
      const vk_buffer_copy_regions  = load_info.load_buffers_pointers.vk_buffer_copy_regions[0..meshes.len];

      // Calculate the required size for the transfer allocation
      const allocation_transfer_bytes = blk: {
         var sum : u32 = 0;

         for (meshes) |mesh| {
            const mesh_bytes = _calculateMeshBytes(mesh);

            sum += mesh_bytes.total_aligned;
         }

         break :blk sum;
      };

      // Create the unified transfer allocation
      const allocation_transfer = try load_info.heap_transfer.memory_heap.allocate(allocator, &.{
         .alignment  = MESH_BYTE_ALIGNMENT,
         .bytes      = allocation_transfer_bytes,
      });
      errdefer load_info.heap_transfer.memory_heap.free(allocator, allocation_transfer);

      // Assign new handle IDs for each mesh
      const mesh_objects_old_len = self.mesh_objects.items.len;
      try _assignMultipleNewHandleId(self, allocator, mesh_handles);
      errdefer self.mesh_objects.shrinkAndFree(allocator, mesh_objects_old_len);

      // Iterate through every new mesh handle and initialize its associated mesh object
      var allocation_transfer_offset : u32 = 0;
      for (meshes, mesh_handles, vk_buffer_copy_regions, 0..meshes.len) |mesh, handle, *vk_buffer_copy_region_dest, i| {
         errdefer for (mesh_handles[0..i]) |handle_old| {
            const object_old = self.getMeshMut(handle_old);
            object_old.setNull();
         };

         const object_dest = self.getMeshMut(handle);

         // Calculate bytes for the current mesh
         const mesh_bytes = _calculateMeshBytes(mesh);

         // Create the draw heap allocation
         const object_allocation_draw = try load_info.heap_draw.memory_heap.allocate(allocator, &.{
            .alignment  = MESH_BYTE_ALIGNMENT,
            .bytes      = mesh_bytes.total,
         });
         errdefer load_info.heap_draw.memory_heap.free(allocator, object_allocation_draw);

         // Calculate pointers for the transfer allocation
         const mesh_pointers = _calculateMeshPointers(&mesh_bytes, load_info.heap_transfer.mapping, allocation_transfer.offset + allocation_transfer_offset);

         // Create the backing object for the mesh
         const object = _createMeshObject(mesh, object_allocation_draw);
         errdefer object.setNull(allocator, load_info.heap_draw, load_info.heap_transfer);

         // Copy the mesh data into the transfer buffer
         @memcpy(mesh_pointers.vertices, mesh.vertices);
         @memcpy(mesh_pointers.indices, mesh.indices);

         // Calculate the copy region
         const vk_buffer_copy_region = c.VkBufferCopy{
            .srcOffset  = allocation_transfer.offset + allocation_transfer_offset,
            .dstOffset  = object_allocation_draw.offset,
            .size       = mesh_bytes.total,
         };

         // Write the newly created data
         object_dest.*                 = object;
         vk_buffer_copy_region_dest.*  = vk_buffer_copy_region;

         // Advance the offset into the transfer allocation
         allocation_transfer_offset += mesh_bytes.total_aligned;
      }
      errdefer for (mesh_handles) |handle| {
         const object = self.getMeshMut(handle);
         object.setNull();
      };

      // Wait for the previous transfer command to finish and reset the fence once complete
      // This is why you should avoid multiple load calls instead of a single
      // unified load call.  We have no choice but to block the thread to safely
      // issue the transfer command.
      try _waitOnFence(load_info.vk_device, self.vk_fence_transfer_finished);
      try _resetFence(load_info.vk_device, self.vk_fence_transfer_finished);

      // Record and send the transfer command
      try _sendTransferCommand(self.vk_command_buffer_transfer, self.vk_fence_transfer_finished, load_info, vk_buffer_copy_regions);

      // Free the old transfer allocation and replace it with the new one
      _allocationTransferTryFreeAndNull(self, allocator, load_info.heap_transfer);
      self.allocation_transfer = allocation_transfer;

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

      _allocationTransferTryFreeAndNull(self, allocator, unload_info.heap_transfer);

      for (meshes) |handle| {
         const object = self.getMeshMut(handle);

         unload_info.heap_draw.memory_heap.free(allocator, object.allocation);

         object.setNull();
      }
      
      _freeExcessNullMeshes(self, allocator);

      return;
   }

   pub fn cleanupFreeMemory(self : * @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice, heap_transfer : * vulkan.MemoryHeapTransfer) void {
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

      _allocationTransferTryFreeAndNull(self, allocator, heap_transfer);
   }

   pub fn pollMeshLoadStatus(self : * @This(), vk_device : c.VkDevice, mesh : MeshHandle) void {
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

      const object = self.getMeshMut(mesh);

      if (object.load_status != .pending) {
         return;
      }

      object.load_status = .ready;
   }

   pub fn pollTextureLoadStatus(self : * @This(), vk_device : c.VkDevice, texture : TextureHandle) void {
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

      const object = self.getTextureMut(texture);

      if (object.load_status != .pending) {
         return;
      }

      object.load_status = .ready;
   }
};

fn _getMeshObjectFallible(asset_server : * const AssetServer, handle : AssetServer.MeshHandle) ? * const AssetServer.MeshObject {
   if (handle >= asset_server.mesh_objects.items.len) {
      return null;
   }

   const object = &asset_server.mesh_objects.items[handle];

   if (object.isNull() == true) {
      return null;
   }

   return object;
}

fn _getTextureObjectFallible(asset_server : * const AssetServer, handle : AssetServer.TextureHandle) ? * const AssetServer.TextureHandle {
   if (handle >= asset_server.texture_objects.items.len) {
      return null;
   }

   const object = &asset_server.texture_objects.items[handle];

   if (object.isNull() == true) {
      return null;
   }

   return object;
}

fn _createTransferCommandBuffer(vk_device : c.VkDevice, vk_transfer_command_pool : c.VkCommandPool) AssetServer.CreateError!c.VkCommandBuffer {
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

fn _createTransferFence(vk_device : c.VkDevice) AssetServer.CreateError!c.VkFence {
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

fn _freeExcessNullMeshes(asset_server : * AssetServer, allocator : std.mem.Allocator) void {
   var new_length = asset_server.mesh_objects.items.len;
   while (new_length != 0 and asset_server.mesh_objects.items[new_length - 1].isNull() == true) {
      new_length -= 1;
   }

   asset_server.mesh_objects.shrinkAndFree(allocator, new_length);

   return;
}

fn _assignNewHandleId(asset_server : * AssetServer, allocator : std.mem.Allocator) AssetServer.LoadError!AssetServer.MeshHandle {
   for (asset_server.mesh_objects.items, 0..asset_server.mesh_objects.items.len) |object, i| {
      if (object.isNull() == true) {
         return i;
      }
   }

   try asset_server.mesh_objects.resize(allocator, asset_server.mesh_objects.items.len + 1);

   return asset_server.mesh_objects.items.len - 1;
}

fn _assignMultipleNewHandleId(asset_server : * AssetServer, allocator : std.mem.Allocator, buffer : [] AssetServer.MeshHandle) AssetServer.LoadError!void {
   const old_size = asset_server.mesh_objects.items.len;
   errdefer asset_server.mesh_objects.shrinkAndFree(allocator, old_size);

   for (buffer) |*handle_out| {
      handle_out.* = try _assignNewHandleId(asset_server, allocator);
   }

   return;
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

fn _createMeshObject(mesh : * const vulkan.types.Mesh, allocation_draw : vulkan.MemoryHeap.Allocation) AssetServer.MeshObject {
   const transform_mesh = math.Matrix4(f32).IDENTITY;

   const push_constants = vulkan.types.PushConstants{
      .transform_mesh   = transform_mesh,
   };

   const indices = @as(u32, @intCast(mesh.indices.len));

   return .{
      .push_constants   = push_constants,
      .allocation       = allocation_draw,
      .indices          = indices,
      .load_status      = .pending,
   };
}

fn _waitOnFence(vk_device : c.VkDevice, vk_fence : c.VkFence) AssetServer.LoadError!void {
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

fn _resetFence(vk_device : c.VkDevice, vk_fence : c.VkFence) AssetServer.LoadError!void {
   var vk_result : c.VkResult = undefined;

   vk_result = c.vkResetFences(vk_device, 1, &vk_fence);

   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.DeviceLost,
      else                             => unreachable,
   }

   return;
}

fn _fenceIsSignaled(vk_device : c.VkDevice, vk_fence : c.VkFence) AssetServer.LoadError!bool {
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

fn _sendTransferCommand(vk_command_buffer_transfer : c.VkCommandBuffer, vk_fence_transfer_finished : c.VkFence, load_info : * const AssetServer.LoadInfo, vk_buffer_copy_regions : [] c.VkBufferCopy) AssetServer.LoadError!void {
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

const NULL_ALLOCATION_OFFSET = std.math.maxInt(u32);

fn _allocationTransferIsNull(asset_server : * const AssetServer) bool {
   return asset_server.allocation_transfer.offset == NULL_ALLOCATION_OFFSET;
}

fn _allocationTransferSetNull(asset_server : * AssetServer) void {
   asset_server.allocation_transfer.offset = NULL_ALLOCATION_OFFSET;
   return;
}

fn _allocationTransferTryFreeAndNull(asset_server : * AssetServer, allocator : std.mem.Allocator, heap_transfer : * vulkan.MemoryHeapTransfer) void {
   if (_allocationTransferIsNull(asset_server) == true) {
      return;
   }

   heap_transfer.memory_heap.free(allocator, asset_server.allocation_transfer);

   _allocationTransferSetNull(asset_server);

   return;
}

