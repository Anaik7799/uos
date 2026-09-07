//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Autonomous PID Telemetry Controller Verification
//// =============================================================================

import cepaf_gleam/ha/pid_tuner.{
  default_pid_config, init_pid_tuner, reset_integral, update_pid,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn pid_init_test() {
  let cfg = default_pid_config()
  let state = init_pid_tuner(cfg, 1000)
  state.integral_accum |> should.equal(0.0)
  state.prev_error |> should.equal(0.0)
  state.last_output |> should.equal(1.0)
}

pub fn pid_equilibrium_nominal_test() {
  let cfg = default_pid_config()
  let state = init_pid_tuner(cfg, 1_000_000)

  // Observed lambda matches setpoint (-3.0) -> error = 0 -> output = 1.0
  let #(updated, actuation) = update_pid(state, -3.0, 2_000_000)
  actuation.recommended_concurrency |> should.equal(16)
  actuation.recommended_publish_interval_ms |> should.equal(50)
  actuation.recommended_batch_size |> should.equal(8)
  should.be_true(actuation.control_output >=. 0.99 && actuation.control_output <=. 1.01)
  updated.prev_error |> should.equal(0.0)
}

pub fn pid_divergent_damping_test() {
  let cfg = default_pid_config()
  let state = init_pid_tuner(cfg, 1_000_000)

  // Observed lambda is high (-0.5 vs -3.0 setpoint) -> error is -2.5 -> throttles down
  let #(updated, actuation) = update_pid(state, -0.5, 2_000_000)
  should.be_true(actuation.control_output <. 0.5)
  should.be_true(actuation.recommended_concurrency <= 8)
  should.be_true(actuation.recommended_publish_interval_ms >= 100)
  should.be_true(updated.integral_accum <. 0.0)
}

pub fn pid_super_stable_boost_test() {
  let cfg = default_pid_config()
  let state = init_pid_tuner(cfg, 1_000_000)

  // Observed lambda is deeply negative (-4.5 vs -3.0 setpoint) -> error is +1.5 -> scales up
  let #(_updated, actuation) = update_pid(state, -4.5, 2_000_000)
  should.be_true(actuation.control_output >. 1.2)
  should.be_true(actuation.recommended_concurrency >= 20)
  should.be_true(actuation.recommended_publish_interval_ms <= 40)
}

pub fn pid_reset_integral_test() {
  let cfg = default_pid_config()
  let state = init_pid_tuner(cfg, 1_000_000)
  let #(updated, _) = update_pid(state, -1.0, 2_000_000)
  should.be_true(updated.integral_accum != 0.0)

  let reset = reset_integral(updated)
  reset.integral_accum |> should.equal(0.0)
}
