#version 450

vec2 v_position[3] = vec2[](
   vec2( 0.0, -0.5),
   vec2 (0.5,  0.5),
   vec2(-0.5,  0.5)
);

vec4 v_color[3] = vec4[](
   vec4(1.0, 0.0, 0.0, 1.0),
   vec4(0.0, 1.0, 0.0, 1.0),
   vec4(0.0, 0.0, 1.0, 1.0)
);

layout (location = 0) out vec4 f_color;

void main() {
   gl_Position = vec4(v_position[gl_VertexIndex], 0.0, 1.0);
   f_color     = v_color[gl_VertexIndex];
   return;
}

