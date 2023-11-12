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
            .x =  0.0,
            .y =  0.5,
            .z =  0.0,
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
            .x =  0.5,
            .y = -0.5,
            .z =  0.0,
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
            .y = -0.5,
            .z =  0.0,
         }},
      },
   },
   .indices = &.{
      0, 1, 2,
   },
};

pub const MESH_TEST_OCTAGON = graphics.types.Mesh{
   .vertices = &.{
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.5,
            .v = 0.5,
         }},
         .position = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z =  0.0,
         }}
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 0.0,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.7071067,
            .v = 1.0000000,
         }},
         .position = .{.xyz = .{
            .x =  0.2071067,
            .y =  0.5000000,
            .z =  0.0,
         }}
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 0.5,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 1.0000000,
            .v = 0.2071067,
         }},
         .position = .{.xyz = .{
            .x =  0.5000000,
            .y =  0.2071067,
            .z =  0.0,
         }}
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 1.0000000,
            .v = 0.2928933,
         }},
         .position = .{.xyz = .{
            .x =  0.5000000,
            .y = -0.2071067,
            .z =  0.0,
         }}
      },
      .{
         .color = .{.channels = .{
            .r = 0.5,
            .g = 1.0,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.7071067,
            .v = 0.0000000,
         }},
         .position = .{.xyz = .{
            .x =  0.2071067,
            .y = -0.5000000,
            .z =  0.0,
         }}
      },
      .{
         .color = .{.channels = .{
            .r = 0.0,
            .g = 1.0,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.2928933,
            .v = 0.0000000,
         }},
         .position = .{.xyz = .{
            .x = -0.2071067,
            .y = -0.5000000,
            .z =  0.0,
         }}
      },
      .{
         .color = .{.channels = .{
            .r = 0.0,
            .g = 0.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.0000000,
            .v = 0.2928933,
         }},
         .position = .{.xyz = .{
            .x = -0.5000000,
            .y = -0.2071067,
            .z =  0.0,
         }}
      },
      .{
         .color = .{.channels = .{
            .r = 0.5,
            .g = 0.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.0000000,
            .v = 0.7071067,
         }},
         .position = .{.xyz = .{
            .x = -0.5000000,
            .y =  0.2071067,
            .z =  0.0,
         }}
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 0.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.2928933,
            .v = 1.0000000,
         }},
         .position = .{.xyz = .{
            .x = -0.2071067,
            .y =  0.5000000,
            .z =  0.0,
         }}
      },
   },
   .indices = &.{
      0, 1, 2,
      0, 2, 3,
      0, 3, 4,
      0, 4, 5,
      0, 5, 6,
      0, 6, 7,
      0, 7, 8,
      0, 8, 1,
   },
};

pub const MESH_TEST_CUBE = graphics.types.Mesh{
   .vertices = &.{
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 0.0,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 1.0,
            .v = 1.0,
         }},
         .position = .{.xyz = .{
            .x =  0.5,
            .y = -0.5,
            .z = -0.5,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 0.5,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 1.0,
            .v = 0.0,
         }},
         .position = .{.xyz = .{
            .x =  0.5,
            .y =  0.5,
            .z = -0.5,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.0,
            .v = 0.0,
         }},
         .position = .{.xyz = .{
            .x = -0.5,
            .y =  0.5,
            .z = -0.5,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 0.5,
            .g = 1.0,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.0,
            .v = 1.0,
         }},
         .position = .{.xyz = .{
            .x = -0.5,
            .y = -0.5,
            .z = -0.5,
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
            .u = 0.0,
            .v = 1.0,
         }},
         .position = .{.xyz = .{
            .x =  0.5,
            .y = -0.5,
            .z =  0.5,
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
            .x =  0.5,
            .y =  0.5,
            .z =  0.5,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 0.5,
            .g = 0.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 1.0,
            .v = 0.0,
         }},
         .position = .{.xyz = .{
            .x = -0.5,
            .y =  0.5,
            .z =  0.5,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 0.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 1.0,
            .v = 1.0,
         }},
         .position = .{.xyz = .{
            .x = -0.5,
            .y = -0.5,
            .z =  0.5,
         }},
      },
   },
   .indices = &.{
      0, 1, 3,
      1, 2, 3,
      3, 2, 7,
      2, 6, 7,
      7, 6, 4,
      6, 5, 4,
      4, 5, 0,
      5, 1, 0,
      4, 0, 7,
      0, 3, 7,
      1, 5, 6,
      1, 6, 2,
   },
};

pub const MESH_TEST_PYRAMID  = graphics.types.Mesh{
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
            .x =  0.0,
            .y =  0.5,
            .z =  0.0,
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
            .x =  0.5,
            .y = -0.5,
            .z =  0.5,
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
            .x =  0.5,
            .y = -0.5,
            .z = -0.5,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 0.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 1.0,
            .v = 0.0,
         }},
         .position = .{.xyz = .{
            .x = -0.5,
            .y = -0.5,
            .z = -0.5,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 0.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.0,
            .v = 0.0,
         }},
         .position = .{.xyz = .{
            .x = -0.5,
            .y = -0.5,
            .z =  0.5,
         }},
      },
   },
   .indices = &.{
      0, 2, 1,
      0, 3, 2,
      0, 4, 3,
      0, 1, 4,
      1, 2, 4,
      4, 2, 3,
   },
};

