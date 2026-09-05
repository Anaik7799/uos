//// =============================================================================
//// [C3I-SIL6-MSTS] /iam Lustre admin page — L5_COGNITIVE × 12 IAM objects
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/lustre/iam</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-IAM-001..008, SC-FERRISKEY-NIF-001..010</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// Materializes the L5_COGNITIVE row of the fractal matrix:
////   12 IamObjects × L5_COGNITIVE = 12 cells, each rendered as an admin tile.
////
//// MVU pattern (server-side Lustre 5.6+, no client JS):
////   Model = per-object counts + supervisor health + GCP federation status
////   Msg   = Refresh (full snapshot) | UpdateCounts(per-object) | ToggleCockpit
////   view  = header + 12 admin tiles + supervisor footer + Andon weather bar

import cepaf_gleam/iam/objects.{
  type IamObject, AccessToken, AuditEvent, GcpPolicy, GcpRecommendation, Group,
  Jwks, OrgPolicy, Realm, Role, ScimOp, Token, User,
}
import gleam/int
import gleam/list
import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{div, h1, h2, h3, li, p, section, span, ul}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

pub type CockpitMode {
  /// All systems healthy — Dark Cockpit (suppress noise).
  CockpitDark
  /// Some staleness — Dim mode.
  CockpitDim
  /// Active warnings — Normal visibility.
  CockpitNormal
  /// Multiple errors — Bright mode.
  CockpitBright
  /// Critical — full illumination.
  CockpitEmergency
}

pub type IamModel {
  IamModel(
    // Per-object counts (one for each of the 12 IAM objects).
    user_count: Int,
    group_count: Int,
    role_count: Int,
    realm_count: Int,
    token_count: Int,
    jwks_keys: Int,
    access_token_cache_size: Int,
    scim_queue_depth: Int,
    audit_events_today: Int,
    gcp_policy_count: Int,
    gcp_recommendation_count: Int,
    org_policy_count: Int,
    // Supervisor liveness — 6 LIVE workers per Phase 7.6.
    supervisor_alive_workers: Int,
    supervisor_total_workers: Int,
    // Vault chain status.
    vault_handoffs_complete: Int,
    vault_handoffs_pending: Int,
    // GCP federation telemetry.
    sts_cache_hit_ratio_pct: Int,
    jwks_cache_age_ms: Int,
    // Cockpit andon mode.
    cockpit: CockpitMode,
  )
}

pub type Msg {
  Refresh(model: IamModel)
  TickRefresh
  ToggleCockpit
}

pub fn init() -> IamModel {
  IamModel(
    user_count: 0,
    group_count: 0,
    role_count: 0,
    realm_count: 0,
    token_count: 0,
    jwks_keys: 0,
    access_token_cache_size: 0,
    scim_queue_depth: 0,
    audit_events_today: 0,
    gcp_policy_count: 0,
    gcp_recommendation_count: 0,
    org_policy_count: 0,
    supervisor_alive_workers: 6,
    supervisor_total_workers: 6,
    vault_handoffs_complete: 0,
    vault_handoffs_pending: 0,
    sts_cache_hit_ratio_pct: 0,
    jwks_cache_age_ms: 0,
    cockpit: CockpitDark,
  )
}

pub fn update(model: IamModel, msg: Msg) -> IamModel {
  case msg {
    Refresh(m) -> m
    TickRefresh -> model
    ToggleCockpit -> IamModel(..model, cockpit: cycle_cockpit(model.cockpit))
  }
}

fn cycle_cockpit(c: CockpitMode) -> CockpitMode {
  case c {
    CockpitDark -> CockpitDim
    CockpitDim -> CockpitNormal
    CockpitNormal -> CockpitBright
    CockpitBright -> CockpitEmergency
    CockpitEmergency -> CockpitDark
  }
}

// ---------------------------------------------------------------------------
// View — renders 12 L5 cells + supervisor footer + andon bar
// ---------------------------------------------------------------------------

pub fn view(model: IamModel) -> Element(Msg) {
  div([class("iam-page " <> cockpit_class(model.cockpit))], [
    weather_bar(model),
    div([class("iam-header")], [
      h1([], [text("Identity & Access Management")]),
      p([], [
        text(
          "FerrisKey-NIF + GCP IAM federation — full fractal L0-L7 × 12-objects",
        ),
      ]),
    ]),
    section(
      [class("iam-grid")],
      list.map(objects.all_objects(), tile_for(_, model)),
    ),
    supervisor_footer(model),
  ])
}

fn weather_bar(model: IamModel) -> Element(Msg) {
  div([class("iam-weather " <> cockpit_class(model.cockpit))], [
    span([class("emoji")], [text(weather_emoji(model.cockpit))]),
    span([class("label")], [text(weather_label(model.cockpit))]),
    span([class("badge")], [
      text(
        int.to_string(model.supervisor_alive_workers)
        <> "/"
        <> int.to_string(model.supervisor_total_workers)
        <> " workers LIVE",
      ),
    ]),
  ])
}

fn tile_for(o: IamObject, model: IamModel) -> Element(Msg) {
  div([class("iam-tile l5-cognitive")], [
    h3([], [text(objects.name(o))]),
    p([class("count")], [text(count_for(o, model))]),
    p([class("binding")], [text(layer_binding(o))]),
  ])
}

fn count_for(o: IamObject, m: IamModel) -> String {
  case o {
    User -> int.to_string(m.user_count)
    Group -> int.to_string(m.group_count)
    Role -> int.to_string(m.role_count)
    Realm -> int.to_string(m.realm_count)
    Token -> int.to_string(m.token_count) <> " active"
    Jwks -> int.to_string(m.jwks_keys) <> " keys"
    AccessToken -> int.to_string(m.access_token_cache_size) <> " cached"
    ScimOp -> int.to_string(m.scim_queue_depth) <> " in queue"
    AuditEvent -> int.to_string(m.audit_events_today) <> " today"
    GcpPolicy -> int.to_string(m.gcp_policy_count)
    GcpRecommendation -> int.to_string(m.gcp_recommendation_count)
    OrgPolicy -> int.to_string(m.org_policy_count)
  }
}

fn layer_binding(o: IamObject) -> String {
  case o {
    User -> "users — bcrypt + SCIM provisioned"
    Group -> "groups — N:M membership + Cloud Identity sync"
    Role -> "roles — c3i-* + custom layer-mask"
    Realm -> "realms — issuer_url + GCP WIF binding"
    Token -> "JWT — EdDSA, kid-rotated, 7d overlap"
    Jwks -> "JWKS — public keys, GCP WIF jwks_uri"
    AccessToken -> "GCP STS — RFC 8693, ≤55min TTL"
    ScimOp -> "SCIM 2.0 — RFC 7643/7644, exp backoff"
    AuditEvent -> "audit_log — append-only, Cloud Logging"
    GcpPolicy -> "allow-policy — etag-locked, no basic roles"
    GcpRecommendation -> "Recommender — weekly 2oo3 review"
    OrgPolicy -> "Org Policy — read-only constraint check"
  }
}

fn supervisor_footer(model: IamModel) -> Element(Msg) {
  let workers = [
    "NifManager", "FreshnessMonitor", "JwksCacheActor", "StsTokenCacheActor",
    "ScimOutboundActor", "KeyRotationActor",
  ]
  div([class("iam-supervisor")], [
    h2([], [
      text("Multilayer Supervisor (sup.OneForAll, intensity=3, period=60s)"),
    ]),
    p([], [
      text("Vault chain: "),
      span([class("metric")], [
        text(int.to_string(model.vault_handoffs_complete)),
      ]),
      text(" complete · "),
      span([class("metric")], [
        text(int.to_string(model.vault_handoffs_pending)),
      ]),
      text(" pending · "),
      span([class("metric")], [
        text(int.to_string(model.sts_cache_hit_ratio_pct) <> "% STS hit ratio"),
      ]),
      text(" · "),
      span([class("metric")], [
        text(int.to_string(model.jwks_cache_age_ms) <> "ms JWKS age"),
      ]),
    ]),
    ul(
      [class("worker-list")],
      list.map(workers, fn(name) {
        li([class("worker live")], [
          span([class("dot")], [text("●")]),
          text(name),
        ])
      }),
    ),
  ])
}

fn cockpit_class(c: CockpitMode) -> String {
  case c {
    CockpitDark -> "cockpit-dark"
    CockpitDim -> "cockpit-dim"
    CockpitNormal -> "cockpit-normal"
    CockpitBright -> "cockpit-bright"
    CockpitEmergency -> "cockpit-emergency"
  }
}

fn weather_emoji(c: CockpitMode) -> String {
  case c {
    CockpitDark -> "🌑"
    CockpitDim -> "🌒"
    CockpitNormal -> "☁️"
    CockpitBright -> "⚠️"
    CockpitEmergency -> "🚨"
  }
}

fn weather_label(c: CockpitMode) -> String {
  case c {
    CockpitDark -> "Nominal — IAM stable"
    CockpitDim -> "Stale cache detected"
    CockpitNormal -> "Active warnings"
    CockpitBright -> "Multiple errors"
    CockpitEmergency -> "EMERGENCY — vault/STS critical"
  }
}
