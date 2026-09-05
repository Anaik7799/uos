//// =============================================================================
//// [C3I-SIL6-MSTS] BRIDGE PAGE — Pass-26 (Phase 3a) + Pass-27 (Phase 3b dedupe)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/web/pages/bridge_page</module>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-FILESIZE-001, SC-MUDA-001, SC-GLM-UI-001</stamp-controls>
////   </compliance>
//// </c3i-module>

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ui/lustre/shell
import cepaf_gleam/ui/state.{type SharedMeshState}
import cepaf_gleam/ui/web/page_helpers.{count_in_json, page_header}
import gleam/int
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

/// /bridge page renderer.
pub fn view(_state: SharedMeshState) -> Element(msg) {
  let health_raw = c3i_nif.system_health()
  let healthy = count_in_json(health_raw, "healthy_count")
  let total = count_in_json(health_raw, "container_count")
  let bridge_status = case healthy == total && total > 0 {
    True -> "Healthy"
    False -> "Degraded"
  }
  html.div([attribute.class("w-full")], [
    page_header("Bridge", "F# CEPAF ↔ Gleam/Elixir bridge — NIF + Zenoh"),
    shell.section("Bridge Status", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("NIF Bridge", bridge_status, "loaded", "zenoh_nif.so"),
        shell.status_card(
          "Mesh Nodes",
          bridge_status,
          int.to_string(healthy) <> "/" <> int.to_string(total),
          "live NIF data",
        ),
        shell.status_card("Zenoh NIF", bridge_status, "loaded", "SC-ZENOH-001"),
        shell.status_card(
          "Rule Engine",
          "Healthy",
          "active",
          "rule_engine_nif.so",
        ),
      ]),
    ]),
    shell.section("Bridge Points", [
      shell.data_table(["Bridge", "Mechanism", "Direction"], [
        ["Rule engine", "NIF (rule_engine_nif.so)", "Gleam → Rust → Gleam"],
        ["Container status", "Podman CLI FFI", "Gleam → Erlang → Shell"],
        ["Zenoh pub/sub", "NIF (zenoh_nif.so)", "Gleam → Rust → Zenoh"],
        ["OODA results", "Zenoh subscription", "Rust → Zenoh → Gleam"],
        ["Ignition commands", "./sa-up CLI", "Gleam TUI → Shell → Rust"],
      ]),
    ]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/page-grid.bundled.js?page=bridge")],
      [],
    ),
  ])
}
