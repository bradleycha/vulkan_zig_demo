const std      = @import("std");
const builtin  = @import("builtin");
const options  = @import("options");

// We create a seperate module to lump all of our C includes together so we can
// share C types across modules.  For example, writing a function with the
// window presentation API to return a Vulkan surface, which can be used from
// within the rendering API.  Using seperate cimports will cause these types
// to technically be different and create annoying compile errors.

pub usingnamespace @cImport({
   @cInclude("stdlib.h");
   @cInclude("string.h");

   switch (options.present_backend) {
      .wayland => {
         @cInclude("wayland-client.h");
         @cInclude("xkbcommon/xkbcommon.h");
         @cInclude("xdg-shell.h");
         @cInclude("pointer-constraints.h");
         @cInclude("relative-pointer.h");
         @cDefine("VK_USE_PLATFORM_WAYLAND_KHR", {});
      },
      .xcb     => {
         @cInclude("xcb/xcb.h");
         @cInclude("xcb/xproto.h");
         @cDefine("VK_USE_PLATFORM_XCB_KHR", {});
      },
   }

   @cInclude("vulkan/vulkan.h");
});

