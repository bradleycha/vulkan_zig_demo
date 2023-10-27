const std      = @import("std");
const f_shared = @import("shared.zig");
const cimports = @import("cimports");
const c        = struct {
   pub usingnamespace cimports.xcb;
};

pub const Compositor = struct {
   pub fn connect(allocator : std.mem.Allocator) f_shared.Compositor.ConnectError!@This() {
      _ = allocator;
      unreachable;
   }

   pub fn disconnect(self : @This(), allocator : std.mem.Allocator) void {
      _ = self;
      _ = allocator;
      unreachable;
   }

   pub fn createWindow(self : * @This(), allocator : std.mem.Allocator, create_info : * const f_shared.Window.CreateInfo) f_shared.Window.CreateError!Window {
      return Window.create(self, allocator, create_info);
   }
};

pub const Window = struct {
   pub fn create(compositor : * Compositor, allocator : std.mem.Allocator, create_info : * const f_shared.Window.CreateInfo) f_shared.Window.CreateError!@This() {
      _ = compositor;
      _ = allocator;
      _ = create_info;
      unreachable;
   }

   pub fn destroy(self : @This(), allocator : std.mem.Allocator) void {
      _ = self;
      _ = allocator;
      unreachable;
   }

   pub fn getResolution(self : * const @This()) f_shared.Window.Resolution {
      _ = self;
      unreachable;
   }

   pub fn setTitle(self : * @This(), title : [*:0] const u8) void {
      _ = self;
      _ = title;
      unreachable;
   }

   pub fn shouldClose(self : * const @This()) bool {
      _ = self;
      unreachable;
   }

   pub fn setShouldClose(self : * @This(), should_close : bool) void {
      _ = self;
      _ = should_close;
      unreachable;
   }

   pub fn pollEvents(self : * @This()) f_shared.Window.PollEventsError!void {
      _ = self;
      unreachable;
   }
};

