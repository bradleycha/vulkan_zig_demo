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
   const float angle_from_sun       = dot(normalize(f_normal_world), normalize(uniforms.normal_sun));
   const float diffuse_mix_factor   = clamp(angle_from_sun * 0.75 + 0.25, 0.0, 1.0);

   const float angle_from_camera = dot(normalize(f_normal_camera), normalize(vec3(0.0, 0.0, 1.0)));
   const float depth_mix_factor  = clamp(angle_from_camera * 0.5 + 0.5, 0.0, 1.0);

   const vec4 color_vertex    = f_color;
   const vec4 color_texture   = texture(u_sampler, f_sample);
   const vec4 color_light     = mix(uniforms.color_ambient, uniforms.color_sun, diffuse_mix_factor);
   const vec4 color_depth     = mix(uniforms.color_depth, vec4(1.0), depth_mix_factor);

   p_color = color_vertex * color_texture * color_light * color_depth;
   return;
}

