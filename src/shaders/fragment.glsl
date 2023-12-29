#version 450

layout (set = 1, binding = 0) uniform sampler2D u_sampler;

layout (location = 0) in vec4 f_color;
layout (location = 1) in vec2 f_sample;

layout (location = 0) out vec4 p_color;

void main() {
   p_color = texture(u_sampler, f_sample) * f_color;
   return;
}

