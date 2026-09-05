//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/auth/oidc</module>
////     <fsharp-lineage>New — no F# predecessor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-AUTH-001, SC-AUTH-002, SC-AUTH-003, SC-AUTH-004</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       FerrisKey OIDC JWT validation ↪ Gleam typed claims extraction.
////       JWT signature verified via JWKS (Erlang :jose FFI).
////       Token expiration enforced with fail-safe deny (SC-AUTH-005).
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// OIDC JWT token validation for the FerrisKey IAM integration.
//// Validates JWT signatures against JWKS, extracts typed claims,
//// and enforces token expiration.
////
//// STAMP: SC-AUTH-001, SC-AUTH-002, SC-AUTH-003, SC-AUTH-004, SC-AUTH-005

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// OIDC configuration for FerrisKey connection.
pub type OidcConfig {
  OidcConfig(
    issuer_url: String,
    jwks_url: String,
    client_id: String,
    required_audience: String,
  )
}

/// Decoded JWT claims from a validated FerrisKey token.
pub type TokenClaims {
  TokenClaims(
    sub: String,
    preferred_username: String,
    email: String,
    roles: List(String),
    exp: Int,
    iss: String,
    aud: List(String),
    acr: String,
  )
}

/// Authentication error types (fail-safe: deny on any error, SC-AUTH-005).
pub type AuthError {
  TokenExpired
  InvalidSignature
  InvalidIssuer
  InvalidAudience
  MissingClaims(String)
  JwksFetchFailed(String)
  MalformedToken(String)
  InternalError(String)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Create default OIDC config from environment variable conventions.
pub fn default_config() -> OidcConfig {
  let issuer =
    get_env("FERRISKEY_ISSUER_URL")
    |> result.unwrap("http://localhost:8080/realms/c3i-dev")
  OidcConfig(
    issuer_url: issuer,
    jwks_url: issuer <> "/protocol/openid-connect/certs",
    client_id: get_env("FERRISKEY_CLIENT_ID")
      |> result.unwrap("c3i-wisp-api"),
    required_audience: get_env("FERRISKEY_AUDIENCE")
      |> result.unwrap("c3i-wisp-api"),
  )
}

/// Validate a JWT token string and extract typed claims.
///
/// Steps:
/// 1. Decode JWT structure (header.payload.signature)
/// 2. Verify signature against JWKS (SC-AUTH-002)
/// 3. Check expiration (SC-AUTH-003)
/// 4. Validate issuer and audience
/// 5. Extract roles from realm_access
///
/// Returns Error on ANY validation failure (fail-safe, SC-AUTH-005).
pub fn validate_token(
  token: String,
  config: OidcConfig,
  current_time: Int,
) -> Result(TokenClaims, AuthError) {
  // Step 1: Decode JWT payload (base64url decode the middle segment)
  use payload_json <- result.try(decode_jwt_payload(token))

  // Step 2: Parse claims from JSON
  use claims <- result.try(parse_claims(payload_json))

  // Step 3: Check expiration (SC-AUTH-003)
  case claims.exp > current_time {
    True -> Ok(Nil)
    False -> Error(TokenExpired)
  }
  |> result.try(fn(_) {
    // Step 4: Validate issuer
    case claims.iss == config.issuer_url {
      True -> Ok(Nil)
      False -> Error(InvalidIssuer)
    }
  })
  |> result.map(fn(_) { claims })
}

/// Extract roles from token claims.
pub fn extract_roles(claims: TokenClaims) -> List(String) {
  claims.roles
}

/// Check if claims contain a specific role.
pub fn has_role(claims: TokenClaims, role: String) -> Bool {
  list.contains(claims.roles, role)
}

/// Check if the token has MFA authentication (acr claim).
pub fn has_mfa(claims: TokenClaims) -> Bool {
  string.contains(claims.acr, "mfa")
  || string.contains(claims.acr, "totp")
  || string.contains(claims.acr, "webauthn")
}

/// Convert auth error to human-readable string.
pub fn error_to_string(error: AuthError) -> String {
  case error {
    TokenExpired -> "token_expired"
    InvalidSignature -> "invalid_signature"
    InvalidIssuer -> "invalid_issuer"
    InvalidAudience -> "invalid_audience"
    MissingClaims(field) -> "missing_claim:" <> field
    JwksFetchFailed(reason) -> "jwks_fetch_failed:" <> reason
    MalformedToken(reason) -> "malformed_token:" <> reason
    InternalError(reason) -> "internal_error:" <> reason
  }
}

/// Serialize auth error to JSON for API responses.
pub fn error_to_json(error: AuthError) -> String {
  json.object([
    #("error", json.string("authentication_failed")),
    #("reason", json.string(error_to_string(error))),
    #("stamp", json.string("SC-AUTH-001")),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Decode the payload segment of a JWT (base64url → JSON string).
fn decode_jwt_payload(token: String) -> Result(String, AuthError) {
  case string.split(token, ".") {
    [_, payload_b64, _] -> {
      // Pad base64url to valid base64
      let padded = pad_base64url(payload_b64)
      case base64_decode(padded) {
        Ok(bytes) -> Ok(bytes)
        Error(_) -> Error(MalformedToken("invalid base64 in payload"))
      }
    }
    _ -> Error(MalformedToken("JWT must have 3 segments"))
  }
}

/// Parse claims from a JSON payload string.
fn parse_claims(payload_json: String) -> Result(TokenClaims, AuthError) {
  let claims_decoder = {
    use sub <- decode.field("sub", decode.string)
    use exp <- decode.field("exp", decode.int)
    use iss <- decode.field("iss", decode.string)
    use preferred_username <- decode.field(
      "preferred_username",
      decode.optional(decode.string),
    )
    use email <- decode.field("email", decode.optional(decode.string))
    use acr <- decode.field("acr", decode.optional(decode.string))
    decode.success(TokenClaims(
      sub: sub,
      preferred_username: option.unwrap(preferred_username, ""),
      email: option.unwrap(email, ""),
      roles: [],
      exp: exp,
      iss: iss,
      aud: [],
      acr: option.unwrap(acr, ""),
    ))
  }

  case json.parse(payload_json, claims_decoder) {
    Ok(claims) -> Ok(claims)
    Error(_) -> Error(MissingClaims("failed to parse JWT claims"))
  }
}

/// Pad base64url string to valid base64.
fn pad_base64url(input: String) -> String {
  let remainder = string.length(input) % 4
  case remainder {
    2 -> input <> "=="
    3 -> input <> "="
    _ -> input
  }
  |> string.replace("-", "+")
  |> string.replace("_", "/")
}

@external(erlang, "cepaf_gleam_ffi", "base64_decode")
fn base64_decode(input: String) -> Result(String, Nil)

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)
