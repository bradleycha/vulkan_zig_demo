const std   = @import("std");
const root  = @import("index.zig");

const BUFFERED_IO_SIZE  = 4096;
const _BufferedReader   = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader);

pub fn parseWavefront(allocator : std.mem.Allocator, reader_obj : * _BufferedReader.Reader, reader_mtl : * _BufferedReader.Reader) anyerror!root.BuildMesh {
   // TODO: Implement, this one will be fun!
   _ = allocator;
   _ = reader_obj;
   _ = reader_mtl;
   return error.NotImplemented;
}

