const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const Instance = struct {
   vk_instance : c.VkInstance,

   pub const CreateInfo = struct {
      extensions        : [] const [*:0] const u8,
      program_name      : ? [*:0] const u8,
      engine_name       : ? [*:0] const u8,
      program_version   : u32,
      engine_version    : u32,
      debugging         : bool,
   };

   pub const CreateError = error {
      OutOfMemory,
      Unknown,
      IncompatibleDriver,
      MissingRequiredLayers,
      MissingRequiredExtensions,
   };

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      var extensions_enabled = std.ArrayList([*:0] const u8).init(allocator);
      defer extensions_enabled.deinit();

      var layers_enabled = std.ArrayList([*:0] const u8).init(allocator);
      defer layers_enabled.deinit();

      try extensions_enabled.appendSlice(create_info.extensions);
      try extensions_enabled.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);

      // TODO: Append validation layers if enabled

      try _checkExtensionsPresent(allocator, extensions_enabled.items);
      try _checkLayersPresent(allocator, layers_enabled.items);

      const vk_info_application = c.VkApplicationInfo{
         .sType               = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
         .pNext               = null,
         .pApplicationName    = create_info.program_name,
         .applicationVersion  = create_info.program_version,
         .pEngineName         = create_info.engine_name,
         .engineVersion       = create_info.engine_version,
         .apiVersion          = c.VK_API_VERSION_1_0,
      };

      const vk_info_create_instance = c.VkInstanceCreateInfo{
         .sType                     = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
         .pNext                     = null,
         .flags                     = c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
         .pApplicationInfo          = &vk_info_application,
         .enabledLayerCount         = @intCast(layers_enabled.items.len),
         .ppEnabledLayerNames       = layers_enabled.items.ptr,
         .enabledExtensionCount     = @intCast(extensions_enabled.items.len),
         .ppEnabledExtensionNames   = extensions_enabled.items.ptr,
      };

      var vk_instance : c.VkInstance = undefined;
      vk_result = c.vkCreateInstance(&vk_info_create_instance, null, &vk_instance);
      switch (vk_result) {
         c.VK_SUCCESS                     => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
         c.VK_ERROR_INITIALIZATION_FAILED => return error.Unknown,
         c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable, // checked above
         c.VK_ERROR_EXTENSION_NOT_PRESENT => unreachable, // checked above
         c.VK_ERROR_INCOMPATIBLE_DRIVER   => return error.IncompatibleDriver,
         else                             => unreachable,
      }
      errdefer c.vkDestroyInstance();

      return @This(){
         .vk_instance   = vk_instance,
      };
   }

   pub fn destroy(self : @This()) void {
      c.vkDestroyInstance(self.vk_instance, null);
      return;
   }
};

fn _checkExtensionsPresent(allocator : std.mem.Allocator, enabled_extensions : [] const [*:0] const u8) Instance.CreateError!void {
   var vk_result : c.VkResult = undefined;

   var vk_extensions_available_count : u32 = undefined;
   vk_result = c.vkEnumerateInstanceExtensionProperties(null, &vk_extensions_available_count, null);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable,
      else                             => unreachable,
   }

   var vk_extensions_available = std.ArrayList(c.VkExtensionProperties).init(allocator);
   defer vk_extensions_available.deinit();
   try vk_extensions_available.resize(@as(usize, vk_extensions_available_count));
   vk_result = c.vkEnumerateInstanceExtensionProperties(null, &vk_extensions_available_count, vk_extensions_available.items.ptr);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_LAYER_NOT_PRESENT     => unreachable,
      else                             => unreachable,
   }

   for (enabled_extensions) |enabled_extension| {
      var found = false;
      for (vk_extensions_available.items) |vk_extension_available| {
         if (c.strcmp(&vk_extension_available.extensionName, enabled_extension) == 0) {
            found = true;
            break;
         }
      }
      if (found == false) {
         return error.MissingRequiredExtensions;
      }
   }

   return;
}

fn _checkLayersPresent(allocator : std.mem.Allocator, enabled_layers : [] const [*:0] const u8) Instance.CreateError!void {
   var vk_result : c.VkResult = undefined;

   var vk_layers_available_count : u32 = undefined;
   vk_result = c.vkEnumerateInstanceLayerProperties(&vk_layers_available_count, null);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }

   var vk_layers_available = std.ArrayList(c.VkLayerProperties).init(allocator);
   defer vk_layers_available.deinit();
   try vk_layers_available.resize(@as(usize, vk_layers_available_count));
   vk_result = c.vkEnumerateInstanceLayerProperties(&vk_layers_available_count, vk_layers_available.items.ptr);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_INCOMPLETE                  => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }

   for (enabled_layers) |enabled_layer| {
      var found = false;
      for (vk_layers_available.items) |vk_layer_available| {
         if (c.strcmp(&vk_layer_available.layerName, enabled_layer) == 0) {
            found = true;
            break;
         }
      }
      if (found == false) {
         return error.MissingRequiredLayers;
      }
   }

   return;
}

