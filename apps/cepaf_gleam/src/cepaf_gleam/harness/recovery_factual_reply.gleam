//// Closed factual DATA decoder. Parsing a native observation grants no task,
//// owner or effect authority. Caller must separately verify transport cleanup,
//// signatures, current owner, exact resource scope and the full causal receipt.
//// Legacy fixture authority strings are not accepted by this v1 schema.

import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/json_guard
import gleam/list
import gleam/result
import gleam/string

fn text(value: v.Value, key: String) -> Result(String, String) {
  case v.get(value, key) {
    Ok(v.Text(s)) -> Ok(s)
    _ -> Error("FACTUAL_FIELD_TYPE")
  }
}

/// Returns only a fresh or historical receipt DATA value. The owner still
/// checks every causal request/capability binding; UNKNOWN never becomes success.
pub fn committed_receipt(raw: String) -> Result(v.Value, String) {
  use _ <- result.try(
    case string.byte_size(raw) > 0 && string.byte_size(raw) <= 32_768 {
      True -> Ok(Nil)
      False -> Error("FACTUAL_REPLY_BOUND")
    },
  )
  use value <- result.try(
    json_guard.native_inspect(raw, 12)
    |> result.map_error(fn(_) { "FACTUAL_INVALID_JSON" }),
  )
  let keys = [
    "schema",
    "status",
    "code",
    "authority",
    "application_admitted",
    "system_admitted",
    "receipt",
  ]
  use _ <- result.try(case value {
    v.Object(fields) ->
      case
        list.length(fields) == list.length(keys)
        && list.all(fields, fn(f) { list.contains(keys, f.0) })
      {
        True -> Ok(Nil)
        False -> Error("FACTUAL_CLOSED_SCHEMA")
      }
    _ -> Error("FACTUAL_OBJECT_REQUIRED")
  })
  use schema <- result.try(text(value, "schema"))
  use status <- result.try(text(value, "status"))
  use code <- result.try(text(value, "code"))
  use authority <- result.try(text(value, "authority"))
  use _ <- result.try(
    case
      schema == "uos.recovery-adapter.factual.v1"
      && authority == "NONE"
      && v.get(value, "application_admitted") == Ok(v.Boolean(False))
      && v.get(value, "system_admitted") == Ok(v.Boolean(False))
      && {
        status == "COMMITTED"
        && code == "COMMITTED_FACT"
        || status == "HISTORICAL"
        && list.contains(["COMMITTED_FACT_ONLY", "NO_NEW_PERMISSION"], code)
      }
    {
      True -> Ok(Nil)
      False -> Error("FACTUAL_NOT_COMMITTED")
    },
  )
  v.get(value, "receipt")
}
