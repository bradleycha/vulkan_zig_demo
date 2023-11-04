const std      = @import("std");
const builtin  = @import("builtin");
const present  = @import("present");
const vulkan   = @import("vulkan/index.zig");
const c        = @import("cimports");

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
   _vulkan_semaphores_image_available  : vulkan.SemaphoreList(FRAMES_IN_FLIGHT),
   _vulkan_semaphores_render_finished  : vulkan.SemaphoreList(FRAMES_IN_FLIGHT),
   _vulkan_fences_in_flight            : vulkan.FenceList(FRAMES_IN_FLIGHT),

   const FRAMES_IN_FLIGHT = 1;

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
      VulkanSemaphoresImageAvailableCreateError,
      VulkanSemaphoresRenderFinishedCreateError,
      VulkanFencesInFlightCreateError,
   };

   pub fn create(allocator : std.mem.Allocator, window : * present.Window, create_info : * const CreateInfo) CreateError!@This() {
      const vulkan_instance_extensions : [] const [*:0] const u8 = &([0] [*:0] const u8 {}) ++
         present.VULKAN_REQUIRED_EXTENSIONS.Instance;

      const vulkan_device_extensions : [] const [*:0] const u8 = &([0] [*:0] const u8 {}) ++
         present.VULKAN_REQUIRED_EXTENSIONS.Device;

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

      const vulkan_semaphores_image_available = vulkan.SemaphoreList(FRAMES_IN_FLIGHT).create(
         vk_device,
      ) catch return error.VulkanSemaphoresImageAvailableCreateError;
      errdefer vulkan_semaphores_image_available.destroy(vk_device);

      const vulkan_semaphores_render_finished = vulkan.SemaphoreList(FRAMES_IN_FLIGHT).create(
         vk_device,
      ) catch return error.VulkanSemaphoresRenderFinishedCreateError;
      errdefer vulkan_semaphores_image_available.destroy(vk_device);

      const vulkan_fences_in_flight = vulkan.FenceList(FRAMES_IN_FLIGHT).create(
         vk_device,
      ) catch return error.VulkanFencesInFlightCreateError;
      errdefer vulkan_fences_in_flight.destroy(vk_device);

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
         ._vulkan_semaphores_image_available = vulkan_semaphores_image_available,
         ._vulkan_semaphores_render_finished = vulkan_semaphores_render_finished,
         ._vulkan_fences_in_flight           = vulkan_fences_in_flight,
      };
   }

   pub fn destroy(self : @This()) void {
      const allocator   = self._allocator;
      const vk_instance = self._vulkan_instance.vk_instance;
      const vk_device   = self._vulkan_device.vk_device;

      self._vulkan_fences_in_flight.destroy(vk_device);
      self._vulkan_semaphores_render_finished.destroy(vk_device);
      self._vulkan_semaphores_image_available.destroy(vk_device);
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
   };

   pub fn drawFrame(self : * @This()) DrawError!void {
      while (try _drawFrameWithSwapchainUpdates(self) == false) {}
      return;
   }
};

fn _drawFrameWithSwapchainUpdates(self : * Renderer) Renderer.DrawError!bool {
   _ = self;
   return true;
}

const RecordInfo = struct {
   vk_command_buffer       : c.VkCommandBuffer,
   vk_framebuffer          : c.VkFramebuffer,
   vk_render_pass          : c.VkRenderPass,
   vk_graphics_pipeline    : c.VkPipeline,
   swapchain_configuration : * const vulkan.SwapchainConfiguration,
   clear_color             : ClearColor,
};

fn _recordRenderPass(record_info : * const RecordInfo) Renderer.DrawError!void {
   var vk_result : c.VkResult = undefined;

   const vk_command_buffer       = record_info.vk_command_buffer;
   const vk_framebuffer          = record_info.vk_framebuffer;
   const vk_render_pass          = record_info.vk_render_pass;
   const vk_graphics_pipeline    = record_info.vk_graphics_pipeline;
   const swapchain_configuration = record_info.swapchain_configuration;
   const clear_color             = record_info.clear_color;

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

   switch (clear_color) {
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

   c.vkCmdDraw(vk_command_buffer, 3, 1, 0, 0);

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

