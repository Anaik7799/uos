/// TUI renderer for c3i terminal interface (SC-GLM-UI-001, SC-GLM-UI-004).
/// Renders ANSI terminal output using cockpit/visuals.gleam primitives.
/// Supports the same command set as Wisp API (SC-GLM-UI-007).
/// Render target: 16ms per frame (60fps terminal refresh — AOR-GLM-UI-008).
///
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/domain.{
  type HealthStatus, type Page, type RenderContext, type TelemetryPoint,
  Critical, Dashboard, Degraded, Healthy, Unknown, page_to_label,
}
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Dark Cockpit 5-Mode State Machine (SC-HMI-010)
// ---------------------------------------------------------------------------

pub type CockpitMode {
  Dark
  Dim
  Normal
  Bright
  Emergency
}

/// Determine cockpit mode from health status (SC-HMI-010).
pub fn determine_mode(health: HealthStatus, threat_count: Int) -> CockpitMode {
  case health {
    Healthy ->
      case threat_count > 0 {
        True -> Dim
        False -> Dark
      }
    Degraded(_) -> Normal
    Critical(_) ->
      case threat_count > 3 {
        True -> Emergency
        False -> Bright
      }
    Unknown -> Dim
  }
}

/// Get header color for the current cockpit mode.
fn mode_header_color(mode: CockpitMode) -> String {
  case mode {
    Dark -> "dim"
    Dim -> "yellow"
    Normal -> "cyan"
    Bright -> "white"
    Emergency -> "red"
  }
}

/// Get mode label for status bar display.
pub fn mode_label(mode: CockpitMode) -> String {
  case mode {
    Dark -> "DARK"
    Dim -> "DIM"
    Normal -> "NORMAL"
    Bright -> "BRIGHT"
    Emergency -> "EMERGENCY"
  }
}

// ---------------------------------------------------------------------------
// Frame renderer
// ---------------------------------------------------------------------------

/// Render a full TUI frame for the given context.
pub fn render_frame(ctx: RenderContext) -> String {
  let mode = determine_mode(ctx.health, 0)
  let header = render_header(ctx, mode)
  let health_line = render_health(ctx.health)
  let zenoh_line = render_zenoh_status(ctx.zenoh_connected)
  let mode_line =
    "  MODE: " <> visuals.with_color(mode_label(mode), mode_header_color(mode))
  let ooda_line = "  OODA: " <> visuals.render_ooda_ring("observe")
  let status_strip =
    "  "
    <> visuals.render_status_strip([
      #("Mesh", "healthy"),
      #("Quorum", "healthy"),
      #("Guardian", "ok"),
      #("Immune", "healthy"),
    ])
  let telemetry = render_telemetry(ctx.telemetry)
  let heatmap =
    visuals.render_fractal_heatmap([
      #("L0 Constitutional", 1.0),
      #("L1 Atomic/Debug", 0.95),
      #("L2 Component", 0.92),
      #("L3 Transaction", 0.88),
      #("L4 System", 0.9),
      #("L5 Cognitive", 0.85),
      #("L6 Ecosystem", 0.78),
      #("L7 Federation", 0.65),
    ])
  let nav = render_navigation(ctx.page)

  string.join(
    [
      header, health_line, zenoh_line, mode_line, ooda_line, status_strip, "",
      telemetry, "", heatmap, "", nav,
    ],
    "\n",
  )
}

/// Top header bar with page title — color varies by cockpit mode.
fn render_header(ctx: RenderContext, mode: CockpitMode) -> String {
  let title = page_to_label(ctx.page)
  let color = mode_header_color(mode)
  let bar = string.repeat("─", 60)
  let pad_len = case 55 - string.length(title) {
    n if n > 0 -> n
    _ -> 1
  }
  visuals.with_color("┌" <> bar <> "┐", color)
  <> "\n"
  <> visuals.with_color("│ c3i " <> title, color)
  <> string.repeat(" ", pad_len)
  <> visuals.with_color("│", color)
  <> "\n"
  <> visuals.with_color("└" <> bar <> "┘", color)
}

/// Health status line with color coding.
fn render_health(status: HealthStatus) -> String {
  case status {
    Healthy -> visuals.with_color("  HEALTH: OK", "green")
    Degraded(reason) ->
      visuals.with_color("  HEALTH: DEGRADED — " <> reason, "yellow")
    Critical(reason) ->
      visuals.with_color("  HEALTH: CRITICAL — " <> reason, "red")
    Unknown -> visuals.with_color("  HEALTH: UNKNOWN", "magenta")
  }
}

/// Zenoh connection status.
fn render_zenoh_status(connected: Bool) -> String {
  case connected {
    True -> visuals.with_color("  ZENOH: CONNECTED", "green")
    False -> visuals.with_color("  ZENOH: DISCONNECTED", "red")
  }
}

/// Telemetry sparkline from recent data points.
fn render_telemetry(points: List(TelemetryPoint)) -> String {
  case points {
    [] -> "  TELEMETRY: (no data)"
    _ -> {
      let values = list.map(points, fn(p) { p.value })
      let sparkline = visuals.render_sparkline(values)
      "  TELEMETRY: "
      <> sparkline
      <> " ("
      <> int.to_string(list.length(points))
      <> " pts)"
    }
  }
}

/// Navigation bar showing all 30 pages across 3 rows.
fn render_navigation(current: Page) -> String {
  let row1 = [
    Dashboard, domain.Planning, domain.Immune, domain.Knowledge, domain.Zenoh,
    domain.Cockpit, domain.Verification, domain.Substrate, domain.Metabolic,
    domain.Podman,
  ]
  let row2 = [
    domain.Mcp, domain.Kms, domain.Telemetry, domain.Federation,
    domain.HealthGrid, domain.Prajna, domain.Agents, domain.Holon, domain.Config,
    domain.Git,
  ]
  let row3 = [
    domain.Database, domain.Bridge, domain.Smriti, domain.PlanningDashboard,
    domain.Integrity, domain.Evolution, domain.Biomorphic,
    domain.HomeostasisPage, domain.Bicameral, domain.Singularity,
  ]
  let render_row = fn(pages) {
    let tabs =
      list.map(pages, fn(p) {
        let label = page_to_label(p)
        case p == current {
          True -> visuals.with_color("[" <> label <> "]", "cyan")
          False -> " " <> label <> " "
        }
      })
    "  " <> string.join(tabs, "|")
  }
  string.join([render_row(row1), render_row(row2), render_row(row3)], "\n")
}
