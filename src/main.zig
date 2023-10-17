const std         = @import("std");
const graphics    = @import("graphics");
const resources   = @import("resources");

const MainError = error {
   CompositorConnectFailure,
   WindowCreateFailure,
};

pub fn main() MainError!void {
   const compositor = graphics.present.Compositor.connect_default() catch return error.CompositorConnectFailure;
   defer compositor.disconnect();

   var window = compositor.createWindow(.{
      .title         = "Learn Vulkan with Zig!",
      .resolution    = .{.width = 1280, .height = 720},
      .display_mode  = .Windowed,
      .decorations   = true,
   }) catch return error.WindowCreateFailure;
   defer window.destroy();

   // TODO: Create vulkan renderer and attach it to the window

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

