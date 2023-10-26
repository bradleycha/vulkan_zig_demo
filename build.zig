const std = @import("std");

pub fn build(b : * std.Build) void {
   const opt_target_platform  = b.standardTargetOptions(.{});
   const opt_optimize_mode    = b.standardOptimizeOption(.{});

   var exe_main = b.addExecutable(.{
      .name             = "learn_vulkan_zig",
      .root_source_file = .{.path = "src/main.zig"},
      .target           = opt_target_platform,
      .optimize         = opt_optimize_mode,
   });

   exe_main.strip = opt_optimize_mode != .Debug;

   b.installArtifact(exe_main);

   const cmd_run_exe_main = b.addRunArtifact(exe_main);
   cmd_run_exe_main.step.dependOn(b.getInstallStep());
   if (b.args) |args| {
      cmd_run_exe_main.addArgs(args);
   }

   const step_run_exe_main = b.step("run", "Run the main output executable");
   step_run_exe_main.dependOn(&cmd_run_exe_main.step);

   return;
}

