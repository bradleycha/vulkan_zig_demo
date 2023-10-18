const std         = @import("std");
const builtin     = @import("builtin");
const zest        = @import("zig-essential-tools");
const graphics    = @import("graphics");
const resources   = @import("resources");

const MainError = error {
   CompositorConnectFailure,
   WindowCreateFailure,
   RendererCreateFailure,
};

pub fn main() MainError!void {
   const PROGRAM_SEXY_NAME = "Learn Vulkan with Zig!";

   const allocator = std.heap.page_allocator;

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
      .debugging     = zest.dbg.enable,
      .name          = PROGRAM_SEXY_NAME,
      .version       = 0x00000000,
      .refresh_mode  = .TripleBuffered,
   }) catch return error.RendererCreateFailure;
   defer renderer.destroy();

   zest.dbg.log.info("initialization complete, entering main loop", .{});

   while (window.shouldClose() == false) {
      window.pollEvents() catch |err| {
         std.log.warn("failed to poll events: {}", .{err});
      };

      const input = window.getInput();

      if (input.buttons.state(.exit).is_pressed()) {
         window.setShouldClose(true);
      }

      // TODO: Buffer swapping, rendering, etc.
   }

   return;
}

