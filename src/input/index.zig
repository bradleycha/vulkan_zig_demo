const std   = @import("std");
const math  = @import("math");

pub const Controller = struct {
   axies    : Axies     = .{},
   mouse    : Mouse     = .{},
   buttons  : Buttons   = .{},

   pub fn advance(self : * @This()) void {
      self.buttons.advance();
      self.mouse.advance();
      return;
   }
};

pub const Axies = struct {
   move  : math.Vector2(f32)  = math.Vector2(f32).ZERO,
   look  : math.Vector2(f32)  = math.Vector2(f32).ZERO,
};

pub const Mouse = struct {
   dx : f32 = 0.0,
   dy : f32 = 0.0,

   pub fn advance(self : * @This()) void {
      self.dx = 0.0;
      self.dy = 0.0;
      return;
   }
};

pub const Buttons = struct {
   _state_prev : @typeInfo(Button).Enum.tag_type = 0,
   _state_curr : @typeInfo(Button).Enum.tag_type = 0,

   pub fn advance(self : * @This()) void {
      self._state_prev = self._state_curr;
      self._state_curr = 0;
      return;
   }

   pub fn state(self : * const @This(), button : Button) Button.State {
      const button_mask = @intFromEnum(button);

      const state_prev = @as(u2, @intFromBool(self._state_prev & button_mask != 0));
      const state_curr = @as(u2, @intFromBool(self._state_curr & button_mask != 0));

      const state_bits = (state_prev << 1) | state_curr;

      const state_enum : Button.State = @enumFromInt(state_bits);

      return state_enum;
   }
};

pub const Button = enum(u2) {
   exit           = 0b01,
   toggle_focus   = 0b10,

   pub const State = enum(u2) {
      up       = 0b00,
      pressed  = 0b01,
      down     = 0b11,
      released = 0b10,

      pub fn isUp(self : @This()) bool {
         return @intFromEnum(self) | 0b01 == 0;
      }

      pub fn isPressed(self : @This()) bool {
         return self == .pressed;
      }

      pub fn isDown(self : @This()) bool {
         return !self.isUp();
      }

      pub fn isReleased(self : @This()) bool {
         return self == .released;
      }
   };
};

