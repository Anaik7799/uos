/// TUI view for Telemetry plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/telemetry.{type TelemetryModel}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: TelemetryModel) -> String {
  let header = visuals.with_color("  TELEMETRY", "cyan")
  let summary = render_summary(model)
  let spans = render_spans(model)
  let metrics = render_metrics(model)
  string.join([header, summary, "", spans, "", metrics], "\n")
}

fn render_summary(model: TelemetryModel) -> String {
  let level = telemetry.log_level_to_string(model.log_level)
  "  Log Level: "
  <> visuals.with_color(level, "blue")
  <> "  Active Traces: "
  <> int.to_string(model.active_traces)
  <> "  Spans: "
  <> int.to_string(list.length(model.spans))
  <> "  Metrics: "
  <> int.to_string(list.length(model.metrics))
}

fn render_spans(model: TelemetryModel) -> String {
  "  Recent Spans:"
  <> "\n"
  <> {
    telemetry.recent_spans(model, 8)
    |> list.map(fn(s) {
      let color = case s.status {
        "ok" -> "green"
        "error" -> "red"
        _ -> "yellow"
      }
      "    "
      <> visuals.with_color("[" <> s.status <> "]", color)
      <> " "
      <> s.name
      <> " "
      <> int.to_string(s.duration_us)
      <> "us"
      <> " trace="
      <> s.trace_id
    })
    |> string.join("\n")
  }
}

fn render_metrics(model: TelemetryModel) -> String {
  "  Metrics:"
  <> "\n"
  <> {
    model.metrics
    |> list.take(10)
    |> list.map(fn(m) {
      "    "
      <> visuals.with_color(m.name, "cyan")
      <> " = "
      <> float.to_string(m.value)
      <> " "
      <> m.unit
    })
    |> string.join("\n")
  }
}
