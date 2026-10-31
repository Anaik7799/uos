import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import uos_swarm/openrouter_usage as usage

fn generation() {
  let assert Ok(e) = usage.endpoint(["generation", "gen-abc-123"])
  e
}

fn output(body: String) {
  let e = generation()
  let assert Ok(o) = usage.observe(e, 200, body)
  json.to_string(usage.to_json(e, o))
}

pub fn exact_endpoints_test() {
  let assert Ok(e) = usage.endpoint(["key"])
  usage.path(e) |> should.equal("/api/v1/key")
  let assert Ok(e) = usage.endpoint(["credits"])
  usage.path(e) |> should.equal("/api/v1/credits")
  usage.path(generation()) |> should.equal("/api/v1/generation?id=gen-abc-123")
  let assert Ok(e) = usage.endpoint(["activity", "2024-02-29"])
  usage.path(e) |> should.equal("/api/v1/activity?date=2024-02-29")
}

pub fn invalid_endpoints_refused_before_io_test() {
  list.each(
    [
      [],
      ["https://evil.test"],
      ["generation", "gen-"],
      ["generation", "gen-x?key=x"],
      ["generation", "gen-x\r\nX:x"],
      ["generation", "gen-x/y"],
      ["generation", "gen-x%20"],
      ["generation", "other-x"],
      ["generation", "gen-é"],
      ["generation", "gen-" <> string.repeat("a", 121)],
      ["key", "extra"],
      ["activity", "2023-02-29"],
      ["activity", "2024-13-01"],
      ["activity", "2024-01-00"],
      ["activity", "2024-1-01"],
      ["activity", "0000-01-01"],
    ],
    fn(args) { usage.endpoint(args) |> should.be_error },
  )
}

pub fn injected_io_fixed_path_timeout_test() {
  let assert Ok(e) = usage.endpoint(["key"])
  usage.run(e, fn(path, timeout) {
    path |> should.equal("/api/v1/key")
    timeout |> should.equal(30_000)
    Ok(#(200, "{\"data\":{\"usage\":0}}"))
  })
  |> should.be_ok
}

pub fn transport_errors_not_echoed_test() {
  usage.run(generation(), fn(_, _) { Error("SECRET_OR_PROVIDER_ERROR_BODY") })
  |> should.equal(Error("transport_unavailable"))
}

pub fn missing_and_explicit_zero_differ_test() {
  let missing = output("{\"data\":{\"id\":\"gen-abc-123\"}}")
  let zero = output("{\"data\":{\"id\":\"gen-abc-123\",\"total_cost\":0}}")
  string.contains(missing, "\"total_cost\":null") |> should.be_true
  string.contains(zero, "\"total_cost\":0") |> should.be_true
  { missing == zero } |> should.be_false
}

pub fn null_amount_is_unknown_test() {
  output("{\"data\":{\"id\":\"gen-abc-123\",\"total_cost\":null}}")
  |> string.contains("\"total_cost\":null")
  |> should.be_true
}

pub fn generation_identity_must_match_test() {
  list.each(
    [
      "{\"data\":{}}",
      "{\"data\":{\"id\":\"gen-other\"}}",
      "{\"data\":{\"id\":null}}",
    ],
    fn(body) {
      usage.observe(generation(), 200, body)
      |> should.equal(Error("generation_id_mismatch"))
    },
  )
}

pub fn recursive_duplicates_and_invalid_json_test() {
  list.each(
    [
      "{\"data\":{},\"data\":{}}",
      "{\"data\":{\"id\":\"gen-abc-123\",\"id\":\"gen-abc-123\"}}",
      "{\"data\":{\"id\":\"gen-abc-123\",\"ignored\":{\"x\":1,\"x\":2}}}",
      "{\"data\":{\"id\":\"gen-abc-123\"}} trailing", "[]", "{",
      "{\"data\":{\"id\":\"gen-abc-123\",\"total_cost\":NaN}}",
    ],
    fn(body) {
      usage.observe(generation(), 200, body)
      |> should.equal(Error("invalid_json"))
    },
  )
}

pub fn known_field_types_and_ranges_fail_closed_test() {
  list.each(
    [
      "\"total_cost\":-0.01",
      "\"total_cost\":\"0\"",
      "\"total_cost\":true",
      "\"total_cost\":1e99",
      "\"tokens_prompt\":-1",
      "\"tokens_prompt\":1.5",
      "\"tokens_prompt\":1000000000001",
      "\"cancelled\":0",
      "\"model\":[]",
      "\"model\":\"" <> string.repeat("a", 257) <> "\"",
    ],
    fn(field) {
      usage.observe(
        generation(),
        200,
        "{\"data\":{\"id\":\"gen-abc-123\"," <> field <> "}}",
      )
      |> should.equal(Error("unknown_response_schema"))
    },
  )
}

pub fn unknown_fields_are_not_emitted_test() {
  let text =
    output(
      "{\"secret\":\"ROOT_PRIVATE\",\"data\":{\"id\":\"gen-abc-123\",\"prompt\":\"PROMPT_PRIVATE\",\"api_key\":\"KEY_PRIVATE\",\"provider_name\":\"DeepSeek\",\"native_tokens_reasoning\":2}}",
    )
  list.each(["ROOT_PRIVATE", "PROMPT_PRIVATE", "KEY_PRIVATE"], fn(secret) {
    string.contains(text, secret) |> should.be_false
  })
  string.contains(text, "DeepSeek") |> should.be_true
  string.contains(text, "\"authority\":\"NONE\"") |> should.be_true
  string.contains(text, "\"ledger_mutated\":false") |> should.be_true
}

pub fn http_errors_discard_body_test() {
  list.each([401, 403, 404, 429, 500], fn(code) {
    let e = generation()
    let assert Ok(o) = usage.observe(e, code, "SECRET MALFORMED BODY")
    let rendered = json.to_string(usage.to_json(e, o))
    string.contains(rendered, "SECRET") |> should.be_false
    string.contains(rendered, "HTTP_ERROR") |> should.be_true
    o.http_status |> should.equal(code)
  })
}

pub fn bounds_and_bad_status_test() {
  usage.observe(generation(), 200, string.repeat("x", 262_145))
  |> should.equal(Error("response_bound_or_status"))
  list.each([0, 199, 600], fn(status) {
    usage.observe(generation(), status, "")
    |> should.equal(Error("response_bound_or_status"))
  })
}

pub fn key_and_credits_whitelist_test() {
  let assert Ok(e) = usage.endpoint(["key"])
  let assert Ok(o) =
    usage.observe(
      e,
      200,
      "{\"data\":{\"usage\":1.25,\"usage_daily\":0,\"limit\":null,\"is_management_key\":false,\"label\":\"PRIVATE_LABEL\"}}",
    )
  let text = json.to_string(usage.to_json(e, o))
  string.contains(text, "PRIVATE_LABEL") |> should.be_false
  string.contains(text, "\"limit\":null") |> should.be_true
  let assert Ok(e) = usage.endpoint(["credits"])
  usage.observe(e, 200, "{\"data\":{\"total_credits\":10,\"total_usage\":2}}")
  |> should.be_ok
  usage.observe(e, 200, "{\"data\":{\"total_usage\":-2}}") |> should.be_error
}

pub fn bounded_activity_only_aggregate_fields_test() {
  let assert Ok(e) = usage.endpoint(["activity", "2026-10-31"])
  let row =
    "{\"date\":\"2026-10-31\",\"usage\":0.5,\"requests\":2,\"prompt\":\"PRIVATE_PROMPT\"}"
  let assert Ok(o) = usage.observe(e, 200, "{\"data\":[" <> row <> "]}")
  json.to_string(usage.to_json(e, o))
  |> string.contains("PRIVATE_PROMPT")
  |> should.be_false
  usage.observe(e, 200, "{\"data\":[]}") |> should.be_ok
  usage.observe(
    e,
    200,
    "{\"data\":[" <> string.join(list.repeat(row, 1001), ",") <> "]}",
  )
  |> should.be_error
  usage.observe(e, 200, "{\"data\":{}}") |> should.be_error
}

pub fn effective_budget_separate_from_null_key_limit_test() {
  let assert Ok(e) = usage.endpoint(["key"])
  let assert Ok(o) =
    usage.observe(
      e,
      200,
      "{\"data\":{\"limit\":null,\"effective_budget\":{\"limit_usd\":10,\"remaining_usd\":3.5,\"spend_usd\":6.5,\"reset_interval\":\"daily\",\"resets_at\":\"2026-11-01T00:00:00Z\",\"scope\":\"organization\",\"id\":\"PRIVATE_BUDGET_ID\",\"label\":\"PRIVATE_LABEL\",\"creator\":\"PRIVATE_CREATOR\"},\"budgets\":[{\"limit_usd\":10,\"reset_interval\":\"daily\",\"id\":\"PRIVATE_SECOND_ID\"}]}}",
    )
  let text = json.to_string(usage.to_json(e, o))
  string.contains(text, "\"limit\":null") |> should.be_true
  string.contains(text, "\"effective_budget\":{") |> should.be_true
  string.contains(text, "\"remaining_usd\":3.5") |> should.be_true
  string.contains(text, "\"reset_interval\":\"daily\"") |> should.be_true
  list.each(
    [
      "PRIVATE_BUDGET_ID",
      "PRIVATE_LABEL",
      "PRIVATE_CREATOR",
      "PRIVATE_SECOND_ID",
    ],
    fn(s) { string.contains(text, s) |> should.be_false },
  )
}

pub fn budget_unknown_and_empty_are_distinct_test() {
  let assert Ok(e) = usage.endpoint(["key"])
  list.each(
    ["{\"data\":{}}", "{\"data\":{\"effective_budget\":null,\"budgets\":null}}"],
    fn(body) {
      let assert Ok(o) = usage.observe(e, 200, body)
      let text = json.to_string(usage.to_json(e, o))
      string.contains(text, "\"effective_budget\":null") |> should.be_true
      string.contains(text, "\"budgets\":null") |> should.be_true
    },
  )
  let assert Ok(o) = usage.observe(e, 200, "{\"data\":{\"budgets\":[]}}")
  json.to_string(usage.to_json(e, o))
  |> string.contains("\"budgets\":[]")
  |> should.be_true
}

pub fn malformed_budget_fields_fail_closed_test() {
  let assert Ok(e) = usage.endpoint(["key"])
  list.each(
    [
      "\"effective_budget\":[]",
      "\"effective_budget\":{\"limit_usd\":-1}",
      "\"effective_budget\":{\"remaining_usd\":\"3\"}",
      "\"effective_budget\":{\"spend_usd\":1e99}",
      "\"effective_budget\":{\"scope\":false}",
      "\"effective_budget\":{\"resets_at\":[]}",
      "\"budgets\":{}",
      "\"budgets\":[null]",
      "\"budgets\":[{\"reset_interval\":0}]",
      "\"budgets\":[{\"scope\":\"" <> string.repeat("x", 257) <> "\"}]",
    ],
    fn(field) {
      usage.observe(e, 200, "{\"data\":{" <> field <> "}}")
      |> should.equal(Error("unknown_response_schema"))
    },
  )
  usage.observe(
    e,
    200,
    "{\"data\":{\"effective_budget\":{\"limit_usd\":1,\"limit_usd\":2}}}",
  )
  |> should.equal(Error("invalid_json"))
}

pub fn budget_list_exact_bound_test() {
  let assert Ok(e) = usage.endpoint(["key"])
  let body = fn(n) {
    "{\"data\":{\"budgets\":["
    <> string.join(list.repeat("{}", n), ",")
    <> "]}}"
  }
  usage.observe(e, 200, body(16)) |> should.be_ok
  usage.observe(e, 200, body(17))
  |> should.equal(Error("unknown_response_schema"))
}

pub fn local_timestamp_preserves_top_level_report_fields_test() {
  let e = generation()
  let assert Ok(o) =
    usage.observe(
      e,
      200,
      "{\"data\":{\"id\":\"gen-abc-123\",\"total_cost\":0.1}}",
    )
  let pure = json.to_string(usage.to_json(e, o))
  let observed = json.to_string(usage.to_json_at(e, o, 1_793_470_000_000_123))
  string.contains(pure, "observed_at_unix_us") |> should.be_false
  string.contains(observed, "\"observed_at_unix_us\":1793470000000123")
  |> should.be_true
  list.each(
    [
      "\"status\":\"OBSERVED_PROVIDER_METADATA\"",
      "\"http_status\":200",
      "\"endpoint\":\"/api/v1/generation?id=gen-abc-123\"",
      "\"data\":{",
      "\"authority\":\"NONE\"",
    ],
    fn(field) {
      string.contains(pure, field) |> should.be_true
      string.contains(observed, field) |> should.be_true
    },
  )
}
