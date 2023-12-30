const std      = @import("std");
const builtin  = @import("builtin");
const present  = @import("present");
const vulkan   = @import("vulkan/index.zig");
const math     = @import("math");
const c        = @import("cimports");

const FRAMES_IN_FLIGHT = 2;

const MAX_TEXTURE_SAMPLERS = 16;

const MEMORY_HEAP_SIZE_DRAW      = 8 * 1024 * 1024;
const MEMORY_HEAP_SIZE_TRANSFER  = 8 * 1024 * 1024;

const NEAR_PLANE     = 0.0;
const FAR_PLANE      = 10000.0;
const FIELD_OF_VIEW  = 70.0;

pub const types = vulkan.types;

pub const RefreshMode = vulkan.RefreshMode;

pub const ShaderSource = vulkan.ShaderSource;

pub const ClearColor = vulkan.ClearColor;

pub const ImageSource = vulkan.ImageSource;

pub const ImageSampling = vulkan.ImageSampling;

pub const AssetLoader = @import("asset_loader.zig");

pub const Renderer = struct {
   _allocator                          : std.mem.Allocator,
   _vulkan_instance                    : vulkan.Instance,
   _vulkan_surface                     : vulkan.Surface,
   _vulkan_physical_device             : vulkan.PhysicalDevice,
   _vulkan_swapchain_configuration     : vulkan.SwapchainConfiguration,
   _vulkan_device                      : vulkan.Device,
   _vulkan_memory_source_image         : vulkan.MemorySourceImage,
   _vulkan_memory_heap_draw            : vulkan.MemoryHeapDraw,
   _vulkan_memory_heap_transfer        : vulkan.MemoryHeapTransfer,
   _vulkan_swapchain                   : vulkan.Swapchain,
   _vulkan_graphics_pipeline           : vulkan.GraphicsPipeline,
   _vulkan_framebuffers                : vulkan.Framebuffers,
   _vulkan_command_pools               : vulkan.CommandPools,
   _vulkan_command_buffers_draw        : vulkan.CommandBuffersDraw(FRAMES_IN_FLIGHT),
   _vulkan_semaphores_image_available  : vulkan.SemaphoreList(FRAMES_IN_FLIGHT),
   _vulkan_semaphores_render_finished  : vulkan.SemaphoreList(FRAMES_IN_FLIGHT),
   _vulkan_fences_in_flight            : vulkan.FenceList(FRAMES_IN_FLIGHT),
   _vulkan_uniform_allocation_draw     : vulkan.MemoryHeap.Allocation,
   _vulkan_uniform_allocation_transfer : vulkan.MemoryHeap.Allocation,
   _vulkan_descriptor_sets             : vulkan.DescriptorSets(.{.uniform_buffers = FRAMES_IN_FLIGHT, .texture_samplers = MAX_TEXTURE_SAMPLERS}),
   _asset_loader                       : AssetLoader,
   _active_texture_samplers            : [MAX_TEXTURE_SAMPLERS] bool,
   _window                             : * const present.Window,
   _refresh_mode                       : RefreshMode,
   _clear_color                        : ClearColor,
   _transform_view                     : math.Matrix4(f32),
   _transform_projection               : math.Matrix4(f32),
   _frame_index                        : u32,
   _framebuffer_size                   : present.Window.Resolution,

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
      VulkanMemorySourceDrawFindError,
      VulkanMemorySourceTransferFindError,
      VulkanMemorySourceImageFindError,
      VulkanMemoryHeapDrawCreateError,
      VulkanMemoryHeapTransferCreateError,
      VulkanSwapchainCreateError,
      VulkanGraphicsPipelineCreateError,
      VulkanFramebuffersCreateError,
      VulkanCommandPoolsCreateError,
      VulkanCommandBuffersDrawCreateError,
      VulkanSemaphoresImageAvailableCreateError,
      VulkanSemaphoresRenderFinishedCreateError,
      VulkanFencesInFlightCreateError,
      VulkanUniformAllocationCreateError,
      VulkanDescriptorSetsCreateError,
      AssetLoaderCreateError,
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

      const vulkan_memory_source_draw = vulkan.MemorySourceDraw.findSuitable(
         vulkan_physical_device.vk_physical_device_memory_properties,
      ) orelse return error.VulkanMemorySourceDrawFindError;

      const vulkan_memory_source_transfer = vulkan.MemorySourceTransfer.findSuitable(
         vulkan_physical_device.vk_physical_device_memory_properties,
      ) orelse return error.VulkanMemorySourceTransferFindError;

      const vulkan_memory_source_image = vulkan.MemorySourceImage.findSuitable(
         vulkan_physical_device.vk_physical_device_memory_properties,
      ) orelse return error.VulkanMemorySourceImageFindError;

      var vulkan_memory_heap_draw = vulkan.MemoryHeapDraw.create(allocator, &.{
         .physical_device  = &vulkan_physical_device,
         .vk_device        = vk_device,
         .heap_size        = MEMORY_HEAP_SIZE_DRAW,
      }, &vulkan_memory_source_draw) catch return error.VulkanMemoryHeapDrawCreateError;
      errdefer vulkan_memory_heap_draw.destroy(allocator, vk_device);

      var vulkan_memory_heap_transfer = vulkan.MemoryHeapTransfer.create(allocator, vk_device, &.{
         .physical_device  = &vulkan_physical_device,
         .vk_device        = vk_device,
         .heap_size        = MEMORY_HEAP_SIZE_TRANSFER,
      }, &vulkan_memory_source_transfer) catch return error.VulkanMemoryHeapTransferCreateError;
      errdefer vulkan_memory_heap_transfer.destroy(allocator, vk_device);

      const vulkan_swapchain = vulkan.Swapchain.create(allocator, &.{
         .vk_device                 = vk_device,
         .vk_surface                = vk_surface,
         .queue_family_indices      = &vulkan_physical_device.queue_family_indices,
         .memory_source_image       = &vulkan_memory_source_image,
         .swapchain_configuration   = &vulkan_swapchain_configuration,
         .depth_buffer_format       = vulkan_physical_device.depth_buffer_format,
      }) catch return error.VulkanSwapchainCreateError;
      errdefer vulkan_swapchain.destroy(allocator, vk_device);

      const vulkan_graphics_pipeline = vulkan.GraphicsPipeline.create(&.{
         .vk_device                 = vk_device,
         .swapchain_configuration   = &vulkan_swapchain_configuration,
         .shader_vertex             = create_info.shader_vertex,
         .shader_fragment           = create_info.shader_fragment,
         .depth_buffer_format       = vulkan_physical_device.depth_buffer_format,
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

      const vulkan_uniform_allocation_info = vulkan.MemoryHeap.AllocateInfo{
         .alignment  = @alignOf(types.UniformBufferObject),
         .bytes      = @sizeOf(types.UniformBufferObject) * FRAMES_IN_FLIGHT,
      };

      const vulkan_uniform_allocation_draw = vulkan_memory_heap_draw.memory_heap.allocate(allocator, &vulkan_uniform_allocation_info) catch return error.VulkanUniformAllocationCreateError;
      errdefer vulkan_memory_heap_draw.memory_heap.free(allocator, vulkan_uniform_allocation_draw);

      const vulkan_uniform_allocation_transfer = vulkan_memory_heap_transfer.memory_heap.allocate(allocator, &vulkan_uniform_allocation_info) catch return error.VulkanUniformAllocationCreateError;
      errdefer vulkan_memory_heap_transfer.memory_heap.free(allocator, vulkan_uniform_allocation_transfer);

      const transform_view = math.Matrix4(f32).IDENTITY;

      const transform_projection = math.Matrix4(f32).createPerspectiveProjection(
         window_framebuffer_size.width,
         window_framebuffer_size.height,
         NEAR_PLANE,
         FAR_PLANE,
         FIELD_OF_VIEW,
      );

      const vulkan_descriptor_sets = vulkan.DescriptorSets(.{.uniform_buffers = FRAMES_IN_FLIGHT, .texture_samplers = MAX_TEXTURE_SAMPLERS}).create(&.{
         .vk_device                                   = vk_device,
         .vk_descriptor_set_layout_uniform_buffers    = vulkan_graphics_pipeline.vk_descriptor_set_layout_uniform_buffers,
         .vk_descriptor_set_layout_texture_samplers   = vulkan_graphics_pipeline.vk_descriptor_set_layout_texture_samplers,
         .vk_buffer                                   = vulkan_memory_heap_draw.memory_heap.vk_buffer,
         .allocation_uniforms                         = vulkan_uniform_allocation_draw,
      }) catch return error.VulkanDescriptorSetsCreateError;
      errdefer vulkan_descriptor_sets.destroy(vk_device);

      var asset_loader = AssetLoader.create(&.{
         .vk_device                 = vk_device,
         .vk_command_pool_transfer  = vulkan_command_pools.transfer,
      }) catch return error.AssetLoaderCreateError;
      errdefer asset_loader.destroy(allocator, &.{
         .vk_device                 = vk_device,
         .vk_command_pool_transfer  = vulkan_command_pools.transfer,
      });
      
      return @This(){
         ._allocator                            = allocator,
         ._vulkan_instance                      = vulkan_instance,
         ._vulkan_surface                       = vulkan_surface,
         ._vulkan_physical_device               = vulkan_physical_device,
         ._vulkan_swapchain_configuration       = vulkan_swapchain_configuration,
         ._vulkan_device                        = vulkan_device,
         ._vulkan_memory_source_image           = vulkan_memory_source_image,
         ._vulkan_memory_heap_draw              = vulkan_memory_heap_draw,
         ._vulkan_memory_heap_transfer          = vulkan_memory_heap_transfer,
         ._vulkan_swapchain                     = vulkan_swapchain,
         ._vulkan_graphics_pipeline             = vulkan_graphics_pipeline,
         ._vulkan_framebuffers                  = vulkan_framebuffers,
         ._vulkan_command_pools                 = vulkan_command_pools,
         ._vulkan_command_buffers_draw          = vulkan_command_buffers_draw,
         ._vulkan_semaphores_image_available    = vulkan_semaphores_image_available,
         ._vulkan_semaphores_render_finished    = vulkan_semaphores_render_finished,
         ._vulkan_fences_in_flight              = vulkan_fences_in_flight,
         ._vulkan_uniform_allocation_draw       = vulkan_uniform_allocation_draw,
         ._vulkan_uniform_allocation_transfer   = vulkan_uniform_allocation_transfer,
         ._vulkan_descriptor_sets               = vulkan_descriptor_sets,
         ._asset_loader                         = asset_loader,
         ._active_texture_samplers              = ([1] bool {false}) ** MAX_TEXTURE_SAMPLERS,
         ._window                               = window,
         ._transform_view                       = transform_view,
         ._transform_projection                 = transform_projection,
         ._refresh_mode                         = create_info.refresh_mode,
         ._clear_color                          = create_info.clear_color,
         ._frame_index                          = 0,
         ._framebuffer_size                     = window_framebuffer_size,
      };
   }

   pub fn destroy(self : @This()) void {
      var self_mut = @constCast(&self); // :(

      const allocator   = self._allocator;
      const vk_instance = self._vulkan_instance.vk_instance;
      const vk_device   = self._vulkan_device.vk_device;

      _ = c.vkDeviceWaitIdle(vk_device);

      self_mut._asset_loader.destroy(allocator, &.{
         .vk_device                 = vk_device,
         .vk_command_pool_transfer  = self._vulkan_command_pools.transfer,
      });

      self._vulkan_descriptor_sets.destroy(vk_device);
      self_mut._vulkan_memory_heap_transfer.memory_heap.free(allocator, self._vulkan_uniform_allocation_transfer);
      self_mut._vulkan_memory_heap_draw.memory_heap.free(allocator, self._vulkan_uniform_allocation_draw);
      self._vulkan_fences_in_flight.destroy(vk_device);
      self._vulkan_semaphores_render_finished.destroy(vk_device);
      self._vulkan_semaphores_image_available.destroy(vk_device);
      self._vulkan_command_buffers_draw.destroy(vk_device, self._vulkan_command_pools.graphics);
      self._vulkan_command_pools.destroy(vk_device);
      self._vulkan_framebuffers.destroy(allocator, vk_device, &self._vulkan_swapchain);
      self._vulkan_graphics_pipeline.destroy(vk_device);
      self._vulkan_swapchain.destroy(allocator, vk_device);
      self_mut._vulkan_memory_heap_transfer.destroy(allocator, vk_device);
      self_mut._vulkan_memory_heap_draw.destroy(allocator, vk_device);
      self._vulkan_device.destroy();
      self._vulkan_surface.destroy(vk_instance);
      self._vulkan_instance.destroy();
      return;
   }

   pub fn loadAssets(self : * @This(), load_buffers : * const AssetLoader.LoadBuffers, load_items : * const AssetLoader.LoadItems) AssetLoader.LoadError!bool {
      return self._asset_loader.load(self._allocator, load_buffers, load_items, &.{
         .vulkan_physical_device       = &self._vulkan_physical_device,
         .vulkan_device                = &self._vulkan_device,
         .vk_queue_transfer            = self._vulkan_device.queues.transfer,
         .memory_heap_transfer         = &self._vulkan_memory_heap_transfer,
         .memory_heap_draw             = &self._vulkan_memory_heap_draw,
         .memory_source_image          = &self._vulkan_memory_source_image,
         .queue_family_index_transfer  = self._vulkan_physical_device.queue_family_indices.transfer,
         .queue_family_index_graphics  = self._vulkan_physical_device.queue_family_indices.graphics,
      });
   }

   pub fn unloadAssets(self : * @This(), handles : [] const AssetLoader.Handle) bool {
      return self._asset_loader.unload(self._allocator, handles, &.{
         .vk_device           = self._vulkan_device.vk_device,
         .vk_queue_graphics   = self._vulkan_device.queues.graphics,
         .memory_heap_draw    = &self._vulkan_memory_heap_draw,
      });
   }

   pub const TextureSampler = struct {
      _index   : usize,
      _texture : AssetLoader.Handle,
      _sampler : AssetLoader.Handle,

      pub const CreateError = error {
         OutOfMemory,
      };

      pub const CreateInfo = struct {
         texture  : AssetLoader.Handle,
         sampler  : AssetLoader.Handle,
      };
   };

   pub fn createTextureSampler(self : * @This(), create_info : * const TextureSampler.CreateInfo) TextureSampler.CreateError!TextureSampler {
      const texture  = create_info.texture;
      const sampler  = create_info.sampler;

      // Find the next available texture sampler
      var next_available_found : ? usize = null;
      for (self._active_texture_samplers, 0..MAX_TEXTURE_SAMPLERS) |is_active, i| {
         if (is_active == false) {
            next_available_found = i;
            break;
         }
      }

      const index = next_available_found orelse return error.OutOfMemory;

      const load_item_texture = &self._asset_loader.get(texture).variant.texture;
      const load_item_sampler = &self._asset_loader.get(sampler).variant.sampler;

      const vk_descriptor_image_info = c.VkDescriptorImageInfo{
         .sampler       = load_item_sampler.sampler.vk_sampler,
         .imageView     = load_item_texture.image_view.vk_image_view,
         .imageLayout   = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      };

      const vk_write_descriptor_set = c.VkWriteDescriptorSet{
         .sType            = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
         .pNext            = null,
         .dstSet           = self._vulkan_descriptor_sets.vk_descriptor_sets_texture_samplers[index],
         .dstBinding       = 0,
         .dstArrayElement  = 0,
         .descriptorCount  = 1,
         .descriptorType   = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
         .pImageInfo       = &vk_descriptor_image_info,
         .pBufferInfo      = undefined,
         .pTexelBufferView = undefined,
      };

      c.vkUpdateDescriptorSets(self._vulkan_device.vk_device, 1, &vk_write_descriptor_set, 0, undefined);

      self._active_texture_samplers[index] = true;

      return .{
         ._index     = index,
         ._texture   = texture,
         ._sampler   = sampler,
      };
   }

   pub fn destroyTextureSampler(self : * @This(), texture_sampler : TextureSampler) void {
      self._active_texture_samplers[texture_sampler._index] = false;
      return;
   }

   pub fn getAsset(self : * const @This(), handle : AssetLoader.Handle) * const AssetLoader.LoadItem {
      return self._asset_loader.get(handle);
   }

   pub fn getAssetMut(self : * @This(), handle : AssetLoader.Handle) * AssetLoader.LoadItem {
      return self._asset_loader.getMut(handle);
   }

   pub fn meshTransformMatrix(self : * const @This(), mesh_handle : AssetLoader.Handle) * const math.Matrix4(f32) {
      const load_item = self.getAsset(mesh_handle);
      const mesh = &load_item.variant.mesh;

      return &mesh.push_constants.transform_mesh;
   }

   pub fn meshTransformMatrixMut(self : * @This(), mesh_handle : AssetLoader.Handle) * math.Matrix4(f32) {
      const load_item = self.getAssetMut(mesh_handle);
      const mesh = &load_item.variant.mesh;

      return &mesh.push_constants.transform_mesh;
   }

   pub fn viewTransform(self : * const @This()) * const math.Matrix4(f32) {
      return &self._transform_view;
   }

   pub fn viewTransformMut(self : * @This()) * math.Matrix4(f32) {
      return &self._transform_view;
   }

   pub const DrawError = error {
      OutOfMemory,
      Unknown,
      DeviceLost,
      SurfaceLost,
      VulkanSwapchainRecreateError,
      VulkanUniformsTransferError,
   };

   pub const Model = struct {
      mesh              : AssetLoader.Handle,
      texture_sampler   : * const TextureSampler,
   };

   pub fn drawFrame(self : * @This(), models : [] const Model) DrawError!bool {
      while (true) {
         switch (try _drawFrameWithSwapchainUpdates(self, models)) {
            .busy                => return false,
            .complete            => return true,
            .recreate_swapchain  => continue,
         }
      }

      unreachable;
   }
};

const _DrawState = enum {
   busy,
   complete,
   recreate_swapchain,
};

fn _drawFrameWithSwapchainUpdates(self : * Renderer, models : [] const Renderer.Model) Renderer.DrawError!_DrawState {
   var vk_result : c.VkResult = undefined;

   const frame_index = self._frame_index;

   const vk_device                           = self._vulkan_device.vk_device;
   const vk_swapchain                        = self._vulkan_swapchain.vk_swapchain;
   const vk_command_buffer                   = self._vulkan_command_buffers_draw.vk_command_buffers[frame_index];
   const vk_semaphore_image_available        = self._vulkan_semaphores_image_available.vk_semaphores[frame_index];
   const vk_semaphore_render_finished        = self._vulkan_semaphores_render_finished.vk_semaphores[frame_index];
   const vk_fence_in_flight                  = self._vulkan_fences_in_flight.vk_fences[frame_index];
   const allocation_uniforms_transfer        = self._vulkan_uniform_allocation_transfer;
   const allocation_uniforms_draw            = self._vulkan_uniform_allocation_draw;
   const vk_descriptor_set_uniform_buffers   = self._vulkan_descriptor_sets.vk_descriptor_sets_uniform_buffers[frame_index];
   const vk_descriptor_sets_texture_samplers = &self._vulkan_descriptor_sets.vk_descriptor_sets_texture_samplers;

   const allocation_uniform_transfer   = vulkan.MemoryHeap.Allocation{
      .offset  = allocation_uniforms_transfer.offset + @as(u32, @intCast(frame_index * @sizeOf(types.UniformBufferObject))),
      .bytes   = @intCast(@sizeOf(types.UniformBufferObject)),
   };
   const allocation_uniform_draw       = vulkan.MemoryHeap.Allocation{
      .offset  = allocation_uniforms_draw.offset + @as(u32, @intCast(frame_index * @sizeOf(types.UniformBufferObject))),
      .bytes   = @intCast(@sizeOf(types.UniformBufferObject)),
   };

   vk_result = c.vkGetFenceStatus(vk_device, vk_fence_in_flight);
   switch (vk_result) {
      c.VK_SUCCESS            => {},
      c.VK_NOT_READY          => return .busy,
      c.VK_ERROR_DEVICE_LOST  => return error.DeviceLost,
      else                    => unreachable,
   }

   const old_framebuffer_size       = &self._framebuffer_size;
   const current_framebuffer_size   = self._window.getResolution();
   if (old_framebuffer_size.width != current_framebuffer_size.width or old_framebuffer_size.height != current_framebuffer_size.height) {
      _recreateSwapchain(self) catch return error.VulkanSwapchainRecreateError;
      return .recreate_swapchain;
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
         return .recreate_swapchain;
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

   const transform_view_projection = self._transform_projection.multiplyMatrix(&self._transform_view);

   const uniform_buffer_int_ptr = @intFromPtr(self._vulkan_memory_heap_transfer.mapping) + allocation_uniform_transfer.offset;
   const uniform_buffer_ptr = @as(* types.UniformBufferObject, @ptrFromInt(uniform_buffer_int_ptr));

   uniform_buffer_ptr.* = .{
      .transform_view_projection = transform_view_projection,
   };

   // Only poll once.  If we are still in the middle of loading, extra
   // synchronization is done below.
   _ = self._asset_loader.poll(self._allocator, &.{
      .vk_device              = vk_device,
      .memory_heap_transfer   = &self._vulkan_memory_heap_transfer,
   });

   try _recordRenderPass(self._allocator, models, &.{
      .vk_command_buffer                     = vk_command_buffer,
      .vk_framebuffer                        = vk_framebuffer,
      .vk_buffer_transfer                    = self._vulkan_memory_heap_transfer.memory_heap.vk_buffer,
      .vk_buffer_draw                        = self._vulkan_memory_heap_draw.memory_heap.vk_buffer,
      .vk_descriptor_set_uniform_buffers     = vk_descriptor_set_uniform_buffers,
      .vk_descriptor_sets_texture_samplers   = vk_descriptor_sets_texture_samplers,
      .swapchain_configuration               = &self._vulkan_swapchain_configuration,
      .graphics_pipeline                     = &self._vulkan_graphics_pipeline,
      .allocation_uniform_transfer           = allocation_uniform_transfer,
      .allocation_uniform_draw               = allocation_uniform_draw,
      .clear_color                           = &self._clear_color,
      .asset_loader                          = &self._asset_loader,
   });

   // We need this special check in the event the graphics and transfer queue
   // are both on the same queue.  If this is the case, we need to make sure we
   // don't submit our draw call before the graphics queue completes the transfer
   // operations.
   var render_pass_wait_semaphores_count : u32 = 1;
   const render_pass_wait_semaphores_buffer = [_] c.VkSemaphore {
      vk_semaphore_image_available,
      self._asset_loader.vk_semaphore_ready,
   };

   if (self._vulkan_device.queues.transfer == self._vulkan_device.queues.graphics and self._asset_loader.isBusy(vk_device) == true) {
      render_pass_wait_semaphores_count += 1;
   }

   const vk_info_submit_render_pass = c.VkSubmitInfo{
      .sType                  = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
      .pNext                  = null,
      .waitSemaphoreCount     = render_pass_wait_semaphores_count,
      .pWaitSemaphores        = &render_pass_wait_semaphores_buffer,
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
      return .recreate_swapchain;
   }

   self._frame_index = (frame_index + 1) % FRAMES_IN_FLIGHT;

   return .complete;
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
      .memory_source_image       = &self._vulkan_memory_source_image,
      .swapchain_configuration   = &vulkan_swapchain_configuration,
      .depth_buffer_format       = self._vulkan_physical_device.depth_buffer_format,
   });
   errdefer vulkan_swapchain.destroy(allocator, vk_device);

   const vulkan_framebuffers = try vulkan.Framebuffers.create(allocator, &.{
      .vk_device                 = vk_device,
      .swapchain_configuration   = &vulkan_swapchain_configuration,
      .swapchain                 = &vulkan_swapchain,
      .graphics_pipeline         = &self._vulkan_graphics_pipeline,
   });
   errdefer vulkan_framebuffers.destroy(allocator, vk_device);

   const transform_projection = math.Matrix4(f32).createPerspectiveProjection(
      framebuffer_size.width,
      framebuffer_size.height,
      NEAR_PLANE,
      FAR_PLANE,
      FIELD_OF_VIEW,
   );

   self._transform_projection = transform_projection;

   self._vulkan_framebuffers.destroy(allocator, vk_device, &vulkan_swapchain);
   self._vulkan_swapchain.destroy(allocator, vk_device);

   self._vulkan_swapchain_configuration   = vulkan_swapchain_configuration;
   self._vulkan_swapchain                 = vulkan_swapchain;
   self._vulkan_framebuffers              = vulkan_framebuffers;
   self._framebuffer_size                 = framebuffer_size;
   
   return;
}

const RecordInfo = struct {
   vk_command_buffer                   : c.VkCommandBuffer,
   vk_framebuffer                      : c.VkFramebuffer,
   vk_buffer_transfer                  : c.VkBuffer,
   vk_buffer_draw                      : c.VkBuffer,
   vk_descriptor_set_uniform_buffers   : c.VkDescriptorSet,
   vk_descriptor_sets_texture_samplers : * const [MAX_TEXTURE_SAMPLERS] c.VkDescriptorSet,
   swapchain_configuration             : * const vulkan.SwapchainConfiguration,
   graphics_pipeline                   : * const vulkan.GraphicsPipeline,
   allocation_uniform_transfer         : vulkan.MemoryHeap.Allocation,
   allocation_uniform_draw             : vulkan.MemoryHeap.Allocation,
   clear_color                         : * const ClearColor,
   asset_loader                        : * AssetLoader,
};

fn _recordRenderPass(allocator : std.mem.Allocator, models : [] const Renderer.Model, record_info : * const RecordInfo) Renderer.DrawError!void {
   var vk_result : c.VkResult = undefined;

   const vk_command_buffer                   = record_info.vk_command_buffer;
   const vk_framebuffer                      = record_info.vk_framebuffer;
   const vk_render_pass                      = record_info.graphics_pipeline.vk_render_pass;
   const vk_pipeline_layout                  = record_info.graphics_pipeline.vk_pipeline_layout;
   const vk_graphics_pipeline                = record_info.graphics_pipeline.vk_pipeline;
   const vk_descriptor_set_uniform_buffers   = record_info.vk_descriptor_set_uniform_buffers;
   const vk_descriptor_sets_texture_samplers = record_info.vk_descriptor_sets_texture_samplers;
   const vk_buffer_transfer                  = record_info.vk_buffer_transfer;
   const vk_buffer_draw                      = record_info.vk_buffer_draw;
   const swapchain_configuration             = record_info.swapchain_configuration;
   const allocation_uniform_transfer         = record_info.allocation_uniform_transfer;
   const allocation_uniform_draw             = record_info.allocation_uniform_draw;
   const clear_color                         = record_info.clear_color;
   const asset_loader                        = record_info.asset_loader;

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

   const vk_buffer_copy_uniform = c.VkBufferCopy{
      .srcOffset  = allocation_uniform_transfer.offset,
      .dstOffset  = allocation_uniform_draw.offset,
      .size       = @sizeOf(types.UniformBufferObject),
   };

   c.vkCmdCopyBuffer(vk_command_buffer, vk_buffer_transfer, vk_buffer_draw, 1, &vk_buffer_copy_uniform);

   // Transition any required textures to shader ready only, must be done
   // before we start the render pass.  Unfortunately, we have to create a
   // temporary buffer to store all our layout transitions.  Issuing many different
   // pipeline barriers is far worse can a few memory allocations on the CPU.
   var vk_image_memory_barriers = std.ArrayListUnmanaged(c.VkImageMemoryBarrier){};
   defer vk_image_memory_barriers.deinit(allocator);
   for (models) |model| {
      const texture_sampler   = model.texture_sampler;
      const texture_load_item = asset_loader.getMut(texture_sampler._texture);
      const texture           = &texture_load_item.variant.texture;

      if (texture_load_item.status == .pending) {
         continue;
      }

      if (texture.transitioned != false) {
         continue;
      }

      texture.transitioned = true;

      const vk_image_memory_barrier_dst = try vk_image_memory_barriers.addOne(allocator);
      vk_image_memory_barrier_dst.* = c.VkImageMemoryBarrier{
         .sType               = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
         .pNext               = null,
         .srcAccessMask       = 0x00000000,
         .dstAccessMask       = c.VK_ACCESS_SHADER_READ_BIT,
         .oldLayout           = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
         .newLayout           = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
         .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
         .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
         .image               = texture.image.vk_image,
         .subresourceRange    = c.VkImageSubresourceRange{
            .aspectMask       = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel     = 0,
            .levelCount       = 1,
            .baseArrayLayer   = 0,
            .layerCount       = 1,
         },
      };
   }

   c.vkCmdPipelineBarrier(
      vk_command_buffer,
      c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
      c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
      0x00000000,
      0,
      undefined,
      0,
      undefined,
      @intCast(vk_image_memory_barriers.items.len),
      vk_image_memory_barriers.items.ptr,
   );

   var clear_color_count : u32 = 1;
   var clear_color_buffer : [2] extern union {
      vk_clear_value : c.VkClearValue,
      color          : types.Color.Rgba(f32),
   } = undefined;

   switch (clear_color.*) {
      .none => {

      },
      .color => |color| {
         clear_color_count += 1;
         clear_color_buffer[0].color = color;
      },
   }

   clear_color_buffer[1].vk_clear_value = c.VkClearValue{.depthStencil = c.VkClearDepthStencilValue{
      .depth   = 1.0,
      .stencil = 0,
   }};

   const vk_info_render_pass_begin = c.VkRenderPassBeginInfo{
      .sType            = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
      .pNext            = null,
      .renderPass       = vk_render_pass,
      .framebuffer      = vk_framebuffer,
      .renderArea       = .{.offset = .{.x = 0, .y = 0}, .extent = swapchain_configuration.extent},
      .clearValueCount  = clear_color_count,
      .pClearValues     = &clear_color_buffer[0].vk_clear_value,
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

   for (models) |model| {
      const load_item_mesh    = asset_loader.get(model.mesh);
      const load_item_texture = asset_loader.getMut(model.texture_sampler._texture);
      const load_item_sampler = asset_loader.get(model.texture_sampler._sampler);
      const mesh              = &load_item_mesh.variant.mesh;

      // If the mesh or texture are in the middle of loading, skip drawing it.
      if (load_item_mesh.status == .pending or load_item_texture.status == .pending or load_item_sampler.status == .pending) {
         continue;
      }

      const vk_buffer_draw_offset_vertex  = @as(u64, mesh.allocation.offset);
      const vk_buffer_draw_offset_index   = @as(u64, mesh.allocation.offset + mesh.allocation.bytes - mesh.indices * @sizeOf(types.Mesh.IndexElement));

      const vk_descriptor_set_texture_sampler = vk_descriptor_sets_texture_samplers[model.texture_sampler._index];

      const vk_descriptor_sets = [_] c.VkDescriptorSet {
         vk_descriptor_set_uniform_buffers,
         vk_descriptor_set_texture_sampler,
      };

      c.vkCmdBindDescriptorSets(vk_command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, vk_pipeline_layout, 0, @intCast(vk_descriptor_sets.len), &vk_descriptor_sets, 0, undefined);

      c.vkCmdPushConstants(vk_command_buffer, vk_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(types.PushConstants), &mesh.push_constants);

      c.vkCmdBindVertexBuffers(vk_command_buffer, 0, 1, &vk_buffer_draw, &vk_buffer_draw_offset_vertex);

      c.vkCmdBindIndexBuffer(vk_command_buffer, vk_buffer_draw, vk_buffer_draw_offset_index, c.VK_INDEX_TYPE_UINT16);

      c.vkCmdDrawIndexed(vk_command_buffer, mesh.indices, 1, 0, 0, 0);
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

