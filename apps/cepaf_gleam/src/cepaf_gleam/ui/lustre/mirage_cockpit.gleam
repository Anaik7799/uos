//// MirageOS migration projection cockpit.
//// STAMP: SC-GLM-UI-001, SC-CHECKLIST-001, SC-MIRAGE-MIGRATE-001

import cepaf_gleam/services/mirage_migration_engine.{type MigrationCandidate}
import cepaf_gleam/services/mirage_unikernel_daemon
import gleam/float
import gleam/int
import gleam/list
import gleam/string

const benchmark_spec_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-1037-mirage-benchmark-contract.md"

pub fn view() -> String {
  let candidates = mirage_migration_engine.get_migration_candidates()
  let projected_savings =
    mirage_migration_engine.total_projected_ram_savings(candidates)
  let verified_admitted =
    mirage_migration_engine.verified_admitted_count(candidates)
  let state = mirage_unikernel_daemon.new_daemon_state()

  "<div class=\"uos-mirage-cockpit\" style=\"padding:1.5rem;background:#0a0e17;color:#e0e6ed\">"
  <> "<header><h1 style=\"color:#00d4aa\">MirageOS Migration Projection Cockpit</h1>"
  <> "<p>Configured candidate model. Runtime health, deployment, SIL certification, and admission are unverified.</p>"
  <> "<p><strong>Evidence scope:</strong> static_migration_projection &middot; <strong>Deployment admission:</strong> NOT_VERIFIED</p></header>"
  <> "<section style=\"border:1px solid #f5a623;padding:1rem;margin:1rem 0\"><h2>Runtime observation</h2>"
  <> "<p>Mode: <code>"
  <> mirage_unikernel_daemon.runtime_mode_label(state.mode)
  <> "</code> &middot; Health: <code>unknown</code> &middot; Observation: <code>"
  <> mirage_unikernel_daemon.observation_status(state.observation)
  <> "</code></p><p>"
  <> mirage_unikernel_daemon.observation_reason(state.observation)
  <> "</p></section>"
  <> "<section><h2>Projection summary</h2><ul>"
  <> "<li>Candidate count: "
  <> int.to_string(list.length(candidates))
  <> "</li><li>Verified admitted: "
  <> int.to_string(verified_admitted)
  <> "</li><li>Projected RAM delta: "
  <> int.to_string(projected_savings)
  <> " MB; measured RAM delta: unknown</li>"
  <> "<li>Cold-start and speedup values: configured projections; runtime measurements required</li>"
  <> "<li>Solo5 syscall profile: target configuration; live enforcement unobserved</li></ul>"
  <> "<p><a href=\""
  <> benchmark_spec_url
  <> "\">Review Mirage benchmark evidence contract</a></p>"
  <> "<p><a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/mirage/candidates\">Candidate projection JSON</a> &middot; "
  <> "<a href=\"http://nas-1.tail55d152.ts.net:4100/api/v1/mirage/status\">Runtime observation JSON</a></p></section>"
  <> render_checklist()
  <> "<section><h2>Configured migration candidates</h2><table style=\"width:100%;border-collapse:collapse\"><thead><tr>"
  <> "<th>ID</th><th>Candidate</th><th>Layer</th><th>Mirage target</th><th>Declared SIL</th><th>Projected RAM</th><th>Projected speedup</th><th>Status</th>"
  <> "</tr></thead><tbody>"
  <> render_candidate_rows(candidates)
  <> "</tbody></table></section>"
  <> "<section style=\"border:1px solid #ff6b6b;padding:1rem;margin-top:1rem\"><h2>Non-negotiable boundaries</h2>"
  <> "<p>BEAM OTP 29 root supervision, the MAX inference tier, root NVMe 25503L801736, and the standalone Jujutsu repository remain outside Mirage migration.</p></section>"
  <> "<footer style=\"margin-top:1rem\"><a href=\"http://nas-1.tail55d152.ts.net:4100/\">UOS cockpit</a> &middot; Mirage evidence is projection-only until receipts are connected.</footer></div>"
}

fn render_checklist() -> String {
  "<details style=\"border:1px solid #f5a623;padding:1rem;margin:1rem 0\"><summary>Comprehensive verification requirements — evidence pending</summary>"
  <> "<p>No all-green claim is made by this projection surface.</p><ul>"
  <> checklist_item("CHK-01-TIME")
  <> checklist_item("CHK-02-TAIL")
  <> checklist_item("CHK-03-FRACT")
  <> checklist_item("CHK-04-KM")
  <> checklist_item("CHK-05-MUDA")
  <> checklist_item("CHK-06-GRAPH")
  <> checklist_item("CHK-07-DRIVE")
  <> checklist_item("CHK-08-C1C8")
  <> checklist_item("CHK-09-MATH")
  <> checklist_item("CHK-10-9MOD")
  <> checklist_item("CHK-11-REGR")
  <> checklist_item("CHK-12-GLEAM")
  <> checklist_item("CHK-13-HERMES")
  <> checklist_item("CHK-14-ZIGVM")
  <> checklist_item("CHK-15-MAX")
  <> checklist_item("CHK-16-OTEL")
  <> checklist_item("CHK-17-SOV")
  <> checklist_item("CHK-18-JJ")
  <> "</ul></details>"
}

fn checklist_item(code: String) -> String {
  "<li><strong>UNVERIFIED</strong> " <> code <> "</li>"
}

fn render_candidate_rows(candidates: List(MigrationCandidate)) -> String {
  candidates
  |> list.map(fn(candidate) {
    "<tr><td>"
    <> candidate.id
    <> "</td><td>"
    <> candidate.name
    <> "</td><td>"
    <> candidate.layer
    <> "</td><td>"
    <> candidate.mirage_target
    <> "</td><td>Declared SIL-"
    <> int.to_string(candidate.target_sil_level)
    <> " (not certified)</td><td>"
    <> int.to_string(candidate.projected_ram_saving_mb)
    <> " MB projected</td><td>"
    <> float.to_string(candidate.projected_speedup_pct)
    <> "% projected</td><td>NOT_VERIFIED / "
    <> string.uppercase(mirage_migration_engine.stage_to_string(
      candidate.status,
    ))
    <> "</td></tr>"
  })
  |> string.join("")
}
