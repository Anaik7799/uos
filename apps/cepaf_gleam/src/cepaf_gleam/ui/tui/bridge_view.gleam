/// TUI view for Bridge/MCP plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/bridge.{type BridgeModel}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: BridgeModel) -> String {
  let header = visuals.with_color("  BRIDGE / MCP", "cyan")
  let methods = render_methods(model)
  let commands = render_commands(model)
  let impl_pct = render_implementation(model)
  string.join([header, methods, commands, impl_pct], "\n")
}

fn render_methods(model: BridgeModel) -> String {
  let count = list.length(model.jsonrpc_methods)
  "  JSON-RPC Methods: " <> visuals.with_color(int.to_string(count), "blue")
}

fn render_commands(model: BridgeModel) -> String {
  "  Commands: "
  <> visuals.with_color("Total:" <> int.to_string(model.commands_total), "blue")
  <> " "
  <> visuals.with_color(
    "Impl:" <> int.to_string(model.commands_implemented),
    "green",
  )
  <> " "
  <> visuals.with_color("Stub:" <> int.to_string(model.commands_stub), "yellow")
}

fn render_implementation(model: BridgeModel) -> String {
  let pct = bridge.implementation_percent(model)
  let pct_int = float.round(pct)
  let color = case pct {
    p if p >=. 80.0 -> "green"
    p if p >=. 50.0 -> "yellow"
    _ -> "red"
  }
  "  Implementation: "
  <> visuals.with_color(int.to_string(pct_int) <> "%", color)
}
