const root  = @import("index.zig");
const std   = @import("std");
const math  = @import("math");
const c     = @import("cimports");

pub const ImageSource = struct {
   data        : [] const u8,
   format      : PixelFormat,
   width       : u32,
   height      : u32,

   pub const PixelFormat = enum(c.VkFormat) {
      rgba8888 = c.VK_FORMAT_R8G8B8A8_SRGB,

      pub fn bytesPerPixel(self : @This()) usize {
         switch (self) {
            .rgba8888 => return 4,
         }

         unreachable;
      }
   };
};

pub const ImageSampling = struct {
   filter_minification  : Filter,
   filter_magnification : Filter,
   address_mode_u       : AddressMode,
   address_mode_v       : AddressMode,
   address_mode_w       : AddressMode,

   pub const Filter = enum(c.VkFilter) {
      nearest  = c.VK_FILTER_NEAREST,
      linear   = c.VK_FILTER_LINEAR,
   };

   pub const AddressMode = enum(c.VkSamplerAddressMode) {
      repeat            = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
      mirrored_repeat   = c.VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT,
      clamp_to_edge     = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
      clamp_to_border   = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
   };
};

const MEMORY_FLAGS = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;

pub const MemorySourceImage = struct {
   memory_source  : root.MemorySource,

   pub fn findSuitable(vk_physical_device_memory_properties : c.VkPhysicalDeviceMemoryProperties) ? @This() {
      const memory_source = root.MemorySource.findSuitable(
         MEMORY_FLAGS,
         vk_physical_device_memory_properties,
      ) orelse return null;

      return @This(){
         .memory_source = memory_source,
      };
   }
};

pub const Image = struct {
   vk_image          : c.VkImage,
   vk_device_memory  : c.VkDeviceMemory,

   pub const CreateInfo = struct {
      vk_device      : c.VkDevice,
      format         : ImageSource.PixelFormat,
      tiling         : c.VkImageTiling,
      width          : u32,
      height         : u32,
      usage_flags    : c.VkImageUsageFlags,
   };

   pub const CreateError = error {
      OutOfMemory,
      Unknown,
   };

   pub fn create(create_info : * const CreateInfo, memory_source : * const MemorySourceImage) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const vk_device = create_info.vk_device;

      const vk_info_create_image = c.VkImageCreateInfo{
         .sType                  = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
         .pNext                  = null,
         .flags                  = 0x00000000,
         .imageType              = c.VK_IMAGE_TYPE_2D,
         .format                 = @intFromEnum(create_info.format),
         .extent                 = c.VkExtent3D{
            .width   = create_info.width,
            .height  = create_info.height,
            .depth   = 1,
         },
         .mipLevels              = 1,
         .arrayLayers            = 1,
         .samples                = c.VK_SAMPLE_COUNT_1_BIT,
         .tiling                 = create_info.tiling,
         .usage                  = create_info.usage_flags,
         .sharingMode            = c.VK_SHARING_MODE_EXCLUSIVE,
         .queueFamilyIndexCount  = 0,
         .pQueueFamilyIndices    = undefined,
         .initialLayout          = c.VK_IMAGE_LAYOUT_UNDEFINED,
      };

      var vk_image : c.VkImage = undefined;
      vk_result = c.vkCreateImage(vk_device, &vk_info_create_image, null, &vk_image);
      switch (vk_result) {
         c.VK_SUCCESS                                    => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY                   => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY                 => return error.OutOfMemory,
         c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT            => return error.OutOfMemory,
         c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR   => return error.Unknown,
         else                                            => unreachable,
      }
      errdefer c.vkDestroyImage(vk_device, vk_image, null);

      var vk_image_memory_requirements : c.VkMemoryRequirements = undefined;
      c.vkGetImageMemoryRequirements(vk_device, vk_image, &vk_image_memory_requirements);

      const vk_info_memory_allocate = c.VkMemoryAllocateInfo{
         .sType            = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
         .pNext            = null,
         .allocationSize   = vk_image_memory_requirements.size,
         .memoryTypeIndex  = memory_source.memory_source.vk_memory_index,
      };

      var vk_device_memory : c.VkDeviceMemory = undefined;
      vk_result = c.vkAllocateMemory(vk_device, &vk_info_memory_allocate, null, &vk_device_memory);
      switch (vk_result) {
         c.VK_SUCCESS                                    => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY                   => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY                 => return error.OutOfMemory,
         c.VK_ERROR_INVALID_EXTERNAL_HANDLE              => return error.OutOfMemory,
         c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR   => return error.Unknown,
         else                                            => unreachable,
      }
      errdefer c.vkFreeMemory(vk_device, vk_device_memory, null);

      vk_result = c.vkBindImageMemory(vk_device, vk_image, vk_device_memory, 0);
      switch (vk_result) {
         c.VK_SUCCESS                                    => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY                   => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY                 => return error.OutOfMemory,
         c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR   => return error.Unknown,
         else                                            => unreachable,
      }

      return @This(){
         .vk_image         = vk_image,
         .vk_device_memory = vk_device_memory,
      };
   }

   pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
      c.vkFreeMemory(vk_device, self.vk_device_memory, null);
      c.vkDestroyImage(vk_device, self.vk_image, null);
      return;
   }
};

pub const ImageView = struct {
   vk_image_view  : c.VkImageView,

   pub const CreateError = error {
      OutOfMemory,
      Unknown,
   };

   pub const CreateInfo = struct {
      vk_device   : c.VkDevice,
      vk_image    : c.VkImage,
      format      : ImageSource.PixelFormat,
   };

   pub fn create(create_info : * const CreateInfo) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const vk_device   = create_info.vk_device;
      const vk_image    = create_info.vk_image;
      const format      = create_info.format;

      const vk_info_create_image_view = c.VkImageViewCreateInfo{
         .sType            = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
         .pNext            = null,
         .flags            = 0x00000000,
         .image            = vk_image,
         .viewType         = c.VK_IMAGE_VIEW_TYPE_2D,
         .format           = @intFromEnum(format),
         .components       = c.VkComponentMapping{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
         },
         .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask       = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel     = 0,
            .levelCount       = 1,
            .baseArrayLayer   = 0,
            .layerCount       = 1,
         },
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
      
      return @This(){
         .vk_image_view = vk_image_view,
      };
   }

   pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
      c.vkDestroyImageView(vk_device, self.vk_image_view, null);
      return;
   }
};

pub const Sampler = struct {
   vk_sampler  : c.VkSampler,

   pub const CreateError = error {
      OutOfMemory,
      Unknown,
   };

   pub const CreateInfo = struct {
      vk_device                     : c.VkDevice,
      sampling                      : ImageSampling,
      anisotropic_filtering_enabled : c.VkBool32,
      anisotropic_filtering_level   : f32,
   };

   pub fn create(create_info : * const CreateInfo) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const vk_device                     = create_info.vk_device;
      const sampling                      = create_info.sampling;
      const anisotropic_filtering_enabled = create_info.anisotropic_filtering_enabled;
      const anisotropic_filtering_level   = create_info.anisotropic_filtering_level;

      const vk_info_create_sampler = c.VkSamplerCreateInfo{
         .sType                     = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
         .pNext                     = null,
         .flags                     = 0x00000000,
         .magFilter                 = @intFromEnum(sampling.filter_magnification),
         .minFilter                 = @intFromEnum(sampling.filter_minification),
         .mipmapMode                = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
         .addressModeU              = @intFromEnum(sampling.address_mode_u),
         .addressModeV              = @intFromEnum(sampling.address_mode_v),
         .addressModeW              = @intFromEnum(sampling.address_mode_w),
         .mipLodBias                = 0.0,
         .anisotropyEnable          = anisotropic_filtering_enabled,
         .maxAnisotropy             = anisotropic_filtering_level,
         .compareEnable             = c.VK_FALSE,
         .compareOp                 = c.VK_COMPARE_OP_ALWAYS,
         .minLod                    = 0.0,
         .maxLod                    = 0.0,
         .borderColor               = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
         .unnormalizedCoordinates   = c.VK_FALSE,
      };

      var vk_sampler : c.VkSampler = undefined;
      vk_result = c.vkCreateSampler(vk_device, &vk_info_create_sampler, null, &vk_sampler);
      switch (vk_result) {
         c.VK_SUCCESS                                    => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY                   => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY                 => return error.OutOfMemory,
         c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR   => return error.Unknown,
         else                                            => unreachable,
      }
      errdefer c.vkDestroySampler(vk_device, vk_sampler, null);

      return @This(){
         .vk_sampler = vk_sampler,
      };
   }

   pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
      c.vkDestroySampler(vk_device, self.vk_sampler, null);
      return;
   }
};

