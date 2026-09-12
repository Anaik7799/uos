//// TUI view for Heartbeat (SC-GLM-UI-001, SC-GLM-UI-004).
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-HA-001

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/heartbeat_page.{type HeartbeatModel}
import gleam/float
import gleam/int
import gleam/string

pub fn render(model: HeartbeatModel) -> String {
  let header = visuals.with_color("  HEARTBEAT MONITOR", "cyan")
  let alive_str = case model.rust_alive {
    True -> visuals.with_color("ALIVE", "green")
    False -> visuals.with_color("DEAD", "red")
  }
  let failover_str = case model.failover_active {
    True -> visuals.with_color("  FAILOVER ACTIVE", "yellow")
    False -> ""
  }
  let status =
    "  Rust Daemon: "
    <> alive_str
    <> failover_str
  let metrics =
    "  Pings: "
    <> int.to_string(model.total_pings)
    <> "  Pongs: "
    <> int.to_string(model.total_pongs)
    <> "  Failures: "
    <> int.to_string(model.consecutive_failures)
  let health_bar = render_health_bar(model.health_score)
  let status_strip =
    "  "
    <> visuals.render_status_strip([
      #("Daemon", case model.rust_alive {
        True -> "healthy"
        False -> "critical"
      }),
      #("NIF", case model.failover_active {
        True -> "warning"
        False -> "healthy"
      }),
      #("Failover", case model.failover_active {
        True -> "info"
        False -> "healthy"
      }),
    ])
  string.join([header, status, metrics, health_bar, status_strip], "\n")
}

fn render_health_bar(health: Float) -> String {
  let pct = health *. 100.0
  let filled = health *. 20.0
  let filled_int = float.round(filled)
  let empty_int = 20 - filled_int
  "  Health: ["
  <> string.repeat("█", filled_int)
  <> string.repeat("░", empty_int)
  <> "] "
  <> int.to_string(float.round(pct))
  <> "%"
}
