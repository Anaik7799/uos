//// =============================================================================
//// [UOS-FPP-HOMEO-SIM-TEST] NASA JPL F Prime Simulated State Machine Test Suite
//// =============================================================================
//// Exhaustively validates the pure simulated execution semantics of all 5
//// F Prime Homeostasis State Machines:
//// 1. Prajna Circuit Breaker: Closed -> Open -> HalfOpen -> Closed / Open
//// 2. Dead-Man Watchdog: Fresh -> Warning -> Stale -> Dead -> Fresh (Fail-Closed)
//// 3. Swarm Cognitive OODA: Observe -> Orient -> Decide -> Act -> Observe
//// 4. Autonomous Evolutionary Gate: GateLocked -> GateArmed -> CandidateEval -> Canary -> Rollback
//// 5. Dynamic Tolerance Envelope: Centered <-> Drift <-> Breach
//// =============================================================================

import cepaf_gleam/fpp/homeostasis_fprime.{
  deadman_watchdog_fprime, evolution_gate_fprime, ooda_swarm_fprime,
  prajna_breaker_fprime, step_simulated, tolerance_envelope_fprime,
}
import cepaf_gleam/fpp/interp.{init_machine}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// -----------------------------------------------------------------------------
// 1. Prajna Circuit Breaker Simulated Suite
// -----------------------------------------------------------------------------

pub fn prajna_breaker_initial_state_test() {
  let machine = prajna_breaker_fprime()
  let assert Ok(state) = init_machine(machine)

  state.current |> should.equal("Closed")
  list.contains(state.log, "prajna_entry_closed") |> should.equal(True)
}

pub fn prajna_breaker_guard_trip_test() {
  let machine = prajna_breaker_fprime()
  let assert Ok(s0) = init_machine(machine)

  // Dispatched without guard: should be dropped, remaining in Closed
  let assert Ok(s_dropped) =
    step_simulated(machine, s0, "fault_detected", [
      #("fault_threshold_exceeded", False),
    ])
  s_dropped.current |> should.equal("Closed")

  // Dispatched with guard: trips to Open
  let assert Ok(s_open) =
    step_simulated(machine, s0, "fault_detected", [
      #("fault_threshold_exceeded", True),
    ])
  s_open.current |> should.equal("Open")
  list.contains(s_open.log, "trip_breaker") |> should.equal(True)
  list.contains(s_open.log, "isolate_subsystem") |> should.equal(True)
  list.contains(s_open.log, "start_cooldown_timer") |> should.equal(True)

  // Cooldown timer expires: transitions to HalfOpen
  let assert Ok(s_half) =
    step_simulated(machine, s_open, "cooldown_expired", [])
  s_half.current |> should.equal("HalfOpen")
  list.contains(s_half.log, "allow_single_canary_probe") |> should.equal(True)

  // Canary probe succeeds: restores to Closed
  let assert Ok(s_closed) =
    step_simulated(machine, s_half, "canary_success", [])
  s_closed.current |> should.equal("Closed")
  list.contains(s_closed.log, "restore_normal_service") |> should.equal(True)
}

pub fn prajna_breaker_canary_failure_re_trip_test() {
  let machine = prajna_breaker_fprime()
  let assert Ok(s0) = init_machine(machine)
  let assert Ok(s_open) =
    step_simulated(machine, s0, "fault_detected", [
      #("fault_threshold_exceeded", True),
    ])
  let assert Ok(s_half) =
    step_simulated(machine, s_open, "cooldown_expired", [])

  // Canary fails: re-trips back to Open
  let assert Ok(s_reopen) =
    step_simulated(machine, s_half, "canary_failure", [])
  s_reopen.current |> should.equal("Open")
  list.contains(s_reopen.log, "restart_backoff") |> should.equal(True)
}

// -----------------------------------------------------------------------------
// 2. Dead-Man Freshness Watchdog Simulated Suite
// -----------------------------------------------------------------------------

pub fn deadman_watchdog_fail_closed_cascade_test() {
  let machine = deadman_watchdog_fprime()
  let assert Ok(s0) = init_machine(machine)
  s0.current |> should.equal("Fresh")

  // 1. Age exceeds 2s -> Warning
  let assert Ok(s_warn) = step_simulated(machine, s0, "warning_timeout", [])
  s_warn.current |> should.equal("Warning")

  // 2. Age exceeds 5s -> Stale
  let assert Ok(s_stale) =
    step_simulated(machine, s_warn, "stale_timeout", [])
  s_stale.current |> should.equal("Stale")

  // 3. Age exceeds 10s -> Dead (Fail-Closed telemetry blanking)
  let assert Ok(s_dead) = step_simulated(machine, s_stale, "dead_timeout", [])
  s_dead.current |> should.equal("Dead")
  list.contains(s_dead.log, "suppress_telemetry_fail_closed")
  |> should.equal(True)
  list.contains(s_dead.log, "blank_telemetry_cells") |> should.equal(True)

  // 4. Heartbeat received without valid handshake: remains Dead
  let assert Ok(s_dead_still) =
    step_simulated(machine, s_dead, "heartbeat_tick", [
      #("handshake_revalidated", False),
    ])
  s_dead_still.current |> should.equal("Dead")

  // 5. Heartbeat received with valid handshake: restores to Fresh
  let assert Ok(s_restored) =
    step_simulated(machine, s_dead, "heartbeat_tick", [
      #("handshake_revalidated", True),
    ])
  s_restored.current |> should.equal("Fresh")
  list.contains(s_restored.log, "restore_live_telemetry") |> should.equal(True)
}

// -----------------------------------------------------------------------------
// 3. Swarm Cognitive OODA Loop Simulated Suite
// -----------------------------------------------------------------------------

pub fn ooda_swarm_full_cycle_test() {
  let machine = ooda_swarm_fprime()
  let assert Ok(s0) = init_machine(machine)
  s0.current |> should.equal("Observe")

  // Observe -> Orient
  let assert Ok(s1) = step_simulated(machine, s0, "telemetry_sampled", [])
  s1.current |> should.equal("Orient")
  list.contains(s1.log, "correlate_stamp_hazards") |> should.equal(True)

  // Orient -> Decide
  let assert Ok(s2) = step_simulated(machine, s1, "hypothesis_formed", [])
  s2.current |> should.equal("Decide")
  list.contains(s2.log, "tally_four_party_quorum") |> should.equal(True)

  // Decide without quorum: dropped
  let assert Ok(s_no_q) =
    step_simulated(machine, s2, "quorum_ratified", [
      #("supermajority_passed", False),
    ])
  s_no_q.current |> should.equal("Decide")

  // Decide with quorum: Act
  let assert Ok(s3) =
    step_simulated(machine, s2, "quorum_ratified", [
      #("supermajority_passed", True),
    ])
  s3.current |> should.equal("Act")
  list.contains(s3.log, "sign_sa_plan_action") |> should.equal(True)

  // Act -> Observe
  let assert Ok(s4) = step_simulated(machine, s3, "action_completed", [])
  s4.current |> should.equal("Observe")
  list.contains(s4.log, "record_trace_receipt") |> should.equal(True)
}

// -----------------------------------------------------------------------------
// 4. Autonomous Evolutionary Gate Simulated Suite
// -----------------------------------------------------------------------------

pub fn evolutionary_gate_lock_and_rollback_test() {
  let machine = evolution_gate_fprime()
  let assert Ok(s0) = init_machine(machine)
  s0.current |> should.equal("GateLocked")

  // Stability test passes: arm gate
  let assert Ok(s_armed) =
    step_simulated(machine, s0, "stability_check", [
      #("lyapunov_dissipative_and_quorum", True),
    ])
  s_armed.current |> should.equal("GateArmed")
  list.contains(s_armed.log, "arm_evolution_gate") |> should.equal(True)

  // Quorum ratified: select candidate
  let assert Ok(s_eval) =
    step_simulated(machine, s_armed, "quorum_ratified", [])
  s_eval.current |> should.equal("CandidateEvaluating")
  list.contains(s_eval.log, "select_pareto_candidate") |> should.equal(True)

  // Evaluation passes: deploy canary in Solo5 sandbox
  let assert Ok(s_canary) =
    step_simulated(machine, s_eval, "canary_eval_pass", [])
  s_canary.current |> should.equal("CanaryMutating")
  list.contains(s_canary.log, "deploy_solo5_sandbox") |> should.equal(True)

  // Canary fails / regresses: Andon rollback triggers, gate locks
  let assert Ok(s_rollback) =
    step_simulated(machine, s_canary, "canary_eval_fail", [])
  s_rollback.current |> should.equal("GateLocked")
  list.contains(s_rollback.log, "andon_rollback_generation")
  |> should.equal(True)
}

// -----------------------------------------------------------------------------
// 5. Dynamic Tolerance Envelope Simulated Suite
// -----------------------------------------------------------------------------

pub fn tolerance_envelope_displacement_test() {
  let machine = tolerance_envelope_fprime()
  let assert Ok(s0) = init_machine(machine)
  s0.current |> should.equal("Centered")

  // Drift Low
  let assert Ok(s_dlow) = step_simulated(machine, s0, "sample_drift_low", [])
  s_dlow.current |> should.equal("DriftLow")
  list.contains(s_dlow.log, "apply_restorative_pid_push") |> should.equal(True)

  // Breach Low
  let assert Ok(s_blow) =
    step_simulated(machine, s_dlow, "sample_breach_low", [])
  s_blow.current |> should.equal("BreachLow")
  list.contains(s_blow.log, "sound_low_boundary_alarm") |> should.equal(True)

  // Restore Nominal
  let assert Ok(s_nom) = step_simulated(machine, s_blow, "sample_nominal", [])
  s_nom.current |> should.equal("Centered")

  // Drift High
  let assert Ok(s_dhigh) =
    step_simulated(machine, s_nom, "sample_drift_high", [])
  s_dhigh.current |> should.equal("DriftHigh")
  list.contains(s_dhigh.log, "apply_damping_drag") |> should.equal(True)

  // Breach High
  let assert Ok(s_bhigh) =
    step_simulated(machine, s_dhigh, "sample_breach_high", [])
  s_bhigh.current |> should.equal("BreachHigh")
  list.contains(s_bhigh.log, "sound_high_boundary_alarm") |> should.equal(True)
}
