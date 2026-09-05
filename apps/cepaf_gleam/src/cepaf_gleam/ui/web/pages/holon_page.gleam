//// Pass-27 — Phase 3c per-page split: holon_view extracted from
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
  let status_raw = c3i_nif.plan_status()
  let total_tasks = count_in_json(status_raw, "total")
  let active_tasks = count_in_json(status_raw, "active")
  html.div([attribute.class("w-full")], [
    page_header(
      "Holon Identity",
      "Multi-runtime holon — Gleam, Elixir, F#, Rust",
    ),
    shell.section("Runtime Stack", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Gleam/BEAM",
          "Healthy",
          "active",
          "primary — L0-L7 UI",
        ),
        shell.status_card(
          "Elixir/Phoenix",
          "Healthy",
          "active",
          "legacy port 4000",
        ),
        shell.status_card("F# CEPAF", "Healthy", "active", "safety kernel"),
        shell.status_card(
          "Rust NIF",
          "Healthy",
          int.to_string(active_tasks) <> " active tasks",
          "ignition daemon",
        ),
      ]),
    ]),
    shell.section("Holon Types", [
      shell.data_table(["Type", "Count", "Description"], [
        ["Computation", "4", "ex-app-1/2/3 + chaya"],
        ["Cognitive", "2", "cortex + cepaf-bridge"],
        ["Transport", "4", "zenoh-router-1/2/3/main"],
        ["Storage", "1", "db-prod"],
        ["Observability", "1", "obs-prod"],
        ["AI Compute", "2", "ollama + mojo"],
        ["ML Runner", "2", "ml-runner-1/2"],
      ]),
    ]),
    shell.section("Planning State", [
      shell.kv_row("Total Tasks", int.to_string(total_tasks)),
      shell.kv_row(
        "Containers",
        int.to_string(state.container_count) <> " registered",
      ),
    ]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/page-grid.bundled.js?page=holon")],
      [],
    ),
  ])
}
