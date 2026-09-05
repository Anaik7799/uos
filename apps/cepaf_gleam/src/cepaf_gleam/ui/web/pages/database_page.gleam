//// Pass-27 — Phase 3c per-page split: database_view extracted from
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

pub fn view(_state: SharedMeshState) -> Element(msg) {
  let status_raw = c3i_nif.plan_status()
  let total_rows = count_in_json(status_raw, "total")
  let active_rows = count_in_json(status_raw, "active")
  let blocked_rows = count_in_json(status_raw, "blocked")
  html.div([attribute.class("w-full")], [
    page_header(
      "Database",
      "Multi-engine persistence — SQLite, DuckDB, Postgres, ZenohKV",
    ),
    shell.section("Supported Engines", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "SQLite WAL",
          "Healthy",
          int.to_string(total_rows) <> " rows",
          "Planning.db",
        ),
        shell.status_card("DuckDB", "Healthy", "active", "analytics + OLAP"),
        shell.status_card("Postgres", "Degraded", "5433", "external cluster"),
        shell.status_card("Zenoh KV", "Healthy", "active", "ephemeral mesh KV"),
        shell.status_card("InMemory", "Healthy", "active", "test isolation"),
      ]),
    ]),
    shell.section("Planning.db Live Stats", [
      shell.kv_row("Total Rows", int.to_string(total_rows)),
      shell.kv_row("Active Tasks", int.to_string(active_rows)),
      shell.kv_row("Blocked Tasks", int.to_string(blocked_rows)),
    ]),
    shell.section("Cross-Holon Access", [
      shell.kv_row(
        "Rule",
        "SC-XHOLON-001 — isolated files, Zenoh-only cross access",
      ),
      shell.kv_row("Conflict resolution", "LastWriterWins (OCC)"),
      shell.kv_row("WAL mode", "Required for all SQLite databases"),
    ]),
    shell.section("Database Schema", [
      shell.data_table(["Table", "Engine", "Purpose"], [
        ["Tasks", "SQLite WAL", "Planning task store (sa-plan-daemon)"],
        ["ConversationHistory", "SQLite WAL", "50-message chat sliding window"],
        ["SemanticCache", "SQLite WAL", "24h TTL inference result cache"],
        ["TransactionTrace", "SQLite WAL", "PipelineTracer end-to-end spans"],
        ["UserPreferences", "SQLite WAL", "Per-user config and rate limits"],
      ]),
    ]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/page-grid.bundled.js?page=database")],
      [],
    ),
  ])
}
/// /bridge page renderer. Body extracted to `pages/bridge_page.gleam`
/// in Pass-26 (Phase 3a · UI-Refactor Roadmap) as a per-page split
/// proof-of-pattern. Delegates to `bridge_page.view`. SC-FILESIZE-001.
