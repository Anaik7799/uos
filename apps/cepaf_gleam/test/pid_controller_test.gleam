/// PID Controller tests (CTRL-1) — 15 tests
///
/// Coverage: init, default, error, update (setpoint, below, above),
/// integral accumulation, derivative response, clamp boundaries,
/// reset_integral, recommend_action, summary, to_json.
///
/// STAMP: SC-MATH-001, SC-OODA-001
import cepaf_gleam/ha/pid_controller
import gleam/float
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// T01  init creates correct state
// ---------------------------------------------------------------------------
pub fn init_creates_correct_state_test() {
  let pid = pid_controller.init(1.0, 0.5, 0.25, 0.9)
  should.equal(pid.kp, 1.0)
  should.equal(pid.ki, 0.5)
  should.equal(pid.kd, 0.25)
  should.equal(pid.setpoint, 0.9)
  should.equal(pid.integral, 0.0)
  should.equal(pid.prev_error, 0.0)
  should.equal(pid.prev_output, 0.0)
  should.equal(pid.step_count, 0)
}

// ---------------------------------------------------------------------------
// T02  default_health_pid has sensible defaults
// ---------------------------------------------------------------------------
pub fn default_health_pid_sensible_defaults_test() {
  let pid = pid_controller.default_health_pid()
  should.equal(pid.kp, 2.0)
  should.equal(pid.ki, 0.1)
  should.equal(pid.kd, 0.5)
  should.equal(pid.setpoint, 0.95)
  should.equal(pid.integral, 0.0)
  should.equal(pid.step_count, 0)
}

// ---------------------------------------------------------------------------
// T03  error/2 returns setpoint − measurement
// ---------------------------------------------------------------------------
pub fn error_returns_difference_test() {
  let pid = pid_controller.init(1.0, 0.0, 0.0, 0.8)
  // Use approximate comparison for IEEE 754 results
  let e1 = pid_controller.error(pid, 0.6)
  should.be_true(float.absolute_value(e1 -. 0.2) <. 1.0e-9)
  let e2 = pid_controller.error(pid, 0.9)
  should.be_true(float.absolute_value(e2 -. { -0.1 }) <. 1.0e-9)
  let e3 = pid_controller.error(pid, 0.8)
  should.equal(e3, 0.0)
}

// ---------------------------------------------------------------------------
// T04  update with measurement at setpoint → output near zero (pure P+D)
// ---------------------------------------------------------------------------
pub fn update_at_setpoint_output_near_zero_test() {
  // Pure proportional controller, no integral, no derivative bias
  let pid = pid_controller.init(2.0, 0.0, 0.0, 0.9)
  let #(_, output) = pid_controller.update(pid, 0.9, 1.0)
  should.equal(output, 0.0)
}

// ---------------------------------------------------------------------------
// T05  update with measurement below setpoint → positive output
// ---------------------------------------------------------------------------
pub fn update_below_setpoint_positive_output_test() {
  // health = 0.7, setpoint = 0.9 → error = 0.2 → P = 2.0 * 0.2 = 0.4
  let pid = pid_controller.init(2.0, 0.0, 0.0, 0.9)
  let #(_, output) = pid_controller.update(pid, 0.7, 1.0)
  should.be_true(output >. 0.0)
}

// ---------------------------------------------------------------------------
// T06  update with measurement above setpoint → negative output
// ---------------------------------------------------------------------------
pub fn update_above_setpoint_negative_output_test() {
  // health = 1.0, setpoint = 0.9 → error = -0.1 → P = 2.0 * -0.1 = -0.2
  let pid = pid_controller.init(2.0, 0.0, 0.0, 0.9)
  let #(_, output) = pid_controller.update(pid, 1.0, 1.0)
  should.be_true(output <. 0.0)
}

// ---------------------------------------------------------------------------
// T07  integral accumulates over multiple updates (Ki > 0)
// ---------------------------------------------------------------------------
pub fn integral_accumulates_over_updates_test() {
  // Pure integral controller — Kp=0, Ki=1.0, Kd=0
  // measurement always 0.7, setpoint=0.9 → e=0.2 each step, dt=1.0
  // After 3 steps integral = 0.2 + 0.2 + 0.2 = 0.6
  let pid = pid_controller.init(0.0, 1.0, 0.0, 0.9)
  let #(pid1, _) = pid_controller.update(pid, 0.7, 1.0)
  let #(pid2, _) = pid_controller.update(pid1, 0.7, 1.0)
  let #(pid3, _) = pid_controller.update(pid2, 0.7, 1.0)
  // integral should be approximately 0.6
  should.be_true(pid3.integral >. 0.55)
  should.be_true(pid3.integral <. 0.65)
  should.equal(pid3.step_count, 3)
}

// ---------------------------------------------------------------------------
// T08  derivative responds to rate of change
// ---------------------------------------------------------------------------
pub fn derivative_responds_to_rate_of_change_test() {
  // Kp=0, Ki=0, Kd=1.0 — pure derivative
  // Step 1: measurement=0.8, prev_error=0.0 → e=0.1, d = 1.0*(0.1−0.0)/1.0 = 0.1
  // Step 2: measurement=0.7 → e=0.2, d = 1.0*(0.2−0.1)/1.0 = 0.1 (increasing error)
  let pid = pid_controller.init(0.0, 0.0, 1.0, 0.9)
  let #(pid1, output1) = pid_controller.update(pid, 0.8, 1.0)
  let #(_, output2) = pid_controller.update(pid1, 0.7, 1.0)
  // Both outputs positive (error increasing) and second step has positive derivative
  should.be_true(output1 >. 0.0)
  should.be_true(output2 >. 0.0)
}

// ---------------------------------------------------------------------------
// T09  clamp works at lower boundary
// ---------------------------------------------------------------------------
pub fn clamp_lower_boundary_test() {
  should.equal(pid_controller.clamp(-2.5, -1.0, 1.0), -1.0)
  should.equal(pid_controller.clamp(-1.0, -1.0, 1.0), -1.0)
}

// ---------------------------------------------------------------------------
// T10  clamp works at upper boundary
// ---------------------------------------------------------------------------
pub fn clamp_upper_boundary_test() {
  should.equal(pid_controller.clamp(3.0, -1.0, 1.0), 1.0)
  should.equal(pid_controller.clamp(1.0, -1.0, 1.0), 1.0)
}

// ---------------------------------------------------------------------------
// T11  clamp passes through values in range
// ---------------------------------------------------------------------------
pub fn clamp_passthrough_in_range_test() {
  should.equal(pid_controller.clamp(0.5, -1.0, 1.0), 0.5)
  should.equal(pid_controller.clamp(-0.3, -1.0, 1.0), -0.3)
  should.equal(pid_controller.clamp(0.0, -1.0, 1.0), 0.0)
}

// ---------------------------------------------------------------------------
// T12  reset_integral zeros the accumulator
// ---------------------------------------------------------------------------
pub fn reset_integral_zeros_accumulator_test() {
  let pid = pid_controller.init(0.0, 1.0, 0.0, 0.9)
  let #(pid1, _) = pid_controller.update(pid, 0.7, 1.0)
  let #(pid2, _) = pid_controller.update(pid1, 0.7, 1.0)
  // integral is now non-zero
  should.be_true(pid2.integral >. 0.0)
  let reset = pid_controller.reset_integral(pid2)
  should.equal(reset.integral, 0.0)
  // gains and setpoint unchanged
  should.equal(reset.kp, pid2.kp)
  should.equal(reset.setpoint, pid2.setpoint)
  should.equal(reset.step_count, pid2.step_count)
}

// ---------------------------------------------------------------------------
// T13  recommend_action returns correct strings for all bands
//
// Boundary semantics (strict >. comparisons in impl):
//   output > 0.5                   → "critical_recovery"
//   output > 0.2 (and <= 0.5)      → "gradual_recovery"
//   output > -0.2 (and <= 0.2)     → "maintain"
//   output > -0.5 (and <= -0.2)    → "gradual_reduction"
//   output <= -0.5                 → "emergency_reduction"
// ---------------------------------------------------------------------------
pub fn recommend_action_all_bands_test() {
  // strictly above 0.5 → critical_recovery
  should.equal(pid_controller.recommend_action(0.8), "critical_recovery")
  should.equal(pid_controller.recommend_action(1.0), "critical_recovery")
  // exactly 0.5 is NOT > 0.5 → gradual_recovery
  should.equal(pid_controller.recommend_action(0.5), "gradual_recovery")
  should.equal(pid_controller.recommend_action(0.35), "gradual_recovery")
  // exactly 0.2 is NOT > 0.2 → maintain
  should.equal(pid_controller.recommend_action(0.2), "maintain")
  should.equal(pid_controller.recommend_action(0.0), "maintain")
  should.equal(pid_controller.recommend_action(-0.1), "maintain")
  // exactly -0.2 is NOT > -0.2 → gradual_reduction
  should.equal(pid_controller.recommend_action(-0.2), "gradual_reduction")
  should.equal(pid_controller.recommend_action(-0.35), "gradual_reduction")
  // exactly -0.5 is NOT > -0.5 → emergency_reduction
  should.equal(pid_controller.recommend_action(-0.5), "emergency_reduction")
  should.equal(pid_controller.recommend_action(-1.0), "emergency_reduction")
}

// ---------------------------------------------------------------------------
// T14  summary returns non-empty string containing key fields
// ---------------------------------------------------------------------------
pub fn summary_returns_informative_string_test() {
  let pid = pid_controller.default_health_pid()
  let s = pid_controller.summary(pid)
  should.be_true(string.length(s) > 20)
  should.be_true(string.contains(s, "setpoint"))
  should.be_true(string.contains(s, "steps"))
}

// ---------------------------------------------------------------------------
// T15  to_json returns valid JSON-like string with all fields
// ---------------------------------------------------------------------------
pub fn to_json_contains_all_fields_test() {
  let pid = pid_controller.init(1.5, 0.2, 0.3, 0.88)
  let j = pid_controller.to_json(pid)
  should.be_true(string.contains(j, "\"setpoint\""))
  should.be_true(string.contains(j, "\"kp\""))
  should.be_true(string.contains(j, "\"ki\""))
  should.be_true(string.contains(j, "\"kd\""))
  should.be_true(string.contains(j, "\"integral\""))
  should.be_true(string.contains(j, "\"prev_error\""))
  should.be_true(string.contains(j, "\"prev_output\""))
  should.be_true(string.contains(j, "\"step_count\""))
  // must start and end with braces
  should.be_true(string.starts_with(j, "{"))
  should.be_true(string.ends_with(j, "}"))
}
