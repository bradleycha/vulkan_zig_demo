const shaders  = @import("shaders");
const graphics = @import("graphics");

pub const VERTEX = graphics.ShaderModule{
   .stage      = .vertex,
   .bytecode   = &shaders.vertex.bytecode,
   .entrypoint = &shaders.vertex.entrypoint,
};

pub const FRAGMENT = graphics.ShaderModule{
   .stage      = .fragment,
   .bytecode   = &shaders.fragment.bytecode,
   .entrypoint = &shaders.fragment.entrypoint,
};

