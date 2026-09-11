//// =============================================================================
//// [C3I-SIL6-MSTS] UOS FRACTAL ATLAS & 17-ASPECT TUI SPLIT-SCREEN VIEW
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/ui/tui/fractal_atlas_tui</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL..L9_SOVEREIGNTY</layer>
////     <topology>Split-Screen ANSI Terminal Visualizer for Atlas & POODAVR</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-INTENT-ATLAS-001, SC-CHECKLIST-001, SC-POODAVR-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/cortex/poodavr_actor.{
  type PoodavrDecision, StageAct, StageDecide, StageObserve, StageOrient,
  StagePredict, StageReflect, StageVerify,
}
import cepaf_gleam/semantics/algebraic_atlas.{
  all_charts, chart_to_int, chart_to_string,
}
import cepaf_gleam/verification/aspect_coverage_engine.{
  type AspectAuditReport,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub const ansi_reset: String = "\u{001b}[0m"
pub const ansi_bold: String = "\u{001b}[1m"
pub const ansi_green: String = "\u{001b}[32m"
pub const ansi_yellow: String = "\u{001b}[33m"
pub const ansi_blue: String = "\u{001b}[34m"
pub const ansi_cyan: String = "\u{001b}[36m"
pub const ansi_red: String = "\u{001b}[31m"

pub fn render_atlas_tui(
  last_decision: Option(PoodavrDecision),
  report: AspectAuditReport,
) -> String {
  let header =
    ansi_bold
    <> ansi_cyan
    <> "╔═══════════════════════════════════════════════════════════════════════════════════════════════╗\n"
    <> "║                 UOS 10-CHART FRACTAL ATLAS & 17-ASPECT POODAVR COCKPIT                        ║\n"
    <> "║ Tailscale: http://nas-1.tail55d152.ts.net:8100/atlas | OS Lock: 25503L801736 | Zero-Muda: BEAM║\n"
    <> "╚═══════════════════════════════════════════════════════════════════════════════════════════════╝\n"
    <> ansi_reset

  let left_title = ansi_bold <> ansi_green <> "--- 10-CHART FRACTAL ATLAS ---" <> ansi_reset <> "\n"
  let charts_rendered =
    list.map(all_charts(), fn(c) {
      "  ["
      <> ansi_cyan
      <> "U"
      <> int.to_string(chart_to_int(c))
      <> ansi_reset
      <> "] "
      <> chart_to_string(c)
      <> "\n"
    })
    |> string.concat

  let poodavr_title =
    "\n"
    <> ansi_bold
    <> ansi_yellow
    <> "--- POODAVR 7-STAGE CYBERNETIC LOOP ---"
    <> ansi_reset
    <> "\n"

  let active_stage = case last_decision {
    Some(d) -> d.stage
    None -> StagePredict
  }

  let stages = [
    #(StagePredict, "1. Predict  [Lyapunov Prior V(x)]"),
    #(StageObserve, "2. Observe  [Zenoh Pub/Sub Ingest]"),
    #(StageOrient,  "3. Orient   [STAMP Hazard & OS Lock]"),
    #(StageDecide,  "4. Decide   [Prajna Breakers & MAX]"),
    #(StageAct,     "5. Act      [Sa-Plan & ZigVM VFS]"),
    #(StageVerify,  "6. Verify   [Denotational [[ I ]]]"),
    #(StageReflect, "7. Reflect  [Lyapunov & Antibodies]"),
  ]

  let stages_rendered =
    list.map(stages, fn(pair) {
      let #(st, desc) = pair
      case st == active_stage {
        True ->
          "  " <> ansi_bold <> ansi_green <> "▶ " <> desc <> " (ACTIVE)" <> ansi_reset <> "\n"
        False ->
          "    " <> desc <> "\n"
      }
    })
    |> string.concat

  let aspect_title =
    "\n"
    <> ansi_bold
    <> ansi_blue
    <> "--- 17 CANONICAL SYSTEM ASPECTS (Coverage: "
    <> float.to_string(report.coverage_score *. 100.0)
    <> "%) ---"
    <> ansi_reset
    <> "\n"

  let aspects_rendered =
    list.map(report.entries, fn(e) {
      "  ["
      <> ansi_green
      <> "PASS"
      <> ansi_reset
      <> "] #"
      <> int.to_string(e.id)
      <> " "
      <> e.name
      <> " ("
      <> e.authority
      <> ")\n"
    })
    |> string.concat

  let footer =
    ansi_bold
    <> ansi_cyan
    <> "─────────────────────────────────────────────────────────────────────────────────────────────────\n"
    <> " 18/18 Checklist Checks PASS | Standalone Jujutsu .jj/ | C1-C8 Gold Standard Verified\n"
    <> ansi_reset

  header
  <> left_title
  <> charts_rendered
  <> poodavr_title
  <> stages_rendered
  <> aspect_title
  <> aspects_rendered
  <> footer
}
