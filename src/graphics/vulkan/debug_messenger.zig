const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const DebugMessenger = struct {
   vk_debug_messenger   : c.VkDebugUtilsMessengerEXT,

   pub const VK_INFO_CREATE_DEBUG_UTILS_MESSENGER = c.VkDebugUtilsMessengerCreateInfoEXT{
      .sType            = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
      .pNext            = null,
      .flags            = 0x00000000,
      .messageSeverity  = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
      .messageType      = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
      .pfnUserCallback  = _vkDebugCallback,
      .pUserData        = null,
   };

   pub const CreateError = error {
      OutOfMemory,
      MissingRequiredFunctions,
   };

   pub fn create(vk_instance : c.VkInstance) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      if (_VulkanFunctions.findFunctions(vk_instance) == false) {
         return error.MissingRequiredFunctions;
      }
      
      var vk_debug_messenger : c.VkDebugUtilsMessengerEXT = undefined;
      vk_result = _VulkanFunctions.vkCreateDebugUtilsMessengerEXT(vk_instance, &VK_INFO_CREATE_DEBUG_UTILS_MESSENGER, null, &vk_debug_messenger);
      switch (vk_result) {
         c.VK_SUCCESS                  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY => return error.OutOfMemory,
         else                          => unreachable,
      }
      errdefer _VulkanFunctions.vkDestroyDebugUtilsMessengerEXT(vk_instance, vk_debug_messenger, null);

      return @This(){
         .vk_debug_messenger = vk_debug_messenger,
      };
   }

   pub fn destroy(self : @This(), vk_instance : c.VkInstance) void {
      _VulkanFunctions.vkDestroyDebugUtilsMessengerEXT(vk_instance, self.vk_debug_messenger, null);
      return;
   }
};

const _VulkanFunctions = struct {
   var pfn_vk_create_debug_utils_messenger_ext  : c.PFN_vkCreateDebugUtilsMessengerEXT    = null;
   var pfn_vk_destroy_debug_utils_messenger_ext : c.PFN_vkDestroyDebugUtilsMessengerEXT   = null;

   pub fn findFunctions(vk_instance : c.VkInstance) bool {
      const pfn_raw_create    = c.vkGetInstanceProcAddr(vk_instance, "vkCreateDebugUtilsMessengerEXT")   orelse return false;
      const pfn_raw_destroy   = c.vkGetInstanceProcAddr(vk_instance, "vkDestroyDebugUtilsMessengerEXT")  orelse return false;

      pfn_vk_create_debug_utils_messenger_ext   = @ptrCast(@alignCast(pfn_raw_create));
      pfn_vk_destroy_debug_utils_messenger_ext  = @ptrCast(@alignCast(pfn_raw_destroy));

      return true;
   }

   pub fn vkCreateDebugUtilsMessengerEXT(instance : c.VkInstance, pCreateInfo : ? * const c.VkDebugUtilsMessengerCreateInfoEXT, pAllocator : ? * const c.VkAllocationCallbacks, pDebugMessenger : ? * c.VkDebugUtilsMessengerEXT) callconv(.C) c.VkResult {
      return (pfn_vk_create_debug_utils_messenger_ext orelse unreachable)(instance, pCreateInfo, pAllocator, pDebugMessenger);
   }

   pub fn vkDestroyDebugUtilsMessengerEXT(instance : c.VkInstance, debugMessenger : c.VkDebugUtilsMessengerEXT, pAllocator : ? * const c.VkAllocationCallbacks) callconv(.C) void {
      return (pfn_vk_destroy_debug_utils_messenger_ext orelse unreachable)(instance, debugMessenger, pAllocator);
   }
};

fn _vkDebugCallback(message_severity : c.VkDebugUtilsMessageSeverityFlagBitsEXT, message_type : c.VkDebugUtilsMessageTypeFlagsEXT, p_callback_data : ? * const c.VkDebugUtilsMessengerCallbackDataEXT, _ : ? * anyopaque) callconv(.C) c.VkBool32 {
   const callback_data = p_callback_data orelse unreachable;

   const s_prefix = "vulkan";
   const s_type = blk: {
      switch (message_type) {
         c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT      => break :blk "general",
         c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT   => break :blk "validation",
         c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT  => break :blk "performance",
         else                                               => unreachable,
      }
   };
   const s_msg = callback_data.pMessage orelse unreachable;

   const fmt = "{s} {s}: {s}";
   const args = .{s_prefix, s_type, s_msg};

   switch (message_severity) {
      c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
      c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT => {
         std.log.info(fmt, args);
      },
      c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT => {
         std.log.warn(fmt, args);
      },
      c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT => {
         std.log.err(fmt, args);
      },
      else => unreachable,
   }

   return c.VK_FALSE;
}

