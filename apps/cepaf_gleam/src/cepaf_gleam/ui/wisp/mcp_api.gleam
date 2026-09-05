/// Wisp API for MCP Server plane (SC-GLM-UI-001, SC-GLM-UI-003).
/// Typed JSON via gleam/json — no raw strings (SC-GLM-UI-003).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007
import cepaf_gleam/mcp/protocol.{type ToolDefinition}
import gleam/json
import gleam/list

/// Full MCP server status JSON with tools list and active sessions.
pub fn status_json(
  server_status: String,
  tools: List(ToolDefinition),
  active_sessions: Int,
) -> String {
  json.object([
    #("plane", json.string("mcp")),
    #("server_status", json.string(server_status)),
    #("active_sessions", json.int(active_sessions)),
    #("tool_count", json.int(list.length(tools))),
    #("tools", json.array(tools, encode_tool)),
  ])
  |> json.to_string()
}

/// Compact tools listing for MCP plane.
pub fn tools_json(tools: List(ToolDefinition)) -> String {
  json.object([
    #("plane", json.string("mcp")),
    #("tool_count", json.int(list.length(tools))),
    #("tools", json.array(tools, encode_tool)),
  ])
  |> json.to_string()
}

fn encode_tool(tool: ToolDefinition) -> json.Json {
  json.object([
    #("name", json.string(tool.name)),
    #("description", json.string(tool.description)),
  ])
}
