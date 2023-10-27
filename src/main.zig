const std         = @import("std");
const builtin     = @import("builtin");
const options     = @import("options");
const present     = @import("present");
const graphics    = @import("graphics");
const resources   = @import("resources");

const MainError = error {
   OutOfMemory,
   CompositorConnectError,
   WindowCreateError,
};

pub fn main() MainError!void {
   var heap = chooseHeapSettings();
   defer _ = heap.deinit();

   const allocator = heap.allocator();

   std.log.info("connecting to desktop compostior", .{});
   var compositor = present.Compositor.connect(allocator) catch return error.CompositorConnectError;
   defer compositor.disconnect(allocator);

   for (present.VULKAN_REQUIRED_EXTENSIONS.Instance) |instance_extension| {
      std.io.getStdOut().writer().print("vulkan instance extension: {s}\n", .{instance_extension}) catch {};
   }
   for (present.VULKAN_REQUIRED_EXTENSIONS.Device) |device_extension| {
      std.io.getStdOut().writer().print("vulkan device extension: {s}\n", .{device_extension}) catch {};
   }

   std.log.info("creating window for rendering", .{});
   var window = compositor.createWindow(allocator, &.{
      .title         = "Learn Graphics Programming with Zig!",
      .display_mode  = .{.windowed = .{.width = 1280, .height = 720}},
   }) catch return error.WindowCreateError;
   defer window.destroy(allocator);

   // TODO: Create renderer

   std.log.info("initialization complete, entering main loop", .{});
   while (window.shouldClose() == false) {
      window.pollEvents() catch |err| {
         std.log.warn("failed to poll window events: {}", .{err});
      };

      // TODO: Main rendering and input loop
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

