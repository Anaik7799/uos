//// Mini App Immune page observer. Reads a bounded snapshot from the immune
//// actor (`immune/system`). Confidence is "observed" only when the actor
//// answered; a missing, dead or silent actor yields a typed unavailable reason.

import cepaf_gleam/immune/system
import cepaf_gleam/telegram/mini_api as api
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const source = "cepaf_gleam/immune/system"

pub const not_running_reason = "immune_actor_not_running"

pub const timeout_reason = "immune_snapshot_timeout"

const max_fields = 24

const max_value_bytes = 512

const min_timeout_ms = 1

const max_timeout_ms = 3000

fn clip(value: String) -> String {
  case string.byte_size(value) <= max_value_bytes {
    True -> value
    False -> string.slice(value, 0, max_value_bytes - 3) <> "..."
  }
}

/// Pure: turn a snapshot result into the page observation.
pub fn observe(
  at: Int,
  snapshot: Result(system.SystemSnapshot, String),
) -> api.Observation {
  case snapshot {
    Error(reason) -> api.Unavailable(reason)
    Ok(s) -> {
      let rows = [
        #("Source", source),
        #("Confidence", "observed"),
        #("Active antibodies", int.to_string(s.active_antibodies)),
        #("Violations", int.to_string(s.violation_count)),
        #("Known patterns", int.to_string(s.known_patterns)),
        #("Antibody targets", string.join(s.antibody_targets, ", ")),
      ]
      let fields =
        rows
        |> list.take(max_fields)
        |> list.map(fn(r) { #(r.0, clip(r.1)) })
        |> dict.from_list
      api.Observed(at, source, fields)
    }
  }
}

fn clamp(timeout_ms: Int) -> Int {
  int.clamp(timeout_ms, min_timeout_ms, max_timeout_ms)
}

/// Bounded live query. A dead or silent actor yields Error(timeout_reason).
pub fn query(
  actor: Subject(system.Message),
  timeout_ms: Int,
) -> Result(system.SystemSnapshot, String) {
  case process.subject_owner(actor) {
    Error(_) -> Error(timeout_reason)
    Ok(pid) ->
      case process.is_alive(pid) {
        False -> Error(timeout_reason)
        True -> {
          let reply = process.new_subject()
          process.send(actor, system.Snapshot(reply))
          process.receive(reply, clamp(timeout_ms))
          |> result.replace_error(timeout_reason)
        }
      }
  }
}

/// Convenience for the runtime: None actor yields Unavailable(not_running_reason).
pub fn observe_live(
  at: Int,
  actor: Option(Subject(system.Message)),
  timeout_ms: Int,
) -> api.Observation {
  case actor {
    None -> api.Unavailable(not_running_reason)
    Some(a) -> observe(at, query(a, timeout_ms))
  }
}
