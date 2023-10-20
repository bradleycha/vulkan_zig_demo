const std         = @import("std");
const zest        = @import("zig-essential-tools");
const f_present   = @import("present.zig");
const c           = @import("cimports.zig");

const VULKAN_TEMP_HEAP = zest.mem.SingleScopeHeap(8 * 1024 * 1024);

pub const Renderer = struct {
   _allocator                       : std.mem.Allocator,
   _vulkan_instance                 : VulkanInstance,
   _vulkan_surface                  : VulkanSurface,
   _vulkan_physical_device          : VulkanPhysicalDevice,
   _vulkan_device                   : VulkanDevice,
   _vulkan_swapchain                : VulkanSwapchain,
   _vulkan_graphics_pipeline        : VulkanGraphicsPipeline,
   _vulkan_framebuffers             : VulkanFramebuffers,
   _vulkan_graphics_command_pool    : VulkanGraphicsCommandPool,
   _vulkan_graphics_command_buffer  : VulkanGraphicsCommandBuffer,

   pub const CreateOptions = struct {
      debugging            : bool,
      name                 : [*:0] const u8,
      version              : u32,
      refresh_mode         : RefreshMode,
      shader_spv_vertex    : [] align(@alignOf(u32)) const u8,
      shader_spv_fragment  : [] align(@alignOf(u32)) const u8,
   };

   pub const RefreshMode = enum {
      SingleBuffered,
      DoubleBuffered,
      TripleBuffered,
   };
   
   pub const CreateError = error {
      OutOfMemory,
      VulkanInstanceCreateFailure,
      VulkanWindowSurfaceCreateFailure,
      VulkanPhysicalDevicePickFailure,
      NoVulkanPhysicalDeviceAvailable,
      VulkanDeviceCreateFailure,
      VulkanSwapchainCreateFailure,
      VulkanGraphicsPipelineCreateFailure,
      VulkanFramebuffersCreateFailure,
      VulkanGraphicsCommandPoolCreateFailure,
      VulkanGraphicsCommandBufferCreateFailure,
   };

   pub fn create(window : * const f_present.Window, allocator : std.mem.Allocator, create_options : CreateOptions) CreateError!@This() {
      const vulkan_instance = VulkanInstance.create(.{
         .application_name    = create_options.name,
         .application_version = create_options.version,
         .engine_name         = "No Engine ;)",
         .engine_version      = 0x00000000,
         .debugging           = create_options.debugging,
      }) catch return error.VulkanInstanceCreateFailure;
      errdefer vulkan_instance.destroy();

      const vulkan_surface = VulkanSurface.create(
         vulkan_instance.vk_instance, window,
      ) catch return error.VulkanWindowSurfaceCreateFailure;
      errdefer vulkan_surface.destroy(vulkan_instance.vk_instance);

      const VULKAN_REQUIRED_DEVICE_EXTENSIONS = [_] [*:0] const u8 {
         c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
      };

      const vulkan_physical_device = VulkanPhysicalDevice.pickMostSuitable(
         vulkan_instance.vk_instance, vulkan_surface.vk_surface, &VULKAN_REQUIRED_DEVICE_EXTENSIONS, window, create_options.refresh_mode,
      ) catch (return error.VulkanPhysicalDevicePickFailure) orelse return error.NoVulkanPhysicalDeviceAvailable;

      zest.dbg.log.info("using device \"{s}\" for vulkan rendering", .{&vulkan_physical_device.vk_physical_device_properties.deviceName});

      const vulkan_swapchain_configuration = &vulkan_physical_device.initial_swapchain_configuration;

      const vulkan_device = VulkanDevice.create(&vulkan_physical_device, &VULKAN_REQUIRED_DEVICE_EXTENSIONS) catch return error.VulkanDeviceCreateFailure;
      errdefer vulkan_device.destroy();

      const vulkan_swapchain = VulkanSwapchain.create(
         allocator,
         vulkan_device.vk_device,
         vulkan_surface.vk_surface,
         &vulkan_physical_device.queue_family_indices,
         vulkan_swapchain_configuration,
      ) catch return error.VulkanSwapchainCreateFailure;
      errdefer vulkan_swapchain.destroy(vulkan_device.vk_device);

      const vulkan_graphics_pipeline = VulkanGraphicsPipeline.create(vulkan_device.vk_device, &vulkan_physical_device.initial_swapchain_configuration, .{
         .spv_vertex    = create_options.shader_spv_vertex,
         .spv_fragment  = create_options.shader_spv_fragment,
      }) catch return error.VulkanGraphicsPipelineCreateFailure;
      errdefer vulkan_graphics_pipeline.destroy(vulkan_device.vk_device);

      const vulkan_framebuffers = VulkanFramebuffers.create(
         allocator,
         vulkan_device.vk_device,
         &vulkan_swapchain,
         &vulkan_graphics_pipeline,
         &vulkan_physical_device.initial_swapchain_configuration,
      ) catch return error.VulkanFramebuffersCreateFailure;
      errdefer vulkan_framebuffers.destroy(vulkan_device.vk_device);

      const vulkan_graphics_command_pool = VulkanGraphicsCommandPool.create(
         vulkan_device.vk_device, vulkan_physical_device.queue_family_indices.graphics,
      ) catch return error.VulkanGraphicsCommandPoolCreateFailure;
      errdefer vulkan_graphics_command_pool.destroy(vulkan_device.vk_device);

      const vulkan_graphics_command_buffer = VulkanGraphicsCommandBuffer.create(
         vulkan_device.vk_device, vulkan_graphics_command_pool.vk_command_pool,
      ) catch return error.VulkanGraphicsCommandBufferCreateFailure;

      return @This(){
         ._allocator                      = allocator,
         ._vulkan_instance                = vulkan_instance,
         ._vulkan_surface                 = vulkan_surface,
         ._vulkan_physical_device         = vulkan_physical_device,
         ._vulkan_device                  = vulkan_device,
         ._vulkan_swapchain               = vulkan_swapchain,
         ._vulkan_graphics_pipeline       = vulkan_graphics_pipeline,
         ._vulkan_framebuffers            = vulkan_framebuffers,
         ._vulkan_graphics_command_pool   = vulkan_graphics_command_pool,
         ._vulkan_graphics_command_buffer = vulkan_graphics_command_buffer,
      };
   }

   pub fn destroy(self : @This()) void {
      self._vulkan_graphics_command_pool.destroy(self._vulkan_device.vk_device);
      self._vulkan_framebuffers.destroy(self._vulkan_device.vk_device);
      self._vulkan_graphics_pipeline.destroy(self._vulkan_device.vk_device);
      self._vulkan_swapchain.destroy(self._vulkan_device.vk_device);
      self._vulkan_device.destroy();
      self._vulkan_surface.destroy(self._vulkan_instance.vk_instance);
      self._vulkan_instance.destroy();
      return;
   }
};

const VulkanInstance = struct {
   vk_instance             : c.VkInstance,
   vulkan_debug_messenger  : ? VulkanDebugMessenger,

   pub const CreateOptions = struct {
      application_name     : [*:0] const u8,
      application_version  : u32,
      engine_name          : [*:0] const u8,
      engine_version       : u32,
      debugging            : bool,
   };

   pub const CreateError = error {
      OutOfMemory,
      UnknownError,
      MissingRequiredValidationLayers,
      MissingRequiredExtensions,
      IncompatibleDriver,
      DebugMessengerCreateFailure,
   };

   pub fn create(create_options : CreateOptions) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const temp_allocator = VULKAN_TEMP_HEAP.allocator();

      var enabled_layers = std.ArrayList([*:0] const u8).init(temp_allocator);
      defer enabled_layers.deinit();

      var enabled_extensions = std.ArrayList([*:0] const u8).init(temp_allocator);
      defer enabled_extensions.deinit();

      try enabled_extensions.appendSlice(f_present.Window.requiredVulkanExtensions());
      try enabled_extensions.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);

      if (create_options.debugging == true) {
         try enabled_layers.append("VK_LAYER_KHRONOS_validation");
         try enabled_extensions.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
      }

      var vk_available_layers_count : u32 = undefined;
      vk_result = c.vkEnumerateInstanceLayerProperties(&vk_available_layers_count, null);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }

      var vk_available_layers = std.ArrayList(c.VkLayerProperties).init(temp_allocator);
      defer vk_available_layers.deinit();
      try vk_available_layers.resize(@as(usize, vk_available_layers_count));
      vk_result = c.vkEnumerateInstanceLayerProperties(&vk_available_layers_count, vk_available_layers.items.ptr);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }

      var vk_available_extensions_count : u32 = undefined;
      vk_result = c.vkEnumerateInstanceExtensionProperties(null, &vk_available_extensions_count, null);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable,
         else                             => unreachable,
      }

      var vk_available_extensions = std.ArrayList(c.VkExtensionProperties).init(temp_allocator);
      defer vk_available_extensions.deinit();
      try vk_available_extensions.resize(@as(usize, vk_available_extensions_count));
      vk_result = c.vkEnumerateInstanceExtensionProperties(null, &vk_available_extensions_count, vk_available_extensions.items.ptr);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable,
         else                             => unreachable,
      }

      var enabled_layers_found = true;
      for (enabled_layers.items) |enabled_layer_name| {
         var layer_found = false;
         for (vk_available_layers.items) |available_layer| {
            if (c.strcmp(&available_layer.layerName, enabled_layer_name) == 0) {
               layer_found = true;
               break;
            }
         }
         if (layer_found == false) {
            zest.dbg.log.err("missing required vulkan instance validation layer \"{s}\"", .{enabled_layer_name});
            enabled_layers_found = false;
         }
      }
      if (enabled_layers_found == false) {
         return error.MissingRequiredValidationLayers;
      }

      var enabled_extensions_found = true;
      for (enabled_extensions.items) |enabled_extension_name| {
         var extension_found = false;
         for (vk_available_extensions.items) |available_extension| {
            if (c.strcmp(&available_extension.extensionName, enabled_extension_name) == 0) {
               extension_found = true;
               break;
            }
         }
         if (extension_found == false) {
            zest.dbg.log.err("missing required vulkan instance extension \"{s}\"", .{enabled_extension_name});
            enabled_extensions_found = false;
         }
      }
      if (enabled_extensions_found == false) {
         return error.MissingRequiredExtensions;
      }

      const vk_info_create_debug_messenger = blk: {
         switch (create_options.debugging) {
            true  => break :blk &VulkanDebugMessenger.CREATE_INFO,
            false => break :blk null,
         }
      };

      const vk_info_application = c.VkApplicationInfo{
         .sType               = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
         .pNext               = null,
         .pApplicationName    = create_options.application_name,
         .applicationVersion  = create_options.application_version,
         .pEngineName         = create_options.engine_name,
         .engineVersion       = create_options.engine_version,
         .apiVersion          = c.VK_API_VERSION_1_0,
      };

      const vk_info_create_instance = c.VkInstanceCreateInfo{
         .sType                     = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
         .pNext                     = vk_info_create_debug_messenger,
         .flags                     = 0x00000000 | c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
         .pApplicationInfo          = &vk_info_application,
         .enabledLayerCount         = @intCast(enabled_layers.items.len),
         .ppEnabledLayerNames       = enabled_layers.items.ptr,
         .enabledExtensionCount     = @intCast(enabled_extensions.items.len),
         .ppEnabledExtensionNames   = enabled_extensions.items.ptr,
      };

      var vk_instance : c.VkInstance = undefined;
      vk_result = c.vkCreateInstance(&vk_info_create_instance, null, &vk_instance);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_INITIALIZATION_FAILED => return error.UnknownError,
         c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable,   // checked above
         c.VK_ERROR_EXTENSION_NOT_PRESENT => unreachable,   // checked above
         c.VK_ERROR_INCOMPATIBLE_DRIVER   => return error.IncompatibleDriver,
         else                             => unreachable,
      }
      errdefer c.vkDestroyInstance(vk_instance, null);

      const vulkan_debug_messenger = blk: {
         switch (create_options.debugging) {
            true  => break :blk VulkanDebugMessenger.create(vk_instance) catch return error.DebugMessengerCreateFailure,
            false => break :blk null,
         }
      };
      errdefer if (vulkan_debug_messenger) |debug_messenger| {
         debug_messenger.destroy(vk_instance);
      };

      return @This(){
         .vk_instance            = vk_instance,
         .vulkan_debug_messenger = vulkan_debug_messenger,
      };
   }

   pub fn destroy(self : @This()) void {
      if (self.vulkan_debug_messenger) |vulkan_debug_messenger| {
         vulkan_debug_messenger.destroy(self.vk_instance);
      }

      c.vkDestroyInstance(self.vk_instance, null);
      return;
   }
};

const VulkanDebugMessenger = struct {
   vk_debug_messenger   : c.VkDebugUtilsMessengerEXT,

   pub const CREATE_INFO = c.VkDebugUtilsMessengerCreateInfoEXT{
      .sType            = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
      .pNext            = null,
      .flags            = 0x00000000,
      .messageSeverity  = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
      .messageType      = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
      .pfnUserCallback  = _vkDebugMessengerCallback,
      .pUserData        = null,
   };

   fn _vkDebugMessengerCallback(
      p_message_severity   : c.VkDebugUtilsMessageSeverityFlagBitsEXT,
      p_message_type       : c.VkDebugUtilsMessageTypeFlagsEXT,
      p_callback_data      : ? * const c.VkDebugUtilsMessengerCallbackDataEXT,
      p_user_data          : ? * anyopaque,
   ) callconv(.C) c.VkBool32 {
      const message_severity  = p_message_severity;
      const message_type      = p_message_type;
      const callback_data     = p_callback_data orelse unreachable;
      _ = p_user_data;

      const message  = callback_data.pMessage orelse unreachable;
      const format   = "vulkan {s} : {s}";
      const prefix   = blk: {
         switch (message_type) {
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT      => break :blk "general",
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT   => break :blk "validation",
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT  => break :blk "performance",
            else                                               => unreachable,
         }
      };

      switch (message_severity) {
         c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT  => {
            zest.dbg.log.info(format, .{prefix, message});
         },
         c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT     => {
            zest.dbg.log.info(format, .{prefix, message});
         },
         c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT  => {
            zest.dbg.log.warn(format, .{prefix, message});
         },
         c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT    => {
            zest.dbg.log.err(format, .{prefix, message});
         },
         else => unreachable,
      }

      return c.VK_FALSE;
   }

   const _VulkanExtensions = struct {
      var vkCreateDebugUtilsMessengerEXT  : c.PFN_vkCreateDebugUtilsMessengerEXT    = null;
      var vkDestroyDebugUtilsMessengerEXT : c.PFN_vkDestroyDebugUtilsMessengerEXT   = null;
   };

   pub const CreateError = error {
      OutOfMemory,
      MissingRequiredExtensions,
   };

   pub fn create(vk_instance : c.VkInstance) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      if (_VulkanExtensions.vkCreateDebugUtilsMessengerEXT == null) {
         const ptr : c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(@alignCast(c.vkGetInstanceProcAddr(vk_instance, "vkCreateDebugUtilsMessengerEXT")));
         if (ptr == null) {
            return error.MissingRequiredExtensions;
         }

         _VulkanExtensions.vkCreateDebugUtilsMessengerEXT = ptr;
      }
      if (_VulkanExtensions.vkDestroyDebugUtilsMessengerEXT == null) {
         const ptr : c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(@alignCast(c.vkGetInstanceProcAddr(vk_instance, "vkDestroyDebugUtilsMessengerEXT")));
         if (ptr == null) {
            return error.MissingRequiredExtensions;
         }

         _VulkanExtensions.vkDestroyDebugUtilsMessengerEXT = ptr;
      }

      const pfn_create  = _VulkanExtensions.vkCreateDebugUtilsMessengerEXT orelse unreachable;
      const pfn_destroy = _VulkanExtensions.vkDestroyDebugUtilsMessengerEXT orelse unreachable;

      var vk_debug_messenger : c.VkDebugUtilsMessengerEXT = undefined;
      vk_result = pfn_create(vk_instance, &CREATE_INFO, null, &vk_debug_messenger);
      switch (vk_result) {
         c.VK_SUCCESS                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY => return error.OutOfMemory,
         else                          => unreachable,
      }
      errdefer pfn_destroy(vk_instance, vk_debug_messenger, null);

      return @This(){.vk_debug_messenger = vk_debug_messenger};
   }

   pub fn destroy(self : @This(), vk_instance : c.VkInstance) void {
      const pfn_destroy = _VulkanExtensions.vkDestroyDebugUtilsMessengerEXT orelse unreachable;

      pfn_destroy(vk_instance, self.vk_debug_messenger, null);
      return;
   }
};

const VulkanPhysicalDevice = struct {
   vk_physical_device               : c.VkPhysicalDevice,
   vk_physical_device_properties    : c.VkPhysicalDeviceProperties,
   vk_physical_device_features      : c.VkPhysicalDeviceFeatures,
   queue_family_indices             : QueueFamilyIndices,
   initial_swapchain_configuration  : VulkanSwapchainConfiguration,

   pub const QueueFamilyIndices = struct {
      graphics       : u32,
      presentation   : u32,
   };

   pub const PickError = error {
      OutOfMemory,
      UnknownError,
      SurfaceLost,
   };

   pub fn pickMostSuitable(vk_instance : c.VkInstance, vk_surface : c.VkSurfaceKHR, vk_required_extensions : [] const [*:0] const u8, window : * const f_present.Window, refresh_mode : Renderer.RefreshMode) PickError!?@This() {
      var vk_result : c.VkResult = undefined;

      const temp_allocator = VULKAN_TEMP_HEAP.allocator();

      var vk_physical_devices_count : u32 = undefined;
      vk_result = c.vkEnumeratePhysicalDevices(vk_instance, &vk_physical_devices_count, null);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_INITIALIZATION_FAILED => return error.UnknownError,
         else                             => unreachable,
      }

      var vk_physical_devices = std.ArrayList(c.VkPhysicalDevice).init(temp_allocator);
      defer vk_physical_devices.deinit();
      try vk_physical_devices.resize(@as(usize, vk_physical_devices_count));
      vk_result = c.vkEnumeratePhysicalDevices(vk_instance, &vk_physical_devices_count, vk_physical_devices.items.ptr);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_INITIALIZATION_FAILED => return error.UnknownError,
         else                             => unreachable,
      }

      var physical_device_chosen : ? @This() = null;

      for (vk_physical_devices.items) |vk_physical_device| {
         const physical_device_new = try _parsePhysicalDevice(
            vk_physical_device,
            vk_surface,
            vk_required_extensions,
            window,
            refresh_mode,
         ) orelse continue;

         if (physical_device_chosen == null) {
            physical_device_chosen = physical_device_new;
            continue;
         }

         const score_old = (physical_device_chosen orelse unreachable)._assignScore();
         const score_new = physical_device_new._assignScore();

         if (score_new > score_old) {
            physical_device_chosen = physical_device_new;
         }
      }

      return physical_device_chosen;
   }

   fn _parsePhysicalDevice(vk_physical_device : c.VkPhysicalDevice, vk_surface : c.VkSurfaceKHR, vk_required_extensions : [] const [*:0] const u8, window : * const f_present.Window, refresh_mode : Renderer.RefreshMode) PickError!?@This() {
      var vk_physical_device_properties : c.VkPhysicalDeviceProperties = undefined;
      c.vkGetPhysicalDeviceProperties(vk_physical_device, &vk_physical_device_properties);

      var vk_physical_device_features : c.VkPhysicalDeviceFeatures = undefined;
      c.vkGetPhysicalDeviceFeatures(vk_physical_device, &vk_physical_device_features);
      
      if (try _deviceSupportsExtensions(vk_physical_device, vk_required_extensions) == false) {
         zest.dbg.log.info("device \"{s}\" does not support required extensions, choosing new device", .{vk_physical_device_properties.deviceName});
         return null;
      }

      const queue_family_indices = try _findQueueFamilyIndices(vk_physical_device, vk_surface) orelse {
         zest.dbg.log.info("device \"{s}\" does not support required queue families, choosing new device", .{vk_physical_device_properties.deviceName});
         return null;
      };

      const initial_swapchain_configuration = try VulkanSwapchainConfiguration.selectBest(vk_physical_device, vk_surface, window, refresh_mode) orelse {
         zest.dbg.log.info("device \"{s}\" does not support required swapchain configuration, choosing new device", .{vk_physical_device_properties.deviceName});
         return null;
      };

      return @This(){
         .vk_physical_device              = vk_physical_device,
         .vk_physical_device_properties   = vk_physical_device_properties,
         .vk_physical_device_features     = vk_physical_device_features,
         .queue_family_indices            = queue_family_indices,
         .initial_swapchain_configuration = initial_swapchain_configuration,
      };   
   }

   fn _deviceSupportsExtensions(vk_physical_device : c.VkPhysicalDevice, vk_required_extensions : [] const [*:0] const u8) PickError!bool {
      var vk_result : c.VkResult = undefined;

      const temp_allocator = VULKAN_TEMP_HEAP.allocator();

      var vk_available_extensions_count : u32 = undefined;
      vk_result = c.vkEnumerateDeviceExtensionProperties(vk_physical_device, null, &vk_available_extensions_count, null);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable,
         else                             => unreachable,
      }

      var vk_available_extensions = std.ArrayList(c.VkExtensionProperties).init(temp_allocator);
      defer vk_available_extensions.deinit();
      try vk_available_extensions.resize(@as(usize, vk_available_extensions_count));
      vk_result = c.vkEnumerateDeviceExtensionProperties(vk_physical_device, null, &vk_available_extensions_count, vk_available_extensions.items.ptr);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable,
         else                             => unreachable,
      }

      var required_extensions_found = true;
      for (vk_required_extensions) |required_extension_name| {
         var extension_found = false;
         for (vk_available_extensions.items) |available_extension| {
            if (c.strcmp(&available_extension.extensionName, required_extension_name) == 0) {
               extension_found = true;
               break;
            }
         }
         if (extension_found == false) {
            zest.dbg.log.info("missing required vulkan device extension \"{s}\"", .{required_extension_name});
            required_extensions_found  = false;
         }
      }

      return required_extensions_found;
   }

   fn _findQueueFamilyIndices(vk_physical_device : c.VkPhysicalDevice, vk_surface : c.VkSurfaceKHR) PickError!?QueueFamilyIndices {
      var vk_result : c.VkResult = undefined;

      const temp_allocator = VULKAN_TEMP_HEAP.allocator();

      var vk_queue_families_count : u32 = undefined;
      c.vkGetPhysicalDeviceQueueFamilyProperties(vk_physical_device, &vk_queue_families_count, null);

      var vk_queue_families = std.ArrayList(c.VkQueueFamilyProperties).init(temp_allocator);
      defer vk_queue_families.deinit();
      try vk_queue_families.resize(@as(usize, vk_queue_families_count));
      c.vkGetPhysicalDeviceQueueFamilyProperties(vk_physical_device, &vk_queue_families_count, vk_queue_families.items.ptr);

      var queue_family_index_graphics     : ? u32 = null;
      var queue_family_index_presentation : ? u32 = null;

      for (vk_queue_families.items, 0..vk_queue_families_count) |vk_queue_family, i| {
         var vk_index : u32 = @intCast(i);

         var vk_queue_supports_presentation : c.VkBool32 = undefined;
         vk_result = c.vkGetPhysicalDeviceSurfaceSupportKHR(vk_physical_device, vk_index, vk_surface, &vk_queue_supports_presentation);
         switch (vk_result) {
            c.VK_SUCCESS                     => {},
            c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
            c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
            c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
            else                             => unreachable,
         }

         var queue_graphics      = false;
         var queue_presentation  = false;

         if (vk_queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            queue_graphics = true;
         }

         if (vk_queue_supports_presentation != c.VK_FALSE) {
            queue_presentation = true;
         }

         if (queue_graphics == true) {
            queue_family_index_graphics = vk_index;
         }
         if (queue_presentation == true) {
            queue_family_index_presentation = vk_index;
         }
      }

      const queue_family_indices = QueueFamilyIndices{
         .graphics      = queue_family_index_graphics orelse return null,
         .presentation  = queue_family_index_presentation orelse return null,
      };

      return queue_family_indices;
   }

   

   fn _assignScore(self : * const @This()) u32 {
      var score : u32 = 0;

      // For now we simply want to prefer discrete GPUs.
      if (self.vk_physical_device_properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
         score += 1000;
      }

      return score;
   }
};

const VulkanDevice = struct {
   vk_device   : c.VkDevice,
   queues      : Queues,

   pub const Queues = struct {
      graphics       : c.VkQueue,
      presentation   : c.VkQueue,
   };

   pub const CreateError = error {
      OutOfMemory,
      UnknownError,
      MissingRequiredExtensions,
      MissingRequiredFeatures,
      DeviceLost,
   };

   pub fn create(vulkan_physical_device : * const VulkanPhysicalDevice, vk_enabled_extensions : [] const [*:0] const u8) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const temp_allocator = VULKAN_TEMP_HEAP.allocator();

      var vk_available_extensions_count : u32 = undefined;
      vk_result = c.vkEnumerateDeviceExtensionProperties(vulkan_physical_device.vk_physical_device, null, &vk_available_extensions_count, null);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable,
         else                             => unreachable,
      }

      var vk_available_extensions = std.ArrayList(c.VkExtensionProperties).init(temp_allocator);
      defer vk_available_extensions.deinit();
      try vk_available_extensions.resize(@as(usize, vk_available_extensions_count));
      vk_result = c.vkEnumerateDeviceExtensionProperties(vulkan_physical_device.vk_physical_device, null, &vk_available_extensions_count, vk_available_extensions.items.ptr);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable,
         else                             => unreachable,
      }

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

      const MAX_QUEUE_FAMILIES = @typeInfo(VulkanPhysicalDevice.QueueFamilyIndices).Struct.fields.len;

      // We need this mess because we need to ensure all queues have a unique queue family index.
      // Effectively we implement a set data structure ourselves for efficiency.
      var vk_infos_create_queue_array : [MAX_QUEUE_FAMILIES] c.VkDeviceQueueCreateInfo = undefined;
      var vk_queue_family_indices_unique_array : [MAX_QUEUE_FAMILIES] u32 = undefined;
      var vk_queue_family_indices_unique_count : usize = 0;

      inline for (@typeInfo(VulkanPhysicalDevice.QueueFamilyIndices).Struct.fields) |queue_family_struct_field| {
         const new_queue_family_index = @field(vulkan_physical_device.queue_family_indices, queue_family_struct_field.name);

         var is_unique = true;
         for (vk_queue_family_indices_unique_array[0..vk_queue_family_indices_unique_count]) |existing_queue_family_index| {
            if (new_queue_family_index == existing_queue_family_index) {
               is_unique = false;
               break;
            }
         }
         if (is_unique == true) {
            vk_queue_family_indices_unique_array[vk_queue_family_indices_unique_count] = new_queue_family_index;
            vk_queue_family_indices_unique_count += 1;
         }
      }

      var vk_infos_create_queue = vk_infos_create_queue_array[0..vk_queue_family_indices_unique_count];
      var vk_queue_family_indices_unique = vk_queue_family_indices_unique_array[0..vk_queue_family_indices_unique_count];

      const vk_queue_priority : f32 = 1.0;

      for (vk_infos_create_queue, vk_queue_family_indices_unique) |*vk_info_create_queue, queue_family_index| {
         vk_info_create_queue.* = .{
            .sType               = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext               = null,
            .flags               = 0x00000000,
            .queueFamilyIndex    = queue_family_index,
            .queueCount          = 1,
            .pQueuePriorities    = &vk_queue_priority,
         };
      }

      const vk_info_create_device = c.VkDeviceCreateInfo{
         .sType                     = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
         .pNext                     = null,
         .flags                     = 0x00000000,
         .queueCreateInfoCount      = @intCast(vk_infos_create_queue.len),
         .pQueueCreateInfos         = vk_infos_create_queue.ptr,
         .enabledLayerCount         = 0,
         .ppEnabledLayerNames       = null,
         .enabledExtensionCount     = @intCast(vk_enabled_extensions.len),
         .ppEnabledExtensionNames   = vk_enabled_extensions.ptr,
         .pEnabledFeatures          = &vk_physical_device_features,
      };

      var vk_device : c.VkDevice = undefined;
      vk_result = c.vkCreateDevice(vulkan_physical_device.vk_physical_device, &vk_info_create_device, null, &vk_device);
      switch (vk_result) {
         c.VK_SUCCESS                        => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY       => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY     => return error.OutOfMemory,
         c.VK_ERROR_INITIALIZATION_FAILED    => return error.UnknownError,
         c.VK_ERROR_EXTENSION_NOT_PRESENT    => return error.MissingRequiredExtensions,
         c.VK_ERROR_FEATURE_NOT_PRESENT      => return error.MissingRequiredFeatures,
         c.VK_ERROR_TOO_MANY_OBJECTS         => return error.OutOfMemory,
         c.VK_ERROR_DEVICE_LOST              => return error.DeviceLost,
         else                                => unreachable,
      }
      errdefer c.vkDestroyDevice(vk_device, null);

      var vk_queue_graphics : c.VkQueue = undefined;
      c.vkGetDeviceQueue(vk_device, vulkan_physical_device.queue_family_indices.graphics, 0, &vk_queue_graphics);

      var vk_queue_presentation : c.VkQueue = undefined;
      c.vkGetDeviceQueue(vk_device, vulkan_physical_device.queue_family_indices.presentation, 0, &vk_queue_presentation);

      const queues = Queues{
         .graphics      = vk_queue_graphics,
         .presentation  = vk_queue_presentation,
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

const VulkanSurface = struct {
   vk_surface  : c.VkSurfaceKHR,

   pub const CreateError = error {
      OutOfMemory,
      UnknownError,
   };

   pub fn create(vk_instance : c.VkInstance, window : * const f_present.Window) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      var vk_surface : c.VkSurfaceKHR = undefined;
      vk_result = window.createVulkanSurface(vk_instance, null, &vk_surface);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => return error.UnknownError,
      }
      errdefer c.vkDestroySurfaceKHR(vk_instance, vk_surface, null);

      return @This(){.vk_surface = vk_surface};
   }

   pub fn destroy(self : @This(), vk_instance : c.VkInstance) void {
      c.vkDestroySurfaceKHR(vk_instance, self.vk_surface, null);
      return;
   }
};

const VulkanSwapchainConfiguration = struct {
   capabilities   : c.VkSurfaceCapabilitiesKHR,
   pixel_format   : c.VkSurfaceFormatKHR,
   present_mode   : c.VkPresentModeKHR,
   extent         : c.VkExtent2D,

   pub const SelectError = error {
      OutOfMemory,
      SurfaceLost,
   };

   pub fn selectBest(vk_physical_device : c.VkPhysicalDevice, vk_surface : c.VkSurfaceKHR, window : * const f_present.Window, refresh_mode : Renderer.RefreshMode) SelectError!?@This() {
      var vk_result : c.VkResult = undefined;

      var vk_surface_capabilities : c.VkSurfaceCapabilitiesKHR = undefined;
      vk_result = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vk_physical_device, vk_surface, &vk_surface_capabilities);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
         else                             => unreachable,
      }

      const pixel_format   = try _chooseSwapchainPixelFormat(vk_physical_device, vk_surface) orelse return null;
      const present_mode   = try _chooseSwapchainPresentMode(vk_physical_device, vk_surface, refresh_mode) orelse return null;

      const extent = _chooseSwapchainExtent(vk_surface_capabilities, window);

      return @This(){
         .capabilities  = vk_surface_capabilities,
         .pixel_format  = pixel_format,
         .present_mode  = present_mode,
         .extent        = extent,
      };
   }

   fn _chooseSwapchainPixelFormat(vk_physical_device : c.VkPhysicalDevice, vk_surface : c.VkSurfaceKHR) SelectError!?c.VkSurfaceFormatKHR {
      var vk_result : c.VkResult = undefined;

      const temp_allocator = VULKAN_TEMP_HEAP.allocator();

      var vk_surface_formats_count : u32 = undefined;
      vk_result = c.vkGetPhysicalDeviceSurfaceFormatsKHR(vk_physical_device, vk_surface, &vk_surface_formats_count, null);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
         else                             => unreachable,
      }

      var vk_surface_formats = std.ArrayList(c.VkSurfaceFormatKHR).init(temp_allocator);
      defer vk_surface_formats.deinit();
      try vk_surface_formats.resize(@as(usize, vk_surface_formats_count));
      vk_result = c.vkGetPhysicalDeviceSurfaceFormatsKHR(vk_physical_device, vk_surface, &vk_surface_formats_count, vk_surface_formats.items.ptr);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
         else                             => unreachable,
      }

      if (vk_surface_formats.items.len == 0) {
         return null;
      }

      var chosen_format       = vk_surface_formats.items[0];
      var chosen_format_score = _assignPixelFormatScore(chosen_format);

      for (vk_surface_formats.items[1..]) |current_format| {
         const current_format_score = _assignPixelFormatScore(current_format);
         
         if (current_format_score > chosen_format_score) {
            chosen_format = current_format;
         }
      }

      return chosen_format;
   }

   fn _assignPixelFormatScore(pixel_format : c.VkSurfaceFormatKHR) u32 {
      // This can be expanded in the future, but for now we only
      // have a preference for RGBA8888 / SRGB Nonlinear format.

      const score_format : u32 = blk: {
         switch (pixel_format.format) {
            c.VK_FORMAT_B8G8R8A8_SRGB  => break :blk 1,
            else                       => break :blk 0,
         }
      };

      const score_colorspace : u32 = blk: {
         switch (pixel_format.colorSpace) {
            c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR => break :blk 1,
            else                                => break :blk 0,
         }
      };

      return score_format + score_colorspace;
   }

   fn _chooseSwapchainPresentMode(vk_physical_device : c.VkPhysicalDevice, vk_surface : c.VkSurfaceKHR, refresh_mode : Renderer.RefreshMode) SelectError!?c.VkPresentModeKHR {
      var vk_result : c.VkResult = undefined;

      const temp_allocator = VULKAN_TEMP_HEAP.allocator();

      var vk_present_modes_count : u32 = undefined;
      vk_result = c.vkGetPhysicalDeviceSurfacePresentModesKHR(vk_physical_device, vk_surface, &vk_present_modes_count, null);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
         else                             => unreachable,
      }

      var vk_present_modes = std.ArrayList(c.VkPresentModeKHR).init(temp_allocator);
      defer vk_present_modes.deinit();
      try vk_present_modes.resize(@as(usize, vk_present_modes_count));
      vk_result = c.vkGetPhysicalDeviceSurfacePresentModesKHR(vk_physical_device, vk_surface, &vk_present_modes_count, vk_present_modes.items.ptr);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_SURFACE_LOST_KHR      => return error.SurfaceLost,
         else                             => unreachable,
      }

      const desired_present_mode = blk: {
         switch (refresh_mode) {
            .SingleBuffered   => break :blk c.VK_PRESENT_MODE_IMMEDIATE_KHR,
            .DoubleBuffered   => break :blk c.VK_PRESENT_MODE_FIFO_KHR,
            .TripleBuffered   => break :blk c.VK_PRESENT_MODE_MAILBOX_KHR,
         }
      };

      var desired_present_mode_found = false;
      for (vk_present_modes.items) |vk_present_mode| {
         if (vk_present_mode == desired_present_mode) {
            desired_present_mode_found = true;
            break;
         }
      }
      if (desired_present_mode_found == false) {
         return null;
      }

      return @intCast(desired_present_mode);
   }

   fn _chooseSwapchainExtent(vk_surface_capabilities : c.VkSurfaceCapabilitiesKHR, window : * const f_present.Window) c.VkExtent2D {
      const vk_extent = vk_surface_capabilities.currentExtent;

      if (vk_extent.width != std.math.maxInt(u32) and vk_extent.height != std.math.maxInt(u32)) {
         return vk_extent;
      }

      const vk_extent_min = vk_surface_capabilities.minImageExtent;
      const vk_extent_max = vk_surface_capabilities.maxImageExtent;

      const window_extent = window.getVulkanFramebufferExtent();

      const clamped_extent = c.VkExtent2D{
         .width   = std.math.clamp(window_extent.width, vk_extent_min.width, vk_extent_max.width),
         .height  = std.math.clamp(window_extent.height, vk_extent_min.height, vk_extent_max.height),
      };

      return clamped_extent;
   }
};

const VulkanSwapchain = struct {
   _allocator     : std.mem.Allocator,
   vk_swapchain   : c.VkSwapchainKHR,
   images         : [] c.VkImage,
   image_views    : [] c.VkImageView,

   pub const CreateError = error {
      OutOfMemory,
      DeviceLost,
      SurfaceLost,
      WindowInUse,
      UnknownError,
   };

   const _QueueFamilyInfo = struct {
      image_sharing_mode         : c.VkSharingMode,
      queue_family_index_count   : u32,
      queue_family_indices       : ? [*] const u32,
   };

   pub fn create(allocator : std.mem.Allocator, vk_device : c.VkDevice, vk_surface : c.VkSurfaceKHR, queue_family_indices : * const VulkanPhysicalDevice.QueueFamilyIndices, swapchain_configuration : * const VulkanSwapchainConfiguration) CreateError!@This() {
      var self = @This(){
         ._allocator    = allocator,
         .vk_swapchain  = @ptrCast(@alignCast(c.VK_NULL_HANDLE)),
         .images        = try allocator.alloc(c.VkImage, 0),
         .image_views   = try allocator.alloc(c.VkImageView, 0),
      };

      try self.recreate(vk_device, vk_surface, queue_family_indices, swapchain_configuration);

      return self;
   }

   pub fn recreate(self : * @This(), vk_device : c.VkDevice, vk_surface : c.VkSurfaceKHR, queue_family_indices : * const VulkanPhysicalDevice.QueueFamilyIndices, swapchain_configuration : * const VulkanSwapchainConfiguration) CreateError!void {
      var vk_result : c.VkResult = undefined;

      const vk_image_count = _chooseImageCount(swapchain_configuration.capabilities);

      const QUEUE_FAMILY_INDICES_LENGTH : u32 = @intCast(@typeInfo(VulkanPhysicalDevice.QueueFamilyIndices).Struct.fields.len);
      const vk_queue_family_array = [QUEUE_FAMILY_INDICES_LENGTH] u32 {
         queue_family_indices.graphics,
         queue_family_indices.presentation,
      };

      const vk_queue_family_info = _createQueueFamilyInfo(queue_family_indices, QUEUE_FAMILY_INDICES_LENGTH, &vk_queue_family_array);

      const vk_info_create_swapchain = c.VkSwapchainCreateInfoKHR{
         .sType                  = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
         .pNext                  = null,
         .flags                  = 0x00000000,
         .surface                = vk_surface,
         .minImageCount          = vk_image_count,
         .imageFormat            = swapchain_configuration.pixel_format.format,
         .imageColorSpace        = swapchain_configuration.pixel_format.colorSpace,
         .imageExtent            = swapchain_configuration.extent,
         .imageArrayLayers       = 1,
         .imageUsage             = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
         .imageSharingMode       = vk_queue_family_info.image_sharing_mode,
         .queueFamilyIndexCount  = vk_queue_family_info.queue_family_index_count,
         .pQueueFamilyIndices    = vk_queue_family_info.queue_family_indices,
         .preTransform           = swapchain_configuration.capabilities.currentTransform,
         .compositeAlpha         = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
         .presentMode            = swapchain_configuration.present_mode,
         .clipped                = c.VK_TRUE,
         .oldSwapchain           = self.vk_swapchain,
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
         c.VK_ERROR_INITIALIZATION_FAILED       => return error.UnknownError,
         c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT   => return error.OutOfMemory,
         else                                   => unreachable,
      }
      errdefer c.vkDestroySwapchainKHR(vk_device, vk_swapchain, null);

      var vk_images_count : u32 = undefined;
      vk_result = c.vkGetSwapchainImagesKHR(vk_device, vk_swapchain, &vk_images_count, null);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }

      var vk_images = try self._allocator.alloc(c.VkImage, @as(usize, vk_images_count));
      errdefer self._allocator.free(vk_images);
      vk_result = c.vkGetSwapchainImagesKHR(vk_device, vk_swapchain, &vk_images_count, vk_images.ptr);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_INCOMPLETE                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }

      var vk_image_views = try self._allocator.alloc(c.VkImageView, @as(usize, vk_images_count));
      errdefer self._allocator.free(vk_image_views);
      for (vk_images, vk_image_views, 0..vk_images_count) |image, *image_view, i| {
         // In the case of error in the loop, we clean up all previously image views.
         errdefer for (vk_image_views[0..i]) |previous_image_view| {
            c.vkDestroyImageView(vk_device, previous_image_view, null);
         };

         image_view.* = try _createImageView(vk_device, image, swapchain_configuration);
      }
      errdefer for (vk_image_views) |image_view| {
         c.vkDestroyImageView(vk_device, image_view, null);
      };

      for (self.image_views) |old_image_view| {
         c.vkDestroyImageView(vk_device, old_image_view, null);
      }
      self._allocator.free(self.image_views);
      self._allocator.free(self.images);
      self.vk_swapchain = vk_swapchain;
      self.images       = vk_images;
      self.image_views  = vk_image_views;
      return;
   }

   fn _chooseImageCount(vk_swapchain_capabilities : c.VkSurfaceCapabilitiesKHR) u32 {
      const count_min = vk_swapchain_capabilities.minImageCount;
      const count_max = vk_swapchain_capabilities.maxImageCount;

      switch (count_max == 0 or count_min < count_max) {
         true  => return count_min + 1,
         false => return count_min,
      }

      unreachable;
   }

   fn _createQueueFamilyInfo(queue_family_indices : * const VulkanPhysicalDevice.QueueFamilyIndices, queue_family_array_count : u32, queue_family_array_ptr : [*] const u32) _QueueFamilyInfo {
      switch (queue_family_indices.graphics != queue_family_indices.presentation) {
         true  => return .{
            .image_sharing_mode        = c.VK_SHARING_MODE_CONCURRENT,
            .queue_family_index_count  = queue_family_array_count,
            .queue_family_indices      = queue_family_array_ptr,
         },
         false => return .{
            .image_sharing_mode        = c.VK_SHARING_MODE_EXCLUSIVE,
            .queue_family_index_count  = 0,
            .queue_family_indices      = null,
         },
      }

      unreachable;
   }

   fn _createImageView(vk_device : c.VkDevice, vk_image : c.VkImage, swapchain_configuration : * const VulkanSwapchainConfiguration) CreateError!c.VkImageView {
      var vk_result : c.VkResult = undefined;

      const vk_component_mapping = c.VkComponentMapping{
         .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
         .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
         .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
         .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
      };

      const vk_subresource_range = c.VkImageSubresourceRange{
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
         .format           = swapchain_configuration.pixel_format.format,
         .components       = vk_component_mapping,
         .subresourceRange = vk_subresource_range,
      };

      var vk_image_view : c.VkImageView = undefined;
      vk_result = c.vkCreateImageView(vk_device, &vk_info_create_image_view, null, &vk_image_view);
      switch (vk_result) {
         c.VK_SUCCESS                                    => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY                   => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY                 => return error.OutOfMemory,
         c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR   => return error.UnknownError,
         else                                            => unreachable,
      }
      errdefer c.vkDestroyImageView(vk_device, vk_image_view, null);

      return vk_image_view;
   }

   pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
      for (self.image_views) |image_view| {
         c.vkDestroyImageView(vk_device, image_view, null);
      }

      self._allocator.free(self.images);
      c.vkDestroySwapchainKHR(vk_device, self.vk_swapchain, null);
      return;
   }
};

const VulkanGraphicsPipeline = struct {
   vk_render_pass       : c.VkRenderPass,
   vk_pipeline_layout   : c.VkPipelineLayout,
   vk_pipeline          : c.VkPipeline,

   pub const CreateOptions = struct {
      spv_vertex     : [] align(@alignOf(u32)) const u8,
      spv_fragment   : [] align(@alignOf(u32)) const u8,
   };

   pub const CreateError = error {
      OutOfMemory,
      InvalidShader,
   };

   pub fn create(vk_device : c.VkDevice, swapchain_configuration : * const VulkanSwapchainConfiguration, create_options : CreateOptions) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const vk_render_pass = try _createRenderPass(vk_device, swapchain_configuration);
      errdefer c.vkDestroyRenderPass(vk_device, vk_render_pass, null);

      const vk_shader_module_vertex    = try _createShaderModule(vk_device, create_options.spv_vertex);
      defer c.vkDestroyShaderModule(vk_device, vk_shader_module_vertex, null);

      const vk_shader_module_fragment  = try _createShaderModule(vk_device, create_options.spv_fragment);
      defer c.vkDestroyShaderModule(vk_device, vk_shader_module_fragment, null);

      const vk_shader_stages = [_] c.VkPipelineShaderStageCreateInfo {
         .{
            .sType               = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext               = null,
            .flags               = 0x00000000,
            .stage               = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module              = vk_shader_module_vertex,
            .pName               = "main",
            .pSpecializationInfo = null,
         },
         .{
            .sType               = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext               = null,
            .flags               = 0x00000000,
            .stage               = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module              = vk_shader_module_fragment,
            .pName               = "main",
            .pSpecializationInfo = null,
         },
      };

      const vk_dynamic_states = [_] c.VkDynamicState {
         c.VK_DYNAMIC_STATE_VIEWPORT,
         c.VK_DYNAMIC_STATE_SCISSOR,
      };

      const vk_info_create_dynamic_state = c.VkPipelineDynamicStateCreateInfo{
         .sType               = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
         .pNext               = null,
         .flags               = 0x00000000,
         .dynamicStateCount   = @intCast(vk_dynamic_states.len),
         .pDynamicStates      = &vk_dynamic_states,
      };

      const vk_info_create_vertex_input = c.VkPipelineVertexInputStateCreateInfo{
         .sType                           = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
         .pNext                           = null,
         .flags                           = 0x00000000,
         .vertexBindingDescriptionCount   = 0,
         .pVertexBindingDescriptions      = null,
         .vertexAttributeDescriptionCount = 0,
         .pVertexAttributeDescriptions    = null,
      };

      const vk_info_create_input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{
         .sType                  = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
         .pNext                  = null,
         .flags                  = 0x00000000,
         .topology               = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
         .primitiveRestartEnable = c.VK_FALSE,
      };

      const vk_info_create_viewport = c.VkPipelineViewportStateCreateInfo{
         .sType         = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
         .pNext         = null,
         .flags         = 0x00000000,
         .viewportCount = 1,
         .pViewports    = null,
         .scissorCount  = 1,
         .pScissors     = null,
      };

      const vk_info_create_rasterizer = c.VkPipelineRasterizationStateCreateInfo{
         .sType                     = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
         .pNext                     = null,
         .flags                     = 0x00000000,
         .depthClampEnable          = c.VK_FALSE,
         .rasterizerDiscardEnable   = c.VK_FALSE,
         .polygonMode               = c.VK_POLYGON_MODE_FILL,
         .cullMode                  = c.VK_CULL_MODE_BACK_BIT,
         .frontFace                 = c.VK_FRONT_FACE_CLOCKWISE,
         .depthBiasEnable           = c.VK_FALSE,
         .depthBiasConstantFactor   = 0.0,
         .depthBiasClamp            = 0.0,
         .depthBiasSlopeFactor      = 0.0,
         .lineWidth                 = 1.0,
      };

      const vk_info_create_multisample = c.VkPipelineMultisampleStateCreateInfo{
         .sType                  = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
         .pNext                  = null,
         .flags                  = 0x00000000,
         .rasterizationSamples   = c.VK_SAMPLE_COUNT_1_BIT,
         .sampleShadingEnable    = c.VK_FALSE,
         .minSampleShading       = 1.0,
         .pSampleMask            = null,
         .alphaToCoverageEnable  = c.VK_FALSE,
         .alphaToOneEnable       = c.VK_FALSE,
      };

      const vk_color_blend_attachment_states = [_] c.VkPipelineColorBlendAttachmentState {
         .{
            .blendEnable         = c.VK_FALSE,
            .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
            .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .colorBlendOp        = c.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp        = c.VK_BLEND_OP_ADD,
            .colorWriteMask      = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
         },
      };

      const vk_info_create_blend_state = c.VkPipelineColorBlendStateCreateInfo{
         .sType            = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
         .pNext            = null,
         .flags            = 0x00000000,
         .logicOpEnable    = c.VK_FALSE,
         .logicOp          = c.VK_LOGIC_OP_COPY,
         .attachmentCount  = @intCast(vk_color_blend_attachment_states.len),
         .pAttachments     = &vk_color_blend_attachment_states,
         .blendConstants   = [4] f32 {0.0, 0.0, 0.0, 0.0},
      };

      const vk_info_create_pipeline_layout = c.VkPipelineLayoutCreateInfo{
         .sType                  = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
         .pNext                  = null,
         .flags                  = 0x00000000,
         .setLayoutCount         = 0,
         .pSetLayouts            = null,
         .pushConstantRangeCount = 0,
         .pPushConstantRanges    = null,
      };

      var vk_pipeline_layout : c.VkPipelineLayout = undefined;
      vk_result = c.vkCreatePipelineLayout(vk_device, &vk_info_create_pipeline_layout, null, &vk_pipeline_layout);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }
      errdefer c.vkDestroyPipelineLayout(vk_device, vk_pipeline_layout, null);

      const vk_info_create_graphics_pipeline = c.VkGraphicsPipelineCreateInfo{
         .sType               = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
         .pNext               = null,
         .flags               = 0x00000000,
         .stageCount          = @intCast(vk_shader_stages.len),
         .pStages             = &vk_shader_stages,
         .pVertexInputState   = &vk_info_create_vertex_input,
         .pInputAssemblyState = &vk_info_create_input_assembly,
         .pTessellationState  = null,
         .pViewportState      = &vk_info_create_viewport,
         .pRasterizationState = &vk_info_create_rasterizer,
         .pMultisampleState   = &vk_info_create_multisample,
         .pDepthStencilState  = null,
         .pColorBlendState    = &vk_info_create_blend_state,
         .pDynamicState       = &vk_info_create_dynamic_state,
         .layout              = vk_pipeline_layout,
         .renderPass          = vk_render_pass,
         .subpass             = 0,
         .basePipelineHandle  = @ptrCast(@alignCast(c.VK_NULL_HANDLE)),
         .basePipelineIndex   = -1,
      };

      var vk_pipeline : c.VkPipeline = undefined;
      vk_result = c.vkCreateGraphicsPipelines(vk_device, @ptrCast(@alignCast(c.VK_NULL_HANDLE)), 1, &vk_info_create_graphics_pipeline, null, &vk_pipeline);
      switch (vk_result) {
         c.VK_SUCCESS                        => {},
         c.VK_PIPELINE_COMPILE_REQUIRED_EXT  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY       => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY     => return error.OutOfMemory,
         c.VK_ERROR_INVALID_SHADER_NV        => return error.InvalidShader,
         else                                => unreachable,
      }
      errdefer c.vkDestroyPipeline(vk_device, vk_pipeline, null);

      return @This(){
         .vk_render_pass      = vk_render_pass,
         .vk_pipeline_layout  = vk_pipeline_layout,
         .vk_pipeline         = vk_pipeline,
      };
   }

   fn _createShaderModule(vk_device : c.VkDevice, bytecode : [] align(@alignOf(u32)) const u8) CreateError!c.VkShaderModule {
      var vk_result : c.VkResult = undefined;

      const vk_info_create_shader_module = c.VkShaderModuleCreateInfo{
         .sType      = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
         .pNext      = null,
         .flags      = 0x00000000,
         .codeSize   = @intCast(bytecode.len),
         .pCode      = @ptrCast(bytecode.ptr),
      };

      var vk_shader_module : c.VkShaderModule = undefined;
      vk_result = c.vkCreateShaderModule(vk_device, &vk_info_create_shader_module, null, &vk_shader_module);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_INVALID_SHADER_NV     => return error.InvalidShader,
         else                             => unreachable,
      }
      errdefer c.vkDestroyShaderModule(vk_device, vk_shader_module, null);

      return vk_shader_module;
   }

   fn _createRenderPass(vk_device : c.VkDevice, swapchain_configuration : * const VulkanSwapchainConfiguration) CreateError!c.VkRenderPass {
      var vk_result : c.VkResult = undefined;

      const vk_attachment_color = c.VkAttachmentDescription{
         .flags            = 0x00000000,
         .format           = swapchain_configuration.pixel_format.format,
         .samples          = c.VK_SAMPLE_COUNT_1_BIT,
         .loadOp           = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
         .storeOp          = c.VK_ATTACHMENT_STORE_OP_STORE,
         .stencilLoadOp    = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
         .stencilStoreOp   = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
         .initialLayout    = c.VK_IMAGE_LAYOUT_UNDEFINED,
         .finalLayout      = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
      };

      const vk_attachment_reference_color = c.VkAttachmentReference{
         .attachment = 0,
         .layout     = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      };

      const vk_subpass_color = c.VkSubpassDescription{
         .flags                     = 0x00000000,
         .pipelineBindPoint         = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
         .inputAttachmentCount      = 0,
         .pInputAttachments         = null,
         .colorAttachmentCount      = 1,
         .pColorAttachments         = &vk_attachment_reference_color,
         .pResolveAttachments       = null,
         .pDepthStencilAttachment   = null,
         .preserveAttachmentCount   = 0,
         .pPreserveAttachments      = null,
      };

      const vk_info_create_render_pass = c.VkRenderPassCreateInfo{
         .sType            = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
         .pNext            = null,
         .flags            = 0x00000000,
         .attachmentCount  = 1,
         .pAttachments     = &vk_attachment_color,
         .subpassCount     = 1,
         .pSubpasses       = &vk_subpass_color,
         .dependencyCount  = 0,
         .pDependencies    = null,
      };

      var vk_render_pass : c.VkRenderPass = undefined;
      vk_result = c.vkCreateRenderPass(vk_device, &vk_info_create_render_pass, null, &vk_render_pass);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }
      errdefer c.vkDestroyRenderPass(vk_device, vk_render_pass, null);

      return vk_render_pass;
   }

   pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
      c.vkDestroyPipeline(vk_device, self.vk_pipeline, null);
      c.vkDestroyPipelineLayout(vk_device, self.vk_pipeline_layout, null);
      c.vkDestroyRenderPass(vk_device, self.vk_render_pass, null);
      return;
   }
};

const VulkanFramebuffers = struct {
   _allocator        : std.mem.Allocator,
   vk_framebuffers   : [] c.VkFramebuffer,

   pub const CreateError = error {
      OutOfMemory,
   };

   pub fn create(allocator : std.mem.Allocator, vk_device : c.VkDevice, vulkan_swapchain : * const VulkanSwapchain, vulkan_graphics_pipeline : * const VulkanGraphicsPipeline, swapchain_configuration : * const VulkanSwapchainConfiguration) CreateError!@This() {
      const vk_framebuffers = try allocator.alloc(c.VkFramebuffer, vulkan_swapchain.image_views.len);
      errdefer allocator.free(vk_framebuffers);

      for (vk_framebuffers, vulkan_swapchain.image_views, 0..vk_framebuffers.len) |*vk_framebuffer_dest, *vk_image_view, i| {
         errdefer for (vk_framebuffers[0..i]) |vk_framebuffer_prev| {
            c.vkDestroyFramebuffer(vk_device, vk_framebuffer_prev, null);
         };

         const vk_framebuffer = try _createFramebuffer(vk_device, vk_image_view, vulkan_graphics_pipeline, swapchain_configuration);
         errdefer c.vkDestroyFramebuffer(vk_device, vk_framebuffer, null);

         vk_framebuffer_dest.* = vk_framebuffer;
      }
      errdefer for (vk_framebuffers) |vk_framebuffer| {
         c.vkDestroyFramebuffer(vk_device, vk_framebuffer, null);
      };

      return @This(){
         ._allocator       = allocator,
         .vk_framebuffers  = vk_framebuffers,
      };
   }

   fn _createFramebuffer(vk_device : c.VkDevice, vk_image_view : * const c.VkImageView, vulkan_graphics_pipeline : * const VulkanGraphicsPipeline, swapchain_configuration : * const VulkanSwapchainConfiguration) CreateError!c.VkFramebuffer {
      var vk_result : c.VkResult = undefined;

      const vk_info_create_framebuffer = c.VkFramebufferCreateInfo{
         .sType            = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
         .pNext            = null,
         .flags            = 0x00000000,
         .renderPass       = vulkan_graphics_pipeline.vk_render_pass,
         .attachmentCount  = 1,
         .pAttachments     = vk_image_view,
         .width            = swapchain_configuration.extent.width,
         .height           = swapchain_configuration.extent.height,
         .layers           = 1,
      };

      var vk_framebuffer : c.VkFramebuffer = undefined;
      vk_result = c.vkCreateFramebuffer(vk_device, &vk_info_create_framebuffer, null, &vk_framebuffer);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }
      errdefer c.vkDestroyFramebuffer(vk_device, vk_framebuffer, null);

      return vk_framebuffer;
   }

   pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
      for (self.vk_framebuffers) |vk_framebuffer| {
         c.vkDestroyFramebuffer(vk_device, vk_framebuffer, null);
      }

      self._allocator.free(self.vk_framebuffers);

      return;
   }
};

const VulkanGraphicsCommandPool = struct {
   vk_command_pool   : c.VkCommandPool,

   pub const CreateError = error {
      OutOfMemory,
   };

   pub fn create(vk_device : c.VkDevice, queue_family_index : u32) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const vk_info_create_command_pool = c.VkCommandPoolCreateInfo{
         .sType            = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
         .pNext            = null,
         .flags            = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
         .queueFamilyIndex = queue_family_index,
      };

      var vk_command_pool : c.VkCommandPool = undefined;
      vk_result = c.vkCreateCommandPool(vk_device, &vk_info_create_command_pool, null, &vk_command_pool);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }
      errdefer c.vkDestroyCommandPool(vk_device, vk_command_pool, null);

      return @This(){
         .vk_command_pool  = vk_command_pool,
      };
   }

   pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
      c.vkDestroyCommandPool(vk_device, self.vk_command_pool, null);
      return;
   }
};

const VulkanGraphicsCommandBuffer = struct {
   vk_command_buffer : c.VkCommandBuffer,

   pub const CreateError = error {
      OutOfMemory,
   };

   pub fn create(vk_device : c.VkDevice, vk_command_pool : c.VkCommandPool) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const vk_info_allocate_command_buffer = c.VkCommandBufferAllocateInfo{
         .sType               = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
         .pNext               = null,
         .commandPool         = vk_command_pool,
         .level               = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
         .commandBufferCount  = 1,
      };

      var vk_command_buffer : c.VkCommandBuffer = undefined;
      vk_result = c.vkAllocateCommandBuffers(vk_device, &vk_info_allocate_command_buffer, &vk_command_buffer);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         else                             => unreachable,
      }

      return @This(){
         .vk_command_buffer   = vk_command_buffer,
      };
   }
};

