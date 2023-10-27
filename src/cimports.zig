// We make all cimports bundled inside a single module so we can share C types
// between modules.  For example, defining a function to create a Vulkan
// surface which returns a VkResult, while then also using that function in the
// renderer module.  Making seperate cimports across modules will break because
// as far as the Zig compiler sees, they are technically different types.

// We also further divide imports into different libraries so the Zig
// compiler's (overzeallous) lazy evaluation allows cleanly including header
// files as usual without messy conditional compilation.

pub const wayland = @cImport({
   @cInclude("wayland-client.h");
   @cInclude("xdg-shell.h");
});

