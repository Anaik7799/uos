//// AG-UI Event Stream Widget — Isomorphic real-time event log.
////
//// Renders a scrolling event stream for both Web (Lustre HTML) and TUI (ANSI).
//// Shows the last N AG-UI events with type, timestamp, and payload preview.
//// Used by Dashboard, Agents, and Cockpit pages.
////
//// STAMP: SC-AGUI-002, SC-GLM-UI-001, SC-ULTRA-001 #4

import cepaf_gleam/cockpit/visuals
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// A captured AG-UI event for display.
pub type StreamEvent {
  StreamEvent(
    event_type: String,
    timestamp: String,
    preview: String,
    severity: String,
  )
}

/// Create demo events showing a typical AG-UI lifecycle.
pub fn demo_events() -> List(StreamEvent) {
  [
    StreamEvent(
      "RunStarted",
      "01:42:10.496",
      "thread=c3i-main run=ooda-42",
      "info",
    ),
    StreamEvent("StepStarted", "01:42:10.497", "phase=observe", "info"),
    StreamEvent(
      "StateSnapshot",
      "01:42:10.498",
      "health=100% containers=16/16",
      "healthy",
    ),
    StreamEvent(
      "ToolCallStart",
      "01:42:10.499",
      "tool=system_health args={}",
      "info",
    ),
    StreamEvent(
      "ToolCallEnd",
      "01:42:10.501",
      "result={\"status\":\"ok\"}",
      "healthy",
    ),
    StreamEvent("ReasoningStart", "01:42:10.502", "OODA orient phase", "info"),
    StreamEvent(
      "TextMessageContent",
      "01:42:10.505",
      "No drift detected. Mesh aligned.",
      "healthy",
    ),
    StreamEvent(
      "StateDelta",
      "01:42:10.506",
      "ooda_phase: observe -> orient",
      "info",
    ),
    StreamEvent(
      "StepFinished",
      "01:42:10.507",
      "phase=observe duration=11ms",
      "healthy",
    ),
    StreamEvent("Heartbeat", "01:42:10.510", "seq=256 interval=10s", "dim"),
    StreamEvent(
      "RunFinished",
      "01:42:10.511",
      "decision=NoAction reason=aligned",
      "healthy",
    ),
  ]
}

/// Render the event stream as Lustre HTML (for Web UI).
pub fn render_html(events: List(StreamEvent), max_events: Int) -> Element(msg) {
  let visible = list.take(events, max_events)
  html.div([attribute.class("section")], [
    html.div([attribute.class("section-title")], [
      element.text("AG-UI Event Stream (Live)"),
    ]),
    html.div(
      [
        attribute.attribute(
          "style",
          "max-height:300px;overflow-y:auto;background:#0a0e17;border:1px solid #1e2a3a;border-radius:4px;padding:8px;font-family:monospace;font-size:.78rem;",
        ),
      ],
      list.map(visible, fn(evt) {
        let color_class = case evt.severity {
          "healthy" -> "status-healthy"
          "critical" -> "status-critical"
          "warning" | "degraded" -> "status-degraded"
          "dim" -> "status-unknown"
          _ -> ""
        }
        html.div(
          [
            attribute.attribute(
              "style",
              "padding:2px 0;border-bottom:1px solid #0d1420;",
            ),
          ],
          [
            html.span(
              [attribute.attribute("style", "color:#7a8fa6;margin-right:8px;")],
              [element.text(evt.timestamp)],
            ),
            html.span(
              [
                attribute.class(color_class),
                attribute.attribute(
                  "style",
                  "margin-right:8px;font-weight:600;",
                ),
              ],
              [element.text(evt.event_type)],
            ),
            html.span([attribute.attribute("style", "color:#a6accd;")], [
              element.text(evt.preview),
            ]),
          ],
        )
      }),
    ),
  ])
}

/// Render the event stream as ANSI text (for TUI).
pub fn render_ansi(events: List(StreamEvent), max_events: Int) -> String {
  let header = visuals.with_color("  AG-UI EVENT STREAM (Live)", "cyan")
  let visible = list.take(events, max_events)
  let lines =
    list.index_map(visible, fn(evt, i) {
      let connector = case i == list.length(visible) - 1 {
        True -> "└─"
        False -> "├─"
      }
      let type_color = case evt.severity {
        "healthy" -> "green"
        "critical" -> "red"
        "degraded" | "warning" -> "yellow"
        _ -> "dim"
      }
      "  "
      <> visuals.with_color(connector, "dim")
      <> " "
      <> visuals.with_color(evt.timestamp, "dim")
      <> " "
      <> visuals.with_color(pad_right_simple(evt.event_type, 20), type_color)
      <> " "
      <> evt.preview
    })
    |> string.join("\n")
  let count_line =
    "  "
    <> visuals.with_color(
      int.to_string(list.length(events)) <> " events total",
      "dim",
    )
  header <> "\n" <> lines <> "\n" <> count_line
}

fn pad_right_simple(text: String, width: Int) -> String {
  let len = string.length(text)
  case len >= width {
    True -> string.slice(text, 0, width)
    False -> text <> string.repeat(" ", width - len)
  }
}
