#version 450

layout (set = 0, binding = 1) uniform UniformBufferObject {
   vec4  color_ambient;
   vec4  color_sun;
   vec4  color_depth;
   vec3  normal_sun;
} uniforms;

layout (set = 1, binding = 0) uniform sampler2D u_sampler;

layout (location = 0) in vec4 f_color;
layout (location = 1) in vec2 f_sample;
layout (location = 2) in vec3 f_normal_world;
layout (location = 3) in vec3 f_normal_camera;

layout (location = 0) out vec4 p_color;

void main() {
   const vec4 color_vertex    = f_color;
   const vec4 color_texture   = texture(u_sampler, f_sample);

   p_color = color_vertex * color_texture;
   return;
}

