const std   = @import("std");
const math  = @import("math");
const input = @import("input");

const MOUSE_SENSITIVITY          = 8.0;
const MOVE_SPEED_BASE            = 2.0;
const MOVE_SPEED_FAST_MULTIPLIER = 5.0;
const MOVE_SPEED_SLOW_MULTIPLIER = 0.2;
const LOOK_SPEED_BASE            = 1.5;
const LOOK_SPEED_FAST_MULTIPLIER = 4.0;
const LOOK_SPEED_SLOW_MULTIPLIER = 0.3;
const ACCELERATION_BASE          = 0.995;
const CAMERA_PITCH_RANGE         = std.math.pi;

comptime {
   if (MOUSE_SENSITIVITY <= 0.0) {
      @compileError("mouse sensitivity must be positive and non-zero");
   }

   if (ACCELERATION_BASE > 1.0) {
      @compileError("acceleration base must be less than or equal to zero");
   }
}

pub const FreeflyCamera = struct {
   position : math.Vector3(f32) = math.Vector3(f32).ZERO,
   velocity : math.Vector3(f32) = math.Vector3(f32).ZERO,
   angles   : math.Vector3(f32) = math.Vector3(f32).ZERO,

   pub fn toMatrix(self : * const @This()) math.Matrix4(f32) {
      const matrix_position   = math.Matrix4(f32).createTranslation(&self.position);
      const matrix_angles     = math.Matrix4(f32).createRotation(&self.angles);

      const matrix = matrix_angles.multiplyMatrix(&matrix_position);

      return matrix;
   }

   pub fn update(self : * @This(), controller : * const input.Controller, time_delta : f32) void {
      const time_delta_vector = @as(@Vector(3, f32), @splat(time_delta));

      const inputs = _calculateInput(controller);

      const angles_delta = _calculateAnglesDelta(&inputs);
      self.angles.vector += angles_delta.vector * time_delta_vector;

      self.angles.angles.pitch = std.math.clamp(self.angles.angles.pitch, CAMERA_PITCH_RANGE * -0.5, CAMERA_PITCH_RANGE * 0.5);

      const velocity_target   = _calculateTargetVelocity(&inputs, &self.angles);
      const velocity_current  = self.velocity;
      const velocity_delta    = velocity_target.vector - velocity_current.vector;

      const acceleration = velocity_delta * @as(@Vector(3, f32), @splat(ACCELERATION_BASE));
      const acceleration_accumulate = acceleration * time_delta_vector;

      const velocity_prev        = self.velocity.vector;
      const velocity_curr        = velocity_prev + acceleration_accumulate;
      const velocity_average     = (velocity_prev + velocity_curr) * @as(@Vector(3, f32), @splat(0.5));
      const velocity_accumulate  = velocity_average * time_delta_vector;

      self.velocity.vector = velocity_curr;
      self.position.vector += velocity_accumulate;

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

fn _calculateAnglesDelta(inputs : * const _FreeflyCameraInput) math.Vector3(f32) {
   const delta_angles = math.Vector3(f32){.angles = .{
      .pitch   = inputs.look.xy.y,
      .yaw     = inputs.look.xy.x,
      .roll    = 0.0,
   }};

   return delta_angles;
}

fn _calculateTargetVelocity(inputs : * const _FreeflyCameraInput, current_angles : * const math.Vector3(f32)) math.Vector3(f32) {
   const velocity = inputs.move;

   const yaw      = current_angles.angles.yaw;
   const sin_yaw  = std.math.sin(yaw);
   const cos_yaw  = std.math.cos(yaw);

   // Rotates the x/z move vector to face the same direction as the camera yaw.
   const velocity_rotated = math.Vector3(f32){.xyz = .{
      .x = velocity.xyz.z * sin_yaw + velocity.xyz.x * cos_yaw,
      .y = velocity.xyz.y,
      .z = velocity.xyz.z * cos_yaw - velocity.xyz.x * sin_yaw,
   }};

   return velocity_rotated;
}

