/// TUI view for Database plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/database.{type DatabaseModel}
import gleam/float
import gleam/int
import gleam/string

pub fn render(model: DatabaseModel) -> String {
  let header = visuals.with_color("  DATABASE", "cyan")
  let types = render_types(model)
  let connections = render_connections(model)
  let queries = render_queries(model)
  let latency = render_latency(model)
  let health = render_health(model)
  string.join([header, types, connections, queries, latency, health], "\n")
}

fn render_types(model: DatabaseModel) -> String {
  "  Supported: " <> string.join(model.supported_types, ", ")
}

fn render_connections(model: DatabaseModel) -> String {
  let color = case model.active_connections {
    0 -> "red"
    _ -> "green"
  }
  "  Active Connections: "
  <> visuals.with_color(int.to_string(model.active_connections), color)
}

fn render_queries(model: DatabaseModel) -> String {
  let fail_color = case model.failed_queries {
    0 -> "green"
    _ -> "red"
  }
  "  Queries: "
  <> int.to_string(model.total_queries)
  <> "  Failed: "
  <> visuals.with_color(int.to_string(model.failed_queries), fail_color)
}

fn render_latency(model: DatabaseModel) -> String {
  let color = case model.avg_latency {
    l if l <. 50.0 -> "green"
    l if l <. 100.0 -> "yellow"
    _ -> "red"
  }
  "  Avg Latency: "
  <> visuals.with_color(float.to_string(model.avg_latency) <> " ms", color)
}

fn render_health(model: DatabaseModel) -> String {
  let healthy = database.is_healthy(model)
  case healthy {
    True -> "  Health: " <> visuals.with_color("HEALTHY", "green")
    False -> "  Health: " <> visuals.with_color("DEGRADED", "red")
  }
}
