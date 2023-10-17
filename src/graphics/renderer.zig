const std         = @import("std");
const zest        = @import("zig-essential-tools");
const f_present   = @import("present.zig");
const c           = @cImport({
   @cInclude("string.h");
   @cInclude("vulkan/vulkan.h");
   @cInclude("GLFW/glfw3.h");
});

const VULKAN_TEMP_HEAP = zest.mem.SingleScopeHeap(8 * 1024 * 1024);

pub const Renderer = struct {
   _allocator              : std.mem.Allocator,
   _vulkan_instance        : VulkanInstance,
   _vulkan_physical_device : VulkanPhysicalDevice,

   pub const CreateOptions = struct {
      debugging   : bool,
      name        : [*:0] const u8,
      version     : u32,
   };
   
   pub const CreateError = error {
      OutOfMemory,
      VulkanInstanceCreateFailure,
      VulkanPhysicalDevicePickFailure,
      NoVulkanPhysicalDeviceAvailable,
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

      const vulkan_physical_device = VulkanPhysicalDevice.pickMostSuitable(
         vulkan_instance.vk_instance,
      ) catch (return error.VulkanPhysicalDevicePickFailure) orelse return error.NoVulkanPhysicalDeviceAvailable;

      _ = window;

      return @This(){
         ._allocator                = allocator,
         ._vulkan_instance          = vulkan_instance,
         ._vulkan_physical_device   = vulkan_physical_device,
      };
   }

   pub fn destroy(self : @This()) void {
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
            zest.dbg.log.err("missing required vulkan validation layer \"{s}\"", .{enabled_layer_name});
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
            zest.dbg.log.err("missing required vulkan extension \"{s}\"", .{enabled_extension_name});
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
   vk_physical_device   : c.VkPhysicalDevice,

   pub const PickError = error {
      OutOfMemory,
      UnknownError,
   };

   pub fn pickMostSuitable(vk_instance : c.VkInstance) PickError!?@This() {
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
            vk_instance,
            vk_physical_device,
         ) orelse continue;

         if (physical_device_chosen == null) {
            physical_device_chosen = physical_device_new;
            continue;
         }

         const score_old = (physical_device_chosen orelse unreachable)._assignScore(vk_instance);
         const score_new = physical_device_new._assignScore(vk_instance);

         if (score_new > score_old) {
            physical_device_chosen = physical_device_new;
         }
      }

      return physical_device_chosen;
   }

   fn _parsePhysicalDevice(vk_instance : c.VkInstance, vk_physical_device : c.VkPhysicalDevice) PickError!?@This() {
      _ = vk_instance;
      _ = vk_physical_device;
      unreachable;
   }

   fn _assignScore(self : * const @This(), vk_instance : c.VkInstance) u32 {
      _ = self;
      _ = vk_instance;
      unreachable;
   }
};

