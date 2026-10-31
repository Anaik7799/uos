//// Wave2 market reference-vector conformance; bounded behavior tests, not SDK certification.

import cepaf_gleam/harness/value
import cepaf_gleam/mcp/http_auth as auth
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/tools
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/wire
import gleam/bit_array
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

const root = "/home/an/NAS-setup/uos"

fn rpc(raw: String) {
  gateway.handle_standard_mcp_line(
    "codex",
    "codex-market",
    root,
    "wave2-market",
    "public",
    raw,
    1000,
  )
}

fn error_code(raw: String, expected: Int) {
  let assert Some(reply) = rpc(raw)
  json.parse(reply, decode.at(["error", "code"], decode.int))
  |> should.equal(Ok(expected))
}

pub fn go_sdk_null_parameterless_params_and_zero_argument_call_test() {
  list.each(["tools/list", "ping", "resources/list", "prompts/list"], fn(method) {
    let assert Some(reply) = rpc("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"" <> method <> "\",\"params\":null}")
    let assert Ok(value.Object(fields)) = json.parse(reply, value.decoder())
    list.any(fields, fn(pair) { pair.0 == "result" }) |> should.be_true
  })
  let assert Some(reply) = rpc("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"integrity_check\",\"arguments\":null}}")
  json.parse(reply, decode.at(["result", "isError"], decode.bool)) |> should.equal(Ok(False))
}

pub fn null_required_params_and_primitive_or_array_bindings_remain_invalid_test() {
  list.each([
    "\"method\":\"tools/call\",\"params\":null",
    "\"method\":\"resources/read\",\"params\":null",
    "\"method\":\"ping\",\"params\":123",
    "\"method\":\"ping\",\"params\":[]",
    "\"method\":\"tools/call\",\"params\":{\"name\":\"integrity_check\",\"arguments\":\"bad\"}",
    "\"method\":\"tools/call\",\"params\":{\"name\":\"integrity_check\",\"arguments\":[]}",
  ], fn(fields) { error_code("{\"jsonrpc\":\"2.0\",\"id\":3," <> fields <> "}", -32_602) })
}

pub fn suite2_unknown_notifications_are_silent_test() {
  list.each(
    [
      "notifications/initialized",
      "notifications/cancelled",
      "notifications/roots/list_changed",
      "notifications/progress",
      "notifications/unknown_future_event",
      "$/cancelRequest",
    ],
    fn(method) {
      rpc("{\"jsonrpc\":\"2.0\",\"method\":\"" <> method <> "\"}")
      |> should.equal(None)
    },
  )
}

pub fn suite2_explicit_null_id_receives_response_test() {
  let assert Some(reply) =
    rpc("{\"jsonrpc\":\"2.0\",\"id\":null,\"method\":\"unknown_method\"}")
  json.parse(reply, decode.at(["id"], value.decoder()))
  |> should.equal(Ok(value.Null))
  json.parse(reply, decode.at(["error", "code"], decode.int))
  |> should.equal(Ok(-32_601))
}

pub fn suite2_invalid_id_types_are_invalid_request_test() {
  list.each(["true", "1.5", "{}", "[]"], fn(id) {
    let assert Some(reply) =
      rpc("{\"jsonrpc\":\"2.0\",\"id\":" <> id <> ",\"method\":\"ping\"}")
    json.parse(reply, decode.at(["id"], value.decoder()))
    |> should.equal(Ok(value.Null))
    json.parse(reply, decode.at(["error", "code"], decode.int))
    |> should.equal(Ok(-32_600))
  })
}

pub fn suite2_empty_and_mixed_batches_test() {
  error_code("[]", -32_600)
  rpc("[{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}]")
  |> should.equal(None)
  let assert Some(reply) =
    rpc(
      "[{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"ping\"},{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"},{\"jsonrpc\":\"2.0\",\"id\":\"list\",\"method\":\"tools/list\"}]",
    )
  let assert Ok(value.Array(items)) = json.parse(reply, value.decoder())
  list.map(items, fn(item) { value.get(item, "id") })
  |> should.equal([Ok(value.Integer(11)), Ok(value.Text("list"))])
}

pub fn suite2_exact_parse_and_method_and_params_taxonomy_test() {
  error_code("{broken", -32_700)
  error_code("17", -32_600)
  error_code("{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"ping\"}", -32_600)
  error_code(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"future/method\"}",
    -32_601,
  )
  error_code(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"resources/read\",\"params\":{}}",
    -32_602,
  )
}

// Suite 1: vectors drawn from JSONTestSuite/OTP grammar categories. I-JSON
// duplicate/NUL restrictions are explicit local policy extensions.
@external(erlang, "mcp_stdio_ffi", "mcp_json_strict_inspect")
fn inspect(raw: BitArray, depth: Int) -> Result(value.Value, dynamic.Dynamic)

@external(erlang, "mcp_stdio_ffi", "mcp_json_stream_decode")
fn stream(
  chunks: List(BitArray),
  depth: Int,
) -> Result(value.Value, dynamic.Dynamic)

@external(erlang, "mcp_stdio_ffi", "mcp_json_encode_checked")
fn encode_checked(
  fields: List(#(String, value.Value)),
) -> Result(String, String)

pub fn suite1_accepts_rfc8259_vectors_and_exact_depth_32_test() {
  let vectors = [
    "{}",
    "[]",
    "null",
    "true",
    "false",
    "0",
    "-0",
    "1",
    "-1",
    "1.5",
    "1e2",
    "1E+2",
    "1E-2",
    "9007199254740991",
    "-9007199254740991",
    "\"astral 😀\"",
    "\"\\uD83D\\uDE00\"",
    "\"\\/\"",
    "\"\\\"\"",
    "\"\\b\\f\\n\\r\\t\"",
    "{\"a\":[1,true,null,{\"b\":\"λ\"}]}",
    "{\"method\":\"ping\",\"Method\":\"tools/list\",\"future_field\":{\"x\":1}}",
    " \r\n\t {\"a\":1} \r\n\t ",
    string.repeat("[", 32) <> "0" <> string.repeat("]", 32),
  ]
  list.each(vectors, fn(raw) {
    inspect(bit_array.from_string(raw), 32) |> should.be_ok()
  })
}

pub fn suite1_rejects_syntax_unicode_nul_duplicates_and_depth_33_test() {
  let vectors = [
    "\"\\uD800\"",
    "\"\\uDEAD\"",
    "\"\\uDEAD\\uD800\"",
    "\"tab\tinside\"",
    "\"line\ninside\"",
    "{\"a\":1,}",
    "[1,]",
    "01",
    "+1",
    "NaN",
    "Infinity",
    "-Infinity",
    "1e9999",
    "{\"jsonrpc\":\"2.0\"} trailing",
    "[{\"jsonrpc\":\"2.0\"",
    "",
    " ",
    "[",
    "{",
    "\"unterminated",
    "\"\\x00\"",
    "[true false]",
    "{a:1}",
    "{'a':1}",
    "{\"a\":undefined}",
    "{\"a\":\"\\u0000\"}",
    "{\"\\u0000\":1}",
    "{\"a\":\"\u{0000}\"}",
    "{\"a\":1,\"a\":2}",
    "{\"x\":{\"a\":1,\"a\":2}}",
    "{\"method\":\"ping\",\"me\\u0074hod\":\"tools/list\"}",
    string.repeat("{\"a\":", 32) <> "{}" <> string.repeat("}", 32),
    string.repeat("[", 33) <> "0" <> string.repeat("]", 33),
  ]
  list.each(vectors, fn(raw) {
    inspect(bit_array.from_string(raw), 32) |> should.be_error()
  })
  list.each([<<192, 175>>, <<255>>, <<237, 160, 128>>, <<34, 0, 34>>], fn(raw) {
    inspect(raw, 32) |> should.be_error()
  })
}

pub fn suite1_duplicate_keys_map_to_invalid_request_test() {
  list.each(
    [
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"method\":\"tools/list\"}",
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"path\":\"AGENTS.md\",\"path\":\"CLAUDE.md\"}}}",
    ],
    fn(raw) {
      error_code(raw, -32_600)
      let assert Some(reply) = rpc(raw)
      string.contains(reply, "DUPLICATE_JSON_KEY") |> should.be_true()
    },
  )
}

pub fn suite5_checked_outbound_encoder_rejects_duplicate_members_test() {
  encode_checked([#("id", value.Integer(1)), #("id", value.Integer(2))])
  |> should.be_error()
  encode_checked([#("id", value.Integer(1)), #("result", value.Object([]))])
  |> should.be_ok()
  encode_checked([
    #(
      "result",
      value.Object([#("a", value.Integer(1)), #("a", value.Integer(2))]),
    ),
  ])
  |> should.be_error()
}

fn chunks(raw: BitArray, size: Int) -> List(BitArray) {
  case raw {
    <<>> -> []
    <<part:size(size)-bytes, rest:bytes>> -> [part, ..chunks(rest, size)]
    _ -> [raw]
  }
}

pub fn suite5_native_streaming_matches_single_buffer_at_every_chunk_size_test() {
  list.each(
    [
      "{\"jsonrpc\":\"2.0\",\"id\":\"λ😀\",\"method\":\"ping\",\"params\":{\"nested\":[1,true,false,null]}}",
      "{\"a\":\"\\uD83D\\uDE00\"}",
      "{\"a\":1,\"a\":2}",
      "{\"a\":{\"x\":1,\"x\":2}}",
      "{\"a\":\"\\u0000\"}",
      "{\"a\":1} garbage",
      "{\"a\":\"\\uD800\"}",
      "[1,2",
      "1e9999",
      "9007199254740991",
      string.repeat("[", 33) <> "0" <> string.repeat("]", 33),
    ],
    fn(raw) {
      let bytes = bit_array.from_string(raw)
      let single = inspect(bytes, 32)
      list.each([1, 7, 64], fn(size) {
        stream(chunks(bytes, size), 32) |> should.equal(single)
      })
    },
  )
}

fn schema_text(schema: value.Value, key: String, fallback: String) -> String {
  case value.get(schema, key) {
    Ok(value.Text(s)) -> s
    _ -> fallback
  }
}

fn schema_sample(key: String, schema: value.Value) -> json.Json {
  case value.get(schema, "enum") {
    Ok(value.Array([choice, ..])) -> value.encode(choice)
    _ ->
      case schema_text(schema, "type", "string") {
        "object" -> schema_arguments(schema)
        "array" -> {
          let item = case value.get(schema, "items") {
            Ok(s) -> s
            _ -> value.Object([])
          }
          json.preprocessed_array(case key {
            "telemetry" -> [json.float(1.0), json.float(0.8), json.float(0.5)]
            "rules" -> [
              json.object([
                #("id", json.string("r0")),
                #("name", json.string("safe")),
                #("layer", json.string("L0")),
                #("layer_rank", json.int(0)),
                #("action", json.string("hold")),
              ]),
            ]
            "agents" -> [
              json.string("codex"),
              json.string("agy"),
              json.string("claude"),
            ]
            _ -> [schema_sample("item", item)]
          })
        }
        "boolean" -> json.bool(True)
        "integer" ->
          json.int(case key {
            "offset" -> 0
            _ -> 1
          })
        "number" ->
          json.float(case key {
            "benefit" -> 2.0
            "fundamental_hz" -> 432.0
            _ -> 1.0
          })
        _ ->
          json.string(case key {
            "path" -> "AGENTS.md"
            "plan" | "plan_id" ->
              "20261030-2325-mcp-resilience-perf-scale-bdd-fractal"
            "id" | "task_id" -> "R01"
            "actor" | "worker" -> "codex"
            "code" -> "let x = 1"
            "language" -> "gleam"
            "action" -> "inspect"
            "criticality" | "impact" -> "3"
            "dependency_readiness" -> "ready"
            "query" -> "supervision"
            "raga" -> "Durga"
            "extension" -> "ggram"
            "preset" -> "swarm"
            "layer" -> "L4_System"
            "source_branch" -> "feature/wave2"
            "target_branch" -> "integration/wave2"
            "args" | "input" -> "{}"
            "catalog_sha256" | "ledger_sha256" -> "any"
            "offset" -> "0"
            "intent" -> "status"
            _ -> "wave2"
          })
      }
  }
}

fn schema_arguments(schema: value.Value) -> json.Json {
  case value.get(schema, "properties") {
    Ok(value.Object(fields)) ->
      json.object(
        list.map(fields, fn(field) {
          #(field.0, schema_sample(field.0, field.1))
        }),
      )
    _ -> json.object([])
  }
}

pub fn suite4_all_53_advertised_schemas_have_no_adapter_key_mismatch_test_() {
  #(atom.create("timeout"), 30, all_53_schema_parity)
}

fn all_53_schema_parity() {
  let definitions = tools.operational_tool_definitions()
  list.length(definitions) |> should.equal(53)
  let results =
    list.map(definitions, fn(definition) {
      let assert Ok(schema) =
        json.parse(json.to_string(definition.input_schema), value.decoder())
      let raw =
        json.object([
          #("jsonrpc", json.string("2.0")),
          #("id", json.int(53)),
          #("method", json.string("tools/call")),
          #(
            "params",
            json.object([
              #("name", json.string(definition.name)),
              #("arguments", case definition.name {
                "plan_get" -> json.object([#("id", json.string("T01"))])
                _ -> schema_arguments(schema)
              }),
            ]),
          ),
        ])
        |> json.to_string
      let assert Some(reply) = rpc(raw)
      #(definition.name, reply, raw)
    })
  let report =
    json.array(results, fn(item) {
      json.object([
        #("tool", json.string(item.0)),
        #("response", json.string(item.1)),
        #("request", json.string(item.2)),
      ])
    })
    |> json.to_string
  let assert Ok(_) = write_market_report(report)
  list.each(results, fn(item) {
    case item.0 {
      "plan_add"
      | "plan_update"
      | "sa_task_claim"
      | "sa_task_complete"
      | "sa_job_enqueue"
      | "sa_workflow_start" ->
        string.contains(item.1, "ROUTE_GRANT_REQUIRED") |> should.be_true()
      "kms_catalog" ->
        string.contains(item.1, "OBSERVATION_PROBE_MISSING") |> should.be_true()
      _ -> Nil
    }
    list.each(
      [
        "INVALID_ANALYSIS_INPUT",
        "MISSING_ARGUMENT",
        "UNKNOWN_TASK_ID",
        "MISSING_TASK_ID",
        "MISSING_JOB_ID",
        "MISSING_WORKFLOW_ID",
        "PROVER_UNRUN_MISSING_TOOL",
      ],
      fn(code) {
        case json.parse(item.1, decode.at(["result", "isError"], decode.bool)) {
          Ok(False) -> Nil
          _ -> string.contains(item.1, code) |> should.equal(False)
        }
      },
    )
  })
}

pub fn suite4_code_security_traps_fail_closed_test() {
  list.each(
    [
      "let x = \"25503L801736\"",
      "SELECT * FROM users; DROP TABLE events",
      "abc\u{0000}def",
    ],
    fn(code) {
      let raw =
        json.object([
          #("jsonrpc", json.string("2.0")),
          #("id", json.int(40)),
          #("method", json.string("tools/call")),
          #(
            "params",
            json.object([
              #("name", json.string("ast_anomaly_detect")),
              #("arguments", json.object([#("code", json.string(code))])),
            ]),
          ),
        ])
        |> json.to_string
      let assert Some(reply) = rpc(raw)
      {
        string.contains(reply, "INVALID_ANALYSIS_INPUT")
        || string.contains(reply, "NUL_BYTE_FORBIDDEN")
      }
      |> should.be_true()
    },
  )
}

pub fn suite2_json_object_tool_result_includes_structured_content_test() {
  let assert Some(reply) =
    rpc(
      "{\"jsonrpc\":\"2.0\",\"id\":22,\"method\":\"tools/call\",\"params\":{\"name\":\"mcp_capability_inventory\",\"arguments\":{}}}",
    )
  json.parse(reply, decode.at(["result", "isError"], decode.bool))
  |> should.equal(Ok(False))
  let assert Ok(value.Object(_)) =
    json.parse(
      reply,
      decode.at(["result", "structuredContent"], value.decoder()),
    )
  let assert Ok(value.Array([_, ..])) =
    json.parse(reply, decode.at(["result", "content"], value.decoder()))
  let assert Ok(value.Object(_)) =
    json.parse(reply, decode.at(["result", "_meta"], value.decoder()))
}

@external(erlang, "mcp_market_fixture", "write_schema_report")
fn write_market_report(report: String) -> Result(Nil, String)

@external(erlang, "mcp_market_fixture", "fault_survival")
fn fault_survival() -> Result(Nil, String)

pub fn suite3_real_stdio_subprocess_survives_hostile_frames_test() {
  fault_survival() |> should.equal(Ok(Nil))
}

@external(erlang, "mcp_market_fixture", "heap_benchmark")
fn heap_benchmark() -> Result(#(Int, Int), String)

pub fn suite5_native_heap_words_are_at_least_five_times_lower_test() {
  let assert Ok(#(legacy, native)) = heap_benchmark()
  { legacy >= 5 * native } |> should.be_true()
}

fn http_config() {
  auth.AuthConfig(
    ["https://nas-1.tail55d152.ts.net"],
    "issuer",
    "uos-mcp",
    "mcp",
    "market-test-signing-key",
  )
}

fn http_headers() {
  let token =
    auth.sign_token(
      auth.TokenClaims(
        "issuer",
        "uos-mcp",
        "codex",
        "codex-market",
        root,
        "market-http",
        ["mcp"],
        100,
        60_000,
      ),
      http_config().signing_secret,
    )
  [
    #("Origin", "https://nas-1.tail55d152.ts.net"),
    #("Authorization", "Bearer " <> token),
    #("Content-Type", "application/json"),
    #("Accept", "application/json"),
    #("Mcp-Protocol-Version", "2026-07-28"),
    #("Mcp-Session-Id", "market-http"),
  ]
}

fn http_run(
  method: String,
  path: String,
  headers: List(#(String, String)),
  body: String,
) {
  gateway.handle_http_with_config(
    method,
    path,
    headers,
    body,
    http_config(),
    1000,
  )
}

fn header_replace(
  headers: List(#(String, String)),
  key: String,
  value: String,
) {
  list.map(headers, fn(h) {
    case h.0 == key {
      True -> #(key, value)
      False -> h
    }
  })
}

pub fn suite2_streamable_http_preflight_delete_and_origin_security_test() {
  list.each(["/mcp", "/.well-known/oauth-protected-resource"], fn(path) {
    let #(status, headers, body) =
      http_run(
        "OPTIONS",
        path,
        [#("Origin", "https://nas-1.tail55d152.ts.net")],
        "",
      )
    status |> should.equal(204)
    body |> should.equal("")
    let assert Ok(methods) =
      auth.header(headers, "access-control-allow-methods")
    string.contains(methods, "DELETE") |> should.be_true()
    string.contains(methods, "OPTIONS") |> should.be_true()
    auth.header(headers, "access-control-max-age") |> should.equal(Ok("86400"))
    auth.header(headers, "x-content-type-options")
    |> should.equal(Ok("nosniff"))
  })
  let #(deleted, _, _) = http_run("DELETE", "/mcp", http_headers(), "")
  deleted |> should.equal(204)
  let #(unauthorized, _, _) =
    http_run(
      "DELETE",
      "/mcp",
      [#("Origin", "https://nas-1.tail55d152.ts.net")],
      "",
    )
  unauthorized |> should.equal(401)
  let #(forbidden, _, _) =
    http_run("OPTIONS", "/mcp", [#("Origin", "https://evil.example")], "")
  forbidden |> should.equal(403)
}

pub fn suite2_http_notifications_and_batch_match_stdio_test() {
  list.each(
    [
      "notifications/initialized",
      "notifications/cancelled",
      "notifications/roots/list_changed",
      "notifications/unknown_future_event",
    ],
    fn(method) {
      let #(status, _, body) =
        http_run(
          "POST",
          "/mcp",
          http_headers(),
          "{\"jsonrpc\":\"2.0\",\"method\":\"" <> method <> "\"}",
        )
      status |> should.equal(202)
      body |> should.equal("")
    },
  )
  let #(status, _, body) =
    http_run(
      "POST",
      "/mcp",
      http_headers(),
      "[{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"ping\"},{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"},{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/list\"}]",
    )
  status |> should.equal(200)
  let assert Ok(value.Array(replies)) = json.parse(body, value.decoder())
  list.map(replies, fn(reply) { value.get(reply, "id") })
  |> should.equal([Ok(value.Integer(11)), Ok(value.Integer(12))])
}

pub fn suite2_http_accept_content_type_size_and_matching_actor_test() {
  let ping = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}"
  let #(accept, _, _) =
    http_run(
      "POST",
      "/mcp",
      list.filter(http_headers(), fn(h) { h.0 != "Accept" }),
      ping,
    )
  accept |> should.equal(406)
  let #(content, _, _) =
    http_run(
      "POST",
      "/mcp",
      header_replace(http_headers(), "Content-Type", "text/plain"),
      ping,
    )
  content |> should.equal(415)
  let #(size, _, _) =
    http_run("POST", "/mcp", http_headers(), string.repeat("x", 1_048_577))
  size |> should.equal(413)
  let #(status, _, reply) =
    http_run(
      "POST",
      "/mcp",
      http_headers(),
      "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"preflight_check\",\"arguments\":{\"actor\":\"codex\",\"action\":\"inspect\",\"benefit\":2,\"cost\":1}}}",
    )
  status |> should.equal(200)
  json.parse(reply, decode.at(["result", "isError"], decode.bool))
  |> should.equal(Ok(False))
  let #(mismatch, _, _) =
    http_run(
      "POST",
      "/mcp",
      http_headers(),
      "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"preflight_check\",\"arguments\":{\"actor\":\"foreign\",\"action\":\"inspect\",\"benefit\":2,\"cost\":1}}}",
    )
  mismatch |> should.equal(403)
}

pub fn suite2_reserved_resource_backpressure_and_uncertain_taxonomy_test() {
  error_code(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"resources/read\",\"params\":{\"uri\":\"uos://not-a-resource\"}}",
    -32_002,
  )
  list.each(
    [
      "GATEWAY_OVERLOADED",
      "RECEIPT_LEDGER_CAPACITY_EXCEEDED",
      "GATEWAY_TIMEOUT",
    ],
    fn(code) {
      let reply =
        gateway.standard_response(
          wire.IntId(1),
          "",
          types.Refused(types.ToolError(code, "bounded", types.Retryable)),
        )
      json.parse(reply, decode.at(["error", "code"], decode.int))
      |> should.equal(Ok(-32_001))
      json.parse(reply, decode.at(["error", "data", "retryable"], decode.bool))
      |> should.equal(Ok(True))
      json.parse(reply, decode.at(["error", "data", "code"], decode.string))
      |> should.equal(Ok(code))
    },
  )
  let reply =
    gateway.standard_response(
      wire.IntId(1),
      "tools/call",
      types.Uncertain(types.UncertainReceipt(
        "i1",
        "public",
        "plan_update",
        "unknown effect",
        "candidate",
      )),
    )
  json.parse(reply, decode.at(["error", "code"], decode.int))
  |> should.equal(Ok(-32_603))
  json.parse(reply, decode.at(["error", "data", "retryability"], decode.string))
  |> should.equal(Ok("reconcile_first"))
}

pub fn suite2_tool_domain_refusal_remains_mcp_result_error_test() {
  let reply =
    gateway.standard_response(
      wire.IntId(1),
      "tools/call",
      types.Refused(types.ToolError(
        "INVALID_ANALYSIS_INPUT",
        "domain refusal",
        types.NonRetryable,
      )),
    )
  json.parse(reply, decode.at(["result", "isError"], decode.bool))
  |> should.equal(Ok(True))
  json.parse(reply, decode.at(["error"], value.decoder())) |> should.be_error()
}

pub fn suite2_oversized_batch_is_bounded_and_case_variant_method_is_invalid_test() {
  let raw =
    "["
    <> string.join(
      list.repeat("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}", 65),
      ",",
    )
    <> "]"
  error_code(raw, -32_600)
  let assert Some(reply) = rpc(raw)
  string.contains(reply, "BATCH_TOO_LARGE") |> should.be_true()
  error_code("{\"jsonrpc\":\"2.0\",\"id\":1,\"Method\":\"ping\"}", -32_600)
}

pub fn suite2_notifications_are_silent_before_parameter_or_version_validation_test() {
  list.each(
    [
      "{\"jsonrpc\":17,\"method\":\"unknown/future\",\"params\":false}",
      "{\"jsonrpc\":\"1.0\",\"method\":\"ping\",\"params\":42}",
      "{\"method\":\"tools/call\",\"params\":{\"arguments\":[]}}",
    ],
    fn(raw) { rpc(raw) |> should.equal(None) },
  )
}

pub fn suite2_nested_batch_items_are_invalid_requests_test() {
  let assert Some(reply) =
    rpc("[[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}]]")
  let assert Ok(value.Array([item])) = json.parse(reply, value.decoder())
  let assert value.Object(_) = item
  value.get(item, "id") |> should.equal(Ok(value.Null))
  let assert Ok(error) = value.get(item, "error")
  value.get(error, "code") |> should.equal(Ok(value.Integer(-32_600)))
}

pub fn suite2_missing_jsonrpc_member_on_request_is_invalid_test() {
  error_code("{\"id\":1,\"method\":\"ping\"}", -32_600)
}

@external(erlang, "mcp_stdio_ffi", "mcp_json_format_checked")
fn format_checked(
  fields: List(#(String, value.Value)),
) -> Result(String, String)

pub fn suite5_native_formatted_response_is_checked_and_roundtrips_test() {
  let fields = [
    #("jsonrpc", value.Text("2.0")),
    #("id", value.Integer(1)),
    #("result", value.Object([#("text", value.Text("λ😀"))])),
  ]
  let assert Ok(formatted) = format_checked(fields)
  let assert Ok(document) = inspect(bit_array.from_string(formatted), 32)
  value.get(document, "jsonrpc") |> should.equal(Ok(value.Text("2.0")))
  value.get(document, "id") |> should.equal(Ok(value.Integer(1)))
  value.get(document, "result")
  |> should.equal(Ok(value.Object([#("text", value.Text("λ😀"))])))
  format_checked([#("id", value.Integer(1)), #("id", value.Integer(2))])
  |> should.be_error()
  format_checked([
    #(
      "result",
      value.Object([#("a", value.Integer(1)), #("a", value.Integer(2))]),
    ),
  ])
  |> should.be_error()
}
