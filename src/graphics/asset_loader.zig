const std      = @import("std");
const math     = @import("math");
const c        = @import("cimports");
const root     = @import("index.zig");
const vulkan   = @import("vulkan/index.zig");

const AssetLoader = @This();

load_items                 : std.ArrayListUnmanaged(LoadItem),
vk_command_buffer_transfer : c.VkCommandBuffer,
vk_fence_ready             : c.VkFence,
allocation_transfer        : vulkan.MemoryHeap.Allocation,

const NULL_ALLOCATION_OFFSET = std.math.maxInt(u32);

pub const LoadItem = struct {
   status   : Status,
   variant  : Variant,

   pub const Status = enum {
      destroyed,  // slot available for use by another item
      pending,    // currently being loaded
      ready,      // ready for use
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

pub const Handle = usize;

pub const CreateError = error {
   OutOfMemory,
};

pub const CreateInfo = struct {
   vk_device                  : c.VkDevice,
   vk_command_pool_transfer   : c.VkCommandPool,
};

pub fn create(create_info : * const CreateInfo) CreateError!AssetLoader {
   const vk_device                  = create_info.vk_device;
   const vk_command_pool_transfer   = create_info.vk_command_pool_transfer;

   var vk_result : c.VkResult = undefined;

   const vk_info_create_fence_ready = c.VkFenceCreateInfo{
      .sType   = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
      .pNext   = null,
      .flags   = c.VK_FENCE_CREATE_SIGNALED_BIT,
   };

   var vk_fence_ready : c.VkFence = undefined;
   vk_result = c.vkCreateFence(vk_device, &vk_info_create_fence_ready, null, &vk_fence_ready);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }
   errdefer c.vkDestroyFence(vk_device, vk_fence_ready, null);

   const vk_info_allocate_command_buffer_transfer = c.VkCommandBufferAllocateInfo{
      .sType               = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .pNext               = null,
      .commandPool         = vk_command_pool_transfer,
      .level               = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      .commandBufferCount  = 1,
   };

   var vk_command_buffer_transfer : c.VkCommandBuffer = undefined;
   vk_result = c.vkAllocateCommandBuffers(vk_device, &vk_info_allocate_command_buffer_transfer, &vk_command_buffer_transfer);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,     
   }
   errdefer c.vkFreeCommandBuffers(vk_device, vk_command_pool_transfer, 1, &vk_command_buffer_transfer);

   return AssetLoader{
      .load_items                   = .{},
      .vk_fence_ready               = vk_fence_ready,
      .vk_command_buffer_transfer   = vk_command_buffer_transfer,
      .allocation_transfer          = .{.offset = NULL_ALLOCATION_OFFSET, .bytes = undefined},
   };
}

pub const DestroyInfo = struct {
   vk_device                  : c.VkDevice,
   vk_command_pool_transfer   : c.VkCommandPool,
};

pub fn destroy(self : * AssetLoader, allocator : std.mem.Allocator, destroy_info : * const DestroyInfo) void {
   const vk_device                  = destroy_info.vk_device;
   const vk_command_pool_transfer   = destroy_info.vk_command_pool_transfer;

   _checkLeakedAssets(self);

   c.vkDestroyFence(vk_device, self.vk_fence_ready, null);
   c.vkFreeCommandBuffers(vk_device, vk_command_pool_transfer, 1, &self.vk_command_buffer_transfer);
   self.load_items.deinit(allocator);

   return;
}

fn _checkLeakedAssets(self : * const AssetLoader) void {
   if (std.debug.runtime_safety == false) {
      return;
   }

   var validation_failed = false;

   if (self.load_items.items.len != 0) {
      std.log.err("assets still loaded", .{});
      validation_failed = true;
   }

   if (self.allocation_transfer.offset != NULL_ALLOCATION_OFFSET) {
      std.log.err("transfer allocation unfreed, call poll() before cleanup", .{});
      validation_failed = true;
   }

   if (validation_failed == true) {
      @panic("resources leaked on loader destruction");
   }

   return;
}

pub fn get(self : * const AssetLoader, handle : Handle) * const LoadItem {
   const load_item = _getAllowDestroyed(self, handle);
   _checkLoadItem(load_item);

   return load_item;
}

pub fn getMut(self : * AssetLoader, handle : Handle) * LoadItem {
   const load_item = _getAllowDestroyedMut(self, handle);
   _checkLoadItem(load_item);

   return load_item;
}

fn _getAllowDestroyed(self : * const AssetLoader, handle : Handle) * const LoadItem {
   _checkHandle(self, handle);
   return &self.load_items.items[handle];
}

fn _getAllowDestroyedMut(self : * AssetLoader, handle : Handle) * LoadItem {
   _checkHandle(self, handle);
   return &self.load_items.items[handle];
}

fn _checkHandle(self : * const AssetLoader, handle : Handle) void {
   if (std.debug.runtime_safety == false) {
      return;
   }

   if (handle >= self.load_items.items.len) {
      @panic("attempted to access invalid load item");
   }

   return;
}

fn _checkLoadItem(load_item : * const LoadItem) void {
   if (std.debug.runtime_safety == false) {
      return;
   }

   if (load_item.status == .destroyed) {
      @panic("attempted to access destroyed load item");
   }

   return;
}

pub fn isBusy(self : * const AssetLoader, vk_device : c.VkDevice) bool {
   var vk_result : c.VkResult = undefined;

   var busy : bool = undefined;
   vk_result = c.vkGetFenceStatus(vk_device, self.vk_fence_ready);
   switch (vk_result) {
      c.VK_SUCCESS            => busy = false,
      c.VK_NOT_READY          => busy = true,
      c.VK_ERROR_DEVICE_LOST  => if (std.debug.runtime_safety == true) @panic("error when polling vulkan fence: device lost") else unreachable,
      else                    => unreachable,
   }

   return busy;
}

// All of the below functions return a boolean instead of null.  This signifies
// if the asset loader is in the middle of loading the previous data or not.
// 'true' means the function completed, while 'false' means the asset loader
// was busy with the previous asset loading.

pub const PollInfo = struct {
   vk_device            : c.VkDevice,
   memory_heap_transfer : * vulkan.MemoryHeapTransfer,
};

pub fn poll(self : * AssetLoader, allocator : std.mem.Allocator, poll_info : * const PollInfo) bool {
   const vk_device            = poll_info.vk_device;
   const memory_heap_transfer = poll_info.memory_heap_transfer;

   if (self.isBusy(vk_device) == true) {
      return false;
   }

   if(self.allocation_transfer.offset != NULL_ALLOCATION_OFFSET) {
      memory_heap_transfer.memory_heap.free(allocator, self.allocation_transfer);
   }

   for (self.load_items.items) |*load_item| {
      if (load_item.status != .pending) {
         continue;
      }

      load_item.status = .ready;
   }

   return true;
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
      push_constants : ? vulkan.types.PushConstants,
      data           : * const vulkan.types.Mesh,
   };

   pub const Texture = struct {
      sampling : root.ImageSampling,
      data     : * const root.ImageSource,
   };
};

pub const LoadInfo = struct {
   vk_device            : c.VkDevice,
   vk_queue_transfer    : c.VkQueue,
   memory_heap_transfer : * vulkan.MemoryHeapTransfer,
   memory_heap_draw     : * vulkan.MemoryHeapDraw,
};

pub const LoadError = error {
   OutOfMemory,
};

// Upon success and returning true, all the load item handles will be stored
// in the load buffers 'handles' field.  Meshes will be stored in the order
// passed in, followed by textures in the order passed in.
pub fn load(self : * AssetLoader, allocator : std.mem.Allocator, load_buffers : * const LoadBuffers, load_items : * const LoadItems, load_info : * const LoadInfo) LoadError!bool {
   const vk_device            = load_info.vk_device;
   const vk_queue_transfer    = load_info.vk_queue_transfer;
   const memory_heap_transfer = load_info.memory_heap_transfer;
   const memory_heap_draw     = load_info.memory_heap_draw;

   const load_meshes_count    = load_items.meshes.len;
   const load_textures_count  = load_items.textures.len;
   const load_items_count     = load_meshes_count + load_textures_count;

   // Runtime safety check - make sure we don't have a buffer overrun
   if (std.debug.runtime_safety == true and @hasField(LoadBuffers, "counts")) {
      const ERROR_MESHES   = "load buffers with size to store {} meshes is not large enough to load {} meshes";
      const ERROR_TEXTURES = "load buffers with size to store {} textures is not large enough to load {} textures";

      const BUFSIZE_ERROR_MESHES    = comptime std.fmt.count(ERROR_MESHES, .{std.math.maxInt(usize), std.math.maxInt(usize)});
      const BUFSIZE_ERROR_TEXTURES  = comptime std.fmt.count(ERROR_TEXTURES, .{std.math.maxInt(usize), std.math.maxInt(usize)});

      const BUFSIZE_ERROR_FORMAT = @max(BUFSIZE_ERROR_MESHES, BUFSIZE_ERROR_TEXTURES);

      var error_format_buffer : [BUFSIZE_ERROR_FORMAT] u8 = undefined;

      const counts = load_buffers.counts;

      if (load_meshes_count > counts.meshes) {
         @panic(std.fmt.bufPrint(&error_format_buffer, ERROR_MESHES, .{counts.meshes, load_meshes_count}) catch unreachable);
      }
      if (load_textures_count > counts.textures) {
         @panic(std.fmt.bufPrint(&error_format_buffer, ERROR_TEXTURES, .{counts.textures, load_textures_count}) catch unreachable);
      }
   }

   if (self.isBusy(vk_device) == true) {
      return false;
   }

   // Here is the general structure of this function:
   // 1. Calculate the total required bytes for everything
   // 2. Create a transfer allocation to store everything on
   // 3. Assign unique handles to every item we want to create
   // 4. Create all the mesh items and record the vkCmdCopy structs
   // 5. Create all the texture items and record the command buffer thing
   // 6. Issue the transfer command
   // 7. Free and overwrite the stored transfer allocation and return

   // Calculate the required bytes for all the meshes and textures
   const bytes_transfer = _calculateTotalBytesAndAlignment(load_items.meshes, load_items.textures);

   // If an existing transfer heap allocation exists, free it
   if (self.allocation_transfer.offset != NULL_ALLOCATION_OFFSET) {
      memory_heap_transfer.memory_heap.free(allocator, self.allocation_transfer);
      self.allocation_transfer.offset = NULL_ALLOCATION_OFFSET;
   }

   // Create the new transfer allocation, but don't store it until the end
   const allocation_transfer = try memory_heap_transfer.memory_heap.allocate(allocator, &.{
      .alignment  = bytes_transfer.max_alignment,
      .bytes      = bytes_transfer.total,
   });
   errdefer memory_heap_transfer.memory_heap.free(allocator, allocation_transfer);

   // Assign new unique handle IDs for each mesh and texture
   try _assignUniqueHandles(self, allocator, load_buffers.handles[0..load_items_count]);
   errdefer {
      for (load_buffers.handles[0..load_items_count]) |handle| {
         const load_item = self.getMut(handle);

         load_item.status = .destroyed;
      }

      _freeTrailingDestroyedLoadItems(self, allocator);
   }

   const handles_meshes    = load_buffers.handles[0..load_items.meshes.len];
   const handles_textures  = load_buffers.handles[load_items.meshes.len..load_items.textures.len];

   // TODO: Implement 4-7
   _ = handles_meshes;
   _ = handles_textures;
   _ = vk_queue_transfer;
   _ = memory_heap_draw;
   unreachable;
}

const BytesAlignment = struct {
   total          : u32,
   max_alignment  : u32,
};

const MESH_BYTE_ALIGNMENT = blk: {
   var alignment : comptime_int = @alignOf(root.types.Mesh.IndexElement);

   for (@typeInfo(root.types.Vertex).Struct.fields) |field| {
      const field_alignment = @alignOf(field.type);

      if (field_alignment > alignment) {
         alignment = field_alignment;
      }
   }

   break :blk alignment;
};

fn _calculateTotalBytesAndAlignment(meshes : [] const LoadItems.Mesh, textures : [] const LoadItems.Texture) BytesAlignment {
   var total         : u32 = 0;
   var max_alignment : u32 = MESH_BYTE_ALIGNMENT;

   for (meshes) |*mesh| {
      const bytes = _calculateMeshBytes(mesh);

      total += bytes.total_aligned;
   }

   for (textures) |*texture| {
      const bytes_alignment = _calculateTextureBytesAlignment(texture);

      total += bytes_alignment.total_aligned;

      if (bytes_alignment.alignment > max_alignment) {
         max_alignment = bytes_alignment.alignment;
      }
   }

   return .{.total = total, .max_alignment = max_alignment};
}

const MeshBytes = struct {
   vertices       : u32,
   indices        : u32,
   total          : u32,
   total_aligned  : u32,
};

fn _calculateMeshBytes(mesh : * const LoadItems.Mesh) MeshBytes {
   const vertices_count = mesh.data.vertices.len;
   const indices_count  = mesh.data.indices.len;

   const vertices_bytes = vertices_count * @sizeOf(root.types.Vertex);
   const indices_bytes  = indices_count * @sizeOf(root.types.Mesh.IndexElement);

   const total = vertices_bytes + indices_bytes;
   const total_aligned = math.alignForward(usize, total, MESH_BYTE_ALIGNMENT);

   return .{
      .vertices      = @intCast(vertices_bytes),
      .indices       = @intCast(indices_bytes),
      .total         = @intCast(total),
      .total_aligned = @intCast(total_aligned),
   };
}

const TextureBytesAlignment = struct {
   alignment      : u32,
   total          : u32,
   total_aligned  : u32,
};

fn _calculateTextureBytesAlignment(texture : * const LoadItems.Texture) TextureBytesAlignment {
   const width             = texture.data.width;
   const height            = texture.data.height;
   const bytes_per_pixel   = texture.data.format.bytesPerPixel();

   const total          = width * height * bytes_per_pixel;
   const total_aligned  = math.alignForward(usize, total, bytes_per_pixel);

   return .{
      .alignment     = @intCast(bytes_per_pixel),
      .total         = @intCast(total),
      .total_aligned = @intCast(total_aligned),
   };
}

// This doesn't actually initialize any of the handles.  It only returns free
// slots and their corresponding handles.
fn _assignUniqueHandles(self : * AssetLoader, allocator : std.mem.Allocator, handles_dest : [] Handle) error{OutOfMemory}!void {
   var open_slots_middle : usize = 0;
   for (self.load_items.items, 0..self.load_items.items.len) |*load_item, i| {
      if (open_slots_middle == handles_dest.len) {
         break;
      }

      if (load_item.status != .destroyed) {
         continue;
      }

      handles_dest[open_slots_middle] = i;

      open_slots_middle += 1;
   }

   const extend_by = handles_dest.len - open_slots_middle;
   const new_length = self.load_items.items.len + extend_by;

   try self.load_items.resize(allocator, new_length);

   for (handles_dest[open_slots_middle..], 0..extend_by) |*handle_dest, i| {
      handle_dest.* = i;
   }

   return;
}

fn _freeTrailingDestroyedLoadItems(self : * AssetLoader, allocator : std.mem.Allocator) void {
   var trimmed_length = self.load_items.items.len;

   while (trimmed_length != 0 and self.load_items[trimmed_length - 1].status != .destroyed) {
      trimmed_length -= 1;
   }

   self.load_items.shrinkAndFree(allocator, trimmed_length);

   return;
}

pub const UnloadInfo = struct {
   vk_device   : c.VkDevice,
};

pub fn unload(self : * AssetLoader, allocator : std.mem.Allocator, handles : [] const Handle, unload_info : * const UnloadInfo) bool {
   const vk_device = unload_info.vk_device;

   if (self.isBusy(vk_device) == true) {
      return false;
   }

   // TODO: Implement
   _ = allocator;
   _ = handles;
   unreachable;
}

