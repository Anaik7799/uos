// STAMP: SC-GLM-UI-001, SC-MIRAGE-001, SC-MIRAGE-MIGRATE-001
// TUI ANSI view for MirageOS Unikernel & Subsystem Migration.

import cepaf_gleam/services/mirage_migration_engine.{
  type MigrationCandidate, Admitted, Implemented, Mapped, Verified,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub fn render(candidates: List(MigrationCandidate)) -> String {
  let total_savings = mirage_migration_engine.total_ram_savings(candidates)
  let admitted = mirage_migration_engine.admitted_count(candidates)

  let header =
    "\u{001b}[1;36m▌ MirageOS Unikernel & Subsystem Migration Dashboard\u{001b}[0m"
    <> "  Admitted: \u{001b}[1;32m"
    <> int.to_string(admitted)
    <> "/7\u{001b}[0m"
    <> " | RAM Saved: \u{001b}[1;32m"
    <> int.to_string(total_savings)
    <> " MB\u{001b}[0m"
    <> " [SOLO5-SPT 6-SYSCALL]"

  let table_header =
    "\u{001b}[90m  ID             Lyr  Subsystem                      SIL  RAM Saved  Speedup  Status\u{001b}[0m"

  let rows =
    list.map(candidates, render_candidate_row)
    |> string.join("\n")

  let safety_block =
    "\u{001b}[90m  Non-Negotiable Boundaries: BEAM OTP 29 Supervisor, MAX Inference Tier, NVMe 25503L801736, Jujutsu .jj/\u{001b}[0m"

  string.join([header, "", table_header, rows, "", safety_block], "\n")
}

fn render_candidate_row(c: MigrationCandidate) -> String {
  let marker = case c.status {
    Admitted -> "\u{001b}[1;32m✔\u{001b}[0m"
    Implemented -> "\u{001b}[1;34m→\u{001b}[0m"
    Verified -> "\u{001b}[1;33m●\u{001b}[0m"
    Mapped -> "\u{001b}[1;35m○\u{001b}[0m"
    _ -> " "
  }

  let status_color = case c.status {
    Admitted -> "\u{001b}[32m"
    Implemented -> "\u{001b}[34m"
    Verified -> "\u{001b}[33m"
    Mapped -> "\u{001b}[35m"
    _ -> "\u{001b}[90m"
  }

  marker
  <> " "
  <> pad_right(c.id, 14)
  <> " "
  <> pad_right(c.layer, 4)
  <> " "
  <> pad_right(c.name, 30)
  <> " "
  <> "SIL-"
  <> int.to_string(c.sil_level)
  <> "  "
  <> pad_right(int.to_string(c.ram_saving_mb) <> " MB", 10)
  <> " "
  <> pad_right(float.to_string(c.speedup_pct) <> "%", 8)
  <> " "
  <> status_color
  <> mirage_migration_engine.stage_to_string(c.status)
  <> "\u{001b}[0m"
}

fn pad_right(s: String, width: Int) -> String {
  let len = string.length(s)
  case len >= width {
    True -> s
    False -> s <> string.repeat(" ", width - len)
  }
}
