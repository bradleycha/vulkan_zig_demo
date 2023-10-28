const std      = @import("std");
const builtin  = @import("builtin");
const present  = @import("present");
const vulkan   = @import("vulkan/index.zig");

pub const Renderer = struct {
   _allocator              : std.mem.Allocator,
   _vulkan_instance        : vulkan.Instance,
   _vulkan_physical_device : vulkan.PhysicalDevice,
   _vulkan_device          : vulkan.Device,

   pub const CreateInfo = struct {
      program_name   : ? [*:0] const u8,
      debugging      : bool,
   };

   pub const CreateError = error {
      VulkanInstanceCreateError,
      VulkanPhysicalDeviceSelectError,
      VulkanDeviceCreateError,
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

      const vulkan_physical_device = vulkan.PhysicalDevice.selectMostSuitable(allocator, &.{
         .vk_instance   = vulkan_instance.vk_instance,
         .extensions    = vulkan_device_extensions,
      }) catch return error.VulkanPhysicalDeviceSelectError;

      const vulkan_device = vulkan.Device.create(&.{
         .physical_device     = &vulkan_physical_device,
         .enabled_extensions  = vulkan_device_extensions,
      }) catch return error.VulkanDeviceCreateError;
      errdefer vulkan_device.destroy();

      _ = window;
      
      return @This(){
         ._allocator                = allocator,
         ._vulkan_instance          = vulkan_instance,
         ._vulkan_physical_device   = vulkan_physical_device,
         ._vulkan_device            = vulkan_device,
      };
   }

   pub fn destroy(self : @This()) void {
      self._vulkan_device.destroy();
      self._vulkan_instance.destroy();
      return;
   }
};

