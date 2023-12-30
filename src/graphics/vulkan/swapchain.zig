const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const Swapchain = struct {
   vk_swapchain            : c.VkSwapchainKHR,
   vk_images_ptr           : [*] c.VkImage,
   vk_image_views_ptr      : [*] c.VkImageView,
   vk_images_count         : u32,
   image_depth_buffer      : root.Image,
   image_view_depth_buffer : root.ImageView,

   pub const CreateInfo = struct {
      vk_device               : c.VkDevice,
      vk_surface              : c.VkSurfaceKHR,
      queue_family_indices    : * const root.QueueFamilyIndices,
      memory_source_image     : * const root.MemorySourceImage,
      swapchain_configuration : * const root.SwapchainConfiguration,
      depth_buffer_format     : c.VkFormat,
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
      const vk_device = create_info.vk_device;

      const vk_swapchain = try _createSwapchain(create_info, vk_swapchain_old);
      errdefer c.vkDestroySwapchainKHR(vk_device, vk_swapchain, null);

      const vk_images = try _getSwapchainImages(allocator, vk_device, vk_swapchain);
      errdefer allocator.free(vk_images);

      const vk_image_views = try _createSwapchainImageViews(allocator, vk_device, vk_images, create_info.swapchain_configuration.format.format);
      errdefer {
         for (vk_image_views) |vk_image_view| {
            c.vkDestroyImageView(vk_device, vk_image_view, null);
         }

         allocator.free(vk_image_views);
      }

      const image_depth_buffer = try root.Image.create(&.{
         .vk_device     = vk_device,
         .vk_format     = create_info.depth_buffer_format,
         .tiling        = c.VK_IMAGE_TILING_OPTIMAL,
         .width         = create_info.swapchain_configuration.extent.width,
         .height        = create_info.swapchain_configuration.extent.height,
         .usage_flags   = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
      }, create_info.memory_source_image);
      errdefer image_depth_buffer.destroy(vk_device);

      const image_view_depth_buffer = try root.ImageView.create(&.{
         .vk_device     = vk_device,
         .vk_image      = image_depth_buffer.vk_image,
         .vk_format     = create_info.depth_buffer_format,
         .aspect_mask   = c.VK_IMAGE_ASPECT_DEPTH_BIT,
      });
      errdefer image_view_depth_buffer.destroy(vk_device);

      return @This(){
         .vk_swapchain              = vk_swapchain,
         .vk_images_ptr             = vk_images.ptr,
         .vk_image_views_ptr        = vk_image_views.ptr,
         .vk_images_count           = @intCast(vk_images.len),
         .image_depth_buffer        = image_depth_buffer,
         .image_view_depth_buffer   = image_view_depth_buffer,
      };
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice) void {
      const vk_images      = self.vk_images_ptr[0..self.vk_images_count];
      const vk_image_views = self.vk_image_views_ptr[0..self.vk_images_count];

      self.image_view_depth_buffer.destroy(vk_device);
      self.image_depth_buffer.destroy(vk_device);

      for (vk_image_views) |vk_image_view| {
         c.vkDestroyImageView(vk_device, vk_image_view, null);
      }

      allocator.free(vk_image_views);
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

fn _createSwapchainImageViews(allocator : std.mem.Allocator, vk_device : c.VkDevice, vk_images : [] const c.VkImage, vk_format : c.VkFormat) Swapchain.CreateError![] c.VkImageView {
   var vk_image_views = try allocator.alloc(c.VkImageView, vk_images.len);
   errdefer allocator.free(vk_image_views);

   for (vk_image_views, vk_images, 0..vk_images.len) |*vk_image_view_dest, vk_image, i| {
      errdefer for (vk_image_views[0..i]) |vk_image_view_old| {
         c.vkDestroyImageView(vk_device, vk_image_view_old, null);
      };

      const vk_image_view = try _createImageView(vk_device, vk_image, vk_format);
      errdefer c.vkDestroyImageView(vk_device, vk_image_view, null);

      vk_image_view_dest.* = vk_image_view;
   }
   errdefer for (vk_image_views) |vk_image_view| {
      c.vkDestroyImageView(vk_device, vk_image_view, null);
   };

   return vk_image_views;
}

fn _createImageView(vk_device : c.VkDevice, vk_image : c.VkImage, vk_format : c.VkFormat) Swapchain.CreateError!c.VkImageView {
   var vk_result : c.VkResult = undefined;

   const vk_image_view_components = c.VkComponentMapping{
      .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
      .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
      .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
      .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
   };

   const vk_image_view_subresource_range = c.VkImageSubresourceRange{
      .aspectMask       = c.VK_IMAGE_ASPECT_COLOR_BIT,
      .baseMipLevel     = 0,
      .levelCount       = 1,
      .baseArrayLayer   = 0,
      .layerCount       = 1,
   };

   const vk_info_create_image_view = c.VkImageViewCreateInfo{
      .sType            = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
      .pNext            = null,
      .flags            = 0x00000000,
      .image            = vk_image,
      .viewType         = c.VK_IMAGE_VIEW_TYPE_2D,
      .format           = vk_format,
      .components       = vk_image_view_components,
      .subresourceRange = vk_image_view_subresource_range,
   };

   var vk_image_view : c.VkImageView = undefined;
   vk_result = c.vkCreateImageView(vk_device, &vk_info_create_image_view, null, &vk_image_view);
   switch (vk_result) {
      c.VK_SUCCESS                                    => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY                   => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY                 => return error.OutOfMemory,
      c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR   => return error.Unknown,
      else                                            => unreachable,
   }
   errdefer c.vkDestroyImageView(vk_device, vk_image_view, null);

   return vk_image_view;
}

