//// Pass-27 — Phase 3d per-page split: knowledge_view extracted from
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
  // Live task/holon counts from NIF (SC-TRUTH-001)
  let status_raw = c3i_nif.plan_status()
  let total_tasks = count_in_json(status_raw, "total")
  let completed_tasks = count_in_json(status_raw, "completed")
  let pending_tasks = count_in_json(status_raw, "pending")
  html.div([attribute.class("w-full")], [
    page_header(
      "Knowledge (Smriti)",
      "Semantic knowledge graph — triple store and embeddings",
    ),
    shell.section("Graph Summary", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Total Tasks",
          "Healthy",
          int.to_string(total_tasks),
          "live from NIF",
        ),
        shell.status_card(
          "Completed",
          "Healthy",
          int.to_string(completed_tasks),
          "in Smriti.db",
        ),
        shell.status_card(
          "Pending",
          case pending_tasks > 0 {
            True -> "Degraded"
            False -> "Healthy"
          },
          int.to_string(pending_tasks),
          "awaiting execution",
        ),
        shell.status_card("Namespaces", "Healthy", "3", "registered"),
      ]),
    ]),
    shell.section("Pure Functions", [
      shell.data_table(["Function", "Status", "Description"], [
        ["dot_product/2", "active", "Pure dot product — no side effects"],
        ["cosine_similarity/2", "active", "L2-normalised similarity score"],
        ["normalize/1", "active", "Unit vector normalisation"],
      ]),
    ]),
    shell.section("Namespaces", [
      shell.data_table(["Prefix", "URI"], [
        ["c3i:", "https://indrajaal.dev/ontology/c3i#"],
        ["mesh:", "https://indrajaal.dev/ontology/mesh#"],
        ["agent:", "https://indrajaal.dev/ontology/agent#"],
      ]),
    ]),
    // ── CA9: ZK Search Bar (SC-ZK-CLAUDE-001) ────────────────────────────
    shell.section("Search Zettelkasten", [shell.zk_search_bar()]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/knowledge-grid.bundled.js?v=pass42")],
      [],
    ),
  ])
}
