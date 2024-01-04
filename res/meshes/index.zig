const std      = @import("std");
const graphics = @import("graphics");
const parser   = @import("parser");

pub const TEST_TRIANGLE = _embedWavefront(.{
   .obj = "test_triangle.obj",
   .mtl = "test_triangle.mtl",
});
pub const TEST_OCTAGON  = _embedWavefront(.{
   .obj = "test_octagon.obj",
   .mtl = "test_octagon.mtl",
});
pub const TEST_CUBE     = _embedWavefront(.{
   .obj = "test_cube.obj",
   .mtl = "test_cube.mtl",
});
pub const TEST_PYRAMID  = _embedWavefront(.{
   .obj = "test_pyramid.obj",
   .mtl = "test_pyramid.mtl",
});
pub const TEST_PLANE    = _embedWavefront(.{
   .obj = "test_plane.obj",
   .mtl = "test_plane.mtl",
});

fn _embedWavefront(comptime paths : struct {
   obj : [] const u8,
   mtl : [] const u8,
}) graphics.types.Mesh {
   const bytes_obj = @embedFile(paths.obj);
   const bytes_mtl = @embedFile(paths.mtl);

   const mesh = parser.wavefront.parseWavefrontComptime(bytes_obj, bytes_mtl) catch |err| {
      @compileError(std.fmt.comptimePrint("failed to parse mesh \'{s}\' / \'{s}\': {s}", .{paths.obj, paths.mtl, @errorName(err)}));
   };

   return mesh;
}

