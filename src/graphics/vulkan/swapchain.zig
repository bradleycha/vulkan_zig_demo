const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const Swapchain = struct {
   vk_swapchain   : c.VkSwapchainKHR,

   pub const CreateInfo = struct {
      vk_device               : c.VkDevice,
      vk_surface              : c.VkSurfaceKHR,
      queue_family_indices    : * const root.QueueFamilyIndices,
      swapchain_configuration : * const root.SwapchainConfiguration,
   };
   
   pub const CreateError = error {
      OutOfMemory,
      DeviceLost,
      SurfaceLost,
      WindowInUse,
      Unknown,
   };

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      return _createSwapchain(allocator, create_info, @ptrCast(@alignCast(c.VK_NULL_HANDLE)));
   }

   pub fn createFrom(self : * const @This(), allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      return _createSwapchain(allocator, create_info, self.vk_swapchain);
   }

   fn _createSwapchain(allocator : std.mem.Allocator, create_info : * const CreateInfo, vk_swapchain_old : c.VkSwapchainKHR) CreateError!@This() {
      _ = allocator;
      _ = create_info;
      _ = vk_swapchain_old;
      unreachable;
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice) void {
      _ = self;
      _ = allocator;
      _ = vk_device;
      unreachable;
   }
};

