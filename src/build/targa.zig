const std = @import("std");

pub const TargaParseStep = struct {
   step        : std.Build.Step,
   input_file  : std.Build.LazyPath,
   output_file : std.Build.GeneratedFile,

   pub fn create(owner : * std.Build, path : std.Build.LazyPath) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");
      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = owner.fmt("targaparsestep {s}", .{path.getDisplayName()}),
            .owner   = owner,
            .makeFn  = make,
         }),
         .input_file    = path,
         .output_file   = .{.step = &self.step},
      };

      path.addStepDependencies(&self.step);

      return self;
   }

   pub fn getOutput(self : * const @This()) std.Build.LazyPath {
      return .{.generated = &self.output_file};
   }

   fn make(step : * std.Build.Step, prog_node : * std.Progress.Node) anyerror!void {
      const b     = step.owner;
      const self  = @fieldParentPtr(@This(), "step", step);

      // TODO: Implement
      _ = b;
      _ = self;
      _ = prog_node;
      unreachable;
   }
};

pub const TargaBundle = struct {
   step           : std.Build.Step,
   contents       : std.ArrayList(Entry),
   generated_file : std.Build.GeneratedFile,

   pub const Entry = struct {
      parse_step  : * TargaParseStep,
      identifier  : [] const u8,
   };

   pub fn create(owner : * std.Build) * @This() {
      const self = owner.allocator.create(@This()) catch @panic("out of memory");
      self.* = .{
         .step = std.Build.Step.init(.{
            .id      = .custom,
            .name    = "targabundle",
            .owner   = owner,
            .makeFn  = make,
         }),
         .contents         = std.ArrayList(Entry).init(owner.allocator),
         .generated_file   = .{.step = &self.step},
      };

      return self;
   }

   pub fn addTarga(self : * @This(), targa_entry : Entry) void {
      const b = self.step.owner;

      const parse_step  = targa_entry.parse_step;
      const identifier  = b.allocator.dupe(u8, targa_entry.identifier) catch @panic("out of memory");

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

   pub fn createModule(self : * @This()) * std.Build.Module {
      return self.step.owner.createModule(.{
         .source_file   = self.getOutput(),
         .dependencies  = &.{},
      });
   }

   fn make(step : * std.Build.Step, prog_node : * std.Progress.Node) anyerror!void {
      const b     = step.owner;
      const self  = @fieldParentPtr(@This(), "step", step);

      // TODO: Implement
      _ = b;
      _ = self;
      _ = prog_node;
      unreachable;
   }
};

