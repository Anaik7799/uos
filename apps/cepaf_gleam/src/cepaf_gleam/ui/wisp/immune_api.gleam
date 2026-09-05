/// Wisp API for Immune plane (SC-GLM-UI-001, SC-GLM-UI-003).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007
import cepaf_gleam/immune/domain.{
  type Antibody, type ChaosAttack, type ImmuneEvent,
}
import gleam/json
import gleam/list

pub fn immune_status_json(
  antibodies: List(Antibody),
  attacks: List(ChaosAttack),
  mara_running: Bool,
) -> String {
  json.object([
    #("plane", json.string("immune")),
    #("antibody_count", json.int(list.length(antibodies))),
    #("active_attacks", json.int(list.length(attacks))),
    #("mara_running", json.bool(mara_running)),
    #(
      "threat_level",
      json.string(case list.length(attacks) {
        0 -> "nominal"
        n if n <= 2 -> "elevated"
        _ -> "critical"
      }),
    ),
    #("antibodies", json.array(antibodies, encode_antibody)),
  ])
  |> json.to_string()
}

pub fn events_json(events: List(ImmuneEvent)) -> String {
  json.object([
    #("plane", json.string("immune")),
    #("event_count", json.int(list.length(events))),
    #("events", json.array(events, encode_event)),
  ])
  |> json.to_string()
}

fn encode_antibody(ab: Antibody) -> json.Json {
  json.object([
    #("id", json.string(ab.id)),
    #("target_pattern", json.string(ab.target_pattern)),
    #("reason", json.string(ab.reason)),
    #("expires_at", json.int(ab.expires_at)),
  ])
}

fn encode_event(evt: ImmuneEvent) -> json.Json {
  case evt {
    domain.AntibodySynthesized(id, pattern) ->
      json.object([
        #("type", json.string("antibody_synthesized")),
        #("id", json.string(id)),
        #("pattern", json.string(pattern)),
      ])
    domain.AttackBlocked(id, reason) ->
      json.object([
        #("type", json.string("attack_blocked")),
        #("id", json.string(id)),
        #("reason", json.string(reason)),
      ])
    domain.SafetyViolationDetected(reason) ->
      json.object([
        #("type", json.string("safety_violation")),
        #("reason", json.string(reason)),
      ])
    domain.AutomatedRollbackInitiated(target) ->
      json.object([
        #("type", json.string("rollback_initiated")),
        #("target", json.string(target)),
      ])
  }
}
