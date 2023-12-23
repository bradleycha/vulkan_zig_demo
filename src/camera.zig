const std   = @import("std");
const math  = @import("math");
const input = @import("input");

const MOUSE_SENSITIVITY    = 8.0;
const MOVE_SPEED           = 5.0;
const CAMERA_PITCH_RANGE   = std.math.pi;

pub const FreeflyCamera = struct {
   position : math.Vector3(f32)  = math.Vector3(f32).ZERO,
   angles   : math.Vector3(f32)  = math.Vector3(f32).ZERO,

   pub fn toMatrix(self : * const @This()) math.Matrix4(f32) {
      const matrix_position   = math.Matrix4(f32).createTranslation(&self.position);
      const matrix_angles     = math.Matrix4(f32).createRotation(&self.angles);

      const matrix = matrix_angles.multiplyMatrix(&matrix_position);

      return matrix;
   }

   pub fn update(self : * @This(), controller : * const input.Controller, time_delta : f32) void {
      const inputs = _calculateFreeflyCameraInput(controller);

      self.angles.vector += blk: {
         const base     = inputs.look.vector;
         const scaled   = base * @as(@Vector(2, f32), @splat(MOUSE_SENSITIVITY * -1.0 * time_delta));
         const shuffled = @Vector(3, f32){
            scaled[1],
            scaled[0],
            0.0,
         };

         break :blk shuffled;
      };

      self.position.vector += blk: {
         const horizontal  = inputs.move.vector;
         const vertical    = inputs.ascend;

         // TODO: Use the math library to construct a rotation matrix instead of
         // coding it by hand.
         const yaw = self.angles.angles.yaw;
         const sin = std.math.sin(yaw);
         const cos = std.math.cos(yaw);
         const horizontal_rotated = @Vector(2, f32){
            horizontal[1] * sin + horizontal[0] * cos,
            horizontal[1] * cos - horizontal[0] * sin,
         };

         const combined = @Vector(3, f32){
            horizontal_rotated[0],
            vertical,
            horizontal_rotated[1],
         };

         const scaled = combined * @as(@Vector(3, f32), @splat(MOVE_SPEED * time_delta));

         break :blk scaled;
      };

      self.angles.angles.pitch = std.math.clamp(self.angles.angles.pitch, CAMERA_PITCH_RANGE * -0.5, CAMERA_PITCH_RANGE * 0.5);

      return;
   }
};

const _FreeflyCameraInput = struct {
   move     : math.Vector2(f32),
   look     : math.Vector2(f32),
   ascend   : f32,
};

fn _calculateFreeflyCameraInput(controller : * const input.Controller) _FreeflyCameraInput {
   var inputs = _FreeflyCameraInput{
      .move    = math.Vector2(f32).ZERO,
      .look    = math.Vector2(f32).ZERO,
      .ascend  = 0.0,
   };

   if (controller.buttons.state(.jump).isDown() == true) {
      inputs.ascend -= 1.0;
   }
   if (controller.buttons.state(.crouch).isDown() == true) {
      inputs.ascend += 1.0;
   }
   if (controller.buttons.state(.forward).isDown() == true) {
      inputs.move.xy.y += 1.0;
   }
   if (controller.buttons.state(.backward).isDown() == true) {
      inputs.move.xy.y -= 1.0;
   }
   if (controller.buttons.state(.left).isDown() == true) {
      inputs.move.xy.x -= 1.0;
   }
   if (controller.buttons.state(.right).isDown() == true) {
      inputs.move.xy.x += 1.0;
   }

   inputs.move.vector += controller.axies.move.vector;
   inputs.look.vector += controller.axies.look.vector;
   inputs.look.vector += controller.mouse.move_delta.vector;

   // Don't want movement magnitude > 1
   inputs.move = inputs.move.normalizeZero();

   return inputs;
}

