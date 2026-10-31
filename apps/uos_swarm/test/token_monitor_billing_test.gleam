import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import uos_swarm/token_monitor_billing as billing

fn receipt(endpoint: String, data: json.Json) -> String {
  json.object([
    #("schema", json.string("uos-openrouter-usage-v1")),
    #("status", json.string("OBSERVED_PROVIDER_METADATA")),
    #("http_status", json.int(200)),
    #("endpoint", json.string(endpoint)),
    #("authority", json.string("NONE")),
    #("ledger_mutated", json.bool(False)),
    #("inference_dispatched", json.bool(False)),
    #("data", data),
  ])
  |> json.to_string
}

fn generation(id: String, cost: List(#(String, json.Json))) -> String {
  receipt(
    "/api/v1/generation?id=" <> id,
    json.object([
      #("id", json.string(id)),
      #("model", json.string("deepseek/model")),
      #("provider_name", json.string("Provider One")),
      ..cost
    ]),
  )
}

fn row(local: String, id: String, path: String) -> json.Json {
  json.object([
    #("local_request_id", json.string(local)),
    #("generation_id", json.string(id)),
    #("receipt_path", json.string(path)),
  ])
}

fn unresolved(local: String) -> json.Json {
  json.object([
    #("local_request_id", json.string(local)),
    #("reason", json.string("PRIVATE_ERROR_BODY_MUST_NOT_ESCAPE")),
  ])
}

fn manifest(rows: List(json.Json), unknown: List(json.Json)) -> String {
  json.object([
    #("schema_version", json.int(1)),
    #("monitor_manifest", json.string("/private/monitor")),
    #("key_usage_path", json.string("/private/key")),
    #("credits_path", json.string("/private/credits")),
    #("generations", json.array(rows, fn(x) { x })),
    #("unresolved_requests", json.array(unknown, fn(x) { x })),
  ])
  |> json.to_string
}

fn standard_manifest() {
  manifest([row("local-one", "gen-one", "/private/one")], [
    unresolved("local-error"),
  ])
}

fn call(provider: String, id: String, estimate: json.Json) -> json.Json {
  json.object([
    #("provider", json.string(provider)),
    #("request_id", json.string(id)),
    #("estimated_nanodollars", estimate),
  ])
}

fn original(calls: List(json.Json)) -> json.Json {
  json.object([
    #("scope", json.string("unchanged_original_marker")),
    #(
      "report",
      json.object([
        #("decision", json.string("HOLD_UNKNOWN_USAGE")),
        #("calls", json.array(calls, fn(x) { x })),
        #("known_total_tokens", json.int(12_345)),
      ]),
    ),
  ])
}

fn monitor(_: String) -> Result(json.Json, String) {
  Ok(
    original([
      call("openrouter", "local-one", json.int(40)),
      call("openrouter", "local-error", json.null()),
      call("claude", "native-known", json.int(100)),
      call("claude", "native-unknown", json.null()),
    ]),
  )
}

fn read(path: String) -> Result(#(String, String, String), String) {
  let body = case path {
    "/private/monitor" -> "{}"
    "/private/key" ->
      receipt(
        "/api/v1/key",
        json.object([#("usage_daily", json.float(6.5)), #("limit", json.null())]),
      )
    "/private/credits" ->
      receipt(
        "/api/v1/credits",
        json.object([
          #("total_credits", json.int(100)),
          #("total_usage", json.int(90)),
        ]),
      )
    "/private/one" ->
      generation("gen-one", [#("total_cost", json.float(0.0123456786))])
    "/private/two" -> generation("gen-two", [#("total_cost", json.int(0))])
    _ -> "{}"
  }
  Ok(#(body, "inode:" <> path, "digest:" <> path))
}

fn output(text: String) {
  let assert Ok(out) = billing.report_with(text, read, monitor)
  out |> json.to_string
}

fn int_at(text: String, path: List(String)) {
  let assert Ok(n) = json.parse(text, decode.at(path, decode.int))
  n
}

pub fn actual_charge_rounding_and_scope_test() {
  let out = output(standard_manifest())
  int_at(out, ["openrouter_billed", "known_subtotal_nanodollars"])
  |> should.equal(12_345_679)
  int_at(out, ["openrouter_billed", "known_calls"]) |> should.equal(1)
  int_at(out, ["openrouter_billed", "unknown_calls"]) |> should.equal(1)
  int_at(out, ["openrouter_sdk_estimates", "known_subtotal_nanodollars"])
  |> should.equal(40)
  int_at(out, ["native_claude_estimates", "known_subtotal_nanodollars"])
  |> should.equal(100)
  int_at(out, ["native_claude_estimates", "unknown_calls"]) |> should.equal(1)
  int_at(out, ["key_wide_separate_do_not_add", "daily_usage_nanodollars"])
  |> should.equal(6_500_000_000)
  int_at(out, ["account_separate_do_not_add", "remaining_nanodollars"])
  |> should.equal(10_000_000_000)
}

pub fn original_report_and_decision_preserved_test() {
  let out = output(standard_manifest())
  let assert Ok(expected) = monitor("")
  let assert Ok(actual) =
    json.parse(
      out,
      decode.field("token_report", decode.dynamic, decode.success),
    )
  let assert Ok(decoded_expected) =
    json.parse(json.to_string(expected), decode.dynamic)
  actual |> should.equal(decoded_expected)
  string.contains(out, "HOLD_UNKNOWN_USAGE") |> should.be_true
  int_at(out, ["token_report", "report", "known_total_tokens"])
  |> should.equal(12_345)
}

pub fn private_paths_and_error_bodies_not_echoed_test() {
  let out = output(standard_manifest())
  list.each(["/private/", "PRIVATE_ERROR_BODY", "inode:", "digest:"], fn(s) {
    string.contains(out, s) |> should.be_false
  })
}

pub fn known_zero_not_unknown_test() {
  let assert Ok(report) =
    billing.report_with(
      manifest([row("local-two", "gen-two", "/private/two")], []),
      read,
      fn(_) { Ok(original([call("openrouter", "local-two", json.int(23))])) },
    )
  let out = json.to_string(report)
  int_at(out, ["openrouter_billed", "known_subtotal_nanodollars"])
  |> should.equal(0)
  int_at(out, ["openrouter_billed", "known_calls"]) |> should.equal(1)
  int_at(out, ["openrouter_billed", "unknown_calls"]) |> should.equal(0)
}

pub fn missing_and_null_cost_remain_unknown_test() {
  list.each([[], [#("total_cost", json.null())]], fn(fields) {
    let reader = fn(path) {
      case path {
        "/private/one" -> Ok(#(generation("gen-one", fields), "one", "one"))
        _ -> read(path)
      }
    }
    let assert Ok(out) =
      billing.report_with(standard_manifest(), reader, monitor)
    let text = json.to_string(out)
    int_at(text, ["openrouter_billed", "known_calls"]) |> should.equal(0)
    int_at(text, ["openrouter_billed", "unknown_calls"]) |> should.equal(2)
  })
}

pub fn negative_and_excessive_cost_refused_test() {
  list.each(
    [json.float(-0.01), json.float(1_000_000.01), json.string("0.01")],
    fn(cost) {
      billing.report_with(
        standard_manifest(),
        fn(path) {
          case path {
            "/private/one" ->
              Ok(#(generation("gen-one", [#("total_cost", cost)]), "one", "one"))
            _ -> read(path)
          }
        },
        monitor,
      )
      |> should.be_error
    },
  )
}

pub fn id_and_endpoint_binding_refused_test() {
  let good = generation("gen-one", [#("total_cost", json.int(1))])
  list.each(
    [
      string.replace(good, "\"id\":\"gen-one\"", "\"id\":\"gen-other\""),
      string.replace(good, "generation?id=gen-one", "generation?id=gen-other"),
    ],
    fn(body) {
      billing.report_with(
        standard_manifest(),
        fn(path) {
          case path {
            "/private/one" -> Ok(#(body, "one", "one"))
            _ -> read(path)
          }
        },
        monitor,
      )
      |> should.be_error
    },
  )
}

pub fn duplicate_local_generation_path_and_unresolved_refused_test() {
  let first = row("local-one", "gen-one", "/private/one")
  list.each(
    [
      manifest([first, first], []),
      manifest([first, row("local-one", "gen-two", "/private/two")], []),
      manifest([first, row("local-two", "gen-one", "/private/two")], []),
      manifest([first, row("local-two", "gen-two", "/private/one")], []),
      manifest([first], [unresolved("local-one")]),
      manifest([], [unresolved("local-error"), unresolved("local-error")]),
    ],
    fn(text) {
      billing.report_with(text, read, fn(_) {
        Ok(
          original([
            call("openrouter", "local-one", json.int(1)),
            call("openrouter", "local-two", json.int(2)),
            call("openrouter", "local-error", json.null()),
          ]),
        )
      })
      |> should.equal(Error("duplicate_or_aliased_billing_source"))
    },
  )
}

pub fn inode_and_digest_aliases_refused_test() {
  list.each([True, False], fn(alias_inode) {
    billing.report_with(
      standard_manifest(),
      fn(path) {
        let assert Ok(raw) = read(path)
        case path {
          "/private/credits" ->
            case alias_inode {
              True -> Ok(#(raw.0, "inode:/private/key", raw.2))
              False -> Ok(#(raw.0, raw.1, "digest:/private/key"))
            }
          _ -> Ok(raw)
        }
      },
      monitor,
    )
    |> should.be_error
  })
}

pub fn unregistered_and_provider_alias_ambiguity_refused_test() {
  billing.report_with(
    manifest([row("absent", "gen-one", "/private/one")], []),
    read,
    monitor,
  )
  |> should.be_error
  billing.report_with(standard_manifest(), read, fn(_) {
    Ok(
      original([
        call("openrouter", "local-one", json.int(1)),
        call("OpenRouter", "local-one", json.int(1)),
        call("openrouter", "local-error", json.null()),
      ]),
    )
  })
  |> should.be_error
}

pub fn malformed_duplicate_keys_and_http_error_refused_test() {
  list.each(
    [
      "{\"data\":{},\"data\":{}}",
      "{} trailing",
      "[]",
      "{",
      string.replace(
        generation("gen-one", []),
        "\"http_status\":200",
        "\"http_status\":403",
      ),
      string.replace(
        generation("gen-one", []),
        "OBSERVED_PROVIDER_METADATA",
        "HTTP_ERROR",
      ),
      string.replace(
        generation("gen-one", []),
        "\"inference_dispatched\":false",
        "\"inference_dispatched\":true",
      ),
    ],
    fn(body) {
      billing.report_with(
        standard_manifest(),
        fn(path) {
          case path {
            "/private/one" -> Ok(#(body, "one", "one"))
            _ -> read(path)
          }
        },
        monitor,
      )
      |> should.be_error
    },
  )
}

pub fn unavailable_receipt_refuses_without_body_test() {
  billing.report_with(standard_manifest(), fn(_) { Error("SECRET") }, monitor)
  |> should.equal(Error("receipt_unavailable"))
}

pub fn noncanonical_paths_and_record_bounds_refused_test() {
  list.each(
    [
      "relative",
      "/private/../one",
      "/private//one",
      "/private/./one",
      "/private/one/",
    ],
    fn(path) {
      billing.report_with(
        manifest([row("local-one", "gen-one", path)], []),
        read,
        monitor,
      )
      |> should.equal(Error("noncanonical_receipt_path"))
    },
  )
  billing.report_with(
    manifest([], list.repeat(unresolved("local-error"), 41)),
    read,
    monitor,
  )
  |> should.equal(Error("billing_manifest_schema_or_record_limit"))
}

pub fn malformed_labels_refused_without_echo_test() {
  let body =
    generation("gen-one", [])
    |> string.replace("Provider One", "SECRET\\nPAYLOAD")
  billing.report_with(
    standard_manifest(),
    fn(path) {
      case path {
        "/private/one" -> Ok(#(body, "one", "one"))
        _ -> read(path)
      }
    },
    monitor,
  )
  |> should.equal(Error("generation_identity_or_labels_invalid"))
}

pub fn missing_disposition_cannot_hide_registered_call_test() {
  billing.report_with(
    manifest([row("local-one", "gen-one", "/private/one")], []),
    read,
    monitor,
  )
  |> should.equal(Error(
    "registered_openrouter_call_missing_billing_disposition",
  ))
}

pub fn unknown_manifest_fields_and_versions_refused_test() {
  list.each(
    [
      string.replace(
        standard_manifest(),
        "\"schema_version\":1",
        "\"schema_version\":2",
      ),
      string.replace(
        standard_manifest(),
        "\"schema_version\":1",
        "\"extra\":true,\"schema_version\":1",
      ),
      string.replace(
        standard_manifest(),
        "\"generation_id\":",
        "\"extra\":true,\"generation_id\":",
      ),
      string.replace(
        standard_manifest(),
        "\"reason\":",
        "\"extra\":true,\"reason\":",
      ),
      string.replace(
        standard_manifest(),
        "\"schema_version\":1",
        "\"schema_version\":1,\"schema_version\":1",
      ),
    ],
    fn(text) { billing.report_with(text, read, monitor) |> should.be_error },
  )
}

pub fn forty_distinct_registered_generations_accepted_test() {
  let ids =
    int.range(from: 1, to: 41, with: [], run: fn(a, n) {
      [int.to_string(n), ..a]
    })
  let text =
    manifest(
      list.map(ids, fn(id) {
        row("local-" <> id, "gen-" <> id, "/private/" <> id)
      }),
      [],
    )
  let assert Ok(report) =
    billing.report_with(
      text,
      fn(path) {
        case path {
          "/private/monitor" | "/private/key" | "/private/credits" -> read(path)
          _ ->
            Ok(#(
              generation(string.replace(path, "/private/", "gen-"), [
                #("total_cost", json.float(0.0000000005)),
              ]),
              path,
              path,
            ))
        }
      },
      fn(_) {
        Ok(
          original(
            list.map(ids, fn(id) {
              call("openrouter", "local-" <> id, json.int(0))
            }),
          ),
        )
      },
    )
  let out = json.to_string(report)
  int_at(out, ["openrouter_billed", "known_calls"]) |> should.equal(40)
  int_at(out, ["openrouter_billed", "known_subtotal_nanodollars"])
  |> should.equal(40)
  int_at(out, ["openrouter_billed", "unknown_calls"]) |> should.equal(0)
}

pub fn record_limit_checked_before_any_reader_test() {
  billing.report_with(
    manifest([], list.repeat(unresolved("local-error"), 41)),
    fn(_) { panic as "oversized_manifest_must_not_read" },
    monitor,
  )
  |> should.equal(Error("billing_manifest_schema_or_record_limit"))
}
