// STAMP: SC-GLM-UI-001, SC-MIRAGE-001, SC-MIRAGE-MIGRATE-001
// TUI view for MirageOS migration projections and simulation state.

import cepaf_gleam/services/mirage_migration_engine.{type MigrationCandidate}
import cepaf_gleam/services/mirage_unikernel_daemon.{type MirageDaemonState}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub fn render(
  candidates: List(MigrationCandidate),
  state: MirageDaemonState,
) -> String {
  let projected_savings =
    mirage_migration_engine.total_projected_ram_savings(candidates)
  let verified_admitted =
    mirage_migration_engine.verified_admitted_count(candidates)

  let header =
    "\u{001b}[1;36m▌ MirageOS Migration Projection Dashboard\u{001b}[0m"
    <> "  Verified admitted: \u{001b}[1;33m"
    <> int.to_string(verified_admitted)
    <> "/"
    <> int.to_string(list.length(candidates))
    <> "\u{001b}[0m"
    <> " | Projected RAM delta: \u{001b}[1;33m"
    <> int.to_string(projected_savings)
    <> " MB (unmeasured)\u{001b}[0m"

  let runtime =
    "  Runtime: "
    <> mirage_unikernel_daemon.runtime_mode_label(state.mode)
    <> " | health=unknown | observation="
    <> mirage_unikernel_daemon.observation_status(state.observation)
    <> " ("
    <> mirage_unikernel_daemon.observation_reason(state.observation)
    <> ")"

  let table_header =
    "\u{001b}[90m  ID             Lyr  Candidate                      Target  Projected RAM  Projected speedup  State\u{001b}[0m"

  let rows =
    list.map(candidates, render_candidate_row)
    |> string.join("\n")

  let evidence =
    "\u{001b}[33m  Evidence: configured projections only; empirical benchmark and formal admission receipts are required.\u{001b}[0m"

  let safety_block =
    "\u{001b}[90m  Non-Negotiable Boundaries: BEAM OTP 29 Supervisor, MAX Inference Tier, NVMe 25503L801736, Jujutsu .jj/\u{001b}[0m"

  string.join(
    [header, runtime, "", table_header, rows, "", evidence, safety_block],
    "\n",
  )
}

fn render_candidate_row(candidate: MigrationCandidate) -> String {
  "○ "
  <> pad_right(candidate.id, 14)
  <> " "
  <> pad_right(candidate.layer, 4)
  <> " "
  <> pad_right(candidate.name, 30)
  <> " "
  <> "SIL-"
  <> int.to_string(candidate.target_sil_level)
  <> "  "
  <> pad_right(int.to_string(candidate.projected_ram_saving_mb) <> " MB", 13)
  <> " "
  <> pad_right(float.to_string(candidate.projected_speedup_pct) <> "%", 18)
  <> " "
  <> mirage_migration_engine.stage_to_string(candidate.status)
  <> "/projection-only"
}

fn pad_right(value: String, width: Int) -> String {
  let length = string.length(value)
  case length >= width {
    True -> value
    False -> value <> string.repeat(" ", width - length)
  }
}
