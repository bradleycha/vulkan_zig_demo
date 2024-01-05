const std      = @import("std");
const graphics = @import("graphics");
const parser   = @import("parser");

pub const TEST_TRIANGLE = _embedWavefront("test_triangle.obj");
pub const TEST_OCTAGON  = _embedWavefront("test_octagon.obj");
pub const TEST_CUBE     = _embedWavefront("test_cube.obj");
pub const TEST_PYRAMID  = _embedWavefront("test_pyramid.obj");
pub const TEST_PLANE    = _embedWavefront("test_plane.obj");

fn _embedWavefront(comptime path : [] const u8) graphics.types.Mesh {
   const bytes = @embedFile(path);

   const mesh = parser.wavefront.parseWavefrontComptime(bytes) catch |err| {
      @compileError(std.fmt.comptimePrint("failed to parse mesh \'{s}\': {s}", .{path, @errorName(err)}));
   };

   return mesh;
}

