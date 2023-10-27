const std      = @import("std");
const builtin  = @import("builtin");

pub const PresentBackend = enum {
   wayland,

   pub fn targetDefault(b : * std.Build, target_platform : * const std.zig.CrossTarget) @This() {
      const os_tag = target_platform.os_tag orelse builtin.os.tag;

      switch (os_tag) {
         .linux   => return .wayland,
         else     => @panic(b.fmt("no default present backend available for target {}", .{os_tag})),
      }

      unreachable;
   }

   pub fn addCompileStepDependencies(self : @This(), owner : * std.Build, compile_step : * std.Build.Step.Compile) void {
      switch (self) {
         .wayland => return _addWaylandCompileStepDependencies(owner, compile_step),
      }

      unreachable;
   }

   fn _addWaylandCompileStepDependencies(owner : * std.Build, compile_step : * std.Build.Step.Compile) void {
      const wl_scanner_xdg_shell = WaylandScannerStep.create(owner, &.{
         .input_xml        = .{.path = "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"},
         .output_basename  = "xdg-shell",
      });

      compile_step.step.dependOn(&wl_scanner_xdg_shell.step);

      const cflags : [] [] const u8 = blk: {
         switch (compile_step.optimize) {
            .Debug => break :blk &.{

            },
            .ReleaseSafe => break :blk &.{

            },
            .ReleaseSmall => break :blk &.{

            },
            .ReleaseFast => break :blk &.{

            },
         }
      };

      compile_step.addCSourceFile(.{
         .file    = wl_scanner_xdg_shell.getOutputGlue(),
         .flags   = cflags,
      });

      compile_step.addIncludePath(wl_scanner_xdg_shell.getOutputDir());
      
      compile_step.linkSystemLibrary("wayland-client");

      return;
   }
};

pub const WaylandScannerStep = struct {
   step              : std.Build.Step,
   input_xml         : std.Build.LazyPath,
   output_basename   : ? [] u8,
   output_dir        : std.Build.GeneratedFile,
   output_glue       : std.Build.GeneratedFile,
   output_header     : std.Build.GeneratedFile,

   pub const CreateInfo = struct {
      input_xml         : std.Build.LazyPath,
      output_basename   : ? [] const u8 = null,
   };

   pub fn create(owner : * std.Build, create_info : * const CreateInfo) * @This() {
      const output_basename_owned : ? [] u8 = blk: {
         if (create_info.output_basename) |output_basename_unwrapped| {
            break :blk owner.allocator.dupe(u8, output_basename_unwrapped) catch @panic("out of memory");
         } else {
            break :blk null;
         }
      };

      const self = owner.allocator.create(@This()) catch @panic("out of memory");

      self.* = .{
         .step             = std.Build.Step.init(.{
            .id      = .custom,
            .name    = owner.fmt("wayland-scanner {s}", .{create_info.input_xml.getDisplayName()}),
            .owner   = owner,
            .makeFn  = make,
         }),
         .input_xml        = create_info.input_xml,
         .output_basename  = output_basename_owned,
         .output_dir       = std.Build.GeneratedFile{.step = &self.step},
         .output_glue      = std.Build.GeneratedFile{.step = &self.step},
         .output_header    = std.Build.GeneratedFile{.step = &self.step},
      };

      create_info.input_xml.addStepDependencies(&self.step);

      return self;
   }

   pub fn getOutputDir(self : * const @This()) std.Build.LazyPath {
      return .{.generated = &self.output_dir};
   }

   pub fn getOutputGlue(self : * const @This()) std.Build.LazyPath {
      return .{.generated = &self.output_glue};
   }

   pub fn getOutputHeader(self : * const @This()) std.Build.LazyPath {
      return .{.generated = &self.output_header};
   }

   fn make(step : * std.Build.Step, prog_node : * std.Progress.Node) anyerror!void {
      const b     = step.owner;
      const self  = @fieldParentPtr(@This(), "step", step);

      var man = b.cache.obtain();
      defer man.deinit();

      man.hash.add(@as(u32, 0x0da23fb7));

      const input_xml = self.input_xml.getPath(b);
      _ = try man.addFile(input_xml, null);
      man.hash.addOptionalBytes(self.output_basename);
      
      const cache_hit   = try step.cacheHit(&man);
      const digest      = man.final();

      const basename = blk: {
         if (self.output_basename) |output_basename| {
            break :blk output_basename;
         } else {
            break :blk std.fs.path.stem(input_xml);
         }
      };

      const output_dir     = try b.cache_root.join(b.allocator, &.{"o", &digest});
      const output_glue    = try std.fs.path.join(b.allocator, &.{output_dir, b.fmt("{s}.c", .{basename})});
      const output_header  = try std.fs.path.join(b.allocator, &.{output_dir, b.fmt("{s}.h", .{basename})});

      if (cache_hit == true) {
         self.output_dir.path    = output_dir;
         self.output_glue.path   = output_glue;
         self.output_header.path = output_header;
         return;
      }

      std.fs.makeDirAbsolute(output_dir) catch |err| {
         if (err != error.PathAlreadyExists) {
            return err;
         }
      };

      const WAYLAND_SCANNER = "wayland-scanner";

      const argv_glue = [_] [] const u8 {
         WAYLAND_SCANNER,
         "private-code",
         input_xml,
         output_glue,
      };

      const argv_header = [_] [] const u8 {
         WAYLAND_SCANNER,
         "client-header",
         input_xml,
         output_header,
      };

      _ = try step.evalZigProcess(&argv_glue, prog_node);
      _ = try step.evalZigProcess(&argv_header, prog_node);

      self.output_dir.path    = output_dir;
      self.output_glue.path   = output_glue;
      self.output_header.path = output_header;
      return;
   }
};

