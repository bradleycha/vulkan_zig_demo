const std      = @import("std");
const builtin  = @import("builtin");
const present  = @import("present");
const vulkan   = @import("vulkan/index.zig");

pub const types = vulkan.types;

pub const RefreshMode = vulkan.RefreshMode;

pub const ShaderSource = vulkan.ShaderSource;

pub const ClearColor = vulkan.ClearColor;

pub const Renderer = struct {
   _allocator                       : std.mem.Allocator,
   _vulkan_instance                 : vulkan.Instance,
   _vulkan_surface                  : vulkan.Surface,
   _vulkan_physical_device          : vulkan.PhysicalDevice,
   _vulkan_swapchain_configuration  : vulkan.SwapchainConfiguration,
   _vulkan_device                   : vulkan.Device,
   _vulkan_swapchain                : vulkan.Swapchain,
   _vulkan_graphics_pipeline        : vulkan.GraphicsPipeline,

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

      return @This(){
         ._allocator                      = allocator,
         ._vulkan_instance                = vulkan_instance,
         ._vulkan_surface                 = vulkan_surface,
         ._vulkan_physical_device         = vulkan_physical_device,
         ._vulkan_swapchain_configuration = vulkan_swapchain_configuration,
         ._vulkan_device                  = vulkan_device,
         ._vulkan_swapchain               = vulkan_swapchain,
         ._vulkan_graphics_pipeline       = vulkan_graphics_pipeline,
      };
   }

   pub fn destroy(self : @This()) void {
      const allocator   = self._allocator;
      const vk_instance = self._vulkan_instance.vk_instance;
      const vk_device   = self._vulkan_device.vk_device;

      self._vulkan_graphics_pipeline.destroy(vk_device);
      self._vulkan_swapchain.destroy(allocator, vk_device);
      self._vulkan_device.destroy();
      self._vulkan_surface.destroy(vk_instance);
      self._vulkan_instance.destroy();
      return;
   }
};

