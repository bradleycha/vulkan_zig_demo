const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const Framebuffers = struct {
   vk_framebuffers_ptr  : [*] c.VkFramebuffer,

   pub const CreateInfo = struct {
      vk_device               : c.VkDevice,
      swapchain_configuration : * const root.SwapchainConfiguration,
      swapchain               : * const root.Swapchain,
      graphics_pipeline       : * const root.GraphicsPipeline,
   };

   pub const CreateError = error {
      OutOfMemory,
   };

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      const vk_device = create_info.vk_device;

      const vk_images_count = create_info.swapchain.vk_images_count;

      const vk_image_views = create_info.swapchain.vk_image_views_ptr[0..vk_images_count];

      const vk_framebuffers = try allocator.alloc(c.VkFramebuffer, @as(usize, vk_images_count));
      errdefer allocator.free(vk_framebuffers);


      for (vk_framebuffers, vk_image_views, 0..vk_images_count) |*vk_framebuffer_dest, vk_image_view, i| {
         errdefer for (vk_framebuffers[0..i]) |vk_framebuffer_old| {
            c.vkDestroyFramebuffer(vk_device, vk_framebuffer_old, null);
         };

         const vk_framebuffer = try _createFramebuffer(create_info, vk_image_view);
         errdefer c.vkDestroyFramebuffer(vk_device, vk_framebuffer, null);

         vk_framebuffer_dest.* = vk_framebuffer;
      }
      errdefer for (vk_framebuffers) |vk_framebuffer| {
         c.vkDestroyFramebuffer(vk_device, vk_framebuffer, null);
      };

      return @This(){
         .vk_framebuffers_ptr = vk_framebuffers.ptr,
      };
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator, vk_device : c.VkDevice, swapchain : * const root.Swapchain) void {
      const vk_framebuffers = self.vk_framebuffers_ptr[0..swapchain.vk_images_count];

      for (vk_framebuffers) |vk_framebuffer| {
         c.vkDestroyFramebuffer(vk_device, vk_framebuffer, null);
      }

      allocator.free(vk_framebuffers);

      return;
   }
};

fn _createFramebuffer(create_info : * const Framebuffers.CreateInfo, vk_image_view : c.VkImageView) Framebuffers.CreateError!c.VkFramebuffer {
   var vk_result : c.VkResult = undefined;

   const vk_device            = create_info.vk_device;
   const vk_swapchain_extent  = create_info.swapchain_configuration.extent;
   const vk_render_pass       = create_info.graphics_pipeline.vk_render_pass;

   const vk_info_create_framebuffer = c.VkFramebufferCreateInfo{
      .sType            = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
      .pNext            = null,
      .flags            = 0x00000000,
      .renderPass       = vk_render_pass,
      .attachmentCount  = 1,
      .pAttachments     = &vk_image_view,
      .width            = vk_swapchain_extent.width,
      .height           = vk_swapchain_extent.height,
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

