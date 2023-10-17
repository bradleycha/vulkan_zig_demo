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
   _allocator        : std.mem.Allocator,
   _vulkan_instance  : VulkanInstance,

   pub const CreateOptions = struct {
      debugging   : bool,
      name        : [*:0] const u8,
      version     : u32,
   };
   
   pub const CreateError = error {
      OutOfMemory,
      VulkanInstanceCreateFailure,
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

      _ = window;

      return @This(){
         ._allocator       = allocator,
         ._vulkan_instance = vulkan_instance,
      };
   }

   pub fn destroy(self : @This()) void {
      self._vulkan_instance.destroy();
      return;
   }
};

const VulkanInstance = struct {
   vk_instance : c.VkInstance,

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
         .pNext                     = null,
         .flags                     = 0x00000000 | c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
         .pApplicationInfo          = &vk_info_application,
         .enabledLayerCount         = @intCast(enabled_layers.items.len),
         .ppEnabledLayerNames       = enabled_layers.items.ptr,
         .enabledExtensionCount     = @intCast(enabled_extensions.items.len),
         .ppEnabledExtensionNames   = enabled_extensions.items.ptr,
      };

      // TODO: Debug messenger

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

      return @This(){.vk_instance = vk_instance};
   }

   pub fn destroy(self : @This()) void {
      c.vkDestroyInstance(self.vk_instance, null);
      return;
   }
};

