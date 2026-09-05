//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/tui/cockpit_view</module>
////     <fsharp-lineage>Cepaf.UI.Terminal.Cockpit.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>ANSI-Rich TUI Dashboard</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007, SC-GLM-UI-008</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       F# `Spectre.Console` Render Trees ≅ Gleam Custom ANSI Strings.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

///
/// TUI view for Cockpit plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007, SC-GLM-UI-008).
/// Dark Cockpit: only anomalies shown by default (SC-GLM-UI-008).
import cepaf_gleam/cockpit/domain.{
  type Alarm, type AlarmLevel, type MeshNode, Advisory, Caution, Connected,
  Critical, Degraded, Disconnected, Normal, Stale, Warning,
}
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/cockpit_view.{type CockpitModel}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: CockpitModel) -> String {
  let header = visuals.with_color("  COCKPIT", "cyan")
  let mode = case model.dark_cockpit {
    True ->
      "  Mode: "
      <> visuals.with_color("DARK COCKPIT", "green")
      <> " (anomalies only)"
    False -> "  Mode: " <> visuals.with_color("FULL VIEW", "blue")
  }
  let nodes = render_nodes(cockpit_view.visible_nodes(model))
  let alarms = render_alarms(cockpit_view.active_alarms(model))
  string.join([header, mode, "", nodes, "", alarms], "\n")
}

fn render_nodes(nodes: List(MeshNode)) -> String {
  "  Nodes ("
  <> int.to_string(list.length(nodes))
  <> "):"
  <> "\n"
  <> {
    nodes
    |> list.take(10)
    |> list.map(fn(n) {
      let status_color = case n.status {
        Connected -> "green"
        Stale -> "yellow"
        Degraded -> "red"
        Disconnected -> "magenta"
      }
      let cpu_bar = visuals.render_progress_bar(n.cpu.value /. 100.0, 10)
      "  "
      <> visuals.with_color(n.name, status_color)
      <> " CPU:"
      <> cpu_bar
      <> " MEM:"
      <> float.to_string(n.memory.value)
      <> "%"
    })
    |> string.join("\n")
  }
}

fn render_alarms(alarms: List(Alarm)) -> String {
  "  Alarms ("
  <> int.to_string(list.length(alarms))
  <> "):"
  <> "\n"
  <> {
    alarms
    |> list.take(8)
    |> list.map(fn(a) {
      let color = case a.level {
        Critical -> "red"
        Warning -> "red"
        Caution -> "yellow"
        Advisory -> "blue"
        Normal -> "green"
      }
      "  "
      <> visuals.with_color("[" <> level_to_string(a.level) <> "]", color)
      <> " "
      <> a.node_id
      <> ": "
      <> a.message
    })
    |> string.join("\n")
  }
}

fn level_to_string(l: AlarmLevel) -> String {
  case l {
    Critical -> "CRIT"
    Warning -> "WARN"
    Caution -> "CAUT"
    Advisory -> "INFO"
    Normal -> "OK"
  }
}
