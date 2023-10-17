const std = @import("std");

pub fn build(b : * std.Build) void {
   const opt_target_platform  = b.standardTargetOptions(.{});
   const opt_optimize_mode    = b.standardOptimizeOption(.{});

   const MODULE_NAME_ZEST        = "zig-essential-tools";
   const MODULE_NAME_GRAPHICS    = "graphics";
   const MODULE_NAME_RESOURCES   = "resources";

   const module_zest = b.addModule(MODULE_NAME_ZEST, .{
      .source_file   = .{.path = "lib/zig-essential-tools/index.zig"},
      .dependencies  = &([_] std.Build.ModuleDependency {

      }),
   });

   const module_graphics = b.addModule(MODULE_NAME_GRAPHICS, .{
      .source_file   = .{.path = "src/graphics/index.zig"},
      .dependencies  = &([_] std.Build.ModuleDependency {
         .{
            .name    = MODULE_NAME_ZEST,
            .module  = module_zest,
         },
      }),
   });

   const module_resources = b.addModule(MODULE_NAME_RESOURCES, .{
      .source_file = .{.path = "res/index.zig"},
      .dependencies  = &([_] std.Build.ModuleDependency {
         .{
            .name    = MODULE_NAME_ZEST,
            .module  = module_zest,
         },
         .{
            .name    = MODULE_NAME_GRAPHICS,
            .module  = module_graphics,
         },
      }),
   });

   const exe_main = b.addExecutable(.{
      .name             = "learn_vulkan_zig",
      .root_source_file = .{.path = "src/main.zig"},
      .target           = opt_target_platform,
      .optimize         = opt_optimize_mode,
   });

   exe_main.linkLibC();
   exe_main.linkSystemLibrary("glfw");
   exe_main.linkSystemLibrary("vulkan");
   exe_main.addModule(MODULE_NAME_ZEST, module_zest);
   exe_main.addModule(MODULE_NAME_GRAPHICS, module_graphics);
   exe_main.addModule(MODULE_NAME_RESOURCES, module_resources);

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

