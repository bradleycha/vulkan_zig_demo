#version 450

layout (location = 0) smooth in vec4 f_color;
layout (location = 1) smooth in vec2 f_sample;
layout (location = 2) smooth in vec3 f_position;

layout (location = 0) out vec4 p_color;

void main() {
   float distance_from_center = distance(vec3(0.0, 0.0, 0.0), f_position);

   float vignette_factor = 1.0 - distance_from_center * 0.65;

   vec4 color_final = vec4(f_color.xyz * vignette_factor, f_color.w);

   p_color = color_final;
   return;
}

