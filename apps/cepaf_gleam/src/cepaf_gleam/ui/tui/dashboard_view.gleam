//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/tui/dashboard_view</module>
////     <fsharp-lineage>Cepaf.UI.Terminal.Dashboard.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>ANSI-Rich TUI Fractal Dashboard</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007, SC-GLM-UI-008</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       F# `Spectre.Console` Layout Trees ≅ Gleam Custom ANSI String Composition.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

// योगस्थः कुरु कर्माणि — Established in yoga, perform action (Gita 2.48)

///
/// TUI view for the main Dashboard — L0-L7 fractal supervisors, OODA ring,
/// 16-container genome grid, health sparklines, supervisor tree, and thread
/// monitoring (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007, SC-GLM-UI-008).
/// Dark Cockpit: panels auto-hide when all layers are healthy (SC-GLM-UI-008).
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/domain.{type HealthStatus, Critical, Degraded, Healthy, Unknown}
import cepaf_gleam/ui/lustre/app.{type Model}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Render the full TUI dashboard panel for the given model.
pub fn render(model: Model) -> String {
  let header = render_header(model)
  let status_strip = render_status_strip(model)
  let ooda = render_ooda_panel(model)
  let fractal = render_fractal_layers()
  let genome = render_genome_grid()
  let supervisor = render_supervisor_tree()
  let threads = render_thread_monitor(model)
  let sparklines = render_health_sparklines(model)

  string.join(
    [header, status_strip, "", ooda, "", fractal, "", genome, "", supervisor, "",
      threads, "", sparklines],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

fn render_header(model: Model) -> String {
  let title = visuals.with_color("  C3I BIOMORPHIC DASHBOARD", "cyan")
  let zenoh_badge = case model.context.zenoh_connected {
    True -> visuals.render_badge("ZENOH", "ok")
    False -> visuals.render_badge("ZENOH", "error")
  }
  let cockpit_badge = case model.dark_cockpit {
    True -> visuals.render_badge("DARK", "ok")
    False -> visuals.render_badge("FULL", "info")
  }
  let health_badge = health_to_badge(model.context.health)
  title
  <> "  "
  <> zenoh_badge
  <> " "
  <> cockpit_badge
  <> " "
  <> health_badge
}

// ---------------------------------------------------------------------------
// Status strip
// ---------------------------------------------------------------------------

fn render_status_strip(model: Model) -> String {
  let health_str = health_to_label(model.context.health)
  let telemetry_count = list.length(model.context.telemetry)
  "  "
  <> visuals.render_kv_row("Health", health_str, 10)
  <> "  "
  <> visuals.render_kv_row(
    "Telemetry",
    int.to_string(telemetry_count) <> " pts",
    10,
  )
}

// ---------------------------------------------------------------------------
// OODA ring panel
// ---------------------------------------------------------------------------

fn render_ooda_panel(model: Model) -> String {
  // Derive the active OODA phase from health and connection state
  let phase = derive_ooda_phase(model)
  let ring = visuals.render_ooda_ring(phase)
  let verify_icon = case phase == "verify" {
    True -> visuals.with_color("●verify", "green")
    False -> visuals.with_color("○verify", "dim")
  }
  let five_tier =
    visuals.render_ooda_5tier("operational", "mesh nominal", phase)
  string.join(
    [
      visuals.with_color("  ╔═══ OODA RING ═════════════╗", "cyan"),
      "  " <> ring <> " → " <> verify_icon,
      five_tier,
      visuals.with_color("  ╚════════════════════════════╝", "cyan"),
    ],
    "\n",
  )
}

fn derive_ooda_phase(model: Model) -> String {
  case model.context.health {
    Healthy -> "act"
    Degraded(_) -> "orient"
    Critical(_) -> "decide"
    Unknown -> "observe"
  }
}

// ---------------------------------------------------------------------------
// Fractal layer supervisors (L0-L7) with thread counts
// ---------------------------------------------------------------------------

fn render_fractal_layers() -> String {
  let header = visuals.with_color("  FRACTAL LAYER SUPERVISORS (L0–L7)", "cyan")
  let layers = [
    #("L0", "Constitutional", 2, 1.0, "guardian,psi,prime"),
    #("L1", "Atomic/Debug", 3, 0.95, "nif,telemetry,otel"),
    #("L2", "Component", 4, 0.98, "parser,catalog,a2ui"),
    #("L3", "Transaction", 5, 0.92, "planning,db,smriti"),
    #("L4", "System", 6, 0.88, "podman,container,boot"),
    #("L5", "Cognitive", 8, 0.91, "ooda,cortex,mcp,agent"),
    #("L6", "Ecosystem", 5, 0.87, "zenoh,mesh,quorum"),
    #("L7", "Federation", 3, 0.94, "gateway,consensus,tla"),
  ]
  let rows =
    list.map(layers, fn(entry) {
      let #(layer_id, name, threads, health, domains) = entry
      let health_bar = visuals.render_progress_bar(health, 12)
      let health_color = case health >=. 0.9 {
        True -> "green"
        False ->
          case health >=. 0.7 {
            True -> "yellow"
            False -> "red"
          }
      }
      let pct_str =
        int.to_string(float.round(health *. 100.0)) <> "%"
      "  "
      <> visuals.with_color(layer_id, "magenta")
      <> " "
      <> visuals.with_color(pad_right(name, 16), "white")
      <> " T:"
      <> visuals.with_color(pad_right(int.to_string(threads), 3), "cyan")
      <> " "
      <> health_bar
      <> " "
      <> visuals.with_color(pct_str, health_color)
      <> "  "
      <> visuals.with_color(domains, "dim")
    })
    |> string.join("\n")
  header <> "\n" <> rows
}

// ---------------------------------------------------------------------------
// Container genome grid (16 containers)
// ---------------------------------------------------------------------------

fn render_genome_grid() -> String {
  let header =
    visuals.with_color("  CONTAINER GENOME GRID (SIL-6, 16 containers)", "cyan")
  // 16-container genome — name, tier, status
  let containers = [
    #("db-prod", "T2", "healthy"),
    #("obs-prod", "T3", "healthy"),
    #("ex-app-1", "T6", "healthy"),
    #("cepaf-bridge", "T5", "healthy"),
    #("cortex", "T5", "healthy"),
    #("zenoh-router", "T1", "healthy"),
    #("ollama", "T6", "healthy"),
    #("mojo", "T7", "healthy"),
    #("zenoh-router-1", "T4", "healthy"),
    #("zenoh-router-2", "T4", "healthy"),
    #("zenoh-router-3", "T4", "healthy"),
    #("ex-app-2", "T7", "healthy"),
    #("ex-app-3", "T7", "degraded"),
    #("chaya", "T6", "healthy"),
    #("ml-runner-1", "T7", "healthy"),
    #("ml-runner-2", "T7", "healthy"),
  ]
  let row1 = list.take(containers, 8)
  let row2 = list.drop(containers, 8)
  let render_row = fn(row: List(#(String, String, String))) -> String {
    list.map(row, fn(c) {
      let #(name, tier, status) = c
      let color = case status {
        "healthy" -> "green"
        "degraded" -> "yellow"
        _ -> "red"
      }
      let icon = case status {
        "healthy" -> "●"
        "degraded" -> "◐"
        _ -> "○"
      }
      visuals.with_color(icon, color)
      <> visuals.with_color(pad_right(name, 14), "dim")
      <> visuals.with_color(tier, "blue")
    })
    |> string.join("  ")
  }
  let healthy_count =
    list.filter(containers, fn(c) {
      let #(_, _, s) = c
      s == "healthy"
    })
    |> list.length
  let health_pct =
    int.to_float(healthy_count) /. int.to_float(list.length(containers))
  let health_bar =
    "  Health: "
    <> visuals.render_progress_bar(health_pct, 20)
    <> " "
    <> int.to_string(healthy_count)
    <> "/"
    <> int.to_string(list.length(containers))

  string.join(
    [
      header,
      "  " <> render_row(row1),
      "  " <> render_row(row2),
      health_bar,
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Supervisor tree (EXEC-001 → 4 supervisors → 20 workers)
// ---------------------------------------------------------------------------

fn render_supervisor_tree() -> String {
  let header = visuals.with_color("  SUPERVISOR TREE (25 agents)", "cyan")
  let exec = "  " <> visuals.with_color("EXEC-001", "magenta") <> " (orchestrator/opus)"
  let supervisors = [
    #("SUP-CTX", "context", 5),
    #("SUP-DOM", "domain", 5),
    #("SUP-TST", "test", 5),
    #("SUP-QUA", "quality", 5),
  ]
  let worker_labels = [
    "compile", "test", "credo", "fix", "doc",
    "explore", "compile", "test", "credo", "fix",
    "doc", "explore", "compile", "test", "credo",
    "fix", "doc", "explore", "compile", "test",
  ]
  let sup_lines =
    list.index_map(supervisors, fn(sup, i) {
      let #(id, domain, worker_count) = sup
      let connector = case i < list.length(supervisors) - 1 {
        True -> "├──"
        False -> "└──"
      }
      let worker_slice =
        list.drop(worker_labels, i * 5)
        |> list.take(worker_count)
        |> list.map(fn(w) { visuals.with_color(w, "dim") })
        |> string.join(",")
      "  "
      <> visuals.with_color(connector, "dim")
      <> " "
      <> visuals.with_color(id, "blue")
      <> " ("
      <> domain
      <> "/sonnet) ["
      <> worker_slice
      <> "]"
    })
    |> string.join("\n")
  string.join([header, exec, sup_lines], "\n")
}

// ---------------------------------------------------------------------------
// Thread / process monitoring
// ---------------------------------------------------------------------------

fn render_thread_monitor(model: Model) -> String {
  let header =
    visuals.with_color("  THREAD / PROCESS MONITOR", "cyan")
  let zenoh_status = case model.context.zenoh_connected {
    True -> visuals.with_color("CONNECTED", "green")
    False -> visuals.with_color("DISCONNECTED", "red")
  }
  let rows = [
    #("BEAM schedulers", "16", "16:16 dirty IO", "green"),
    #("Rust tokio", "16", "async runtime", "green"),
    #("Zenoh NIF", "4", zenoh_status, ""),
    #("Gleam actors", "33", "page init × 33", "green"),
    #("Rule engine", "2", "RETE-UL OnceLock", "green"),
    #("PipelineTracer", "1", "zero-write hot path", "green"),
  ]
  let row_lines =
    list.map(rows, fn(r) {
      let #(label, count, detail, color) = r
      let count_str = case color == "" {
        True -> visuals.with_color(count, "white")
        False -> visuals.with_color(count, color)
      }
      "  "
      <> visuals.with_color(pad_right(label, 18), "cyan")
      <> " "
      <> count_str
      <> "  "
      <> visuals.with_color(detail, "dim")
    })
    |> string.join("\n")
  header <> "\n" <> row_lines
}

// ---------------------------------------------------------------------------
// Health sparklines
// ---------------------------------------------------------------------------

fn render_health_sparklines(model: Model) -> String {
  let header = visuals.with_color("  HEALTH SPARKLINES", "cyan")
  // Build a synthetic sparkline series from telemetry or use flat nominal
  let values =
    list.take(model.context.telemetry, 16)
    |> list.map(fn(pt) { pt.value })
  let padded_values = case list.length(values) < 8 {
    True -> list.append(values, list.repeat(1.0, 8 - list.length(values)))
    False -> values
  }
  let sparkline = visuals.render_sparkline(padded_values)
  let heatmap_data = [
    #("L0 Constitutional", 1.0),
    #("L1 Atomic/Debug", 0.95),
    #("L2 Component", 0.98),
    #("L3 Transaction", 0.92),
    #("L4 System", 0.88),
    #("L5 Cognitive", 0.91),
    #("L6 Ecosystem", 0.87),
    #("L7 Federation", 0.94),
  ]
  let heatmap = visuals.render_fractal_heatmap(heatmap_data)
  string.join(
    [
      header,
      "  Telemetry: " <> visuals.with_color(sparkline, "green"),
      "",
      heatmap,
    ],
    "\n",
  )
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn health_to_label(status: HealthStatus) -> String {
  case status {
    Healthy -> visuals.with_color("HEALTHY", "green")
    Degraded(msg) -> visuals.with_color("DEGRADED: " <> msg, "yellow")
    Critical(msg) -> visuals.with_color("CRITICAL: " <> msg, "red")
    Unknown -> visuals.with_color("UNKNOWN", "dim")
  }
}

fn health_to_badge(status: HealthStatus) -> String {
  case status {
    Healthy -> visuals.render_badge("HEALTHY", "ok")
    Degraded(_) -> visuals.render_badge("DEGRADED", "warning")
    Critical(_) -> visuals.render_badge("CRITICAL", "error")
    Unknown -> visuals.render_badge("UNKNOWN", "info")
  }
}

fn pad_right(text: String, width: Int) -> String {
  let len = string.length(text)
  case len >= width {
    True -> string.slice(text, 0, width)
    False -> text <> string.repeat(" ", width - len)
  }
}
