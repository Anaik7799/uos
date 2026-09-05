//// Pass-27 — Phase 3c per-page split: config_view extracted from
//// domain_views.gleam. Uses shared page_helpers (Pass-27 Phase 3b).
//// SC-FILESIZE-001 / SC-MUDA-001 / SC-GLM-UI-001.

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ui/lustre/shell
import cepaf_gleam/ui/state.{type SharedMeshState}
import cepaf_gleam/ui/web/page_helpers.{count_in_json, page_header}
import gleam/int
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn view(state: SharedMeshState) -> Element(msg) {
  let health_raw = c3i_nif.system_health()
  let healthy_count = count_in_json(health_raw, "healthy_containers")
  let reported_healthy = case healthy_count > 0 {
    True -> healthy_count
    False -> state.healthy_count
  }
  let config_status = case state.quorum_healthy {
    True -> "Healthy"
    False -> "Degraded"
  }
  html.div([attribute.class("w-full")], [
    page_header(
      "Mesh Configuration",
      "MeshConfig — containers, networks, quorum",
    ),
    shell.section("Mesh Status", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Containers",
          config_status,
          int.to_string(reported_healthy) <> "/16",
          "healthy / total",
        ),
        shell.status_card(
          "Quorum",
          config_status,
          case state.quorum_healthy {
            True -> "Active"
            False -> "Lost"
          },
          "2oo3 voting",
        ),
        shell.status_card(
          "Zenoh",
          case state.zenoh_connected {
            True -> "Healthy"
            False -> "Critical"
          },
          case state.zenoh_connected {
            True -> "Connected"
            False -> "Down"
          },
          "TCP 7447",
        ),
      ]),
    ]),
    shell.section("Topology", [
      shell.kv_row(
        "Containers",
        "16 (SIL-6 genome) — " <> int.to_string(reported_healthy) <> " healthy",
      ),
      shell.kv_row("Networks", "1 (indrajaal-net)"),
      shell.kv_row("Quorum Size", "4 nodes (2oo3 + spare)"),
      shell.kv_row("Total vCPU", "8.0 cores"),
      shell.kv_row("Total Memory", "4096 MB"),
    ]),
    shell.section("Port Assignments", [
      shell.data_table(["Port", "Service", "Notes"], [
        ["4000-4010", "Mesh containers", "RESERVED — no non-mesh use"],
        ["4100", "Gleam Wisp HTTP", "Triple-interface (SC-GLM-UI-006)"],
        ["4317", "OTel gRPC", "Collector"],
        ["5433", "PostgreSQL", "db-prod"],
        ["7447", "Zenoh router", "Primary TCP"],
        ["9090", "Prometheus", "Metrics scrape"],
      ]),
    ]),
    // System Controls — Hot Reload (SC-HA-RELOAD-001)
    shell.section("System Controls", [shell.hot_reload_button()]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/page-grid.bundled.js?page=config")],
      [],
    ),
  ])
}
