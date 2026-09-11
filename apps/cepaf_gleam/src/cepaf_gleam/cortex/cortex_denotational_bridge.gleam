//// =============================================================================
//// [C3I-SIL6-MSTS] UOS CORTEX DENOTATIONAL INTENT VALUATION BRIDGE
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/cortex/cortex_denotational_bridge</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Denotational Declarative Intent Valuation Bridge</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-INTENT-ATLAS-001, SC-CHECKLIST-001, SC-JIDOKA-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/cortex/cortex_types.{type TaskIntent}
import cepaf_gleam/semantics/algebraic_atlas.{
  type ChartIndex, type ChartState, type DeclarativeIntent,
  type DenotationalOutcome, ChartState, DeclarativeIntent, DenotationalSuccess,
  DenotationalVetoed, L3Transactions, L5CognitiveOODA, TraceCoordinates,
  evaluate_denotational_intent, verify_sheaf_gluing,
}
import gleam/string

pub const hard_denied_system_os_serial: String = "25503L801736"

/// Formulates a typed DeclarativeIntent from a runtime TaskIntent.
pub fn formulate_declarative_intent(
  intent: TaskIntent,
  target_chart: ChartIndex,
  action: String,
) -> DeclarativeIntent {
  let lower_text = string.lowercase(intent.raw_text)
  let is_os_disk_targeted =
    string.contains(lower_text, hard_denied_system_os_serial)
    || string.contains(lower_text, "wipe")
    && string.contains(lower_text, "nvme")

  let is_unledgered =
    string.contains(lower_text, "unledgered")
    || string.contains(lower_text, "bypass sa-plan")

  let preserves_invariants = !is_os_disk_targeted && !is_unledgered

  DeclarativeIntent(
    intent_id: intent.id,
    proposer_holon: "cortex_denotational_bridge",
    source_chart: L5CognitiveOODA,
    target_chart: target_chart,
    action: action,
    required_preconditions: ["constitutional_guard_active", "prajna_closed"],
    guaranteed_postconditions: ["receipt_stored_in_wal", "trace13_conserved"],
    preserves_constitutional_invariants: preserves_invariants,
  )
}

/// Evaluates a DeclarativeIntent under denotational valuation semantics [[ I ]] (sigma).
pub fn evaluate_intent_valuation(
  intent: DeclarativeIntent,
  state: ChartState,
) -> DenotationalOutcome {
  evaluate_denotational_intent(intent, state)
}

/// Verifies sheaf gluing across overlapping chart sections in the Atlas.
pub fn verify_atlas_sheaf_consistency(
  sections: List(#(ChartIndex, String)),
  overlaps: List(#(ChartIndex, ChartIndex, String)),
) -> Result(String, String) {
  verify_sheaf_gluing(sections, overlaps)
}

/// Executes a complete denotational roundtrip for a TaskIntent.
/// Returns Ok(#(new_chart_state, receipt_hash)) or Error(veto_reason).
pub fn execute_denotational_roundtrip(
  intent: TaskIntent,
  current_epoch: Int,
  now_ms: Int,
) -> Result(#(ChartState, String), String) {
  let decl_intent =
    formulate_declarative_intent(
      intent,
      L3Transactions,
      "sa_plan:execute:" <> intent.id,
    )

  let initial_coords =
    TraceCoordinates(
      timestamp_us: now_ms * 1000,
      layer_id: 5,
      holon_id: "cortex_bridge",
      causal_epoch: current_epoch,
      shannon_entropy_bits: 2.8,
      lyapunov_energy: 0.15,
      cyclomatic_complexity: 94,
      divergence_ppm: 80,
      itqs_quality: 0.96,
      quarantine_flags: 0,
      worker_hash: "bridge_worker",
      plan_digest: "bridge_plan",
      parent_digest: "root_plan",
    )

  let chart_st =
    ChartState(
      chart: L5CognitiveOODA,
      coordinates: initial_coords,
      payload_json: "{\"roundtrip_intent\":\"" <> intent.id <> "\"}",
      constitutional_health: 0.95,
    )

  case evaluate_intent_valuation(decl_intent, chart_st) {
    DenotationalSuccess(final_state, receipt) -> Ok(#(final_state, receipt))
    DenotationalVetoed(_, reason) -> Error(reason)
  }
}
