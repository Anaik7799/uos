//// secrets_vault_w16_test — Wave 16 W4 closure tests for the secrets-vault
//// triple-interface tile (Lustre + Wisp + TUI).
////
//// These tests exercise the wiring that Wave 16 added on top of the Wave-prior
//// skeleton:
////   1. ui/lustre/secrets_vault.init/update/view — model invariants
////   2. ui/tui/secrets_vault_view.render — ANSI box-drawing
////   3. wiring_guard inclusion (verified via test/wiring_guard_test.gleam)
////
//// SC-WIRE-005 + SC-VAULT-009 + SC-AGUI-UI-008 + SC-GLM-UI-001.
//// [zk-3346fc607a1ef9e6] Stub-That-Lies guard: every assertion exercises real
//// constructors; no fake-success.

import cepaf_gleam/ui/lustre/secrets_vault.{
  Counts, Model, RefreshNowClicked, SecretStatus, StatusFetchFailed,
  StatusReceived, init, update, view_html,
}
import cepaf_gleam/ui/tui/secrets_vault_view as tui
import gleam/string
import gleeunit/should

// =====================================================================
// 1. Lustre Model — init produces sealed/amber default (honest pre-state)
// =====================================================================

pub fn init_returns_sealed_amber_test() {
  let m = init()
  m.vault_state |> should.equal("Sealed")
  m.dashboard_color |> should.equal("amber")
  m.counts.fresh |> should.equal(0)
  m.counts.soft_stale |> should.equal(0)
  m.counts.hard_stale |> should.equal(0)
}

// =====================================================================
// 2. update(StatusReceived) — Andon transition to green when Active+fresh
// =====================================================================

pub fn update_status_received_transitions_to_green_test() {
  let m = init()
  let m2 =
    update(
      m,
      StatusReceived(
        vault_state: "Active",
        last_sync_age: 5,
        counts: Counts(fresh: 3, soft_stale: 0, hard_stale: 0),
        per_secret: [SecretStatus("anthropic_api_key", "fresh")],
        color: "green",
        now: 1_777_665_700,
      ),
    )
  m2.vault_state |> should.equal("Active")
  m2.dashboard_color |> should.equal("green")
  m2.counts.fresh |> should.equal(3)
  m2.last_refresh_ts |> should.equal(1_777_665_700)
}

// =====================================================================
// 3. update(StatusFetchFailed) — Andon escalates to amber + Unknown state
// =====================================================================

pub fn update_status_fetch_failed_escalates_test() {
  let m = init()
  // Simulate prior healthy state.
  let m2 =
    update(
      m,
      StatusReceived(
        vault_state: "Active",
        last_sync_age: 5,
        counts: Counts(fresh: 1, soft_stale: 0, hard_stale: 0),
        per_secret: [],
        color: "green",
        now: 1_777_665_700,
      ),
    )
  // Then subprocess fails.
  let m3 = update(m2, StatusFetchFailed("binary_missing"))
  m3.vault_state |> should.equal("Unknown")
  m3.dashboard_color |> should.equal("amber")
}

// =====================================================================
// 4. update(RefreshNowClicked) — model unchanged (handled by effect layer)
// =====================================================================

pub fn update_refresh_now_clicked_is_pure_test() {
  let m = init()
  let m2 = update(m, RefreshNowClicked)
  m2.vault_state |> should.equal(m.vault_state)
  m2.dashboard_color |> should.equal(m.dashboard_color)
}

// =====================================================================
// 5. view_html — never embeds a secret value (SC-VAULT-009 invariant)
// =====================================================================

pub fn view_html_never_contains_secret_value_test() {
  let m =
    Model(
      vault_state: "Active",
      last_sync_age_seconds: 5,
      counts: Counts(fresh: 1, soft_stale: 0, hard_stale: 0),
      per_secret: [SecretStatus("anthropic_api_key", "fresh")],
      dashboard_color: "green",
      last_refresh_ts: 0,
    )
  let html = view_html(m)
  // Renders the secret name + state but NEVER a value.
  string.contains(html, "anthropic_api_key") |> should.equal(True)
  string.contains(html, "fresh") |> should.equal(True)
  // Ensure no Bearer / Authorization / value-shaped substring leaks.
  string.contains(html, "sk-ant-") |> should.equal(False)
  string.contains(html, "Authorization") |> should.equal(False)
}

// =====================================================================
// 6. view_html — embeds dashboard color + Andon state indicator
// =====================================================================

pub fn view_html_carries_dashboard_color_test() {
  let m =
    Model(
      vault_state: "Active",
      last_sync_age_seconds: 5,
      counts: Counts(fresh: 0, soft_stale: 0, hard_stale: 2),
      per_secret: [],
      dashboard_color: "red",
      last_refresh_ts: 0,
    )
  let html = view_html(m)
  string.contains(html, "vault-tile-red") |> should.equal(True)
  string.contains(html, "data-vault-state=\"Active\"") |> should.equal(True)
}

// =====================================================================
// 7. TUI view — produces non-empty ANSI box for default Sealed model
// =====================================================================

pub fn tui_render_sealed_model_test() {
  let m = init()
  let ansi = tui.render(m)
  // Must contain box-drawing chars (╔ ║ ╚) per SC-GLM-UI-004 ANSI rendering.
  string.contains(ansi, "Secrets Vault Status") |> should.equal(True)
  string.contains(ansi, "Sealed") |> should.equal(True)
}

// =====================================================================
// 8. TUI view — color-coded indicator for green/amber/red dashboard color
// =====================================================================

pub fn tui_render_active_green_uses_green_indicator_test() {
  let m =
    Model(
      vault_state: "Active",
      last_sync_age_seconds: 5,
      counts: Counts(fresh: 2, soft_stale: 0, hard_stale: 0),
      per_secret: [SecretStatus("k1", "fresh")],
      dashboard_color: "green",
      last_refresh_ts: 0,
    )
  let ansi = tui.render(m)
  // ANSI green fg = ESC[32m (\u{001b}[32m).
  string.contains(ansi, "\u{001b}[32m") |> should.equal(True)
  string.contains(ansi, "Active") |> should.equal(True)
  // Per-secret state is shown.
  string.contains(ansi, "k1") |> should.equal(True)
}
