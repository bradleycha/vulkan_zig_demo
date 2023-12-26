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
const VELOCITY_APPROACH_RATE     = 0.25;
const CAMERA_PITCH_RANGE         = std.math.pi;

comptime {
   if (MOUSE_SENSITIVITY <= 0.0) {
      @compileError("mouse sensitivity must be positive and non-zero");
   }

   if (VELOCITY_APPROACH_RATE <= 0.0 or VELOCITY_APPROACH_RATE >= 1.0) {
      @compileError("velocity approach rate must be between 0 and 1, exclusive");
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

      // We want our camera to approach a given velocity using exponential decay.
      // This means our velocity and position calculations are much more complex
      // than just multiplying by delta time since our function is exponential.
      // For this, I derived a general formula for calculating a value using a
      // recursive approach and its accumulation with respect to delta time:
      //
      // -----------------------------------------------------------------------
      // f(t)  = the value we are modelling at time point 't'
      // a(n)  = the value on the 'n'th frame
      // b(n)  = the accumulation of the value on the 'n'th frame
      // dt    = the time the previous frame took to complete
      //
      // a(n+1) = f(f^-1(a(n)) + dt)
      // b(n+1) = b(n) + Int(f(t)dt, f^-1(a(n)), f^-1(a(n)) + dt)
      // -----------------------------------------------------------------------
      //
      // To model our exponential decay, I chose the following function to model
      // velocity:
      //
      // f(t) = C + A*B^t, t >= 0
      //
      // A = initial velocity - target velocity
      // B = rate of decay, 0 < B < 1
      // C = target velocity
      //
      // If we plug our function into the above formula, we get the following:
      //
      // a(n) = current velocity
      // b(n) = current position
      //
      // a(n+1) = C + (a(n) - C)*B^dt
      // b(n+1) = b(n) + C*dt + (1/ln(B))(a(n+1) - a(n))
      //
      // Note how if given a(0) and b(0), we don't have to store the difference
      // between initial velocity and target velocity.  In addition, this can
      // all be easily extended to Zig vector types since we use addition,
      // subtraction, and multiplication for everything except B^dt, which can
      // just be @splat()'d and multiplied like usual.
      //
      // Also worth noting we shouldn't use bases too close to 0 or 1 due to
      // floating-point inaccuracy causing our code to break down.  A base
      // closer to 0.5 will have better accuracy.

      const velocity_target = _calculateTargetVelocity(&inputs, &self.angles).vector;

      // B^dt
      const time_delta_exponent = std.math.pow(f32, VELOCITY_APPROACH_RATE, time_delta);
      const time_delta_exponent_vector = @as(@Vector(3, f32), @splat(time_delta_exponent));

      // a(n) and a(n+1)
      const velocity_curr = self.velocity.vector;
      const velocity_next = velocity_target + (velocity_curr - velocity_target) * time_delta_exponent_vector;

      // b(n)
      const position_curr = self.position.vector;

      // 1/ln(B)
      const base_logarithm_reciprocal = 1.0 / std.math.log(f32, std.math.e, VELOCITY_APPROACH_RATE);
      const base_logarithm_reciprocal_vector = @as(@Vector(3, f32), @splat(base_logarithm_reciprocal));

      // C*dt
      const position_accumulate_linear = velocity_target * time_delta_vector;

      // (1/ln(B))(a(n+1) - a(n))
      const position_accumulate_exponential = base_logarithm_reciprocal_vector * (velocity_next - velocity_curr);

      // b(n+1)
      const position_next = position_curr + position_accumulate_linear + position_accumulate_exponential;

      // Happy new years and cheers to 2024!
      self.velocity.vector = velocity_next;
      self.position.vector = position_next;

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

