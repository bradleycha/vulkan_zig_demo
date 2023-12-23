const std   = @import("std");
const math  = @import("math");
const input = @import("input");

const MOUSE_SENSITIVITY          = 8.0;
const MOVE_SPEED_BASE            = 10.0;
const MOVE_SPEED_FAST_MULTIPLIER = 5.0;
const MOVE_SPEED_SLOW_MULTIPLIER = 0.4;
const LOOK_SPEED_BASE            = 1.5;
const LOOK_SPEED_FAST_MULTIPLIER = 4.0;
const LOOK_SPEED_SLOW_MULTIPLIER = 0.2;
const DECELERATION_RATE          = 1.5;
const SPEED_CAP_SCALE            = 4.0;
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
      const inputs = _calculateFreeflyCameraInput(controller);

      const time_delta_vector_2 = @as(@Vector(2, f32), @splat(time_delta));
      const time_delta_vector_3 = @as(@Vector(3, f32), @splat(time_delta));

      const angles_delta = blk: {
         const base     = inputs.look.vector;
         const scaled   = base * time_delta_vector_2;
         const shuffled = @Vector(3, f32){
            scaled[1],
            scaled[0],
            0.0,
         };

         break :blk shuffled;
      };

      self.angles.vector += angles_delta;
      self.angles.angles.pitch = std.math.clamp(self.angles.angles.pitch, CAMERA_PITCH_RANGE * -0.5, CAMERA_PITCH_RANGE * 0.5);

      const velocity_delta = blk: {
         const base  = inputs.move.vector;
         const yaw   = self.angles.angles.yaw;
         const sin   = std.math.sin(yaw);
         const cos   = std.math.cos(yaw);

         const yaw_rotated = @Vector(3, f32){
            base[2] * sin + base[0] * cos,
            base[1],
            base[2] * cos - base[0] * sin,
         };

         const decay = self.velocity.normalizeZero().vector * @as(@Vector(3, f32), @splat(DECELERATION_RATE * -1.0));

         const final = (yaw_rotated + decay) * time_delta_vector_3;

         break :blk final;
      };

      const position_delta = blk: {
         // Be careful here!  This time, we are NOT calculating the area of a
         // rectangle, but the area of a trapezoid.  Thus, we need to use the
         // area formula of a trapezoid with base lengths "base" and "base + delta"
         // and height "time_delta".

         const prev     = self.velocity.vector;
         const curr     = prev + velocity_delta;
         const average  = (prev + curr) * @as(@Vector(3, f32), @splat(0.5));
         const scaled   = average * time_delta_vector_3;

         break :blk scaled;
      };
      
      self.velocity.vector += velocity_delta;

      const velocity_magnitude = self.velocity.magnitude();
      if (velocity_magnitude > inputs.speed_cap) {
         self.velocity.vector = self.velocity.vector * @as(@Vector(3, f32), @splat(inputs.speed_cap / velocity_magnitude));
      }

      self.position.vector += position_delta;

      return;
   }
};

const _FreeflyCameraInput = struct {
   move        : math.Vector3(f32),
   look        : math.Vector2(f32),
   speed_cap   : f32,
};

fn _calculateFreeflyCameraInput(controller : * const input.Controller) _FreeflyCameraInput {
   var inputs = _FreeflyCameraInput{
      .move       = math.Vector3(f32).ZERO,
      .look       = math.Vector2(f32).ZERO,
      .speed_cap  = 0.0,
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
   inputs.speed_cap = scalar_multiplier_move * (1.0 / SPEED_CAP_SCALE);

   // Add mouse movement at the end to skip over speed modifiers and normalization.
   const mouse_look = controller.mouse.move_delta.vector * @as(@Vector(2, f32), @splat(MOUSE_SENSITIVITY * -1.0));
   inputs.look.vector += mouse_look;

   return inputs;
}

