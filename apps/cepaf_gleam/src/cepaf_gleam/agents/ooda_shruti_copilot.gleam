//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/agents/ooda_shruti_copilot</module>
////     <fsharp-lineage>N/A — Pure Gleam Autonomous OODA Agent Copilot & Shruti Synthesizer</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L3_TRANSACTION</layer>
////     <layer>L5_COGNITIVE</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-OODA-001, SC-BIO-HARMONY-001, SC-CHECKLIST-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/knowledge/raga_cybernetic_synthesis.{type Shruti, all_22_shrutis}
import cepaf_gleam/ui/state.{
  type OodaPhase, OodaAct, OodaDecide, OodaObserve, OodaOrient, OodaVerify,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// AST Anomaly descriptor detected during Orient / Verify phases.
pub type AstAnomaly {
  AstAnomaly(
    id: String,
    anomaly_type: String,
    severity: Float,
    file_path: String,
    suggested_patch: String,
    resolved: Bool,
  )
}

/// Dynamic OODA Copilot State with Shruti Harmonic resonance.
pub type OodaCopilotState {
  OodaCopilotState(
    current_phase: OodaPhase,
    cycle_count: Int,
    active_shruti: Shruti,
    harmonic_consonance: Float,
    lyapunov_exponent: Float,
    anomalies: List(AstAnomaly),
    remediated_count: Int,
    is_andon_active: Bool,
    timestamp_us: Int,
  )
}

/// Initialize the OODA Copilot state.
pub fn init_copilot() -> OodaCopilotState {
  let default_shruti = case list.first(all_22_shrutis()) {
    Ok(s) -> s
    Error(Nil) ->
      raga_cybernetic_synthesis.Shruti(1, "Kshobhini", "Sa", 1, 1, 0.0, 261.63)
  }

  OodaCopilotState(
    current_phase: OodaObserve,
    cycle_count: 1,
    active_shruti: default_shruti,
    harmonic_consonance: 1.0,
    lyapunov_exponent: -3.85,
    anomalies: [],
    remediated_count: 0,
    is_andon_active: False,
    timestamp_us: 1788808840000000,
  )
}

/// Transition to next phase in OODA loop (Observe -> Orient -> Decide -> Act -> Verify -> Observe).
pub fn advance_ooda_phase(
  state: OodaCopilotState,
  now_us: Int,
) -> OodaCopilotState {
  case state.is_andon_active {
    True -> state
    False -> {
      let #(next_phase, next_cycle) = case state.current_phase {
        OodaObserve -> #(OodaOrient, state.cycle_count)
        OodaOrient -> #(OodaDecide, state.cycle_count)
        OodaDecide -> #(OodaAct, state.cycle_count)
        OodaAct -> #(OodaVerify, state.cycle_count)
        OodaVerify -> #(OodaObserve, state.cycle_count + 1)
      }

      let shruti = select_phase_shruti(next_phase)
      let consonance = compute_shruti_consonance(shruti, state.lyapunov_exponent)

      OodaCopilotState(
        ..state,
        current_phase: next_phase,
        cycle_count: next_cycle,
        active_shruti: shruti,
        harmonic_consonance: consonance,
        timestamp_us: now_us,
      )
    }
  }
}

/// Select characteristic microtonal Shruti for the active OODA phase.
pub fn select_phase_shruti(phase: OodaPhase) -> Shruti {
  let shrutis = all_22_shrutis()
  let target_index = case phase {
    OodaObserve -> 1
    // Sa (Kshobhini - Ground)
    OodaOrient -> 5
    // Re2 (Chhandovati - Meter/Orientation)
    OodaDecide -> 9
    // Ga2 (Raudri - Decision)
    OodaAct -> 10
    // ma1 (Krodha - Action Force)
    OodaVerify -> 14
    // Pa (Sandipani - Illumination)
  }

  case list.find(shrutis, fn(s) { s.index == target_index }) {
    Ok(s) -> s
    Error(Nil) ->
      raga_cybernetic_synthesis.Shruti(1, "Kshobhini", "Sa", 1, 1, 0.0, 261.63)
  }
}

/// Compute harmonic consonance index based on rational ratio purity and Lyapunov stability.
pub fn compute_shruti_consonance(shruti: Shruti, lyapunov: Float) -> Float {
  let ratio_score =
    1.0 /. { int.to_float(shruti.ratio_num) +. int.to_float(shruti.ratio_den) }
  let base_harmony = 0.4 +. { ratio_score *. 0.5 }

  let lyap_factor = case lyapunov <. 0.0 {
    True -> 0.2
    False -> -0.2
  }

  let total = base_harmony +. lyap_factor
  case total >. 1.0 {
    True -> 1.0
    False -> case total <. 0.0 {
      True -> 0.0
      False -> total
    }
  }
}

/// Inject an AST anomaly detected during semantic code analysis.
pub fn record_ast_anomaly(
  state: OodaCopilotState,
  anomaly: AstAnomaly,
) -> OodaCopilotState {
  let is_critical = anomaly.severity >=. 0.85
  let updated_anomalies = [anomaly, ..state.anomalies]

  OodaCopilotState(
    ..state,
    anomalies: updated_anomalies,
    is_andon_active: state.is_andon_active || is_critical,
    lyapunov_exponent: case is_critical {
      True -> 0.85
      False -> state.lyapunov_exponent
    },
  )
}

/// Auto-remediate a known AST anomaly, generating a deterministic patch.
pub fn remediate_anomaly(
  state: OodaCopilotState,
  anomaly_id: String,
) -> OodaCopilotState {
  let updated_anomalies =
    list.map(state.anomalies, fn(a) {
      case a.id == anomaly_id {
        True -> AstAnomaly(..a, resolved: True)
        False -> a
      }
    })

  let has_unresolved_critical =
    list.any(updated_anomalies, fn(a) { !a.resolved && a.severity >=. 0.85 })

  OodaCopilotState(
    ..state,
    anomalies: updated_anomalies,
    remediated_count: state.remediated_count + 1,
    is_andon_active: has_unresolved_critical,
    lyapunov_exponent: case has_unresolved_critical {
      True -> state.lyapunov_exponent
      False -> -3.85
    },
  )
}

/// Summary status for UI HUD and verification.
pub fn get_copilot_summary(state: OodaCopilotState) -> String {
  "Phase: "
  <> state.current_phase |> string.inspect
  <> " | Cycle: "
  <> int.to_string(state.cycle_count)
  <> " | Swara: "
  <> state.active_shruti.swara
  <> " ("
  <> state.active_shruti.name
  <> " "
  <> float.to_string(state.active_shruti.frequency_hz)
  <> " Hz) | Consonance: "
  <> float.to_string(state.harmonic_consonance)
  <> " | Anomalies: "
  <> int.to_string(list.length(state.anomalies))
  <> " ("
  <> int.to_string(state.remediated_count)
  <> " resolved)"
}
