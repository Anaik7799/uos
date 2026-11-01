//// Bounded factual owner journal client. Neither configuration nor records
//// authenticate an admitted owner or grant task permission. Actual paired
//// guardian cleanup is retained; missing cleanup never becomes a successful IO.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/native_launch
import cepaf_gleam/harness/telegram_store_transport as transport
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/json_guard
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Binding {
  Binding(
    owner_id: String,
    operation_id: String,
    request_sha256: String,
    context_sha256: String,
  )
}

pub type Phase {
  Pending
  Unknown
  CommittedFact
  Refused
  ReconcileOnly
}

pub type Entry {
  Entry(
    sequence: Int,
    phase: Phase,
    receipt_sha256: Option(String),
    previous_sha256: Option(String),
    sha256: String,
  )
}

pub type Cleanup {
  Reaped(exit: Int, utc_us: Int)
  Unconfirmed
}

pub type RawExchange {
  RawExchange(body: Result(String, String), cleanup: Cleanup)
}

pub type Reply {
  Reply(code: String, record: Option(Entry))
}

pub type Exchange {
  Exchange(reply: Result(Reply, String), cleanup: Cleanup)
}

/// Explicit transport DATA, never an owner/issuer/resource authority. Legacy
/// callers retain their existing constructor/API; finite refusal never falls
/// back to legacy. Trusted caller separately binds manifest and resource scope.
pub opaque type ConnectionData {
  LegacyConnection(transport.LocalConfiguration)
  FiniteConnection(native_launch.Configuration)
}

pub fn legacy_connection_data(
  c: transport.LocalConfiguration,
) -> ConnectionData {
  LegacyConnection(c)
}

pub fn finite_connection_data(
  c: native_launch.Configuration,
) -> ConnectionData {
  FiniteConnection(c)
}

@external(erlang, "telegram_store_transport_ffi", "request_config_with_cleanup")
fn native(
  config: transport.LocalConfiguration,
  body: String,
) -> #(Result(String, String), Option(#(Int, Int)))

pub fn sha(s: String) -> Bool {
  string.byte_size(s) == 64
  && list.all(string.to_graphemes(s), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}

pub fn identifier(s: String) -> Bool {
  string.byte_size(s) > 0
  && string.byte_size(s) <= 160
  && list.all(string.to_utf_codepoints(s), fn(c) {
    let n = string.utf_codepoint_to_int(c)
    n >= 48
    && n <= 57
    || n >= 65
    && n <= 90
    || n >= 97
    && n <= 122
    || list.contains([45, 46, 47, 95], n)
  })
}

pub fn valid_binding(b: Binding) -> Bool {
  identifier(b.owner_id)
  && sha(b.operation_id)
  && sha(b.request_sha256)
  && sha(b.context_sha256)
}

pub fn phase_text(p: Phase) -> String {
  case p {
    Pending -> "pending"
    Unknown -> "unknown"
    CommittedFact -> "committed_fact"
    Refused -> "refused"
    ReconcileOnly -> "reconcile_only"
  }
}

pub fn binding_value(b: Binding) -> json.Json {
  json.object([
    #("owner_id", json.string(b.owner_id)),
    #("operation_id", json.string(b.operation_id)),
    #("request_sha256", json.string(b.request_sha256)),
    #("context_sha256", json.string(b.context_sha256)),
  ])
}

fn optional(s: Option(String)) -> json.Json {
  case s {
    None -> json.null()
    Some(s) -> json.string(s)
  }
}

pub fn record_digest(b: Binding, r: Entry) -> String {
  files.digest(
    json.to_string(
      json.object([
        #("domain", json.string("uos.recovery-owner-record.v1")),
        #("binding", binding_value(b)),
        #("sequence", json.int(r.sequence)),
        #("phase", json.string(phase_text(r.phase))),
        #("receipt_sha256", optional(r.receipt_sha256)),
        #("previous_sha256", optional(r.previous_sha256)),
      ]),
    ),
  )
}

pub fn body(
  b: Binding,
  event: Option(#(Int, Phase, Option(String))),
  previous: Option(String),
) -> Result(String, String) {
  use _ <- result.try(case valid_binding(b) {
    True -> Ok(Nil)
    False -> Error("INVALID_BINDING")
  })
  let event_json = case event {
    None -> json.null()
    Some(#(sequence, p, receipt)) ->
      json.object([
        #("sequence", json.int(sequence)),
        #("phase", json.string(phase_text(p))),
        #("receipt_sha256", optional(receipt)),
      ])
  }
  Ok(
    json.to_string(
      json.object([
        #("schema_version", json.int(1)),
        #(
          "operation",
          json.string(case event {
            None -> "latest"
            Some(_) -> "append"
          }),
        ),
        #("binding", binding_value(b)),
        #("expected_previous", optional(previous)),
        #("event", event_json),
      ]),
    ),
  )
}

pub fn raw_exchange(
  config: transport.LocalConfiguration,
  body: String,
) -> RawExchange {
  case string.byte_size(body) > 0 && string.byte_size(body) <= 65_536 {
    False -> RawExchange(Error("INPUT_BOUND"), Unconfirmed)
    True -> {
      let #(result, witness) = native(config, body)
      let cleanup = case witness {
        Some(#(exit, utc))
          if { exit == 0 || exit == 124 || exit == 125 }
          && utc > 0
          && utc <= 9_000_000_000_000_000
        -> Reaped(exit, utc)
        _ -> Unconfirmed
      }
      RawExchange(result, cleanup)
    }
  }
}

pub fn raw_exchange_finite(
  config: native_launch.Configuration,
  body: String,
) -> RawExchange {
  case string.byte_size(body) > 0 && string.byte_size(body) <= 65_536 {
    False -> RawExchange(Error("INPUT_BOUND"), Unconfirmed)
    True -> {
      let #(reply, witness) = native_launch.exchange_with_cleanup(config, body)
      let result =
        result.map_error(reply, fn(code) {
          case code {
            transport.InputBound -> "transport_input_bound"
            transport.ConfigurationOrSpawn -> "transport_configuration_or_spawn"
            transport.Uncertain -> "transport_uncertain"
            transport.CleanupUnknown -> "transport_cleanup_unknown"
          }
        })
      let cleanup = case witness {
        Some(#(exit, utc))
          if { exit == 0 || exit == 124 || exit == 125 }
          && utc > 0
          && utc <= 9_000_000_000_000_000
        -> Reaped(exit, utc)
        _ -> Unconfirmed
      }
      RawExchange(result, cleanup)
    }
  }
}

fn raw_connection(config: ConnectionData, body: String) -> RawExchange {
  case config {
    LegacyConnection(c) -> raw_exchange(c, body)
    FiniteConnection(c) -> raw_exchange_finite(c, body)
  }
}

pub fn cleanup_known(c: Cleanup) -> Bool {
  case c {
    Reaped(_, _) -> True
    Unconfirmed -> False
  }
}

pub fn successful(c: Cleanup) -> Bool {
  case c {
    Reaped(0, _) -> True
    _ -> False
  }
}

fn closed(value: v.Value, keys: List(String)) -> Result(Nil, String) {
  case value {
    v.Object(fs) ->
      case
        list.length(fs) == list.length(keys)
        && list.all(fs, fn(f) { list.contains(keys, f.0) })
      {
        True -> Ok(Nil)
        False -> Error("REPLY_SCHEMA")
      }
    _ -> Error("REPLY_SCHEMA")
  }
}

pub fn text(value: v.Value, k: String) -> Result(String, String) {
  use x <- result.try(v.get(value, k))
  case x {
    v.Text(s) -> Ok(s)
    _ -> Error("REPLY_TEXT")
  }
}

fn optional_digest(
  value: v.Value,
  k: String,
) -> Result(Option(String), String) {
  use x <- result.try(v.get(value, k))
  case x {
    v.Null -> Ok(None)
    v.Text(s) ->
      case sha(s) {
        True -> Ok(Some(s))
        False -> Error("REPLY_DIGEST")
      }
    _ -> Error("REPLY_DIGEST")
  }
}

fn decode_phase(s: String) -> Result(Phase, String) {
  case s {
    "pending" -> Ok(Pending)
    "unknown" -> Ok(Unknown)
    "committed_fact" -> Ok(CommittedFact)
    "refused" -> Ok(Refused)
    "reconcile_only" -> Ok(ReconcileOnly)
    _ -> Error("REPLY_PHASE")
  }
}

fn decode_record(b: Binding, value: v.Value) -> Result(Option(Entry), String) {
  case value {
    v.Null -> Ok(None)
    _ -> {
      use _ <- result.try(
        closed(value, [
          "sequence",
          "phase",
          "receipt_sha256",
          "previous_sha256",
          "sha256",
        ]),
      )
      use sequence <- result.try(case v.get(value, "sequence") {
        Ok(v.Integer(n)) if n > 0 && n <= 256 -> Ok(n)
        _ -> Error("REPLY_SEQUENCE")
      })
      use p <- result.try(text(value, "phase") |> result.try(decode_phase))
      use receipt <- result.try(optional_digest(value, "receipt_sha256"))
      use previous <- result.try(optional_digest(value, "previous_sha256"))
      use digest <- result.try(text(value, "sha256"))
      let r = Entry(sequence, p, receipt, previous, digest)
      case
        digest == record_digest(b, r)
        && { p == CommittedFact } == { receipt != None }
        && { sequence == 1 } == { previous == None }
      {
        True -> Ok(Some(r))
        False -> Error("REPLY_RECORD_BINDING")
      }
    }
  }
}

pub fn decode_reply(raw: String, b: Binding) -> Result(Reply, String) {
  use _ <- result.try(case string.byte_size(raw) <= 16_384 {
    True -> Ok(Nil)
    False -> Error("REPLY_BOUND")
  })
  use value <- result.try(
    json_guard.native_inspect(raw, 6)
    |> result.map_error(fn(_) { "INVALID_JSON" }),
  )
  use _ <- result.try(
    closed(value, ["status", "code", "binding", "record", "authority"]),
  )
  use status <- result.try(text(value, "status"))
  use authority <- result.try(text(value, "authority"))
  use code <- result.try(text(value, "code"))
  use rb <- result.try(v.get(value, "binding"))
  use _ <- result.try(
    closed(rb, ["owner_id", "operation_id", "request_sha256", "context_sha256"]),
  )
  use owner <- result.try(text(rb, "owner_id"))
  use operation <- result.try(text(rb, "operation_id"))
  use request <- result.try(text(rb, "request_sha256"))
  use context <- result.try(text(rb, "context_sha256"))
  use _ <- result.try(
    case
      status == "ok"
      && authority == "NONE"
      && list.contains(["APPENDED", "REPLAY", "LATEST"], code)
      && Binding(owner, operation, request, context) == b
    {
      True -> Ok(Nil)
      False -> Error("JOURNAL_HOLD_OR_BINDING")
    },
  )
  use value <- result.try(v.get(value, "record"))
  use record <- result.try(decode_record(b, value))
  Ok(Reply(code, record))
}

pub fn exchange(
  config: transport.LocalConfiguration,
  b: Binding,
  event: Option(#(Int, Phase, Option(String))),
  previous: Option(String),
) -> Exchange {
  exchange_connection_data(legacy_connection_data(config), b, event, previous)
}

pub fn exchange_connection_data(
  config: ConnectionData,
  b: Binding,
  event: Option(#(Int, Phase, Option(String))),
  previous: Option(String),
) -> Exchange {
  case body(b, event, previous) {
    Error(code) -> Exchange(Error(code), Unconfirmed)
    Ok(body) -> {
      let raw = raw_connection(config, body)
      let reply = case successful(raw.cleanup) {
        True -> {
          use reply <- result.try(
            raw.body |> result.try(fn(raw) { decode_reply(raw, b) }),
          )
          case event, reply.record {
            None, _ if reply.code == "LATEST" -> Ok(reply)
            Some(#(n, p, digest)), Some(r)
              if r.sequence == n
              && r.phase == p
              && r.receipt_sha256 == digest
              && r.previous_sha256 == previous
              && { reply.code == "APPENDED" || reply.code == "REPLAY" }
            -> Ok(reply)
            _, _ -> Error("JOURNAL_ACK_REQUEST_MISMATCH")
          }
        }
        False -> Error("JOURNAL_CLEANUP_OR_TRANSPORT")
      }
      Exchange(reply, raw.cleanup)
    }
  }
}
