// =============================================================================
// poodavr_kalman_controller_test.gleam — Tests for 7-Stage POODAVR Controller
// STAMP: SC-POODAVR-002, SC-MATH-001, SC-SIL6-001, SC-JIDOKA-001
// =============================================================================

import cepaf_gleam/ha/poodavr_kalman_controller.{
  ControllerAndonHalt, ControllerNominal, execute_full_poodavr_cycle,
  new_controller,
}
import gleam/list
import gleeunit/should

pub fn poodavr_nominal_convergence_test() {
  // Target setpoint = 100.0, initial estimate = 80.0
  let controller = new_controller("cycle-001", 100.0, 80.0)

  // Provide observations trending towards 100.0
  let observations = [85.0, 92.0, 97.0, 99.0, 100.2, 99.8, 100.0]

  let #(final_state, verdict) =
    list.fold(observations, #(controller, ControllerNominal("init", 0.0, 0.0, 0.0)), fn(acc, obs) {
      let #(c, _) = acc
      execute_full_poodavr_cycle(c, obs, 0.5, 50.0)
    })

  case verdict {
    ControllerNominal(_, filtered_estimate, energy, _action) -> {
      should.be_true(final_state.is_stable)
      should.be_false(final_state.andon_halt)
      // Check that estimate moved significantly towards 100.0 from initial 80.0
      should.be_true(filtered_estimate >. 90.0)
      should.be_true(energy <. 100.0)
    }
    ControllerAndonHalt(_cid, _stage, _reason, _code) -> {
      should.fail()
    }
  }
}

pub fn poodavr_lyapunov_divergence_andon_halt_test() {
  // Target setpoint = 100.0, initial estimate = 100.0 (already at equilibrium)
  let controller = new_controller("cycle-002", 100.0, 100.0)

  // Sudden catastrophic diverging measurement spike (e.g. sensor failure or fault)
  // Max divergence allowed is small (5.0), but observation spikes to 250.0 (energy jump > 10,000)
  let #(halted_state, verdict) =
    execute_full_poodavr_cycle(controller, 250.0, 0.5, 5.0)

  should.be_true(halted_state.andon_halt)
  should.be_false(halted_state.is_stable)

  case verdict {
    ControllerAndonHalt(cid, stage, reason, code) -> {
      cid |> should.equal("cycle-002")
      stage |> should.equal("Verify")
      code |> should.equal(-32002)
      should.be_true(reason != "")
    }
    ControllerNominal(_, _, _, _) -> should.fail()
  }

  // Once in Andon halt, further cycles must remain halted (idempotent fail-closed)
  let #(further_state, second_verdict) =
    execute_full_poodavr_cycle(halted_state, 100.0, 0.5, 5.0)

  should.be_true(further_state.andon_halt)
  case second_verdict {
    ControllerAndonHalt(_, _, _, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn poodavr_7_stages_recorded_test() {
  let controller = new_controller("cycle-003", 50.0, 48.0)
  let #(final_state, _) = execute_full_poodavr_cycle(controller, 49.5, 0.2, 10.0)

  // Verify all 7 stages recorded in history
  should.be_true(list.contains(final_state.stage_history, "Predict"))
  should.be_true(list.contains(final_state.stage_history, "Observe"))
  should.be_true(list.contains(final_state.stage_history, "Orient"))
  should.be_true(list.contains(final_state.stage_history, "Decide"))
  should.be_true(list.contains(final_state.stage_history, "Act"))
  should.be_true(list.contains(final_state.stage_history, "Verify:Passed"))
}
