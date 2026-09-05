//// Pass-27 — Phase 3d per-page split: smriti_view extracted from
//// domain_views.gleam. SC-FILESIZE-001 / SC-MUDA-001 / SC-GLM-UI-001.

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ui/lustre/shell
import cepaf_gleam/ui/state.{type SharedMeshState}
import cepaf_gleam/ui/web/page_helpers.{count_in_json, page_header}
import gleam/int
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn view(_state: SharedMeshState) -> Element(msg) {
  let status_raw = c3i_nif.plan_status()
  let total_tasks = count_in_json(status_raw, "total")
  let completed_tasks = count_in_json(status_raw, "completed")
  let pending_tasks = count_in_json(status_raw, "pending")
  let active_tasks = count_in_json(status_raw, "active")
  html.div([attribute.class("w-full")], [
    page_header(
      "Smriti Knowledge",
      "Semantic knowledge graph — federation and immortality",
    ),
    shell.section("Catalog", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "ZK Holons",
          "Healthy",
          int.to_string(total_tasks),
          "Planning.db total",
        ),
        shell.status_card(
          "Active",
          case active_tasks > 0 {
            True -> "Healthy"
            False -> "Degraded"
          },
          int.to_string(active_tasks),
          "in progress",
        ),
        shell.status_card(
          "Completed",
          "Healthy",
          int.to_string(completed_tasks),
          "resolved entries",
        ),
        shell.status_card(
          "Pending",
          case pending_tasks > 100 {
            True -> "Degraded"
            False -> "Healthy"
          },
          int.to_string(pending_tasks),
          "awaiting action",
        ),
      ]),
    ]),
    shell.section("Pure Semantic Functions", [
      shell.data_table(["Function", "Type", "Status"], [
        ["dot_product/2", "Float → Float → Float", "active"],
        ["cosine_similarity/2", "Vector → Vector → Float", "active"],
        ["normalize/1", "Vector → Vector", "active"],
      ]),
    ]),
    // ── CA9: ZK Search Bar (SC-ZK-CLAUDE-001) ────────────────────────────
    shell.section("Search Zettelkasten", [shell.zk_search_bar()]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/page-grid.bundled.js?page=smriti")],
      [],
    ),
  ])
}
