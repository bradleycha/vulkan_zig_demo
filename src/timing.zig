const std = @import("std");

pub const DeltaTimer = struct {
   _timestamp_prev   : i128,
   _timestamp_curr   : i128,

   pub fn start() @This() {
      const timestamp_start = std.time.nanoTimestamp();

      return @This(){
         ._timestamp_prev  = timestamp_start,
         ._timestamp_curr  = timestamp_start,
      };
   }

   pub fn lap(self : * @This()) void {
      const timestamp_lap = std.time.nanoTimestamp();

      self._timestamp_prev = self._timestamp_curr;
      self._timestamp_curr = timestamp_lap;

      return;
   }

   pub fn delta(self : * const @This()) i128 {
      return self._timestamp_curr - self._timestamp_prev;
   }

   pub fn deltaSeconds(self : * const @This()) f64 {
      return @as(f64, @floatFromInt(self.delta())) / 1000000000.0;
   }
};

pub const UpdateTimer = struct {
   _timestamp_base            : i128,
   _timestamp_curr            : i128,
   _update_delay_nanoseconds  : i128,

   pub fn start(update_delay_nanoseconds: i128) @This() {
      const timestamp_start = std.time.nanoTimestamp();

      return @This(){
         ._timestamp_base           = timestamp_start,
         ._timestamp_curr           = timestamp_start,
         ._update_delay_nanoseconds = update_delay_nanoseconds,
      };
   }

   pub fn tick(self : * @This()) void {
      const timestamp_tick = std.time.nanoTimestamp();

      self._timestamp_curr = timestamp_tick;

      return;
   }

   pub fn lap(self : * @This()) void {
      const timestamp_lap = std.time.nanoTimestamp();

      self._timestamp_base = timestamp_lap;
      self._timestamp_curr = timestamp_lap;

      return;
   }

   pub fn isElapsed(self : * const @This()) bool {
      return self._timestamp_curr - self._timestamp_base >= self._update_delay_nanoseconds;
   }
};

