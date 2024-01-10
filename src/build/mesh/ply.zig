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
   format         : Format,
   count_vertices : root.BuildMesh.IndexElement,
   count_faces    : u32,

   pub const Format = enum {
      binary_little_endian,
      binary_big_endian,
      ascii,
   };

   pub fn parse(reader : * _BufferedReader.Reader) anyerror!@This() {
      var line_read_buffer : [LINE_READ_BUFFER_LENGTH] u8 = undefined;
      var parse_state = PlyHeaderParseState{};

      try _headerCheckMagic(reader, &line_read_buffer);

      while (true) {
         const line = try _readLine(reader, &line_read_buffer);

         var line_tokens = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);
         const continue_parsing = try _parseHeaderTokens(&parse_state, &line_tokens);

         if (continue_parsing == false) {
            break;
         }
      }

      const self = try parse_state.unwrap();

      return self;
   }
};

fn _headerCheckMagic(reader : * _BufferedReader.Reader, buffer : [] u8) anyerror!void {
   const MAGIC  = "ply";

   const line_magic = try _readLine(reader, buffer);

   if (std.mem.eql(u8, line_magic, MAGIC) == false) {
      return error.InvalidFileType;
   }

   return;
}

const PlyHeaderParseState = struct {
   format            : ? PlyHeader.Format             = null,
   current_element   : Element                        = .none,
   count_vertices    : ? root.BuildMesh.IndexElement  = null,
   count_faces       : ? u32                          = null,

   pub const Element = enum {
      none,
      unknown,
      vertices,
      faces,
   };

   pub fn unwrap(self : * const @This()) anyerror!PlyHeader {
      const format = self.format orelse return error.NoFormatSpecified;


      const count_vertices = self.count_vertices orelse return error.NoVertexCountSpecified;
      if (count_vertices == 0) {
         return error.ZeroVerticesPresent;
      }

      const count_faces = self.count_faces orelse return error.NoFaceCountSpecified;
      if (count_faces == 0) {
         return error.ZeroFacesPresent;
      }

      return PlyHeader{
         .format           = format,
         .count_vertices   = count_vertices,
         .count_faces      = count_faces,
      };
   }
};

fn _parseHeaderTokens(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   // Return without error because this could just be an empty line.
   const statement = tokens.next() orelse return true;

   const parser_map = std.ComptimeStringMap(* const fn (* PlyHeaderParseState, * std.mem.TokenIterator(u8, .any)) anyerror!bool, &.{
      .{"format",       _parseHeaderFormat},
      .{"comment",      _parseHeaderComment},
      .{"element",      _parseHeaderElement},
      .{"property",     _parseHeaderProperty},
      .{"end_header",   _parseHeaderEnd},
   });

   const parser = parser_map.get(statement) orelse return error.InvalidHeaderStatement;

   return parser(state, tokens);
}

fn _parseHeaderFormat(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   if (state.format != null) {
      return error.DuplicateFormatSpecifiers;
   }

   const format_token = tokens.next() orelse return error.MissingFormatSpecifierType;

   const format_token_map = std.ComptimeStringMap(PlyHeader.Format, &.{
      .{"binary_little_endian",  .binary_little_endian},
      .{"binary_big_endian",     .binary_big_endian},
      .{"ascii",                 .ascii},
   });

   const format = format_token_map.get(format_token) orelse return error.InvalidFormatSpecifierType;

   const version_token = tokens.next() orelse return error.IncompleteFormatSpecifier;

   if (tokens.next() != null) {
      return error.UnexpectedTokensAfterFormatVersion;
   }

   var tokens_version = std.mem.tokenizeScalar(u8, version_token, '.');

   const version_major_token  = tokens_version.next() orelse return error.MissingFormatSpecifierMajorVersion;
   const version_minor_token  = tokens_version.next() orelse return error.MissingFormatSpecifierMinorVersion;

   if (tokens_version.next() != null) {
      return error.UnexpectedTokensAfterFormatVersion;
   }

   const version_major = std.fmt.parseInt(u8, version_major_token, 10) catch return error.InvalidFormatSpecifierMajorVersion;
   const version_minor = std.fmt.parseInt(u8, version_minor_token, 10) catch return error.InvalidFormatSpecifierMinorVersion;

   if (version_major != 1) {
      return error.UnsupportedFormatSpecifierMajorVersion;
   }

   if (version_minor != 0) {
      return error.UnsupportedFormatSpecifierMinorVersion;
   }

   state.format = format;
   return true;
}

fn _parseHeaderComment(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   _ = state;
   _ = tokens;
   return true;
}

fn _parseHeaderElement(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   const element_token = tokens.next() orelse return error.MissingElementType;

   const element_map = std.ComptimeStringMap(* const fn (* PlyHeaderParseState, * std.mem.TokenIterator(u8, .any)) anyerror!bool, &.{
      .{"vertex", _parseHeaderElementVertex},
      .{"face",   _parseHeaderElementFace},
   });

   const parser = element_map.get(element_token) orelse _parseHeaderElementUnknown;

   return parser(state, tokens);
}

fn _parseHeaderElementVertex(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   if (state.count_vertices != null) {
      return error.DuplicateVertexElementDefinition;
   }

   const count = try _parseHeaderElementCountGeneric(root.BuildMesh.IndexElement, tokens);

   state.current_element   = .vertices;
   state.count_vertices    = count;
   return true;
}

fn _parseHeaderElementFace(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   if (state.count_faces != null) {
      return error.DuplicateFaceElementDefinition;
   }

   const count = try _parseHeaderElementCountGeneric(u32, tokens);

   state.current_element   = .faces;
   state.count_faces       = count;
   return true;
}

fn _parseHeaderElementUnknown(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   _ = try _parseHeaderElementCountGeneric(u32, tokens);

   state.current_element = .unknown;
   return true;
}

fn _parseHeaderElementCountGeneric(comptime T : type, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!T {
   const count_token = tokens.next() orelse return error.MissingElementCount;

   if (tokens.next() != null) {
      return error.UnexpectedTokensAfterElementCount;
   }

   const count = std.fmt.parseInt(T, count_token, 10) catch return error.InvalidElementCount;

   return count;
}

fn _parseHeaderProperty(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   const parser : * const fn (* PlyHeaderParseState, * std.mem.TokenIterator(u8, .any)) anyerror!bool = blk: {
      switch (state.current_element) {
         .none       => return error.PropertyDefinitionBeforeElements,
         .vertices   => break :blk _parseHeaderPropertyVertex,
         .faces      => break :blk _parseHeaderPropertyFace,
         .unknown    => break :blk _parseHeaderPropertyUnknown,
      }
   };
   
   return parser(state, tokens);
}

fn _parseHeaderPropertyVertex(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   // TODO: Implement
   _ = state;
   _ = tokens;
   return true;
}

fn _parseHeaderPropertyFace(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   // TODO: Implement
   _ = state;
   _ = tokens;
   return true;
}

fn _parseHeaderPropertyUnknown(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   // TODO: Implement
   _ = state;
   _ = tokens;
   return true;
}

fn _parseHeaderEnd(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   _ = state;

   if (tokens.next() != null) {
      return error.UnexpectedTokensAfterEndHeaderStatement;
   }

   return false;
}

