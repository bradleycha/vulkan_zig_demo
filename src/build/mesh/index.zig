const std         = @import("std");
const wavefront   = @import("wavefront.zig");

const BUFFERED_IO_SIZE  = 4096;
const _BufferedReader   = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader);
const _BufferedWriter   = std.io.BufferedWriter(BUFFERED_IO_SIZE, std.fs.File.Writer);

pub const BuildMesh = struct {
   vertices : [] const Vertex,
   indices  : [] const IndexElement,

   pub const Vertex = struct {
      color    : @Vector(4, f32),
      sample   : @Vector(2, f32),
      position : @Vector(3, f32),
      normal   : @Vector(3, f32),
   };

   pub const IndexElement = u16;
};

pub const MeshParseStep = struct {
   step        : std.Build.Step,
   input       : MeshInput,
   output_file : std.Build.GeneratedFile,

   pub const MeshInputTag = enum {
      wavefront,
   };

   pub const MeshInput = union(MeshInputTag) {
      wavefront   : WavefrontInput,
   };

   pub const WavefrontInput = struct {
      path_obj : std.Build.LazyPath,
      path_mtl : std.Build.LazyPath,
   };

   pub fn create(owner : * std.Build, input : MeshInput) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");

      const step_name = blk: {
         switch (input) {
            .wavefront => |*model| {
               const name_obj = model.path_obj.getDisplayName();
               const name_mtl = model.path_mtl.getDisplayName();

               break :blk owner.fmt("meshparsestep wavefront {s} + {s}", .{name_obj, name_mtl});
            },
         }
      };

      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = step_name,
            .owner   = owner,
            .makeFn  = make,
         }),
         .input         = input,
         .output_file   = .{.step = &self.step},
      };

      switch (input) {
         .wavefront => |*model| {
            model.path_obj.addStepDependencies(&self.step);
            model.path_mtl.addStepDependencies(&self.step);
         },
      }

      return self;
   }

   pub fn getOutput(self : * const @This()) std.Build.LazyPath {
      return .{.generated = &self.output_file};
   }

   fn make(step : * std.Build.Step, prog_node : * std.Progress.Node) anyerror!void {
      _ = step;
      _ = prog_node;
      return error.NotImplemented;
   }
};

pub const MeshBundle = struct {
   step           : std.Build.Step,
   contents       : std.ArrayList(Entry),
   generated_file : std.Build.GeneratedFile,

   const MODULE_NAME_GRAPHICS = "graphics";

   pub const Entry = struct {
      parse_step  : * MeshParseStep,
      identifier  : [] const u8,
   };

   pub fn create(owner : * std.Build) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");
      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = "meshbundle",
            .owner   = owner,
            .makeFn  = make,
         }),
         .contents         = std.ArrayList(Entry).init(owner.allocator),
         .generated_file   = .{.step = &self.step},
      };

      return self;
   }

   pub fn addMesh(self : * @This(), mesh_entry : Entry) void {
      const b = self.step.owner;

      const parse_step  = mesh_entry.parse_step;
      const identifier  = b.allocator.dupe(u8, mesh_entry.identifier) catch @panic("out of memory");

      self.contents.append(.{
         .parse_step = parse_step,
         .identifier = identifier,
      }) catch @panic("out of memory");

      self.step.dependOn(&parse_step.step);

      return;
   }

   pub fn getOutput(self : * const @This()) std.Build.LazyPath {
      return .{.generated = &self.generated_file};
   }

   pub fn createModule(self : * @This(), module_graphics : * std.Build.Module) * std.Build.Module {
      return self.step.owner.createModule(.{
         .source_file   = self.getOutput(),
         .dependencies  = &.{
            .{
               .name    = MODULE_NAME_GRAPHICS,
               .module  = module_graphics,
            },
         },
      });
   }

   fn make(step : * std.Build.Step, prog_node : * std.Progress.Node) anyerror!void {
      _ = step;
      _ = prog_node;
      return error.NotImplemented;
   }
};

