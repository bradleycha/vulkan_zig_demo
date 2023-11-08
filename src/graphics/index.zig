const std      = @import("std");
const builtin  = @import("builtin");
const present  = @import("present");
const vulkan   = @import("vulkan/index.zig");
const c        = @import("cimports");

const FRAMES_IN_FLIGHT = 2;

const MEMORY_HEAP_SIZE_DRAW      = 8 * 1024 * 1024;
const MEMORY_HEAP_SIZE_TRANSFER  = 8 * 1024 * 1024;

pub const types = vulkan.types;

pub const RefreshMode = vulkan.RefreshMode;

pub const ShaderSource = vulkan.ShaderSource;

pub const ClearColor = vulkan.ClearColor;

pub const Renderer = struct {
   _allocator                          : std.mem.Allocator,
   _vulkan_instance                    : vulkan.Instance,
   _vulkan_surface                     : vulkan.Surface,
   _vulkan_physical_device             : vulkan.PhysicalDevice,
   _vulkan_swapchain_configuration     : vulkan.SwapchainConfiguration,
   _vulkan_device                      : vulkan.Device,
   _vulkan_swapchain                   : vulkan.Swapchain,
   _vulkan_graphics_pipeline           : vulkan.GraphicsPipeline,
   _vulkan_framebuffers                : vulkan.Framebuffers,
   _vulkan_command_pools               : vulkan.CommandPools,
   _vulkan_command_buffers_draw        : vulkan.CommandBuffersDraw(FRAMES_IN_FLIGHT),
   _vulkan_command_buffer_transfer     : vulkan.CommandBufferTransfer,
   _vulkan_semaphores_image_available  : vulkan.SemaphoreList(FRAMES_IN_FLIGHT),
   _vulkan_semaphores_render_finished  : vulkan.SemaphoreList(FRAMES_IN_FLIGHT),
   _vulkan_fences_in_flight            : vulkan.FenceList(FRAMES_IN_FLIGHT),
   _vulkan_memory_heap_draw            : vulkan.MemoryHeapDraw,
   _vulkan_memory_heap_transfer        : vulkan.MemoryHeapTransfer,
   _loaded_meshes                      : std.ArrayListUnmanaged(MeshObject),
   _window                             : * const present.Window,
   _refresh_mode                       : RefreshMode,
   _clear_color                        : ClearColor,
   _frame_index                        : u32,
   _framebuffer_size                   : present.Window.Resolution,

   const MeshObject = struct {
      push_constants : vulkan.types.PushConstants,
      allocation     : vulkan.MemoryHeap.Allocation,
      indices        : u32,

      pub const NULL_OBJECT = std.math.maxInt(u32);

      // Using magic value and function to help tightly pack model objects
      // together in the array.
      pub fn isNull(self : * const @This()) bool {
         return self.indices == NULL_OBJECT;
      }
   };

   pub const CreateInfo = struct {
      program_name      : ? [*:0] const u8,
      debugging         : bool,
      refresh_mode      : RefreshMode,
      shader_vertex     : ShaderSource,
      shader_fragment   : ShaderSource,
      clear_color       : ClearColor,
   };

   pub const CreateError = error {
      VulkanInstanceCreateError,
      VulkanSurfaceCreateError,
      VulkanPhysicalDeviceSelectError,
      VulkanDeviceCreateError,
      VulkanSwapchainCreateError,
      VulkanGraphicsPipelineCreateError,
      VulkanFramebuffersCreateError,
      VulkanCommandPoolsCreateError,
      VulkanCommandBuffersDrawCreateError,
      VulkanCommandBufferTransferCreateError,
      VulkanSemaphoresImageAvailableCreateError,
      VulkanSemaphoresRenderFinishedCreateError,
      VulkanFencesInFlightCreateError,
      VulkanMemoryHeapDrawCreateError,
      VulkanMemoryHeapTransferCreateError,
   };

   pub fn create(allocator : std.mem.Allocator, window : * present.Window, create_info : * const CreateInfo) CreateError!@This() {
      const vulkan_instance_extensions : [] const [*:0] const u8 = &([0] [*:0] const u8 {}) ++
         present.VULKAN_REQUIRED_EXTENSIONS.Instance;

      const vulkan_device_extensions : [] const [*:0] const u8 = &([0] [*:0] const u8 {}) ++
         present.VULKAN_REQUIRED_EXTENSIONS.Device;

      const window_framebuffer_size = window.getResolution();

      const vulkan_instance = vulkan.Instance.create(allocator, &.{
         .extensions       = vulkan_instance_extensions,
         .program_name     = create_info.program_name,
         .engine_name      = "No Engine ;)",
         .program_version  = 0x00000000,
         .engine_version   = 0x00000000,
         .debugging        = create_info.debugging,
      }) catch return error.VulkanInstanceCreateError;
      errdefer vulkan_instance.destroy();

      const vk_instance = vulkan_instance.vk_instance;

      const vulkan_surface = vulkan.Surface.create(&.{
         .vk_instance   = vk_instance,
         .window        = window,
      }) catch return error.VulkanSurfaceCreateError;
      errdefer vulkan_surface.destroy(vk_instance);

      const vk_surface = vulkan_surface.vk_surface;

      const vulkan_physical_device_selection = vulkan.PhysicalDeviceSelection.selectMostSuitable(allocator, &.{
         .vk_instance            = vk_instance,
         .vk_surface             = vk_surface,
         .window                 = window,
         .present_mode_desired   = @intFromEnum(create_info.refresh_mode),
         .extensions             = vulkan_device_extensions,
      }) catch return error.VulkanPhysicalDeviceSelectError;

      const vulkan_physical_device           = vulkan_physical_device_selection.physical_device;
      const vulkan_swapchain_configuration   = vulkan_physical_device_selection.swapchain_configuration;

      const vulkan_device = vulkan.Device.create(&.{
         .physical_device     = &vulkan_physical_device,
         .enabled_extensions  = vulkan_device_extensions,
      }) catch return error.VulkanDeviceCreateError;
      errdefer vulkan_device.destroy();

      const vk_device = vulkan_device.vk_device;

      const vulkan_swapchain = vulkan.Swapchain.create(allocator, &.{
         .vk_device                 = vk_device,
         .vk_surface                = vk_surface,
         .queue_family_indices      = &vulkan_physical_device.queue_family_indices,
         .swapchain_configuration   = &vulkan_swapchain_configuration,
      }) catch return error.VulkanSwapchainCreateError;
      errdefer vulkan_swapchain.destroy(allocator, vk_device);

      const vulkan_graphics_pipeline = vulkan.GraphicsPipeline.create(&.{
         .vk_device                 = vk_device,
         .swapchain_configuration   = &vulkan_swapchain_configuration,
         .shader_vertex             = create_info.shader_vertex,
         .shader_fragment           = create_info.shader_fragment,
         .clear_mode                = create_info.clear_color,
      }) catch return error.VulkanGraphicsPipelineCreateError;
      errdefer vulkan_graphics_pipeline.destroy(vk_device);

      const vulkan_framebuffers = vulkan.Framebuffers.create(allocator, &.{
         .vk_device                 = vk_device,
         .swapchain_configuration   = &vulkan_swapchain_configuration,
         .swapchain                 = &vulkan_swapchain,
         .graphics_pipeline         = &vulkan_graphics_pipeline,
      }) catch return error.VulkanFramebuffersCreateError;
      errdefer vulkan_framebuffers.destroy(allocator, vk_device, &vulkan_swapchain);

      const vulkan_command_pools = vulkan.CommandPools.create(
         vk_device,
         &vulkan_physical_device.queue_family_indices,
      ) catch return error.VulkanCommandPoolsCreateError;
      errdefer vulkan_command_pools.destroy(vk_device);

      const vulkan_command_buffers_draw = vulkan.CommandBuffersDraw(FRAMES_IN_FLIGHT).create(&.{
         .vk_device        = vk_device,
         .vk_command_pool  = vulkan_command_pools.graphics,
      }) catch return error.VulkanCommandBuffersDrawCreateError;
      errdefer vulkan_command_buffers_draw.destroy(vk_device, vulkan_command_pools.graphics);

      const vulkan_command_buffer_transfer = vulkan.CommandBufferTransfer.create(&.{
         .vk_device        = vk_device,
         .vk_command_pool  = vulkan_command_pools.transfer,
      }) catch return error.VulkanCommandBufferTransferCreateError;
      errdefer vulkan_command_buffer_transfer.destroy(vk_device, vulkan_command_pools.transfer);

      const vulkan_semaphores_image_available = vulkan.SemaphoreList(FRAMES_IN_FLIGHT).create(
         vk_device,
      ) catch return error.VulkanSemaphoresImageAvailableCreateError;
      errdefer vulkan_semaphores_image_available.destroy(vk_device);

      const vulkan_semaphores_render_finished = vulkan.SemaphoreList(FRAMES_IN_FLIGHT).create(
         vk_device,
      ) catch return error.VulkanSemaphoresRenderFinishedCreateError;
      errdefer vulkan_semaphores_render_finished.destroy(vk_device);

      const vulkan_fences_in_flight = vulkan.FenceList(FRAMES_IN_FLIGHT).create(
         vk_device,
      ) catch return error.VulkanFencesInFlightCreateError;
      errdefer vulkan_fences_in_flight.destroy(vk_device);

      const vulkan_memory_heap_draw = vulkan.MemoryHeapDraw.create(allocator, &.{
         .physical_device  = &vulkan_physical_device,
         .vk_device        = vk_device,
         .heap_size        = MEMORY_HEAP_SIZE_DRAW,
      }) catch return error.VulkanMemoryHeapDrawCreateError;
      errdefer vulkan_memory_heap_draw.destroy(allocator, vk_device);

      const vulkan_memory_heap_transfer = vulkan.MemoryHeapTransfer.create(allocator, vk_device, &.{
         .physical_device  = &vulkan_physical_device,
         .vk_device        = vk_device,
         .heap_size        = MEMORY_HEAP_SIZE_TRANSFER,
      }) catch return error.VulkanMemoryHeapTransferCreateError;
      errdefer vulkan_memory_heap_transfer.destroy(allocator, vk_device);

      return @This(){
         ._allocator                         = allocator,
         ._vulkan_instance                   = vulkan_instance,
         ._vulkan_surface                    = vulkan_surface,
         ._vulkan_physical_device            = vulkan_physical_device,
         ._vulkan_swapchain_configuration    = vulkan_swapchain_configuration,
         ._vulkan_device                     = vulkan_device,
         ._vulkan_swapchain                  = vulkan_swapchain,
         ._vulkan_graphics_pipeline          = vulkan_graphics_pipeline,
         ._vulkan_framebuffers               = vulkan_framebuffers,
         ._vulkan_command_pools              = vulkan_command_pools,
         ._vulkan_command_buffers_draw       = vulkan_command_buffers_draw,
         ._vulkan_command_buffer_transfer    = vulkan_command_buffer_transfer,
         ._vulkan_semaphores_image_available = vulkan_semaphores_image_available,
         ._vulkan_semaphores_render_finished = vulkan_semaphores_render_finished,
         ._vulkan_fences_in_flight           = vulkan_fences_in_flight,
         ._vulkan_memory_heap_draw           = vulkan_memory_heap_draw,
         ._vulkan_memory_heap_transfer       = vulkan_memory_heap_transfer,
         ._loaded_meshes                     = .{},
         ._window                            = window,
         ._refresh_mode                      = create_info.refresh_mode,
         ._clear_color                       = create_info.clear_color,
         ._frame_index                       = 0,
         ._framebuffer_size                  = window_framebuffer_size,
      };
   }

   pub fn destroy(self : @This()) void {
      var self_mut = self;

      const allocator   = self._allocator;
      const vk_instance = self._vulkan_instance.vk_instance;
      const vk_device   = self._vulkan_device.vk_device;

      _ = c.vkDeviceWaitIdle(vk_device);

      self_mut._loaded_meshes.deinit(allocator);
      self._vulkan_memory_heap_transfer.destroy(allocator, vk_device);
      self._vulkan_memory_heap_draw.destroy(allocator, vk_device);
      self._vulkan_fences_in_flight.destroy(vk_device);
      self._vulkan_semaphores_render_finished.destroy(vk_device);
      self._vulkan_semaphores_image_available.destroy(vk_device);
      self._vulkan_command_buffer_transfer.destroy(vk_device, self._vulkan_command_pools.transfer);
      self._vulkan_command_buffers_draw.destroy(vk_device, self._vulkan_command_pools.graphics);
      self._vulkan_command_pools.destroy(vk_device);
      self._vulkan_framebuffers.destroy(allocator, vk_device, &self._vulkan_swapchain);
      self._vulkan_graphics_pipeline.destroy(vk_device);
      self._vulkan_swapchain.destroy(allocator, vk_device);
      self._vulkan_device.destroy();
      self._vulkan_surface.destroy(vk_instance);
      self._vulkan_instance.destroy();
      return;
   }

   pub const DrawError = error {
      OutOfMemory,
      Unknown,
      DeviceLost,
      SurfaceLost,
      VulkanSwapchainRecreateError,
   };

   pub const MeshHandle = struct {
      index : usize,
   };

   pub const MeshLoadError = error {
      OutOfMemory,
      Unknown,
      MapError,
      TransferError,
   };

   pub fn loadMesh(self : * @This(), mesh : * const types.Mesh) MeshLoadError!MeshHandle {
      const allocator      = self._allocator;
      const heap_draw      = &self._vulkan_memory_heap_draw;
      const heap_transfer  = &self._vulkan_memory_heap_transfer;

      var loaded_meshes_index_found : ? usize = null;
      for (self._loaded_meshes.items, 0..self._loaded_meshes.items.len) |mesh_object, i| {
         if (mesh_object.isNull()) {
            loaded_meshes_index_found = i;
            break;
         }
      }

      const loaded_meshes_index = blk: {
         if (loaded_meshes_index_found) |index| {
            break :blk index;
         } else {
            break :blk self._loaded_meshes.items.len;
         }
      };

      if (loaded_meshes_index_found == null) {
         _ = try self._loaded_meshes.addOne(self._allocator);
      }
      errdefer if (loaded_meshes_index_found == null) {
         self._loaded_meshes.shrinkAndFree(self._allocator, self._loaded_meshes.items.len - 1);
      };

      const bytes_vertices = mesh.vertices.len * @sizeOf(types.Vertex);
      const bytes_indices  = mesh.indices.len * @sizeOf(types.Mesh.IndexElement);

      // We store vertices first, then indices right after in memory. This will
      // aid in memory cache usage, thus improve performance.  This is valid
      // because our alignment of vertices is greater than alignment of
      // indices, so we know our memory is aligned for indices after our
      // vertices.
      const bytes       = bytes_vertices + bytes_indices;
      const alignment   = @sizeOf(types.Vertex);

      const allocate_info = vulkan.MemoryHeap.AllocateInfo{
         .bytes      = @as(u32, @intCast(bytes)),
         .alignment  = @as(u32, @intCast(alignment)),
      };

      const allocation_draw = try heap_draw.memory_heap.allocate(allocator, &allocate_info);
      errdefer heap_draw.memory_heap.free(allocator, allocation_draw);

      const allocation_transfer = try heap_transfer.memory_heap.allocate(allocator, &allocate_info);
      defer heap_transfer.memory_heap.free(allocator, allocation_transfer);

      const transfer_int_ptr_vertices  = @intFromPtr(heap_transfer.mapping) + allocation_transfer.offset;
      const transfer_int_ptr_indices   = @intFromPtr(heap_transfer.mapping) + allocation_transfer.offset + bytes_vertices;

      const transfer_ptr_vertices   = @as([*] types.Vertex, @ptrFromInt(transfer_int_ptr_vertices));
      const transfer_ptr_indices    = @as([*] types.Mesh.IndexElement, @ptrFromInt(transfer_int_ptr_indices));

      @memcpy(transfer_ptr_vertices, mesh.vertices);
      @memcpy(transfer_ptr_indices, mesh.indices);

      vulkan.MemoryHeap.transferFromStaging(&.{
         .heap_source                  = &heap_transfer.memory_heap,
         .heap_destination             = &heap_draw.memory_heap,
         .allocation_source            = allocation_transfer,
         .allocation_destination       = allocation_draw,
         .device                       = &self._vulkan_device,
         .vk_command_buffer_transfer   = self._vulkan_command_buffer_transfer.vk_command_buffer,
      }) catch return error.TransferError;

      const transform_mesh = types.Matrix4(f32){.items = .{
         1.0, 0.0, 0.0, 0.0,
         0.0, 1.0, 0.0, 0.0,
         0.0, 0.0, 1.0, 0.0,
         0.0, 0.0, 0.0, 1.0,
      }};

      const push_constants = types.PushConstants{
         .transform_mesh = transform_mesh,
      };

      const mesh_object = MeshObject{
         .push_constants   = push_constants,
         .allocation       = allocation_draw,
         .indices          = @intCast(mesh.indices.len),
      };

      const mesh_handle = MeshHandle{
         .index   = loaded_meshes_index,
      };

      self._loaded_meshes.items[loaded_meshes_index] = mesh_object;
      return mesh_handle;
   }

   pub fn unloadMesh(self : * @This(), mesh_handle : MeshHandle) void {
      const mesh_object = &self._loaded_meshes.items[mesh_handle.index];

      self._vulkan_memory_heap_draw.memory_heap.free(self._allocator, mesh_object.allocation);

      if (self._loaded_meshes.items.len == 1) {
         self._loaded_meshes.clearAndFree(self._allocator);
         return;
      }

      var i : usize = self._loaded_meshes.items.len - 1;
      while (self._loaded_meshes.items[i].isNull() == true and i != 0) {
         i -= 1;
      }

      self._loaded_meshes.shrinkAndFree(self._allocator, i + 1);

      return;
   }

   pub fn meshTransform(self : * const @This(), mesh_handle : MeshHandle) * const types.Matrix4(f32) {
      return &self._loaded_meshes.items[mesh_handle.index].push_constants.transform_mesh;
   }

   pub fn meshTransformMut(self : * @This(), mesh_handle : MeshHandle) * types.Matrix4(f32) {
      return &self._loaded_meshes.items[mesh_handle.index].push_constants.transform_mesh;
   }

   pub fn drawFrame(self : * @This(), mesh_handles : [] const MeshHandle) DrawError!void {
      while (try _drawFrameWithSwapchainUpdates(self, mesh_handles) == false) {}
      return;
   }
};

fn _drawFrameWithSwapchainUpdates(self : * Renderer, mesh_handles : [] const Renderer.MeshHandle) Renderer.DrawError!bool {
   var vk_result : c.VkResult = undefined;

   const frame_index = self._frame_index;

   const vk_device                     = self._vulkan_device.vk_device;
   const vk_swapchain                  = self._vulkan_swapchain.vk_swapchain;
   const vk_command_buffer             = self._vulkan_command_buffers_draw.vk_command_buffers[frame_index];
   const vk_semaphore_image_available  = self._vulkan_semaphores_image_available.vk_semaphores[frame_index];
   const vk_semaphore_render_finished  = self._vulkan_semaphores_render_finished.vk_semaphores[frame_index];
   const vk_fence_in_flight            = self._vulkan_fences_in_flight.vk_fences[frame_index];

   vk_result = c.vkWaitForFences(vk_device, 1, &vk_fence_in_flight, c.VK_TRUE, std.math.maxInt(u64));
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_TIMEOUT                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_DEVICE_LOST           => return error.DeviceLost,
      else                             => unreachable,
   }

   const old_framebuffer_size       = &self._framebuffer_size;
   const current_framebuffer_size   = self._window.getResolution();
   if (old_framebuffer_size.width != current_framebuffer_size.width or old_framebuffer_size.height != current_framebuffer_size.height) {
      _recreateSwapchain(self) catch return error.VulkanSwapchainRecreateError;
      return false;
   }

   var recreate_swapchain = false;

   var vk_swapchain_image_index : u32 = undefined;
   vk_result = c.vkAcquireNextImageKHR(vk_device, vk_swapchain, std.math.maxInt(u64), vk_semaphore_image_available, @ptrCast(@alignCast(c.VK_NULL_HANDLE)), &vk_swapchain_image_index);
   switch (vk_result) {
      c.VK_SUCCESS                                    => {},
      c.VK_TIMEOUT                                    => {},
      c.VK_NOT_READY                                  => {},
      c.VK_SUBOPTIMAL_KHR                             => recreate_swapchain = true,
      c.VK_ERROR_OUT_OF_HOST_MEMORY                   => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY                 => return error.OutOfMemory,
      c.VK_ERROR_DEVICE_LOST                          => return error.DeviceLost,
      c.VK_ERROR_OUT_OF_DATE_KHR                      => {
         _recreateSwapchain(self) catch return error.VulkanSwapchainRecreateError;
         return false;
      },
      c.VK_ERROR_SURFACE_LOST_KHR                     => return error.SurfaceLost,
      c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT  => return error.Unknown,
      else                                            => unreachable,
   }

   // TODO: Better place to move fence reset? This will cause a deadlock if any
   // of the following returns an error.
   vk_result = c.vkResetFences(vk_device, 1, &vk_fence_in_flight);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }

   const vk_framebuffer = self._vulkan_framebuffers.vk_framebuffers_ptr[vk_swapchain_image_index];

   vk_result = c.vkResetCommandBuffer(vk_command_buffer, 0x00000000);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }

   try _recordRenderPass(mesh_handles, &.{
      .vk_command_buffer         = vk_command_buffer,
      .vk_framebuffer            = vk_framebuffer,
      .vk_buffer_draw            = self._vulkan_memory_heap_draw.memory_heap.vk_buffer,
      .swapchain_configuration   = &self._vulkan_swapchain_configuration,
      .graphics_pipeline         = &self._vulkan_graphics_pipeline,
      .clear_color               = &self._clear_color,
      .loaded_meshes             = self._loaded_meshes.items,
   });

   const vk_info_submit_render_pass = c.VkSubmitInfo{
      .sType                  = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
      .pNext                  = null,
      .waitSemaphoreCount     = 1,
      .pWaitSemaphores        = &vk_semaphore_image_available,
      .pWaitDstStageMask      = &([1] c.VkPipelineStageFlags {c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT}),
      .commandBufferCount     = 1,
      .pCommandBuffers        = &vk_command_buffer,
      .signalSemaphoreCount   = 1,
      .pSignalSemaphores      = &vk_semaphore_render_finished,
   };

   vk_result = c.vkQueueSubmit(self._vulkan_device.queues.graphics, 1, &vk_info_submit_render_pass, vk_fence_in_flight);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_DEVICE_LOST           => return error.DeviceLost,
      else                             => unreachable,
   }

   const vk_info_present = c.VkPresentInfoKHR{
      .sType               = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
      .pNext               = null,
      .waitSemaphoreCount  = 1,
      .pWaitSemaphores     = &vk_semaphore_render_finished,
      .swapchainCount      = 1,
      .pSwapchains         = &vk_swapchain,
      .pImageIndices       = &vk_swapchain_image_index,
      .pResults            = null,
   };

   vk_result = c.vkQueuePresentKHR(self._vulkan_device.queues.present, &vk_info_present);
   switch (vk_result) {
      c.VK_SUCCESS                                    => {},
      c.VK_SUBOPTIMAL_KHR                             => recreate_swapchain = true,
      c.VK_ERROR_OUT_OF_HOST_MEMORY                   => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY                 => return error.OutOfMemory,
      c.VK_ERROR_DEVICE_LOST                          => return error.DeviceLost,
      c.VK_ERROR_OUT_OF_DATE_KHR                      => recreate_swapchain = true,
      c.VK_ERROR_SURFACE_LOST_KHR                     => return error.SurfaceLost,
      c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT  => return error.Unknown,
      else                                            => unreachable,
   }

   if (recreate_swapchain == true) {
      _recreateSwapchain(self) catch return error.VulkanSwapchainRecreateError;
      return false;
   }

   self._frame_index = (frame_index + 1) % FRAMES_IN_FLIGHT;

   return true;
}

const SwapchainRecreateError = error {
   OutOfMemory,
   Unknown,
   DeviceLost,
   SurfaceLost,
   WindowInUse,
   NoAvailableSwapchainConfiguration,
};

fn _recreateSwapchain(self : * Renderer) SwapchainRecreateError!void {
   var vk_result : c.VkResult = undefined;

   const allocator   = self._allocator;
   const vk_device   = self._vulkan_device.vk_device;
   const vk_surface  = self._vulkan_surface.vk_surface;

   vk_result = c.vkDeviceWaitIdle(vk_device);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_DEVICE_LOST           => return error.DeviceLost,
      else                             => unreachable,
   }

   const framebuffer_size = self._window.getResolution();

   const vulkan_swapchain_configuration = try vulkan.SwapchainConfiguration.selectMostSuitable(allocator, &.{
      .vk_physical_device     = self._vulkan_physical_device.vk_physical_device,
      .vk_surface             = vk_surface,
      .window                 = self._window,
      .present_mode_desired   = @intFromEnum(self._refresh_mode),
   }) orelse return error.NoAvailableSwapchainConfiguration;

   const vulkan_swapchain = try self._vulkan_swapchain.createFrom(allocator, &.{
      .vk_device                 = vk_device,
      .vk_surface                = vk_surface,
      .queue_family_indices      = &self._vulkan_physical_device.queue_family_indices,
      .swapchain_configuration   = &vulkan_swapchain_configuration,
   });
   errdefer vulkan_swapchain.destroy(allocator, vk_device);

   const vulkan_framebuffers = try vulkan.Framebuffers.create(allocator, &.{
      .vk_device                 = vk_device,
      .swapchain_configuration   = &vulkan_swapchain_configuration,
      .swapchain                 = &vulkan_swapchain,
      .graphics_pipeline         = &self._vulkan_graphics_pipeline,
   });
   errdefer vulkan_framebuffers.destroy(allocator, vk_device);

   self._vulkan_framebuffers.destroy(allocator, vk_device, &vulkan_swapchain);
   self._vulkan_swapchain.destroy(allocator, vk_device);

   self._vulkan_swapchain_configuration   = vulkan_swapchain_configuration;
   self._vulkan_swapchain                 = vulkan_swapchain;
   self._vulkan_framebuffers              = vulkan_framebuffers;
   self._framebuffer_size                 = framebuffer_size;
   
   return;
}

const RecordInfo = struct {
   vk_command_buffer       : c.VkCommandBuffer,
   vk_framebuffer          : c.VkFramebuffer,
   vk_buffer_draw          : c.VkBuffer,
   swapchain_configuration : * const vulkan.SwapchainConfiguration,
   graphics_pipeline       : * const vulkan.GraphicsPipeline,
   clear_color             : * const ClearColor,
   loaded_meshes           : [] const Renderer.MeshObject,
};

fn _recordRenderPass(mesh_handles : [] const Renderer.MeshHandle, record_info : * const RecordInfo) Renderer.DrawError!void {
   var vk_result : c.VkResult = undefined;

   const vk_command_buffer       = record_info.vk_command_buffer;
   const vk_framebuffer          = record_info.vk_framebuffer;
   const vk_render_pass          = record_info.graphics_pipeline.vk_render_pass;
   const vk_pipeline_layout      = record_info.graphics_pipeline.vk_pipeline_layout;
   const vk_graphics_pipeline    = record_info.graphics_pipeline.vk_pipeline;
   const vk_buffer_draw          = record_info.vk_buffer_draw;
   const swapchain_configuration = record_info.swapchain_configuration;
   const clear_color             = record_info.clear_color;
   const loaded_meshes           = record_info.loaded_meshes;

   const vk_info_command_buffer_begin = c.VkCommandBufferBeginInfo{
      .sType            = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .pNext            = null,
      .flags            = 0x00000000,
      .pInheritanceInfo = null,
   };

   vk_result = c.vkBeginCommandBuffer(vk_command_buffer, &vk_info_command_buffer_begin);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }

   var clear_color_count : u32 = undefined;
   var clear_color_data  : extern union {
      vk_clear_value : c.VkClearValue,
      vector         : @Vector(4, f32),
   } = undefined;

   switch (clear_color.*) {
      .none => {
         clear_color_count = 0;
      },
      .color => |color| {
         clear_color_count = 1;
         clear_color_data.vector = color.vector;
      },
   }

   const vk_info_render_pass_begin = c.VkRenderPassBeginInfo{
      .sType            = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
      .pNext            = null,
      .renderPass       = vk_render_pass,
      .framebuffer      = vk_framebuffer,
      .renderArea       = .{.offset = .{.x = 0, .y = 0}, .extent = swapchain_configuration.extent},
      .clearValueCount  = clear_color_count,
      .pClearValues     = &clear_color_data.vk_clear_value,
   };

   c.vkCmdBeginRenderPass(vk_command_buffer, &vk_info_render_pass_begin, c.VK_SUBPASS_CONTENTS_INLINE);

   c.vkCmdBindPipeline(vk_command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, vk_graphics_pipeline);

   const vk_viewport = c.VkViewport{
      .x          = 0,
      .y          = 0,
      .width      = @floatFromInt(swapchain_configuration.extent.width),
      .height     = @floatFromInt(swapchain_configuration.extent.height),
      .minDepth   = 0.0,
      .maxDepth   = 1.0,
   };

   c.vkCmdSetViewport(vk_command_buffer, 0, 1, &vk_viewport);

   const vk_scissor = c.VkRect2D{
      .offset  = .{.x = 0, .y = 0},
      .extent  = swapchain_configuration.extent,
   };

   c.vkCmdSetScissor(vk_command_buffer, 0, 1, &vk_scissor);

   for (mesh_handles) |mesh_handle| {
      const mesh_object = loaded_meshes[mesh_handle.index];

      const vk_buffer_draw_offset_vertex  = @as(u64, mesh_object.allocation.offset);
      const vk_buffer_draw_offset_index   = @as(u64, mesh_object.allocation.offset + mesh_object.allocation.length - mesh_object.indices * @sizeOf(types.Mesh.IndexElement));

      c.vkCmdPushConstants(vk_command_buffer, vk_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(types.PushConstants), &mesh_object.push_constants);

      c.vkCmdBindVertexBuffers(vk_command_buffer, 0, 1, &vk_buffer_draw, &vk_buffer_draw_offset_vertex);

      c.vkCmdBindIndexBuffer(vk_command_buffer, vk_buffer_draw, vk_buffer_draw_offset_index, c.VK_INDEX_TYPE_UINT16);

      c.vkCmdDrawIndexed(vk_command_buffer, mesh_object.indices, 1, 0, 0, 0);
   }

   c.vkCmdEndRenderPass(vk_command_buffer);

   vk_result = c.vkEndCommandBuffer(vk_command_buffer);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => return error.Unknown,
   }

   return;
}

