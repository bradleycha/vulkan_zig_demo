const std = @import("std");

/// Formats an error set member into a string form which fits into English
/// sentences easier.  This is useful combined with inline switch to quickly
/// and effortlessly format error strings for every possible error in the given
/// set.  This is done by making the entire error name lowercase, inserting
/// spaces between lower and upper case letters and replacing non-alphanumeric
/// characters with spaces.  Numbers are prefixed with a pound sign.  For
/// example, "ThisIsAnError" gets transformed into "this is an error", and
/// "some_error_2_1" turns into "some error #2 #1".  This generates the strings
/// at compile-time, so there is no runtime cost to this function.
pub fn errorToString(comptime err : anytype) [] const u8 {
   // Required comptime block for stupid reasons
   comptime {
      const err_type = @TypeOf(err);
      const err_info = @typeInfo(err_type);
      if (err_info != .ErrorSet) {
         @compileError("expected error set, found " ++ err_type);
      }

      const name_raw = @errorName(err);
      var buf : [] const u8 = "";

      if (name_raw.len == 0) {
         return buf;
      }

      // First character is special - don't insert a leading space if we need to
      // do anything to it
      buf = buf ++ blk: {
         const c = name_raw[0];

         if (std.ascii.isUpper(c) == true) {
            break :blk [1] u8 {std.ascii.toLower(c)};
         }
         if (std.ascii.isLower(c) == true) {
            break :blk [1] u8 {c};
         }
         if (std.ascii.isDigit(c) == true) {
            break :blk "#" ++ [1] u8 {c};
         }

         break :blk "";
      };

      // Iterate over the rest of the string, storing the previous character for
      // additional formatting
      var c_prev = name_raw[0];
      for (name_raw[1..]) |c| {
         // Perform formatting depending on the character and previous character
         // Believe it or not, this is cleaner code than the old implementation
         if (std.ascii.isDigit(c_prev) == true) {
            if (std.ascii.isAlphabetic(c) == true) {
               buf = buf ++ " ";
            }
         }
         if (std.ascii.isDigit(c) == true) {
            if (std.ascii.isAlphabetic(c_prev) == true) {
               buf = buf ++ " ";
            }
            if (std.ascii.isDigit(c_prev) == false) {
               buf = buf ++ "#";
            }

            buf = buf ++ [1] u8 {c};
         }
         if (std.ascii.isAlphanumeric(c) == false) {
            if (std.ascii.isAlphanumeric(c_prev) == true) {
               buf = buf ++ " ";
            }
         }
         if (std.ascii.isUpper(c) == true) {
            if (std.ascii.isLower(c_prev) == true) {
               buf = buf ++ " ";
            }

            buf = buf ++ [1] u8 {std.ascii.toLower(c)};
         }
         if (std.ascii.isLower(c) == true) {
            buf = buf ++ [1] u8 {c};
         }

         // Make sure to advance the previous character for the next iteration
         c_prev = c;
      }

      // Hack fix, removes any additional whitespace at the end as a result of
      // non-alphanumeric characters
      buf = std.mem.trim(u8, buf, &std.ascii.whitespace);

      // Return our formatted error string.  I hate string formatting :(
      // At least comptime lets me avoid the mess of dynamically allocated arrays
      return buf;
   }
}

/// Same thing as errorToString, but a null terminator is appended.
pub fn errorToStringTerm(comptime err : anytype) [:0] const u8 {
   comptime {
      const str = errorToString(err) ++ [1] u8 {0};
      return str[0..str.len - 1 :0];
   }
}

