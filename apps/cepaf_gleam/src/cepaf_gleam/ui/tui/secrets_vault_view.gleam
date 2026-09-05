//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/tui/secrets_vault_view</module>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-UI-001 (triple-interface), SC-VAULT-009</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// TUI ANSI rendering of the secrets vault Andon tile. Triple-interface
//// counterpart to ui/lustre/secrets_vault.gleam — same Model, different
//// rendering target. Per SC-GLM-UI-001, every UI capability MUST be
//// available in all 3 interfaces (Lustre web + Wisp REST + TUI).

import cepaf_gleam/ui/lustre/secrets_vault.{
  type Model, type SecretStatus, SecretStatus,
}

// =====================================================================
// ANSI codes (subset; reuses cockpit color palette per SC-HMI-010)
// =====================================================================

const reset = "\u{001b}[0m"

const bold = "\u{001b}[1m"

const dim = "\u{001b}[2m"

const fg_green = "\u{001b}[32m"

const fg_yellow = "\u{001b}[33m"

const fg_red = "\u{001b}[31m"

const fg_cyan = "\u{001b}[36m"

// =====================================================================
// Public renderer
// =====================================================================

/// Render the vault Andon tile as ANSI text. Lines are 64-char box-drawn
/// to fit a typical 80-col terminal alongside other tiles.
pub fn render(model: Model) -> String {
  let header = box_top("Secrets Vault Status")
  let state_line =
    box_line(state_indicator(model) <> " State: " <> model.vault_state)
  let sync_line =
    box_line(
      "Last GCP sync: " <> int_to_string(model.last_sync_age_seconds) <> "s ago",
    )
  let counts_line =
    box_line(
      fg_green
      <> int_to_string(model.counts.fresh)
      <> " fresh"
      <> reset
      <> "  "
      <> fg_yellow
      <> int_to_string(model.counts.soft_stale)
      <> " soft-stale"
      <> reset
      <> "  "
      <> fg_red
      <> int_to_string(model.counts.hard_stale)
      <> " hard-stale"
      <> reset,
    )
  let separator = box_separator()
  let secrets = render_secrets(model.per_secret, "")
  let footer = box_bottom()

  header
  <> state_line
  <> sync_line
  <> counts_line
  <> separator
  <> secrets
  <> footer
}

// =====================================================================
// Helpers
// =====================================================================

fn state_indicator(model: Model) -> String {
  case model.dashboard_color {
    "green" -> fg_green <> "●" <> reset
    "amber" -> fg_yellow <> "●" <> reset
    "red" -> fg_red <> "●" <> reset
    _ -> dim <> "●" <> reset
  }
}

fn render_secrets(secrets: List(SecretStatus), acc: String) -> String {
  case secrets {
    [] -> acc
    [SecretStatus(name, state), ..rest] -> {
      let dot = case state {
        "fresh" -> fg_green <> "●" <> reset
        "soft_stale" -> fg_yellow <> "●" <> reset
        "hard_stale" -> fg_red <> "●" <> reset
        _ -> dim <> "○" <> reset
      }
      let line =
        box_line("  " <> dot <> " " <> name <> "  " <> dim <> state <> reset)
      render_secrets(rest, acc <> line)
    }
  }
}

fn box_top(title: String) -> String {
  bold
  <> fg_cyan
  <> "╔══ "
  <> title
  <> " ══════════════════════════════════════╗"
  <> reset
  <> "\n"
}

fn box_line(content: String) -> String {
  fg_cyan <> "║ " <> reset <> content <> "\n"
}

fn box_separator() -> String {
  fg_cyan
  <> "║ "
  <> dim
  <> "─────────────────────────────────────────────────────"
  <> reset
  <> "\n"
}

fn box_bottom() -> String {
  bold
  <> fg_cyan
  <> "╚════════════════════════════════════════════════════════╝"
  <> reset
  <> "\n"
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(n: Int) -> String
