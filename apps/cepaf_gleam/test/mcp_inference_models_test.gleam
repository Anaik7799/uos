//// Test suite for Modular MAX / Mojo High-Utility AI Models and MCP Tooling.
//// Verifies operational execution of all 7 models, Jidoka injection interception,
//// and mutating action STPA preflight interlocking.

import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/tools
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

fn tool_call(id: String, name: String, arguments: json.Json) -> String {
  let request =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.string(id)),
      #("method", json.string("tools/call")),
      #(
        "params",
        json.object([
          #("name", json.string(name)),
          #("arguments", arguments),
        ]),
      ),
    ])
    |> json.to_string
  let assert Some(response) = server.handle_request_raw(request)
  response
}

fn extract_tool_result(response: String) -> Result(String, json.DecodeError) {
  let item_decoder = {
    use text <- decode.field("text", decode.string)
    decode.success(text)
  }
  let decoder = {
    use items <- decode.subfield(["result", "content"], decode.list(item_decoder))
    case items {
      [first, ..] -> decode.success(first)
      [] -> decode.failure("", "non-empty content")
    }
  }
  json.parse(response, decoder)
}

pub fn all_seven_inference_tools_advertised_test() {
  let names =
    tools.operational_tool_definitions()
    |> list.map(fn(t) { t.name })

  names |> list.contains("stpa_fmea_hazard") |> should.be_true
  names |> list.contains("rete_rule_conflict") |> should.be_true
  names |> list.contains("ruliad_branch_eval") |> should.be_true
  names |> list.contains("shruti_harmonics") |> should.be_true
  names |> list.contains("ast_anomaly_detect") |> should.be_true
  names |> list.contains("zk_transclude") |> should.be_true
  names |> list.contains("lyapunov_trend_predict") |> should.be_true
}

pub fn tool_stpa_fmea_hazard_execution_test() {
  let response =
    tool_call(
      "test-stpa",
      "stpa_fmea_hazard",
      json.object([
        #("action", json.string("reboot_node")),
        #("component", json.string("cluster_supervisor")),
        #("context", json.string("nominal")),
        #("criticality", json.int(3)),
        #("dependency_readiness", json.string("ready")),
        #("impact", json.int(2)),
      ]),
    )
  let assert Ok(text) = extract_tool_result(response)
  text |> string.contains("\"gate_decision\":\"PERMITTED\"") |> should.be_true
  text |> string.contains("\"rpn\":") |> should.be_true
  text |> string.contains("\"sil_rating\":") |> should.be_true
}

pub fn tool_rete_rule_conflict_execution_test() {
  let response =
    tool_call(
      "test-rete",
      "rete_rule_conflict",
      json.object([
        #(
          "rules",
          json.array(
            [
              json.object([
                #("id", json.string("rule_quarantine")),
                #("name", json.string("quarantine")),
                #("layer", json.string("L5")),
                #("score", json.float(25.0)),
                #("layer_rank", json.int(5)),
              ]),
              json.object([
                #("id", json.string("rule_admit")),
                #("name", json.string("admit")),
                #("layer", json.string("L2")),
                #("score", json.float(10.0)),
                #("layer_rank", json.int(2)),
              ]),
            ],
            fn(x) { x },
          ),
        ),
      ]),
    )
  let assert Ok(text) = extract_tool_result(response)
  text |> string.contains("\"rules_evaluated\":2") |> should.be_true
  text |> string.contains("\"winner\":") |> should.be_true
}

pub fn tool_ruliad_branch_eval_execution_test() {
  let response =
    tool_call(
      "test-ruliad",
      "ruliad_branch_eval",
      json.object([
        #("source_branch", json.string("integration/feature")),
        #("target_branch", json.string("main")),
        #("candidate_changes", json.array(["clean candidate"], json.string)),
        #("agents", json.array(["agy", "claude", "codex"], json.string)),
      ]),
    )
  let assert Ok(text) = extract_tool_result(response)
  text |> string.contains("\"branchial_distance\":") |> should.be_true
  text |> string.contains("\"convergence_status\":") |> should.be_true
}

pub fn tool_shruti_harmonics_execution_test() {
  let response =
    tool_call(
      "test-shruti",
      "shruti_harmonics",
      json.object([
        #("raga", json.string("durga")),
        #("fundamental_hz", json.float(146.83)),
        #("telemetry", json.array([1.0, 1.2, 0.9, 1.1], json.float)),
      ]),
    )
  let assert Ok(text) = extract_tool_result(response)
  text |> string.contains("\"raga\":\"durga\"") |> should.be_true
  text |> string.contains("\"spectral_entropy\":") |> should.be_true
}

pub fn tool_ast_anomaly_detect_execution_test() {
  let response =
    tool_call(
      "test-ast-normal",
      "ast_anomaly_detect",
      json.object([
        #("code", json.string("pub fn verify() -> Bool { True }")),
        #("language", json.string("gleam")),
        #("strict_mode", json.bool(True)),
      ]),
    )
  let assert Ok(text) = extract_tool_result(response)
  text |> string.contains("\"passed\":true") |> should.be_true
  text |> string.contains("\"anomaly_score\":") |> should.be_true
}

pub fn tool_zk_transclude_execution_test() {
  let response =
    tool_call(
      "test-zk",
      "zk_transclude",
      json.object([
        #("query", json.string("sa-plan jidoka")),
        #("limit", json.int(3)),
      ]),
    )
  let assert Ok(text) = extract_tool_result(response)
  text |> string.contains("\"status\":\"ok\"") |> should.be_true
  text |> string.contains("\"matches\":[") |> should.be_true
}

pub fn tool_lyapunov_trend_predict_execution_test() {
  let response =
    tool_call(
      "test-lyapunov",
      "lyapunov_trend_predict",
      json.object([
        #("telemetry", json.array([1.0, 1.01, 1.02], json.float)),
        #("dt", json.float(1.0)),
        #("horizon_seconds", json.float(60.0)),
        #("critical_threshold", json.float(50.0)),
      ]),
    )
  let assert Ok(text) = extract_tool_result(response)
  text |> string.contains("\"status\":\"ok\"") |> should.be_true
  text |> string.contains("\"stability_state\":\"strongly_stable\"") |> should.be_true
  text |> string.contains("\"lyapunov_exponent\":") |> should.be_true
}

pub fn ast_anomaly_triggers_jidoka_andon_halt_test() {
  // Test that injecting raw SQL or NUL bytes into any tool call triggers Jidoka Andon Stop Line
  let response =
    tool_call(
      "test-malicious-sql",
      "plan_status",
      json.object([
        #("plan_id", json.string("DROP TABLE uos_tasks; --")),
      ]),
    )
  let code_decoder = {
    use code <- decode.subfield(["error", "code"], decode.int)
    decode.success(code)
  }
  let msg_decoder = {
    use msg <- decode.subfield(["error", "message"], decode.string)
    decode.success(msg)
  }

  json.parse(response, code_decoder) |> should.equal(Ok(-32_002))
  let assert Ok(msg) = json.parse(response, msg_decoder)
  msg |> string.contains("Fractal Jidoka Andon Halt") |> should.be_true
}
