//// Exact native-v2 detached signature FACTS only. No key/provider/custody or
//// task/release permission is constructed. Expected bindings are caller DATA.
//// Four bounded calls stop immediately on refusal or uncertain cleanup; no
//// retry, durable replay policy or global linearity guarantee is supplied.

import cepaf_gleam/harness/native_launch
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/json_guard
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type ExpectedData {
  ExpectedData(
    intent: String,
    manifest_sha256: String,
    request_sha256: String,
    capability_sha256: String,
  )
}

pub opaque type Facts {
  Facts(values: List(v.Value), cleanup_times: List(Int))
}

fn hex(text: String, length: Int) -> Bool {
  string.byte_size(text) == length
  && list.all(string.to_graphemes(text), fn(c) {
    string.byte_size(c) == 1 && string.contains("0123456789abcdef", c)
  })
}

fn token(text: String) -> Bool {
  string.byte_size(text) > 0
  && string.byte_size(text) <= 200
  && list.all(string.to_utf_codepoints(text), fn(c) {
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

fn text(value: v.Value, key: String) -> Result(String, String) {
  case v.get(value, key) {
    Ok(v.Text(s)) -> Ok(s)
    _ -> Error("SIGNATURE_FIELD_TYPE")
  }
}

fn call(
  config: native_launch.Configuration,
  expected: ExpectedData,
  operation: String,
  kr: String,
  ki: String,
  rr: String,
  resource: Option(String),
) -> Result(#(v.Value, String, Int), String) {
  // Ordered canonical fields are part of the native request ABI.
  let body =
    json.to_string(
      json.object([
        #("schema", json.string("uos.recovery.native-signing.v2")),
        #("operation", json.string(operation)),
        #("intent_id", json.string(expected.intent)),
        #("kernel_review", json.string(kr)),
        #("kernel_issuer", json.string(ki)),
        #("resource_review", json.string(rr)),
      ]),
    )
  use _ <- result.try(case string.byte_size(body) <= 2048 {
    True -> Ok(Nil)
    False -> Error("SIGNATURE_REQUEST_BOUND")
  })
  let #(reply, cleanup) = native_launch.exchange_with_cleanup(config, body)
  // Even an otherwise valid body without this SAME invocation's exit0 witness
  // is unusable; do not issue a subsequent role request after uncertainty.
  use observed <- result.try(case cleanup {
    Some(#(0, utc)) if utc > 0 && utc <= 9_000_000_000_000_000 -> Ok(utc)
    _ -> Error("SIGNATURE_CLEANUP_UNCONFIRMED_NO_AUTORETRY")
  })
  use raw <- result.try(
    result.map_error(reply, fn(_) { "SIGNATURE_OUTCOME_UNKNOWN_NO_AUTORETRY" }),
  )
  use _ <- result.try(
    case string.byte_size(raw) > 0 && string.byte_size(raw) <= 4096 {
      True -> Ok(Nil)
      False -> Error("SIGNATURE_REPLY_BOUND")
    },
  )
  use value <- result.try(
    json_guard.native_inspect(raw, 8)
    |> result.map_error(fn(_) { "SIGNATURE_JSON_REFUSED" }),
  )
  let keys = [
    "status",
    "operation",
    "intent_id",
    "manifest_sha256",
    "request_sha256",
    "capability_sha256",
    "resource_sha256",
    "signature_hex",
    "authority",
    "admitted",
  ]
  use _ <- result.try(case value {
    v.Object(fields) ->
      case
        list.length(fields) == list.length(keys)
        && list.all(fields, fn(f) { list.contains(keys, f.0) })
      {
        True -> Ok(Nil)
        False -> Error("SIGNATURE_CLOSED_SCHEMA")
      }
    _ -> Error("SIGNATURE_OBJECT_REQUIRED")
  })
  use status <- result.try(text(value, "status"))
  use op <- result.try(text(value, "operation"))
  use intent <- result.try(text(value, "intent_id"))
  use manifest <- result.try(text(value, "manifest_sha256"))
  use request <- result.try(text(value, "request_sha256"))
  use capability <- result.try(text(value, "capability_sha256"))
  use signature <- result.try(text(value, "signature_hex"))
  use authority <- result.try(text(value, "authority"))
  use actual_resource <- result.try(v.get(value, "resource_sha256"))
  let resource_matches = case operation, resource, actual_resource {
    "review_kernel", None, v.Null | "issue_kernel", None, v.Null -> True
    "review_resource", None, v.Text(hash) -> hex(hash, 64)
    "issue_resource", Some(expected_hash), v.Text(hash) ->
      hex(hash, 64) && hash == expected_hash
    _, _, _ -> False
  }
  use _ <- result.try(
    case
      status == "SIGNATURE_FACT_ONLY"
      && op == operation
      && intent == expected.intent
      && manifest == expected.manifest_sha256
      && request == expected.request_sha256
      && capability == expected.capability_sha256
      && hex(signature, 128)
      && authority == "NONE"
      && v.get(value, "admitted") == Ok(v.Boolean(False))
      && resource_matches
    {
      True -> Ok(Nil)
      False -> Error("SIGNATURE_FACT_BINDING")
    },
  )
  Ok(#(value, signature, observed))
}

/// The native issuer validates prior signatures; a separate native finalizer
/// must still run unchanged K.verify/R.verify against the actual resource.
pub fn collect_four(
  reviewer: native_launch.Configuration,
  issuer: native_launch.Configuration,
  expected: ExpectedData,
) -> Result(Facts, String) {
  use _ <- result.try(
    case
      token(expected.intent)
      && hex(expected.manifest_sha256, 64)
      && hex(expected.request_sha256, 64)
      && hex(expected.capability_sha256, 64)
    {
      True -> Ok(Nil)
      False -> Error("SIGNATURE_EXPECTED_DATA")
    },
  )
  use #(a, kr, ta) <- result.try(call(
    reviewer,
    expected,
    "review_kernel",
    "",
    "",
    "",
    None,
  ))
  use #(b, ki, tb) <- result.try(call(
    issuer,
    expected,
    "issue_kernel",
    kr,
    "",
    "",
    None,
  ))
  use #(c, rr, tc) <- result.try(call(
    reviewer,
    expected,
    "review_resource",
    kr,
    ki,
    "",
    None,
  ))
  use resource <- result.try(text(c, "resource_sha256"))
  use #(d, _, td) <- result.try(call(
    issuer,
    expected,
    "issue_resource",
    kr,
    ki,
    rr,
    Some(resource),
  ))
  Ok(Facts([a, b, c, d], [ta, tb, tc, td]))
}

pub fn facts_json(facts: Facts) -> String {
  json.to_string(json.array(facts.values, v.encode))
}

pub fn cleanup_json(facts: Facts) -> String {
  json.to_string(
    json.array(facts.cleanup_times, fn(t) {
      json.object([#("exit", json.int(0)), #("observed_utc_us", json.int(t))])
    }),
  )
}
