const std   = @import("std");
const root  = @import("index.zig");

const BUFFERED_IO_SIZE  = 4096;
const _BufferedReader   = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader);

pub fn parseWavefront(allocator : std.mem.Allocator, reader_obj : * _BufferedReader.Reader, reader_mtl : * _BufferedReader.Reader) anyerror!root.BuildMesh {
   var obj = try WavefrontObj.deserializeFromFile(allocator, reader_obj);
   defer obj.destroy(allocator);

   var mtl = try WavefrontMtl.deserializeFromFile(allocator, reader_mtl);
   defer mtl.destroy(allocator);

   // TODO: Implement triangulation, mesh optimization, etc.
   return error.NotImplemented;
}

// We use a max buffer length and make a single allocation instead of
// readUntilDelimiterAlloc() so we aren't allocating in a loop, potentially
// hundreds of thousands of times.  TL:DR - "Performace...gotta go fast!"
const LINE_READ_BUFFER_SIZE = 1024 * 1024;

const WavefrontObj = struct {
   pub fn deserializeFromFile(allocator : std.mem.Allocator, reader : * _BufferedReader.Reader) anyerror!@This() {
      var self = @This(){};
      errdefer self.destroy(allocator);

      const read_buffer = try allocator.alloc(u8, LINE_READ_BUFFER_SIZE);
      defer allocator.free(read_buffer);

      while (reader.readUntilDelimiter(read_buffer, '\n')) |line| {
         try _deserializeObjLine(&self, allocator, line);
      } else |err| switch (err) {
         error.EndOfStream => {},
         else => return err,
      }

      return self;
   }

   pub fn destroy(self : * @This(), allocator : std.mem.Allocator) void {
      _ = self;
      _ = allocator;
      return;
   }
};

fn _mapTokenToParser(
   comptime F     : type,
   comptime map   : [] const struct {token : [] const u8, parser : ? * const F},
   token          : [] const u8,
) anyerror!? * const F {
   const type_info_parser = @typeInfo(F);

   if (type_info_parser != .Fn) {
      @compileError(std.fmt.comptimePrint("expected function type, found {s}", .{@typeName(F)}));
   }

   // Only caveat with ComptimeStringMap for our case is it expects a set of
   // tuples, but we have named struct fields.  We have to reconstruct the struct
   // using a temporary tuple type.  Other than that, yay Standard Library!
   const MapTupleEntry = struct{[] const u8, ? * const F};
   const map_tuples = comptime blk: {
      var map_tuples_uninit : [map.len] MapTupleEntry = undefined;

      for (map, &map_tuples_uninit) |entry, *tuple_entry| {
         tuple_entry.* = .{entry.token, entry.parser};
      }

      break :blk map_tuples_uninit;
   };

   const StringMap = std.ComptimeStringMap(? * const F, &map_tuples);

   return StringMap.get(token) orelse return error.UnknownStatement;
}

fn _deserializeObjLine(obj : * WavefrontObj, allocator : std.mem.Allocator, line : [] const u8) anyerror!void {
   var tokens = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);

   const statement_identifier_token = tokens.next() orelse return;

   const parser_found = try _mapTokenToParser(fn (* WavefrontObj, std.mem.Allocator, * std.mem.TokenIterator(u8, .any)) anyerror!void, &.{
      .{.token = "#",            .parser = null},
      .{.token = "v",            .parser = null},
      .{.token = "vt",           .parser = null},
      .{.token = "vn",           .parser = null},
      .{.token = "vp",           .parser = null},
      .{.token = "cstype",       .parser = null},
      .{.token = "deg",          .parser = null},
      .{.token = "bmat",         .parser = null},
      .{.token = "step",         .parser = null},
      .{.token = "p",            .parser = null},
      .{.token = "l",            .parser = null},
      .{.token = "f",            .parser = null},
      .{.token = "curv",         .parser = null},
      .{.token = "curv2",        .parser = null},
      .{.token = "surf",         .parser = null},
      .{.token = "parm",         .parser = null},
      .{.token = "trim",         .parser = null},
      .{.token = "hole",         .parser = null},
      .{.token = "scrv",         .parser = null},
      .{.token = "sp",           .parser = null},
      .{.token = "end",          .parser = null},
      .{.token = "con",          .parser = null},
      .{.token = "g",            .parser = null},
      .{.token = "s",            .parser = null},
      .{.token = "mg",           .parser = null},
      .{.token = "o",            .parser = null},
      .{.token = "bevel",        .parser = null},
      .{.token = "c_interp",     .parser = null},
      .{.token = "d_interp",     .parser = null},
      .{.token = "lod",          .parser = null},
      .{.token = "usemtl",       .parser = null},
      .{.token = "mtllib",       .parser = null},
      .{.token = "shadow_obj",   .parser = null},
      .{.token = "trace_obj",    .parser = null},
      .{.token = "ctech",        .parser = null},
      .{.token = "stech",        .parser = null},
   }, statement_identifier_token);

   if (parser_found) |parser| {
      try parser(obj, allocator, &tokens);
   }

   return;
}

const WavefrontMtl = struct {
   pub fn deserializeFromFile(allocator : std.mem.Allocator, reader : * _BufferedReader.Reader) anyerror!@This() {
      var self = @This(){};
      errdefer self.destroy(allocator);

      const read_buffer = try allocator.alloc(u8, LINE_READ_BUFFER_SIZE);
      defer allocator.free(read_buffer);

      while (reader.readUntilDelimiter(read_buffer, '\n')) |line| {
         try _deserializeMtlLine(&self, allocator, line);
      } else |err| switch (err) {
         error.EndOfStream => {},
         else => return err,
      }

      return self;
   }

   pub fn destroy(self : * @This(), allocator : std.mem.Allocator) void {
      _ = self;
      _ = allocator;
      return;
   }
};

fn _deserializeMtlLine(mtl : * WavefrontMtl, allocator : std.mem.Allocator, line : [] const u8) anyerror!void {
   var tokens = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);

   const statement_identifier_token = tokens.next() orelse return;

   const parser_found = try _mapTokenToParser(fn (* WavefrontMtl, std.mem.Allocator, * std.mem.TokenIterator(u8, .any)) anyerror!void, &.{
      .{.token = "#",         .parser = null},
      .{.token = "newmtl",    .parser = null},
      .{.token = "Ka",        .parser = null},
      .{.token = "Kd",        .parser = null},
      .{.token = "Ks",        .parser = null},
      .{.token = "Ke",        .parser = null},
      .{.token = "Tf",        .parser = null},
      .{.token = "illum",     .parser = null},
      .{.token = "d",         .parser = null},
      .{.token = "Ns",        .parser = null},
      .{.token = "sharpness", .parser = null},
      .{.token = "Ni",        .parser = null},
      .{.token = "Pr",        .parser = null},
      .{.token = "Pm",        .parser = null},
      .{.token = "Ps",        .parser = null},
      .{.token = "Pc",        .parser = null},
      .{.token = "Pcr",       .parser = null},
      .{.token = "Ke",        .parser = null},
      .{.token = "map_Ka",    .parser = null},
      .{.token = "map_Kd",    .parser = null},
      .{.token = "map_Ke",    .parser = null},
      .{.token = "map_Ks",    .parser = null},
      .{.token = "map_Ns",    .parser = null},
      .{.token = "map_d",     .parser = null},
      .{.token = "disp",      .parser = null},
      .{.token = "decal",     .parser = null},
      .{.token = "bump",      .parser = null},
      .{.token = "refl",      .parser = null},
      .{.token = "map_Pr",    .parser = null},
      .{.token = "map_Pm",    .parser = null},
      .{.token = "map_Ps",    .parser = null},
      .{.token = "map_Ke",    .parser = null},
      .{.token = "aniso",     .parser = null},
      .{.token = "anisor",    .parser = null},
      .{.token = "norm",      .parser = null},
   }, statement_identifier_token);

   if (parser_found) |parser| {
      try parser(mtl, allocator, &tokens);
   }

   return;
}

