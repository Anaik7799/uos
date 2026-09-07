//// N01: read-only peer observation. Transport success never grants system health.
//// Denotation: a bounded HTTP observation maps to a diagnostic state. The map
//// preserves unavailable/invalid evidence and has no system-admitted variant.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/string

pub type Endpoint {
  CurrentPeer
  ObsoletePeer
}

pub type State {
  Unavailable
  HttpFailure
  IdentityMismatch
  ReachableUnverified
}

pub opaque type Report {
  Report(
    endpoint: Endpoint,
    state: State,
    http_status: Int,
    observed_at_ms: Int,
    version: String,
    reason: String,
  )
}

pub const current_url = "http://vm-1.tail55d152.ts.net:4100"

pub const obsolete_url = "http://vm-1.tail55d152.ts.net:8088"

pub const probe_timeout_ms = 7000

pub const task_timeout_seconds = 1200

pub fn url(endpoint: Endpoint) -> String {
  case endpoint {
    CurrentPeer -> current_url
    ObsoletePeer -> obsolete_url
  }
}

@external(erlang, "uos_peer_http_ffi", "probe")
fn probe(url: String) -> Result(#(Int, Int, String, Int), String)

/// The I/O boundary has a closed URL allowlist, response quota and deadline.
pub fn observe(endpoint: Endpoint) -> Report {
  from_observation(endpoint, probe(url(endpoint) <> "/api/health"))
}

/// Public for independent transport-oracle testing; it cannot grant admission.
pub fn from_observation(
  endpoint: Endpoint,
  observation: Result(#(Int, Int, String, Int), String),
) -> Report {
  case observation {
    Error(_) -> Report(endpoint, Unavailable, 0, 0, "", "probe unavailable")
    Ok(#(exit_code, status, _, time)) if exit_code != 0 ->
      Report(endpoint, Unavailable, status, time, "", "transport failed")
    Ok(#(_, status, _, time)) if status != 200 ->
      Report(
        endpoint,
        HttpFailure,
        status,
        time,
        "",
        "HTTP response was not 200",
      )
    Ok(#(_, status, body, time)) -> {
      let decoder = {
        use interface <- decode.field("interface", decode.string)
        use port <- decode.field("port", decode.int)
        use version <- decode.field("version", decode.string)
        decode.success(#(interface, port, version))
      }
      case json.parse(body, decoder) {
        Ok(#("wisp", 4100, version)) if version != "" ->
          Report(
            endpoint,
            ReachableUnverified,
            status,
            time,
            version,
            "C3I service reports its interface and version; deployed build identity is not supplied",
          )
        _ ->
          Report(
            endpoint,
            IdentityMismatch,
            status,
            time,
            "",
            "expected C3I identity is absent or mismatched",
          )
      }
    }
  }
}

pub fn state_name(report: Report) -> String {
  case report.state {
    Unavailable -> "UNAVAILABLE"
    HttpFailure -> "HTTP_FAILURE"
    IdentityMismatch -> "IDENTITY_MISMATCH"
    ReachableUnverified -> "REACHABLE_UNVERIFIED"
  }
}

pub fn system_green(_report: Report) -> Bool {
  // A diagnostic observation has no formal or deployed-candidate authority.
  False
}

pub fn to_json(report: Report) -> String {
  json.object([
    #("schema", json.string("uos.peer-health.v1")),
    #("endpoint", json.string(url(report.endpoint))),
    #("status", json.string(state_name(report))),
    #("http_status", json.int(report.http_status)),
    #("observed_at_ms", json.int(report.observed_at_ms)),
    #("service_version", json.string(report.version)),
    #("build_identity", json.string("UNKNOWN")),
    #("system_green", json.bool(system_green(report))),
    #("reason", json.string(report.reason)),
    #("timeout_seconds", json.int(task_timeout_seconds)),
    #("probe_timeout_ms", json.int(probe_timeout_ms)),
  ])
  |> json.to_string()
}

/// Plain text is shared by TUI and escaped HTML rendering.
pub fn summary(report: Report) -> String {
  string.join(
    [
      state_name(report),
      url(report.endpoint),
      "HTTP " <> int.to_string(report.http_status),
      report.reason,
      "System health is unverified.",
    ],
    " | ",
  )
}
