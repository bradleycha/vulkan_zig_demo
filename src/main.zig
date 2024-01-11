const std         = @import("std");
const builtin     = @import("builtin");
const options     = @import("options");
const math        = @import("math");
const input       = @import("input");
const present     = @import("present");
const graphics    = @import("graphics");
const resources   = @import("resources");
const camera      = @import("camera.zig");

const MainError = error {
   OutOfMemory,
   StopwatchStartFailure,
   CompositorConnectError,
   WindowCreateError,
   RendererCreateError,
   ResourceLoadError,
};

const PROGRAM_NAME                     = "Learn Graphics Programming with Zig!";
const WINDOW_TITLE_UPDATE_TIME_SECONDS = 1.0;
const SPIN_SPEED                       = 2.0;
const CAMERA_SPAWN_POINT               = camera.FreeflyCamera{
   .position = .{.xyz = .{
      .x =  1.0,
      .y =  0.0,
      .z = -2.5,
   }},
   .angles = .{.angles = .{
      .pitch   = 0.0,
      .yaw     = std.math.pi / -10.0,
      .roll    = 0.0,
   }},
};

comptime {
   const float_mode = blk: {
      switch (std.debug.runtime_safety) {
         true  => break :blk std.builtin.FloatMode.Strict,
         false => break :blk std.builtin.FloatMode.Optimized,
      }
   };

   // Does this enable fast floating-point for all our imported packages too?
   // TODO: Disassemble and inspect the generated assembly to verify this works.
   @setFloatMode(float_mode);
}

pub fn main() MainError!void {
   var heap = chooseHeapSettings();
   defer _ = heap.deinit();

   const allocator = heap.allocator();

   std.log.info("starting timers", .{});
   var timer_delta_graphics   = std.time.Timer.start() catch return error.StopwatchStartFailure;
   var timer_delta_physics    = std.time.Timer.start() catch return error.StopwatchStartFailure;
   var timer_window_title     = std.time.Timer.start() catch return error.StopwatchStartFailure;

   std.log.info("connecting to desktop compostior", .{});
   var compositor = present.Compositor.connect(allocator) catch return error.CompositorConnectError;
   defer compositor.disconnect(allocator);

   std.log.info("creating window for rendering", .{});
   var window = compositor.createWindow(allocator, &.{
      .title         = PROGRAM_NAME,
      .display_mode  = .{.windowed = .{.width = 1280, .height = 720}},
   }, &.{
      .exit          = .escape,
      .toggle_focus  = .tab,
      .move_forward  = .w,
      .move_backward = .s,
      .move_left     = .a,
      .move_right    = .d,
      .move_up       = .space,
      .move_down     = .left_shift,
      .look_up       = .arrow_up,
      .look_down     = .arrow_down,
      .look_left     = .arrow_left,
      .look_right    = .arrow_right,
      .accelerate    = .left_control,
      .decelerate    = .left_alt,
      .respawn       = .r
   }) catch return error.WindowCreateError;
   defer window.destroy(allocator);

   const controller = window.controller();

   var renderer = graphics.Renderer.create(allocator, &window, &.{
      .program_name        = PROGRAM_NAME,
      .debugging           = builtin.mode == .Debug,
      .refresh_mode        = .triple_buffered,
      .multisampling_level = .maximum,
      .shader_vertex       = resources.shaders.VERTEX,
      .shader_fragment     = resources.shaders.FRAGMENT,
      .clear_color         = .{.color = .{.channels = .{
         .r = 0.1,
         .g = 0.2,
         .b = 0.5,
         .a = 1.0,
      }}},
      .transform_view      = undefined,
      .color_ambient       = .{.channels = .{
         .r = 0.15,
         .g = 0.20,
         .b = 0.35,
         .a = 1.00,
      }},
      .color_sun           = .{.channels = .{
         .r = 1.00,
         .g = 0.85,
         .b = 0.60,
         .a = 1.00,
      }},
      .color_depth         = .{.channels = .{
         .r = 0.25,
         .g = 0.25,
         .b = 0.25,
         .a = 1.00,
      }},
      .normal_sun          = .{.xyz = .{
         .x =  1.00,
         .y =  1.00,
         .z =  1.00,
      }},
   }) catch return error.RendererCreateError;
   defer renderer.destroy();

   std.log.info("loading resources", .{});

   var asset_load_buffers_array : graphics.AssetLoader.LoadBuffersArrayStatic(&.{
      .meshes     = 3,
      .textures   = 3,
      .samplers   = 1,
   }) = undefined;

   while (renderer.loadAssets(&asset_load_buffers_array.getBuffers(), &.{
      .meshes = &.{
         .{
            .data = &resources.meshes.TEST_PLANE,
         },
         .{
            .data = &resources.meshes.TEST_PYRAMID,
         },
         .{
            .data = &resources.meshes.TEST_CUBE,
         },
      },
     .textures = &.{
         .{
            .data = &resources.textures.TILE,
         },
         .{
            .data = &resources.textures.GRASS,
         },
         .{
            .data = &resources.textures.ROCK,
         },
      },
     .samplers = &.{
         .{
            .sampling = .{
               .filter_magnification   = .linear,
               .filter_minification    = .linear,
               .address_mode_u         = .repeat,
               .address_mode_v         = .repeat,
               .address_mode_w         = .repeat,
            },
         },
     },
   }) catch (return error.ResourceLoadError) == false) {}
   defer while(renderer.unloadAssets(&asset_load_buffers_array.handles) == false) {};

   const mesh_handle_test_plane     = asset_load_buffers_array.handles[0];
   const mesh_handle_test_pyramid   = asset_load_buffers_array.handles[1];
   const mesh_handle_test_cube      = asset_load_buffers_array.handles[2];
   const texture_handle_tile        = asset_load_buffers_array.handles[3];
   const texture_handle_grass       = asset_load_buffers_array.handles[4];
   const texture_handle_rock        = asset_load_buffers_array.handles[5];
   const sampler_handle_default     = asset_load_buffers_array.handles[6];

   const texture_sampler_tile = try renderer.createTextureSampler(&.{
      .texture = texture_handle_tile,
      .sampler = sampler_handle_default,
   });
   defer renderer.destroyTextureSampler(texture_sampler_tile);

   const texture_sampler_grass = try renderer.createTextureSampler(&.{
      .texture = texture_handle_grass,
      .sampler = sampler_handle_default,
   });
   defer renderer.destroyTextureSampler(texture_sampler_grass);

   const texture_sampler_rock = try renderer.createTextureSampler(&.{
      .texture = texture_handle_rock,
      .sampler = sampler_handle_default,
   });
   defer renderer.destroyTextureSampler(texture_sampler_rock);

   var mesh_push_constants_test_plane     : graphics.types.PushConstants = undefined;
   var mesh_push_constants_test_pyramid   : graphics.types.PushConstants = undefined;
   var mesh_push_constants_test_cube      : graphics.types.PushConstants = undefined;

   const mesh_matrix_test_plane     = &mesh_push_constants_test_plane.transform_mesh;
   const mesh_matrix_test_pyramid   = &mesh_push_constants_test_pyramid.transform_mesh;
   const mesh_matrix_test_cube      = &mesh_push_constants_test_cube.transform_mesh;

   std.log.info("initialization complete, entering main loop", .{});

   var freefly_camera = CAMERA_SPAWN_POINT;

   mesh_matrix_test_plane.* = math.Transform(f32).toMatrix(&.{
      .translation = .{.xyz = .{
         .x =  0.00,
         .y = -0.75,
         .z =  0.00,
      }},
      .rotation = .{.angles = .{
         .pitch   = 0.0,
         .yaw     = 0.0,
         .roll    = 0.0,
      }},
      .scale = .{.xyz = .{
         .x = 5.0,
         .y = 5.0,
         .z = 5.0,
      }},
   });

   var time_delta_graphics : f32 = 0.0;

   var time_accumulated_graphics       : f32 = 0.0;
   var time_accumulated_physics        : f32 = 0.0;
   var time_accumulated_graphics_count : u32 = 0;
   var time_accumulated_physics_count  : u32 = 0;

   var theta : f32 = 0.0;

   var mesh_transform_test_pyramid = math.Transform(f32){
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

   var mesh_transform_test_cube = math.Transform(f32){
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

   main_loop: while (true) {
      if (window.shouldClose() == true) {
         break :main_loop;
      }

      if (controller.buttons.state(.exit).isPressed() == true) {
         break :main_loop;
      }

      if (controller.buttons.state(.toggle_focus).isPressed() == true) {
         window.setCursorGrabbed(!window.isCursorGrabbed());
      }

      if (controller.buttons.state(.respawn).isPressed() == true) {
         freefly_camera = CAMERA_SPAWN_POINT;
      }

      const time_delta_physics   = @as(f32, @floatFromInt(timer_delta_physics.lap())) / 1000000000.0;
      const time_window_title    = @as(f64, @floatFromInt(timer_window_title.read())) / 1000000000.0;

      time_accumulated_physics         += time_delta_physics;
      time_accumulated_physics_count   += 1;

      if (time_window_title > WINDOW_TITLE_UPDATE_TIME_SECONDS) {
         @setCold(true);

         timer_window_title.reset();

         const fps = calculateAverageRate(time_accumulated_graphics, time_accumulated_graphics_count);
         const tps = calculateAverageRate(time_accumulated_physics, time_accumulated_physics_count);

         time_accumulated_graphics        = 0.0;
         time_accumulated_physics         = 0.0;
         time_accumulated_graphics_count  = 0;
         time_accumulated_physics_count   = 0;

         // The allocations within the loop are fine since we only execute this
         // code and re-allocate when the timer rolls over, which is to say
         // very infrequently.  The added jank for guessing a reasonable buffer
         // length isn't worth the microscopic performance gain.
         const title = try std.fmt.allocPrintZ(allocator, PROGRAM_NAME ++ " - {d:0.0} fps, {d:0.0} tps", .{fps, tps});
         defer allocator.free(title);

         window.setTitle(title);
      }

      freefly_camera.update(controller, time_delta_physics);

      renderer.uniformsMut().vertex.transform_view = freefly_camera.toMatrix();

      mesh_transform_test_pyramid.rotation.angles.yaw = theta;

      mesh_transform_test_cube.translation.xyz.x      = std.math.cos(theta);
      mesh_transform_test_cube.translation.xyz.z      = std.math.sin(theta);
      mesh_transform_test_cube.rotation.angles.pitch  = theta;
      mesh_transform_test_cube.rotation.angles.roll   = theta;

      mesh_matrix_test_pyramid.* = mesh_transform_test_pyramid.toMatrix();
      mesh_matrix_test_cube.*    = mesh_transform_test_cube.toMatrix();

      const frame_rendered = renderer.drawFrame(&.{
         .{
            .mesh             = mesh_handle_test_plane,
            .push_constants   = &mesh_push_constants_test_plane,
            .texture_sampler  = &texture_sampler_grass,
         },
         .{
            .mesh             = mesh_handle_test_pyramid,
            .push_constants   = &mesh_push_constants_test_pyramid,
            .texture_sampler  = &texture_sampler_rock,
         },
         .{
            .mesh             = mesh_handle_test_cube,
            .push_constants   = &mesh_push_constants_test_cube,
            .texture_sampler  = &texture_sampler_tile,
         },
      }) catch |err| blk: {
         std.log.warn("failed to draw frame: {}", .{err});
         break :blk false;
      };

      if (frame_rendered == true) {
         time_delta_graphics = @as(f32, @floatFromInt(timer_delta_graphics.lap())) / 1000000000.0;

         time_accumulated_graphics        += time_delta_graphics;
         time_accumulated_graphics_count  += 1;
      }

      window.pollEvents() catch |err| {
         std.log.warn("failed to poll window events: {}", .{err});
      };

      theta = @floatCast(@rem(theta + SPIN_SPEED * time_delta_physics, std.math.pi * 2.0));
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

   if (std.debug.runtime_safety == true) {
      return std.heap.page_allocator;
   }

   return std.heap.raw_c_allocator;
}

fn calculateAverageRate(sum : f32, count : u32) f32 {
   if (sum == 0.0) {
      @setCold(true);
      return 0.0;
   }

   if (count == 0) {
      @setCold(true);
      return 0;
   }

   return @as(f32, @floatFromInt(count)) / sum;
}

