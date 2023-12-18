const root  = @import("index.zig");
const std   = @import("std");
const math  = @import("math");
const c     = @import("cimports");

pub const ImageSource = struct {
   data        : [] const u8,
   format      : PixelFormat,
   width       : u32,
   height      : u32,

   pub const PixelFormat = enum(c.VkFormat) {
      rgb888   = c.VK_FORMAT_R8G8B8_SRGB,
      rgba8888 = c.VK_FORMAT_R8G8B8A8_SRGB,

      pub fn bytesPerPixel(self : @This()) usize {
         switch (self) {
            .rgb888     => return 3,
            .rgba8888   => return 4,
         }

         unreachable;
      }
   };
};

