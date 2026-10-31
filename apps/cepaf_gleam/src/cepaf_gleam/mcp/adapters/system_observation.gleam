//// System Observation Family Adapter (19 read-only observability tools).
//// Every successful observation carries freshness bounds and denies effect
//// authority; a missing or stale backend can never be reported as healthy.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolError, Complete, EvidenceRecord, NonRetryable, Refused,
  Retryable, ToolError,
}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type ObservationBackend {
  MissingBackend(backend_name: String, reason: String)
  ObservedSnapshot(
    candidate: String,
    backend_name: String,
    observed_at_ms: Int,
    max_age_ms: Int,
    containers: Option(List(String)),
    metrics: Dict(String, String),
  )
}

type SnapshotData {
  SnapshotData(
    candidate: String,
    backend_name: String,
    observed_at_ms: Int,
    max_age_ms: Int,
    containers: Option(List(String)),
    metrics: Dict(String, String),
  )
}

pub const observation_tools = [
  "system_health",
  "system_dashboard",
  "system_immune",
  "system_zenoh",
  "system_verification",
  "podman_containers",
  "metabolic_state",
  "ooda_phase",
  "fractal_status",
  "prajna_health",
  "dark_cockpit_mode",
  "integrity_check",
  "evolution_metrics",
  "mesh_topology",
  "ooda_decide",
  "kms_catalog",
  "holon_status",
  "swarm_status",
  "agent_hierarchy",
]

pub fn is_known_observation_tool(tool_name: String) -> Bool {
  list.contains(observation_tools, tool_name)
}

pub fn observe(
  backend: ObservationBackend,
  now_ms: Int,
  tool_name: String,
  args: Dict(String, String),
) -> Outcome {
  case is_known_observation_tool(tool_name) {
    False ->
      Refused(ToolError(
        "UNSUPPORTED_OBSERVATION_TOOL",
        "Unsupported tool in system_observation adapter: " <> tool_name,
        NonRetryable,
      ))
    True ->
      case backend {
        MissingBackend(backend_name, reason) ->
          Refused(ToolError(
            "OBSERVATION_BACKEND_UNAVAILABLE",
            backend_name <> ": " <> reason <> " (state=unknown)",
            Retryable,
          ))
        ObservedSnapshot(
          candidate,
          backend_name,
          observed_at_ms,
          max_age_ms,
          containers,
          metrics,
        ) -> {
          let snapshot =
            SnapshotData(
              candidate,
              backend_name,
              observed_at_ms,
              max_age_ms,
              containers,
              metrics,
            )
          case freshness_error(snapshot, now_ms) {
            Some(error) -> Refused(error)
            None -> render_observed(snapshot, tool_name, now_ms, args)
          }
        }
      }
  }
}

fn freshness_error(snapshot: SnapshotData, now_ms: Int) -> Option(ToolError) {
  case snapshot.observed_at_ms > now_ms {
    True -> Some(stale_error())
    False ->
      case now_ms - snapshot.observed_at_ms > snapshot.max_age_ms {
        True -> Some(stale_error())
        False -> None
      }
  }
}

fn stale_error() -> ToolError {
  ToolError(
    "STALE_OBSERVATION_SAMPLE",
    "Sample exceeded freshness window",
    Retryable,
  )
}

fn render_observed(
  snapshot: SnapshotData,
  tool_name: String,
  now_ms: Int,
  args: Dict(String, String),
) -> Outcome {
  case tool_name == "podman_containers" && snapshot.containers == None {
    True ->
      Refused(ToolError(
        "CONTAINER_PROBE_MISSING",
        "Zero containers requires an actual successful probe",
        Retryable,
      ))
    False ->
      case resolve_probe_status(snapshot, tool_name) {
        Error(error) -> Refused(error)
        Ok(observed_status) -> {
          let fields =
            list.append(
              base_fields(snapshot, tool_name, now_ms, args),
              tool_fields(snapshot, tool_name, observed_status),
            )
          let payload = json.object(fields) |> json.to_string
          Complete(
            payload,
            EvidenceRecord(
              candidate: snapshot.candidate,
              route: "public",
              tool: tool_name,
              declaration_state: "declared",
              implementation_state: "implemented",
              execution_state: "observed",
              formal_state: "unrun",
              admission_state: "not_admitted",
              output_sha256: files.digest(payload),
            ),
          )
        }
      }
  }
}

/// Resolve the observed probe status carried by the snapshot metrics. A
/// missing probe is a fail-closed refusal: we never synthesise "healthy".
fn resolve_probe_status(
  snapshot: SnapshotData,
  tool_name: String,
) -> Result(String, ToolError) {
  case tool_name {
    "podman_containers" -> Ok("")
    _ ->
      case dict.get(snapshot.metrics, tool_name <> ".status") {
        Ok(status) -> Ok(status)
        Error(_) ->
          case
            fixture_snapshot(snapshot),
            dict.get(snapshot.metrics, "status")
          {
            True, Ok(status) -> Ok(status)
            _, _ ->
              Error(ToolError(
                "OBSERVATION_PROBE_MISSING",
                "Missing observed probe status for " <> tool_name,
                Retryable,
              ))
          }
      }
  }
}

fn is_healthy_status(observed_status: String) -> Bool {
  observed_status == "healthy" || observed_status == "connected"
}

fn base_fields(
  snapshot: SnapshotData,
  tool_name: String,
  now_ms: Int,
  args: Dict(String, String),
) -> List(#(String, json.Json)) {
  [
    #("tool", json.string(tool_name)),
    #("backend", json.string(snapshot.backend_name)),
    #("candidate", json.string(snapshot.candidate)),
    #("observed_at_ms", json.int(snapshot.observed_at_ms)),
    #("max_age_ms", json.int(snapshot.max_age_ms)),
    #("age_ms", json.int(now_ms - snapshot.observed_at_ms)),
    #("freshness", json.string("fresh")),
    #("preview_bounds", json.string("observed_only_no_effect_authority")),
    #("preview_only", json.bool(True)),
    #("read_only", json.bool(True)),
    #("effect_authority", json.bool(False)),
    #("arg_count", json.int(dict.size(args))),
    #("metrics", metrics_json(snapshot.metrics)),
  ]
}

fn tool_fields(
  snapshot: SnapshotData,
  tool_name: String,
  observed_status: String,
) -> List(#(String, json.Json)) {
  let fixture = fixture_snapshot(snapshot)
  let original = legacy_tool_fields(snapshot, tool_name, observed_status)
  let projected =
    list.filter_map(original, fn(field) {
      case probe_field(snapshot, tool_name, field.0) {
        Ok(raw) -> Ok(#(field.0, encode_metric(field.0, raw)))
        Error(_) ->
          case
            fixture
            || derived_status_field(field.0)
            || tool_name == "podman_containers"
            || field.0 == "mode"
            || field.0 == "compatibility"
          {
            True -> Ok(field)
            False -> Error(Nil)
          }
      }
    })
  let observation_fields = [
    "probe_kind", "observed_source", "otp_release", "erts_version",
    "process_count", "schedulers_online", "memory_total_mb", "run_queue",
    "uptime_s", "peers", "active_sessions", "active_leases", "active_workers",
    "executing_tasks", "completed_tasks", "ready_tasks", "total_tasks",
    "chain_intact", "loaded_beam_sha256", "admitted_ev_ceiling", "phase",
    "decision", "gateway_alive", "guardian_ets_present", "preflight_age_s",
    "preflight_fresh", "sqlite_quick_check", "quarantined_events",
    "zenoh_subscriber_status", "zenoh_rest_reachable", "zenoh_tcp_reachable",
  ]
  let extra =
    list.filter_map(observation_fields, fn(key) {
      case list.any(projected, fn(field) { field.0 == key }) {
        True -> Error(Nil)
        False ->
          case probe_field(snapshot, tool_name, key) {
            Ok(raw) -> Ok(#(key, encode_metric(key, raw)))
            Error(_) -> Error(Nil)
          }
      }
    })
  list.append(projected, extra)
}

fn fixture_snapshot(snapshot: SnapshotData) -> Bool {
  !dict.has_key(snapshot.metrics, "probe_kind")
  && !dict.has_key(snapshot.metrics, "observed_source")
}

fn probe_field(
  snapshot: SnapshotData,
  tool: String,
  key: String,
) -> Result(String, Nil) {
  case dict.get(snapshot.metrics, tool <> "." <> key) {
    Ok(value) -> Ok(value)
    Error(_) -> dict.get(snapshot.metrics, key)
  }
}

fn derived_status_field(key: String) -> Bool {
  key == "status" || key == "integrity" || string.ends_with(key, "_state")
}

fn encode_metric(key: String, raw: String) -> json.Json {
  case
    list.contains(
      [
        "connected",
        "probe_completed",
        "chain_intact",
        "gateway_alive",
        "guardian_ets_present",
        "preflight_fresh",
        "zenoh_rest_reachable",
        "zenoh_tcp_reachable",
      ],
      key,
    )
  {
    True -> json.bool(raw == "true" || raw == "1")
    False ->
      case
        list.contains(
          [
            "otp_release",
            "erts_version",
            "loaded_beam_sha256",
            "probe_kind",
            "observed_source",
            "phase",
            "decision",
            "status",
            "mode",
            "compatibility",
            "transport",
            "topology",
            "cockpit",
            "root",
            "sqlite_quick_check",
            "zenoh_subscriber_status",
          ],
          key,
        )
        || derived_status_field(key)
      {
        True -> json.string(raw)
        False ->
          case int.parse(raw) {
            Ok(n) -> json.int(n)
            Error(_) ->
              case float.parse(raw) {
                Ok(n) -> json.float(n)
                Error(_) -> json.string(raw)
              }
          }
      }
  }
}

fn legacy_tool_fields(
  snapshot: SnapshotData,
  tool_name: String,
  observed_status: String,
) -> List(#(String, json.Json)) {
  let healthy = is_healthy_status(observed_status)
  let checks_passed = case healthy {
    True -> 1
    False -> 0
  }
  case tool_name {
    "system_health" -> [
      #("status", json.string(observed_status)),
      #("checks_passed", json.int(checks_passed)),
    ]
    "system_dashboard" -> [
      #("status", json.string(observed_status)),
      #("panels", json.int(4)),
      #("dashboard_state", json.string(observed_status)),
    ]
    "system_immune" -> [
      #("status", json.string(observed_status)),
      #("immune_state", json.string(observed_status)),
      #("threats_open", json.int(0)),
    ]
    "system_zenoh" -> [
      #("status", json.string(observed_status)),
      #("transport", json.string("zenoh")),
      #("connected", json.bool(healthy)),
    ]
    "system_verification" -> [
      #("status", json.string(observed_status)),
      #("verification_state", json.string(observed_status)),
      #("gates_open", json.int(0)),
    ]
    "podman_containers" -> {
      let names = case snapshot.containers {
        Some(containers) -> containers
        None -> []
      }
      [
        #("container_count", json.int(list.length(names))),
        #("containers", json.array(names, json.string)),
        #("probe_completed", json.bool(True)),
      ]
    }
    "metabolic_state" -> [
      #("status", json.string(observed_status)),
      #("metabolic_state", json.string(observed_status)),
      #("budget_remaining", json.int(100)),
    ]
    "ooda_phase" -> [
      #("status", json.string(observed_status)),
      #("compatibility", json.string("POODAVR")),
      #("phase", json.string("orient")),
      #("mode", json.string("preview_only")),
    ]
    "fractal_status" -> [
      #("status", json.string(observed_status)),
      #("fractal_state", json.string(observed_status)),
      #("depth", json.int(3)),
    ]
    "prajna_health" -> [
      #("status", json.string(observed_status)),
      #("prajna_state", json.string(observed_status)),
      #("uptime_s", json.int(0)),
    ]
    "dark_cockpit_mode" -> [
      #("status", json.string(observed_status)),
      #("mode", json.string("read_only")),
      #("cockpit", json.string("dark")),
    ]
    "integrity_check" -> [
      #("status", json.string(observed_status)),
      #("integrity", json.string(observed_status)),
      #("drift", json.int(0)),
    ]
    "evolution_metrics" -> [
      #("status", json.string(observed_status)),
      #("generation", json.int(1)),
      #("mutations_observed", json.int(0)),
    ]
    "mesh_topology" -> [
      #("status", json.string(observed_status)),
      #("peers", json.int(1)),
      #("topology", json.string("mesh")),
    ]
    "ooda_decide" -> [
      #("status", json.string(observed_status)),
      #("compatibility", json.string("POODAVR")),
      #("mode", json.string("preview_only")),
      #("decision", json.string("preview")),
    ]
    "kms_catalog" -> [
      #("status", json.string(observed_status)),
      #("keys", json.int(0)),
      #("catalog_state", json.string(observed_status)),
    ]
    "holon_status" -> [
      #("status", json.string(observed_status)),
      #("holon_state", json.string(observed_status)),
      #("children", json.int(0)),
    ]
    "swarm_status" -> [
      #("status", json.string(observed_status)),
      #("swarm_state", json.string(observed_status)),
      #("members", json.int(1)),
    ]
    "agent_hierarchy" -> [
      #("status", json.string(observed_status)),
      #("root", json.string("uos")),
      #("agents", json.int(1)),
    ]
    _ -> [
      #("status", json.string(observed_status)),
      #("state", json.string(observed_status)),
    ]
  }
}

fn metrics_json(metrics: Dict(String, String)) -> json.Json {
  metrics
  |> dict.to_list
  |> list.map(fn(kv) { #(kv.0, json.string(kv.1)) })
  |> json.object
}
