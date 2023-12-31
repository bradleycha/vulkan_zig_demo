#version 450

const vec3 SUN_ANGLE = vec3(1.0, -0.05, 1.0);

layout (set = 1, binding = 0) uniform sampler2D u_sampler;

layout (location = 0) in vec4 f_color;
layout (location = 1) in vec2 f_sample;
layout (location = 2) in vec3 f_normal;

layout (location = 0) out vec4 p_color;

void main() {
   const vec4 col_texture = texture(u_sampler, f_sample);
   const vec4 col_vertex  = f_color;
   const vec4 col_ambient = vec4(0.30, 0.40, 0.45, 1.0);
   const vec4 col_diffuse = vec4(1.00, 0.80, 0.40, 1.0);

   const float lighting_face_angle = dot(normalize(SUN_ANGLE), normalize(f_normal));
   const float lighting_mix_factor = lighting_face_angle * 0.5 + 0.5;

   const vec4 col_lighting = mix(col_ambient, col_diffuse, lighting_mix_factor);

   p_color = col_vertex * col_texture * col_lighting;
   return;
}

