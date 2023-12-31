#version 450

layout (location = 0) in vec4 v_color;
layout (location = 1) in vec2 v_sample;
layout (location = 2) in vec3 v_position;
layout (location = 3) in vec3 v_normal;

layout (location = 0) smooth out vec4 f_color;
layout (location = 1) smooth out vec2 f_sample;

layout (push_constant) uniform PushConstants {
   mat4  transform_mesh;
} push_constants;

layout (set = 0, binding = 0) uniform UniformBufferObject {
   mat4  transform_view_projection;
} uniforms;

void main() {
   vec4 v_position_world      = push_constants.transform_mesh * vec4(v_position, 1.0);
   vec4 v_position_projected  = uniforms.transform_view_projection * v_position_world;

   f_color     = v_color;
   f_sample    = v_sample;
   gl_Position = v_position_projected;
   return;
}

