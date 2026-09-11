//// =============================================================================
//// [UOS-FPP-POODAVR] NASA JPL F Prime (F') POODAVR 7-Stage Cybernetic Loop FSM
//// =============================================================================
//// Canonical FPP metamodel implementation of the 7-stage POODAVR Cybernetic Loop:
//// 1. Predicting (Lyapunov energy V(x) prior & Kalman estimation)
//// 2. Observing (Sensory ingest, Zenoh pub/sub, UTC microsecond Z)
//// 3. Orienting (PII scrub, STAMP hazard, hardware lock, sa-plan preflight)
//// 4. Deciding (Prajna 5-breaker pool, MAX SIMD ranker, 2oo3 quorum)
//// 5. Acting (Sa-Plan durable dispatch, ZigVM VFS execution, SHA-256 receipt)
//// 6. Verifying (Denotational valuation [[ I ]](sigma), Trace13 conservation)
//// 7. Reflecting (Lyapunov trend update, immune antibody synthesis, ZK memory)
//// 8. ConstitutionalHalt (Fail-closed Andon Halt -32002)
//// =============================================================================

import cepaf_gleam/fpp/domain.{
  type StateMachine, InternalMachine, SignalDef, State, ToState, Transition,
}
import gleam/option.{None, Some}

pub fn poodavr_lifecycle_fprime() -> StateMachine {
  let signals = [
    SignalDef("tick_predict", None),
    SignalDef("telemetry_observed", None),
    SignalDef("intent_received", None),
    SignalDef("orientation_cleared", None),
    SignalDef("decision_ratified", None),
    SignalDef("action_dispatched", None),
    SignalDef("verification_passed", None),
    SignalDef("verification_failed", None),
    SignalDef("cycle_complete", None),
    SignalDef("andon_halt", None),
    SignalDef("safety_veto", None),
    SignalDef("constitutional_override", None),
  ]

  let predicting_state =
    State(
      state_name: "Predicting",
      entry: ["fprime_predict_lyapunov_prior", "fprime_sample_kalman"],
      exit: ["fprime_exit_predict"],
      transitions: [
        Transition(
          on_signal: "telemetry_observed",
          guard: None,
          do_actions: ["advance_to_observe"],
          target: ToState("Observing"),
        ),
        Transition(
          on_signal: "safety_veto",
          guard: None,
          do_actions: ["trip_constitutional_halt"],
          target: ToState("ConstitutionalHalt"),
        ),
      ],
    )

  let observing_state =
    State(
      state_name: "Observing",
      entry: ["fprime_ingest_zenoh_telemetry", "fprime_stamp_utc_microsecond"],
      exit: ["fprime_exit_observe"],
      transitions: [
        Transition(
          on_signal: "intent_received",
          guard: None,
          do_actions: ["capture_sensory_batch"],
          target: ToState("Orienting"),
        ),
        Transition(
          on_signal: "safety_veto",
          guard: None,
          do_actions: ["trip_constitutional_halt"],
          target: ToState("ConstitutionalHalt"),
        ),
      ],
    )

  let orienting_state =
    State(
      state_name: "Orienting",
      entry: [
        "fprime_pii_scrub",
        "fprime_stamp_safety_lattice",
        "fprime_sa_plan_preflight",
      ],
      exit: ["fprime_exit_orient"],
      transitions: [
        Transition(
          on_signal: "orientation_cleared",
          guard: Some("intent_is_safe"),
          do_actions: ["record_orientation_trace"],
          target: ToState("Deciding"),
        ),
        Transition(
          on_signal: "andon_halt",
          guard: None,
          do_actions: ["trip_andon_stop_line_32002"],
          target: ToState("ConstitutionalHalt"),
        ),
        Transition(
          on_signal: "safety_veto",
          guard: None,
          do_actions: ["trip_constitutional_halt"],
          target: ToState("ConstitutionalHalt"),
        ),
      ],
    )

  let deciding_state =
    State(
      state_name: "Deciding",
      entry: [
        "fprime_prajna_breaker_cascade",
        "fprime_max_simd_rank",
        "fprime_consensus_ratify",
      ],
      exit: ["fprime_exit_decide"],
      transitions: [
        Transition(
          on_signal: "decision_ratified",
          guard: Some("breakers_closed"),
          do_actions: ["seal_decision_plan"],
          target: ToState("Acting"),
        ),
        Transition(
          on_signal: "safety_veto",
          guard: None,
          do_actions: ["trip_constitutional_halt"],
          target: ToState("ConstitutionalHalt"),
        ),
      ],
    )

  let acting_state =
    State(
      state_name: "Acting",
      entry: [
        "fprime_sa_plan_durable_dispatch",
        "fprime_zigvm_vfs_execute",
        "fprime_receipt_seal",
      ],
      exit: ["fprime_exit_act"],
      transitions: [
        Transition(
          on_signal: "action_dispatched",
          guard: None,
          do_actions: ["collect_execution_receipt"],
          target: ToState("Verifying"),
        ),
        Transition(
          on_signal: "safety_veto",
          guard: None,
          do_actions: ["trip_constitutional_halt"],
          target: ToState("ConstitutionalHalt"),
        ),
      ],
    )

  let verifying_state =
    State(
      state_name: "Verifying",
      entry: [
        "fprime_denotational_valuation",
        "fprime_trace13_conserve_check",
      ],
      exit: ["fprime_exit_verify"],
      transitions: [
        Transition(
          on_signal: "verification_passed",
          guard: Some("trace13_conserved"),
          do_actions: ["advance_causal_epoch"],
          target: ToState("Reflecting"),
        ),
        Transition(
          on_signal: "verification_failed",
          guard: None,
          do_actions: ["emit_verification_breach"],
          target: ToState("ConstitutionalHalt"),
        ),
        Transition(
          on_signal: "safety_veto",
          guard: None,
          do_actions: ["trip_constitutional_halt"],
          target: ToState("ConstitutionalHalt"),
        ),
      ],
    )

  let reflecting_state =
    State(
      state_name: "Reflecting",
      entry: [
        "fprime_lyapunov_trend_update",
        "fprime_immune_antibody_log",
        "fprime_zk_memory_emit",
      ],
      exit: ["fprime_exit_reflect"],
      transitions: [
        Transition(
          on_signal: "cycle_complete",
          guard: None,
          do_actions: ["recycle_poodavr_loop"],
          target: ToState("Predicting"),
        ),
        Transition(
          on_signal: "safety_veto",
          guard: None,
          do_actions: ["trip_constitutional_halt"],
          target: ToState("ConstitutionalHalt"),
        ),
      ],
    )

  let halt_state =
    State(
      state_name: "ConstitutionalHalt",
      entry: [
        "fprime_andon_halt_freeze",
        "fprime_emit_trace_diagnostic",
        "fprime_quarantine_subsystem",
      ],
      exit: ["fprime_exit_halt"],
      transitions: [
        Transition(
          on_signal: "constitutional_override",
          guard: Some("two_key_operator_cleared"),
          do_actions: ["clear_quarantine", "reset_loop_state"],
          target: ToState("Predicting"),
        ),
      ],
    )

  InternalMachine(
    machine_name: "POODAVRCyberneticLoop",
    signals: signals,
    guards: [
      "intent_is_safe",
      "breakers_closed",
      "trace13_conserved",
      "two_key_operator_cleared",
    ],
    actions: [
      "fprime_predict_lyapunov_prior",
      "fprime_sample_kalman",
      "fprime_exit_predict",
      "advance_to_observe",
      "fprime_ingest_zenoh_telemetry",
      "fprime_stamp_utc_microsecond",
      "fprime_exit_observe",
      "capture_sensory_batch",
      "fprime_pii_scrub",
      "fprime_stamp_safety_lattice",
      "fprime_sa_plan_preflight",
      "fprime_exit_orient",
      "record_orientation_trace",
      "trip_andon_stop_line_32002",
      "fprime_prajna_breaker_cascade",
      "fprime_max_simd_rank",
      "fprime_consensus_ratify",
      "fprime_exit_decide",
      "seal_decision_plan",
      "fprime_sa_plan_durable_dispatch",
      "fprime_zigvm_vfs_execute",
      "fprime_receipt_seal",
      "fprime_exit_act",
      "collect_execution_receipt",
      "fprime_denotational_valuation",
      "fprime_trace13_conserve_check",
      "fprime_exit_verify",
      "advance_causal_epoch",
      "emit_verification_breach",
      "fprime_lyapunov_trend_update",
      "fprime_immune_antibody_log",
      "fprime_zk_memory_emit",
      "fprime_exit_reflect",
      "recycle_poodavr_loop",
      "fprime_andon_halt_freeze",
      "fprime_emit_trace_diagnostic",
      "fprime_quarantine_subsystem",
      "fprime_exit_halt",
      "clear_quarantine",
      "reset_loop_state",
      "trip_constitutional_halt",
    ],
    states: [
      predicting_state,
      observing_state,
      orienting_state,
      deciding_state,
      acting_state,
      verifying_state,
      reflecting_state,
      halt_state,
    ],
    choices: [],
    initial: #([], "Predicting"),
  )
}
