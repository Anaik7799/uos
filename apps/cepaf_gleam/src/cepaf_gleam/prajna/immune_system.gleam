//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/prajna/immune_system</module>
////   <fsharp-lineage>Cepaf.Prajna.ImmuneSystem</fsharp-lineage></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology></c3i-module>

import cepaf_gleam/prajna/bio.{type VitalSigns}
import gleam/list

pub type ThreatLevel {
  None
  Low
  Medium
  High
  Critical
}

pub type ThreatType {
  ResourceExhaustion
  UnauthorizedAccess
  CascadeFailure
  DataCorruption
  NetworkAnomaly
  UnknownThreat(String)
}

pub type AntibodyAction {
  Ignore
  Log
  Alert
  Isolate
  Escalate
  Terminate
}

pub type Strategy {
  Passive
  Adaptive
  Defensive
  Aggressive
}

pub type Threat {
  Threat(
    id: String,
    threat_type: ThreatType,
    level: ThreatLevel,
    source: String,
    description: String,
    timestamp: String,
  )
}

pub type AntibodyResponse {
  AntibodyResponse(
    action: AntibodyAction,
    strategy: Strategy,
    reason: String,
    threats_assessed: Int,
  )
}

pub fn assess_threat(vitals: VitalSigns) -> ThreatLevel {
  case vitals.health_index, vitals.stress_index {
    h, s if h <. 0.2 || s >. 0.9 -> Critical
    h, s if h <. 0.4 || s >. 0.7 -> High
    h, s if h <. 0.6 || s >. 0.5 -> Medium
    h, s if h <. 0.8 || s >. 0.3 -> Low
    _, _ -> None
  }
}

pub fn recommend_action(level: ThreatLevel) -> AntibodyAction {
  case level {
    None -> Ignore
    Low -> Log
    Medium -> Alert
    High -> Isolate
    Critical -> Terminate
  }
}

pub fn create_threat(
  id: String,
  threat_type: ThreatType,
  level: ThreatLevel,
  source: String,
  description: String,
  timestamp: String,
) -> Threat {
  Threat(
    id: id,
    threat_type: threat_type,
    level: level,
    source: source,
    description: description,
    timestamp: timestamp,
  )
}

pub fn respond(threat: Threat) -> AntibodyResponse {
  let action = recommend_action(threat.level)
  let strategy = case threat.level {
    None -> Passive
    Low -> Passive
    Medium -> Adaptive
    High -> Defensive
    Critical -> Aggressive
  }
  AntibodyResponse(
    action: action,
    strategy: strategy,
    reason: threat.description,
    threats_assessed: 1,
  )
}

pub fn mara_recommend(threats: List(Threat)) -> AntibodyResponse {
  let count = list.length(threats)
  case count {
    0 ->
      AntibodyResponse(
        action: Ignore,
        strategy: Passive,
        reason: "No threats detected",
        threats_assessed: 0,
      )
    _ -> {
      let highest_level =
        list.fold(threats, None, fn(acc, t) {
          case threat_level_to_int(t.level) > threat_level_to_int(acc) {
            True -> t.level
            False -> acc
          }
        })
      let action = recommend_action(highest_level)
      let strategy = case highest_level {
        None -> Passive
        Low -> Passive
        Medium -> Adaptive
        High -> Defensive
        Critical -> Aggressive
      }
      AntibodyResponse(
        action: action,
        strategy: strategy,
        reason: "Aggregated threat assessment",
        threats_assessed: count,
      )
    }
  }
}

fn threat_level_to_int(level: ThreatLevel) -> Int {
  case level {
    None -> 0
    Low -> 1
    Medium -> 2
    High -> 3
    Critical -> 4
  }
}
