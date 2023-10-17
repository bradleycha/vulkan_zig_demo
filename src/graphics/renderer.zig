const std         = @import("std");
const f_present   = @import("present.zig");
const c           = @cImport({
   @cInclude("vulkan/vulkan.h");
   @cInclude("GLFW/glfw3.h");
});

pub const Renderer = struct {
   pub const CreateOptions = struct {

   };
   
   pub const CreateError = error {

   };

   pub fn create(window : * const f_present.Window, create_options : CreateOptions) CreateError!@This() {
      _ = window;
      _ = create_options;
      unreachable;
   }

   pub fn destroy(self : @This()) void {
      _ = self;
      unreachable;
   }
};

