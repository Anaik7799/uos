//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/auth</module>
////     <fsharp-lineage>New — no F# predecessor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-AUTH-001, SC-IAM-003</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Authentication management page (Lustre SSR — no client JS).
//// Displays current user identity, role assignments, MFA status,
//// and active sessions from FerrisKey IAM.
////
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-AUTH-001, SC-IAM-003

import cepaf_gleam/auth/rbac.{
  type FractalPermission, FullAccess, NoAccess, OperatorAccess, ServiceAccount,
  ViewerAccess,
}
import gleam/list
import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{div, h2, h3, li, p, span, table, tbody, td, th,
  tr, ul}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

pub type AuthModel {
  AuthModel(
    username: String,
    email: String,
    roles: List(String),
    permission: FractalPermission,
    has_mfa: Bool,
    active_sessions: Int,
    ferriskey_enabled: Bool,
    issuer_url: String,
  )
}

pub type AuthMsg {
  RefreshAuth
  SessionsLoaded(count: Int)
}

// ---------------------------------------------------------------------------
// Init / Update / View (MVU)
// ---------------------------------------------------------------------------

pub fn init() -> AuthModel {
  AuthModel(
    username: "",
    email: "",
    roles: [],
    permission: NoAccess,
    has_mfa: False,
    active_sessions: 0,
    ferriskey_enabled: False,
    issuer_url: "http://localhost:8080/realms/c3i-dev",
  )
}

pub fn update(model: AuthModel, msg: AuthMsg) -> AuthModel {
  case msg {
    RefreshAuth -> model
    SessionsLoaded(count) -> AuthModel(..model, active_sessions: count)
  }
}

pub fn view(model: AuthModel) -> Element(AuthMsg) {
  div([class("auth-page")], [
    h2([class("page-title")], [text("Authentication & Identity")]),
    // Identity card
    identity_card(model),
    // RBAC permissions
    rbac_card(model),
    // MFA status
    mfa_card(model),
    // FerrisKey status
    ferriskey_status_card(model),
  ])
}

// ---------------------------------------------------------------------------
// Sub-views
// ---------------------------------------------------------------------------

fn identity_card(model: AuthModel) -> Element(AuthMsg) {
  div([class("card identity-card")], [
    h3([], [text("Current Identity")]),
    table([class("data-table")], [
      tbody([], [
        info_row("Username", model.username),
        info_row("Email", model.email),
        info_row("Active Sessions", case model.active_sessions {
          0 -> "None"
          n -> int_to_string(n)
        }),
      ]),
    ]),
  ])
}

fn rbac_card(model: AuthModel) -> Element(AuthMsg) {
  div([class("card rbac-card")], [
    h3([], [text("Roles & Permissions")]),
    div([class("roles-list")], [
      p([], [
        text("Permission Level: "),
        span([class("badge " <> permission_badge_class(model.permission))], [
          text(rbac.permission_to_string(model.permission)),
        ]),
      ]),
      h3([], [text("Assigned Roles")]),
      ul([], case model.roles {
        [] -> [li([], [text("No roles assigned")])]
        roles ->
          list.map(roles, fn(role) {
            li([class("role-item")], [text(role)])
          })
      }),
    ]),
    // Accessible layers
    h3([], [text("Accessible Fractal Layers")]),
    div([class("layer-chips")],
      rbac.accessible_layers(model.permission)
      |> list.map(fn(layer) {
        let layer_str = case layer {
          domain.L0Constitutional -> "L0"
          domain.L1AtomicDebug -> "L1"
          domain.L2Component -> "L2"
          domain.L3Transaction -> "L3"
          domain.L4System -> "L4"
          domain.L5Cognitive -> "L5"
          domain.L6Ecosystem -> "L6"
          domain.L7Federation -> "L7"
        }
        span([class("chip layer-chip")], [text(layer_str)])
      }),
    ),
  ])
}

fn mfa_card(model: AuthModel) -> Element(AuthMsg) {
  div([class("card mfa-card")], [
    h3([], [text("Multi-Factor Authentication")]),
    p([], [
      text("MFA Status: "),
      span(
        [
          class(case model.has_mfa {
            True -> "badge badge-success"
            False -> "badge badge-warning"
          }),
        ],
        [
          text(case model.has_mfa {
            True -> "Enrolled"
            False -> "Not Enrolled"
          }),
        ],
      ),
    ]),
    p([class("mfa-note")], [
      text(
        "MFA is required for L0 Constitutional operations (Guardian approval, emergency stop).",
      ),
    ]),
  ])
}

fn ferriskey_status_card(model: AuthModel) -> Element(AuthMsg) {
  div([class("card ferriskey-card")], [
    h3([], [text("FerrisKey IAM")]),
    table([class("data-table")], [
      tbody([], [
        info_row("Status", case model.ferriskey_enabled {
          True -> "Connected"
          False -> "Disabled (static token mode)"
        }),
        info_row("Issuer", model.issuer_url),
        info_row("Auth Method", case model.ferriskey_enabled {
          True -> "OIDC JWT (FerrisKey)"
          False -> "Static Bearer Token"
        }),
      ]),
    ]),
  ])
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn info_row(label: String, value: String) -> Element(AuthMsg) {
  tr([], [
    th([class("info-label")], [text(label)]),
    td([class("info-value")], [text(value)]),
  ])
}

fn permission_badge_class(perm: FractalPermission) -> String {
  case perm {
    FullAccess -> "badge-admin"
    OperatorAccess -> "badge-operator"
    ViewerAccess -> "badge-viewer"
    ServiceAccount -> "badge-service"
    NoAccess -> "badge-none"
  }
}

@external(erlang, "erlang", "integer_to_list")
fn int_to_string(n: Int) -> String

import cepaf_gleam/ui/domain
