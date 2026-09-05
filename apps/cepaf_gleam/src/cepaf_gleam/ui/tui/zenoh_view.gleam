/// TUI view for Zenoh Mesh plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// Enhanced with OTel span display, message rate visualization,
/// subscription health monitoring, and control message display.
///
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/zenoh_mesh.{type ZenohModel}
import cepaf_gleam/ui/zenoh_otel.{type OtelSpan}
import cepaf_gleam/zenoh/domain.{Connected, Connecting, Disconnected}
import gleam/int
import gleam/list
import gleam/string

/// Extended Zenoh TUI model with OTel and control message data.
pub type ZenohTuiModel {
  ZenohTuiModel(
    zenoh_model: ZenohModel,
    recent_spans: List(OtelSpan),
    control_messages: List(String),
    message_rate_history: List(Int),
  )
}

pub fn render(model: ZenohModel) -> String {
  let header = visuals.with_color("  ZENOH MESH", "cyan")
  let status = render_status(model)
  let stats = render_stats(model)
  let is_connected = case model.health.status {
    Connected -> True
    _ -> False
  }
  let topology = visuals.render_mesh_topology(3, is_connected, 16, 16)
  let subs = render_subscriptions(model.subscriptions)
  string.join([header, status, stats, "", topology, "", subs], "\n")
}

fn render_status(model: ZenohModel) -> String {
  let status_text = case model.health.status {
    Connected -> visuals.with_color("CONNECTED", "green")
    Disconnected -> visuals.with_color("DISCONNECTED", "red")
    Connecting -> visuals.with_color("CONNECTING", "yellow")
    domain.Error(msg) -> visuals.with_color("ERROR: " <> msg, "red")
  }
  "  Status: " <> status_text <> "  Session: " <> model.health.session_id
}

fn render_stats(model: ZenohModel) -> String {
  "  Pub: "
  <> int.to_string(model.health.messages_published)
  <> "  Recv: "
  <> int.to_string(model.health.messages_received)
  <> "  Errors: "
  <> int.to_string(model.health.error_count)
  <> "  Reconnects: "
  <> int.to_string(model.health.reconnect_count)
}

fn render_subscriptions(topics: List(String)) -> String {
  "  Subscriptions ("
  <> int.to_string(list.length(topics))
  <> "):"
  <> "\n"
  <> {
    topics
    |> list.take(8)
    |> list.map(fn(t) { "    " <> visuals.with_color(t, "blue") })
    |> string.join("\n")
  }
}

// ---------------------------------------------------------------------------
// Extended TUI rendering with OTel and control messages
// ---------------------------------------------------------------------------

/// Render the full extended Zenoh TUI view.
pub fn render_extended(model: ZenohTuiModel) -> String {
  let base = render(model.zenoh_model)
  let otel_section = render_otel_spans(model.recent_spans)
  let rate_section = render_message_rate(model.message_rate_history)
  let ctrl_section = render_control_messages(model.control_messages)
  let sub_health = render_subscription_health(model.zenoh_model)

  string.join(
    [base, "", otel_section, "", rate_section, "", sub_health, "", ctrl_section],
    "\n",
  )
}

/// Render OTel spans section.
fn render_otel_spans(spans: List(OtelSpan)) -> String {
  let header = visuals.with_color("  OTel Spans (Recent)", "magenta")
  case spans {
    [] -> header <> "\n    No spans recorded"
    _ -> {
      let span_lines =
        spans
        |> list.take(5)
        |> list.map(fn(span) {
          let phase_color = ooda_phase_color(span.ooda_phase)
          "    ["
          <> visuals.with_color(
            zenoh_otel.ooda_phase_to_string(span.ooda_phase),
            phase_color,
          )
          <> "] "
          <> span.name
          <> " ("
          <> int.to_string(span.duration_us)
          <> "us)"
        })
      string.join([header, ..span_lines], "\n")
    }
  }
}

/// Render message rate visualization as a sparkline.
fn render_message_rate(history: List(Int)) -> String {
  let header = visuals.with_color("  Message Rate", "yellow")
  case history {
    [] -> header <> "\n    No data"
    _ -> {
      let sparkline = build_sparkline(history)
      let current = case list.last(history) {
        Ok(n) -> int.to_string(n)
        Error(_) -> "0"
      }
      header <> "\n    " <> sparkline <> " (current: " <> current <> " msg/s)"
    }
  }
}

/// Build a simple ASCII sparkline from rate history.
fn build_sparkline(values: List(Int)) -> String {
  case values {
    [] -> ""
    _ -> {
      let max_val =
        list_fold(values, 0, fn(acc, v) {
          case v > acc {
            True -> v
            False -> acc
          }
        })
      values
      |> list.map(fn(v) { spark_char(v, max_val) })
      |> string.join("")
    }
  }
}

fn spark_char(value: Int, max_val: Int) -> String {
  case max_val {
    0 -> "▁"
    _ -> {
      let level = value * 7 / max_val
      case level {
        0 -> "▁"
        1 -> "▂"
        2 -> "▃"
        3 -> "▄"
        4 -> "▅"
        5 -> "▆"
        6 -> "▇"
        _ -> "█"
      }
    }
  }
}

fn list_fold(items: List(a), init: b, folder: fn(b, a) -> b) -> b {
  case items {
    [] -> init
    [x, ..rest] -> list_fold(rest, folder(init, x), folder)
  }
}

/// Render subscription health monitoring.
fn render_subscription_health(model: ZenohModel) -> String {
  let header = visuals.with_color("  Subscription Health", "cyan")
  let total = list.length(model.subscriptions)
  let health_indicator = case model.health.status {
    Connected -> visuals.with_color("HEALTHY", "green")
    Disconnected -> visuals.with_color("DEGRADED", "red")
    Connecting -> visuals.with_color("SYNCING", "yellow")
    domain.Error(_) -> visuals.with_color("ERROR", "red")
  }
  header
  <> "\n    Topics: "
  <> int.to_string(total)
  <> "  Status: "
  <> health_indicator
  <> "  Errors: "
  <> int.to_string(model.health.error_count)
}

/// Render control messages section.
fn render_control_messages(messages: List(String)) -> String {
  let header = visuals.with_color("  Control Messages", "white")
  case messages {
    [] -> header <> "\n    No control messages"
    _ -> {
      let msg_lines =
        messages
        |> list.take(5)
        |> list.map(fn(m) { "    > " <> m })
      string.join([header, ..msg_lines], "\n")
    }
  }
}

/// Get color for OODA phase display.
fn ooda_phase_color(phase: zenoh_otel.OodaPhase) -> String {
  case phase {
    zenoh_otel.Observe -> "blue"
    zenoh_otel.Orient -> "yellow"
    zenoh_otel.Decide -> "magenta"
    zenoh_otel.Act -> "green"
  }
}
