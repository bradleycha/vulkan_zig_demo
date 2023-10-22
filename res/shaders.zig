const graphics = @import("graphics");
const shaders  = @import("shaders");

pub const Vertex = graphics.renderer.Renderer.ShaderBinary{
   .spv_binary = &shaders.shader_vertex_spv,
   .entrypoint = shaders.shader_vertex_entrypoint,
};

pub const Fragment = graphics.renderer.Renderer.ShaderBinary{
   .spv_binary = &shaders.shader_fragment_spv,
   .entrypoint = shaders.shader_fragment_entrypoint,
};

