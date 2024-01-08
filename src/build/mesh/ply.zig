const std   = @import("std");
const root  = @import("index.zig");

const BUFFERED_IO_SIZE  = 4096;
const _BufferedReader   = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader);

pub fn parsePly(allocator : std.mem.Allocator, input : * _BufferedReader.Reader) anyerror!root.BuildMesh {
   const header = try PlyHeader.parse(input);

   // TODO: Implement rest
   _ = allocator;
   _ = header;
   return error.NotImplemented;
}

const LINE_READ_BUFFER_LENGTH = 1024;

fn _readLine(reader : * _BufferedReader.Reader, buf : [] u8) anyerror![] const u8 {
   const NEWLINE = '\n';

   return reader.readUntilDelimiter(buf, NEWLINE);
}

const PlyHeader = struct {
   format   : Format,

   pub const Format = enum {
      binary_little_endian,
      binary_big_endian,
      ascii,
   };

   pub fn parse(reader : * _BufferedReader.Reader) anyerror!@This() {
      var line_read_buffer : [LINE_READ_BUFFER_LENGTH] u8 = undefined;

      try _headerCheckMagic(reader, &line_read_buffer);

      const format = try _headerParseFormat(reader, &line_read_buffer);

      try _headerCheckComment(reader, &line_read_buffer);

      // TODO: Rest
      _ = format;
      return error.PlyHeaderParsingNotImplemented;
   }
};

fn _headerCheckMagic(reader : * _BufferedReader.Reader, buffer : [] u8) anyerror!void {
   const MAGIC = "ply";

   const magic_read = try _readLine(reader, buffer);

   if (std.mem.eql(u8, MAGIC, magic_read) == false) {
      return error.InvalidFiletype;
   }

   return;
}

fn _headerParseFormat(reader : * _BufferedReader.Reader, buffer : [] u8) anyerror!PlyHeader.Format {
   const FORMAT_PREFIX                 = "format";
   const FORMAT_BINARY_LITTLE_ENDIAN   = "binary_little_endian";
   const FORMAT_BINARY_BIG_ENDIAN      = "binary_big_endian";
   const FORMAT_ASCII                  = "ascii";
   const FORMAT_VERSION_MAJOR          = 1;

   const format_line  = try _readLine(reader, buffer);
   var format_tokens  = std.mem.tokenizeAny(u8, format_line, &std.ascii.whitespace);

   const format_token_prefix  = format_tokens.next() orelse return error.MalformedFormat;
   const format_token_type    = format_tokens.next() orelse return error.MalformedFormat;
   const format_token_version = format_tokens.next() orelse return error.MalformedFormat;

   if (format_tokens.next() != null) {
      return error.MalformedFormat;
   }

   if (std.mem.eql(u8, FORMAT_PREFIX, format_token_prefix) == false) {
      return error.MalformedFormat;
   }

   const format_type_map = std.ComptimeStringMap(PlyHeader.Format, &.{
      .{FORMAT_BINARY_LITTLE_ENDIAN,   .binary_little_endian},
      .{FORMAT_BINARY_BIG_ENDIAN,      .binary_big_endian},
      .{FORMAT_ASCII,                  .ascii},
   });

   const format_type = format_type_map.get(format_token_type) orelse return error.UnknownFormatType;

   var format_version_tokens = std.mem.tokenizeScalar(u8, format_token_version, '.');

   // We only care to make sure the major version is 1
   const format_token_version_major = format_version_tokens.next() orelse return error.MalformedFormatVersion;
   const format_version_major       = try std.fmt.parseInt(u8, format_token_version_major, 10);

   if (format_version_major != FORMAT_VERSION_MAJOR) {
      return error.UnsupportedFormatVersion;
   }

   return format_type;
}

fn _headerCheckComment(reader : * _BufferedReader.Reader, buffer : [] u8) anyerror!void {
   const COMMENT = "comment";

   const line = try _readLine(reader, buffer);

   var line_tokens = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);

   const comment_token = line_tokens.next() orelse return error.MalformedComment;

   if (std.mem.eql(u8, COMMENT, comment_token) == false) {
      return error.MalformedComment;
   }

   return;
}

