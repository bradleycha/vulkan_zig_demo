const graphics = @import("graphics");

pub const TEST_TRIANGLE = graphics.types.Mesh{
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
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
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
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
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
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
         }},
      },
   },
   .indices = &.{
      0, 1, 2,
   },
};

pub const TEST_OCTAGON = graphics.types.Mesh{
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
         }},
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
         }},
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
         }},
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
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
            .u = 1.0000000,
            .v = 0.2071067,
         }},
         .position = .{.xyz = .{
            .x =  0.5000000,
            .y =  0.2071067,
            .z =  0.0,
         }},
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
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
            .u = 1.0000000,
            .v = 0.2928933,
         }},
         .position = .{.xyz = .{
            .x =  0.5000000,
            .y = -0.2071067,
            .z =  0.0,
         }},
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
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
            .u = 0.7071067,
            .v = 0.0000000,
         }},
         .position = .{.xyz = .{
            .x =  0.2071067,
            .y = -0.5000000,
            .z =  0.0,
         }},
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
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
            .u = 0.2928933,
            .v = 0.0000000,
         }},
         .position = .{.xyz = .{
            .x = -0.2071067,
            .y = -0.5000000,
            .z =  0.0,
         }},
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
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
            .u = 0.0000000,
            .v = 0.2928933,
         }},
         .position = .{.xyz = .{
            .x = -0.5000000,
            .y = -0.2071067,
            .z =  0.0,
         }},
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
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
            .u = 0.0000000,
            .v = 0.7071067,
         }},
         .position = .{.xyz = .{
            .x = -0.5000000,
            .y =  0.2071067,
            .z =  0.0,
         }},
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
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
            .u = 0.2928933,
            .v = 1.0000000,
         }},
         .position = .{.xyz = .{
            .x = -0.2071067,
            .y =  0.5000000,
            .z =  0.0,
         }},
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  0.0,
            .z = -1.0,
         }},
      },
   },
   .indices = &.{
      1, 2, 0,
      3,
      4,
      0xFFFF,
      4, 5, 0,
      6,
      7,
      0xFFFF,
      7, 8, 0,
      1,
   },
};

pub const TEST_CUBE = graphics.types.Mesh{
   .vertices = &.{
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
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
         .normal = .{.xyz = .{
            .x =  1.0,
            .y = -1.0,
            .z = -1.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
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
         .normal = .{.xyz = .{
            .x =  1.0,
            .y =  1.0,
            .z = -1.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
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
         .normal = .{.xyz = .{
            .x = -1.0,
            .y =  1.0,
            .z = -1.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
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
         .normal = .{.xyz = .{
            .x = -1.0,
            .y = -1.0,
            .z = -1.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
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
         .normal = .{.xyz = .{
            .x =  1.0,
            .y = -1.0,
            .z =  1.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
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
         .normal = .{.xyz = .{
            .x =  1.0,
            .y =  1.0,
            .z =  1.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
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
         .normal = .{.xyz = .{
            .x = -1.0,
            .y =  1.0,
            .z =  1.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
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
         .normal = .{.xyz = .{
            .x = -1.0,
            .y = -1.0,
            .z =  1.0,
         }},
      },
   },
   .indices = &.{
      0, 1, 3,
      2,
      7,
      6,
      4,
      5,
      1,
      6,
      2,
      0xFFFF,
      1, 0, 4,
      3,
      7,
   },
};

pub const TEST_PYRAMID  = graphics.types.Mesh{
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
            .v = 1.0,
         }},
         .position = .{.xyz = .{
            .x =  0.0,
            .y =  0.5,
            .z =  0.0,
         }},
         .normal = .{.xyz = .{
            .x =  0.0,
            .y =  1.0,
            .z =  0.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
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
         .normal = .{.xyz = .{
            .x =  1.0,
            .y = -1.0,
            .z =  1.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
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
         .normal = .{.xyz = .{
            .x =  1.0,
            .y = -1.0,
            .z = -1.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
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
         .normal = .{.xyz = .{
            .x = -1.0,
            .y = -1.0,
            .z = -1.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
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
            .z =  0.5,
         }},
         .normal = .{.xyz = .{
            .x = -1.0,
            .y = -1.0,
            .z =  1.0,
         }},
      },
   },
   .indices = &.{
      2, 3, 4,
      0,
      1,
      2,
      4,
      0xFFFF,
      0, 3, 2,
   },
};

pub const TEST_PLANE  = graphics.types.Mesh{
   .vertices = &.{
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.0,
            .v = 0.0,
         }},
         .position = .{.xyz = .{
            .x = -0.5,
            .y =  0.0,
            .z = -0.5,
         }},
         .normal = .{.xyz = .{
            .x = 0.0,
            .y = 1.0,
            .z = 0.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 1.0,
            .v = 0.0,
         }},
         .position = .{.xyz = .{
            .x =  0.5,
            .y =  0.0,
            .z = -0.5,
         }},
         .normal = .{.xyz = .{
            .x = 0.0,
            .y = 1.0,
            .z = 0.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 0.0,
            .v = 1.0,
         }},
         .position = .{.xyz = .{
            .x = -0.5,
            .y =  0.0,
            .z =  0.5,
         }},
         .normal = .{.xyz = .{
            .x = 0.0,
            .y = 1.0,
            .z = 0.0,
         }},
      },
      .{
         .color = .{.channels = .{
            .r = 1.0,
            .g = 1.0,
            .b = 1.0,
            .a = 1.0,
         }},
         .sample = .{.uv = .{
            .u = 1.0,
            .v = 1.0,
         }},
         .position = .{.xyz = .{
            .x =  0.5,
            .y =  0.0,
            .z =  0.5,
         }},
         .normal = .{.xyz = .{
            .x = 0.0,
            .y = 1.0,
            .z = 0.0,
         }},
      },
   },
   .indices = &.{
      0, 1, 2,
      3,
   },
};

