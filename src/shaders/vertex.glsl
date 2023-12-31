#version 450

layout (location = 0) in vec4 v_color;
layout (location = 1) in vec2 v_sample;
layout (location = 2) in vec3 v_position;
layout (location = 3) in vec3 v_normal;

layout (location = 0) smooth out vec4 f_color;
layout (location = 1) smooth out vec2 f_sample;
layout (location = 2) smooth out vec3 f_normal;

layout (push_constant) uniform PushConstants {
   mat4  transform_mesh;
} push_constants;

layout (set = 0, binding = 0) uniform UniformBufferObject {
   mat4  transform_view;
   mat4  transform_project;
} uniforms;

void main() {
   vec4 v_position_world      = push_constants.transform_mesh * vec4(v_position, 1.0);
   vec4 v_normal_world        = push_constants.transform_mesh * vec4(v_normal, 1.0);
   vec4 v_position_camera     = uniforms.transform_view * v_position_world;
   vec4 v_position_projected  = uniforms.transform_project * v_position_camera;

   f_color     = v_color;
   f_sample    = v_sample;
   f_normal    = vec3(v_normal_world.xyz);
   gl_Position = v_position_projected;
   return;
}

