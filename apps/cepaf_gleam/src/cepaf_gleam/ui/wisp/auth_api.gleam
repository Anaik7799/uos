//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/wisp/auth_api</module>
////     <fsharp-lineage>New — no F# predecessor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-UI-003, SC-AUTH-001, SC-IAM-003</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Wisp REST API endpoints for authentication management.
//// Returns typed JSON via gleam/json (SC-GLM-UI-003).
////
//// Endpoints:
////   GET  /api/v1/auth/me        — current user claims
////   GET  /api/v1/auth/status     — FerrisKey connection status
////   POST /api/v1/auth/telegram   — Telegram token exchange
////
//// STAMP: SC-GLM-UI-003, SC-AUTH-001, SC-IAM-003

import cepaf_gleam/auth/rbac
import gleam/json
import gleam/list

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// GET /api/v1/auth/me — return current user claims as JSON.
pub fn me_json(user: rbac.AuthenticatedUser) -> String {
  json.object([
    #("sub", json.string(user.sub)),
    #("username", json.string(user.username)),
    #("email", json.string(user.email)),
    #("roles", json.array(user.roles, json.string)),
    #("permission", json.string(rbac.permission_to_string(user.permission))),
    #("has_mfa", json.bool(user.has_mfa)),
    #("accessible_layers",
      json.array(
        rbac.accessible_layers(user.permission)
        |> list.map(fn(l) {
          case l {
            domain.L0Constitutional -> "L0"
            domain.L1AtomicDebug -> "L1"
            domain.L2Component -> "L2"
            domain.L3Transaction -> "L3"
            domain.L4System -> "L4"
            domain.L5Cognitive -> "L5"
            domain.L6Ecosystem -> "L6"
            domain.L7Federation -> "L7"
          }
        }),
        json.string,
      ),
    ),
  ])
  |> json.to_string()
}

/// GET /api/v1/auth/status — return FerrisKey IAM connection status.
pub fn status_json(ferriskey_enabled: Bool) -> String {
  json.object([
    #("page", json.string("auth")),
    #("ferriskey_enabled", json.bool(ferriskey_enabled)),
    #("auth_method", json.string(case ferriskey_enabled {
      True -> "oidc_jwt"
      False -> "static_bearer_token"
    })),
    #("stamp", json.string("SC-AUTH-001")),
    #("iam_features", json.object([
      #("oidc", json.bool(ferriskey_enabled)),
      #("rbac", json.bool(ferriskey_enabled)),
      #("mfa", json.bool(ferriskey_enabled)),
      #("webhooks", json.bool(ferriskey_enabled)),
      #("federation", json.bool(ferriskey_enabled)),
      #("audit_events", json.bool(ferriskey_enabled)),
    ])),
  ])
  |> json.to_string()
}

/// Error response for unauthorized requests.
pub fn unauthorized_json(reason: String) -> String {
  json.object([
    #("error", json.string("unauthorized")),
    #("reason", json.string(reason)),
    #("stamp", json.string("SC-AUTH-001")),
  ])
  |> json.to_string()
}

/// Error response for forbidden requests (authenticated but insufficient role).
pub fn forbidden_json(reason: String) -> String {
  json.object([
    #("error", json.string("forbidden")),
    #("reason", json.string(reason)),
    #("stamp", json.string("SC-IAM-003")),
  ])
  |> json.to_string()
}

import cepaf_gleam/ui/domain
