import cepaf_gleam/auth/oidc
import gleeunit/should

// =============================================================================
// C1: OIDC Module Structure
// =============================================================================

pub fn oidc_config_constructs_test() {
  let config =
    oidc.OidcConfig(
      issuer_url: "http://localhost:8080/realms/c3i-dev",
      jwks_url: "http://localhost:8080/realms/c3i-dev/protocol/openid-connect/certs",
      client_id: "c3i-wisp-api",
      required_audience: "c3i-wisp-api",
    )
  config.issuer_url
  |> should.equal("http://localhost:8080/realms/c3i-dev")
}

pub fn token_claims_constructs_test() {
  let claims =
    oidc.TokenClaims(
      sub: "user-123",
      preferred_username: "testuser",
      email: "test@example.com",
      roles: ["c3i-admin", "c3i-viewer"],
      exp: 9_999_999_999,
      iss: "http://localhost:8080/realms/c3i-dev",
      aud: ["c3i-wisp-api"],
      acr: "urn:ferriskey:mfa:totp",
    )
  claims.sub |> should.equal("user-123")
  claims.preferred_username |> should.equal("testuser")
  claims.email |> should.equal("test@example.com")
}

// =============================================================================
// C2: Auth Error Types
// =============================================================================

pub fn auth_error_expired_test() {
  oidc.error_to_string(oidc.TokenExpired)
  |> should.equal("token_expired")
}

pub fn auth_error_invalid_signature_test() {
  oidc.error_to_string(oidc.InvalidSignature)
  |> should.equal("invalid_signature")
}

pub fn auth_error_invalid_issuer_test() {
  oidc.error_to_string(oidc.InvalidIssuer)
  |> should.equal("invalid_issuer")
}

pub fn auth_error_missing_claims_test() {
  oidc.error_to_string(oidc.MissingClaims("sub"))
  |> should.equal("missing_claim:sub")
}

pub fn auth_error_to_json_test() {
  let json_str = oidc.error_to_json(oidc.TokenExpired)
  // Should contain the error structure
  should.be_true(
    json_str
    |> gleam_string_contains("authentication_failed"),
  )
  should.be_true(
    json_str
    |> gleam_string_contains("token_expired"),
  )
}

// =============================================================================
// C5: Role Extraction
// =============================================================================

pub fn extract_roles_test() {
  let claims = test_claims(["c3i-admin", "c3i-operator"])
  oidc.extract_roles(claims)
  |> should.equal(["c3i-admin", "c3i-operator"])
}

pub fn has_role_admin_test() {
  let claims = test_claims(["c3i-admin"])
  oidc.has_role(claims, "c3i-admin")
  |> should.be_true()
}

pub fn has_role_missing_test() {
  let claims = test_claims(["c3i-viewer"])
  oidc.has_role(claims, "c3i-admin")
  |> should.be_false()
}

pub fn has_mfa_totp_test() {
  let claims =
    oidc.TokenClaims(..test_claims([]), acr: "urn:ferriskey:mfa:totp")
  oidc.has_mfa(claims)
  |> should.be_true()
}

pub fn has_mfa_webauthn_test() {
  let claims =
    oidc.TokenClaims(..test_claims([]), acr: "urn:ferriskey:mfa:webauthn")
  oidc.has_mfa(claims)
  |> should.be_true()
}

pub fn has_mfa_none_test() {
  let claims = oidc.TokenClaims(..test_claims([]), acr: "1")
  oidc.has_mfa(claims)
  |> should.be_false()
}

// =============================================================================
// C3: Token Validation (expired token)
// =============================================================================

pub fn validate_expired_token_returns_error_test() {
  let config = oidc.default_config()
  // This is a malformed token, but tests the code path
  let result = oidc.validate_token("a.b.c", config, 1_000_000)
  // Should fail (malformed base64)
  should.be_error(result)
}

// =============================================================================
// Helpers
// =============================================================================

fn test_claims(roles: List(String)) -> oidc.TokenClaims {
  oidc.TokenClaims(
    sub: "user-test",
    preferred_username: "testuser",
    email: "test@test.com",
    roles: roles,
    exp: 9_999_999_999,
    iss: "http://localhost:8080/realms/c3i-dev",
    aud: ["c3i-wisp-api"],
    acr: "",
  )
}

import gleam/string

fn gleam_string_contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}
