const std         = @import("std");
const builtin     = @import("builtin");
const zest        = @import("zig-essential-tools");
const graphics    = @import("graphics");
const resources   = @import("resources");
const timing      = @import("timing.zig");

const MainError = error {
   CompositorConnectFailure,
   WindowCreateFailure,
   RendererCreateFailure,
   WindowTitleFormatFailure,
};

pub fn main() MainError!void {
   const PROGRAM_SEXY_NAME = "Learn Vulkan with Zig!";

   const allocator = zest.mem.allocator;

   var delta_timer         = timing.DeltaTimer.start();
   var window_title_timer  = timing.UpdateTimer.start(1000000000);

   zest.dbg.log.info("connecting to default desktop compositor", .{});
   const compositor = graphics.present.Compositor.connect_default() catch return error.CompositorConnectFailure;
   defer compositor.disconnect();

   zest.dbg.log.info("creating window for presentation", .{});
   var window = compositor.createWindow(allocator, .{
      .title         = PROGRAM_SEXY_NAME,
      .resolution    = .{.width = 1280, .height = 720},
      .display_mode  = .Windowed,
      .decorations   = true,
   }) catch return error.WindowCreateFailure;
   defer window.destroy();

   zest.dbg.log.info("creating vulkan renderer", .{});
   var renderer = window.createRenderer(allocator, .{
      .debugging        = zest.dbg.enable,
      .name             = PROGRAM_SEXY_NAME,
      .version          = 0x00000000,
      .refresh_mode     = .TripleBuffered,
      .clear_color      = .{.color = .{.r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0}},
      .shader_vertex    = &resources.shaders.Vertex,
      .shader_fragment  = &resources.shaders.Fragment,
      .frames_in_flight = 2,
   }) catch return error.RendererCreateFailure;
   defer renderer.destroy();

   zest.dbg.log.info("initialization complete, entering main loop", .{});

   delta_timer.lap();

   while (window.shouldClose() == false) {
      const delta_time  = delta_timer.deltaSeconds();
      const fps         = 1.0 / delta_time;

      if (window_title_timer.isElapsed() == true) {
         const window_title_formatted = std.fmt.allocPrintZ(allocator, PROGRAM_SEXY_NAME ++ " - {d:.0} fps", .{fps}) catch return error.WindowTitleFormatFailure;
         defer allocator.free(window_title_formatted);

         window.setTitle(window_title_formatted);

         window_title_timer.lap();
      }

      window.pollEvents() catch |err| {
         std.log.warn("failed to poll events: {}", .{err});
      };

      const input = window.getInput();

      if (input.buttons.state(.exit).is_pressed()) {
         window.setShouldClose(true);
      }

      renderer.renderFrame() catch |err| {
         std.log.warn("failed to render frame: {}", .{err});
      };

      delta_timer.lap();
      window_title_timer.tick();
   }

   return;
}

