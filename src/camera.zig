const std   = @import("std");
const math  = @import("math");
const input = @import("input");

const MOUSE_SENSITIVITY          = 8.0;
const MOVE_SPEED_BASE            = 1.0;
const MOVE_SPEED_FAST_MULTIPLIER = 5.0;
const MOVE_SPEED_SLOW_MULTIPLIER = 0.2;
const LOOK_SPEED_BASE            = 1.5;
const LOOK_SPEED_FAST_MULTIPLIER = 4.0;
const LOOK_SPEED_SLOW_MULTIPLIER = 0.2;
const ACCELERATION_EXPONENT_BASE = 2.0;
const CAMERA_PITCH_RANGE         = std.math.pi;

pub const FreeflyCamera = struct {
   position : math.Vector3(f32)  = math.Vector3(f32).ZERO,
   velocity : math.Vector3(f32)  = math.Vector3(f32).ZERO,
   angles   : math.Vector3(f32)  = math.Vector3(f32).ZERO,

   pub fn toMatrix(self : * const @This()) math.Matrix4(f32) {
      const matrix_position   = math.Matrix4(f32).createTranslation(&self.position);
      const matrix_angles     = math.Matrix4(f32).createRotation(&self.angles);

      const matrix = matrix_angles.multiplyMatrix(&matrix_position);

      return matrix;
   }

   pub fn update(self : * @This(), controller : * const input.Controller, time_delta : f32) void {
      const inputs = _calculateInput(controller);

      const new_angles = _calculateNewAngles(&self.angles, &inputs, time_delta);
      self.angles = new_angles;

      // TODO: Everything velocity/position

      return;
   }
};

const _FreeflyCameraInput = struct {
   move : math.Vector3(f32),
   look : math.Vector2(f32),
};

fn _calculateInput(controller : * const input.Controller) _FreeflyCameraInput {
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

   // Don't want base movement speeds to be > 1
   inputs.move = inputs.move.normalizeZero();
   inputs.look = inputs.look.normalizeZero();

   inputs.move.vector *= @splat(MOVE_SPEED_BASE);
   inputs.look.vector *= @splat(LOOK_SPEED_BASE);

   if (controller.buttons.state(.accelerate).isDown() == true) {
      inputs.move.vector *= @splat(MOVE_SPEED_FAST_MULTIPLIER);
      inputs.look.vector *= @splat(LOOK_SPEED_FAST_MULTIPLIER);
   }

   if (controller.buttons.state(.decelerate).isDown() == true) {
      inputs.move.vector *= @splat(MOVE_SPEED_SLOW_MULTIPLIER);
      inputs.look.vector *= @splat(LOOK_SPEED_SLOW_MULTIPLIER);
   }

   // Add at the end to skip acceleration/deceleration and normalization
   inputs.look.vector += controller.mouse.move_delta.vector * @as(@Vector(2, f32), @splat(MOUSE_SENSITIVITY * -1.0));

   return inputs;
}

fn _calculateNewAngles(old_angles : * const math.Vector3(f32), inputs : * const _FreeflyCameraInput, time_delta : f32) math.Vector3(f32) {
   const delta_angles = math.Vector3(f32){.angles = .{
      .pitch   = inputs.look.xy.y * time_delta,
      .yaw     = inputs.look.xy.x * time_delta,
      .roll    = 0.0,
   }};

   const new_angles = old_angles.vector + delta_angles.vector;
   
   return .{.vector = new_angles};
}

