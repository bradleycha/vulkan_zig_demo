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
};

const PROGRAM_NAME                     = "Learn Graphics Programming with Zig!";
const WINDOW_TITLE_UPDATE_TIME_SECONDS = 1.0;

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

   var renderer = graphics.Renderer.create(allocator, &window, &.{
      .program_name     = PROGRAM_NAME,
      .debugging        = builtin.mode == .Debug,
      .refresh_mode     = .triple_buffered,
      .shader_vertex    = resources.shaders.VERTEX,
      .shader_fragment  = resources.shaders.FRAGMENT,
      .clear_color      = .{.color = .{.channels = .{
         .r = 1.0,
         .g = 1.0,
         .b = 1.0,
         .a = 1.0,
      }}}
   }) catch return error.RendererCreateError;
   defer renderer.destroy();

   std.log.info("initialization complete, entering main loop", .{});
   while (window.shouldClose() == false) {
      const time_delta        = @as(f64, @floatFromInt(timer_delta.lap())) / 1000000000.0;
      const time_window_title = @as(f64, @floatFromInt(timer_window_title.read())) / 1000000000.0;

      if (time_window_title > WINDOW_TITLE_UPDATE_TIME_SECONDS) {
         timer_window_title.reset();

         const fps = 1.0 / time_delta;

         // "In this situation, programmers usually apply..."computer science".
         // And by..."computer science", I mean picking what seems like a
         // reasonable buffer length and then doubling it for good measure"
         //    - Dave Plumber 2021
         const FORMAT_BUFFER_LENGTH = PROGRAM_NAME.len * 2;

         var format_buffer : [FORMAT_BUFFER_LENGTH:0] u8 = undefined;
         const title = std.fmt.bufPrintZ(&format_buffer, PROGRAM_NAME ++ " - {d:0.0} fps", .{fps}) catch PROGRAM_NAME;

         window.setTitle(title);
      }

      window.pollEvents() catch |err| {
         std.log.warn("failed to poll window events: {}", .{err});
      };

      renderer.drawFrame() catch |err| {
         std.log.warn("failed to draw frame: {}", .{err});
      };
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

