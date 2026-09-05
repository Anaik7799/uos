import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub fn with_color(text: String, color: String) -> String {
  let code = case color {
    "green" -> "\u{001b}[32m"
    "red" -> "\u{001b}[31m"
    "yellow" -> "\u{001b}[33m"
    "blue" -> "\u{001b}[34m"
    "cyan" -> "\u{001b}[36m"
    "magenta" -> "\u{001b}[35m"
    "white" -> "\u{001b}[37m"
    "dim" -> "\u{001b}[90m"
    "bold" -> "\u{001b}[1m"
    _ -> ""
  }

  case code {
    "" -> text
    _ -> code <> text <> "\u{001b}[0m"
  }
}

pub fn render_progress_bar(percent: Float, width: Int) -> String {
  let filled_width = float.round(percent *. int.to_float(width))
  let empty_width = width - filled_width

  let color = case percent {
    p if p >=. 0.8 -> "green"
    p if p >=. 0.5 -> "yellow"
    _ -> "red"
  }

  let bar =
    "["
    <> string.repeat("=", filled_width)
    <> string.repeat(" ", empty_width)
    <> "]"
  with_color(bar, color)
}

pub fn render_sparkline(data: List(Float)) -> String {
  // Unicode block characters for sparklines:  ▂▃▄▅▆▇█
  let blocks = [" ", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

  let max_val = list.fold(data, 0.0, float.max)

  list.map(data, fn(v) {
    let index = case max_val >. 0.0 {
      True -> float.round(v /. max_val *. 7.0)
      False -> 0
    }
    case list.drop(blocks, index) |> list.first {
      Ok(b) -> b
      Error(_) -> " "
    }
  })
  |> string.join("")
}

/// Render a box-drawing table with headers and rows.
pub fn render_table(
  headers: List(String),
  rows: List(List(String)),
  col_widths: List(Int),
) -> String {
  let sep = render_table_separator(col_widths)
  let header_line = render_table_row(headers, col_widths)
  let row_lines =
    list.map(rows, fn(row) { render_table_row(row, col_widths) })
    |> string.join("\n")

  sep
  <> "\n"
  <> with_color(header_line, "cyan")
  <> "\n"
  <> sep
  <> "\n"
  <> row_lines
  <> "\n"
  <> sep
}

fn render_table_separator(col_widths: List(Int)) -> String {
  "+"
  <> {
    list.map(col_widths, fn(w) { string.repeat("─", w + 2) })
    |> string.join("+")
  }
  <> "+"
}

fn render_table_row(cells: List(String), col_widths: List(Int)) -> String {
  let pairs = list.zip(cells, col_widths)
  "│"
  <> {
    list.map(pairs, fn(pair) {
      let #(cell, width) = pair
      " " <> pad_right(cell, width) <> " "
    })
    |> string.join("│")
  }
  <> "│"
}

fn pad_right(text: String, width: Int) -> String {
  let len = string.length(text)
  case len >= width {
    True -> string.slice(text, 0, width)
    False -> text <> string.repeat(" ", width - len)
  }
}

/// Render a status badge with ANSI background color.
pub fn render_badge(label: String, variant: String) -> String {
  let bg = case variant {
    "healthy" | "ok" | "pass" -> "\u{001b}[42m"
    "degraded" | "warning" -> "\u{001b}[43m"
    "critical" | "error" | "fail" -> "\u{001b}[41m"
    "info" -> "\u{001b}[44m"
    _ -> "\u{001b}[100m"
  }
  bg <> "\u{001b}[30m " <> label <> " \u{001b}[0m"
}

/// Render an OODA ring showing the current phase.
pub fn render_ooda_ring(phase: String) -> String {
  let phases = ["observe", "orient", "decide", "act"]
  list.map(phases, fn(p) {
    case p == phase {
      True -> with_color("●" <> p, "green")
      False -> with_color("○" <> p, "dim")
    }
  })
  |> string.join(" → ")
}

/// Render a key-value row with aligned columns.
pub fn render_kv_row(key: String, value: String, key_width: Int) -> String {
  with_color(pad_right(key, key_width), "cyan") <> " : " <> value
}

/// Render the OODA 5-Tier Decision Brain for TUI.
/// Shows nested tiers: Agent → Intelligence → Knowledge → Cortex → Strategy
/// with latency budgets and active phase highlighting.
pub fn render_ooda_5tier(
  decision: String,
  reason: String,
  active_phase: String,
) -> String {
  let header = with_color("  ╔═══ OODA DECISION BRAIN ═══╗", "cyan")
  let tiers = [
    #("Agent", "30ms", active_phase == "observe" || active_phase == "act"),
    #("Intelligence", "100ms", active_phase == "orient"),
    #("Knowledge", "1ms", True),
    #("Cortex", "50ms", active_phase == "decide"),
    #("Strategy", "1000ms", active_phase == "observe"),
  ]
  let tier_lines =
    list.map(tiers, fn(tier) {
      let #(name, budget, active) = tier
      let icon = case active {
        True -> with_color("◉", "green")
        False -> with_color("◯", "dim")
      }
      let name_str = case active {
        True -> with_color(pad_right(name, 14), "green")
        False -> with_color(pad_right(name, 14), "dim")
      }
      let budget_str = with_color("<" <> budget, "dim")
      "  " <> icon <> " " <> name_str <> " " <> budget_str
    })
    |> string.join("\n")
  let decision_line =
    "  Decision: " <> with_color(decision, "yellow") <> " — " <> reason
  let footer = with_color("  ╚══════════════════════════════╝", "cyan")
  string.join([header, tier_lines, decision_line, footer], "\n")
}

/// Render a 16-container Zenoh mesh topology as ASCII art.
/// Shows 3 Zenoh routers at center, 13 containers radiating outward.
pub fn render_mesh_topology(
  routers: Int,
  connected: Bool,
  container_count: Int,
  healthy_count: Int,
) -> String {
  let router_icon = case connected {
    True -> with_color("◆", "green")
    False -> with_color("◇", "red")
  }
  let alive = with_color("●", "green")
  let dead = with_color("○", "red")
  let wire = case connected {
    True -> with_color("─", "dim")
    False -> with_color("╌", "red")
  }

  // Build a simple mesh diagram
  let r_row = case routers {
    r if r >= 3 ->
      "          "
      <> router_icon
      <> wire
      <> wire
      <> wire
      <> router_icon
      <> wire
      <> wire
      <> wire
      <> router_icon
    r if r >= 1 -> "              " <> router_icon
    _ -> "              " <> with_color("◇", "red")
  }
  let r_label =
    "        "
    <> with_color("Zenoh Router Mesh", "cyan")
    <> " ("
    <> int.to_string(routers)
    <> " active)"

  // Container ring — show healthy/dead ratio
  let containers_per_row = 8
  let row1 =
    "    "
    <> render_container_row(
      0,
      containers_per_row,
      healthy_count,
      container_count,
      alive,
      dead,
      wire,
    )
  let row2 = case container_count > containers_per_row {
    True ->
      "    "
      <> render_container_row(
        containers_per_row,
        container_count,
        healthy_count,
        container_count,
        alive,
        dead,
        wire,
      )
    False -> ""
  }

  let health_pct = case container_count {
    0 -> 0.0
    _ -> int.to_float(healthy_count) /. int.to_float(container_count)
  }
  let health_bar =
    "    Health: "
    <> render_progress_bar(health_pct, 24)
    <> " "
    <> int.to_string(healthy_count)
    <> "/"
    <> int.to_string(container_count)

  string.join(
    [
      with_color("  ╔═══ MESH TOPOLOGY ═══╗", "cyan"),
      r_label,
      r_row,
      "        " <> string.repeat(wire, 18),
      row1,
      row2,
      health_bar,
      with_color("  ╚═══════════════════════╝", "cyan"),
    ],
    "\n",
  )
}

fn render_container_row(
  start: Int,
  end: Int,
  healthy: Int,
  _total: Int,
  alive_icon: String,
  dead_icon: String,
  wire: String,
) -> String {
  build_range(start, end)
  |> list.map(fn(i) {
    let icon = case i < healthy {
      True -> alive_icon
      False -> dead_icon
    }
    icon <> wire
  })
  |> string.join("")
}

fn build_range(start: Int, end: Int) -> List(Int) {
  case start >= end {
    True -> []
    False -> [start, ..build_range(start + 1, end)]
  }
}

/// Render a fractal layer heatmap (L0-L7) showing health per layer.
/// Uses Unicode blocks: ████ for healthy, ░░░░ for degraded, .... for missing.
pub fn render_fractal_heatmap(layers: List(#(String, Float))) -> String {
  let header = with_color("  FRACTAL HEATMAP (L0─L7)", "cyan")
  let rows =
    list.map(layers, fn(entry) {
      let #(name, health) = entry
      let bar_width = 16
      let filled = float.round(health *. int.to_float(bar_width))
      let empty = bar_width - filled
      let color = case health {
        h if h >=. 0.9 -> "green"
        h if h >=. 0.5 -> "yellow"
        _ -> "red"
      }
      "  "
      <> with_color(pad_right(name, 18), "dim")
      <> " "
      <> with_color(string.repeat("█", filled), color)
      <> with_color(string.repeat("░", empty), "dim")
      <> " "
      <> with_color(
        {
          let pct = float.round(health *. 100.0)
          int.to_string(pct) <> "%"
        },
        color,
      )
    })
    |> string.join("\n")
  header <> "\n" <> rows
}

/// Render a mini timeline of events with timestamps.
pub fn render_timeline(events: List(#(String, String))) -> String {
  let header = with_color("  EVENT TIMELINE", "cyan")
  let rows =
    list.index_map(events, fn(entry, i) {
      let #(time, event) = entry
      let connector = case i == list.length(events) - 1 {
        True -> "  └─"
        False -> "  ├─"
      }
      with_color(connector, "dim")
      <> " "
      <> with_color(time, "dim")
      <> " "
      <> event
    })
    |> string.join("\n")
  header <> "\n" <> rows
}

/// Render a mini-dashboard status strip (one line, multiple indicators).
pub fn render_status_strip(indicators: List(#(String, String))) -> String {
  list.map(indicators, fn(ind) {
    let #(label, status) = ind
    render_badge(status, status) <> " " <> with_color(label, "dim")
  })
  |> string.join("  ")
}
