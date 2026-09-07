//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Adaptive Lyapunov Damping Controller Verification
//// =============================================================================

import cepaf_gleam/ha/lyapunov_controller.{
  EmergencyHalt, NominalThroughput, ThrottledBackpressure,
  compute_batch_size, init_controller, update_controller,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn controller_init_nominal_test() {
  let ctrl = init_controller(1, 16)
  ctrl.concurrency_limit |> should.equal(16)
  ctrl.min_concurrency |> should.equal(1)
  ctrl.max_concurrency |> should.equal(16)
  ctrl.publish_interval_ms |> should.equal(50)
  ctrl.state |> should.equal(NominalThroughput)
  compute_batch_size(ctrl) |> should.equal(8)
}

pub fn controller_stable_trajectory_test() {
  let ctrl = init_controller(2, 32)
  let updated = update_controller(ctrl, -3.5)
  
  updated.current_exponent |> should.equal(-3.5)
  updated.concurrency_limit |> should.equal(32)
  updated.publish_interval_ms |> should.equal(50)
  updated.state |> should.equal(NominalThroughput)
  compute_batch_size(updated) |> should.equal(16)
}

pub fn controller_marginal_damping_test() {
  let ctrl = init_controller(2, 20)
  let updated = update_controller(ctrl, -0.6)
  
  // lambda = -0.6 -> severity = 0.6 / 1.5 = 0.4 -> limit = round(20 * 0.4) = 8
  updated.current_exponent |> should.equal(-0.6)
  updated.concurrency_limit |> should.equal(8)
  case updated.state {
    ThrottledBackpressure(ratio) -> {
      ratio |> should.equal(0.4)
    }
    _ -> should.fail()
  }
  compute_batch_size(updated) |> should.equal(1)
}

pub fn controller_unstable_emergency_halt_test() {
  let ctrl = init_controller(1, 16)
  let updated = update_controller(ctrl, 0.45)
  
  updated.concurrency_limit |> should.equal(1)
  updated.publish_interval_ms |> should.equal(1000)
  case updated.state {
    EmergencyHalt(_) -> should.be_true(True)
    _ -> should.fail()
  }
  compute_batch_size(updated) |> should.equal(0)
}
