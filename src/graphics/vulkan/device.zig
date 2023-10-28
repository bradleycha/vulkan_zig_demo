const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const Queues = struct {
   graphics : c.VkQueue,
   transfer : c.VkQueue,
};

pub const Device = struct {
   vk_device   : c.VkDevice,
   queues      : Queues,

   pub const CreateInfo = struct {
      physical_device      : * const root.PhysicalDevice,
      enabled_extensions   : [] const [*:0] const u8,
   };

   pub const CreateError = error {
      OutOfMemory,
      Unknown,
      DeviceLost,
      MissingRequiredExtensions,
      MissingRequiredFeatures,
   };

   pub fn create(create_info : * const CreateInfo) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const enabled_extensions   = create_info.enabled_extensions;
      const physical_device      = create_info.physical_device;
      const queue_family_indices = &physical_device.queue_family_indices;

      const vk_physical_device_features = c.VkPhysicalDeviceFeatures{
         .robustBufferAccess                       = c.VK_FALSE,
         .fullDrawIndexUint32                      = c.VK_FALSE,
         .imageCubeArray                           = c.VK_FALSE,
         .independentBlend                         = c.VK_FALSE,
         .geometryShader                           = c.VK_FALSE,
         .tessellationShader                       = c.VK_FALSE,
         .sampleRateShading                        = c.VK_FALSE,
         .dualSrcBlend                             = c.VK_FALSE,
         .logicOp                                  = c.VK_FALSE,
         .multiDrawIndirect                        = c.VK_FALSE,
         .drawIndirectFirstInstance                = c.VK_FALSE,
         .depthClamp                               = c.VK_FALSE,
         .depthBiasClamp                           = c.VK_FALSE,
         .fillModeNonSolid                         = c.VK_FALSE,
         .depthBounds                              = c.VK_FALSE,
         .wideLines                                = c.VK_FALSE,
         .largePoints                              = c.VK_FALSE,
         .alphaToOne                               = c.VK_FALSE,
         .multiViewport                            = c.VK_FALSE,
         .samplerAnisotropy                        = c.VK_FALSE,
         .textureCompressionETC2                   = c.VK_FALSE,
         .textureCompressionASTC_LDR               = c.VK_FALSE,
         .textureCompressionBC                     = c.VK_FALSE,
         .occlusionQueryPrecise                    = c.VK_FALSE,
         .pipelineStatisticsQuery                  = c.VK_FALSE,
         .vertexPipelineStoresAndAtomics           = c.VK_FALSE,
         .fragmentStoresAndAtomics                 = c.VK_FALSE,
         .shaderTessellationAndGeometryPointSize   = c.VK_FALSE,
         .shaderImageGatherExtended                = c.VK_FALSE,
         .shaderStorageImageExtendedFormats        = c.VK_FALSE,
         .shaderStorageImageMultisample            = c.VK_FALSE,
         .shaderStorageImageReadWithoutFormat      = c.VK_FALSE,
         .shaderStorageImageWriteWithoutFormat     = c.VK_FALSE,
         .shaderUniformBufferArrayDynamicIndexing  = c.VK_FALSE,
         .shaderSampledImageArrayDynamicIndexing   = c.VK_FALSE,
         .shaderStorageBufferArrayDynamicIndexing  = c.VK_FALSE,
         .shaderStorageImageArrayDynamicIndexing   = c.VK_FALSE,
         .shaderClipDistance                       = c.VK_FALSE,
         .shaderCullDistance                       = c.VK_FALSE,
         .shaderFloat64                            = c.VK_FALSE,
         .shaderInt64                              = c.VK_FALSE,
         .shaderInt16                              = c.VK_FALSE,
         .shaderResourceResidency                  = c.VK_FALSE,
         .shaderResourceMinLod                     = c.VK_FALSE,
         .sparseBinding                            = c.VK_FALSE,
         .sparseResidencyBuffer                    = c.VK_FALSE,
         .sparseResidencyImage2D                   = c.VK_FALSE,
         .sparseResidencyImage3D                   = c.VK_FALSE,
         .sparseResidency2Samples                  = c.VK_FALSE,
         .sparseResidency4Samples                  = c.VK_FALSE,
         .sparseResidency8Samples                  = c.VK_FALSE,
         .sparseResidency16Samples                 = c.VK_FALSE,
         .sparseResidencyAliased                   = c.VK_FALSE,
         .variableMultisampleRate                  = c.VK_FALSE,
         .inheritedQueries                         = c.VK_FALSE,
      };

      var vk_infos_create_queue_buffer : [root.QueueFamilyIndices.INFO.Count] c.VkDeviceQueueCreateInfo = undefined;
      var vk_infos_create_queue_count = _populateUniqueQueueCreateInfos(queue_family_indices, &vk_infos_create_queue_buffer);

      const vk_info_create_device = c.VkDeviceCreateInfo{
         .sType                     = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
         .pNext                     = null,
         .flags                     = 0x00000000,
         .queueCreateInfoCount      = vk_infos_create_queue_count,
         .pQueueCreateInfos         = &vk_infos_create_queue_buffer,
         .enabledLayerCount         = 0,
         .ppEnabledLayerNames       = undefined,
         .enabledExtensionCount     = @intCast(enabled_extensions.len),
         .ppEnabledExtensionNames   = enabled_extensions.ptr,
         .pEnabledFeatures          = &vk_physical_device_features,
      };

      var vk_device : c.VkDevice = undefined;
      vk_result = c.vkCreateDevice(physical_device.vk_physical_device, &vk_info_create_device, null, &vk_device);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_INITIALIZATION_FAILED => return error.Unknown,
         c.VK_ERROR_EXTENSION_NOT_PRESENT => return error.MissingRequiredExtensions,
         c.VK_ERROR_FEATURE_NOT_PRESENT   => return error.MissingRequiredFeatures,
         c.VK_ERROR_TOO_MANY_OBJECTS      => return error.OutOfMemory,
         c.VK_ERROR_DEVICE_LOST           => return error.DeviceLost,
         else                             => unreachable,
      }
      errdefer c.vkDestroyDevice(vk_device, null);

      var vk_queue_graphics : c.VkQueue = undefined;
      c.vkGetDeviceQueue(vk_device, queue_family_indices.graphics, 0, &vk_queue_graphics);

      var vk_queue_transfer : c.VkQueue = undefined;
      c.vkGetDeviceQueue(vk_device, queue_family_indices.transfer, 0, &vk_queue_transfer);

      const queues = Queues{
         .graphics   = vk_queue_graphics,
         .transfer   = vk_queue_transfer,
      };

      return @This(){
         .vk_device  = vk_device,
         .queues     = queues,
      };
   }

   pub fn destroy(self : @This()) void {
      c.vkDestroyDevice(self.vk_device, null);
      return;
   }
};

fn _populateUniqueQueueCreateInfos(queue_family_indices : * const root.QueueFamilyIndices, vk_infos_create_queue_buffer : * [root.QueueFamilyIndices.INFO.Count] c.VkDeviceQueueCreateInfo) u32 {
   // We only want to create queues for each unique queue family index.
   // Therefore, we need to implement a set data structure for our indices and
   // only populate vulkan create infos for our unique queue families.

   var queue_families_array : [root.QueueFamilyIndices.INFO.Count] u32 = undefined;
   queue_families_array[root.QueueFamilyIndices.INFO.Index.Graphics] = queue_family_indices.graphics;
   queue_families_array[root.QueueFamilyIndices.INFO.Index.Transfer] = queue_family_indices.transfer;

   var queue_families_unique : [root.QueueFamilyIndices.INFO.Count] u32 = undefined;
   var queue_families_unique_count : u32 = 0;

   loop_insert: for (&queue_families_array) |queue_family_index| {
      for (queue_families_unique[0..queue_families_unique_count]) |queue_family_index_existing| {
         if (queue_family_index == queue_family_index_existing) {
            continue :loop_insert;
         }
      }

      // This is done to ensure pointer lifetimes are valid outside function scope.
      const S = struct{var QUEUE_PRIORITY : f32 = 1.0;};

      queue_families_unique[queue_families_unique_count] = queue_family_index;
      vk_infos_create_queue_buffer[queue_families_unique_count] = c.VkDeviceQueueCreateInfo{
         .sType            = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
         .pNext            = null,
         .flags            = 0x00000000,
         .queueFamilyIndex = queue_family_index,
         .queueCount       = 1,
         .pQueuePriorities = &S.QUEUE_PRIORITY,
      };

      queue_families_unique_count += 1;
   }

   return queue_families_unique_count;
}

