const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const Swapchain = struct {
   vk_swapchain      : c.VkSwapchainKHR,
   vk_images_count   : u32,
   vk_images_ptr     : [*] c.VkImage,

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
      return _createRaw(allocator, create_info, @ptrCast(@alignCast(c.VK_NULL_HANDLE)));
   }

   pub fn createFrom(self : * const @This(), allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      return _createRaw(allocator, create_info, self.vk_swapchain);
   }

   fn _createRaw(allocator : std.mem.Allocator, create_info : * const CreateInfo, vk_swapchain_old : c.VkSwapchainKHR) CreateError!@This() {
      const vk_swapchain = try _createSwapchain(create_info, vk_swapchain_old);
      errdefer c.vkDestroySwapchainKHR(create_info.vk_device, vk_swapchain, null);

      const vk_images = try _getSwapchainImages(allocator, create_info.vk_device, vk_swapchain);
      errdefer allocator.free(vk_images);

      return @This(){
         .vk_swapchain     = vk_swapchain,
         .vk_images_count  = @intCast(vk_images.len),
         .vk_images_ptr    = vk_images.ptr,
      };
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice) void {
      const vk_images = self.vk_images_ptr[0..self.vk_images_count];

      allocator.free(vk_images);
      c.vkDestroySwapchainKHR(vk_device, self.vk_swapchain, null);
      return;
   }
};

fn _createSwapchain(create_info : * const Swapchain.CreateInfo, vk_swapchain_old : c.VkSwapchainKHR) Swapchain.CreateError!c.VkSwapchainKHR {
   var vk_result : c.VkResult = undefined;

   const vk_device               = create_info.vk_device;
   const vk_surface              = create_info.vk_surface;
   const queue_family_indices    = create_info.queue_family_indices;
   const swapchain_configuration = create_info.swapchain_configuration;

   const image_count = _chooseImageCount(&swapchain_configuration.capabilities);

   var concurrency_mode_queue_family_indices_buffer : [_ConcurrencyMode.INFO.Count] u32 = undefined;
   const concurrency_mode = _chooseConcurrencyMode(queue_family_indices, &concurrency_mode_queue_family_indices_buffer);

   const vk_info_create_swapchain = c.VkSwapchainCreateInfoKHR{
      .sType                  = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
      .pNext                  = null,
      .flags                  = 0x00000000,
      .surface                = vk_surface,
      .minImageCount          = image_count,
      .imageFormat            = swapchain_configuration.format.format,
      .imageColorSpace        = swapchain_configuration.format.colorSpace,
      .imageExtent            = swapchain_configuration.extent,
      .imageArrayLayers       = 1,
      .imageUsage             = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
      .imageSharingMode       = concurrency_mode.sharing_mode,
      .queueFamilyIndexCount  = concurrency_mode.queue_family_indices_count,
      .pQueueFamilyIndices    = concurrency_mode.queue_family_indices_ptr,
      .preTransform           = swapchain_configuration.capabilities.currentTransform,
      .compositeAlpha         = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
      .presentMode            = swapchain_configuration.present_mode,
      .clipped                = c.VK_TRUE,
      .oldSwapchain           = vk_swapchain_old,
   };

   var vk_swapchain : c.VkSwapchainKHR = undefined;
   vk_result = c.vkCreateSwapchainKHR(vk_device, &vk_info_create_swapchain, null, &vk_swapchain);
   switch (vk_result) {
      c.VK_SUCCESS                           => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY          => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY        => return error.OutOfMemory,
      c.VK_ERROR_DEVICE_LOST                 => return error.DeviceLost,
      c.VK_ERROR_SURFACE_LOST_KHR            => return error.SurfaceLost,
      c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR    => return error.WindowInUse,
      c.VK_ERROR_INITIALIZATION_FAILED       => return error.Unknown,
      c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT   => return error.OutOfMemory,
      else                                   => unreachable,
   }
   errdefer c.vkDestroySwapchainKHR(vk_device, vk_swapchain, null);

   return vk_swapchain;
}

fn _chooseImageCount(capabilities : * const c.VkSurfaceCapabilitiesKHR) u32 {
   const images_min = capabilities.minImageCount;
   const images_max = capabilities.maxImageCount;

   if (images_max != 0 and images_min == images_max) {
      return images_min;
   }

   return images_min + 1;
}

const _ConcurrencyMode = struct {
   sharing_mode               : c.VkSharingMode,
   queue_family_indices_count : u32,
   queue_family_indices_ptr   : [*] const u32,

   pub const INFO = struct {
      pub const Count = 2;
      pub const Index = struct {
         pub const Graphics   = 0;
         pub const Present    = 1;
      };
   };
};

fn _chooseConcurrencyMode(queue_family_indices : * const root.QueueFamilyIndices, queue_family_indices_array : * [_ConcurrencyMode.INFO.Count] u32) _ConcurrencyMode {
   if (queue_family_indices.graphics == queue_family_indices.present) {
      return .{
         .sharing_mode                 = c.VK_SHARING_MODE_EXCLUSIVE,
         .queue_family_indices_count   = undefined,
         .queue_family_indices_ptr     = undefined,
      };
   }

   queue_family_indices_array[_ConcurrencyMode.INFO.Index.Graphics]  = queue_family_indices.graphics;
   queue_family_indices_array[_ConcurrencyMode.INFO.Index.Present]   = queue_family_indices.present;

   return .{
      .sharing_mode                 = c.VK_SHARING_MODE_CONCURRENT,
      .queue_family_indices_count   = _ConcurrencyMode.INFO.Count,
      .queue_family_indices_ptr     = queue_family_indices_array.ptr,
   };
}

fn _getSwapchainImages(allocator : std.mem.Allocator, vk_device : c.VkDevice, vk_swapchain : c.VkSwapchainKHR) Swapchain.CreateError![] c.VkImage {
   var vk_result : c.VkResult = undefined;

   var vk_images_count : u32 = undefined;
   vk_result = c.vkGetSwapchainImagesKHR(vk_device, vk_swapchain, &vk_images_count, null);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }

   var vk_images = try allocator.alloc(c.VkImage, @as(usize, vk_images_count));
   errdefer allocator.free(vk_images);
   vk_result = c.vkGetSwapchainImagesKHR(vk_device, vk_swapchain, &vk_images_count, vk_images.ptr);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }

   return vk_images;
}

