const std = @import("std");

pub const ShaderCompile = struct {
   pub const Stage = enum {
      vertex,
      fragment,
      geometry,
      compute,
   };

   pub const Options = struct {
      input_path  : [] const u8,
      output_path : [] const u8,
      stage       : Stage,
      optimize    : std.builtin.OptimizeMode,
   };

   pub fn add(b : * std.Build, exe : * std.Build.Step.Compile, options : Options) anyerror!void {
      const FLAG_SHADER_STAGE = "-fshader-stage=";
      const FLAG_OPT_LEVEL    = "-O";

      const shader_stage = blk: {
         switch (options.stage) {
            .vertex     => break :blk FLAG_SHADER_STAGE ++ "vertex",
            .fragment   => break :blk FLAG_SHADER_STAGE ++ "fragment",
            .geometry   => break :blk FLAG_SHADER_STAGE ++ "geometry",
            .compute    => break :blk FLAG_SHADER_STAGE ++ "compute",
         }
      };

      const opt_level = blk: {
         switch (options.optimize) {
            .Debug         => break :blk FLAG_OPT_LEVEL ++ "0",
            .ReleaseSafe   => break :blk FLAG_OPT_LEVEL ++ "",
            .ReleaseSmall  => break :blk FLAG_OPT_LEVEL ++ "s",
            .ReleaseFast   => break :blk FLAG_OPT_LEVEL ++ "",
         }
      };

      const run_cmd = b.addSystemCommand(&([_] [] const u8 {
         "glslc",
         shader_stage,
         opt_level,
         "-o",
         options.output_path,
         options.input_path,
      }));

      exe.step.dependOn(&run_cmd.step);

      return;
   }
};
