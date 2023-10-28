const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const Instance = struct {
   vk_instance       : c.VkInstance,
   debug_messenger   : ? root.DebugMessenger,

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
      MissingRequiredFunctions,
   };

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      var extensions_enabled = std.ArrayList([*:0] const u8).init(allocator);
      defer extensions_enabled.deinit();

      var layers_enabled = std.ArrayList([*:0] const u8).init(allocator);
      defer layers_enabled.deinit();

      try extensions_enabled.appendSlice(create_info.extensions);
      try extensions_enabled.appendSlice(&.{
         c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
      });

      if (create_info.debugging == true) {
         try extensions_enabled.appendSlice(&.{
            c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
         });

         try layers_enabled.appendSlice(&.{
            "VK_LAYER_KHRONOS_validation",
         });
      }

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

      var vk_info_create_debug_utils_messenger : ? * const c.VkDebugUtilsMessengerCreateInfoEXT = blk: {
         if (create_info.debugging == true) {
            break :blk &root.DebugMessenger.VK_INFO_CREATE_DEBUG_UTILS_MESSENGER;
         } else {
            break :blk null;
         }
      };

      const vk_info_create_instance = c.VkInstanceCreateInfo{
         .sType                     = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
         .pNext                     = vk_info_create_debug_utils_messenger,
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
      errdefer c.vkDestroyInstance(vk_instance, null);

      const debug_messenger : ? root.DebugMessenger = blk: {
         if (create_info.debugging == true) {
            break :blk try root.DebugMessenger.create(vk_instance);
         } else {
            break :blk null;
         }
      };
      errdefer if (debug_messenger) |debug_messenger_unwrapped| {
         debug_messenger_unwrapped.destroy(vk_instance);
      };

      return @This(){
         .vk_instance      = vk_instance,
         .debug_messenger  = debug_messenger,
      };
   }

   pub fn destroy(self : @This()) void {
      if (self.debug_messenger) |*debug_messenger| {
         debug_messenger.destroy(self.vk_instance);
      }

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

   var everything_found = true;
   for (enabled_extensions) |enabled_extension| {
      var found = false;
      for (vk_extensions_available.items) |vk_extension_available| {
         if (c.strcmp(&vk_extension_available.extensionName, enabled_extension) == 0) {
            found = true;
            break;
         }
      }
      if (found == false) {
         everything_found = false;
         std.log.err("missing required vulkan instance extension \"{s}\"", .{enabled_extension});
      }
   }

   if (everything_found == false) {
      return error.MissingRequiredExtensions;
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

   var everything_found = true;
   for (enabled_layers) |enabled_layer| {
      var found = false;
      for (vk_layers_available.items) |vk_layer_available| {
         if (c.strcmp(&vk_layer_available.layerName, enabled_layer) == 0) {
            found = true;
            break;
         }
      }
      if (found == false) {
         everything_found = false;
         std.log.err("missing required vulkan instance layer \"{s}\"", .{enabled_layer});
      }
   }

   if (everything_found == false) {
      return error.MissingRequiredLayers;
   }

   return;
}

