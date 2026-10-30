//// T15 Unified JSON-RPC wire normalizer. Decouples transport concerns from
//// logical effect identity: notifications are always silent on the wire, and
//// logical effect IDs stay stable across changing JSON-RPC transport ids.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/profiles/legacy
import cepaf_gleam/mcp/profiles/modern
import cepaf_gleam/mcp/types.{
  type Outcome, type ProtocolProfile, Complete, Legacy20241105, Modern20260728,
  Refused, Uncertain,
}
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type WireId {
  NoIdNotification
  StringId(String)
  IntId(Int)
}

pub type WireError {
  WireError(code: String, reason: String)
}

pub type NormalizedMessage {
  NormalizedMessage(
    id: WireId,
    method: String,
    args: List(#(String, String)),
    canonical_json: String,
  )
}

pub fn decode_request(
  profile: ProtocolProfile,
  raw_json: String,
) -> Result(NormalizedMessage, WireError) {
  case json.parse(raw_json, message_decoder()) {
    Error(_) ->
      Error(WireError(
        code: "MALFORMED_JSONRPC",
        reason: "Request is not a well-formed JSON-RPC message",
      ))
    Ok(message) -> validate_profile(profile, message)
  }
}

pub fn logical_effect_id(
  route: String,
  method_or_tool: String,
  canonical_args: List(#(String, String)),
  explicit_idempotency_key: Option(String),
) -> String {
  let suffix = case explicit_idempotency_key {
    Some(key) -> "idem:" <> key
    None ->
      canonical_args
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.map(fn(kv) { kv.0 <> "=" <> kv.1 })
      |> string.join("&")
  }
  files.digest(route <> "|" <> method_or_tool <> "|" <> suffix)
}

pub fn encode_outcome(
  profile: ProtocolProfile,
  req_id: WireId,
  outcome: Outcome,
) -> Option(String) {
  case req_id {
    NoIdNotification -> None
    StringId(_) | IntId(_) -> {
      let id_json = case req_id {
        StringId(value) -> json.string(value)
        IntId(value) -> json.int(value)
        NoIdNotification -> json.null()
      }
      Some(json.to_string(encode_response(profile, id_json, outcome)))
    }
  }
}

fn validate_profile(
  profile: ProtocolProfile,
  message: NormalizedMessage,
) -> Result(NormalizedMessage, WireError) {
  let mismatched = case profile {
    Legacy20241105 -> list.contains(legacy.modern_only_methods, message.method)
    Modern20260728 -> list.contains(modern.legacy_only_methods, message.method)
  }
  case mismatched {
    True ->
      Error(WireError(
        code: "PROFILE_METHOD_MISMATCH",
        reason: "Method " <> message.method <> " is not valid for this profile",
      ))
    False -> Ok(message)
  }
}

fn message_decoder() -> decode.Decoder(NormalizedMessage) {
  use id <- decode.optional_field(
    "id",
    NoIdNotification,
    id_nullable_decoder(),
  )
  use method <- decode.field("method", decode.string)
  use args_dict <- decode.then(
    decode.optionally_at(
      ["params", "arguments"],
      dict.new(),
      decode.dict(decode.string, decode.string),
    ),
  )
  let args = dict.to_list(args_dict)
  decode.success(NormalizedMessage(
    id: id,
    method: method,
    args: args,
    canonical_json: canonical_json(method, args),
  ))
}

fn id_value_decoder() -> decode.Decoder(WireId) {
  decode.one_of(decode.map(decode.int, IntId), [
    decode.map(decode.string, StringId),
  ])
}

fn id_nullable_decoder() -> decode.Decoder(WireId) {
  decode.map(decode.optional(id_value_decoder()), fn(maybe) {
    case maybe {
      Some(id) -> id
      None -> NoIdNotification
    }
  })
}

fn canonical_json(method: String, args: List(#(String, String))) -> String {
  let sorted = list.sort(args, fn(a, b) { string.compare(a.0, b.0) })
  json.to_string(json.object([
    #("method", json.string(method)),
    #(
      "args",
      json.object(list.map(sorted, fn(kv) { #(kv.0, json.string(kv.1)) })),
    ),
  ]))
}

fn encode_response(
  profile: ProtocolProfile,
  id_json: json.Json,
  outcome: Outcome,
) -> json.Json {
  case profile {
    Legacy20241105 -> legacy_response(id_json, outcome)
    Modern20260728 -> modern_response(id_json, outcome)
  }
}

fn legacy_response(id_json: json.Json, outcome: Outcome) -> json.Json {
  case outcome {
    Complete(value, _) ->
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", id_json),
        #("result", json.string(value)),
      ])
    Refused(error) ->
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", id_json),
        #("error", json.object([
          #("code", json.string(error.code)),
          #("message", json.string(error.reason)),
        ])),
      ])
    Uncertain(receipt) ->
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", id_json),
        #("error", json.object([
          #("code", json.string("UNCERTAIN")),
          #("message", json.string(receipt.reason)),
        ])),
      ])
  }
}

fn modern_response(id_json: json.Json, outcome: Outcome) -> json.Json {
  case outcome {
    Complete(value, evidence) ->
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", id_json),
        #("result", json.object([
          #("status", json.string("complete")),
          #("value", json.string(value)),
          #("evidence", json.object([
            #("candidate", json.string(evidence.candidate)),
            #("route", json.string(evidence.route)),
            #("tool", json.string(evidence.tool)),
            #("output_sha256", json.string(evidence.output_sha256)),
          ])),
        ])),
      ])
    Refused(error) ->
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", id_json),
        #("error", json.object([
          #("code", json.string(error.code)),
          #("message", json.string(error.reason)),
          #("data", json.object([#("structured", json.bool(True))])),
        ])),
      ])
    Uncertain(receipt) ->
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", id_json),
        #("result", json.object([
          #("status", json.string("uncertain")),
          #("reason", json.string(receipt.reason)),
        ])),
      ])
  }
}
