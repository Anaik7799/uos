/// Lustre component for MCP Server plane (SC-GLM-UI-001).
/// Manages MCP tools, active sessions, and server status.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import gleam/list

pub type McpModel {
  McpModel(
    tools: List(McpTool),
    active_sessions: List(McpSession),
    server_status: ServerStatus,
  )
}

pub type McpTool {
  McpTool(name: String, description: String, enabled: Bool)
}

pub type McpSession {
  McpSession(id: String, client: String, started_at: Int)
}

pub type ServerStatus {
  Running
  Stopped
  Starting
  Errored(reason: String)
}

pub type McpMsg {
  ToolsLoaded(List(McpTool))
  SessionStarted(McpSession)
  SessionEnded(String)
  RefreshMcp
}

pub fn init() -> McpModel {
  McpModel(tools: [], active_sessions: [], server_status: Stopped)
}

pub fn update(model: McpModel, msg: McpMsg) -> McpModel {
  case msg {
    ToolsLoaded(tools) -> McpModel(..model, tools: tools)
    SessionStarted(session) ->
      McpModel(..model, active_sessions: [session, ..model.active_sessions])
    SessionEnded(id) ->
      McpModel(
        ..model,
        active_sessions: list.filter(model.active_sessions, fn(s) { s.id != id }),
      )
    RefreshMcp -> model
  }
}

pub fn enabled_tools(model: McpModel) -> List(McpTool) {
  list.filter(model.tools, fn(t) { t.enabled })
}

pub fn session_count(model: McpModel) -> Int {
  list.length(model.active_sessions)
}
