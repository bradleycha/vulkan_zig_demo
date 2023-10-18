const std         = @import("std");
const zest        = @import("zig-essential-tools");
const f_present   = @import("present.zig");
const c           = @import("cimports.zig");

const VULKAN_TEMP_HEAP = zest.mem.SingleScopeHeap(8 * 1024 * 1024);

pub const Renderer = struct {
   _allocator              : std.mem.Allocator,
   _vulkan_instance        : VulkanInstance,
   _vulkan_surface         : VulkanSurface,
   _vulkan_physical_device : VulkanPhysicalDevice,
   _vulkan_device          : VulkanDevice,

   pub const CreateOptions = struct {
      debugging   : bool,
      name        : [*:0] const u8,
      version     : u32,
   };
   
   pub const CreateError = error {
      OutOfMemory,
      VulkanInstanceCreateFailure,
      VulkanWindowSurfaceCreateFailure,
      VulkanPhysicalDevicePickFailure,
      NoVulkanPhysicalDeviceAvailable,
      VulkanDeviceCreateFailure,
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
         vulkan_instance.vk_instance, vulkan_surface.vk_surface, &VULKAN_REQUIRED_DEVICE_EXTENSIONS,
      ) catch (return error.VulkanPhysicalDevicePickFailure) orelse return error.NoVulkanPhysicalDeviceAvailable;

      zest.dbg.log.info("using device \"{s}\" for vulkan rendering", .{&vulkan_physical_device.vk_physical_device_properties.deviceName});

      const vulkan_device = VulkanDevice.create(&vulkan_physical_device) catch return error.VulkanDeviceCreateFailure;
      errdefer vulkan_device.destroy();

      return @This(){
         ._allocator                = allocator,
         ._vulkan_instance          = vulkan_instance,
         ._vulkan_surface           = vulkan_surface,
         ._vulkan_physical_device   = vulkan_physical_device,
         ._vulkan_device            = vulkan_device,
      };
   }

   pub fn destroy(self : @This()) void {
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
   vk_physical_device            : c.VkPhysicalDevice,
   vk_physical_device_properties : c.VkPhysicalDeviceProperties,
   vk_physical_device_features   : c.VkPhysicalDeviceFeatures,
   vk_required_extensions_ptr    : [*] const [*:0] const u8,
   vk_required_extensions_count  : u32,
   queue_family_indices          : QueueFamilyIndices,

   pub const QueueFamilyIndices = struct {
      graphics       : u32,
      presentation   : u32,
   };

   pub const PickError = error {
      OutOfMemory,
      UnknownError,
      SurfaceLost,
   };

   pub fn pickMostSuitable(vk_instance : c.VkInstance, vk_surface : c.VkSurfaceKHR, vk_required_extensions : [] const [*:0] const u8) PickError!?@This() {
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

   fn _parsePhysicalDevice(vk_physical_device : c.VkPhysicalDevice, vk_surface : c.VkSurfaceKHR, vk_required_extensions : [] const [*:0] const u8) PickError!?@This() {
      var vk_physical_device_properties : c.VkPhysicalDeviceProperties = undefined;
      c.vkGetPhysicalDeviceProperties(vk_physical_device, &vk_physical_device_properties);

      var vk_physical_device_features : c.VkPhysicalDeviceFeatures = undefined;
      c.vkGetPhysicalDeviceFeatures(vk_physical_device, &vk_physical_device_features);
      
      if (try _deviceSupportsExtensions(vk_physical_device, vk_required_extensions) == false) {
         return null;
      }

      const queue_family_indices = try _findQueueFamilyIndices(vk_physical_device, vk_surface) orelse return null;

      return @This(){
         .vk_physical_device              = vk_physical_device,
         .vk_physical_device_properties   = vk_physical_device_properties,
         .vk_physical_device_features     = vk_physical_device_features,
         .vk_required_extensions_ptr      = vk_required_extensions.ptr,
         .vk_required_extensions_count    = @intCast(vk_required_extensions.len),
         .queue_family_indices            = queue_family_indices,
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
            zest.dbg.log.err("missing required vulkan device extension \"{s}\"", .{required_extension_name});
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

   pub fn create(vulkan_physical_device : * const VulkanPhysicalDevice) CreateError!@This() {
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
         .enabledExtensionCount     = vulkan_physical_device.vk_required_extensions_count,
         .ppEnabledExtensionNames   = vulkan_physical_device.vk_required_extensions_ptr,
         .pEnabledFeatures          = &vk_physical_device_features,
      };

      var vk_device : c.VkDevice = undefined;
      vk_result = c.vkCreateDevice(vulkan_physical_device.vk_physical_device, &vk_info_create_device, null, &vk_device);
      switch (vk_result) {
         c.VK_SUCCESS                        => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY       => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY     => return error.OutOfMemory,
         c.VK_ERROR_INITIALIZATION_FAILED    => return error.UnknownError,
         c.VK_ERROR_EXTENSION_NOT_PRESENT    => unreachable,   // checked as part of VulkanPhysicalDevice.pickMostSuitable()
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

