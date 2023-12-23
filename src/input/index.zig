const std   = @import("std");
const math  = @import("math");

pub const Controller = struct {
   axies    : Axies     = .{},
   mouse    : Mouse     = .{},
   buttons  : Buttons   = .{},

   pub fn advance(self : * @This()) void {
      self.axies.normalize();
      self.mouse.advance();
      self.buttons.advance();
      return;
   }
};

pub const Axies = struct {
   move  : math.Vector2(f32)  = math.Vector2(f32).ZERO,
   look  : math.Vector2(f32)  = math.Vector2(f32).ZERO,

   pub fn normalize(self : * @This()) void {
      self.move = self.move.normalizeZero();
      self.look = self.look.normalizeZero();
      return;
   }
};

pub const Mouse = struct {
   move_delta  : math.Vector2(f32) = math.Vector2(f32).ZERO,

   pub fn advance(self : * @This()) void {
      self.move_delta = math.Vector2(f32).ZERO;
      return;
   }
};

pub const Buttons = struct {
   _state_prev : @typeInfo(Button).Enum.tag_type = 0,
   _state_curr : @typeInfo(Button).Enum.tag_type = 0,

   pub fn advance(self : * @This()) void {
      self._state_prev = self._state_curr;
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

   pub fn press(self : * @This(), button : Button) void {
      self._state_curr |= @intFromEnum(button);
      return;
   }

   pub fn release(self : * @This(), button : Button) void {
      self._state_curr &= ~@intFromEnum(button);
      return;
   }
};

pub const Button = enum(u15) {
   exit           = 1 << 0,
   toggle_focus   = 1 << 1,
   move_forward   = 1 << 2,
   move_backward  = 1 << 3,
   move_left      = 1 << 4,
   move_right     = 1 << 5,
   jump           = 1 << 6,
   crouch         = 1 << 7,
   look_up        = 1 << 8,
   look_down      = 1 << 9,
   look_left      = 1 << 10,
   look_right     = 1 << 11,
   accelerate     = 1 << 12,
   decelerate     = 1 << 13,
   respawn        = 1 << 14,

   pub const State = enum(u2) {
      up       = 0b00,
      pressed  = 0b01,
      down     = 0b11,
      released = 0b10,

      pub fn isUp(self : @This()) bool {
         return @intFromEnum(self) & 0b01 == 0;
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

