//// =============================================================================
//// [C3I-SIL6-MSTS] UOS CORTEX & SA-PLAN ANSI SPLIT-SCREEN TUI
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/ui/tui/cortex_tui</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM..L5_COGNITIVE</layer>
////     <topology>ANSI Split-Screen Terminal Dashboard for Cortex & Sa-Plan</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-COG-001, SC-SA-PLAN-001, SC-JIDOKA-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/ha/cortex_saplan_coordinator.{type CoordinatorState}
import gleam/int

pub const ansi_reset: String = "\u{001b}[0m"
pub const ansi_bold: String = "\u{001b}[1m"
pub const ansi_green: String = "\u{001b}[32m"
pub const ansi_yellow: String = "\u{001b}[33m"
pub const ansi_cyan: String = "\u{001b}[36m"
pub const ansi_red: String = "\u{001b}[31m"

pub fn render_cortex_tui(coord: CoordinatorState) -> String {
  let header =
    ansi_bold
    <> ansi_cyan
    <> "╔═══════════════════════════════════════════════════════════════════════════════════════════════╗\n"
    <> "║                 UOS CORTEX COGNITIVE ENGINE & SA-PLAN AUTHORITY TUI                           ║\n"
    <> "║ Tailscale: http://nas-1.tail55d152.ts.net:8100/cortex | OS Lock: 25503L801736 | Mode: Fenced ║\n"
    <> "╚═══════════════════════════════════════════════════════════════════════════════════════════════╝\n"
    <> ansi_reset

  let andon_color = case coord.andon_active {
    True -> ansi_red
    False -> ansi_green
  }
  let andon_text = case coord.andon_active {
    True -> "TRIPPED (STOP LINE HALT -32002)"
    False -> "ARMED & NOMINAL (Fenced Leases)"
  }

  let status_bar =
    ansi_bold
    <> andon_color
    <> "  ANDON STATUS: "
    <> andon_text
    <> " | DISPATCHED: "
    <> int.to_string(coord.total_dispatched)
    <> " | COMPLETED: "
    <> int.to_string(coord.total_completed)
    <> "\n"
    <> ansi_reset

  let ooda_banner =
    "\n"
    <> ansi_bold
    <> ansi_yellow
    <> "--- CORTEX 7-STAGE POODAVR CYBERNETIC LOOP ---"
    <> ansi_reset
    <> "\n"
    <> "  [1. Predict]  -> Invariant Envelope & Lyapunov Baseline\n"
    <> "  [2. Observe]  -> Telemetry Ingestion & Sensor Fusion\n"
    <> "  [3. Orient]   -> Contextual Memory & Embedding Classification\n"
    <> "  [4. Decide]   -> 4-Party Sovereign Quorum Consensus\n"
    <> "  [5. Act]      -> Sa-Plan Leased Job & Task Execution\n"
    <> "  [6. Verify]   -> 18-Checkpoint Comprehensive Verification Checklist\n"
    <> "  [7. Reflect]  -> Generation Increment & SHA-256 Receipt Validation\n"

  header <> status_bar <> ooda_banner
}
