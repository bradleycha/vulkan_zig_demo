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
   const vec3 normal_sun_unit = normalize(uniforms.normal_sun);

   const float lighting_sun_face_angle = dot(normal_sun_unit, normalize(f_normal_world));
   const float lighting_cam_face_angle = dot(normal_sun_unit, normalize(f_normal_camera));

   const float lighting_sun_mix_factor = lighting_sun_face_angle * 0.5 + 0.5;
   const float lighting_cam_mix_factor = lighting_cam_face_angle * 0.5 + 0.5;

   const vec4 color_vertex          = f_color;
   const vec4 color_texture         = texture(u_sampler, f_sample);
   const vec4 color_lighting_sun    = mix(uniforms.color_ambient, uniforms.color_sun, lighting_sun_mix_factor);
   const vec4 color_lighting_depth  = mix(uniforms.color_depth, vec4(1.0, 1.0, 1.0, 1.0), lighting_cam_mix_factor);

   p_color = color_vertex * color_texture * color_lighting_sun * color_lighting_depth;
   return;
}

