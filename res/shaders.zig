const shaders  = @import("shaders");
const graphics = @import("graphics");

pub const VERTEX = graphics.ShaderSource{
   .bytecode   = &shaders.vertex.bytecode,
   .entrypoint = shaders.vertex.entrypoint,
};

pub const FRAGMENT = graphics.ShaderSource{
   .bytecode   = &shaders.fragment.bytecode,
   .entrypoint = shaders.fragment.entrypoint,
};

