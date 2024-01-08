const std   = @import("std");
const bd    = @import("src/build/index.zig");

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

const TEXTURE_PATH = struct {
   pub const grass   = "res/textures/grass.tga";
   pub const rock    = "res/textures/rock.tga";
   pub const tile    = "res/textures/tile.tga";
};

const TEXTURE_FORMAT = struct {
   pub const grass   = .targa;
   pub const rock    = .targa;
   pub const tile    = .targa;
};

const TEXTURE_IDENTIFIER = struct {
   pub const grass   = "grass";
   pub const rock    = "rock";
   pub const tile    = "tile";
};

const MESH_PATH = struct {
   pub const test_triangle = "res/meshes/test_triangle.ply";
   pub const test_octagon  = "res/meshes/test_octagon.ply";
   pub const test_cube     = "res/meshes/test_cube.ply";
   pub const test_pyramid  = "res/meshes/test_pyramid.ply";
   pub const test_plane    = "res/meshes/test_plane.ply";
};

const MESH_IDENTIFIER = struct {
   pub const test_triangle = "test_triangle";
   pub const test_octagon  = "test_octagon";
   pub const test_cube     = "test_cube";
   pub const test_pyramid  = "test_pyramid";
   pub const test_plane    = "test_plane";
};

const MODULE_NAME = struct {
   pub const options    = "options";
   pub const cimports   = "cimports";
   pub const math       = "math";
   pub const structures = "structures";
   pub const input      = "input";
   pub const present    = "present";
   pub const graphics   = "graphics";
   pub const shaders    = "shaders";
   pub const textures   = "textures";
   pub const meshes     = "meshes";
   pub const resources  = "resources";
};

const MODULE_ROOT_SOURCE_PATH = struct {
   pub const cimports   = "src/cimports.zig";
   pub const math       = "src/math/index.zig";
   pub const structures = "src/structures/index.zig";
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
         .{
            .name    = MODULE_NAME.math,
            .module  = module_math,
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

   const texture_grass  = bd.image.ImageParseStep.create(b, &.{
      .path    = .{.path = TEXTURE_PATH.grass},
      .format  = TEXTURE_FORMAT.grass,
   });
   const texture_rock   = bd.image.ImageParseStep.create(b, &.{
      .path    = .{.path = TEXTURE_PATH.rock},
      .format  = TEXTURE_FORMAT.rock,
   });
   const texture_tile   = bd.image.ImageParseStep.create(b, &.{
      .path    = .{.path = TEXTURE_PATH.tile},
      .format  = TEXTURE_FORMAT.tile,
   });

   const image_bundle = bd.image.ImageBundle.create(b);

   image_bundle.addImage(.{
      .parse_step = texture_grass,
      .identifier = TEXTURE_IDENTIFIER.grass,
   });
   image_bundle.addImage(.{
      .parse_step = texture_rock,
      .identifier = TEXTURE_IDENTIFIER.rock,
   });
   image_bundle.addImage(.{
      .parse_step = texture_tile,
      .identifier = TEXTURE_IDENTIFIER.tile,
   });

   const mesh_test_triangle = bd.mesh.MeshParseStep.create(b, .{.ply = .{
      .path = .{.path = MESH_PATH.test_triangle},
   }});
   const mesh_test_octagon = bd.mesh.MeshParseStep.create(b, .{.ply = .{
      .path = .{.path = MESH_PATH.test_octagon},
   }});
   const mesh_test_cube = bd.mesh.MeshParseStep.create(b, .{.ply = .{
      .path = .{.path = MESH_PATH.test_cube},
   }});
   const mesh_test_pyramid = bd.mesh.MeshParseStep.create(b, .{.ply = .{
      .path = .{.path = MESH_PATH.test_pyramid},
   }});
   const mesh_test_plane = bd.mesh.MeshParseStep.create(b, .{.ply = .{
      .path = .{.path = MESH_PATH.test_plane},
   }});

   const mesh_bundle = bd.mesh.MeshBundle.create(b);

   mesh_bundle.addMesh(.{
      .parse_step = mesh_test_triangle,
      .identifier = MESH_IDENTIFIER.test_triangle,
   });
   mesh_bundle.addMesh(.{
      .parse_step = mesh_test_octagon,
      .identifier = MESH_IDENTIFIER.test_octagon,
   });
   mesh_bundle.addMesh(.{
      .parse_step = mesh_test_cube,
      .identifier = MESH_IDENTIFIER.test_cube,
   });
   mesh_bundle.addMesh(.{
      .parse_step = mesh_test_pyramid,
      .identifier = MESH_IDENTIFIER.test_pyramid,
   });
   mesh_bundle.addMesh(.{
      .parse_step = mesh_test_plane,
      .identifier = MESH_IDENTIFIER.test_plane,
   });

   const module_shaders    = shader_bundle.createModule(module_graphics);
   const module_textures   = image_bundle.createModule(module_graphics);
   const module_meshes     = mesh_bundle.createModule(module_graphics);

   const module_resources = b.addModule(MODULE_NAME.resources, .{
      .source_file   = .{.path = MODULE_ROOT_SOURCE_PATH.resources},
      .dependencies  = &.{
         .{
            .name    = MODULE_NAME.shaders,
            .module  = module_shaders,
         },
         .{
            .name    = MODULE_NAME.textures,
            .module  = module_textures,
         },
         .{
            .name    = MODULE_NAME.meshes,
            .module  = module_meshes,
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

