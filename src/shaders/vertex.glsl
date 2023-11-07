#version 450

layout (location = 0) in vec4 v_color;
layout (location = 1) in vec2 v_sample;
layout (location = 2) in vec3 v_position;

layout (location = 0) smooth out vec4 f_color;
layout (location = 1) smooth out vec2 f_sample;
layout (location = 2) smooth out vec3 f_position;

void main() {
   f_color     = v_color;
   f_sample    = v_sample;
   f_position  = v_position;
   gl_Position = vec4(v_position, 1.0);
   return;
}

