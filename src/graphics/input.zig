const std = @import("std");

pub const InputState = struct {
   buttons  : ButtonList,

   pub fn create() @This() {
      return @This(){
         .buttons = ButtonList.create(),
      };
   }

   pub fn advance(self : * @This()) void {
      self.buttons.advance();
      return;
   }
};

pub const ButtonList = struct {
   _state_prev : _ButtonStateType,
   _state_curr : _ButtonStateType,

   const _ButtonStateType = @typeInfo(Button).Enum.tag_type;

   pub fn create() @This() {
      return @This(){
         ._state_prev   = 0,
         ._state_curr   = 0,
      };
   }

   pub fn state(self : * const @This(), button : Button) Button.State {
      const mask = @intFromEnum(button);

      const state_prev = self._state_prev & mask != 0;
      const state_curr = self._state_curr & mask != 0;

      const state_combined = (@as(u2, @intFromBool(state_prev)) << 1) | (@as(u2, @intFromBool(state_curr)));
      const state_enum : Button.State = @enumFromInt(state_combined);

      return state_enum;
   }

   pub fn advance(self : * @This()) void {
      self._state_prev = self._state_curr;
      self._state_curr = 0;
      return;
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

pub const Button = enum(u1) {
   exit  = 0b1,

   pub const State = enum(u2) {
      up       = 0b00,
      pressed  = 0b01,
      down     = 0b11,
      released = 0b10,

      pub fn is_pressed(self : @This()) bool {
         return self == .pressed;
      }

      pub fn is_released(self : @This()) bool {
         return self == .released;
      }

      pub fn is_down(self : @This()) bool {
         return @intFromEnum(self) & 0b01 != 0;
      }

      pub fn is_up(self : @This()) bool {
         return !self.is_down();
      }
   };
};

