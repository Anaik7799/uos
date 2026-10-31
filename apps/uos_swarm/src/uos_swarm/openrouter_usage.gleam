//// Read-only provider metadata projection. Missing amounts remain unknown.
//// API observations are not invoices, admission, or permission to spend.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

@external(erlang, "token_monitor_json_ffi", "valid_object")
fn strict_object(text: String) -> Bool

@external(erlang, "uos_openrouter_usage_ffi", "get")
fn get(path: String, timeout_ms: Int) -> Result(#(Int, String), String)

pub opaque type Endpoint {
  Key
  Credits
  Generation(String)
  Activity(String)
}

pub type Observation {
  Observation(http_status: Int, data: json.Json)
}

pub fn endpoint(args: List(String)) -> Result(Endpoint, String) {
  case args {
    ["key"] -> Ok(Key)
    ["credits"] -> Ok(Credits)
    ["generation", id] -> {
      case valid_id(id) {
        True -> Ok(Generation(id))
        False -> Error("invalid_generation_id")
      }
    }
    ["activity", date] -> {
      case valid_date(date) {
        True -> Ok(Activity(date))
        False -> Error("invalid_date")
      }
    }
    _ -> Error("usage_key_credits_generation_ID_activity_DATE")
  }
}

fn ascii_chars(text: String, allowed: String) -> Bool {
  list.all(string.to_graphemes(text), fn(c) {
    string.byte_size(c) == 1 && string.contains(allowed, c)
  })
}

fn valid_id(id: String) -> Bool {
  string.starts_with(id, "gen-")
  && string.byte_size(id) >= 5
  && string.byte_size(id) <= 124
  && ascii_chars(
    id,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-",
  )
}

fn valid_date(date: String) -> Bool {
  case string.split(date, "-") {
    [y, m, d] -> {
      case
        string.byte_size(y) == 4
        && string.byte_size(m) == 2
        && string.byte_size(d) == 2
        && ascii_chars(y <> m <> d, "0123456789")
      {
        False -> False
        True ->
          case int.parse(y), int.parse(m), int.parse(d) {
            Ok(year), Ok(month), Ok(day) -> {
              let leap = year % 400 == 0 || { year % 4 == 0 && year % 100 != 0 }
              let maxday = case month {
                2 ->
                  case leap {
                    True -> 29
                    False -> 28
                  }
                4 | 6 | 9 | 11 -> 30
                _ -> 31
              }
              year >= 1
              && month >= 1
              && month <= 12
              && day >= 1
              && day <= maxday
            }
            _, _, _ -> False
          }
      }
    }
    _ -> False
  }
}

pub fn path(e: Endpoint) -> String {
  case e {
    Key -> "/api/v1/key"
    Credits -> "/api/v1/credits"
    Generation(id) -> "/api/v1/generation?id=" <> id
    Activity(date) -> "/api/v1/activity?date=" <> date
  }
}

pub fn fetch(e: Endpoint) -> Result(Observation, String) {
  run(e, get)
}

pub fn run(
  e: Endpoint,
  io: fn(String, Int) -> Result(#(Int, String), String),
) -> Result(Observation, String) {
  use response <- result.try(
    io(path(e), 30_000) |> result.replace_error("transport_unavailable"),
  )
  observe(e, response.0, response.1)
}

fn number() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.map(decode.int, int.to_float)])
}

type Kind {
  Amount
  Count
  Label
  Flag
}

fn value(kind: Kind) -> decode.Decoder(json.Json) {
  case kind {
    Amount -> {
      use n <- decode.then(number())
      case n >=. 0.0 && n <=. 1_000_000_000_000.0 {
        True -> decode.success(json.float(n))
        False ->
          decode.failure(json.null(), expected: "bounded nonnegative amount")
      }
    }
    Count -> {
      use n <- decode.then(decode.int)
      case n >= 0 && n <= 1_000_000_000_000 {
        True -> decode.success(json.int(n))
        False ->
          decode.failure(json.null(), expected: "bounded nonnegative integer")
      }
    }
    Label -> {
      use s <- decode.then(decode.string)
      case string.byte_size(s) <= 256 {
        True -> decode.success(json.string(s))
        False -> decode.failure(json.null(), expected: "bounded label")
      }
    }
    Flag -> decode.map(decode.bool, json.bool)
  }
}

fn fields(
  spec: List(#(String, Kind)),
) -> decode.Decoder(List(#(String, json.Json))) {
  case spec {
    [] -> decode.success([])
    [#(key, kind), ..rest] -> {
      use found <- decode.optional_field(
        key,
        None,
        decode.optional(value(kind)),
      )
      use remaining <- decode.then(fields(rest))
      decode.success([
        #(key, case found {
          None -> json.null()
          Some(v) -> v
        }),
        ..remaining
      ])
    }
  }
}

fn spec(e: Endpoint) -> List(#(String, Kind)) {
  case e {
    Key -> [
      #("usage", Amount),
      #("usage_daily", Amount),
      #("usage_weekly", Amount),
      #("usage_monthly", Amount),
      #("limit", Amount),
      #("limit_remaining", Amount),
      #("is_management_key", Flag),
      #("include_byok_in_limit", Flag),
      #("byok_usage", Amount),
      #("byok_usage_daily", Amount),
      #("byok_usage_weekly", Amount),
      #("byok_usage_monthly", Amount),
    ]
    Credits -> [#("total_credits", Amount), #("total_usage", Amount)]
    Generation(_) -> [
      #("id", Label),
      #("model", Label),
      #("provider_name", Label),
      #("total_cost", Amount),
      #("usage", Amount),
      #("upstream_inference_cost", Amount),
      #("tokens_prompt", Count),
      #("tokens_completion", Count),
      #("native_tokens_prompt", Count),
      #("native_tokens_completion", Count),
      #("native_tokens_reasoning", Count),
      #("native_tokens_cached", Count),
      #("generation_time", Amount),
      #("latency", Amount),
      #("created_at", Label),
      #("finish_reason", Label),
      #("cancelled", Flag),
      #("streamed", Flag),
      #("is_byok", Flag),
    ]
    Activity(_) -> [
      #("date", Label),
      #("model", Label),
      #("model_permaslug", Label),
      #("provider_name", Label),
      #("usage", Amount),
      #("byok_usage", Amount),
      #("total_cost", Amount),
      #("upstream_inference_cost", Amount),
      #("prompt_tokens", Count),
      #("completion_tokens", Count),
      #("reasoning_tokens", Count),
      #("cached_tokens", Count),
      #("requests", Count),
    ]
  }
}

// Organization/key budget metadata is separate from the key-level limit.
// Null or absent records stay unknown; no budget identifiers are exposed.
fn budget() -> decode.Decoder(json.Json) {
  decode.map(
    fields([
      #("limit_usd", Amount),
      #("remaining_usd", Amount),
      #("spend_usd", Amount),
      #("reset_interval", Label),
      #("resets_at", Label),
      #("scope", Label),
    ]),
    json.object,
  )
}

fn budgets() -> decode.Decoder(json.Json) {
  use records <- decode.then(decode.list(budget()))
  case list.length(records) <= 16 {
    True -> decode.success(json.array(records, fn(x) { x }))
    False -> decode.failure(json.null(), expected: "at most sixteen budgets")
  }
}

fn key_data() -> decode.Decoder(json.Json) {
  use ordinary <- decode.then(fields(spec(Key)))
  use effective <- decode.optional_field(
    "effective_budget",
    None,
    decode.optional(budget()),
  )
  use all <- decode.optional_field("budgets", None, decode.optional(budgets()))
  decode.success(
    json.object(
      list.append(ordinary, [
        #("effective_budget", case effective {
          None -> json.null()
          Some(v) -> v
        }),
        #("budgets", case all {
          None -> json.null()
          Some(v) -> v
        }),
      ]),
    ),
  )
}

pub fn observe(
  e: Endpoint,
  status: Int,
  body: String,
) -> Result(Observation, String) {
  case status >= 200 && status <= 599 && string.byte_size(body) <= 262_144 {
    False -> Error("response_bound_or_status")
    True ->
      case status != 200 {
        True -> Ok(Observation(status, json.null()))
        False -> {
          use _ <- result.try(case strict_object(body) {
            True -> Ok(Nil)
            False -> Error("invalid_json")
          })
          use _ <- result.try(case e {
            Generation(id) ->
              case json.parse(body, decode.at(["data", "id"], decode.string)) {
                Ok(actual) if actual == id -> Ok(Nil)
                _ -> Error("generation_id_mismatch")
              }
            _ -> Ok(Nil)
          })
          let decoder = case e {
            Key -> key_data()
            Activity(_) -> {
              use rows <- decode.then(
                decode.list(decode.map(fields(spec(e)), json.object)),
              )
              case list.length(rows) <= 1000 {
                True -> decode.success(json.array(rows, fn(x) { x }))
                False ->
                  decode.failure(json.null(), expected: "bounded activity rows")
              }
            }
            _ -> decode.map(fields(spec(e)), json.object)
          }
          use data <- result.try(
            json.parse(body, decode.at(["data"], decoder))
            |> result.replace_error("unknown_response_schema"),
          )
          Ok(Observation(status, data))
        }
      }
  }
}

fn report_fields(e: Endpoint, o: Observation) -> List(#(String, json.Json)) {
  [
    #("schema", json.string("uos-openrouter-usage-v1")),
    #(
      "status",
      json.string(case o.http_status {
        200 -> "OBSERVED_PROVIDER_METADATA"
        _ -> "HTTP_ERROR"
      }),
    ),
    #("http_status", json.int(o.http_status)),
    #("endpoint", json.string(path(e))),
    #("authority", json.string("NONE")),
    #("cost_basis", json.string("PROVIDER_API_METADATA_NOT_INVOICE")),
    #("unknown_semantics", json.string("null_is_unknown_not_zero")),
    #("ledger_mutated", json.bool(False)),
    #("inference_dispatched", json.bool(False)),
    #("data", o.data),
  ]
}

pub fn to_json(e: Endpoint, o: Observation) -> json.Json {
  json.object(report_fields(e, o))
}

/// The CLI supplies a local post-fetch host-clock observation. This timestamp
/// does not attest synchronization, provider time, freshness, or billing truth.
pub fn to_json_at(
  e: Endpoint,
  o: Observation,
  observed_at_unix_us: Int,
) -> json.Json {
  json.object(
    list.append(report_fields(e, o), [
      #("observed_at_unix_us", json.int(observed_at_unix_us)),
    ]),
  )
}
