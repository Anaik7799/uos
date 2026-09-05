//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/secrets_vault</module>
////     <fsharp-lineage>New — no F# predecessor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-AGUI-UI-008, SC-VAULT-009, SC-GLM-UI-001, SC-GLM-UI-002</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Andon dashboard tile for the secrets vault. Refreshes every 30s per
//// SC-AGUI-UI-008. Per-secret freshness state (fresh/soft-stale/hard-stale)
//// shown with green/amber/red color coding driven by the dashboard_color()
//// classifier in ui/wisp/secret_api.gleam.
////
//// Lustre MVU pattern (SC-GLM-UI-002): Model / Msg / init / update / view.
//// Server-rendered HTML; no client JS emitted. Polls /api/v1/secret-status.

// =====================================================================
// Model
// =====================================================================

pub type SecretStatus {
  SecretStatus(name: String, state: String)
}

pub type Counts {
  Counts(fresh: Int, soft_stale: Int, hard_stale: Int)
}

pub type Model {
  Model(
    vault_state: String,
    last_sync_age_seconds: Int,
    counts: Counts,
    per_secret: List(SecretStatus),
    dashboard_color: String,
    last_refresh_ts: Int,
  )
}

pub fn init() -> Model {
  Model(
    vault_state: "Sealed",
    last_sync_age_seconds: 0,
    counts: Counts(fresh: 0, soft_stale: 0, hard_stale: 0),
    per_secret: [],
    dashboard_color: "amber",
    last_refresh_ts: 0,
  )
}

// =====================================================================
// Messages
// =====================================================================

pub type Msg {
  /// 30-second refresh tick (SC-AGUI-UI-008)
  Tick(now_seconds: Int)
  /// New status payload received from /api/v1/secret-status
  StatusReceived(
    vault_state: String,
    last_sync_age: Int,
    counts: Counts,
    per_secret: List(SecretStatus),
    color: String,
    now: Int,
  )
  /// HTTP fetch failed; show degraded state
  StatusFetchFailed(reason: String)
  /// Operator clicks "Refresh now"
  RefreshNowClicked
}

// =====================================================================
// Update — pure transitions, exhaustive (SC-GLM-UI-002)
// =====================================================================

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    Tick(_) -> model

    // ↑ Tick just triggers an effect to fetch — handled by view layer
    StatusReceived(vault_state, last_sync_age, counts, per_secret, color, now) ->
      Model(
        vault_state: vault_state,
        last_sync_age_seconds: last_sync_age,
        counts: counts,
        per_secret: per_secret,
        dashboard_color: color,
        last_refresh_ts: now,
      )

    StatusFetchFailed(_reason) ->
      Model(..model, dashboard_color: "amber", vault_state: "Unknown")

    RefreshNowClicked -> model
  }
}

// =====================================================================
// View — pure rendering of the Andon tile
// =====================================================================

pub fn view_html(model: Model) -> String {
  let header =
    "<div class=\"vault-tile vault-tile-"
    <> model.dashboard_color
    <> "\" data-testid=\"secrets-vault-tile\">"
    <> "<h2>🔐 Secrets Vault</h2>"

  let state_row =
    "<div class=\"vault-state\" data-vault-state=\""
    <> model.vault_state
    <> "\">State: "
    <> render_state_indicator(model.vault_state)
    <> " "
    <> model.vault_state
    <> "</div>"

  let sync_row =
    "<div class=\"sync-age\">Last GCP sync: "
    <> int_to_string(model.last_sync_age_seconds)
    <> "s ago</div>"

  let counts_row =
    "<div class=\"counts\">"
    <> "<span class=\"fresh\">"
    <> int_to_string(model.counts.fresh)
    <> " fresh</span> "
    <> "<span class=\"soft-stale\">"
    <> int_to_string(model.counts.soft_stale)
    <> " soft-stale</span> "
    <> "<span class=\"hard-stale\">"
    <> int_to_string(model.counts.hard_stale)
    <> " hard-stale</span>"
    <> "</div>"

  let secret_list =
    "<ul class=\"per-secret\">"
    <> render_per_secret(model.per_secret)
    <> "</ul>"

  let refresh_btn =
    "<button data-testid=\"refresh-secrets\" data-action=\"refresh-secret-status\">Refresh now</button>"

  let footer = "</div>"

  header
  <> state_row
  <> sync_row
  <> counts_row
  <> secret_list
  <> refresh_btn
  <> footer
}

fn render_state_indicator(state: String) -> String {
  case state {
    "Active" -> "<span class=\"led led-green\">●</span>"
    "Sealed" -> "<span class=\"led led-amber\">●</span>"
    "Corrupt" | "Halted" -> "<span class=\"led led-red\">●</span>"
    _ -> "<span class=\"led led-grey\">●</span>"
  }
}

fn render_per_secret(secrets: List(SecretStatus)) -> String {
  do_render_per_secret(secrets, "")
}

fn do_render_per_secret(secrets: List(SecretStatus), acc: String) -> String {
  case secrets {
    [] -> acc
    [SecretStatus(name, state), ..tail] -> {
      let li =
        "<li class=\"secret-"
        <> state
        <> "\" data-secret=\""
        <> name
        <> "\" data-state=\""
        <> state
        <> "\">"
        <> render_state_dot(state)
        <> " <code>"
        <> name
        <> "</code> — "
        <> state
        <> "</li>"
      do_render_per_secret(tail, acc <> li)
    }
  }
}

fn render_state_dot(state: String) -> String {
  case state {
    "fresh" -> "🟢"
    "soft_stale" -> "🟡"
    "hard_stale" -> "🔴"
    _ -> "⚪"
  }
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(n: Int) -> String
