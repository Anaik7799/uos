//// Runtime availability and JSON-RPC boundary controls for the MCP server.

import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/tools
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
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

fn is_tool_error(response: String) -> Result(Bool, json.DecodeError) {
  let decoder = {
    use is_error <- decode.subfield(["result", "isError"], decode.bool)
    decode.success(is_error)
  }
  json.parse(response, decoder)
}

pub fn absent_nif_is_not_advertised_and_call_fails_closed_test() {
  case tools.nif_runtime_available() {
    False -> {
      tools.catalog_json()
      |> json.to_string
      |> string.contains("\"nif_runtime_status\":\"unavailable\"")
      |> should.be_true
      let names = tools.operational_tool_definitions() |> list.map(fn(t) { t.name })
      names |> list.contains("plan_status") |> should.be_false
      names |> list.contains("system_health") |> should.be_false
      names |> list.contains("verification_run") |> should.be_false

      let response = tool_call("nif-missing", "plan_status", json.object([]))
      response |> is_tool_error |> should.equal(Ok(True))
      response |> string.contains("NIF runtime is not loaded") |> should.be_true
      response |> string.contains("\"active\":0") |> should.be_false
    }
    True -> {
      tools.catalog_json()
      |> json.to_string
      |> string.contains("\"nif_runtime_status\":\"available\"")
      |> should.be_true
      let names = tools.operational_tool_definitions() |> list.map(fn(t) { t.name })
      names |> list.contains("plan_status") |> should.be_true
    }
  }
}

pub fn missing_file_is_a_tool_error_test() {
  let response =
    tool_call(
      "file-missing",
      "read_file",
      json.object([
        #("path", json.string("/definitely/missing/uos-mcp-runtime-check")),
      ]),
    )
  response |> is_tool_error |> should.equal(Ok(True))
  response |> string.contains("enoent") |> should.be_true
}

pub fn valid_string_integer_and_number_ids_are_preserved_test() {
  let assert Some(string_response) =
    server.handle_request_raw(
      "{\"jsonrpc\":\"2.0\",\"id\":\"request-7\",\"method\":\"tools/list\"}",
    )
  let assert Some(integer_response) =
    server.handle_request_raw(
      "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/list\"}",
    )
  let assert Some(number_response) =
    server.handle_request_raw(
      "{\"jsonrpc\":\"2.0\",\"id\":1.5,\"method\":\"tools/list\"}",
    )

  json.parse(string_response, decode.field("id", decode.string, decode.success))
  |> should.equal(Ok("request-7"))
  json.parse(integer_response, decode.field("id", decode.int, decode.success))
  |> should.equal(Ok(7))
  json.parse(number_response, decode.field("id", decode.float, decode.success))
  |> should.equal(Ok(1.5))
}

pub fn unsupported_id_is_an_explicit_invalid_request_test() {
  let assert Some(response) =
    server.handle_request_raw(
      "{\"jsonrpc\":\"2.0\",\"id\":true,\"method\":\"tools/list\"}",
    )
  let decoder = {
    use code <- decode.subfield(["error", "code"], decode.int)
    decode.success(code)
  }
  json.parse(response, decoder) |> should.equal(Ok(-32_600))
  response |> string.contains("\"id\":null") |> should.be_true
}

pub fn notifications_never_receive_responses_test() {
  server.handle_request_raw("{\"jsonrpc\":\"2.0\",\"method\":\"tools/list\"}")
  |> should.equal(None)
  server.handle_request_raw(
    "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"run_gate\",\"arguments\":{}}}",
  )
  |> should.equal(None)
}

pub fn mutating_tool_excessive_risk_is_preflight_vetoed_test() {
  // Test SC-PRED-001: Autonomous Agent Preflight Interlocking fail-closed on high risk
  let response =
    tool_call(
      "preflight-veto-risk",
      "plan_add",
      json.object([
        #("title", json.string("Dangerous Action")),
        #("priority", json.string("high")),
        #("risk_score", json.float(0.85)),
        #("actor", json.string("AutonomousAgent")),
      ]),
    )
  let code_decoder = {
    use code <- decode.subfield(["error", "code"], decode.int)
    decode.success(code)
  }
  let message_decoder = {
    use msg <- decode.subfield(["error", "message"], decode.string)
    decode.success(msg)
  }

  json.parse(response, code_decoder) |> should.equal(Ok(-32_001))
  let assert Ok(msg) = json.parse(response, message_decoder)
  msg |> string.contains("Preflight veto:") |> should.be_true
  msg |> string.contains("Excessive predicted risk") |> should.be_true
}

pub fn mutating_tool_negative_seu_is_preflight_vetoed_test() {
  // Test SC-PRED-001: Vetoed when SEU <= 0
  let response =
    tool_call(
      "preflight-veto-seu",
      "plan_update",
      json.object([
        #("id", json.string("task-123")),
        #("status", json.string("completed")),
        #("benefit", json.float(-10.0)),
        #("cost", json.float(100.0)),
      ]),
    )
  let code_decoder = {
    use code <- decode.subfield(["error", "code"], decode.int)
    decode.success(code)
  }
  let message_decoder = {
    use msg <- decode.subfield(["error", "message"], decode.string)
    decode.success(msg)
  }

  json.parse(response, code_decoder) |> should.equal(Ok(-32_001))
  let assert Ok(msg) = json.parse(response, message_decoder)
  msg |> string.contains("Preflight veto:") |> should.be_true
  msg |> string.contains("Subjective Expected Utility") |> should.be_true
}

pub fn fractal_jidoka_andon_halt_on_bypass_attempt_test() {
  // Test SC-JIDOKA-001: Immediate fail-closed Andon Halt on non-sa-plan bypass attempt
  let response =
    tool_call(
      "jidoka-halt-bypass",
      "plan_add",
      json.object([
        #("title", json.string("Shadow Plan Task")),
        #("priority", json.string("high")),
        #("bypass_sa_plan", json.bool(True)),
      ]),
    )
  let code_decoder = {
    use code <- decode.subfield(["error", "code"], decode.int)
    decode.success(code)
  }
  let message_decoder = {
    use msg <- decode.subfield(["error", "message"], decode.string)
    decode.success(msg)
  }

  json.parse(response, code_decoder) |> should.equal(Ok(-32_002))
  let assert Ok(msg) = json.parse(response, message_decoder)
  msg |> string.contains("Fractal Jidoka Andon Halt") |> should.be_true
  msg |> string.contains("SC-JIDOKA-001") |> should.be_true
}

pub fn fractal_jidoka_andon_halt_on_unledgered_execution_test() {
  // Test SC-JIDOKA-001: Immediate fail-closed Andon Halt on unledgered task execution
  let response =
    tool_call(
      "jidoka-halt-unledgered",
      "plan_update",
      json.object([
        #("id", json.string("task-phantom")),
        #("status", json.string("completed")),
        #("unledgered", json.bool(True)),
      ]),
    )
  let code_decoder = {
    use code <- decode.subfield(["error", "code"], decode.int)
    decode.success(code)
  }
  let message_decoder = {
    use msg <- decode.subfield(["error", "message"], decode.string)
    decode.success(msg)
  }

  json.parse(response, code_decoder) |> should.equal(Ok(-32_002))
  let assert Ok(msg) = json.parse(response, message_decoder)
  msg |> string.contains("Fractal Jidoka Andon Halt") |> should.be_true
}

pub fn sa_plan_durable_tools_advertised_test() {
  // Verify sa-plan tools are part of the operational tool catalog
  let names =
    tools.operational_tool_definitions()
    |> list.map(fn(t) { t.name })

  names |> list.contains("sa_plan_status") |> should.be_true
  names |> list.contains("sa_plan_list") |> should.be_true
  names |> list.contains("sa_task_claim") |> should.be_true
  names |> list.contains("sa_task_complete") |> should.be_true
  names |> list.contains("sa_job_enqueue") |> should.be_true
  names |> list.contains("sa_workflow_start") |> should.be_true
}


