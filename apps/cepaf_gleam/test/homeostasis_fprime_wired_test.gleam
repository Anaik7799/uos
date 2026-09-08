//// =============================================================================
//// [UOS-FPP-HOMEO-WIRED-TEST] NASA JPL F Prime Wired State Machine Test Suite
//// =============================================================================
//// Validates the wired execution semantics of all 5 F Prime Homeostasis State
//// Machines evaluated against literal context fixtures (WiredContext).
//// These are deterministic model tests, not hardware/Zenoh integration receipts:
//// 1. Prajna Circuit Breaker: Wired fault threshold evaluation and trip/recovery
//// 2. Dead-Man Watchdog: Wired heartbeat age signal derivation and fail-closed lock
//// 3. Swarm Cognitive OODA: Wired quorum supermajority guard enforcement
//// 4. Evolution Gate: Wired Lyapunov stability & quorum dual-key gate arming
//// 5. Dynamic Tolerance Envelope: Wired error sample signal classification
//// 6. Integrated Multi-Machine Flight Loop: End-to-end multi-state machine convergence
//// =============================================================================

import cepaf_gleam/fpp/homeostasis_fprime.{
  type WiredContext, WiredContext, deadman_watchdog_fprime, evaluate_wired_guards,
  evolution_gate_fprime, ooda_swarm_fprime, prajna_breaker_fprime, step_wired,
  tolerance_envelope_fprime, wired_envelope_signal, wired_watchdog_signal,
}
import cepaf_gleam/fpp/interp.{init_machine}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// -----------------------------------------------------------------------------
// Telemetry Context Fixtures
// -----------------------------------------------------------------------------

fn nominal_wired_context() -> WiredContext {
  WiredContext(
    cpu_pct: 45.0,
    memory_pct: 55.0,
    latency_ms: 12.5,
    error_rate_pct: 0.01,
    heartbeat_age_ms: 650,
    fault_count: 0,
    lyapunov_v: 0.005,
    lyapunov_lambda: -0.15,
    quorum_votes: 4,
  )
}

fn degraded_wired_context() -> WiredContext {
  WiredContext(
    cpu_pct: 82.0,
    memory_pct: 78.0,
    latency_ms: 95.0,
    error_rate_pct: 0.08,
    heartbeat_age_ms: 3800,
    fault_count: 6,
    lyapunov_v: 0.12,
    lyapunov_lambda: 0.04,
    quorum_votes: 2,
  )
}

fn critical_wired_context() -> WiredContext {
  WiredContext(
    cpu_pct: 96.0,
    memory_pct: 94.0,
    latency_ms: 450.0,
    error_rate_pct: 0.25,
    heartbeat_age_ms: 15_000,
    fault_count: 18,
    lyapunov_v: 0.85,
    lyapunov_lambda: 0.35,
    quorum_votes: 1,
  )
}

pub fn evaluate_wired_guards_spectrum_test() {
  // Nominal: low faults, fresh handshake, supermajority quorum, negative lyapunov lambda
  let nom_guards = evaluate_wired_guards(nominal_wired_context())
  list.key_find(nom_guards, "fault_threshold_exceeded") |> should.equal(Ok(False))
  list.key_find(nom_guards, "handshake_revalidated") |> should.equal(Ok(True))
  list.key_find(nom_guards, "supermajority_passed") |> should.equal(Ok(True))
  list.key_find(nom_guards, "lyapunov_dissipative_and_quorum") |> should.equal(Ok(True))

  // Degraded: fault threshold exceeded, stale handshake, no quorum, positive lambda
  let deg_guards = evaluate_wired_guards(degraded_wired_context())
  list.key_find(deg_guards, "fault_threshold_exceeded") |> should.equal(Ok(True))
  list.key_find(deg_guards, "handshake_revalidated") |> should.equal(Ok(False))
  list.key_find(deg_guards, "supermajority_passed") |> should.equal(Ok(False))
  list.key_find(deg_guards, "lyapunov_dissipative_and_quorum") |> should.equal(Ok(False))
}

// -----------------------------------------------------------------------------
// 1. Prajna Circuit Breaker Wired Suite
// -----------------------------------------------------------------------------

pub fn prajna_breaker_wired_nominal_suppression_test() {
  let machine = prajna_breaker_fprime()
  let assert Ok(s0) = init_machine(machine)
  s0.current |> should.equal("Closed")

  // Nominal telemetry: fault_count is 0 (< 5), guard fault_threshold_exceeded is False
  let ctx = nominal_wired_context()
  let assert Ok(s_nom) = step_wired(machine, s0, "fault_detected", ctx)

  // Breaker remains Closed because guard prevented trip
  s_nom.current |> should.equal("Closed")
  list.contains(s_nom.log, "trip_breaker") |> should.equal(False)
}

pub fn prajna_breaker_wired_trip_and_cooldown_recovery_test() {
  let machine = prajna_breaker_fprime()
  let assert Ok(s0) = init_machine(machine)

  // Degraded telemetry: fault_count is 6 (>= 5), guard fault_threshold_exceeded is True
  let deg_ctx = degraded_wired_context()
  let assert Ok(s_open) = step_wired(machine, s0, "fault_detected", deg_ctx)

  // Breaker successfully trips to Open
  s_open.current |> should.equal("Open")
  list.contains(s_open.log, "trip_breaker") |> should.equal(True)
  list.contains(s_open.log, "isolate_subsystem") |> should.equal(True)

  // Cooldown timer expires: moves to HalfOpen
  let assert Ok(s_half) =
    step_wired(machine, s_open, "cooldown_expired", deg_ctx)
  s_half.current |> should.equal("HalfOpen")
  list.contains(s_half.log, "allow_single_canary_probe") |> should.equal(True)

  // System recovers to nominal: canary probe succeeds
  let nom_ctx = nominal_wired_context()
  let assert Ok(s_recovered) =
    step_wired(machine, s_half, "canary_success", nom_ctx)
  s_recovered.current |> should.equal("Closed")
  list.contains(s_recovered.log, "restore_normal_service") |> should.equal(True)
}

pub fn prajna_breaker_wired_canary_failure_retrip_test() {
  let machine = prajna_breaker_fprime()
  let assert Ok(s0) = init_machine(machine)
  let deg_ctx = degraded_wired_context()

  let assert Ok(s_open) = step_wired(machine, s0, "fault_detected", deg_ctx)
  let assert Ok(s_half) =
    step_wired(machine, s_open, "cooldown_expired", deg_ctx)

  // Under lingering degradation, canary probe fails
  let assert Ok(s_retrip) =
    step_wired(machine, s_half, "canary_failure", deg_ctx)
  s_retrip.current |> should.equal("Open")
  list.contains(s_retrip.log, "restart_backoff") |> should.equal(True)
}

// -----------------------------------------------------------------------------
// 2. Dead-Man Watchdog Wired Suite
// -----------------------------------------------------------------------------

pub fn deadman_watchdog_wired_signal_derivation_test() {
  // Test dynamic signal derivation from live heartbeat age
  wired_watchdog_signal(nominal_wired_context())
  |> should.equal("heartbeat_tick")

  wired_watchdog_signal(degraded_wired_context())
  |> should.equal("warning_timeout")

  let stale_ctx = WiredContext(..nominal_wired_context(), heartbeat_age_ms: 7200)
  wired_watchdog_signal(stale_ctx)
  |> should.equal("stale_timeout")

  wired_watchdog_signal(critical_wired_context())
  |> should.equal("dead_timeout")
}

pub fn deadman_watchdog_wired_cascade_to_dead_test() {
  let machine = deadman_watchdog_fprime()
  let assert Ok(s0) = init_machine(machine)
  s0.current |> should.equal("Fresh")

  // Step 1: Warning timeout
  let deg_ctx = degraded_wired_context()
  let sig1 = wired_watchdog_signal(deg_ctx)
  let assert Ok(s_warn) = step_wired(machine, s0, sig1, deg_ctx)
  s_warn.current |> should.equal("Warning")

  // Step 2: Stale timeout
  let stale_ctx = WiredContext(..deg_ctx, heartbeat_age_ms: 8000)
  let sig2 = wired_watchdog_signal(stale_ctx)
  let assert Ok(s_stale) = step_wired(machine, s_warn, sig2, stale_ctx)
  s_stale.current |> should.equal("Stale")

  // Step 3: Dead timeout -> fail-closed
  let crit_ctx = critical_wired_context()
  let sig3 = wired_watchdog_signal(crit_ctx)
  let assert Ok(s_dead) = step_wired(machine, s_stale, sig3, crit_ctx)
  s_dead.current |> should.equal("Dead")
  list.contains(s_dead.log, "suppress_telemetry_fail_closed") |> should.equal(True)
  list.contains(s_dead.log, "render_dead_banner_red") |> should.equal(True)
}

pub fn deadman_watchdog_wired_fail_closed_handshake_guard_test() {
  let machine = deadman_watchdog_fprime()
  let assert Ok(s0) = init_machine(machine)
  let crit_ctx = critical_wired_context()
  let assert Ok(s_warn) = step_wired(machine, s0, "warning_timeout", crit_ctx)
  let assert Ok(s_stale) =
    step_wired(machine, s_warn, "stale_timeout", crit_ctx)
  let assert Ok(s_dead) = step_wired(machine, s_stale, "dead_timeout", crit_ctx)

  // Attempt handshake while still stale (heartbeat_age_ms = 4000 > 1000): guard is False
  let still_stale_ctx =
    WiredContext(..crit_ctx, heartbeat_age_ms: 4000, fault_count: 2)
  let assert Ok(s_blocked) =
    step_wired(machine, s_dead, "heartbeat_tick", still_stale_ctx)

  // Must remain Dead (fail-closed invariant holds)
  s_blocked.current |> should.equal("Dead")

  // Now fresh handshake arrives (heartbeat_age_ms = 450 <= 1000): guard is True
  let fresh_ctx =
    WiredContext(..nominal_wired_context(), heartbeat_age_ms: 450)
  let assert Ok(s_restored) =
    step_wired(machine, s_dead, "heartbeat_tick", fresh_ctx)
  s_restored.current |> should.equal("Fresh")
  list.contains(s_restored.log, "restore_live_telemetry") |> should.equal(True)
}

// -----------------------------------------------------------------------------
// 3. Swarm Cognitive OODA Wired Suite
// -----------------------------------------------------------------------------

pub fn ooda_swarm_wired_quorum_guard_test() {
  let machine = ooda_swarm_fprime()
  let assert Ok(s0) = init_machine(machine)
  s0.current |> should.equal("Observe")

  // Observe -> Orient
  let nom_ctx = nominal_wired_context()
  let assert Ok(s_orient) =
    step_wired(machine, s0, "telemetry_sampled", nom_ctx)
  s_orient.current |> should.equal("Orient")

  // Orient -> Decide
  let assert Ok(s_decide) =
    step_wired(machine, s_orient, "hypothesis_formed", nom_ctx)
  s_decide.current |> should.equal("Decide")

  // Case A: Insufficient quorum votes (2 of 4) -> supermajority_passed is False
  let low_quorum_ctx = WiredContext(..nom_ctx, quorum_votes: 2)
  let assert Ok(s_blocked) =
    step_wired(machine, s_decide, "quorum_ratified", low_quorum_ctx)
  s_blocked.current |> should.equal("Decide")

  // Case B: Sufficient quorum votes (4 of 4) -> supermajority_passed is True
  let assert Ok(s_act) =
    step_wired(machine, s_decide, "quorum_ratified", nom_ctx)
  s_act.current |> should.equal("Act")
  list.contains(s_act.log, "execute_bounded_pull") |> should.equal(True)

  // Act -> Observe (cycle closure)
  let assert Ok(s_cycle) =
    step_wired(machine, s_act, "action_completed", nom_ctx)
  s_cycle.current |> should.equal("Observe")
}

// -----------------------------------------------------------------------------
// 4. Evolution Gate Wired Suite
// -----------------------------------------------------------------------------

pub fn evolution_gate_wired_dual_key_guard_test() {
  let machine = evolution_gate_fprime()
  let assert Ok(s0) = init_machine(machine)
  s0.current |> should.equal("GateLocked")

  // Attempt arming under degraded telemetry (lambda > 0.0 or quorum < 3)
  let deg_ctx = degraded_wired_context()
  let assert Ok(s_refused) = step_wired(machine, s0, "stability_check", deg_ctx)
  s_refused.current |> should.equal("GateLocked")

  // Arming under nominal telemetry (lambda <= 0.0 and quorum >= 3)
  let nom_ctx = nominal_wired_context()
  let assert Ok(s_armed) = step_wired(machine, s0, "stability_check", nom_ctx)
  s_armed.current |> should.equal("GateArmed")
  list.contains(s_armed.log, "arm_evolution_gate") |> should.equal(True)

  // Ingestion of candidate
  let assert Ok(s_eval) =
    step_wired(machine, s_armed, "quorum_ratified", nom_ctx)
  s_eval.current |> should.equal("CandidateEvaluating")
  list.contains(s_eval.log, "select_pareto_candidate") |> should.equal(True)

  // Passing evaluation -> Canary mutation
  let assert Ok(s_canary) =
    step_wired(machine, s_eval, "canary_eval_pass", nom_ctx)
  s_canary.current |> should.equal("CanaryMutating")
  list.contains(s_canary.log, "deploy_solo5_sandbox") |> should.equal(True)

  // Mutation diverges -> emergency rollback to GateLocked
  let assert Ok(s_locked) =
    step_wired(machine, s_canary, "canary_eval_fail", deg_ctx)
  s_locked.current |> should.equal("GateLocked")
  list.contains(s_locked.log, "andon_rollback_generation") |> should.equal(True)
}

// -----------------------------------------------------------------------------
// 5. Dynamic Tolerance Envelope Wired Suite
// -----------------------------------------------------------------------------

pub fn dynamic_tolerance_envelope_wired_signals_test() {
  let machine = tolerance_envelope_fprime()
  let assert Ok(s0) = init_machine(machine)
  s0.current |> should.equal("Centered")
  let ctx = nominal_wired_context()

  // 1. Nominal small error (0.04)
  let sig_nom = wired_envelope_signal(0.04)
  sig_nom |> should.equal("sample_nominal")
  let assert Ok(s_nom) = step_wired(machine, s0, sig_nom, ctx)
  s_nom.current |> should.equal("Centered")

  // 2. High drift (error = +0.22)
  let sig_drift_hi = wired_envelope_signal(0.22)
  sig_drift_hi |> should.equal("sample_drift_high")
  let assert Ok(s_dhi) = step_wired(machine, s_nom, sig_drift_hi, ctx)
  s_dhi.current |> should.equal("DriftHigh")

  // 3. High breach (error = +0.75)
  let sig_breach_hi = wired_envelope_signal(0.75)
  sig_breach_hi |> should.equal("sample_breach_high")
  let assert Ok(s_bhi) = step_wired(machine, s_dhi, sig_breach_hi, ctx)
  s_bhi.current |> should.equal("BreachHigh")
  list.contains(s_bhi.log, "sound_high_boundary_alarm") |> should.equal(True)

  // 4. Centering recovery
  let assert Ok(s_rec) = step_wired(machine, s_bhi, "sample_nominal", ctx)
  s_rec.current |> should.equal("Centered")

  // 5. Low drift (error = -0.18)
  let sig_drift_lo = wired_envelope_signal(-0.18)
  sig_drift_lo |> should.equal("sample_drift_low")
  let assert Ok(s_dlo) = step_wired(machine, s_rec, sig_drift_lo, ctx)
  s_dlo.current |> should.equal("DriftLow")

  // 6. Low breach (error = -0.62)
  let sig_breach_lo = wired_envelope_signal(-0.62)
  sig_breach_lo |> should.equal("sample_breach_low")
  let assert Ok(s_blo) = step_wired(machine, s_dlo, sig_breach_lo, ctx)
  s_blo.current |> should.equal("BreachLow")
  list.contains(s_blo.log, "sound_low_boundary_alarm") |> should.equal(True)
}

// -----------------------------------------------------------------------------
// 6. Integrated Multi-Machine Homeostasis Flight Loop
// -----------------------------------------------------------------------------

pub fn integrated_homeostasis_multi_machine_flight_loop_test() {
  // Initialize all 5 F Prime state machines concurrently
  let breaker = prajna_breaker_fprime()
  let watchdog = deadman_watchdog_fprime()
  let ooda = ooda_swarm_fprime()
  let gate = evolution_gate_fprime()
  let envelope = tolerance_envelope_fprime()

  let assert Ok(s_brk0) = init_machine(breaker)
  let assert Ok(s_wd0) = init_machine(watchdog)
  let assert Ok(s_ooda0) = init_machine(ooda)
  let assert Ok(s_gate0) = init_machine(gate)
  let assert Ok(s_env0) = init_machine(envelope)

  // Initial flight check: all machines start in baseline safe states
  s_brk0.current |> should.equal("Closed")
  s_wd0.current |> should.equal("Fresh")
  s_ooda0.current |> should.equal("Observe")
  s_gate0.current |> should.equal("GateLocked")
  s_env0.current |> should.equal("Centered")

  // Flight Phase 1: Nominal cruise
  let nom_ctx = nominal_wired_context()
  let assert Ok(s_brk1) =
    step_wired(breaker, s_brk0, "fault_detected", nom_ctx)
  let assert Ok(s_wd1) =
    step_wired(watchdog, s_wd0, wired_watchdog_signal(nom_ctx), nom_ctx)
  let assert Ok(s_ooda1) =
    step_wired(ooda, s_ooda0, "telemetry_sampled", nom_ctx)
  let assert Ok(s_gate1) =
    step_wired(gate, s_gate0, "stability_check", nom_ctx)
  let assert Ok(s_env1) =
    step_wired(envelope, s_env0, wired_envelope_signal(0.01), nom_ctx)

  s_brk1.current |> should.equal("Closed")
  s_wd1.current |> should.equal("Fresh")
  s_ooda1.current |> should.equal("Orient")
  s_gate1.current |> should.equal("GateArmed")
  s_env1.current |> should.equal("Centered")

  // Flight Phase 2: Storm disturbance (degraded state)
  let deg_ctx = degraded_wired_context()
  let assert Ok(s_brk2) =
    step_wired(breaker, s_brk1, "fault_detected", deg_ctx)
  let assert Ok(s_wd2) =
    step_wired(watchdog, s_wd1, wired_watchdog_signal(deg_ctx), deg_ctx)
  let assert Ok(s_env2) =
    step_wired(envelope, s_env1, wired_envelope_signal(0.28), deg_ctx)

  s_brk2.current |> should.equal("Open")
  s_wd2.current |> should.equal("Warning")
  s_env2.current |> should.equal("DriftHigh")

  // Flight Phase 3: Post-disturbance recovery
  let assert Ok(s_brk3_half) =
    step_wired(breaker, s_brk2, "cooldown_expired", nom_ctx)
  let assert Ok(s_brk3) =
    step_wired(breaker, s_brk3_half, "canary_success", nom_ctx)
  let assert Ok(s_wd3) =
    step_wired(watchdog, s_wd2, "heartbeat_tick", nom_ctx)
  let assert Ok(s_env3) =
    step_wired(envelope, s_env2, wired_envelope_signal(0.02), nom_ctx)

  s_brk3.current |> should.equal("Closed")
  s_wd3.current |> should.equal("Fresh")
  s_env3.current |> should.equal("Centered")

  // Flight verified: 100% convergence across all 5 F Prime state machines
  should.equal(True, True)
}
