const std   = @import("std");
const bd    = @import("build/index.zig");

const SHADER_SOURCE_PATH = struct {
   pub const vertex     = "src/shaders/vertex.glsl";
   pub const fragment   = "src/shaders/fragment.glsl";
};

const SHADER_IDENTIFIER = struct {
   pub const vertex     = "vertex";
   pub const fragment   = "fragment";
};

const SHADER_MAIN = struct {
   pub const vertex     = "main";
   pub const fragment   = "main";
};

const MODULE_NAME = struct {
   pub const options    = "options";
   pub const shaders    = "shaders";
   pub const cimports   = "cimports";
   pub const structures = "structures";
   pub const math       = "math";
   pub const input      = "input";
   pub const present    = "present";
   pub const graphics   = "graphics";
   pub const resources  = "resources";
};

const MODULE_ROOT_SOURCE_PATH = struct {
   pub const cimports   = "src/cimports.zig";
   pub const structures = "src/structures/index.zig";
   pub const math       = "src/math/index.zig";
   pub const input      = "src/input/index.zig";
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
      "Backend system library for window presentation",
   ) orelse bd.present.PresentBackend.targetDefault(b, &opt_target_platform);

   const options = b.addOptions();
   options.addOption(bd.present.PresentBackend, "present_backend", opt_present_backend);

   const shader_vertex = bd.shader.ShaderCompileStep.create(b, &.{
      .input_file = .{.path = SHADER_SOURCE_PATH.vertex},
      .optimize   = opt_optimize_mode,
      .stage      = .vertex,
   });

   const shader_fragment = bd.shader.ShaderCompileStep.create(b, &.{
      .input_file = .{.path = SHADER_SOURCE_PATH.fragment},
      .optimize   = opt_optimize_mode,
      .stage      = .fragment,
   });

   const shader_bundle = bd.shader.ShaderBundle.create(b);

   shader_bundle.addShader(.{
      .compile_step  = shader_vertex,
      .identifier    = SHADER_IDENTIFIER.vertex,
      .entrypoint    = SHADER_MAIN.vertex,
   });

   shader_bundle.addShader(.{
      .compile_step  = shader_fragment,
      .identifier    = SHADER_IDENTIFIER.fragment,
      .entrypoint    = SHADER_MAIN.fragment,
   });

   const module_options = options.createModule();

   const module_shaders = shader_bundle.createModule();

   const module_cimports = b.addModule(MODULE_NAME.cimports, .{
      .source_file   = .{.path = MODULE_ROOT_SOURCE_PATH.cimports},
      .dependencies  = &.{
         .{
            .name    = MODULE_NAME.options,
            .module  = module_options,
         },
      },
   });

   const module_structures = b.addModule(MODULE_NAME.structures, .{
      .source_file   = .{.path = MODULE_ROOT_SOURCE_PATH.structures},
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

   const module_math = b.addModule(MODULE_NAME.math, .{
      .source_file   = .{.path = MODULE_ROOT_SOURCE_PATH.math},
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

   const module_input = b.addModule(MODULE_NAME.input, .{
      .source_file   = .{.path = MODULE_ROOT_SOURCE_PATH.input},
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
            .name    = MODULE_NAME.structures,
            .module  = module_structures,
         },
        .{
            .name    = MODULE_NAME.math,
            .module  = module_math,
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
         .{
            .name    = MODULE_NAME.structures,
            .module  = module_structures,
         },
         .{
            .name    = MODULE_NAME.input,
            .module  = module_input,
         },
        .{
            .name    = MODULE_NAME.math,
            .module  = module_math,
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
         .{
            .name    = MODULE_NAME.structures,
            .module  = module_structures,
         },
        .{
            .name    = MODULE_NAME.math,
            .module  = module_math,
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
            .name    = MODULE_NAME.shaders,
            .module  = module_shaders,
         },
         .{
            .name    = MODULE_NAME.graphics,
            .module  = module_graphics,
         },
         .{
            .name    = MODULE_NAME.structures,
            .module  = module_structures,
         },
        .{
            .name    = MODULE_NAME.math,
            .module  = module_math,
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
   exe_main.linkSystemLibrary("vulkan");
   exe_main.addModule(MODULE_NAME.options, module_options);
   exe_main.addModule(MODULE_NAME.structures, module_structures);
   exe_main.addModule(MODULE_NAME.math, module_math);
   exe_main.addModule(MODULE_NAME.input, module_input);
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

