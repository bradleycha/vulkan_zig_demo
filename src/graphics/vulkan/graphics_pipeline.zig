const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const ShaderSource = struct {
   bytecode          : [] align(@sizeOf(u32)) const u8,
   entrypoint        : [*:0] const u8,
};

pub const ClearColorTag = enum {
   none,
   color,
};

pub const ClearColor = union(ClearColorTag) {
   none  : void,
   color : root.types.Color.Rgba(f32),
};

pub const GraphicsPipeline = struct {
   pub const CreateInfo = struct {
      vk_device               : c.VkDevice,
      swapchain_configuration : * const root.SwapchainConfiguration,
      shader_vertex           : ShaderSource,
      shader_fragment         : ShaderSource,
      clear_color             : ClearColor,
   };

   pub const CreateError = error {
      OutOfMemory,
      InvalidShader,
   };

   pub fn create(allocator : std.mem.Allocator, create_info : * const CreateInfo) CreateError!@This() {
      _ = allocator;
      _ = create_info;
      unreachable;
   }

   pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
      _ = self;
      _ = vk_device;
      unreachable;
   }
};

