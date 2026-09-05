/// TUI view for MCP Server plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/mcp.{
  type McpModel, type McpTool, Errored, Running, Starting, Stopped,
}
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: McpModel) -> String {
  let header = visuals.with_color("  MCP SERVER", "cyan")
  let status = render_status(model)
  let tools = render_tools(model.tools)
  let sessions = render_sessions(model)
  string.join([header, status, "", tools, "", sessions], "\n")
}

fn render_status(model: McpModel) -> String {
  let status_text = case model.server_status {
    Running -> visuals.with_color("RUNNING", "green")
    Stopped -> visuals.with_color("STOPPED", "red")
    Starting -> visuals.with_color("STARTING", "yellow")
    Errored(reason) -> visuals.with_color("ERROR: " <> reason, "red")
  }
  "  Status: "
  <> status_text
  <> "  Sessions: "
  <> int.to_string(mcp.session_count(model))
}

fn render_tools(tools: List(McpTool)) -> String {
  "  Tools ("
  <> int.to_string(list.length(tools))
  <> "):"
  <> "\n"
  <> {
    tools
    |> list.take(10)
    |> list.map(fn(t) {
      let indicator = case t.enabled {
        True -> visuals.with_color("[ON]", "green")
        False -> visuals.with_color("[OFF]", "red")
      }
      "    " <> indicator <> " " <> t.name <> " — " <> t.description
    })
    |> string.join("\n")
  }
}

fn render_sessions(model: McpModel) -> String {
  "  Active Sessions ("
  <> int.to_string(mcp.session_count(model))
  <> "):"
  <> "\n"
  <> {
    model.active_sessions
    |> list.take(5)
    |> list.map(fn(s) {
      "    "
      <> visuals.with_color(s.id, "blue")
      <> " client="
      <> s.client
      <> " started="
      <> int.to_string(s.started_at)
    })
    |> string.join("\n")
  }
}
