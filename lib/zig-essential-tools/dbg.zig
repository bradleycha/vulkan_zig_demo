const std      = @import("std");
const builtin  = @import("builtin");

/// Determines whether debug functions should be enabled.  This will be set to
/// true in Debug builds, but false in any kind of ReleaseXXXX build.
/// Debug-only functions will be stubbed out when disabled, so no code
/// modifications are required to strip out debug-only functions in release
/// builds.
pub const enable = builtin.mode == .Debug;

/// Simple debug-only assertions.  Will panic the program if the condition is
/// false.
pub fn assert(condition : bool) void {
   if (comptime enable == false) {
      return;
   }

   if (condition == false) {
      @panic("debug assertion failed");
   }

   return;
}

/// Standard library style debug-only logger.  Follows the same syntax as the
/// standard library's log function.  This is fully thread-safe, so no extra
/// work is required for thread synchronization.
pub const log = struct {
   var _LogLock      = std.Thread.Mutex{};
   var _LevelMinimum = @This().Level.DefaultMinimum;
   var _LevelMaximum = @This().Level.DefaultMaximum;

   /// Message level used to mark severity of a logger message.  Order is from
   /// least to most servere.
   pub const Level = enum {
      info,
      warn,
      err,

      pub const DefaultMinimum = blk: {
         const fields = @typeInfo(@This()).Enum.fields;
         break :blk @field(@This(), fields[0].name);
      };
      pub const DefaultMaximum = blk: {
         const fields = @typeInfo(@This()).Enum.fields;
         break :blk @field(@This(), fields[fields.len - 1].name);
      };

      pub fn asText(comptime self : @This()) [] const u8 {
         switch (self) {
            .info => return "info",
            .warn => return "warning",
            .err  => return "error",
         }
      }

      fn _variantIndex(self : @This()) usize {
         const fields = @typeInfo(@This()).Enum.fields;
         inline for (fields, 0..) |field, i| {
            const variant = @field(@This(), field.name);
            if (variant == self) {
               return i;
            }
         }
         unreachable;
      }

      pub fn compare(
         lhs   : @This(),
         op    : std.math.CompareOperator,
         rhs   : @This(),
      ) bool {
         const lhs_idx = lhs._variantIndex();
         const rhs_idx = rhs._variantIndex();

         return std.math.compare(lhs_idx, op, rhs_idx);
      }
   };

   pub fn defaultLog(
      comptime message_level  : @This().Level,
      comptime format         : [] const u8,
      args                    : anytype,
   ) void {
      if (comptime enable == false) {
         return;
      }

      @This()._LogLock.lock();
      defer @This()._LogLock.unlock();

      if (@This().Level.compare(message_level, .lt, @This()._LevelMinimum)) {
         return;
      }
      if (@This().Level.compare(message_level, .gt, @This()._LevelMaximum)) {
         return;
      }

      const stream = comptime std.io.getStdErr().writer();
      const prefix = comptime "[debug] " ++ message_level.asText() ++ ": ";
      const suffix = comptime "\n";

      stream.print(prefix ++ format ++ suffix, args) catch {};

      return;
   }

   pub fn info(comptime format : [] const u8, args : anytype) void {
      return @This().defaultLog(.info, format, args);
   }

   pub fn warn(comptime format : [] const u8, args : anytype) void {
      return @This().defaultLog(.warn, format, args);
   }

   pub fn err(comptime format : [] const u8, args : anytype) void {
      return @This().defaultLog(.err, format, args);
   }

   /// Sets the minimum printable log level.  Any message with a level lower
   /// than the provided level will be discarded.  Defaults to have no bound.
   pub fn setLevelMinimum(level : @This().Level) void {
      if (comptime enable == false) {
         return;
      }

      @This()._LogLock.lock();
      defer @This()._LogLock.unlock();

      @This()._LevelMinimum = level;
      return;
   }

   /// Sets the maximum printable log level.  Any message with a level higher
   /// than the provided level will be discarded.  Defaults to have no bound.
   pub fn setLevelMaximum(level : @This().Level) void {
      if (comptime enable == false) {
         return;
      }

      @This()._LogLock.lock();
      defer @This()._LogLock.unlock();

      @This()._LevelMaximum = level;
      return;
   }
};

