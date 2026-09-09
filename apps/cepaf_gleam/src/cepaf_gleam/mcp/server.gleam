// STAMP: SC-MCP-001, SC-FUNC-001, SC-TODO-001, SC-ZMOF-005
// AOR: AOR-GLM-001, AOR-MCP-001
// Criticality: Level 2 (HIGH) - MCP Server stdio JSON-RPC 2.0 transport
//
// Full stdio JSON-RPC 2.0 transport with NIF-backed planning tools:
// 1. Reads lines from stdin
// 2. Parses JSON-RPC requests
// 3. Dispatches to tool handlers (planning via Rust NIF, others via stubs)
// 4. Writes JSON-RPC responses to stdout
// 5. Logs diagnostics to stderr
// 6. Zenoh transport via bridge/zenoh_mcp.gleam (handle_request_raw)

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ha/fractal_forecast
import cepaf_gleam/mcp/authz
import cepaf_gleam/mcp/protocol.{type ToolDefinition}
import cepaf_gleam/mcp/tools
import cepaf_gleam/planning/sa_plan_bridge
import cepaf_gleam/services/max_inference_daemon as max_daemon
import cepaf_gleam/ui/wisp/inference_api
import cepaf_gleam/ui/wisp/router as wisp_router
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// ---------------------------------------------------------------------------
// Erlang FFI bindings
// ---------------------------------------------------------------------------

type StdioLine {
  Line(String)
  EndOfFile
  ReadError(String)
}

@external(erlang, "mcp_stdio_ffi", "read_line")
fn read_stdio_line() -> StdioLine

@external(erlang, "cepaf_gleam_ffi", "file_read")
fn erl_file_read(path: String) -> Result(BitArray, String)

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn main() {
  io.println_error(
    "[mcp-server] Starting C3I Planning MCP Server (stdio transport)...",
  )
  loop()
}

pub fn start() {
  main()
}

// ---------------------------------------------------------------------------
// stdin read loop
// ---------------------------------------------------------------------------

fn loop() {
  case read_stdio_line() {
    Line(line) -> {
      let trimmed = string.trim(line)
      case trimmed {
        "" -> loop()
        _ -> {
          io.println_error("[mcp-server] request received")
          case process_line(trimmed) {
            Some(resp) -> {
              io.println_error("[mcp-server] response emitted")
              io.println(resp)
            }
            None -> Nil
          }
          loop()
        }
      }
    }
    EndOfFile -> io.println_error("[mcp-server] stdin closed, shutting down")
    ReadError(reason) ->
      io.println_error("[mcp-server] stdin error, shutting down: " <> reason)
  }
}

// ---------------------------------------------------------------------------
// JSON-RPC parsing
// ---------------------------------------------------------------------------

type RequestId {
  Notification
  PresentId(json.Json)
}

fn process_line(line: String) -> Option(String) {
  let id_decoder =
    decode.one_of(
      decode.map(decode.string, fn(value) { PresentId(json.string(value)) }),
      [
        decode.map(decode.int, fn(value) { PresentId(json.int(value)) }),
        decode.map(decode.float, fn(value) { PresentId(json.float(value)) }),
      ],
    )
  let request_decoder = {
    use m <- decode.field("method", decode.string)
    use i <- decode.optional_field("id", Notification, id_decoder)
    decode.success(#(m, i))
  }

  case json.parse(line, decode.dynamic) {
    Error(_) -> Some(error_response(None, -32_700, "Parse error"))
    Ok(document) ->
      case decode.run(document, request_decoder) {
        Error(_) -> Some(error_response(None, -32_600, "Invalid Request"))
        Ok(#(method, PresentId(id))) -> dispatch(method, Some(id), line)
        Ok(#(method, Notification)) -> {
          // JSON-RPC notifications execute but never receive a response.
          let _ = dispatch(method, None, line)
          None
        }
      }
  }
}

// ---------------------------------------------------------------------------
// Method dispatch
// ---------------------------------------------------------------------------

fn dispatch(
  method: String,
  id: Option(json.Json),
  raw_line: String,
) -> Option(String) {
  case method {
    "initialize" -> Some(initialize_response(id))
    "initialized" -> None
    "notifications/initialized" -> None
    "tools/list" -> Some(tools_list_response(id))
    "tools/call" -> Some(tools_call(id, raw_line))
    _ -> Some(error_response(id, -32_601, "Method not found: " <> method))
  }
}

// ---------------------------------------------------------------------------
// initialize
// ---------------------------------------------------------------------------

fn initialize_response(id: Option(json.Json)) -> String {
  success_response(
    id,
    json.object([
      #("protocolVersion", json.string("2024-11-05")),
      #("capabilities", json.object([#("tools", json.object([]))])),
      #(
        "serverInfo",
        json.object([
          #("name", json.string("c3i-planning-mcp")),
          #("version", json.string("1.0.0")),
        ]),
      ),
    ]),
  )
}

// ---------------------------------------------------------------------------
// tools/list
// ---------------------------------------------------------------------------

fn tools_list_response(id: Option(json.Json)) -> String {
  let defs: List(ToolDefinition) = tools.operational_tool_definitions()
  let tools_json =
    json.array(
      list.map(defs, fn(t) {
        json.object([
          #("name", json.string(t.name)),
          #("description", json.string(t.description)),
          #("inputSchema", t.input_schema),
        ])
      }),
      of: fn(x) { x },
    )
  success_response(id, json.object([#("tools", tools_json)]))
}

// ---------------------------------------------------------------------------
// tools/call
// ---------------------------------------------------------------------------

fn tools_call(id: Option(json.Json), raw_line: String) -> String {
  let name_decoder = {
    use n <- decode.subfield(["params", "name"], decode.string)
    decode.success(n)
  }
  case json.parse(raw_line, name_decoder) {
    Ok(tool_name) -> execute_tool(tool_name, id, raw_line)
    Error(_) -> error_response(id, -32_602, "Missing params.name")
  }
}

// ---------------------------------------------------------------------------
// Tool execution — NIF-backed planning + existing tools
// ---------------------------------------------------------------------------

pub fn is_mutating_tool(name: String) -> Bool {
  case name {
    "plan_add"
    | "plan_update"
    | "sa_task_claim"
    | "sa_task_complete"
    | "sa_job_enqueue"
    | "sa_workflow_start" -> True
    _ -> False
  }
}

pub fn check_fractal_jidoka_violation(
  name: String,
  raw_line: String,
) -> Result(Nil, String) {
  let bypass_decoder = {
    use b <- decode.subfield(
      ["params", "arguments", "bypass_sa_plan"],
      decode.bool,
    )
    decode.success(b)
  }
  let unledgered_decoder = {
    use u <- decode.subfield(["params", "arguments", "unledgered"], decode.bool)
    decode.success(u)
  }
  let shadow_decoder = {
    use s <- decode.subfield(
      ["params", "arguments", "shadow_plan"],
      decode.bool,
    )
    decode.success(s)
  }

  let is_bypass = case json.parse(raw_line, bypass_decoder) {
    Ok(True) -> True
    _ -> False
  }
  let is_unledgered = case json.parse(raw_line, unledgered_decoder) {
    Ok(True) -> True
    _ -> False
  }
  let is_shadow = case json.parse(raw_line, shadow_decoder) {
    Ok(True) -> True
    _ -> False
  }

  // Model 1: Live AST Anomaly & Security Invariant Check (SC-INF-001)
  let ast_rep = inference_api.evaluate_ast_anomaly(raw_line, "json", True)
  let ast_blocked = case ast_rep.passed {
    False ->
      list.contains(ast_rep.violations, "JIDOKA_BYPASS_ATTEMPT")
      || list.contains(ast_rep.violations, "RAW_SQL_INJECTION")
      || list.contains(ast_rep.violations, "NUL_BYTE_INJECTION")
      || list.contains(ast_rep.violations, "OS_STORAGE_DENIED_SERIAL")
    True -> False
  }

  case is_bypass || is_unledgered || is_shadow || ast_blocked {
    True ->
      sa_plan_bridge.enforce_fractal_jidoka("AutonomousAgent", name, False)
    False -> Ok(Nil)
  }
}

pub fn verify_mutating_action_preflight(
  action: String,
  raw_line: String,
) -> fractal_forecast.AgenticPreflightCertificate {
  let actor_decoder = {
    use a <- decode.subfield(["params", "arguments", "actor"], decode.string)
    decode.success(a)
  }
  let benefit_decoder = {
    use b <- decode.subfield(["params", "arguments", "benefit"], decode.float)
    decode.success(b)
  }
  let cost_decoder = {
    use c <- decode.subfield(["params", "arguments", "cost"], decode.float)
    decode.success(c)
  }
  let risk_decoder = {
    use r <- decode.subfield(
      ["params", "arguments", "risk_score"],
      decode.float,
    )
    decode.success(r)
  }
  let contention_decoder = {
    use h <- decode.subfield(
      ["params", "arguments", "contention_history"],
      decode.list(decode.float),
    )
    decode.success(h)
  }

  let actor = case json.parse(raw_line, actor_decoder) {
    Ok(a) -> a
    Error(_) -> "AutonomousAgent"
  }
  let benefit = case json.parse(raw_line, benefit_decoder) {
    Ok(b) -> b
    Error(_) -> 100.0
  }
  let cost = case json.parse(raw_line, cost_decoder) {
    Ok(c) -> c
    Error(_) -> 10.0
  }

  let base_forecast = case json.parse(raw_line, contention_decoder) {
    Ok(history) -> fractal_forecast.predict_l3_transaction(history, 60)
    Error(_) ->
      fractal_forecast.predict_l3_transaction(
        [0.05, 0.04, 0.06, 0.05, 0.04, 0.05, 0.05, 0.04],
        60,
      )
  }

  let forecast = case json.parse(raw_line, risk_decoder) {
    Ok(r) -> fractal_forecast.LayerForecast(..base_forecast, risk_score: r)
    Error(_) -> base_forecast
  }

  // Model 4: STPA-UCA & FMEA Causal Hazard Evaluation (SC-INF-001, SC-SIL6-001)
  let stpa_rep =
    inference_api.evaluate_stpa_fmea(
      action,
      "mcp_actuator",
      raw_line,
      4,
      "ready",
      4,
    )
  case
    stpa_rep.gate_decision == "ANDON_STOP_BLOCKED" || stpa_rep.severity >= 9
  {
    True ->
      fractal_forecast.PreflightVetoed(
        certificate_id: "CERT-STPA-" <> action,
        actor: actor,
        action: action,
        rejection_reason: "STPA-FMEA Safety Gate: "
          <> stpa_rep.gate_decision
          <> " (RPN="
          <> int.to_string(stpa_rep.rpn)
          <> ", SIL="
          <> stpa_rep.sil_rating
          <> ")",
        risk_score: 1.0,
      )
    False ->
      fractal_forecast.verify_agentic_preflight(
        actor,
        action,
        forecast,
        benefit,
        cost,
      )
  }
}

fn execute_tool(
  name: String,
  id: Option(json.Json),
  raw_line: String,
) -> String {
  case check_fractal_jidoka_violation(name, raw_line) {
    Error(reason) -> error_response(id, -32_002, reason)
    Ok(Nil) ->
      // Authorization at the effect boundary (mcp/authz.gleam): rate limit,
      // path controls and the guardian gate, all before any preflight or
      // execution. A denial is a typed JSON-RPC error and nothing runs.
      case authz.authorize_and_persist(name, is_mutating_tool(name), raw_line) {
        Error(denial) ->
          error_response(
            id,
            authz.denial_code(denial),
            authz.denial_message(denial),
          )
        Ok(_) ->
          case is_mutating_tool(name) {
            True -> {
              case verify_mutating_action_preflight(name, raw_line) {
                fractal_forecast.PreflightApproved(_, _, _, _, _) -> {
                  // Legacy payload identities do not establish effect authority.
                  // Only the separately task-bound development harness may
                  // expose its finite development effects.
                  error_response(
                    id,
                    -32_003,
                    "Transport-bound task authority unavailable; legacy mutation refused",
                  )
                }
                fractal_forecast.PreflightVetoed(_, _, _, reason, _risk) -> {
                  error_response(id, -32_001, "Preflight veto: " <> reason)
                }
              }
            }
            False -> {
              case tools.unavailable_reason(name) {
                Some(reason) -> tool_unavailable(id, name, reason)
                None -> execute_available_tool(name, id, raw_line)
              }
            }
          }
      }
  }
}

fn execute_available_tool(
  name: String,
  id: Option(json.Json),
  raw_line: String,
) -> String {
  case name {
    // Planning tools (Rust NIF -> Smriti.db)
    "plan_status" -> tool_plan_status(id)
    "plan_list_pending" -> tool_plan_list_pending(id)
    "plan_list" -> tool_plan_list(id, raw_line)
    "plan_get" -> tool_plan_get(id, raw_line)
    "plan_add" ->
      case verify_mutating_action_preflight(name, raw_line) {
        fractal_forecast.PreflightApproved(_, _, _, _, _) ->
          tool_plan_add(id, raw_line)
        fractal_forecast.PreflightVetoed(_, _, _, reason, _) ->
          error_response(id, -32_001, "Preflight veto: " <> reason)
      }
    "plan_update" ->
      case verify_mutating_action_preflight(name, raw_line) {
        fractal_forecast.PreflightApproved(_, _, _, _, _) ->
          tool_plan_update(id, raw_line)
        fractal_forecast.PreflightVetoed(_, _, _, reason, _) ->
          error_response(id, -32_001, "Preflight veto: " <> reason)
      }
    "plan_search" -> tool_plan_search(id, raw_line)
    // System data tools (mesh state)
    "system_health" -> tool_system_health(id)
    "system_dashboard" -> tool_system_dashboard(id)
    "system_immune" -> tool_system_immune(id)
    "system_zenoh" -> tool_system_zenoh(id)
    "system_verification" -> tool_system_verification(id)
    // Legacy aliases (backward compat)
    "planning_query" -> tool_plan_list_pending(id)
    "todo_status" -> tool_plan_status(id)
    // Other tools
    "knowledge_search" -> tool_knowledge_search(id, raw_line)
    "verification_run" -> tool_verification_run(id)
    "read_file" -> tool_read_file(id, raw_line)
    // Domain-specific page tools (per-page MCP access)
    "podman_containers" -> tool_page_json(id, "/api/v1/podman")
    "metabolic_state" -> tool_page_json(id, "/api/v1/metabolic")
    "ooda_phase" -> tool_page_json(id, "/api/v1/ooda")
    "fractal_status" -> tool_page_json(id, "/api/v1/verification")
    "prajna_health" -> tool_page_json(id, "/api/v1/prajna")
    "dark_cockpit_mode" -> tool_adapter_response(id, c3i_nif.system_dashboard())
    "integrity_check" -> tool_page_json(id, "/api/v1/integrity")
    "evolution_metrics" -> tool_page_json(id, "/api/v1/evolution")
    "mesh_topology" -> tool_adapter_response(id, c3i_nif.system_zenoh())
    "ooda_decide" -> tool_page_json(id, "/api/v1/ooda/decide")
    "kms_catalog" -> tool_page_json(id, "/api/v1/kms")
    // ZigVM / Hermes Harness tools
    "control_loop" -> tool_control_loop(id, raw_line)
    "safety_status" -> tool_safety_status(id)
    "registry_status" -> tool_registry_status(id)
    "run_selfcheck" -> tool_run_selfcheck(id, raw_line)
    "run_gate" -> tool_run_gate(id, raw_line)
    "zk_search" -> tool_zk_search(id, raw_line)
    "sa_bridge_submit" -> tool_sa_bridge_submit(id, raw_line)
    // Unified Fractal Forecasting & Preflight Gates (SC-HIVE-FORECAST-001, SC-PRED-001)
    "forecast_predict" -> tool_forecast_predict(id, raw_line)
    "preflight_check" -> tool_preflight_check(id, raw_line)
    // Sa-Plan Durable Execution Tools (SC-JIDOKA-001, SC-SA-PLAN-001)
    "sa_plan_status" -> tool_sa_plan_status(id)
    "sa_plan_list" -> tool_sa_plan_list(id)
    "sa_task_claim" -> tool_sa_task_claim(id, raw_line)
    "sa_task_complete" -> tool_sa_task_complete(id, raw_line)
    "sa_job_enqueue" -> tool_sa_job_enqueue(id, raw_line)
    "sa_workflow_start" -> tool_sa_workflow_start(id, raw_line)
    // Modular MAX / Mojo High-Utility AI Models (SC-INF-001)
    "stpa_fmea_hazard" -> tool_stpa_fmea_hazard(id, raw_line)
    "rete_rule_conflict" -> tool_rete_rule_conflict(id, raw_line)
    "ruliad_branch_eval" -> tool_ruliad_branch_eval(id, raw_line)
    "shruti_harmonics" -> tool_shruti_harmonics(id, raw_line)
    "ast_anomaly_detect" -> tool_ast_anomaly_detect(id, raw_line)
    "zk_transclude" -> tool_zk_transclude(id, raw_line)
    "lyapunov_trend_predict" -> tool_lyapunov_trend_predict(id, raw_line)
    _ -> error_response(id, -32_602, "Unknown tool: " <> name)
  }
}

// ---------------------------------------------------------------------------
// Planning tool handlers (NIF-backed)
// ---------------------------------------------------------------------------

fn tool_plan_status(id: Option(json.Json)) -> String {
  tool_adapter_response(id, c3i_nif.plan_status())
}

fn tool_plan_list_pending(id: Option(json.Json)) -> String {
  tool_adapter_response(id, c3i_nif.plan_list_pending())
}

fn tool_plan_list(id: Option(json.Json), raw_line: String) -> String {
  let status_decoder = {
    use s <- decode.subfield(["params", "arguments", "status"], decode.string)
    decode.success(s)
  }
  let status = case json.parse(raw_line, status_decoder) {
    Ok(s) -> s
    Error(_) -> "all"
  }
  tool_adapter_response(id, c3i_nif.plan_list_by_status(status))
}

fn tool_plan_get(id: Option(json.Json), raw_line: String) -> String {
  let id_decoder = {
    use i <- decode.subfield(["params", "arguments", "id"], decode.string)
    decode.success(i)
  }
  case json.parse(raw_line, id_decoder) {
    Ok(task_id) -> tool_adapter_response(id, c3i_nif.plan_get_task(task_id))
    Error(_) -> error_response(id, -32_602, "Missing params.arguments.id")
  }
}

fn tool_plan_add(id: Option(json.Json), raw_line: String) -> String {
  let decoder = {
    use title <- decode.subfield(
      ["params", "arguments", "title"],
      decode.string,
    )
    use priority <- decode.subfield(
      ["params", "arguments", "priority"],
      decode.string,
    )
    decode.success(#(title, priority))
  }
  case json.parse(raw_line, decoder) {
    Ok(#(title, priority)) ->
      tool_adapter_response(id, c3i_nif.plan_add_task(title, priority))
    Error(_) ->
      error_response(
        id,
        -32_602,
        "Missing params.arguments.title and/or params.arguments.priority",
      )
  }
}

fn tool_plan_update(id: Option(json.Json), raw_line: String) -> String {
  let decoder = {
    use task_id <- decode.subfield(["params", "arguments", "id"], decode.string)
    use status <- decode.subfield(
      ["params", "arguments", "status"],
      decode.string,
    )
    decode.success(#(task_id, status))
  }
  case json.parse(raw_line, decoder) {
    Ok(#(task_id, status)) ->
      tool_adapter_response(id, c3i_nif.plan_update_task(task_id, status))
    Error(_) ->
      error_response(
        id,
        -32_602,
        "Missing params.arguments.id and/or params.arguments.status",
      )
  }
}

fn tool_plan_search(id: Option(json.Json), raw_line: String) -> String {
  let query_decoder = {
    use q <- decode.subfield(["params", "arguments", "query"], decode.string)
    decode.success(q)
  }
  case json.parse(raw_line, query_decoder) {
    Ok(query) -> tool_adapter_response(id, c3i_nif.plan_search(query))
    Error(_) -> error_response(id, -32_602, "Missing params.arguments.query")
  }
}

// ---------------------------------------------------------------------------
// System data tool handlers (mesh state)
// ---------------------------------------------------------------------------

fn tool_system_health(id: Option(json.Json)) -> String {
  tool_adapter_response(id, c3i_nif.system_health())
}

fn tool_system_dashboard(id: Option(json.Json)) -> String {
  tool_adapter_response(id, c3i_nif.system_dashboard())
}

fn tool_system_immune(id: Option(json.Json)) -> String {
  tool_adapter_response(id, c3i_nif.system_immune())
}

fn tool_system_zenoh(id: Option(json.Json)) -> String {
  tool_adapter_response(id, c3i_nif.system_zenoh())
}

fn tool_system_verification(id: Option(json.Json)) -> String {
  tool_adapter_response(id, c3i_nif.system_verification())
}

// ---------------------------------------------------------------------------
// Other tool handlers (kept from original)
// ---------------------------------------------------------------------------

fn tool_knowledge_search(id: Option(json.Json), raw_line: String) -> String {
  let query_decoder = {
    use q <- decode.subfield(["params", "arguments", "query"], decode.string)
    decode.success(q)
  }
  let query = case json.parse(raw_line, query_decoder) {
    Ok(q) -> q
    Error(_) -> ""
  }
  tool_adapter_response(id, c3i_nif.knowledge_search(query))
}

fn tool_verification_run(id: Option(json.Json)) -> String {
  tool_adapter_response(id, c3i_nif.verification_run())
}

fn tool_read_file(id: Option(json.Json), raw_line: String) -> String {
  let path_decoder = {
    use p <- decode.subfield(["params", "arguments", "path"], decode.string)
    decode.success(p)
  }
  case json.parse(raw_line, path_decoder) {
    Ok(path) -> {
      case read_file_as_string(path) {
        Ok(content) -> tool_content_response(id, content)
        Error(e) -> tool_error_response(id, "Error reading file: " <> e)
      }
    }
    Error(_) -> error_response(id, -32_602, "Missing params.arguments.path")
  }
}

/// Route a per-page tool through the Wisp router to get JSON data.
fn tool_page_json(id: Option(json.Json), api_path: String) -> String {
  tool_adapter_response(id, wisp_router.route(api_path))
}

fn tool_forecast_predict(id: Option(json.Json), raw_line: String) -> String {
  let layer_decoder = {
    use l <- decode.subfield(["params", "arguments", "layer"], decode.string)
    decode.success(l)
  }
  let horizon_decoder = {
    use h <- decode.subfield(
      ["params", "arguments", "horizon_seconds"],
      decode.int,
    )
    decode.success(h)
  }
  let layer = case json.parse(raw_line, layer_decoder) {
    Ok(l) -> l
    Error(_) -> "all"
  }
  let horizon = case json.parse(raw_line, horizon_decoder) {
    Ok(h) -> h
    Error(_) -> 60
  }

  case string.lowercase(layer) {
    "all" ->
      tool_content_response(
        id,
        json.to_string(fractal_forecast.all_layers_forecast_json()),
      )
    "l0" | "l0_constitutional" | "constitutional" ->
      tool_content_response(
        id,
        json.to_string(
          fractal_forecast.layer_forecast_to_json(
            fractal_forecast.predict_l0_constitutional(
              [0.98, 0.99, 0.97, 0.98, 0.99, 0.98, 0.99, 0.98],
              horizon,
            ),
          ),
        ),
      )
    "l1" | "l1_atomic" | "atomic" ->
      tool_content_response(
        id,
        json.to_string(
          fractal_forecast.layer_forecast_to_json(
            fractal_forecast.predict_l1_atomic(
              [0.12, 0.14, 0.11, 0.13, 0.12, 0.15, 0.13, 0.12],
              horizon,
            ),
          ),
        ),
      )
    "l2" | "l2_component" | "component" ->
      tool_content_response(
        id,
        json.to_string(
          fractal_forecast.layer_forecast_to_json(
            fractal_forecast.predict_l2_component(
              [0.55, 0.58, 0.56, 0.6, 0.62, 0.61, 0.63, 0.62],
              horizon,
            ),
          ),
        ),
      )
    "l3" | "l3_transaction" | "transaction" ->
      tool_content_response(
        id,
        json.to_string(
          fractal_forecast.layer_forecast_to_json(
            fractal_forecast.predict_l3_transaction(
              [0.05, 0.04, 0.06, 0.05, 0.04, 0.05, 0.05, 0.04],
              horizon,
            ),
          ),
        ),
      )
    "l4" | "l4_system" | "system" ->
      tool_content_response(
        id,
        json.to_string(
          fractal_forecast.layer_forecast_to_json(
            fractal_forecast.predict_l4_system(
              [0.02, 0.01, 0.03, 0.02, 0.01, 0.02, 0.02, 0.01],
              horizon,
            ),
          ),
        ),
      )
    "l5" | "l5_cognitive" | "cognitive" ->
      tool_content_response(
        id,
        json.to_string(
          fractal_forecast.layer_forecast_to_json(
            fractal_forecast.predict_l5_cognitive(
              [0.45, 0.48, 0.5, 0.47, 0.52, 0.49, 0.51, 0.5],
              horizon,
            ),
          ),
        ),
      )
    "l6" | "l6_ecosystem" | "ecosystem" ->
      tool_content_response(
        id,
        json.to_string(
          fractal_forecast.layer_forecast_to_json(
            fractal_forecast.predict_l6_ecosystem(
              [0.15, 0.18, 0.16, 0.17, 0.19, 0.16, 0.18, 0.17],
              horizon,
            ),
          ),
        ),
      )
    "l7" | "l7_federation" | "federation" ->
      tool_content_response(
        id,
        json.to_string(
          fractal_forecast.layer_forecast_to_json(
            fractal_forecast.predict_l7_federation(
              [0.08, 0.09, 0.07, 0.08, 0.1, 0.09, 0.08, 0.09],
              horizon,
            ),
          ),
        ),
      )
    "l8" | "l8_mutation" | "mutation" ->
      tool_content_response(
        id,
        json.to_string(
          fractal_forecast.layer_forecast_to_json(
            fractal_forecast.predict_l8_mutation(
              [0.94, 0.95, 0.93, 0.96, 0.94, 0.95, 0.96, 0.95],
              horizon,
            ),
          ),
        ),
      )
    "l9" | "l9_verification" | "verification" ->
      tool_content_response(
        id,
        json.to_string(
          fractal_forecast.layer_forecast_to_json(
            fractal_forecast.predict_l9_verification(
              [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
              horizon,
            ),
          ),
        ),
      )
    _ ->
      tool_content_response(
        id,
        json.to_string(fractal_forecast.all_layers_forecast_json()),
      )
  }
}

fn tool_preflight_check(id: Option(json.Json), raw_line: String) -> String {
  let decoder = {
    use actor <- decode.subfield(
      ["params", "arguments", "actor"],
      decode.string,
    )
    use action <- decode.subfield(
      ["params", "arguments", "action"],
      decode.string,
    )
    use benefit <- decode.subfield(
      ["params", "arguments", "benefit"],
      decode.float,
    )
    use cost <- decode.subfield(["params", "arguments", "cost"], decode.float)
    decode.success(#(actor, action, benefit, cost))
  }
  case json.parse(raw_line, decoder) {
    Ok(#(actor, action, benefit, cost)) -> {
      let default_forecast =
        fractal_forecast.predict_l3_transaction(
          [0.05, 0.04, 0.06, 0.05, 0.04, 0.05, 0.05, 0.04],
          60,
        )
      let cert =
        fractal_forecast.verify_agentic_preflight(
          actor,
          action,
          default_forecast,
          benefit,
          cost,
        )
      tool_content_response(
        id,
        json.to_string(fractal_forecast.preflight_certificate_to_json(cert)),
      )
    }
    Error(_) ->
      error_response(
        id,
        -32_602,
        "Missing required params.arguments: actor, action, benefit, cost",
      )
  }
}

// ---------------------------------------------------------------------------
// Sa-Plan Durable Tool Handlers (SC-JIDOKA-001, SC-SA-PLAN-001)
// ---------------------------------------------------------------------------

fn tool_sa_plan_status(id: Option(json.Json)) -> String {
  case sa_plan_bridge.query_sa_plan_status() {
    Ok(out) -> tool_content_response(id, out)
    Error(err) -> tool_error_response(id, err)
  }
}

fn tool_sa_plan_list(id: Option(json.Json)) -> String {
  case sa_plan_bridge.query_sa_plan_list() {
    Ok(out) -> tool_content_response(id, out)
    Error(err) -> tool_error_response(id, err)
  }
}

fn tool_sa_task_claim(id: Option(json.Json), raw_line: String) -> String {
  let worker_decoder = {
    use w <- decode.subfield(["params", "arguments", "worker"], decode.string)
    decode.success(w)
  }
  let plan_decoder = {
    use p <- decode.subfield(["params", "arguments", "plan"], decode.string)
    decode.success(p)
  }
  let task_id_decoder = {
    use t <- decode.subfield(["params", "arguments", "task_id"], decode.string)
    decode.success(t)
  }

  case
    json.parse(raw_line, worker_decoder),
    json.parse(raw_line, plan_decoder),
    json.parse(raw_line, task_id_decoder)
  {
    Ok(worker), Ok(plan), Ok(task_id) -> {
      case sa_plan_bridge.claim_sa_task(worker, plan, task_id) {
        Ok(out) -> tool_content_response(id, out)
        Error(err) -> tool_error_response(id, err)
      }
    }
    _, _, _ ->
      error_response(
        id,
        -32_602,
        "Missing required parameters: worker, plan, task_id",
      )
  }
}

fn tool_sa_task_complete(id: Option(json.Json), raw_line: String) -> String {
  let attempt_decoder = {
    use a <- decode.subfield(["params", "arguments", "attempt"], decode.int)
    decode.success(a)
  }
  let plan_decoder = {
    use p <- decode.subfield(["params", "arguments", "plan"], decode.string)
    decode.success(p)
  }
  let task_id_decoder = {
    use t <- decode.subfield(["params", "arguments", "task_id"], decode.string)
    decode.success(t)
  }
  let worker_decoder = {
    use w <- decode.subfield(["params", "arguments", "worker"], decode.string)
    decode.success(w)
  }
  let result_decoder = {
    use r <- decode.subfield(["params", "arguments", "result"], decode.string)
    decode.success(r)
  }

  case
    json.parse(raw_line, plan_decoder),
    json.parse(raw_line, task_id_decoder),
    json.parse(raw_line, worker_decoder),
    json.parse(raw_line, result_decoder),
    json.parse(raw_line, attempt_decoder)
  {
    Ok(plan), Ok(task_id), Ok(worker), Ok(result), Ok(attempt) -> {
      case
        sa_plan_bridge.complete_sa_task(plan, task_id, worker, attempt, result)
      {
        Ok(out) -> tool_content_response(id, out)
        Error(err) -> tool_error_response(id, err)
      }
    }
    _, _, _, _, _ ->
      error_response(
        id,
        -32_602,
        "Missing required parameters: plan, task_id, worker, attempt, result",
      )
  }
}

fn tool_sa_job_enqueue(id: Option(json.Json), raw_line: String) -> String {
  let id_decoder = {
    use job_id <- decode.subfield(["params", "arguments", "id"], decode.string)
    decode.success(job_id)
  }
  let name_decoder = {
    use n <- decode.subfield(["params", "arguments", "name"], decode.string)
    decode.success(n)
  }
  let queue_decoder = {
    use q <- decode.subfield(["params", "arguments", "queue"], decode.string)
    decode.success(q)
  }
  let worker_decoder = {
    use w <- decode.subfield(["params", "arguments", "worker"], decode.string)
    decode.success(w)
  }
  let args_decoder = {
    use a <- decode.subfield(["params", "arguments", "args"], decode.string)
    decode.success(a)
  }

  case
    json.parse(raw_line, id_decoder),
    json.parse(raw_line, name_decoder),
    json.parse(raw_line, queue_decoder),
    json.parse(raw_line, worker_decoder),
    json.parse(raw_line, args_decoder)
  {
    Ok(job_id), Ok(name), Ok(queue), Ok(worker), Ok(args) -> {
      case sa_plan_bridge.poka_yoke_validate_job(queue, worker, args) {
        Ok(Nil) -> {
          case
            sa_plan_bridge.enqueue_sa_job(job_id, name, queue, worker, args)
          {
            Ok(out) -> tool_content_response(id, out)
            Error(err) -> tool_error_response(id, err)
          }
        }
        Error(poka_err) -> error_response(id, -32_602, poka_err)
      }
    }
    _, _, _, _, _ ->
      error_response(
        id,
        -32_602,
        "Missing required parameters: id, name, queue, worker, args",
      )
  }
}

fn tool_sa_workflow_start(id: Option(json.Json), raw_line: String) -> String {
  let wf_id_decoder = {
    use wid <- decode.subfield(["params", "arguments", "id"], decode.string)
    decode.success(wid)
  }
  let name_decoder = {
    use n <- decode.subfield(["params", "arguments", "name"], decode.string)
    decode.success(n)
  }
  let kind_decoder = {
    use k <- decode.subfield(["params", "arguments", "kind"], decode.string)
    decode.success(k)
  }
  let input_decoder = {
    use inp <- decode.subfield(["params", "arguments", "input"], decode.string)
    decode.success(inp)
  }

  case
    json.parse(raw_line, wf_id_decoder),
    json.parse(raw_line, name_decoder),
    json.parse(raw_line, kind_decoder),
    json.parse(raw_line, input_decoder)
  {
    Ok(wf_id), Ok(name), Ok(kind), Ok(input) -> {
      case sa_plan_bridge.poka_yoke_validate_workflow(wf_id, kind) {
        Ok(Nil) -> {
          case sa_plan_bridge.start_sa_workflow(wf_id, name, kind, input) {
            Ok(out) -> tool_content_response(id, out)
            Error(err) -> tool_error_response(id, err)
          }
        }
        Error(poka_err) -> error_response(id, -32_602, poka_err)
      }
    }
    _, _, _, _ ->
      error_response(
        id,
        -32_602,
        "Missing required parameters: id, name, kind, input",
      )
  }
}

// ---------------------------------------------------------------------------
// Modular MAX / Mojo High-Utility Model Handlers (SC-INF-001)
// ---------------------------------------------------------------------------

fn tool_stpa_fmea_hazard(id: Option(json.Json), raw_line: String) -> String {
  let action_decoder = {
    use a <- decode.subfield(["params", "arguments", "action"], decode.string)
    decode.success(a)
  }
  let component_decoder = {
    use c <- decode.subfield(
      ["params", "arguments", "component"],
      decode.string,
    )
    decode.success(c)
  }
  let context_decoder = {
    use ctx <- decode.subfield(
      ["params", "arguments", "context"],
      decode.string,
    )
    decode.success(ctx)
  }
  let crit_decoder = {
    use cr <- decode.subfield(
      ["params", "arguments", "criticality"],
      decode.int,
    )
    decode.success(cr)
  }
  let dep_decoder = {
    use d <- decode.subfield(
      ["params", "arguments", "dependency_readiness"],
      decode.string,
    )
    decode.success(d)
  }
  let impact_decoder = {
    use i <- decode.subfield(["params", "arguments", "impact"], decode.int)
    decode.success(i)
  }

  let action = case json.parse(raw_line, action_decoder) {
    Ok(a) -> a
    Error(_) -> "unknown_action"
  }
  let component = case json.parse(raw_line, component_decoder) {
    Ok(c) -> c
    Error(_) -> "general"
  }
  let context = case json.parse(raw_line, context_decoder) {
    Ok(ctx) -> ctx
    Error(_) -> ""
  }
  let crit = case json.parse(raw_line, crit_decoder) {
    Ok(cr) -> cr
    Error(_) -> 3
  }
  let dep = case json.parse(raw_line, dep_decoder) {
    Ok(d) -> d
    Error(_) -> "ready"
  }
  let impact = case json.parse(raw_line, impact_decoder) {
    Ok(i) -> i
    Error(_) -> 3
  }

  let rep =
    inference_api.evaluate_stpa_fmea(
      action,
      component,
      context,
      crit,
      dep,
      impact,
    )
  tool_adapter_response(id, max_daemon.stpa_fmea_report_to_json(rep))
}

fn tool_rete_rule_conflict(id: Option(json.Json), raw_line: String) -> String {
  let rule_decoder = {
    use r_id <- decode.field("id", decode.string)
    use name <- decode.optional_field("name", "rule", decode.string)
    use layer <- decode.optional_field("layer", "L5", decode.string)
    use score <- decode.optional_field("score", 10.0, decode.float)
    use layer_rank <- decode.optional_field("layer_rank", 5, decode.int)
    use salience <- decode.optional_field("salience", 1.0, decode.float)
    use specificity <- decode.optional_field("specificity", 1, decode.int)
    use matched_conditions <- decode.optional_field(
      "matched_conditions",
      1,
      decode.int,
    )
    use action <- decode.optional_field("action", "execute", decode.string)
    decode.success(max_daemon.ReteRuleScore(
      id: r_id,
      name: name,
      layer: layer,
      score: score,
      layer_rank: layer_rank,
      salience: salience,
      specificity: specificity,
      matched_conditions: matched_conditions,
      action: action,
    ))
  }
  let rules_decoder = {
    use r <- decode.subfield(
      ["params", "arguments", "rules"],
      decode.list(rule_decoder),
    )
    decode.success(r)
  }

  let rules = case json.parse(raw_line, rules_decoder) {
    Ok(r) -> r
    Error(_) -> []
  }

  let rep = inference_api.evaluate_rete_conflict(rules)
  tool_adapter_response(id, max_daemon.rete_conflict_report_to_json(rep))
}

fn tool_ruliad_branch_eval(id: Option(json.Json), raw_line: String) -> String {
  let src_decoder = {
    use s <- decode.subfield(
      ["params", "arguments", "source_branch"],
      decode.string,
    )
    decode.success(s)
  }
  let tgt_decoder = {
    use t <- decode.subfield(
      ["params", "arguments", "target_branch"],
      decode.string,
    )
    decode.success(t)
  }
  let changes_decoder = {
    use c <- decode.subfield(
      ["params", "arguments", "candidate_changes"],
      decode.list(decode.string),
    )
    decode.success(c)
  }
  let agents_decoder = {
    use a <- decode.subfield(
      ["params", "arguments", "agents"],
      decode.list(decode.string),
    )
    decode.success(a)
  }

  let src = case json.parse(raw_line, src_decoder) {
    Ok(s) -> s
    Error(_) -> "integration/main"
  }
  let tgt = case json.parse(raw_line, tgt_decoder) {
    Ok(t) -> t
    Error(_) -> "feature/current"
  }
  let changes = case json.parse(raw_line, changes_decoder) {
    Ok(c) -> c
    Error(_) -> []
  }
  let agents = case json.parse(raw_line, agents_decoder) {
    Ok(a) -> a
    Error(_) -> ["AutonomousAgent"]
  }

  let rep = inference_api.evaluate_ruliad_branch(src, tgt, changes, agents)
  tool_adapter_response(id, max_daemon.ruliad_branch_report_to_json(rep))
}

fn tool_shruti_harmonics(id: Option(json.Json), raw_line: String) -> String {
  let raga_decoder = {
    use r <- decode.subfield(["params", "arguments", "raga"], decode.string)
    decode.success(r)
  }
  let fund_decoder = {
    use f <- decode.subfield(
      ["params", "arguments", "fundamental_hz"],
      decode.float,
    )
    decode.success(f)
  }
  let telem_decoder = {
    use t <- decode.subfield(
      ["params", "arguments", "telemetry"],
      decode.list(decode.float),
    )
    decode.success(t)
  }

  let raga = case json.parse(raw_line, raga_decoder) {
    Ok(r) -> r
    Error(_) -> "Durga"
  }
  let fund = case json.parse(raw_line, fund_decoder) {
    Ok(f) -> f
    Error(_) -> 136.1
  }
  let telem = case json.parse(raw_line, telem_decoder) {
    Ok(t) -> t
    Error(_) -> [1.0, 1.25, 1.5]
  }

  let rep = inference_api.evaluate_shruti_harmonics(telem, raga, fund)
  tool_adapter_response(id, max_daemon.shruti_harmonic_report_to_json(rep))
}

fn tool_ast_anomaly_detect(id: Option(json.Json), raw_line: String) -> String {
  let code_decoder = {
    use c <- decode.subfield(["params", "arguments", "code"], decode.string)
    decode.success(c)
  }
  let lang_decoder = {
    use l <- decode.subfield(["params", "arguments", "language"], decode.string)
    decode.success(l)
  }
  let strict_decoder = {
    use s <- decode.subfield(
      ["params", "arguments", "strict_mode"],
      decode.bool,
    )
    decode.success(s)
  }

  let code = case json.parse(raw_line, code_decoder) {
    Ok(c) -> c
    Error(_) -> ""
  }
  let lang = case json.parse(raw_line, lang_decoder) {
    Ok(l) -> l
    Error(_) -> "gleam"
  }
  let strict = case json.parse(raw_line, strict_decoder) {
    Ok(s) -> s
    Error(_) -> True
  }

  let rep = inference_api.evaluate_ast_anomaly(code, lang, strict)
  tool_adapter_response(id, max_daemon.ast_report_to_json(rep))
}

fn tool_zk_transclude(id: Option(json.Json), raw_line: String) -> String {
  let query_decoder = {
    use q <- decode.subfield(["params", "arguments", "query"], decode.string)
    decode.success(q)
  }
  let limit_decoder = {
    use l <- decode.subfield(["params", "arguments", "limit"], decode.int)
    decode.success(l)
  }

  let query = case json.parse(raw_line, query_decoder) {
    Ok(q) -> q
    Error(_) -> "sa-plan"
  }
  let limit = case json.parse(raw_line, limit_decoder) {
    Ok(l) -> l
    Error(_) -> 3
  }

  let rep = inference_api.evaluate_zk_transclusion(query, limit)
  tool_adapter_response(id, max_daemon.zk_result_to_json(rep))
}

fn tool_lyapunov_trend_predict(
  id: Option(json.Json),
  raw_line: String,
) -> String {
  let telem_decoder = {
    use t <- decode.subfield(
      ["params", "arguments", "telemetry"],
      decode.list(decode.float),
    )
    decode.success(t)
  }
  let dt_decoder = {
    use d <- decode.subfield(["params", "arguments", "dt"], decode.float)
    decode.success(d)
  }
  let horizon_decoder = {
    use h <- decode.subfield(
      ["params", "arguments", "horizon_seconds"],
      decode.float,
    )
    decode.success(h)
  }
  let thresh_decoder = {
    use cr <- decode.subfield(
      ["params", "arguments", "critical_threshold"],
      decode.float,
    )
    decode.success(cr)
  }

  let telem = case json.parse(raw_line, telem_decoder) {
    Ok(t) -> t
    Error(_) -> [1.0, 1.01, 1.02]
  }
  let dt = case json.parse(raw_line, dt_decoder) {
    Ok(d) -> d
    Error(_) -> 1.0
  }
  let horizon = case json.parse(raw_line, horizon_decoder) {
    Ok(h) -> h
    Error(_) -> 60.0
  }
  let thresh = case json.parse(raw_line, thresh_decoder) {
    Ok(cr) -> cr
    Error(_) -> 100.0
  }

  let rep = inference_api.evaluate_lyapunov_trend(telem, dt, horizon, thresh)
  tool_adapter_response(id, max_daemon.lyapunov_result_to_json(rep))
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn read_file_as_string(path: String) -> Result(String, String) {
  case erl_file_read(path) {
    Ok(bits) -> {
      case bit_array.to_string(bits) {
        Ok(s) -> Ok(s)
        Error(_) -> Error("Invalid UTF-8 in file")
      }
    }
    Error(e) -> Error(e)
  }
}

fn tool_content_response(id: Option(json.Json), text: String) -> String {
  success_response(
    id,
    json.object([
      #(
        "content",
        json.preprocessed_array([
          json.object([
            #("type", json.string("text")),
            #("text", json.string(text)),
          ]),
        ]),
      ),
    ]),
  )
}

fn tool_error_response(id: Option(json.Json), text: String) -> String {
  success_response(
    id,
    json.object([
      #("isError", json.bool(True)),
      #(
        "content",
        json.preprocessed_array([
          json.object([
            #("type", json.string("text")),
            #("text", json.string(text)),
          ]),
        ]),
      ),
    ]),
  )
}

fn adapter_failed(text: String) -> Bool {
  let error_decoder = {
    use _ <- decode.field("error", decode.dynamic)
    decode.success(True)
  }
  let ok_decoder = {
    use ok <- decode.field("ok", decode.bool)
    decode.success(!ok)
  }
  let status_decoder = {
    use status <- decode.field("status", decode.string)
    decode.success(string.lowercase(status) == "error")
  }
  case
    json.parse(text, error_decoder),
    json.parse(text, ok_decoder),
    json.parse(text, status_decoder)
  {
    Ok(True), _, _ | _, Ok(True), _ | _, _, Ok(True) -> True
    _, _, _ -> False
  }
}

fn tool_adapter_response(id: Option(json.Json), text: String) -> String {
  case adapter_failed(text) {
    True -> tool_error_response(id, text)
    False -> tool_content_response(id, text)
  }
}

fn success_response(id: Option(json.Json), result: json.Json) -> String {
  json.to_string(
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", encode_id(id)),
      #("result", result),
    ]),
  )
}

fn error_response(id: Option(json.Json), code: Int, message: String) -> String {
  json.to_string(
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", encode_id(id)),
      #(
        "error",
        json.object([
          #("code", json.int(code)),
          #("message", json.string(message)),
        ]),
      ),
    ]),
  )
}

fn encode_id(id: Option(json.Json)) -> json.Json {
  case id {
    Some(i) -> i
    None -> json.null()
  }
}

// ---------------------------------------------------------------------------
// Public API for Zenoh transport (bridge/zenoh_mcp.gleam calls these)
// ---------------------------------------------------------------------------

pub fn handle_request(
  method: String,
  id: Option(String),
  raw_line: String,
) -> Option(String) {
  dispatch(method, option.map(id, json.string), raw_line)
}

pub fn handle_request_raw(line: String) -> Option(String) {
  process_line(line)
}

// ---------------------------------------------------------------------------
// ZigVM & Hermes Harness MCP tool handlers
// ---------------------------------------------------------------------------

/// Missing runtime bindings are tool errors, never synthesized success receipts.
fn tool_unavailable(
  id: Option(json.Json),
  name: String,
  reason: String,
) -> String {
  tool_error_response(
    id,
    "UNAVAILABLE: "
      <> name
      <> " — "
      <> reason
      <> "; no action or verification was performed.",
  )
}

fn tool_control_loop(id: Option(json.Json), _raw_line: String) -> String {
  tool_unavailable(id, "control_loop", "no verified runtime binding")
}

fn tool_safety_status(id: Option(json.Json)) -> String {
  tool_unavailable(id, "safety_status", "no verified runtime binding")
}

fn tool_registry_status(id: Option(json.Json)) -> String {
  tool_unavailable(id, "registry_status", "no verified runtime binding")
}

fn tool_run_selfcheck(id: Option(json.Json), _raw_line: String) -> String {
  tool_unavailable(id, "run_selfcheck", "no verified runtime binding")
}

fn tool_run_gate(id: Option(json.Json), _raw_line: String) -> String {
  tool_unavailable(id, "run_gate", "no verified runtime binding")
}

fn tool_zk_search(id: Option(json.Json), _raw_line: String) -> String {
  tool_unavailable(id, "zk_search", "no verified runtime binding")
}

fn tool_sa_bridge_submit(id: Option(json.Json), _raw_line: String) -> String {
  tool_unavailable(id, "sa_bridge_submit", "no verified runtime binding")
}
