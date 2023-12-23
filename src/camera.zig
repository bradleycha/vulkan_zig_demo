const std   = @import("std");
const math  = @import("math");
const input = @import("input");

const MOUSE_SENSITIVITY          = 8.0;
const MOVE_SPEED_BASE            = 3.0;
const MOVE_SPEED_FAST_MULTIPLIER = 5.0;
const MOVE_SPEED_SLOW_MULTIPLIER = 0.1;
const LOOK_SPEED_BASE            = 1.5;
const LOOK_SPEED_FAST_MULTIPLIER = 4.0;
const LOOK_SPEED_SLOW_MULTIPLIER = 0.2;
const CAMERA_PITCH_RANGE         = std.math.pi;

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
         const scaled   = base * @as(@Vector(2, f32), @splat(time_delta));
         const shuffled = @Vector(3, f32){
            scaled[1],
            scaled[0],
            0.0,
         };

         break :blk shuffled;
      };

      self.position.vector += blk: {
         const horizontal = @Vector(2, f32){inputs.move.xyz.x, inputs.move.xyz.z};
         const vertical = inputs.move.xyz.y;

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

         const scaled = combined * @as(@Vector(3, f32), @splat(time_delta));

         break :blk scaled;
      };

      self.angles.angles.pitch = std.math.clamp(self.angles.angles.pitch, CAMERA_PITCH_RANGE * -0.5, CAMERA_PITCH_RANGE * 0.5);

      return;
   }
};

const _FreeflyCameraInput = struct {
   move : math.Vector3(f32),
   look : math.Vector2(f32),
};

fn _calculateFreeflyCameraInput(controller : * const input.Controller) _FreeflyCameraInput {
   var inputs = _FreeflyCameraInput{
      .move = math.Vector3(f32).ZERO,
      .look = math.Vector2(f32).ZERO,
   };

   if (controller.buttons.state(.jump).isDown() == true) {
      inputs.move.xyz.y -= 1.0;
   }
   if (controller.buttons.state(.crouch).isDown() == true) {
      inputs.move.xyz.y += 1.0;
   }
   if (controller.buttons.state(.move_forward).isDown() == true) {
      inputs.move.xyz.z += 1.0;
   }
   if (controller.buttons.state(.move_backward).isDown() == true) {
      inputs.move.xyz.z -= 1.0;
   }
   if (controller.buttons.state(.move_left).isDown() == true) {
      inputs.move.xyz.x -= 1.0;
   }
   if (controller.buttons.state(.move_right).isDown() == true) {
      inputs.move.xyz.x += 1.0;
   }
   if (controller.buttons.state(.look_up).isDown() == true) {
      inputs.look.xy.y += 1.0;
   }
   if (controller.buttons.state(.look_down).isDown() == true) {
      inputs.look.xy.y -= 1.0;
   }
   if (controller.buttons.state(.look_left).isDown() == true) {
      inputs.look.xy.x += 1.0;
   }
   if (controller.buttons.state(.look_right).isDown() == true) {
      inputs.look.xy.x -= 1.0;
   }

   const axis_move = @Vector(3, f32){controller.axies.move.xy.x, 0.0, controller.axies.move.xy.y};
   const axis_look = controller.axies.look.vector;

   inputs.move.vector += axis_move;
   inputs.look.vector += axis_look;

   // Don't want base input magnitudes > 1
   inputs.move = inputs.move.normalizeZero();
   inputs.look = inputs.look.normalizeZero();

   var scalar_multiplier_move : f32 = MOVE_SPEED_BASE;
   var scalar_multiplier_look : f32 = LOOK_SPEED_BASE;

   if (controller.buttons.state(.accelerate).isDown() == true) {
      scalar_multiplier_move *= MOVE_SPEED_FAST_MULTIPLIER;
      scalar_multiplier_look *= LOOK_SPEED_FAST_MULTIPLIER;
   }

   if (controller.buttons.state(.decelerate).isDown() == true) {
      scalar_multiplier_move *= MOVE_SPEED_SLOW_MULTIPLIER;
      scalar_multiplier_look *= LOOK_SPEED_SLOW_MULTIPLIER;
   }

   const vector_multiplier_move = @as(@Vector(3, f32), @splat(scalar_multiplier_move));
   const vector_multiplier_look = @as(@Vector(2, f32), @splat(scalar_multiplier_look));

   inputs.move.vector *= vector_multiplier_move;
   inputs.look.vector *= vector_multiplier_look;

   // Add mouse movement at the end to skip over speed modifiers and normalization.
   const mouse_look = controller.mouse.move_delta.vector * @as(@Vector(2, f32), @splat(MOUSE_SENSITIVITY * -1.0));
   inputs.look.vector += mouse_look;

   return inputs;
}

