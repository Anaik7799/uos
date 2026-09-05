/// TUI view for Substrate plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/substrate.{type DbConnection, type SubstrateModel}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

pub fn render(model: SubstrateModel) -> String {
  let header = visuals.with_color("  SUBSTRATE", "cyan")
  let governor = render_governor(model)
  let connections = render_connections(model.db_connections)
  let file_ops = render_file_ops(model)
  string.join([header, governor, "", connections, "", file_ops], "\n")
}

fn render_governor(model: SubstrateModel) -> String {
  case model.governor_action {
    Some(action) ->
      "  Governor: "
      <> visuals.with_color(action.name, "green")
      <> "  State: "
      <> action.state
      <> "  T: "
      <> int.to_string(action.timestamp)
    None -> "  Governor: " <> visuals.with_color("NONE", "yellow")
  }
}

fn render_connections(conns: List(DbConnection)) -> String {
  let active = list.filter(conns, fn(c) { c.status == "active" }) |> list.length
  let total = list.length(conns)
  "  DB Connections: "
  <> visuals.with_color(int.to_string(active), "green")
  <> "/"
  <> int.to_string(total)
  <> " active"
  <> "\n"
  <> {
    conns
    |> list.take(8)
    |> list.map(fn(c) {
      let color = case c.status {
        "active" -> "green"
        "idle" -> "yellow"
        _ -> "red"
      }
      "    "
      <> visuals.with_color("[" <> c.status <> "]", color)
      <> " "
      <> c.id
      <> " "
      <> c.database
      <> " "
      <> int.to_string(c.latency_ms)
      <> "ms"
    })
    |> string.join("\n")
  }
}

fn render_file_ops(model: SubstrateModel) -> String {
  "  File Ops ("
  <> int.to_string(list.length(model.file_ops))
  <> "):"
  <> "\n"
  <> {
    model.file_ops
    |> list.take(5)
    |> list.map(fn(op) {
      let color = case op.status {
        "completed" -> "green"
        "pending" -> "yellow"
        _ -> "red"
      }
      "    " <> visuals.with_color(op.operation, color) <> " " <> op.path
    })
    |> string.join("\n")
  }
}
