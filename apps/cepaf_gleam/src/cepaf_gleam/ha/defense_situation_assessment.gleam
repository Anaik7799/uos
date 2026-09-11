//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/defense_situation_assessment</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L2_HEALTH</layer>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Unified Safety-Critical Defense Situation Assessment Engine.
////       Fuses Tri-Agent surveillance data, Lyapunov stability exponent,
////       health derivative velocity, and local compute ratio into DEFCON postures.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>
////       SC-DEFENSE-CONSTITUTION-001, SC-SURVEILLANCE-001, SC-MATH-001,
////       SC-SIL4-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/ha/health_derivative.{type HealthSample}
import cepaf_gleam/ha/lyapunov_proof.{type StabilityVerdict, Marginal, Stable, Unstable}
import cepaf_gleam/ha/tri_agent_monitor.{type TriAgentMonitorState}
import gleam/float
import gleam/int
import gleam/json
import gleam/list

/// Defense Operational Threat Posture.
pub type DefenseThreatPosture {
  Defcon1Emergency(reason: String)
  Defcon2Warning(reason: String)
  Defcon3Elevated(reason: String)
  Defcon4Nominal(reason: String)
}

/// Convert threat posture to human-readable string.
pub fn posture_to_string(posture: DefenseThreatPosture) -> String {
  case posture {
    Defcon1Emergency(r) -> "DEFCON_1_EMERGENCY: " <> r
    Defcon2Warning(r) -> "DEFCON_2_WARNING: " <> r
    Defcon3Elevated(r) -> "DEFCON_3_ELEVATED: " <> r
    Defcon4Nominal(r) -> "DEFCON_4_NOMINAL: " <> r
  }
}

/// Numerical DEFCON level (1 to 4).
pub fn posture_level(posture: DefenseThreatPosture) -> Int {
  case posture {
    Defcon1Emergency(_) -> 1
    Defcon2Warning(_) -> 2
    Defcon3Elevated(_) -> 3
    Defcon4Nominal(_) -> 4
  }
}

/// Unified Assessment Snapshot.
pub type DefenseAssessment {
  DefenseAssessment(
    timestamp_ns: Int,
    posture: DefenseThreatPosture,
    composite_health: Float,
    local_processing_ratio: Float,
    lyapunov_lambda: Float,
    lyapunov_verdict: StabilityVerdict,
    health_velocity: Float,
    total_intercepted_actions: Int,
    total_halted_actions: Int,
  )
}

/// Assess current defense situational posture from composite sensors.
pub fn evaluate_defense_posture(
  current_time_ns: Int,
  monitor: TriAgentMonitorState,
  samples: List(HealthSample),
  lambda_estimate: Float,
) -> DefenseAssessment {
  let derivative = list.fold(samples, health_derivative.init(1.0), health_derivative.update)
  let velocity = derivative.velocity
  let current_health = case samples {
    [latest, ..] -> latest.value
    [] -> 1.0
  }

  // Calculate local processing ratio (minimum target: 90%)
  let total_acts = monitor.total_intercepted
  let local_acts = total_acts - monitor.total_halted
  let local_ratio = case total_acts > 0 {
    True -> int.to_float(local_acts) /. int.to_float(total_acts)
    False -> 1.0
  }

  // Derive composite threat posture
  let posture = case monitor.cloud_degradation_active {
    // Active EW Jamming / Network Blackout (Psi-13)
    True ->
      case monitor.total_halted > 0 {
        True ->
          Defcon1Emergency(
            "Active Electronic Warfare Blackout with intercepted hostile exfiltration attempts.",
          )
        False ->
          Defcon2Warning(
            "Autonomous Degradation Active: Operating 100% on bare-metal MAX Gemma fabric.",
          )
      }

    False -> {
      case monitor.total_halted > 2 {
        True ->
          Defcon1Emergency(
            "Multiple un-ledgered actions or exfiltration attempts halted by Jidoka Stop Line.",
          )
        False -> {
          case lambda_estimate >. 0.05 || velocity <. -0.2 {
            True ->
              Defcon2Warning(
                "Health trajectory diverging; negative Lyapunov stability detected.",
              )
            False -> {
              case monitor.total_rerouted_local > 0 || current_health <. 0.85 {
                True ->
                  Defcon3Elevated(
                    "Cloud degradation failovers active; Prajna operating in elevated monitoring.",
                  )
                False ->
                  Defcon4Nominal(
                    "All constitutional invariants nominal. 92.86% local processing verified.",
                  )
              }
            }
          }
        }
      }
    }
  }

  let verdict = case lambda_estimate <. 0.0 {
    True -> Stable
    False ->
      case lambda_estimate >. 0.0001 {
        True -> Unstable
        False -> Marginal
      }
  }

  DefenseAssessment(
    timestamp_ns: current_time_ns,
    posture: posture,
    composite_health: current_health,
    local_processing_ratio: local_ratio,
    lyapunov_lambda: lambda_estimate,
    lyapunov_verdict: verdict,
    health_velocity: velocity,
    total_intercepted_actions: monitor.total_intercepted,
    total_halted_actions: monitor.total_halted,
  )
}

/// JSON Serialization of defense assessment.
pub fn assessment_to_json(assessment: DefenseAssessment) -> json.Json {
  let verdict_str = case assessment.lyapunov_verdict {
    Stable -> "STABLE"
    Unstable -> "UNSTABLE"
    Marginal -> "MARGINAL"
  }

  json.object([
    #("timestamp_ns", json.int(assessment.timestamp_ns)),
    #("defcon_level", json.int(posture_level(assessment.posture))),
    #("posture_string", json.string(posture_to_string(assessment.posture))),
    #("composite_health", json.float(assessment.composite_health)),
    #("local_processing_ratio", json.float(assessment.local_processing_ratio)),
    #("lyapunov_lambda", json.float(assessment.lyapunov_lambda)),
    #("lyapunov_verdict", json.string(verdict_str)),
    #("health_velocity", json.float(assessment.health_velocity)),
    #(
      "total_intercepted_actions",
      json.int(assessment.total_intercepted_actions),
    ),
    #("total_halted_actions", json.int(assessment.total_halted_actions)),
  ])
}

/// ANSI Dashboard summary string for C3I Cockpit.
pub fn render_ansi_banner(assessment: DefenseAssessment) -> String {
  let level = posture_level(assessment.posture)
  let badge = case level {
    1 -> "[DEFCON 1: EMERGENCY]"
    2 -> "[DEFCON 2: WARNING]"
    3 -> "[DEFCON 3: ELEVATED]"
    _ -> "[DEFCON 4: NOMINAL]"
  }

  badge
  <> " Health="
  <> float.to_string(assessment.composite_health)
  <> " | LocalRatio="
  <> float.to_string(assessment.local_processing_ratio *. 100.0)
  <> "% | Lambda="
  <> float.to_string(assessment.lyapunov_lambda)
}
