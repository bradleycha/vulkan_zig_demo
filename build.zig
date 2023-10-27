const std   = @import("std");
const bd    = @import("build/index.zig");

const MODULE_NAME = struct {
   pub const options    = "options";
   pub const cimports   = "cimports";
   pub const present    = "present";
   pub const graphics   = "graphics";
   pub const resources  = "resources";
};

const MODULE_ROOT_SOURCE_PATH = struct {
   pub const cimports   = "src/cimports.zig";
   pub const present    = "src/present/index.zig";
   pub const graphics   = "src/graphics/index.zig";
   pub const resources  = "res/index.zig";
};

const PROGRAM_EXECUTABLE = struct {
   pub const output_name      = "learn_graphics_zig";
   pub const root_source_path = "src/main.zig";
};

pub fn build(b : * std.Build) void {
   const opt_target_platform  = b.standardTargetOptions(.{});
   const opt_optimize_mode    = b.standardOptimizeOption(.{});
   const opt_present_backend   = b.option(
      bd.present.PresentBackend,
      "present-backend",
      "backend library for presentation, aka windowing",
   ) orelse bd.present.PresentBackend.targetDefault(b, &opt_target_platform);

   const options = b.addOptions();
   options.addOption(bd.present.PresentBackend, "present_backend", opt_present_backend);

   const module_options = options.createModule();

   const module_cimports = b.addModule(MODULE_NAME.cimports, .{
      .source_file   = .{.path = MODULE_ROOT_SOURCE_PATH.cimports},
      .dependencies  = &.{
         .{
            .name    = MODULE_NAME.options,
            .module  = module_options,
         },
      },
   });

   const module_present = b.addModule(MODULE_NAME.present, .{
      .source_file   = .{.path = MODULE_ROOT_SOURCE_PATH.present},
      .dependencies  = &.{
         .{
            .name    = MODULE_NAME.options,
            .module  = module_options,
         },
         .{
            .name    = MODULE_NAME.cimports,
            .module  = module_cimports,
         },
      },
   });

   const module_graphics = b.addModule(MODULE_NAME.graphics, .{
      .source_file   = .{.path = MODULE_ROOT_SOURCE_PATH.graphics},
      .dependencies  = &.{
         .{
            .name    = MODULE_NAME.options,
            .module  = module_options,
         },
         .{
            .name    = MODULE_NAME.cimports,
            .module  = module_cimports,
         },
         .{
            .name    = MODULE_NAME.present,
            .module  = module_present,
         },
      },
   });

   const module_resources = b.addModule(MODULE_NAME.resources, .{
      .source_file   = .{.path = MODULE_ROOT_SOURCE_PATH.resources},
      .dependencies  = &.{
         .{
            .name    = MODULE_NAME.options,
            .module  = module_options,
         },
         .{
            .name    = MODULE_NAME.graphics,
            .module  = module_graphics,
         },
      },
   });

   var exe_main = b.addExecutable(.{
      .name             = PROGRAM_EXECUTABLE.output_name,
      .root_source_file = .{.path = PROGRAM_EXECUTABLE.root_source_path},
      .target           = opt_target_platform,
      .optimize         = opt_optimize_mode,
   });

   b.installArtifact(exe_main);

   exe_main.linkLibC();
   exe_main.addModule(MODULE_NAME.options, module_options);
   exe_main.addModule(MODULE_NAME.present, module_present);
   exe_main.addModule(MODULE_NAME.graphics, module_graphics);
   exe_main.addModule(MODULE_NAME.resources, module_resources);
   exe_main.strip = opt_optimize_mode != .Debug;

   opt_present_backend.addCompileStepDependencies(b, exe_main);

   const cmd_run_exe_main = b.addRunArtifact(exe_main);
   cmd_run_exe_main.step.dependOn(b.getInstallStep());
   if (b.args) |args| {
      cmd_run_exe_main.addArgs(args);
   }

   const step_run_exe_main = b.step("run", "Run the main output executable");
   step_run_exe_main.dependOn(&cmd_run_exe_main.step);

   return;
}

