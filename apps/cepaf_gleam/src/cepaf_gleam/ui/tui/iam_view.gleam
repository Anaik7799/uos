//// =============================================================================
//// [C3I-SIL6-MSTS] /iam TUI ANSI view — L5_COGNITIVE × 12 IAM objects
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/tui/iam_view</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// Triple-interface partner of `ui/lustre/iam.gleam`. Renders the same
//// IAM admin model as ANSI text for terminal use. Shares the IamModel
//// type to satisfy SC-GLM-UI-001 (no per-interface type duplication).

import cepaf_gleam/iam/objects.{
  type IamObject, AccessToken, AuditEvent, GcpPolicy, GcpRecommendation, Group,
  Jwks, OrgPolicy, Realm, Role, ScimOp, Token, User,
}
import cepaf_gleam/ui/lustre/iam.{
  type CockpitMode, type IamModel, CockpitBright, CockpitDark, CockpitDim,
  CockpitEmergency, CockpitNormal,
}
import gleam/int
import gleam/list
import gleam/string

// ANSI color codes — minimal palette.
const reset = "\u{1b}[0m"

const dim = "\u{1b}[2m"

const bold = "\u{1b}[1m"

const cyan = "\u{1b}[36m"

const green = "\u{1b}[32m"

const yellow = "\u{1b}[33m"

const red = "\u{1b}[31m"

const blue = "\u{1b}[34m"

const magenta = "\u{1b}[35m"

pub fn render(model: IamModel) -> String {
  string.join(
    [
      header(model),
      "",
      weather_line(model),
      "",
      objects_table(model),
      "",
      supervisor_block(model),
    ],
    "\n",
  )
}

fn header(_model: IamModel) -> String {
  bold
  <> cyan
  <> "╔═══════════════════════════════════════════════════════════════╗"
  <> "\n"
  <> "║   IDENTITY & ACCESS MANAGEMENT — full L0-L7 × 12 objects     ║"
  <> "\n"
  <> "║   FerrisKey-NIF + GCP IAM federation + RustyVault custody    ║"
  <> "\n"
  <> "╚═══════════════════════════════════════════════════════════════╝"
  <> reset
}

fn weather_line(model: IamModel) -> String {
  let mode_color = cockpit_color(model.cockpit)
  let mode_text = cockpit_label(model.cockpit)
  bold
  <> mode_color
  <> "● "
  <> mode_text
  <> reset
  <> "  "
  <> dim
  <> "supervisor: "
  <> int.to_string(model.supervisor_alive_workers)
  <> "/"
  <> int.to_string(model.supervisor_total_workers)
  <> " LIVE"
  <> "  "
  <> "vault: "
  <> int.to_string(model.vault_handoffs_complete)
  <> " complete, "
  <> int.to_string(model.vault_handoffs_pending)
  <> " pending"
  <> reset
}

fn objects_table(model: IamModel) -> String {
  let header_row =
    bold <> "Object              Layer  Count    Description" <> reset
  let rows =
    objects.all_objects()
    |> list.map(fn(o) { row_for(o, model) })
    |> string.join("\n")
  header_row <> "\n" <> rows
}

fn row_for(o: IamObject, m: IamModel) -> String {
  let name = pad_right(objects.name(o), 18)
  let layer = layer_for(o)
  let count = pad_right(count_string(o, m), 8)
  let desc = description(o)
  green
  <> "  "
  <> name
  <> reset
  <> "  "
  <> blue
  <> layer
  <> reset
  <> "  "
  <> yellow
  <> count
  <> reset
  <> "  "
  <> dim
  <> desc
  <> reset
}

fn layer_for(o: IamObject) -> String {
  case o {
    User -> "L3+L7"
    Group -> "L3+L7"
    Role -> "L3   "
    Realm -> "L3+L7"
    Token -> "L0+L1"
    Jwks -> "L0+L7"
    AccessToken -> "L7   "
    ScimOp -> "L7   "
    AuditEvent -> "L0+L7"
    GcpPolicy -> "L7   "
    GcpRecommendation -> "L7   "
    OrgPolicy -> "L7   "
  }
}

fn count_string(o: IamObject, m: IamModel) -> String {
  case o {
    User -> int.to_string(m.user_count)
    Group -> int.to_string(m.group_count)
    Role -> int.to_string(m.role_count)
    Realm -> int.to_string(m.realm_count)
    Token -> int.to_string(m.token_count)
    Jwks -> int.to_string(m.jwks_keys)
    AccessToken -> int.to_string(m.access_token_cache_size)
    ScimOp -> int.to_string(m.scim_queue_depth)
    AuditEvent -> int.to_string(m.audit_events_today)
    GcpPolicy -> int.to_string(m.gcp_policy_count)
    GcpRecommendation -> int.to_string(m.gcp_recommendation_count)
    OrgPolicy -> int.to_string(m.org_policy_count)
  }
}

fn description(o: IamObject) -> String {
  case o {
    User -> "bcrypt + SCIM provisioned"
    Group -> "N:M membership + Cloud Identity"
    Role -> "c3i-* + custom layer-mask"
    Realm -> "issuer_url + GCP WIF binding"
    Token -> "EdDSA JWT, kid-rotated, 7d overlap"
    Jwks -> "GCP WIF jwks_uri source"
    AccessToken -> "STS RFC 8693, ≤55min"
    ScimOp -> "RFC 7643/7644, exp backoff"
    AuditEvent -> "append-only + Cloud Logging"
    GcpPolicy -> "etag-locked, no basic roles"
    GcpRecommendation -> "Recommender weekly 2oo3"
    OrgPolicy -> "constraints (read-only)"
  }
}

fn supervisor_block(model: IamModel) -> String {
  let workers = [
    "NifManager",
    "FreshnessMonitor",
    "JwksCacheActor",
    "StsTokenCacheActor",
    "ScimOutboundActor",
    "KeyRotationActor",
  ]
  let lines =
    workers
    |> list.map(fn(name) {
      "  "
      <> green
      <> "●"
      <> reset
      <> " "
      <> name
      <> " "
      <> dim
      <> "(LIVE)"
      <> reset
    })
    |> string.join("\n")
  bold
  <> magenta
  <> "─── Multilayer Supervisor (OneForAll, intensity=3, period=60s) ───"
  <> reset
  <> "\n"
  <> lines
  <> "\n"
  <> dim
  <> "  STS hit ratio: "
  <> int.to_string(model.sts_cache_hit_ratio_pct)
  <> "%   JWKS age: "
  <> int.to_string(model.jwks_cache_age_ms)
  <> "ms"
  <> reset
}

fn cockpit_color(c: CockpitMode) -> String {
  case c {
    CockpitDark -> dim
    CockpitDim -> blue
    CockpitNormal -> green
    CockpitBright -> yellow
    CockpitEmergency -> red
  }
}

fn cockpit_label(c: CockpitMode) -> String {
  case c {
    CockpitDark -> "DARK · IAM nominal"
    CockpitDim -> "DIM · stale cache"
    CockpitNormal -> "NORMAL · warnings"
    CockpitBright -> "BRIGHT · multiple errors"
    CockpitEmergency -> "EMERGENCY · vault/STS critical"
  }
}

fn pad_right(s: String, width: Int) -> String {
  let len = string.length(s)
  case len >= width {
    True -> s
    False -> s <> string.repeat(" ", width - len)
  }
}
