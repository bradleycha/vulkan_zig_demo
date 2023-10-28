const std      = @import("std");
const builtin  = @import("builtin");
const present  = @import("present");
const vulkan   = @import("vulkan/index.zig");

pub const Renderer = struct {
   _allocator        : std.mem.Allocator,
   _vulkan_instance  : vulkan.Instance,

   pub const CreateInfo = struct {
      debugging   : bool,
   };

   pub const CreateError = error {
      VulkanInstanceCreateError,
   };

   pub fn create(allocator : std.mem.Allocator, window : * present.Window, create_info : * const CreateInfo) CreateError!@This() {
      const vulkan_instance_extensions : [] const [*:0] const u8 = &([0] [*:0] const u8 {}) ++
         present.VULKAN_REQUIRED_EXTENSIONS.Instance;

      const vulkan_device_extensions : [] const [*:0] const u8 = &([0] [*:0] const u8 {}) ++
         present.VULKAN_REQUIRED_EXTENSIONS.Device;

      const vulkan_instance = vulkan.Instance.create(allocator, &.{
         .extensions = vulkan_instance_extensions,
         .debugging  = create_info.debugging,
      }) catch return error.VulkanInstanceCreateFailure;
      errdefer vulkan_instance.destroy(allocator);

      _ = window;
      _ = vulkan_device_extensions;
      
      return @This(){
         ._allocator       = allocator,
         ._vulkan_instance = vulkan_instance,
      };
   }

   pub fn destroy(self : @This()) void {
      self._vulkan_instance.destroy(self._allocator);
      return;
   }
};

