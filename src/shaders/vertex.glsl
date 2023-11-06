#version 450

layout (location = 0) in vec4 v_color;
layout (location = 1) in vec2 v_sample;
layout (location = 2) in vec3 v_position;

layout (location = 0) smooth out vec4 f_color;
layout (location = 1) smooth out vec2 f_sample;
layout (location = 2) smooth out vec3 f_position;

layout (push_constant) uniform PushConstants {
   mat4 mesh_transform;
} push_constants;

void main() {
   vec4 position_final = push_constants.mesh_transform * vec4(v_position, 1.0);

   f_color     = v_color;
   f_sample    = v_sample;
   f_position  = vec3(position_final.xyz);
   gl_Position = position_final;
   return;
}

