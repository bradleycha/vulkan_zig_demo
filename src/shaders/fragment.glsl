#version 450

layout (set = 1, binding = 0) uniform sampler2D u_sampler;

layout (location = 0) in vec4 f_color;
layout (location = 1) in vec2 f_sample;

layout (location = 0) out vec4 p_color;

void main() {
   const vec4 col_texture = texture(u_sampler, f_sample);
   const vec4 col_vertex  = f_color;
   const vec4 col_ambient = vec4(0.04, 0.09, 0.30, 1.0);
   const vec4 col_diffuse = vec4(1.00, 0.80, 0.20, 1.0);

   p_color = col_vertex * col_texture * col_ambient;
   return;
}

