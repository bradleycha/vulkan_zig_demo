// We have to do this in order to share C-import types across files.
pub usingnamespace @cImport({
   @cInclude("string.h");
   @cInclude("vulkan/vulkan.h");
   @cInclude("GLFW/glfw3.h");
});

