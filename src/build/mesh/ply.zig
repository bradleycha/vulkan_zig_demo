const std   = @import("std");
const root  = @import("index.zig");

const BUFFERED_IO_SIZE  = 4096;
const _BufferedReader   = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader);

pub fn parsePly(allocator : std.mem.Allocator, reader : * _BufferedReader.Reader) anyerror!root.BuildMesh {
   _ = allocator;
   _ = reader;
   return error.NotImplemented;
}

