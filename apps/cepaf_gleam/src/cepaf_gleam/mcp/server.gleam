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
import cepaf_gleam/mcp/protocol.{type ToolDefinition}
import cepaf_gleam/mcp/tools
import cepaf_gleam/ui/wisp/router as wisp_router
import gleam/dynamic/decode
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

fn execute_tool(
  name: String,
  id: Option(json.Json),
  raw_line: String,
) -> String {
  case tools.unavailable_reason(name) {
    Some(reason) -> tool_unavailable(id, name, reason)
    None -> execute_available_tool(name, id, raw_line)
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
    "plan_add" -> tool_plan_add(id, raw_line)
    "plan_update" -> tool_plan_update(id, raw_line)
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn read_file_as_string(path: String) -> Result(String, String) {
  case erl_file_read(path) {
    Ok(bits) -> {
      case bit_array_to_string(bits) {
        Ok(s) -> Ok(s)
        Error(_) -> Error("Invalid UTF-8 in file")
      }
    }
    Error(e) -> Error(e)
  }
}

@external(erlang, "gleam_stdlib", "identity")
fn bit_array_to_string(bits: BitArray) -> Result(String, Nil)

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
