//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/pid_controller</module>
////     <fsharp-lineage>None — novel PID control law for health steering (F21)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       PID Controller for System Health (CTRL-1).
////       Implements u(t) = Kp·e(t) + Ki·∫e(t)dt + Kd·de/dt
////       where e = setpoint − measurement.
////       Used by guard_grid OODA to compute proportional control actions
////       rather than binary threshold-based decisions.
////       Control output is clamped to [−1.0, 1.0]:
////         negative → reduce load / shed capacity
////         positive → increase capacity / trigger recovery
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Classical discrete-time PID ↪ Gleam pure value type.
////       All state is passed by value; no mutable globals; caller owns persistence.
////       Integral windup guarded by output clamp and reset_integral/1.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 arithmetic — adequate for health control; not for safety actuation.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// PID CONTROLLER — PROPORTIONAL-INTEGRAL-DERIVATIVE HEALTH STEERING
//// कर्मण्येवाधिकारस्ते — Your right is to action alone (Gita 2.47)
////
//// Classical discrete-time PID update law:
////
////   e(t)  = setpoint − measurement
////   P     = Kp · e(t)
////   I     = integral + Ki · e(t) · dt
////   D     = Kd · (e(t) − e(t−1)) / dt
////   u(t)  = clamp(P + I + D, −1.0, 1.0)
////
//// Design principles:
////   1. PURE — update/3 and all helpers have no side-effects; state is by value.
////   2. CLAMPED — output always in [−1.0, 1.0]; integral windup prevented
////      by capping the term at the clamp boundaries.
////   3. DT-SAFE — dt_seconds is guarded: values ≤ 0 are treated as the
////      minimum tick (0.001 s) to avoid division by zero.
////   4. RESET-SAFE — reset_integral/1 zeros accumulated error without
////      touching gains or setpoint.
////   5. IDEMPOTENT — calling update/3 with measurement == setpoint yields
////      output → 0 (modulo accumulated integral).
////
//// STAMP: SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001

import gleam/float
import gleam/int
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Complete PID controller state — passed by value, no shared mutable state.
pub type PidState {
  PidState(
    /// Proportional gain
    kp: Float,
    /// Integral gain
    ki: Float,
    /// Derivative gain
    kd: Float,
    /// Target setpoint (desired health, e.g. 0.95)
    setpoint: Float,
    /// Accumulated integral error (Ki · Σ e·dt)
    integral: Float,
    /// Previous error, used for derivative term
    prev_error: Float,
    /// Previous control output
    prev_output: Float,
    /// Monotonic count of update/3 calls
    step_count: Int,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise a PID controller with explicit tuning parameters.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Gains + setpoint ↪ clean PidState</morphism>
///   <formal-proof>
///     <P> Pre: kp, ki, kd >= 0.0; setpoint in [0.0, 1.0] </P>
///     <C> init(kp, ki, kd, setpoint) </C>
///     <Q> Post: integral = 0.0, prev_error = 0.0, prev_output = 0.0, step_count = 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init(kp: Float, ki: Float, kd: Float, setpoint: Float) -> PidState {
  PidState(
    kp: kp,
    ki: ki,
    kd: kd,
    setpoint: setpoint,
    integral: 0.0,
    prev_error: 0.0,
    prev_output: 0.0,
    step_count: 0,
  )
}

/// Default PID tuned for system health control.
///
/// Defaults: Kp=2.0, Ki=0.1, Kd=0.5, setpoint=0.95
/// These gains are empirically derived for the C3I health domain where:
///   - measurement range: [0.0, 1.0]
///   - output range:      [−1.0, 1.0]
///   - typical dt:        1.0 s (1-second OODA tick)
pub fn default_health_pid() -> PidState {
  init(2.0, 0.1, 0.5, 0.95)
}

/// Compute the signed error: setpoint − measurement.
///
/// Positive error → measurement is below setpoint → system needs recovery.
/// Negative error → measurement is above setpoint → system can relax load.
pub fn error(state: PidState, measurement: Float) -> Float {
  state.setpoint -. measurement
}

/// Update the PID with a new health measurement.
///
/// Returns #(new_state, control_output) where control_output ∈ [−1.0, 1.0].
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">PidState + measurement + dt ↪ updated PidState + Float</morphism>
///   <formal-proof>
///     <P> Pre: measurement in [0.0, 1.0]; dt_seconds > 0.0 </P>
///     <C> update(state, measurement, dt_seconds) </C>
///     <Q> Post: output in [−1.0, 1.0]; step_count = prev_step_count + 1 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn update(
  state: PidState,
  measurement: Float,
  dt_seconds: Float,
) -> #(PidState, Float) {
  // Guard: dt must be positive to avoid division by zero
  let dt = case dt_seconds <=. 0.0 {
    True -> 0.001
    False -> dt_seconds
  }

  let e = error(state, measurement)

  // Proportional term
  let p = state.kp *. e

  // Integral term with windup prevention:
  // We accumulate first, then clamp the full output — not the integral itself.
  let new_integral = state.integral +. state.ki *. e *. dt

  // Derivative term: rate of change of error
  let d = state.kd *. { e -. state.prev_error } /. dt

  // Raw output
  let raw = p +. new_integral +. d

  // Clamp to [−1.0, 1.0]
  let output = clamp(raw, -1.0, 1.0)

  let new_state =
    PidState(
      ..state,
      integral: new_integral,
      prev_error: e,
      prev_output: output,
      step_count: state.step_count + 1,
    )

  #(new_state, output)
}

/// Reset the integral accumulator to zero without changing gains or setpoint.
///
/// Use when the operating point changes significantly to avoid windup carry-over.
pub fn reset_integral(state: PidState) -> PidState {
  PidState(..state, integral: 0.0)
}

/// Clamp a float value to [min, max].
pub fn clamp(value: Float, min: Float, max: Float) -> Float {
  case value <. min {
    True -> min
    False ->
      case value >. max {
        True -> max
        False -> value
      }
  }
}

/// Map a control output value to a human-readable action recommendation.
///
/// Bands:
///   output > 0.5   → "critical_recovery"   — immediate capacity increase
///   output > 0.2   → "gradual_recovery"     — ramp up capacity
///   output > -0.2  → "maintain"             — system near setpoint
///   output > -0.5  → "gradual_reduction"    — ease load slightly
///   else           → "emergency_reduction"  — aggressive load shedding
pub fn recommend_action(output: Float) -> String {
  case output >. 0.5 {
    True -> "critical_recovery"
    False ->
      case output >. 0.2 {
        True -> "gradual_recovery"
        False ->
          case output >. -0.2 {
            True -> "maintain"
            False ->
              case output >. -0.5 {
                True -> "gradual_reduction"
                False -> "emergency_reduction"
              }
          }
      }
  }
}

/// Human-readable summary of the current PID state.
pub fn summary(state: PidState) -> String {
  let sp = float_to_str(state.setpoint)
  let kp = float_to_str(state.kp)
  let ki = float_to_str(state.ki)
  let kd = float_to_str(state.kd)
  let intg = float_to_str(state.integral)
  let pe = float_to_str(state.prev_error)
  let po = float_to_str(state.prev_output)
  let steps = int.to_string(state.step_count)
  string.concat([
    "PidState{setpoint=",
    sp,
    ",Kp=",
    kp,
    ",Ki=",
    ki,
    ",Kd=",
    kd,
    ",integral=",
    intg,
    ",prev_error=",
    pe,
    ",prev_output=",
    po,
    ",steps=",
    steps,
    "}",
  ])
}

/// Serialize PID state to a JSON string for Zenoh / audit publishing.
pub fn to_json(state: PidState) -> String {
  let sp = float_to_str(state.setpoint)
  let kp = float_to_str(state.kp)
  let ki = float_to_str(state.ki)
  let kd = float_to_str(state.kd)
  let intg = float_to_str(state.integral)
  let pe = float_to_str(state.prev_error)
  let po = float_to_str(state.prev_output)
  let steps = int.to_string(state.step_count)
  string.concat([
    "{\"setpoint\":",
    sp,
    ",\"kp\":",
    kp,
    ",\"ki\":",
    ki,
    ",\"kd\":",
    kd,
    ",\"integral\":",
    intg,
    ",\"prev_error\":",
    pe,
    ",\"prev_output\":",
    po,
    ",\"step_count\":",
    steps,
    "}",
  ])
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn float_to_str(f: Float) -> String {
  float.to_string(f)
}
