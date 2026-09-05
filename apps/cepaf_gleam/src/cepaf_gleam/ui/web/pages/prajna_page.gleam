//// Pass-27 — Phase 3d per-page split: prajna_view extracted from
//// domain_views.gleam. SC-FILESIZE-001 / SC-MUDA-001 / SC-GLM-UI-001.

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ui/lustre/shell
import cepaf_gleam/ui/state.{
  type SharedMeshState, cockpit_mode_to_string, ooda_phase_to_string,
}
import cepaf_gleam/ui/web/page_helpers.{count_in_json, page_header}
import gleam/int
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn view(state: SharedMeshState) -> Element(msg) {
  let health_raw = c3i_nif.system_health()
  let healthy_containers = count_in_json(health_raw, "healthy_containers")
  let circuit_label = case healthy_containers > 0 {
    True -> int.to_string(healthy_containers) <> " healthy"
    False -> "< 100 msgs/s"
  }
  html.div([attribute.class("w-full")], [
    page_header(
      "Prajna Biomorphic",
      "Neuro-symbolic AI substrate — circuit breaker, advisory",
    ),
    shell.section("AI Advisory", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Circuit Breaker", "Healthy", "closed", circuit_label),
        shell.status_card(
          "Dark Cockpit",
          "Healthy",
          cockpit_mode_to_string(state.dark_cockpit_mode),
          "5-mode state machine",
        ),
        shell.status_card(
          "Mesh Health",
          case state.quorum_healthy {
            True -> "Healthy"
            False -> "Degraded"
          },
          int.to_string(state.healthy_count)
            <> "/"
            <> int.to_string(state.container_count),
          "containers monitored",
        ),
        shell.status_card(
          "OODA Phase",
          "Healthy",
          ooda_phase_to_string(state.ooda_phase),
          "< 100ms cycle",
        ),
      ]),
    ]),
    shell.section("5-Mode State Machine", [
      shell.data_table(["Mode", "Trigger", "Display", "Color"], [
        ["Dark", "No alerts", "Minimal gray", "Monochrome"],
        ["Dim", "Warnings", "Subtle yellow", "Low-saturation"],
        ["Normal", "Errors", "Visible orange", "Standard"],
        ["Bright", "Multiple errors", "High-visibility", "High-contrast"],
        ["Emergency", "Critical", "Full illumination", "Red dominant"],
      ]),
    ]),
    shell.section("DB3 — OODA Cycle Trace", [shell.ooda_trace_viewer()]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/page-grid.bundled.js?page=prajna")],
      [],
    ),
  ])
}
