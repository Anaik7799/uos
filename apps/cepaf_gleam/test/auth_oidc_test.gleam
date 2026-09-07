import cepaf_gleam/auth/oidc
import cepaf_gleam/ui/wisp/auth as wisp_auth
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleeunit/should

const issuer = "https://issuer.example/realms/c3i"

const audience = "c3i-wisp-api"

const now = 2_000_000_000

// RFC 8037 Appendix A public Ed25519 test key. No private key is stored.
const jwks = "{\"keys\":[{\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"kid\":\"rfc8037-test\",\"alg\":\"EdDSA\",\"use\":\"sig\",\"key_ops\":[\"verify\"],\"x\":\"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo\"}]}"

const wrong_key_jwks = "{\"keys\":[{\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"kid\":\"rfc8037-test\",\"alg\":\"EdDSA\",\"x\":\"PUAXw-hDiVqStwqnTRt-vJyYLM8uxJaMwM1V8Sr0Zgw\"}]}"

pub fn valid_signed_token_test() {
  let assert Ok(claims) =
    oidc.validate_token(valid_token(), fresh_config(), now)
  claims.sub |> should.equal("user-123")
  claims.preferred_username |> should.equal("alice")
  claims.aud |> should.equal(["other", audience])
  claims.roles |> should.equal(["c3i-admin", "c3i-viewer"])
  claims.nbf |> should.equal(Some(1_999_999_900))
  claims.iat |> should.equal(Some(1_999_999_900))
  oidc.has_mfa(claims) |> should.be_true()
}

pub fn string_audience_is_accepted_test() {
  let assert Ok(claims) =
    oidc.validate_token(string_audience_token(), fresh_config(), now)
  claims.aud |> should.equal([audience])
}

pub fn tampered_signature_is_rejected_test() {
  let tampered = string.drop_end(valid_token(), 1) <> "A"
  oidc.validate_token(tampered, fresh_config(), now)
  |> should.equal(Error(oidc.InvalidSignature))
}

pub fn wrong_key_is_rejected_test() {
  oidc.validate_token(valid_token(), config_with(wrong_key_jwks), now)
  |> should.equal(Error(oidc.InvalidSignature))
}

pub fn none_algorithm_is_rejected_test() {
  oidc.validate_token(none_token(), fresh_config(), now)
  |> should.equal(Error(oidc.InvalidSignature))
}

pub fn duplicate_header_is_rejected_test() {
  oidc.validate_token(duplicate_header_token(), fresh_config(), now)
  |> should.equal(Error(oidc.MalformedToken("duplicate_json_member")))
}

pub fn duplicate_claim_is_rejected_test() {
  oidc.validate_token(duplicate_payload_token(), fresh_config(), now)
  |> should.equal(Error(oidc.MalformedToken("duplicate_json_member")))
}

pub fn token_directed_jku_is_rejected_test() {
  oidc.validate_token(jku_token(), fresh_config(), now)
  |> should.equal(Error(oidc.MalformedToken("disallowed_header")))
}

pub fn wrong_issuer_is_rejected_test() {
  oidc.validate_token(wrong_issuer_token(), fresh_config(), now)
  |> should.equal(Error(oidc.InvalidIssuer))
}

pub fn wrong_audience_is_rejected_test() {
  oidc.validate_token(wrong_audience_token(), fresh_config(), now)
  |> should.equal(Error(oidc.InvalidAudience))
}

pub fn expired_token_is_rejected_test() {
  oidc.validate_token(expired_token(), fresh_config(), now)
  |> should.equal(Error(oidc.TokenExpired))
}

pub fn future_nbf_is_rejected_test() {
  oidc.validate_token(future_nbf_token(), fresh_config(), now)
  |> should.equal(Error(oidc.TokenNotYetValid))
}

pub fn future_iat_is_rejected_test() {
  oidc.validate_token(future_iat_token(), fresh_config(), now)
  |> should.equal(Error(oidc.TokenIssuedInFuture))
}

pub fn empty_subject_is_rejected_test() {
  oidc.validate_token(empty_subject_token(), fresh_config(), now)
  |> should.equal(Error(oidc.MissingClaims("sub")))
}

pub fn padded_base64url_segment_is_rejected_test() {
  let assert [header, payload, signature] = string.split(valid_token(), ".")
  let padded = header <> "=." <> payload <> "." <> signature
  oidc.validate_token(padded, fresh_config(), now)
  |> should.equal(Error(oidc.MalformedToken("noncanonical_base64url")))
}

pub fn absent_snapshot_fails_closed_test() {
  oidc.validate_token(valid_token(), base_config(), now)
  |> should.equal(Error(oidc.MissingJwksSnapshot))
}

pub fn stale_snapshot_fails_closed_test() {
  let stale =
    oidc.load_jwks_snapshot(base_config(), jwks, now - 301, 300)
    |> result.unwrap(base_config())
  oidc.validate_token(valid_token(), stale, now)
  |> should.equal(Error(oidc.StaleJwksSnapshot))
}

pub fn oversized_token_is_rejected_test() {
  oidc.validate_token(string.repeat("a", 8193), fresh_config(), now)
  |> should.equal(Error(oidc.MalformedToken("bad_token_length")))
}

pub fn invalid_jwk_profile_is_rejected_at_load_test() {
  let rsa =
    "{\"keys\":[{\"kty\":\"RSA\",\"crv\":\"Ed25519\",\"kid\":\"test\",\"alg\":\"EdDSA\",\"x\":\"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo\"}]}"
  oidc.load_jwks_snapshot(base_config(), rsa, now, 300)
  |> should.equal(Error(oidc.InvalidJwksSnapshot("invalid_jwk")))
}

pub fn duplicate_jwks_member_is_rejected_at_load_test() {
  let duplicate =
    "{\"keys\":[],\"keys\":[{\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"kid\":\"test\",\"alg\":\"EdDSA\",\"x\":\"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo\"}]}"
  oidc.load_jwks_snapshot(base_config(), duplicate, now, 300)
  |> should.equal(Error(oidc.InvalidJwksSnapshot("duplicate_json_member")))
}

pub fn more_than_sixteen_keys_is_rejected_at_load_test() {
  let key =
    "{\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"kid\":\"same\",\"alg\":\"EdDSA\",\"x\":\"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo\"}"
  let snapshot = "{\"keys\":[" <> string.join(list.repeat(key, 17), ",") <> "]}"
  oidc.load_jwks_snapshot(base_config(), snapshot, now, 300)
  |> should.equal(Error(oidc.InvalidJwksSnapshot("too_many_jwks_keys")))
}

pub fn oidc_mode_never_downgrades_to_static_admin_test() {
  wisp_auth.validate_authorization(
    "Bearer static-secret",
    wisp_auth.oidc_mode(fresh_config()),
    now,
  )
  |> should.equal(wisp_auth.InvalidToken(
    "malformed_token:malformed_compact_jwt",
  ))
}

pub fn static_mode_remains_available_when_explicitly_selected_test() {
  wisp_auth.validate_authorization(
    "Bearer static-secret",
    wisp_auth.static_mode("static-secret"),
    now,
  )
  |> should.equal(wisp_auth.Authenticated("api-client"))
}

pub fn token_claim_helpers_test() {
  let claims =
    oidc.TokenClaims(
      sub: "user-test",
      preferred_username: "testuser",
      email: "test@test.com",
      roles: ["c3i-admin"],
      exp: 9_999_999_999,
      iss: issuer,
      aud: [audience],
      acr: "urn:ferriskey:mfa:webauthn",
      nbf: None,
      iat: None,
    )
  oidc.extract_roles(claims) |> should.equal(["c3i-admin"])
  oidc.has_role(claims, "c3i-admin") |> should.be_true()
  oidc.has_mfa(claims) |> should.be_true()
}

fn base_config() -> oidc.OidcConfig {
  oidc.OidcConfig(
    issuer_url: issuer,
    jwks_url: issuer <> "/protocol/openid-connect/certs",
    client_id: audience,
    required_audience: audience,
    jwks_snapshot: None,
  )
}

fn fresh_config() -> oidc.OidcConfig {
  config_with(jwks)
}

fn config_with(snapshot: String) -> oidc.OidcConfig {
  oidc.load_jwks_snapshot(base_config(), snapshot, now - 100, 300)
  |> result.unwrap(base_config())
}

fn valid_token() -> String {
  "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9."
  <> "eyJzdWIiOiJ1c2VyLTEyMyIsInByZWZlcnJlZF91c2VybmFtZSI6ImFsaWNlIiwiZW1haWwiOiJhbGljZUBleGFtcGxlLnRlc3QiLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsiYzNpLWFkbWluIiwiYzNpLXZpZXdlciJdfSwiZXhwIjoyMDAwMDAwMzAwLCJuYmYiOjE5OTk5OTk5MDAsImlhdCI6MTk5OTk5OTkwMCwiaXNzIjoiaHR0cHM6Ly9pc3N1ZXIuZXhhbXBsZS9yZWFsbXMvYzNpIiwiYXVkIjpbIm90aGVyIiwiYzNpLXdpc3AtYXBpIl0sImFjciI6InVybjpmZXJyaXNrZXk6bWZhOnRvdHAifQ."
  <> "dVxBTR6flg4DMlYUpbasP7tZalJXKJl40Amw5WoT1iQyoaMCv4GNoC7Mp4JJWeVl9RGH2Kps98VlzuuBYHF-Dw"
}

fn string_audience_token() -> String {
  "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6MjAwMDAwMDMwMCwiaXNzIjoiaHR0cHM6Ly9pc3N1ZXIuZXhhbXBsZS9yZWFsbXMvYzNpIiwiYXVkIjoiYzNpLXdpc3AtYXBpIn0.mfaSQdB3lV47YleIzp9Kr3dFpBgZ87aiQBr3F_BMWdOUjAGJwoiRifw8ZtZcazFPL1gxFfgSQSz04xDhCVtuAg"
}

fn wrong_audience_token() -> String {
  "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6MjAwMDAwMDMwMCwiaXNzIjoiaHR0cHM6Ly9pc3N1ZXIuZXhhbXBsZS9yZWFsbXMvYzNpIiwiYXVkIjoic29tZXdoZXJlLWVsc2UifQ.m1N4U7EzuP-bxSeItjc_kXY62hLNvItS8gzDDtTJZCdppaJGBA9_Lw9zfQfWUQ62g7opQxTxAhwtQo9_CFkxCA"
}

fn wrong_issuer_token() -> String {
  "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6MjAwMDAwMDMwMCwiaXNzIjoiaHR0cHM6Ly9ldmlsLmV4YW1wbGUiLCJhdWQiOiJjM2ktd2lzcC1hcGkifQ.ssyELjLJ2qXJAiGCEhPLoxie1xoSiOK2iT0gUY2YGLA5TOiztRNbKbBEoQNGF8oqWB-dqs0sUx8YwEaZdwxnCw"
}

fn expired_token() -> String {
  "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6MTk5OTk5OTk5OSwiaXNzIjoiaHR0cHM6Ly9pc3N1ZXIuZXhhbXBsZS9yZWFsbXMvYzNpIiwiYXVkIjoiYzNpLXdpc3AtYXBpIn0.lZ_M4XMqou_mWwjgLA4RcTKwfhN7Eguf6pVGrD8kgK8Ob21wbwgO0d7_SJeabf7ieL37gkVCRy7q1Kq6bnIpCg"
}

fn future_nbf_token() -> String {
  "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6MjAwMDAwMDMwMCwibmJmIjoyMDAwMDAwMjAwLCJpc3MiOiJodHRwczovL2lzc3Vlci5leGFtcGxlL3JlYWxtcy9jM2kiLCJhdWQiOiJjM2ktd2lzcC1hcGkifQ.DTIlNiHeFZqBfFJA-EWObxoLeuQ5_RoSar5tmbxC_l59m4vqt-kzFyuMsuYm6_TUSaVBOj-tY-MLX90YMfZaAA"
}

fn future_iat_token() -> String {
  "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6MjAwMDAwMDMwMCwiaWF0IjoyMDAwMDAwMjAwLCJpc3MiOiJodHRwczovL2lzc3Vlci5leGFtcGxlL3JlYWxtcy9jM2kiLCJhdWQiOiJjM2ktd2lzcC1hcGkifQ.1sTiYHZrEIaYmZGsdDKUeq-78OGBh2WmJZAn4sv3Y3Mk62GXHIbG1Pyy27oPDgKD8OojdNWJdBMwrijqdUoCCQ"
}

fn empty_subject_token() -> String {
  "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIiLCJleHAiOjIwMDAwMDAzMDAsImlzcyI6Imh0dHBzOi8vaXNzdWVyLmV4YW1wbGUvcmVhbG1zL2MzaSIsImF1ZCI6ImMzaS13aXNwLWFwaSJ9.NCutft46ucM-ufDkWwVAdMyTVuj745J-ENcOJI3Vw9OflpYb4g6GhR16DAPm_TF0OW4tWBN38ZtXT7tVi-F7BA"
}

fn duplicate_payload_token() -> String {
  "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyIsInN1YiI6ImV2aWwiLCJleHAiOjIwMDAwMDAzMDAsImlzcyI6Imh0dHBzOi8vaXNzdWVyLmV4YW1wbGUvcmVhbG1zL2MzaSIsImF1ZCI6ImMzaS13aXNwLWFwaSJ9.PUseKJng77syosb4_9EglyPDWjRbilLjrRKY6qbiEEtrP9Xqe2ZOnTd1tZQpfcAOL7KT65S-0B82up4TcpPWAw"
}

fn duplicate_header_token() -> String {
  "eyJhbGciOiJFZERTQSIsImFsZyI6Im5vbmUiLCJraWQiOiJyZmM4MDM3LXRlc3QiLCJ0eXAiOiJKV1QifQ.eyJzdWIiOiJ1c2VyLTEyMyIsInByZWZlcnJlZF91c2VybmFtZSI6ImFsaWNlIiwiZW1haWwiOiJhbGljZUBleGFtcGxlLnRlc3QiLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsiYzNpLWFkbWluIiwiYzNpLXZpZXdlciJdfSwiZXhwIjoyMDAwMDAwMzAwLCJuYmYiOjE5OTk5OTk5MDAsImlhdCI6MTk5OTk5OTkwMCwiaXNzIjoiaHR0cHM6Ly9pc3N1ZXIuZXhhbXBsZS9yZWFsbXMvYzNpIiwiYXVkIjpbIm90aGVyIiwiYzNpLXdpc3AtYXBpIl0sImFjciI6InVybjpmZXJyaXNrZXk6bWZhOnRvdHAifQ.43GbIK8d_JuBA6ooEUbVxBMsxXYmApL_8Ix2fOcSpDf3qAURXmO2Bf9or92wY5zWyUiWCnVZmx2Y2doXRKTQDA"
}

fn none_token() -> String {
  "eyJhbGciOiJub25lIiwia2lkIjoicmZjODAzNy10ZXN0IiwidHlwIjoiSldUIn0.eyJzdWIiOiJ1c2VyLTEyMyIsInByZWZlcnJlZF91c2VybmFtZSI6ImFsaWNlIiwiZW1haWwiOiJhbGljZUBleGFtcGxlLnRlc3QiLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsiYzNpLWFkbWluIiwiYzNpLXZpZXdlciJdfSwiZXhwIjoyMDAwMDAwMzAwLCJuYmYiOjE5OTk5OTk5MDAsImlhdCI6MTk5OTk5OTkwMCwiaXNzIjoiaHR0cHM6Ly9pc3N1ZXIuZXhhbXBsZS9yZWFsbXMvYzNpIiwiYXVkIjpbIm90aGVyIiwiYzNpLXdpc3AtYXBpIl0sImFjciI6InVybjpmZXJyaXNrZXk6bWZhOnRvdHAifQ.auP2A4yafpzyDgatKkV5wfBDXnogCU2W3TqBf7s9_vAluWnlZHJaw2zXcBs0dxTRPq3Ir3RONeSJExDVVEqfAA"
}

fn jku_token() -> String {
  "eyJhbGciOiJFZERTQSIsImtpZCI6InJmYzgwMzctdGVzdCIsInR5cCI6IkpXVCIsImprdSI6Imh0dHBzOi8vZXZpbC5leGFtcGxlL2p3a3MifQ.eyJzdWIiOiJ1c2VyLTEyMyIsInByZWZlcnJlZF91c2VybmFtZSI6ImFsaWNlIiwiZW1haWwiOiJhbGljZUBleGFtcGxlLnRlc3QiLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsiYzNpLWFkbWluIiwiYzNpLXZpZXdlciJdfSwiZXhwIjoyMDAwMDAwMzAwLCJuYmYiOjE5OTk5OTk5MDAsImlhdCI6MTk5OTk5OTkwMCwiaXNzIjoiaHR0cHM6Ly9pc3N1ZXIuZXhhbXBsZS9yZWFsbXMvYzNpIiwiYXVkIjpbIm90aGVyIiwiYzNpLXdpc3AtYXBpIl0sImFjciI6InVybjpmZXJyaXNrZXk6bWZhOnRvdHAifQ.ZZGr2gVMZtk4V1fvnDwLnf-B8ilsKj0tvWIYx6daKKPuudB8CYndYJep89FWhAH4rNpydtmQRXXk1UqzBPM2Aw"
}
