#version 450

layout (location = 0) smooth in vec4 f_color;
layout (location = 1) smooth in vec2 f_sample;

layout (location = 0) out vec4 p_color;

void main() {
   p_color = f_color;
   return;
}

