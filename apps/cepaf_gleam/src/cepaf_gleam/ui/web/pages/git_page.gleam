//// Pass-27 — Phase 3c per-page split: git_view extracted from
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
  let completed_count = count_in_json(status_raw, "completed")
  let pending_count = count_in_json(status_raw, "pending")
  let total_count = count_in_json(status_raw, "total")
  let git_status = case state.quorum_healthy {
    True -> "Healthy"
    False -> "Degraded"
  }
  html.div([attribute.class("w-full")], [
    page_header(
      "Git Intelligence",
      "ICP v2.0 commit conventions — 9 types, 23 scopes",
    ),
    shell.section("Repository Health", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Pipeline",
          git_status,
          "ICP v2.0",
          "9 types, 23 scopes",
        ),
        shell.status_card(
          "Completed",
          "Healthy",
          int.to_string(completed_count),
          "tasks done",
        ),
        shell.status_card(
          "Pending",
          case pending_count > 100 {
            True -> "Degraded"
            False -> "Healthy"
          },
          int.to_string(pending_count),
          "tasks remaining",
        ),
        shell.status_card(
          "Total Tasks",
          git_status,
          int.to_string(total_count),
          "in Planning.db",
        ),
      ]),
    ]),
    shell.section("Commit Convention", [
      shell.kv_row("Format", "type(scope): action — context [ref]"),
      shell.kv_row("Max length", "80 characters"),
      shell.kv_row(
        "Types",
        "feat fix refactor perf test docs chore security evolve",
      ),
      shell.kv_row(
        "Scopes (23)",
        "guardian app db kms mesh cepaf zenoh sentinel…",
      ),
      shell.kv_row("Health Score", case state.quorum_healthy {
        True -> "0.85"
        False -> "0.60"
      }),
    ]),
    shell.section("Task Pipeline", [
      shell.kv_row("Completed Tasks", int.to_string(completed_count)),
      shell.kv_row("Pending Tasks", int.to_string(pending_count)),
    ]),
    shell.section("Branch Strategy", [
      shell.kv_row("Main branch", "main"),
      shell.kv_row("Feature branches", "multiverse/<agent-id>-<scope>"),
      shell.kv_row("Merge strategy", "ff-only after Guardian approval"),
    ]),
    shell.section("Commit Type Reference", [
      shell.data_table(["Type", "Scope", "Example"], [
        ["feat", "app, db, zenoh", "feat(zenoh): add mesh health publisher"],
        [
          "fix",
          "cepaf, sentinel",
          "fix(sentinel): correct threat classification",
        ],
        ["refactor", "core, plan", "refactor(plan): extract priority sorting"],
        ["test", "test, ci", "test(immune): add wiring guard coverage"],
        ["docs", "sync, core", "docs(sync): update constraint registry"],
      ]),
    ]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/page-grid.bundled.js?page=git")],
      [],
    ),
  ])
}
