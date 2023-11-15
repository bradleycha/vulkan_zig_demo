const std         = @import("std");
const builtin     = @import("builtin");
const options     = @import("options");
const present     = @import("present");
const graphics    = @import("graphics");
const resources   = @import("resources");

const MainError = error {
   OutOfMemory,
   DeltaTimerStartFailure,
   WindowTitleTimerStartFailure,
   CompositorConnectError,
   WindowCreateError,
   RendererCreateError,
   ResourceLoadError,
};

const PROGRAM_NAME                     = "Learn Graphics Programming with Zig!";
const WINDOW_TITLE_UPDATE_TIME_SECONDS = 1.0;
const SPIN_SPEED                       = 2.0;

pub fn main() MainError!void {
   var heap = chooseHeapSettings();
   defer _ = heap.deinit();

   const allocator = heap.allocator();

   std.log.info("starting timers", .{});
   var timer_delta         = std.time.Timer.start() catch return error.DeltaTimerStartFailure;
   var timer_window_title  = std.time.Timer.start() catch return error.DeltaTimerStartFailure;

   std.log.info("connecting to desktop compostior", .{});
   var compositor = present.Compositor.connect(allocator) catch return error.CompositorConnectError;
   defer compositor.disconnect(allocator);

   std.log.info("creating window for rendering", .{});
   var window = compositor.createWindow(allocator, &.{
      .title         = PROGRAM_NAME,
      .display_mode  = .{.windowed = .{.width = 1280, .height = 720}},
   }) catch return error.WindowCreateError;
   defer window.destroy(allocator);

   const input_state = window.inputState();

   var renderer = graphics.Renderer.create(allocator, &window, &.{
      .program_name     = PROGRAM_NAME,
      .debugging        = builtin.mode == .Debug,
      .refresh_mode     = .triple_buffered,
      .shader_vertex    = resources.shaders.VERTEX,
      .shader_fragment  = resources.shaders.FRAGMENT,
      .clear_color      = .{.color = .{.channels = .{
         .r = 0.0,
         .g = 0.0,
         .b = 0.0,
         .a = 1.0,
      }}},
   }) catch return error.RendererCreateError;
   defer renderer.destroy();

   const camera_matrix = renderer.cameraTransformMatrixMut();

   std.log.info("loading resources", .{});

   const mesh_handle_test_pyramid = renderer.loadMesh(&resources.meshes.MESH_TEST_PYRAMID) catch return error.ResourceLoadError;
   defer renderer.unloadMesh(mesh_handle_test_pyramid);

   const mesh_handle_test_cube = renderer.loadMesh(&resources.meshes.MESH_TEST_CUBE) catch return error.ResourceLoadError;
   defer renderer.unloadMesh(mesh_handle_test_cube);

   const mesh_matrix_test_pyramid   = renderer.meshTransformMatrixMut(mesh_handle_test_pyramid);
   const mesh_matrix_test_cube      = renderer.meshTransformMatrixMut(mesh_handle_test_cube);

   std.log.info("initialization complete, entering main loop", .{});

   var theta : f32 = 0.0;

   var camera_transform = graphics.types.Transform(f32){
      .translation = .{.xyz = .{
         .x =  0.0,
         .y =  0.0,
         .z = -2.5,
      }},
      .rotation = .{.angles = .{
         .pitch   = 0.0,
         .yaw     = std.math.pi / -10.0,
         .roll    = 0.0,
      }},
      .scale = .{.xyz = .{
         .x = 1.0,
         .y = 1.0,
         .z = 1.0,
      }},
   };

   var mesh_transform_test_pyramid = graphics.types.Transform(f32){
      .translation = .{.xyz = .{
         .x = 0.0,
         .y = 0.0,
         .z = undefined,
      }},
      .rotation = .{.angles = .{
         .pitch   = 0.0,
         .yaw     = undefined,
         .roll    = 0.0,
      }},
      .scale = .{.xyz = .{
         .x = 1.0,
         .y = 1.0,
         .z = 1.0,
      }},
   };

   var mesh_transform_test_cube = graphics.types.Transform(f32){
      .translation = .{.xyz = .{
         .x = undefined,
         .y = undefined,
         .z = 0.0,
      }},
      .rotation = .{.angles = .{
         .pitch   = undefined,
         .yaw     = 0.0,
         .roll    = 0.0,
      }},
      .scale = .{.xyz = .{
         .x = 0.70,
         .y = 0.70,
         .z = 0.70,
      }},
   };

   while (window.shouldClose() == false) {
      const time_delta        = @as(f64, @floatFromInt(timer_delta.lap())) / 1000000000.0;
      const time_window_title = @as(f64, @floatFromInt(timer_window_title.read())) / 1000000000.0;

      if (time_window_title > WINDOW_TITLE_UPDATE_TIME_SECONDS) {
         timer_window_title.reset();

         const fps = 1.0 / time_delta;

         // The allocations within the loop are fine since we only execute this
         // code and re-allocate when the timer rolls over, which is to say
         // very infrequently.  The added jank for guessing a reasonable buffer
         // length isn't worth the microscopic performance gain.
         const title = try std.fmt.allocPrintZ(allocator, PROGRAM_NAME ++ " - {d:0.0} fps", .{fps});
         defer allocator.free(title);

         window.setTitle(title);
      }

      // TODO: Freefly camera
      _ = input_state;

      mesh_transform_test_pyramid.translation.xyz.z   = std.math.cos(theta);
      mesh_transform_test_pyramid.rotation.angles.yaw = theta;

      mesh_transform_test_cube.translation.xyz.x      = std.math.cos(theta);
      mesh_transform_test_cube.translation.xyz.y      = std.math.sin(theta);
      mesh_transform_test_cube.rotation.angles.pitch  = theta;

      camera_matrix.*            = camera_transform.toMatrix();
      mesh_matrix_test_pyramid.* = mesh_transform_test_pyramid.toMatrix();
      mesh_matrix_test_cube.*    = mesh_transform_test_cube.toMatrix();

      renderer.drawFrame(&.{mesh_handle_test_pyramid, mesh_handle_test_cube}) catch |err| {
         std.log.warn("failed to draw frame: {}", .{err});
      };

      window.pollEvents() catch |err| {
         std.log.warn("failed to poll window events: {}", .{err});
      };

      theta = @floatCast(@rem(theta + SPIN_SPEED * time_delta, std.math.pi * 2.0));
   }

   return;
}

fn chooseHeapSettings() std.heap.GeneralPurposeAllocator(.{}) {
   const backing_allocator = chooseBackingAllocator();

   return .{.backing_allocator = backing_allocator};
}

fn chooseBackingAllocator() std.mem.Allocator {
   if (builtin.link_libc == false) {
      return std.heap.page_allocator;
   }

   if (builtin.mode == .Debug) {
      return std.heap.page_allocator;
   }

   return std.heap.raw_c_allocator;
}

