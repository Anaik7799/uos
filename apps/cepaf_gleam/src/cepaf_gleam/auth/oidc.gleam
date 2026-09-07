//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/auth/oidc</module>
////     <fsharp-lineage>New — no F# predecessor</fsharp-lineage>
////   </identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance>
////     <stamp-controls>SC-AUTH-001, SC-AUTH-002, SC-AUTH-003, SC-AUTH-004, SC-AUTH-005</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       A bounded compact JWS plus issuer-bound, fresh, preloaded Ed25519
////       JWKS snapshot maps to typed claims only after every observation
////       (structure, signature, issuer, audience, time, subject) accepts.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// FerrisKey EdDSA/Ed25519 JWT verification. The request path performs no
//// network I/O and never trusts token-directed key material.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

const default_snapshot_max_age_seconds = 300

const maximum_snapshot_max_age_seconds = 3600

const allowed_clock_skew_seconds = 60

const maximum_audiences = 16

/// A validated, operator-provided JWKS snapshot bound to an OIDC config.
/// Its JSON contains public verification keys only.
pub opaque type JwksSnapshot {
  JwksSnapshot(json: String, loaded_at: Int, max_age_seconds: Int)
}

/// OIDC configuration for FerrisKey connection.
pub type OidcConfig {
  OidcConfig(
    issuer_url: String,
    jwks_url: String,
    client_id: String,
    required_audience: String,
    jwks_snapshot: Option(JwksSnapshot),
  )
}

/// Claims extracted only after cryptographic and semantic validation.
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
    nbf: Option(Int),
    iat: Option(Int),
  )
}

/// Authentication errors. Every variant denotes rejection.
pub type AuthError {
  TokenExpired
  TokenNotYetValid
  TokenIssuedInFuture
  InvalidSignature
  InvalidIssuer
  InvalidAudience
  InvalidTimeClaims
  MissingClaims(String)
  MissingJwksSnapshot
  StaleJwksSnapshot
  InvalidJwksSnapshot(String)
  JwksFetchFailed(String)
  MalformedToken(String)
  InternalError(String)
}

/// Configuration without key authority. Validation fails closed until a
/// trusted snapshot is attached with `load_jwks_snapshot`.
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
    jwks_snapshot: None,
  )
}

/// Validate and attach a trusted JWKS snapshot. Refresh is explicit: callers
/// replace the returned immutable config with another successful result.
pub fn load_jwks_snapshot(
  config: OidcConfig,
  snapshot_json: String,
  loaded_at: Int,
  max_age_seconds: Int,
) -> Result(OidcConfig, AuthError) {
  case
    loaded_at >= 0
    && max_age_seconds > 0
    && max_age_seconds <= maximum_snapshot_max_age_seconds
  {
    False -> Error(InvalidJwksSnapshot("invalid_snapshot_freshness"))
    True ->
      case validate_jwks_snapshot(snapshot_json) {
        Error(reason) -> Error(InvalidJwksSnapshot(reason))
        Ok(Nil) ->
          Ok(
            OidcConfig(
              ..config,
              jwks_snapshot: Some(JwksSnapshot(
                json: snapshot_json,
                loaded_at: loaded_at,
                max_age_seconds: max_age_seconds,
              )),
            ),
          )
      }
  }
}

/// Load a pre-fetched JWKS snapshot from the process environment. This reads
/// local configuration only; it never fetches `jwks_url`.
pub fn config_from_env() -> Result(OidcConfig, AuthError) {
  let config = default_config()
  use snapshot_json <- result.try(
    get_env("FERRISKEY_JWKS_SNAPSHOT")
    |> result.map_error(fn(_) { MissingJwksSnapshot }),
  )
  use loaded_at_text <- result.try(
    get_env("FERRISKEY_JWKS_LOADED_AT")
    |> result.map_error(fn(_) { MissingJwksSnapshot }),
  )
  use loaded_at <- result.try(
    int.parse(loaded_at_text)
    |> result.map_error(fn(_) {
      InvalidJwksSnapshot("invalid_snapshot_loaded_at")
    }),
  )
  let max_age = case get_env("FERRISKEY_JWKS_MAX_AGE_SECONDS") {
    Error(_) -> Ok(default_snapshot_max_age_seconds)
    Ok(value) ->
      int.parse(value)
      |> result.map_error(fn(_) {
        InvalidJwksSnapshot("invalid_snapshot_max_age")
      })
  }
  use max_age <- result.try(max_age)
  load_jwks_snapshot(config, snapshot_json, loaded_at, max_age)
}

/// Validate a compact EdDSA/Ed25519 JWT against the config's fresh snapshot.
///
/// Semantics: `accept ≙ structure ∧ key-profile ∧ signature ∧ fresh-jwks ∧
/// issuer ∧ audience ∧ expiry ∧ optional-time-bounds ∧ nonempty-subject`.
pub fn validate_token(
  token: String,
  config: OidcConfig,
  current_time: Int,
) -> Result(TokenClaims, AuthError) {
  use snapshot <- result.try(require_fresh_snapshot(
    config.jwks_snapshot,
    current_time,
  ))
  use payload_json <- result.try(
    verify_ed25519_jwt(token, snapshot.json)
    |> result.map_error(classify_verifier_error),
  )
  use claims <- result.try(parse_claims(payload_json))
  use _ <- result.try(validate_subject(claims.sub))
  use _ <- result.try(validate_issuer(claims.iss, config.issuer_url))
  use _ <- result.try(validate_audience(claims.aud, config.required_audience))
  use _ <- result.try(validate_times(claims, current_time))
  Ok(claims)
}

pub fn extract_roles(claims: TokenClaims) -> List(String) {
  claims.roles
}

pub fn has_role(claims: TokenClaims, role: String) -> Bool {
  list.contains(claims.roles, role)
}

pub fn has_mfa(claims: TokenClaims) -> Bool {
  string.contains(claims.acr, "mfa")
  || string.contains(claims.acr, "totp")
  || string.contains(claims.acr, "webauthn")
}

pub fn error_to_string(error: AuthError) -> String {
  case error {
    TokenExpired -> "token_expired"
    TokenNotYetValid -> "token_not_yet_valid"
    TokenIssuedInFuture -> "token_issued_in_future"
    InvalidSignature -> "invalid_signature"
    InvalidIssuer -> "invalid_issuer"
    InvalidAudience -> "invalid_audience"
    InvalidTimeClaims -> "invalid_time_claims"
    MissingClaims(field) -> "missing_claim:" <> field
    MissingJwksSnapshot -> "missing_jwks_snapshot"
    StaleJwksSnapshot -> "stale_jwks_snapshot"
    InvalidJwksSnapshot(reason) -> "invalid_jwks_snapshot:" <> reason
    JwksFetchFailed(reason) -> "jwks_fetch_failed:" <> reason
    MalformedToken(reason) -> "malformed_token:" <> reason
    InternalError(reason) -> "internal_error:" <> reason
  }
}

pub fn error_to_json(error: AuthError) -> String {
  json.object([
    #("error", json.string("authentication_failed")),
    #("reason", json.string(error_to_string(error))),
    #("stamp", json.string("SC-AUTH-001")),
  ])
  |> json.to_string()
}

fn require_fresh_snapshot(
  snapshot: Option(JwksSnapshot),
  current_time: Int,
) -> Result(JwksSnapshot, AuthError) {
  case snapshot {
    None -> Error(MissingJwksSnapshot)
    Some(snapshot) ->
      case
        current_time >= 0
        && snapshot.loaded_at <= current_time
        && current_time - snapshot.loaded_at <= snapshot.max_age_seconds
      {
        True -> Ok(snapshot)
        False -> Error(StaleJwksSnapshot)
      }
  }
}

fn parse_claims(payload_json: String) -> Result(TokenClaims, AuthError) {
  let audience_decoder =
    decode.one_of(decode.map(decode.string, fn(audience) { [audience] }), [
      decode.list(decode.string),
    ])
  let realm_access_decoder = {
    use roles <- decode.optional_field("roles", [], decode.list(decode.string))
    decode.success(roles)
  }
  let claims_decoder = {
    use sub <- decode.field("sub", decode.string)
    use exp <- decode.field("exp", decode.int)
    use iss <- decode.field("iss", decode.string)
    use aud <- decode.field("aud", audience_decoder)
    use preferred_username <- decode.optional_field(
      "preferred_username",
      "",
      decode.string,
    )
    use email <- decode.optional_field("email", "", decode.string)
    use acr <- decode.optional_field("acr", "", decode.string)
    use roles <- decode.optional_field("realm_access", [], realm_access_decoder)
    use nbf <- decode.optional_field("nbf", None, decode.map(decode.int, Some))
    use iat <- decode.optional_field("iat", None, decode.map(decode.int, Some))
    decode.success(TokenClaims(
      sub: sub,
      preferred_username: preferred_username,
      email: email,
      roles: roles,
      exp: exp,
      iss: iss,
      aud: aud,
      acr: acr,
      nbf: nbf,
      iat: iat,
    ))
  }

  case json.parse(payload_json, claims_decoder) {
    Ok(claims) -> Ok(claims)
    Error(_) -> Error(MissingClaims("sub,exp,iss,aud"))
  }
}

fn validate_subject(subject: String) -> Result(Nil, AuthError) {
  case string.trim(subject) != "" && string.length(subject) <= 512 {
    True -> Ok(Nil)
    False -> Error(MissingClaims("sub"))
  }
}

fn validate_issuer(actual: String, required: String) -> Result(Nil, AuthError) {
  case actual == required && required != "" {
    True -> Ok(Nil)
    False -> Error(InvalidIssuer)
  }
}

fn validate_audience(
  audiences: List(String),
  required: String,
) -> Result(Nil, AuthError) {
  case
    required != ""
    && audiences != []
    && list.length(audiences) <= maximum_audiences
    && list.all(audiences, fn(audience) { audience != "" })
    && list.contains(audiences, required)
  {
    True -> Ok(Nil)
    False -> Error(InvalidAudience)
  }
}

fn validate_times(
  claims: TokenClaims,
  current_time: Int,
) -> Result(Nil, AuthError) {
  case current_time >= 0 && claims.exp >= 0 {
    False -> Error(InvalidTimeClaims)
    True ->
      case claims.exp > current_time {
        False -> Error(TokenExpired)
        True -> validate_optional_times(claims, current_time)
      }
  }
}

fn validate_optional_times(
  claims: TokenClaims,
  current_time: Int,
) -> Result(Nil, AuthError) {
  case claims.nbf {
    Some(nbf) if nbf < 0 || nbf >= claims.exp -> Error(InvalidTimeClaims)
    Some(nbf) if nbf > current_time + allowed_clock_skew_seconds ->
      Error(TokenNotYetValid)
    _ ->
      case claims.iat {
        Some(iat) if iat < 0 || iat >= claims.exp -> Error(InvalidTimeClaims)
        Some(iat) if iat > current_time + allowed_clock_skew_seconds ->
          Error(TokenIssuedInFuture)
        _ -> Ok(Nil)
      }
  }
}

fn classify_verifier_error(reason: String) -> AuthError {
  case reason {
    "invalid_signature"
    | "key_not_found"
    | "unsupported_algorithm"
    | "invalid_signature_size"
    | "invalid_public_key"
    | "duplicate_kid" -> InvalidSignature
    "invalid_jwks_snapshot"
    | "jwks_snapshot_too_large"
    | "empty_jwks_snapshot"
    | "too_many_jwks_keys"
    | "invalid_jwk" -> InvalidJwksSnapshot(reason)
    other -> MalformedToken(other)
  }
}

@external(erlang, "oidc_jwt_ffi", "validate_jwks_snapshot")
fn validate_jwks_snapshot(snapshot_json: String) -> Result(Nil, String)

@external(erlang, "oidc_jwt_ffi", "verify_ed25519_jwt")
fn verify_ed25519_jwt(
  token: String,
  snapshot_json: String,
) -> Result(String, String)

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)
