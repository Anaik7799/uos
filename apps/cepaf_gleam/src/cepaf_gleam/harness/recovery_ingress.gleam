//// Isolated development candidate JSON interface. No native worker, runtime
//// collector, issuer authentication, MCP server registration or task effects.

import cepaf_gleam/harness/recovery_model as model
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/json_guard
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type State {
  State(candidate: Option(model.Candidate))
}

pub fn initial() -> State {
  State(None)
}

pub fn supported_operations() -> List(String) {
  ["status", "prepare", "commit_set", "inspect"]
}

fn invalid() -> Result(a, String) {
  Error("INVALID_WIRE")
}

fn closed(v: value.Value, keys: List(String)) -> Result(Nil, String) {
  case v {
    value.Object(fields) ->
      case
        list.length(fields) == list.length(keys)
        && list.all(fields, fn(p) { list.contains(keys, p.0) })
      {
        True -> Ok(Nil)
        False -> invalid()
      }
    _ -> invalid()
  }
}

fn field(v: value.Value, key: String) -> Result(value.Value, String) {
  value.get(v, key) |> result.map_error(fn(_) { "INVALID_WIRE" })
}

fn text(v: value.Value, key: String) -> Result(String, String) {
  use v <- result.try(field(v, key))
  case v {
    value.Text(s) -> Ok(s)
    _ -> invalid()
  }
}

fn integer(v: value.Value, key: String) -> Result(Int, String) {
  use v <- result.try(field(v, key))
  case v {
    value.Integer(n) -> Ok(n)
    _ -> invalid()
  }
}

fn nanoseconds(v: value.Value, key: String) -> Result(Int, String) {
  use raw <- result.try(text(v, key))
  case string.byte_size(raw) > 0 && string.byte_size(raw) <= 19 {
    False -> invalid()
    True ->
      case int.parse(raw) {
        Ok(n) if n > 0 && n <= 9_000_000_000_000_000_000 ->
          case int.to_string(n) == raw {
            True -> Ok(n)
            False -> invalid()
          }
        _ -> invalid()
      }
  }
}

fn bindings(v: value.Value) -> Result(model.ClaimedBindings, String) {
  use _ <- result.try(
    closed(v, [
      "snapshot",
      "portfolio",
      "selection",
      "selection_proof",
      "review",
      "source",
      "native_worker",
      "guardian",
    ]),
  )
  use snapshot <- result.try(text(v, "snapshot"))
  use portfolio <- result.try(text(v, "portfolio"))
  use selection <- result.try(text(v, "selection"))
  use proof <- result.try(text(v, "selection_proof"))
  use review <- result.try(text(v, "review"))
  use source <- result.try(text(v, "source"))
  use worker <- result.try(text(v, "native_worker"))
  use guardian <- result.try(text(v, "guardian"))
  Ok(model.ClaimedBindings(
    snapshot,
    portfolio,
    selection,
    proof,
    review,
    source,
    worker,
    guardian,
  ))
}

fn window(v: value.Value) -> Result(model.Window, String) {
  use _ <- result.try(
    closed(v, [
      "host",
      "boot",
      "clock_domain",
      "created_utc_ms",
      "expires_utc_ms",
      "created_mono_ms",
      "expires_mono_ms",
    ]),
  )
  use host <- result.try(text(v, "host"))
  use boot <- result.try(text(v, "boot"))
  use domain <- result.try(text(v, "clock_domain"))
  use created <- result.try(integer(v, "created_utc_ms"))
  use expires <- result.try(integer(v, "expires_utc_ms"))
  use mono_created <- result.try(integer(v, "created_mono_ms"))
  use mono_expires <- result.try(integer(v, "expires_mono_ms"))
  Ok(model.Window(
    host,
    boot,
    domain,
    created,
    expires,
    mono_created,
    mono_expires,
  ))
}

fn member(v: value.Value) -> Result(model.Member, String) {
  use _ <- result.try(
    closed(v, [
      "task",
      "worker",
      "old_attempt",
      "old_lease_ns",
      "next_attempt",
      "lease_ms",
    ]),
  )
  use task <- result.try(text(v, "task"))
  use worker <- result.try(text(v, "worker"))
  use attempt <- result.try(integer(v, "old_attempt"))
  use lease <- result.try(nanoseconds(v, "old_lease_ns"))
  use next <- result.try(integer(v, "next_attempt"))
  use duration <- result.try(integer(v, "lease_ms"))
  Ok(model.Member(task, worker, attempt, lease, next, duration))
}

fn proposal(v: value.Value) -> Result(model.Proposal, String) {
  use _ <- result.try(
    closed(v, [
      "schema",
      "request_id",
      "plan",
      "issuer",
      "issuer_session",
      "reviewer",
      "reviewer_session",
      "bindings",
      "window",
      "members",
    ]),
  )
  use schema <- result.try(text(v, "schema"))
  use _ <- result.try(case schema == "uos.recovery-candidate.v1" {
    True -> Ok(Nil)
    False -> invalid()
  })
  use request <- result.try(text(v, "request_id"))
  use plan <- result.try(text(v, "plan"))
  use issuer <- result.try(text(v, "issuer"))
  use session <- result.try(text(v, "issuer_session"))
  use reviewer <- result.try(text(v, "reviewer"))
  use peer_session <- result.try(text(v, "reviewer_session"))
  use b <- result.try(field(v, "bindings"))
  use b <- result.try(bindings(b))
  use w <- result.try(field(v, "window"))
  use w <- result.try(window(w))
  use ms <- result.try(field(v, "members"))
  use ms <- result.try(case ms {
    value.Array(ms) ->
      case list.length(ms) == 3 {
        True -> list.try_map(ms, member)
        False -> invalid()
      }
    _ -> invalid()
  })
  Ok(model.Proposal(
    request,
    plan,
    issuer,
    session,
    reviewer,
    peer_session,
    b,
    w,
    ms,
  ))
}

fn decode(raw: String) -> Result(#(String, value.Value), String) {
  use _ <- result.try(
    case string.byte_size(raw) > 0 && string.byte_size(raw) <= 32_768 {
      True -> Ok(Nil)
      False -> Error("INPUT_BOUND")
    },
  )
  use v <- result.try(
    json_guard.native_inspect(raw, 12)
    |> result.map_error(fn(_) { "INVALID_JSON" }),
  )
  use _ <- result.try(closed(v, ["schema_version", "operation", "payload"]))
  use version <- result.try(integer(v, "schema_version"))
  use _ <- result.try(case version == 1 {
    True -> Ok(Nil)
    False -> invalid()
  })
  use operation <- result.try(text(v, "operation"))
  use payload <- result.try(field(v, "payload"))
  Ok(#(operation, payload))
}

fn bound_candidate(
  state: State,
  v: value.Value,
) -> Result(model.Candidate, String) {
  use _ <- result.try(closed(v, ["request_id", "candidate_digest"]))
  use request <- result.try(text(v, "request_id"))
  use digest <- result.try(text(v, "candidate_digest"))
  use candidate <- result.try(case state.candidate {
    Some(candidate) -> Ok(candidate)
    None -> Error("NOT_PREPARED")
  })
  let saved = model.inspect(candidate)
  case request == saved.request_id && digest == saved.candidate_digest {
    True -> Ok(candidate)
    False -> Error("CANDIDATE_BINDING_MISMATCH")
  }
}

fn advance(
  candidate: model.Candidate,
  c: model.SuppliedContext,
) -> Result(model.Candidate, String) {
  model.advance(candidate, c) |> result.map_error(model.rejection_code)
}

fn perform(
  state: State,
  operation: String,
  v: value.Value,
  c: model.SuppliedContext,
) -> Result(#(State, String, Bool), String) {
  case operation {
    "status" -> {
      use _ <- result.try(closed(v, []))
      case state.candidate {
        None -> Ok(#(state, "CANDIDATE_INTERFACE_ONLY", False))
        Some(candidate) -> {
          use next <- result.try(advance(candidate, c))
          Ok(#(State(Some(next)), "CANDIDATE_INTERFACE_ONLY", False))
        }
      }
    }
    "prepare" -> {
      use p <- result.try(proposal(v))
      case state.candidate {
        Some(candidate) -> {
          let saved = model.inspect(candidate)
          use _ <- result.try(
            case saved.candidate_digest == model.proposal_digest(p) {
              True -> Ok(Nil)
              False ->
                Error(case saved.request_id == p.request_id {
                  True -> "CONFLICTING_REPLAY"
                  False -> "CANDIDATE_ALREADY_PREPARED"
                })
            },
          )
          use next <- result.try(advance(candidate, c))
          Ok(#(State(Some(next)), "HISTORICAL_CANDIDATE_DATA", False))
        }
        None -> {
          use candidate <- result.try(
            model.validate(p, c)
            |> result.map_error(model.rejection_code),
          )
          Ok(#(State(Some(candidate)), "CANDIDATE_DATA_PREPARED", False))
        }
      }
    }
    "commit_set" | "inspect" -> {
      use candidate <- result.try(bound_candidate(state, v))
      use next <- result.try(advance(candidate, c))
      case operation {
        // This is a refused effect with a retained valid clock observation.
        // Returning through the generic Error branch would lose the high-water.
        "commit_set" -> Ok(#(State(Some(next)), "WORKER_UNAVAILABLE", True))
        _ -> Ok(#(State(Some(next)), "LOCAL_CANDIDATE_ONLY", False))
      }
    }
    _ -> Error("UNKNOWN_OPERATION")
  }
}

fn response(state: State, code: String, held: Bool) -> String {
  let candidate = case state.candidate {
    None -> json.null()
    Some(candidate) -> json.string(model.inspect(candidate).candidate_digest)
  }
  json.to_string(
    json.object([
      #("schema_version", json.int(1)),
      #(
        "status",
        json.string(case held {
          True -> "HOLD"
          False -> "DATA_ONLY"
        }),
      ),
      #("code", json.string(code)),
      #("candidate_digest", candidate),
      #("authority", json.string("NONE")),
      #("new_effect_permission", json.bool(False)),
      #("mutation_attempted", json.bool(False)),
      #("worker_status", json.string("UNIMPLEMENTED")),
      #("native_outcome", json.string("UNOBSERVED")),
      #("context_authenticated", json.bool(False)),
      #("independent_review_authenticated", json.bool(False)),
      #("runtime_activation", json.bool(False)),
    ]),
  )
}

/// Pure bounded candidate protocol. The context is supplied outside the wire
/// and remains unauthenticated fixture data. No native dispatch function or
/// authenticated-worker constructor exists: commit_set always refuses.
pub fn handle_candidate_json(
  state: State,
  raw: String,
  context: model.SuppliedContext,
) -> #(State, String) {
  let outcome = {
    use decoded <- result.try(decode(raw))
    perform(state, decoded.0, decoded.1, context)
  }
  case outcome {
    Ok(#(next, code, held)) -> #(next, response(next, code, held))
    Error(code) -> #(state, response(state, code, True))
  }
}
