const std   = @import("std");
const root  = @import("index.zig");

const LINE_READ_BUFFER_LENGTH = 1024;
const BUFFERED_IO_SIZE        = 4096;
const _BufferedReader         = std.io.BufferedReader(BUFFERED_IO_SIZE, std.fs.File.Reader);

pub fn parsePly(allocator : std.mem.Allocator, input : * _BufferedReader.Reader) anyerror!root.BuildMesh {
   var line_read_buffer : [LINE_READ_BUFFER_LENGTH] u8 = undefined;

   const header = try PlyHeader.parse(input, &line_read_buffer);

   const buffer_vertices = try allocator.alloc(root.BuildMesh.Vertex, header.count_vertices);
   errdefer allocator.free(buffer_vertices);

   // We know the amount of vertices from the header, but unfortunately for the
   // indices the header only tells us the number of triangle fans, but not the
   // amount of indices in each triangle fan.  Thus, we need dynamically-sized
   // arrays for our index buffer.  I attempt to mitigate this by initializing
   // with capacity to hold all the indices if all the faces are a single triangle.

   var arraylist_indices = try std.ArrayListUnmanaged(root.BuildMesh.IndexElement).initCapacity(allocator, header.count_faces * 3);
   errdefer arraylist_indices.deinit(allocator);

   try _readPlyMesh(allocator, input, &header, &line_read_buffer, buffer_vertices, &arraylist_indices);

   const buffer_indices = try arraylist_indices.toOwnedSlice(allocator);

   return .{
      .vertices   = buffer_vertices,
      .indices    = buffer_indices,
   };
}

fn _readLine(reader : * _BufferedReader.Reader, buf : [] u8) anyerror![] const u8 {
   const NEWLINE = '\n';

   return reader.readUntilDelimiter(buf, NEWLINE);
}

const PlyTypeTag = enum {
   char,
   uchar,
   short,
   ushort,
   int,
   uint,
   float,
   double,
   list,

   pub fn toZigType(comptime self : @This()) type {
      switch (self) {
         .char    => return i8,
         .uchar   => return u8,
         .short   => return i16,
         .ushort  => return u16,
         .int     => return i32,
         .uint    => return u32,
         .float   => return f32,
         .double  => return f64,
         .list    => @compileError("list type can't be directly converted to a zig type"),
      }

      unreachable;
   }
};

const PlyType = union(PlyTypeTag) {
   char     : void,
   uchar    : void,
   short    : void,
   ushort   : void,
   int      : void,
   uint     : void,
   float    : void,
   double   : void,
   list     : @This().List,

   pub const List = struct {
      count    : PlyTypeTag,  // can't be list
      element  : PlyTypeTag,  // can't be list
   };
};

const PlyFormat = enum {
   binary_little_endian,
   binary_big_endian,
   ascii,
};

const PlyVertexPropertyTag = enum {
   position_x,
   position_y,
   position_z,
   normal_x,
   normal_y,
   normal_z,
   texture_mapping_u,
   texture_mapping_v,
   color_r,
   color_g,
   color_b,
   color_a,
};

const PlyVertexProperty = struct {
   ty    : PlyType,
   tag   : PlyVertexPropertyTag,
};

const MAX_VERTEX_PROPERTIES = @typeInfo(PlyVertexPropertyTag).Enum.fields.len;

const PlyHeader = struct {
   format                     : PlyFormat,
   count_vertices             : root.BuildMesh.IndexElement,
   count_faces                : u32,
   face_list_type             : PlyType,
   vertex_properties_buffer   : [MAX_VERTEX_PROPERTIES] PlyVertexProperty,
   vertex_properties_count    : usize,
   vertices_first             : bool,

   pub fn parse(reader : * _BufferedReader.Reader, line_read_buffer : [] u8) anyerror!@This() {
      var parse_state = PlyHeaderParseState{};

      try _headerCheckMagic(reader, line_read_buffer);

      while (true) {
         const line = try _readLine(reader, line_read_buffer);

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
   format                     : ? PlyFormat                                = null,
   current_element            : Element                                    = .none,
   current_property_index     : usize                                      = 0,
   count_vertices             : ? root.BuildMesh.IndexElement              = null,
   count_faces                : ? u32                                      = null,
   face_list_type             : ? PlyType                                  = null,
   vertex_properties_buffer   : [MAX_VERTEX_PROPERTIES] PlyVertexProperty  = undefined,
   vertex_properties_count    : usize                                      = 0,
   vertices_first             : bool                                       = undefined,

   pub const Element = enum {
      none,
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

      const face_list_type = self.face_list_type orelse return error.NoFacePropertySpecified;

      const vertex_properties_buffer   = self.vertex_properties_buffer;
      const vertex_properties_count    = self.vertex_properties_count;

      if (vertex_properties_count == 0) {
         return error.ZeroVertexPropertiesPresent;
      }

      const vertices_first = self.vertices_first;

      return PlyHeader{
         .format                    = format,
         .count_vertices            = count_vertices,
         .count_faces               = count_faces,
         .face_list_type            = face_list_type,
         .vertex_properties_buffer  = vertex_properties_buffer,
         .vertex_properties_count   = vertex_properties_count,
         .vertices_first            = vertices_first,
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

   const format_token_map = std.ComptimeStringMap(PlyFormat, &.{
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

   const parser = element_map.get(element_token) orelse return error.InvalidElementType;

   const should_continue = parser(state, tokens);

   state.current_property_index = 0;
   
   return should_continue;
}

fn _parseHeaderElementVertex(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   if (state.count_vertices != null) {
      return error.DuplicateVertexElementDefinition;
   }

   const count = try _parseHeaderElementCountGeneric(root.BuildMesh.IndexElement, tokens);

   if (state.current_element == .none) {
      @setCold(true);
      state.vertices_first = true;
   }

   state.current_element   = .vertices;
   state.count_vertices    = count;
   return true;
}

fn _parseHeaderElementFace(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   if (state.count_faces != null) {
      return error.DuplicateFaceElementDefinition;
   }

   const count = try _parseHeaderElementCountGeneric(u32, tokens);

   if (state.current_element == .none) {
      @setCold(true);
      state.vertices_first = false;
   }

   state.current_element   = .faces;
   state.count_faces       = count;
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
   const parser : * const fn (* PlyHeaderParseState, * std.mem.TokenIterator(u8, .any), PlyType) anyerror!bool = blk: {
      switch (state.current_element) {
         .none       => return error.PropertyDefinitionBeforeElements,
         .vertices   => break :blk _parseHeaderPropertyVertex,
         .faces      => break :blk _parseHeaderPropertyFace,
      }
   };

   const ty = try _parseTokensToType(tokens);
   
   const should_continue = parser(state, tokens, ty);

   state.current_property_index += 1;

   return should_continue;
}

fn _parseTokensToType(tokens : * std.mem.TokenIterator(u8, .any)) anyerror!PlyType {
   const base_token = tokens.next() orelse return error.MissingTypeSpecifier;

   const map_type_tag = std.ComptimeStringMap(PlyTypeTag, &.{
      .{"char",   .char},
      .{"uchar",  .uchar},
      .{"short",  .short},
      .{"ushort", .ushort},
      .{"int",    .int},
      .{"uint",   .uint},
      .{"float",  .float},
      .{"double", .double},
      .{"list",   .list},
   });

   const base = map_type_tag.get(base_token) orelse return error.InvalidTypeSpecifier;

   switch (base) {
      .list => {},
      inline else => |tag| return tag,
   }

   const count_token    = tokens.next() orelse return error.MissingListCountTypeSpecifier;
   const element_token  = tokens.next() orelse return error.MissingListElementTypeSpecifier;

   const count    = map_type_tag.get(count_token)     orelse return error.InvalidListCountTypeSpecifier;
   const element  = map_type_tag.get(element_token)   orelse return error.InvalidListElementTypeSpecifier;

   return .{.list = .{.count = count, .element = element}};
}

fn _parseHeaderPropertyVertex(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any), ty : PlyType) anyerror!bool {
   const property_token = tokens.next() orelse return error.MissingVertexPropertyIdentifier;

   if (tokens.next() != null) {
      return error.UnexpectedTokensAfterVertexPropertyIdentifier;
   }

   const property_map = std.ComptimeStringMap(PlyVertexPropertyTag, &.{
      .{"x",      .position_x},
      .{"y",      .position_y},
      .{"z",      .position_z},
      .{"nx",     .normal_x},
      .{"ny",     .normal_y},
      .{"nz",     .normal_z},
      .{"u",      .texture_mapping_u},
      .{"v",      .texture_mapping_v},
      .{"s",      .texture_mapping_u},
      .{"t",      .texture_mapping_v},
      .{"red",    .color_r},
      .{"green",  .color_g},
      .{"blue",   .color_b},
      .{"alpha",  .color_a},
   });

   const property = property_map.get(property_token) orelse return error.InvalidVertexPropertyIdentifier;

   // Ensures we never duplicate properties, which by extension also acts as a
   // safety check to prevent buffer overruns.
   for (state.vertex_properties_buffer[0..state.vertex_properties_count]) |property_existing| {
      if (property_existing.tag == property) {
         return error.DuplicateVertexPropertyIdentifier;      
      }
   }

   state.vertex_properties_buffer[state.vertex_properties_count] = .{
      .ty   = ty,
      .tag  = property,
   };
   state.vertex_properties_count += 1;

   return true;
}

fn _parseHeaderPropertyFace(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any), ty : PlyType) anyerror!bool {
   const property_token = tokens.next() orelse return error.MissingFacePropertyIdentifier;

   if (tokens.next() != null) {
      return error.UnexpectedTokensAfterFacePropertyIdentifier;
   }

   const property_map = std.ComptimeStringMap(void, &.{
      .{"vertex_index",    {}},
      .{"vertex_indices",  {}},
   });

   _ = property_map.get(property_token) orelse return error.InvalidFacePropertyIdentifier;

   if (ty != .list) {
      return error.InvalidFacePropertyTypeForIdentifier;
   }

   if (state.face_list_type != null) {
      return error.DuplicateFacePropertyVertexIndicesIdentifier;
   }

   state.face_list_type = ty;
   return true;
}

fn _parseHeaderEnd(state : * PlyHeaderParseState, tokens : * std.mem.TokenIterator(u8, .any)) anyerror!bool {
   _ = state;

   if (tokens.next() != null) {
      return error.UnexpectedTokensAfterEndHeaderStatement;
   }

   return false;
}

fn _readPlyMesh(allocator : std.mem.Allocator, reader : * _BufferedReader.Reader, header : * const PlyHeader, line_read_buffer : [] u8, buffer_vertices : [] root.BuildMesh.Vertex, arraylist_indices : * std.ArrayListUnmanaged(root.BuildMesh.IndexElement)) anyerror!void {
   switch (header.vertices_first) {
      true => {
         try _readPlyMeshVertices(reader, header, line_read_buffer, buffer_vertices);
         try _readPlyMeshIndices(allocator, reader, header, line_read_buffer, arraylist_indices);
      },
      false => {
         try _readPlyMeshIndices(allocator, reader, header, line_read_buffer, arraylist_indices);
         try _readPlyMeshVertices(reader, header, line_read_buffer, buffer_vertices);
      },
   }

   return;
}

fn _readPlyMeshVertices(reader : * _BufferedReader.Reader, header : * const PlyHeader, line_read_buffer : [] u8, buffer_vertices : [] root.BuildMesh.Vertex) anyerror!void {
   for (buffer_vertices) |*vertex_out| {
      // Pre-initialize with defaults because the given vertex format could be
      // missing required fields.
      vertex_out.* = .{
         .color      = .{1.0, 1.0, 1.0, 1.0},
         .sample     = .{0.0, 0.0},
         .position   = .{0.0, 0.0, 0.0},
         .normal     = .{0.0, 1.0, 0.0},
      };

      try _readPlyMeshVertex(reader, header, line_read_buffer, vertex_out);
   }

   return;
}

fn _readPlyMeshVertex(reader : * _BufferedReader.Reader, header : * const PlyHeader, line_read_buffer : [] u8, vertex_out : * root.BuildMesh.Vertex) anyerror!void {
   switch (header.format) {
      .binary_little_endian   => try _readPlyMeshVertexBinary(reader, header, .Little, vertex_out),
      .binary_big_endian      => try _readPlyMeshVertexBinary(reader, header, .Big, vertex_out),
      .ascii                  => try _readPlyMeshVertexAscii(reader, header, line_read_buffer, vertex_out),
   }

   return;
}


fn _readPlyMeshVertexBinary(reader : * _BufferedReader.Reader, header : * const PlyHeader, endianess : std.builtin.Endian, vertex_out : * root.BuildMesh.Vertex) anyerror!void {
   for (header.vertex_properties_buffer[0..header.vertex_properties_count]) |*property| {
      try _readPlyMeshVertexPropertyBinary(reader, property, endianess, vertex_out);
   }
   
   return;
}

fn _readPlyMeshVertexPropertyBinary(reader : * _BufferedReader.Reader, property : * const PlyVertexProperty, endianess : std.builtin.Endian, vertex_out : * root.BuildMesh.Vertex) anyerror!void {
   switch (@as(PlyTypeTag, property.ty)) {
      .list => unreachable,
      inline else => |tag| {
         const ty = PlyTypeTag.toZigType(tag);
         try _readPlyMeshVertexPropertyTypedBinary(ty, reader, property.tag, endianess, vertex_out);
      }
   }

   return;
}

fn _readPlyMeshVertexPropertyTypedBinary(comptime T : type, reader : * _BufferedReader.Reader, property_tag : PlyVertexPropertyTag, endianess : std.builtin.Endian, vertex_out : * root.BuildMesh.Vertex) anyerror!void {
   const value = blk: {
      switch (T) {
         f32 => {
            const bits = try reader.readInt(u32, endianess);
            break :blk @as(f32, @bitCast(bits));
         },
         f64 => {
            const bits = try reader.readInt(u64, endianess);
            break :blk @as(f64, @bitCast(bits));
         },
         else => {
            break :blk try reader.readInt(T, endianess);
         },
      }
   };
   
   return _storeParsedVertexProperty(T, value, property_tag, vertex_out);
}

fn _readPlyMeshVertexAscii(reader : * _BufferedReader.Reader, header : * const PlyHeader, line_read_buffer : [] u8, vertex_out : * root.BuildMesh.Vertex) anyerror!void {
   const line = try _readLine(reader, line_read_buffer);

   var tokens = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);

   for (header.vertex_properties_buffer[0..header.vertex_properties_count]) |*property| {
      const token = tokens.next() orelse return error.MalformedVertex;
      try _readPlyMeshVertexPropertyAscii(property, token, vertex_out);
   }

   if (tokens.next() != null) {
      return error.UnexpectedDataAfterVertex;
   }

   return;
}

fn _readPlyMeshVertexPropertyAscii(property : * const PlyVertexProperty, token : [] const u8, vertex_out : * root.BuildMesh.Vertex) anyerror!void {
   switch (@as(PlyTypeTag, property.ty)) {
      .list => unreachable,
      inline else => |tag| {
         const ty = PlyTypeTag.toZigType(tag);
         try _readPlyMeshVertexPropertyTypedAscii(ty, property.tag, token, vertex_out);
      }
   }

   return;
}

fn _readPlyMeshVertexPropertyTypedAscii(comptime T : type, property_tag : PlyVertexPropertyTag, token : [] const u8, vertex_out : * root.BuildMesh.Vertex) anyerror!void {
   const value = blk: {
      switch (T) {
         f32, f64 => {
            break :blk try std.fmt.parseFloat(T, token);
         },
         else => {
            break :blk try std.fmt.parseInt(T, token, 10);
         },
      }
   };
   
   return _storeParsedVertexProperty(T, value, property_tag, vertex_out);
}

fn _storeParsedVertexProperty(comptime T : type, value : T, property_tag : PlyVertexPropertyTag, vertex_out : * root.BuildMesh.Vertex) void {
   switch (property_tag) {
      .position_x          => _storeParsedVertexPositionX(T, value, vertex_out),
      .position_y          => _storeParsedVertexPositionY(T, value, vertex_out),
      .position_z          => _storeParsedVertexPositionZ(T, value, vertex_out),
      .normal_x            => _storeParsedVertexNormalX(T, value, vertex_out),
      .normal_y            => _storeParsedVertexNormalY(T, value, vertex_out),
      .normal_z            => _storeParsedVertexNormalZ(T, value, vertex_out),
      .texture_mapping_u   => _storeParsedVertexTextureMappingU(T, value, vertex_out),
      .texture_mapping_v   => _storeParsedVertexTextureMappingV(T, value, vertex_out),
      .color_r             => _storeParsedVertexColorR(T, value, vertex_out),
      .color_g             => _storeParsedVertexColorG(T, value, vertex_out),
      .color_b             => _storeParsedVertexColorB(T, value, vertex_out),
      .color_a             => _storeParsedVertexColorA(T, value, vertex_out),
   }

   return;
}

fn _convertType(comptime T : type, comptime U : type, value : T) U {
   const info_t = @typeInfo(T);
   const info_u = @typeInfo(U);

   if (info_t == .Int and info_u == .Int) {
      return @as(U, @intCast(value));
   }

   if (info_t == .Float and info_u == .Float) {
      return @as(U, @floatCast(value));
   }

   if (info_t == .Int and info_u == .Float) {
      return @as(U, @floatFromInt(value));
   }

   if (info_t == .Float and info_u == .Int) {
      return @as(U, @intFromFloat(value));
   }

   @compileError("invalid type conversion");
}

fn _storeParsedVertexPositionX(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.position[0] = value_converted;
   return;
}

fn _storeParsedVertexPositionY(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.position[1] = value_converted;
   return;
}

fn _storeParsedVertexPositionZ(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.position[2] = value_converted;
   return;
}

fn _storeParsedVertexNormalX(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.normal[0] = value_converted;
   return;
}

fn _storeParsedVertexNormalY(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.normal[1] = value_converted;
   return;
}

fn _storeParsedVertexNormalZ(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.normal[2] = value_converted;
   return;
}

fn _storeParsedVertexTextureMappingU(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.sample[0] = value_converted;
   return;
}

fn _storeParsedVertexTextureMappingV(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.sample[1] = value_converted;
   return;
}

fn _storeParsedVertexColorR(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.color[0] = value_converted;
   return;
}

fn _storeParsedVertexColorG(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.color[1] = value_converted;
   return;
}

fn _storeParsedVertexColorB(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.color[2] = value_converted;
   return;
}

fn _storeParsedVertexColorA(comptime T : type, value : T, vertex_out : * root.BuildMesh.Vertex) void {
   const value_converted = _convertType(T, f32, value);

   vertex_out.color[3] = value_converted;
   return;
}

fn _readPlyMeshIndices(allocator : std.mem.Allocator, reader : * _BufferedReader.Reader, header : * const PlyHeader, line_read_buffer : [] u8, arraylist_indices : * std.ArrayListUnmanaged(root.BuildMesh.IndexElement)) anyerror!void {
   // TODO: Implement
   _ = allocator;
   _ = reader;
   _ = header;
   _ = line_read_buffer;
   _ = arraylist_indices;
   return error.IndexReadingNotImplemented;
}

