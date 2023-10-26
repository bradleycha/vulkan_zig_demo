const std         = @import("std");
const window      = @import("window");
const graphics    = @import("graphics");
const resources   = @import("resources");

pub fn main() void {
   std.io.getStdOut().writer().print("Hello, world!\n", .{}) catch {};
   return;
}

