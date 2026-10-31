//// Private, read-only provider billing reconciliation. Provider metadata is not
//// an invoice, an admission, or permission to spend. No HTTP is performed here.

import gleam/dict
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/token_monitor_manifest

@external(erlang, "token_monitor_json_ffi", "valid_object")
fn strict_object(text: String) -> Bool

@external(erlang, "token_monitor_json_ffi", "read_receipt")
pub fn read_receipt(path: String) -> Result(#(String, String, String), String)

type Generation {
  Generation(local: String, id: String, path: String)
}

type Unresolved {
  Unresolved(local: String, reason: String)
}

type Manifest {
  Manifest(
    version: Int,
    monitor: String,
    key: String,
    credits: String,
    generations: List(Generation),
    unresolved: List(Unresolved),
  )
}

type Call {
  Call(provider: String, id: String, estimate: Option(Int))
}

type Seen =
  dict.Dict(String, Bool)

fn shape(keys: List(String)) -> decode.Decoder(Nil) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  case
    dict.size(fields) == list.length(keys)
    && list.all(keys, fn(k) { dict.has_key(fields, k) })
  {
    True -> decode.success(Nil)
    False -> decode.failure(Nil, "exact_billing_manifest_fields")
  }
}

fn generation() {
  use _ <- decode.then(
    shape(["local_request_id", "generation_id", "receipt_path"]),
  )
  use local <- decode.field("local_request_id", decode.string)
  use id <- decode.field("generation_id", decode.string)
  use path <- decode.field("receipt_path", decode.string)
  decode.success(Generation(local, id, path))
}

fn unresolved() {
  use _ <- decode.then(shape(["local_request_id", "reason"]))
  use local <- decode.field("local_request_id", decode.string)
  use reason <- decode.field("reason", decode.string)
  decode.success(Unresolved(local, reason))
}

fn manifest() {
  use _ <- decode.then(
    shape([
      "schema_version",
      "monitor_manifest",
      "key_usage_path",
      "credits_path",
      "generations",
      "unresolved_requests",
    ]),
  )
  use v <- decode.field("schema_version", decode.int)
  use m <- decode.field("monitor_manifest", decode.string)
  use k <- decode.field("key_usage_path", decode.string)
  use c <- decode.field("credits_path", decode.string)
  use gs <- decode.field("generations", decode.list(generation()))
  use us <- decode.field("unresolved_requests", decode.list(unresolved()))
  decode.success(Manifest(v, m, k, c, gs, us))
}

fn parse(text: String, decoder: decode.Decoder(a)) -> Result(a, String) {
  case strict_object(text) && string.byte_size(text) <= 65_536 {
    False -> Error("invalid_bounded_receipt_json")
    True ->
      json.parse(text, decoder) |> result.replace_error("invalid_receipt_shape")
  }
}

fn require(ok: Bool, reason: String) -> Result(Nil, String) {
  case ok {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

fn ascii(text: String, alphabet: String, cap: Int) -> Bool {
  string.length(text) > 0
  && string.length(text) <= cap
  && list.all(string.to_graphemes(text), fn(c) { string.contains(alphabet, c) })
}

fn identifier(text: String) -> Bool {
  ascii(
    text,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/",
    256,
  )
}

fn path_ok(path: String) -> Bool {
  string.starts_with(path, "/")
  && string.length(path) <= 4096
  && identifier(path)
  && list.all(string.split(path, "/") |> list.drop(1), fn(p) {
    p != "" && p != "." && p != ".."
  })
}

fn unique(seen: Seen, key: String) -> Result(Seen, String) {
  case dict.has_key(seen, key) {
    True -> Error("duplicate_or_aliased_billing_source")
    False -> Ok(dict.insert(seen, key, True))
  }
}

fn load(
  path: String,
  seen: Seen,
  read: fn(String) -> Result(#(String, String, String), String),
) -> Result(#(String, Seen), String) {
  use _ <- result.try(require(path_ok(path), "noncanonical_receipt_path"))
  use seen <- result.try(unique(seen, "path:" <> path))
  use raw <- result.try(
    read(path) |> result.replace_error("receipt_unavailable"),
  )
  use _ <- result.try(require(
    raw.1 != "" && raw.2 != "",
    "missing_source_identity",
  ))
  use seen <- result.try(unique(seen, "inode:" <> raw.1))
  use seen <- result.try(unique(seen, "digest:" <> raw.2))
  Ok(#(raw.0, seen))
}

fn number() {
  decode.one_of(decode.float, [decode.map(decode.int, int.to_float)])
}

fn amount(field: String) {
  decode.optional_field(field, None, decode.optional(number()), decode.success)
}

// Reporting ceiling, not a provider spending limit. Conversion is nearest
// nanodollar, halfway away from zero, from the provider JSON numeric value.
fn nano(value: Option(Float)) -> Result(Option(Int), String) {
  case value {
    None -> Ok(None)
    Some(n) ->
      case n >=. 0.0 && n <=. 1_000_000.0 {
        True -> Ok(Some(float.round(n *. 1_000_000_000.0)))
        False -> Error("invalid_or_out_of_reporting_range_amount")
      }
  }
}

fn money(value: Option(Int)) -> json.Json {
  case value {
    Some(n) -> json.int(n)
    None -> json.null()
  }
}

fn envelope(text: String, endpoint: String) -> Result(Nil, String) {
  let d = {
    use s <- decode.field("schema", decode.string)
    use status <- decode.field("status", decode.string)
    use code <- decode.field("http_status", decode.int)
    use ep <- decode.field("endpoint", decode.string)
    use auth <- decode.field("authority", decode.string)
    use ledger <- decode.field("ledger_mutated", decode.bool)
    use inference <- decode.field("inference_dispatched", decode.bool)
    decode.success(
      s == "uos-openrouter-usage-v1"
      && status == "OBSERVED_PROVIDER_METADATA"
      && code == 200
      && ep == endpoint
      && auth == "NONE"
      && !ledger
      && !inference,
    )
  }
  use ok <- result.try(parse(text, d))
  require(ok, "unobserved_or_mismatched_provider_receipt")
}

fn provider(text: String) -> String {
  string.lowercase(text)
}

fn calls_decoder() {
  let c = {
    use p <- decode.field("provider", decode.string)
    use id <- decode.field("request_id", decode.string)
    use e <- decode.field("estimated_nanodollars", decode.optional(decode.int))
    decode.success(Call(provider(p), id, e))
  }
  decode.field(
    "report",
    decode.field("calls", decode.list(c), decode.success),
    decode.success,
  )
}

fn selected(calls: List(Call), id: String) -> Result(Nil, String) {
  case list.filter(calls, fn(c) { c.id == id }) {
    [Call("openrouter", _, _)] -> Ok(Nil)
    _ -> Error("unregistered_or_ambiguous_local_request")
  }
}

fn estimates(calls: List(Call), p: String) -> json.Json {
  let rows = list.filter(calls, fn(c) { c.provider == p })
  let totals =
    list.fold(rows, #(0, 0, 0), fn(a, c) {
      case c.estimate {
        Some(n) -> #(a.0 + n, a.1 + 1, a.2)
        None -> #(a.0, a.1, a.2 + 1)
      }
    })
  json.object([
    #("known_subtotal_nanodollars", json.int(totals.0)),
    #("known_calls", json.int(totals.1)),
    #("unknown_calls", json.int(totals.2)),
  ])
}

pub fn report(text: String) -> Result(json.Json, String) {
  report_with(text, read_receipt, token_monitor_manifest.report)
}

/// Injected readers are for deterministic tests; no authentication claim is made
/// about arbitrary input. The native entry point uses existing bounded readers.
pub fn report_with(
  text: String,
  read: fn(String) -> Result(#(String, String, String), String),
  monitor_report: fn(String) -> Result(json.Json, String),
) -> Result(json.Json, String) {
  use m <- result.try(parse(text, manifest()))
  use _ <- result.try(require(
    m.version == 1
      && list.length(m.generations) + list.length(m.unresolved) <= 40,
    "billing_manifest_schema_or_record_limit",
  ))
  use mon <- result.try(load(m.monitor, dict.new(), read))
  use original <- result.try(monitor_report(mon.0))
  let original_text = json.to_string(original)
  use calls <- result.try(parse(original_text, calls_decoder()))
  use _ <- result.try(require(
    list.length(calls) <= 256
      && list.all(calls, fn(c) {
      case c.estimate {
        None -> True
        Some(n) -> n >= 0 && n <= 1_000_000_000_000_000
      }
    }),
    "invalid_monitor_call_estimates",
  ))
  use _ <- result.try(
    list.try_fold(calls, dict.new(), fn(seen, c) {
      unique(seen, "monitor-call:" <> c.provider <> ":" <> c.id)
    }),
  )
  use decision <- result.try(parse(
    original_text,
    decode.field(
      "report",
      decode.field("decision", decode.string, decode.success),
      decode.success,
    ),
  ))
  use key <- result.try(load(m.key, mon.1, read))
  use _ <- result.try(envelope(key.0, "/api/v1/key"))
  let kd = {
    use daily <- decode.field("data", amount("usage_daily"))
    use limit <- decode.field("data", amount("limit"))
    decode.success(#(daily, limit))
  }
  use kr <- result.try(parse(key.0, kd))
  use daily <- result.try(nano(kr.0))
  use limit <- result.try(nano(kr.1))
  use credit <- result.try(load(m.credits, key.1, read))
  use _ <- result.try(envelope(credit.0, "/api/v1/credits"))
  let cd = {
    use total <- decode.field("data", amount("total_credits"))
    use used <- decode.field("data", amount("total_usage"))
    decode.success(#(total, used))
  }
  use cr <- result.try(parse(credit.0, cd))
  use total <- result.try(nano(cr.0))
  use used <- result.try(nano(cr.1))
  use gs <- result.try(
    list.try_fold(m.generations, #(credit.1, [], 0, 0, 0), fn(a, g) {
      use _ <- result.try(require(
        identifier(g.local)
          && ascii(
          g.id,
          "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-",
          124,
        )
          && string.starts_with(g.id, "gen-")
          && string.length(g.id) >= 5,
        "invalid_billing_request_identifier",
      ))
      use _ <- result.try(selected(calls, g.local))
      use seen <- result.try(unique(a.0, "local:" <> g.local))
      use seen <- result.try(unique(seen, "generation:" <> g.id))
      use raw <- result.try(load(g.path, seen, read))
      use _ <- result.try(envelope(raw.0, "/api/v1/generation?id=" <> g.id))
      let gd = {
        use id <- decode.field("id", decode.string)
        use model <- decode.field("model", decode.string)
        use p <- decode.field("provider_name", decode.string)
        use cost <- decode.optional_field(
          "total_cost",
          None,
          decode.optional(number()),
        )
        decode.success(#(id, model, p, cost))
      }
      use data <- result.try(parse(
        raw.0,
        decode.field("data", gd, decode.success),
      ))
      use _ <- result.try(require(
        data.0 == g.id
          && identifier(data.1)
          && ascii(
          data.2,
          "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_. /",
          256,
        ),
        "generation_identity_or_labels_invalid",
      ))
      use cost <- result.try(nano(data.3))
      let row =
        json.object([
          #("local_request_id", json.string(g.local)),
          #("generation_id", json.string(g.id)),
          #("model", json.string(data.1)),
          #("provider", json.string(data.2)),
          #("billed_nanodollars", money(cost)),
        ])
      case cost {
        Some(n) -> Ok(#(raw.1, [row, ..a.1], a.2 + n, a.3 + 1, a.4))
        None -> Ok(#(raw.1, [row, ..a.1], a.2, a.3, a.4 + 1))
      }
    }),
  )
  use us <- result.try(
    list.try_fold(m.unresolved, #(gs.0, []), fn(a, u) {
      use _ <- result.try(require(
        identifier(u.local)
          && string.length(u.reason) > 0
          && string.length(u.reason) <= 512,
        "invalid_unresolved_request",
      ))
      use _ <- result.try(selected(calls, u.local))
      use seen <- result.try(unique(a.0, "local:" <> u.local))
      // Caller-supplied reason is deliberately not echoed.
      Ok(
        #(seen, [
          json.object([
            #("local_request_id", json.string(u.local)),
            #("reason", json.string("generation_id_unavailable_charge_unknown")),
            #("billed_nanodollars", json.null()),
          ]),
          ..a.1
        ]),
      )
    }),
  )
  use _ <- result.try(require(
    list.all(calls, fn(c) {
      c.provider != "openrouter" || dict.has_key(us.0, "local:" <> c.id)
    }),
    "registered_openrouter_call_missing_billing_disposition",
  ))
  let remaining = case total, used {
    Some(t), Some(u) -> Some(t - u)
    _, _ -> None
  }
  Ok(
    json.object([
      #("schema", json.string("uos-private-billing-reconciliation-v1")),
      #("privacy", json.string("PRIVATE_ACCOUNT_METADATA_DO_NOT_PUBLISH")),
      #("authority", json.string("NONE")),
      #("decision", json.string(decision)),
      #("token_report", original),
      #("cost_basis", json.string("PROVIDER_API_METADATA_NOT_INVOICE")),
      #(
        "rounding",
        json.string("nearest_nanodollar_half_away_from_zero_from_JSON_number"),
      ),
      #(
        "openrouter_billed",
        json.object([
          #("known_subtotal_nanodollars", json.int(gs.2)),
          #("known_calls", json.int(gs.3)),
          #("unknown_calls", json.int(gs.4 + list.length(m.unresolved))),
          #("coverage_complete", json.bool(False)),
          #("generations", json.array(list.reverse(gs.1), fn(x) { x })),
          #("unresolved", json.array(list.reverse(us.1), fn(x) { x })),
        ]),
      ),
      #("openrouter_sdk_estimates", estimates(calls, "openrouter")),
      #("native_claude_estimates", estimates(calls, "claude")),
      #(
        "key_wide_separate_do_not_add",
        json.object([
          #("daily_usage_nanodollars", money(daily)),
          #("limit_nanodollars", money(limit)),
          #(
            "null_limit_semantics",
            json.string("unknown_or_unspecified_not_spend_authority"),
          ),
        ]),
      ),
      #(
        "account_separate_do_not_add",
        json.object([
          #("total_credits_nanodollars", money(total)),
          #("total_usage_nanodollars", money(used)),
          #("remaining_nanodollars", money(remaining)),
        ]),
      ),
      #("ledger_mutated", json.bool(False)),
      #("inference_dispatched", json.bool(False)),
      #("refunds_authorized", json.bool(False)),
      #("api_tokens_added", json.bool(False)),
    ]),
  )
}
