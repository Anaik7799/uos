//// =============================================================================
//// [UOS-FPP-HOMEO] NASA JPL F Prime (F') State Machines for Homeostasis Monitoring
//// =============================================================================
//// Formally encodes the 5 core Homeostasis State Machines into NASA JPL FPP
//// specifications in pure Gleam, supporting both Simulated and Wired execution:
//// 1. Prajna Circuit Breaker FSM (Closed <-> HalfOpen <-> Open)
//// 2. Dead-Man Freshness Watchdog FSM (Fresh -> Warning -> Stale -> Dead)
//// 3. Swarm Cognitive OODA FSM (Observe -> Orient -> Decide -> Act)
//// 4. Autonomous Evolutionary Gate FSM (GateLocked <-> GateArmed <-> Canary)
//// 5. Dynamic Tolerance Envelope FSM (Centered <-> Drift <-> Breach)
//// =============================================================================

import cepaf_gleam/fpp/domain.{
  type StateMachine, InternalMachine, SignalDef, State, ToState, Transition,
}
import cepaf_gleam/fpp/interp.{type MachineState, dispatch_signal}
import gleam/option.{None, Some}

// -----------------------------------------------------------------------------
// 1. Prajna Circuit Breaker F Prime State Machine
// -----------------------------------------------------------------------------

pub fn prajna_breaker_fprime() -> StateMachine {
  let signals = [
    SignalDef("fault_detected", None),
    SignalDef("cooldown_expired", None),
    SignalDef("canary_success", None),
    SignalDef("canary_failure", None),
  ]

  let closed_state =
    State(
      state_name: "Closed",
      entry: ["prajna_entry_closed"],
      exit: ["prajna_exit_closed"],
      transitions: [
        Transition(
          on_signal: "fault_detected",
          guard: Some("fault_threshold_exceeded"),
          do_actions: ["trip_breaker", "isolate_subsystem"],
          target: ToState("Open"),
        ),
      ],
    )

  let open_state =
    State(
      state_name: "Open",
      entry: ["prajna_entry_open", "start_cooldown_timer"],
      exit: ["prajna_exit_open"],
      transitions: [
        Transition(
          on_signal: "cooldown_expired",
          guard: None,
          do_actions: ["allow_single_canary_probe"],
          target: ToState("HalfOpen"),
        ),
      ],
    )

  let half_open_state =
    State(
      state_name: "HalfOpen",
      entry: ["prajna_entry_half_open"],
      exit: ["prajna_exit_half_open"],
      transitions: [
        Transition(
          on_signal: "canary_success",
          guard: None,
          do_actions: ["reset_fault_counter", "restore_normal_service"],
          target: ToState("Closed"),
        ),
        Transition(
          on_signal: "canary_failure",
          guard: None,
          do_actions: ["trip_breaker", "restart_backoff"],
          target: ToState("Open"),
        ),
      ],
    )

  InternalMachine(
    machine_name: "PrajnaCircuitBreaker",
    signals: signals,
    guards: ["fault_threshold_exceeded"],
    actions: [
      "trip_breaker",
      "isolate_subsystem",
      "allow_single_canary_probe",
      "reset_fault_counter",
      "restore_normal_service",
    ],
    states: [closed_state, open_state, half_open_state],
    choices: [],
    initial: #([], "Closed"),
  )
}

// -----------------------------------------------------------------------------
// 2. Dead-Man Freshness Watchdog F Prime State Machine
// -----------------------------------------------------------------------------

pub fn deadman_watchdog_fprime() -> StateMachine {
  let signals = [
    SignalDef("heartbeat_tick", None),
    SignalDef("warning_timeout", None),
    SignalDef("stale_timeout", None),
    SignalDef("dead_timeout", None),
  ]

  let fresh_state =
    State(
      state_name: "Fresh",
      entry: ["render_fresh_badge_green"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "warning_timeout",
          guard: None,
          do_actions: ["log_freshness_warning"],
          target: ToState("Warning"),
        ),
        Transition(
          on_signal: "heartbeat_tick",
          guard: None,
          do_actions: ["reset_watchdog_clock"],
          target: ToState("Fresh"),
        ),
      ],
    )

  let warning_state =
    State(
      state_name: "Warning",
      entry: ["render_warning_badge_yellow"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "heartbeat_tick",
          guard: None,
          do_actions: ["reset_watchdog_clock"],
          target: ToState("Fresh"),
        ),
        Transition(
          on_signal: "stale_timeout",
          guard: None,
          do_actions: ["log_freshness_stale"],
          target: ToState("Stale"),
        ),
      ],
    )

  let stale_state =
    State(
      state_name: "Stale",
      entry: ["render_stale_badge_orange"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "heartbeat_tick",
          guard: None,
          do_actions: ["reset_watchdog_clock"],
          target: ToState("Fresh"),
        ),
        Transition(
          on_signal: "dead_timeout",
          guard: None,
          do_actions: ["suppress_telemetry_fail_closed", "emit_dead_alert"],
          target: ToState("Dead"),
        ),
      ],
    )

  let dead_state =
    State(
      state_name: "Dead",
      entry: ["render_dead_banner_red", "blank_telemetry_cells"],
      exit: ["clear_dead_banner"],
      transitions: [
        Transition(
          on_signal: "heartbeat_tick",
          guard: Some("handshake_revalidated"),
          do_actions: ["restore_live_telemetry"],
          target: ToState("Fresh"),
        ),
      ],
    )

  InternalMachine(
    machine_name: "DeadManWatchdog",
    signals: signals,
    guards: ["handshake_revalidated"],
    actions: [
      "render_fresh_badge_green",
      "render_warning_badge_yellow",
      "render_stale_badge_orange",
      "render_dead_banner_red",
      "suppress_telemetry_fail_closed",
      "restore_live_telemetry",
    ],
    states: [fresh_state, warning_state, stale_state, dead_state],
    choices: [],
    initial: #([], "Fresh"),
  )
}

// -----------------------------------------------------------------------------
// 3. Swarm Cognitive OODA F Prime State Machine
// -----------------------------------------------------------------------------

pub fn ooda_swarm_fprime() -> StateMachine {
  let signals = [
    SignalDef("telemetry_sampled", None),
    SignalDef("hypothesis_formed", None),
    SignalDef("quorum_ratified", None),
    SignalDef("action_completed", None),
    SignalDef("safety_veto", None),
  ]

  let observe_state =
    State(
      state_name: "Observe",
      entry: ["poll_zenoh_telemetry"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "telemetry_sampled",
          guard: None,
          do_actions: ["ingest_sensor_matrix"],
          target: ToState("Orient"),
        ),
      ],
    )

  let orient_state =
    State(
      state_name: "Orient",
      entry: ["correlate_stamp_hazards"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "hypothesis_formed",
          guard: None,
          do_actions: ["propose_mitigation_action"],
          target: ToState("Decide"),
        ),
        Transition(
          on_signal: "safety_veto",
          guard: None,
          do_actions: ["fallback_constitutional_safe"],
          target: ToState("Observe"),
        ),
      ],
    )

  let decide_state =
    State(
      state_name: "Decide",
      entry: ["tally_four_party_quorum"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "quorum_ratified",
          guard: Some("supermajority_passed"),
          do_actions: ["sign_sa_plan_action"],
          target: ToState("Act"),
        ),
        Transition(
          on_signal: "safety_veto",
          guard: None,
          do_actions: ["drop_unratified_action"],
          target: ToState("Observe"),
        ),
      ],
    )

  let act_state =
    State(
      state_name: "Act",
      entry: ["execute_bounded_pull"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "action_completed",
          guard: None,
          do_actions: ["record_trace_receipt"],
          target: ToState("Observe"),
        ),
      ],
    )

  InternalMachine(
    machine_name: "SwarmOodaCognition",
    signals: signals,
    guards: ["supermajority_passed"],
    actions: [
      "poll_zenoh_telemetry",
      "ingest_sensor_matrix",
      "propose_mitigation_action",
      "sign_sa_plan_action",
      "record_trace_receipt",
    ],
    states: [observe_state, orient_state, decide_state, act_state],
    choices: [],
    initial: #([], "Observe"),
  )
}

// -----------------------------------------------------------------------------
// 4. Autonomous Evolutionary Gate F Prime State Machine
// -----------------------------------------------------------------------------

pub fn evolution_gate_fprime() -> StateMachine {
  let signals = [
    SignalDef("stability_check", None),
    SignalDef("quorum_ratified", None),
    SignalDef("canary_eval_pass", None),
    SignalDef("canary_eval_fail", None),
    SignalDef("lock_gate", None),
  ]

  let locked_state =
    State(
      state_name: "GateLocked",
      entry: ["inhibit_all_mutations", "render_locked_badge"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "stability_check",
          guard: Some("lyapunov_dissipative_and_quorum"),
          do_actions: ["arm_evolution_gate"],
          target: ToState("GateArmed"),
        ),
      ],
    )

  let armed_state =
    State(
      state_name: "GateArmed",
      entry: ["render_armed_badge"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "quorum_ratified",
          guard: None,
          do_actions: ["select_pareto_candidate"],
          target: ToState("CandidateEvaluating"),
        ),
        Transition(
          on_signal: "lock_gate",
          guard: None,
          do_actions: ["disarm_gate"],
          target: ToState("GateLocked"),
        ),
      ],
    )

  let evaluating_state =
    State(
      state_name: "CandidateEvaluating",
      entry: ["run_gospel_verification"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "canary_eval_pass",
          guard: None,
          do_actions: ["deploy_solo5_sandbox"],
          target: ToState("CanaryMutating"),
        ),
        Transition(
          on_signal: "canary_eval_fail",
          guard: None,
          do_actions: ["quarantine_candidate"],
          target: ToState("GateLocked"),
        ),
      ],
    )

  let canary_state =
    State(
      state_name: "CanaryMutating",
      entry: ["monitor_canary_stability"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "canary_eval_pass",
          guard: None,
          do_actions: ["promote_candidate_to_main"],
          target: ToState("GateArmed"),
        ),
        Transition(
          on_signal: "canary_eval_fail",
          guard: None,
          do_actions: ["andon_rollback_generation"],
          target: ToState("GateLocked"),
        ),
      ],
    )

  InternalMachine(
    machine_name: "EvolutionaryGate",
    signals: signals,
    guards: ["lyapunov_dissipative_and_quorum"],
    actions: [
      "inhibit_all_mutations",
      "arm_evolution_gate",
      "select_pareto_candidate",
      "deploy_solo5_sandbox",
      "andon_rollback_generation",
      "promote_candidate_to_main",
    ],
    states: [locked_state, armed_state, evaluating_state, canary_state],
    choices: [],
    initial: #([], "GateLocked"),
  )
}

// -----------------------------------------------------------------------------
// 5. Dynamic Tolerance Envelope F Prime State Machine
// -----------------------------------------------------------------------------

pub fn tolerance_envelope_fprime() -> StateMachine {
  let signals = [
    SignalDef("sample_nominal", None),
    SignalDef("sample_drift_low", None),
    SignalDef("sample_drift_high", None),
    SignalDef("sample_breach_low", None),
    SignalDef("sample_breach_high", None),
  ]

  let centered_state =
    State(
      state_name: "Centered",
      entry: ["render_gauge_centered"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "sample_drift_low",
          guard: None,
          do_actions: ["render_gauge_drift_low"],
          target: ToState("DriftLow"),
        ),
        Transition(
          on_signal: "sample_drift_high",
          guard: None,
          do_actions: ["render_gauge_drift_high"],
          target: ToState("DriftHigh"),
        ),
      ],
    )

  let drift_low_state =
    State(
      state_name: "DriftLow",
      entry: ["apply_restorative_pid_push"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "sample_nominal",
          guard: None,
          do_actions: [],
          target: ToState("Centered"),
        ),
        Transition(
          on_signal: "sample_breach_low",
          guard: None,
          do_actions: ["sound_low_boundary_alarm"],
          target: ToState("BreachLow"),
        ),
      ],
    )

  let drift_high_state =
    State(
      state_name: "DriftHigh",
      entry: ["apply_damping_drag"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "sample_nominal",
          guard: None,
          do_actions: [],
          target: ToState("Centered"),
        ),
        Transition(
          on_signal: "sample_breach_high",
          guard: None,
          do_actions: ["sound_high_boundary_alarm"],
          target: ToState("BreachHigh"),
        ),
      ],
    )

  let breach_low_state =
    State(
      state_name: "BreachLow",
      entry: ["flash_red_low_breach"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "sample_nominal",
          guard: None,
          do_actions: ["clear_low_breach_alarm"],
          target: ToState("Centered"),
        ),
      ],
    )

  let breach_high_state =
    State(
      state_name: "BreachHigh",
      entry: ["flash_red_high_breach"],
      exit: [],
      transitions: [
        Transition(
          on_signal: "sample_nominal",
          guard: None,
          do_actions: ["clear_high_breach_alarm"],
          target: ToState("Centered"),
        ),
      ],
    )

  InternalMachine(
    machine_name: "ToleranceEnvelope",
    signals: signals,
    guards: [],
    actions: [
      "render_gauge_centered",
      "render_gauge_drift_low",
      "render_gauge_drift_high",
      "sound_low_boundary_alarm",
      "sound_high_boundary_alarm",
    ],
    states: [
      centered_state,
      drift_low_state,
      drift_high_state,
      breach_low_state,
      breach_high_state,
    ],
    choices: [],
    initial: #([], "Centered"),
  )
}

// -----------------------------------------------------------------------------
// 6. Unified Simulated & Wired Dispatch Interfaces
// -----------------------------------------------------------------------------

/// Execute a simulated step on any F Prime state machine
pub fn step_simulated(
  machine: StateMachine,
  current: MachineState,
  signal: String,
  guards: List(#(String, Bool)),
) -> Result(MachineState, String) {
  dispatch_signal(machine, guards, current, signal)
}

/// Caller-supplied context for a pure state-machine calculation.
/// This type does not itself read hardware or establish sensor provenance.
pub type WiredContext {
  WiredContext(
    cpu_pct: Float,
    memory_pct: Float,
    latency_ms: Float,
    error_rate_pct: Float,
    heartbeat_age_ms: Int,
    fault_count: Int,
    lyapunov_v: Float,
    lyapunov_lambda: Float,
    quorum_votes: Int,
  )
}

pub fn valid_wired_context(ctx: WiredContext) -> Bool {
  ctx.cpu_pct >=. 0.0 && ctx.cpu_pct <=. 100.0
  && ctx.memory_pct >=. 0.0 && ctx.memory_pct <=. 100.0
  && ctx.latency_ms >=. 0.0 && ctx.error_rate_pct >=. 0.0
  && ctx.error_rate_pct <=. 100.0 && ctx.heartbeat_age_ms >= 0
  && ctx.fault_count >= 0 && ctx.lyapunov_v >=. 0.0
  && ctx.quorum_votes >= 0 && ctx.quorum_votes <= 4
}

/// Validate the context before permitting a positive guard.
pub fn evaluate_wired_guards(ctx: WiredContext) -> List(#(String, Bool)) {
  let valid = valid_wired_context(ctx)
  [
    #("fault_threshold_exceeded", !valid || ctx.fault_count >= 5),
    #("handshake_revalidated", valid && ctx.heartbeat_age_ms <= 1000),
    #("supermajority_passed", valid && ctx.quorum_votes >= 3),
    #(
      "lyapunov_dissipative_and_quorum",
      valid && ctx.lyapunov_lambda <=. 0.0 && ctx.quorum_votes >= 3,
    ),
  ]
}

/// Derive appropriate live FPP signal from wired context for Watchdog
pub fn wired_watchdog_signal(ctx: WiredContext) -> String {
  case valid_wired_context(ctx), ctx.heartbeat_age_ms {
    False, _ -> "dead_timeout"
    True, age if age <= 2000 -> "heartbeat_tick"
    True, age if age <= 5000 -> "warning_timeout"
    True, age if age <= 10000 -> "stale_timeout"
    True, _ -> "dead_timeout"
  }
}

/// Derive appropriate live FPP signal from wired context for Tolerance Envelope
pub fn wired_envelope_signal(error: Float) -> String {
  case error {
    e if e >. 0.50 -> "sample_breach_high"
    e if e >. 0.10 -> "sample_drift_high"
    e if e <. -0.50 -> "sample_breach_low"
    e if e <. -0.10 -> "sample_drift_low"
    _ -> "sample_nominal"
  }
}

/// Compute a model transition. Returned action labels do not execute effects.
pub fn step_wired(
  machine: StateMachine,
  current: MachineState,
  signal: String,
  ctx: WiredContext,
) -> Result(MachineState, String) {
  case valid_wired_context(ctx) {
    False -> Error("invalid wired context")
    True -> dispatch_signal(machine, evaluate_wired_guards(ctx), current, signal)
  }
}
