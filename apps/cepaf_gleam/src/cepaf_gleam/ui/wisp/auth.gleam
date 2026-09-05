//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/wisp/auth</module>
////     <fsharp-lineage>Cepaf.Security.Auth.fs (not yet ported)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-SEC-001, SC-GLM-UI-003, SC-GLM-UI-006</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Static bearer token validation ↪ future JWT/Ed25519 upgrade path.
////       Mitigation: Token read from env var C3I_API_TOKEN at call-site;
////       no global mutable state; Result(T, E) used exclusively.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Bearer-token authentication middleware for the Wisp REST API (port 4100).
////
//// Design (CPS 8.60):
////   - GET endpoints are open — operators can monitor without a token.
////   - POST/PUT/DELETE/PATCH require a valid Bearer token.
////   - Token source: env var C3I_API_TOKEN (default: "c3i-dev-token").
////   - Future upgrade: swap validate_token/1 for JWT/Ed25519 without
////     changing the handle_request call-site.
////
//// STAMP: SC-SEC-001, SC-GLM-UI-003

import cepaf_gleam/auth/oidc.{type TokenClaims}
import cepaf_gleam/auth/rbac
import envoy
import gleam/http.{Delete, Patch, Post, Put}
import gleam/http/request.{type Request as HttpRequest}
import gleam/json
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Result of inspecting the Authorization header on an incoming request.
pub type AuthResult {
  /// Token was present, well-formed, and matched the configured secret.
  Authenticated(principal: String)
  /// Authenticated via FerrisKey OIDC JWT with typed claims.
  AuthenticatedOidc(claims: TokenClaims)
  /// No Authorization header was present.
  Unauthenticated
  /// Header was present but malformed or the token did not match.
  InvalidToken(reason: String)
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Environment variable name for the API bearer token.
const token_env_var = "C3I_API_TOKEN"

/// Fallback token used when the env var is not set (development only).
const default_dev_token = "c3i-dev-token"

/// Principal name assigned to any successfully authenticated caller.
const api_principal = "api-client"

/// Prefix that MUST appear at the start of a valid Authorization header.
const bearer_prefix = "Bearer "

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Inspect the Authorization header of `request` and return an `AuthResult`.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pure function ↪ no side effects beyond env read</morphism>
///   <formal-proof>
///     <P> request is a valid HTTP request value </P>
///     <C> validate_request(request) </C>
///     <Q> Returns Authenticated, Unauthenticated, or InvalidToken. Never panics. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn validate_request(request: HttpRequest(String)) -> AuthResult {
  case request.get_header(request, "authorization") {
    Error(Nil) -> Unauthenticated
    Ok(header_value) -> validate_header(header_value)
  }
}

/// Convenience wrapper that returns `Ok(principal)` or `Error(reason)`.
/// Use this at call-sites that want a flat Result rather than the full ADT.
pub fn require_auth(request: HttpRequest(String)) -> Result(String, String) {
  case validate_request(request) {
    Authenticated(principal) -> Ok(principal)
    AuthenticatedOidc(claims) -> Ok(claims.preferred_username)
    Unauthenticated -> Error("no_token")
    InvalidToken(reason) -> Error(reason)
  }
}

/// Require OIDC authentication and return typed claims.
/// Returns Error if FerrisKey is not enabled or token is invalid.
pub fn require_oidc_auth(
  request: HttpRequest(String),
) -> Result(TokenClaims, String) {
  case validate_request(request) {
    AuthenticatedOidc(claims) -> Ok(claims)
    Authenticated(_) -> Error("oidc_required")
    Unauthenticated -> Error("no_token")
    InvalidToken(reason) -> Error(reason)
  }
}

/// Get the authenticated user context with resolved RBAC permissions.
pub fn get_authenticated_user(
  request: HttpRequest(String),
) -> Result(rbac.AuthenticatedUser, String) {
  case validate_request(request) {
    AuthenticatedOidc(claims) -> {
      let permission = rbac.resolve_permission(claims.roles)
      Ok(rbac.AuthenticatedUser(
        sub: claims.sub,
        username: claims.preferred_username,
        email: claims.email,
        roles: claims.roles,
        permission: permission,
        has_mfa: oidc.has_mfa(claims),
      ))
    }
    Authenticated(principal) ->
      Ok(rbac.AuthenticatedUser(
        sub: "static-token",
        username: principal,
        email: "",
        roles: ["c3i-admin"],
        permission: rbac.FullAccess,
        has_mfa: False,
      ))
    Unauthenticated -> Error("no_token")
    InvalidToken(reason) -> Error(reason)
  }
}

/// Return `True` when `method` is a mutation verb (POST, PUT, DELETE, PATCH).
/// GET and HEAD pass through without authentication (read-only monitoring).
pub fn is_mutation(method: http.Method) -> Bool {
  case method {
    Post | Put | Delete | Patch -> True
    _ -> False
  }
}

/// Produce a structured 401 JSON error body.
/// All JSON via gleam/json — no raw string concatenation (SC-GLM-UI-003).
pub fn auth_error_json(reason: String) -> String {
  json.object([
    #("error", json.string("unauthorized")),
    #("reason", json.string(reason)),
    #("stamp", json.string("SC-SEC-001")),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Validate a raw Authorization header value against the configured token.
///
/// When FERRISKEY_ENABLED=true, attempts OIDC JWT validation first.
/// Falls back to static token for backward compatibility (dev mode).
fn validate_header(header_value: String) -> AuthResult {
  case string.starts_with(header_value, bearer_prefix) {
    False -> InvalidToken("authorization header must use Bearer scheme")
    True -> {
      let submitted_token = string.drop_start(header_value, 7)

      // Try FerrisKey OIDC validation first when enabled
      case ferriskey_enabled() {
        True -> validate_oidc_token(submitted_token)
        False -> validate_static_token(submitted_token)
      }
    }
  }
}

/// Validate JWT token against FerrisKey OIDC.
fn validate_oidc_token(token: String) -> AuthResult {
  let config = oidc.default_config()
  let current_time = system_time_seconds()
  case oidc.validate_token(token, config, current_time) {
    Ok(claims) -> AuthenticatedOidc(claims)
    Error(err) -> {
      // Fall back to static token check (SC-AUTH-006: disable in prod)
      case validate_static_token(token) {
        Authenticated(p) -> Authenticated(p)
        _ -> InvalidToken(oidc.error_to_string(err))
      }
    }
  }
}

/// Validate against the static bearer token (original behavior).
fn validate_static_token(submitted_token: String) -> AuthResult {
  let expected_token = configured_token()
  case submitted_token == expected_token {
    True -> Authenticated(api_principal)
    False -> InvalidToken("token_mismatch")
  }
}

/// Check if FerrisKey OIDC is enabled.
fn ferriskey_enabled() -> Bool {
  case envoy.get("FERRISKEY_ENABLED") {
    Ok("true") -> True
    Ok("1") -> True
    _ -> False
  }
}

@external(erlang, "cepaf_gleam_ffi", "system_time_seconds")
fn system_time_seconds() -> Int

/// Read the expected token from the environment, falling back to the dev
/// default when the variable is absent.
fn configured_token() -> String {
  case envoy.get(token_env_var) {
    Ok(token) -> token
    Error(Nil) -> default_dev_token
  }
}
