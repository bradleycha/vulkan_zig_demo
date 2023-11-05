const graphics = @import("graphics");

pub const MESH_TEST_TRIANGLE = graphics.types.Mesh{
   .vertices = &.{
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 0.0,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.5,
            .v = 1.0,
         }},
         .position = .{.xyz = .{
            .x = 0.0,
            .y = -0.5,
            .z = 0.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 0.0,
            .g = 1.0,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 1.0,
            .v = 0.0,
         }},
         .position = .{.xyz = .{
            .x = 0.5,
            .y = 0.5,
            .z = 0.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 0.0,
            .g = 0.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.0,
            .v = 0.0,
         }},
         .position = .{.xyz = .{
            .x = -0.5,
            .y = 0.5,
            .z = 0.0,
         }},
      },
   },
   .indices = &.{
      0, 1, 2,
   },
};

