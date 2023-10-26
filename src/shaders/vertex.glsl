#version 450

layout (location = 0) in vec4 v_color;
layout (location = 1) in vec2 v_sample;
layout (location = 2) in vec3 v_position;

layout (location = 0) smooth out vec4 f_color;
layout (location = 1) smooth out vec2 f_sample;
layout (location = 2) smooth out vec3 f_position;

layout (binding = 0) uniform UniformBufferObject {
   vec2  translation;
   float aspect_correction;
} ubo;

void main() {
   vec3 position_final = v_position + vec3(ubo.translation.xy, 0.0);

   gl_Position = vec4(position_final.x * ubo.aspect_correction, position_final.yz, 1.0);
   f_color     = v_color;
   f_sample    = v_sample;
   f_position  = position_final;
   return;
}

