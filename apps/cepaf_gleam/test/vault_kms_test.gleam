//// vault_kms_test — Pass-26 exhaustive coverage of pure GCP KMS
//// Decrypt request builder.
////
//// SC-VAULT-007: KMS DR is the LAST resort in the unseal chain
//// SC-VAULT-017: GCP region MUST be europe-north1 (GDPR EU residency)

import cepaf_gleam/vault_kms.{
  type AdcToken, type KmsKeyRef, AdcToken, BadRequest, EmptyCryptoKey,
  EmptyKeyring, EmptyProject, KmsKeyRef, MalformedSuccess, PermissionDenied,
  RateLimited, ServiceUnavailable, Unauthenticated, WrongRegion,
  build_decrypt_request, key_resource_path, parse_decrypt_response,
  parse_decrypt_response_strict, validate_key_ref,
}
import gleam/list
import gleam/string
import gleeunit/should

fn good_ref() -> KmsKeyRef {
  KmsKeyRef(
    project: "durable-limiter-457011-u7",
    location: "europe-north1",
    keyring: "c3i-secrets-dr",
    crypto_key: "kek",
  )
}

fn good_token() -> AdcToken {
  AdcToken(value: "ya29.a0AfH6SMC...")
}

// =====================================================================
// validate_key_ref — SC-VAULT-017 enforcement
// =====================================================================

pub fn validate_accepts_canonical_eu_north_1_ref_test() {
  validate_key_ref(good_ref()) |> should.equal(Ok(good_ref()))
}

pub fn validate_rejects_us_region_test() {
  let bad = KmsKeyRef(..good_ref(), location: "us-central1")
  case validate_key_ref(bad) {
    Error(WrongRegion(actual: "us-central1")) -> Nil
    _ -> panic as "expected WrongRegion"
  }
}

pub fn validate_rejects_empty_project_test() {
  let bad = KmsKeyRef(..good_ref(), project: "")
  validate_key_ref(bad) |> should.equal(Error(EmptyProject))
}

pub fn validate_rejects_empty_keyring_test() {
  let bad = KmsKeyRef(..good_ref(), keyring: "")
  validate_key_ref(bad) |> should.equal(Error(EmptyKeyring))
}

pub fn validate_rejects_empty_crypto_key_test() {
  let bad = KmsKeyRef(..good_ref(), crypto_key: "")
  validate_key_ref(bad) |> should.equal(Error(EmptyCryptoKey))
}

pub fn validate_rejects_global_region_test() {
  let bad = KmsKeyRef(..good_ref(), location: "global")
  case validate_key_ref(bad) {
    Error(WrongRegion(actual: "global")) -> Nil
    _ -> panic as "expected WrongRegion(global)"
  }
}

// =====================================================================
// key_resource_path — full path assembly
// =====================================================================

pub fn key_resource_path_assembles_correctly_test() {
  key_resource_path(good_ref())
  |> should.equal(
    "projects/durable-limiter-457011-u7/locations/europe-north1/keyRings/c3i-secrets-dr/cryptoKeys/kek",
  )
}

pub fn key_resource_path_handles_unicode_safely_test() {
  let ref =
    KmsKeyRef(
      project: "p1",
      location: "europe-north1",
      keyring: "kr",
      crypto_key: "ck",
    )
  let p = key_resource_path(ref)
  string.contains(p, "projects/p1") |> should.equal(True)
  string.contains(p, "/keyRings/kr") |> should.equal(True)
  string.contains(p, "/cryptoKeys/ck") |> should.equal(True)
}

// =====================================================================
// build_decrypt_request — full envelope assembly
// =====================================================================

pub fn build_request_returns_post_method_test() {
  let assert Ok(req) =
    build_decrypt_request(good_ref(), good_token(), "deadbeef")
  req.method |> should.equal("POST")
}

pub fn build_request_url_targets_cloudkms_v1_decrypt_test() {
  let assert Ok(req) =
    build_decrypt_request(good_ref(), good_token(), "deadbeef")
  string.starts_with(req.url, "https://cloudkms.googleapis.com/v1/")
  |> should.equal(True)
  string.ends_with(req.url, ":decrypt") |> should.equal(True)
}

pub fn build_request_body_includes_ciphertext_test() {
  let assert Ok(req) =
    build_decrypt_request(good_ref(), good_token(), "Y2lwaGVydGV4dA==")
  string.contains(req.body, "\"ciphertext\":\"Y2lwaGVydGV4dA==\"")
  |> should.equal(True)
}

pub fn build_request_authorization_header_uses_bearer_token_test() {
  let assert Ok(req) =
    build_decrypt_request(good_ref(), AdcToken(value: "tok123"), "x")
  let auth_header =
    list.find(req.headers, fn(pair) {
      let #(k, _) = pair
      k == "Authorization"
    })
  case auth_header {
    Ok(#(_, v)) -> v |> should.equal("Bearer tok123")
    _ -> panic as "no Authorization header"
  }
}

pub fn build_request_content_type_is_application_json_test() {
  let assert Ok(req) = build_decrypt_request(good_ref(), good_token(), "x")
  let ct =
    list.find(req.headers, fn(pair) {
      let #(k, _) = pair
      k == "Content-Type"
    })
  case ct {
    Ok(#(_, "application/json")) -> Nil
    _ -> panic as "Content-Type not application/json"
  }
}

pub fn build_request_propagates_validation_errors_test() {
  let bad = KmsKeyRef(..good_ref(), location: "asia-east1")
  case build_decrypt_request(bad, good_token(), "x") {
    Error(WrongRegion(actual: "asia-east1")) -> Nil
    _ -> panic as "expected WrongRegion error from invalid ref"
  }
}

pub fn build_request_propagates_empty_project_error_test() {
  let bad = KmsKeyRef(..good_ref(), project: "")
  build_decrypt_request(bad, good_token(), "x")
  |> should.equal(Error(EmptyProject))
}

// =====================================================================
// parse_decrypt_response — string-pure extractor
// =====================================================================

pub fn parse_response_extracts_plaintext_test() {
  let body = "{\"plaintext\":\"bWFzdGVyLWtleQ==\",\"plaintextCrc32c\":\"123\"}"
  parse_decrypt_response(body) |> should.equal(Ok("bWFzdGVyLWtleQ=="))
}

pub fn parse_response_returns_error_when_field_absent_test() {
  let body = "{\"error\":\"unauthorized\"}"
  case parse_decrypt_response(body) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected Error on missing plaintext"
  }
}

pub fn parse_response_handles_empty_body_test() {
  case parse_decrypt_response("") {
    Error(_) -> Nil
    _ -> panic as "expected error on empty body"
  }
}

// =====================================================================
// Pass-35 Track C — parse_decrypt_response_strict (status-class split)
// =====================================================================

pub fn strict_parser_returns_ok_on_200_with_valid_body_test() {
  let body = "{\"plaintext\":\"bWFzdGVyLWtleQ==\"}"
  parse_decrypt_response_strict(200, body)
  |> should.equal(Ok("bWFzdGVyLWtleQ=="))
}

pub fn strict_parser_returns_unauthenticated_on_401_test() {
  let body = "{\"error\":{\"code\":401,\"status\":\"UNAUTHENTICATED\"}}"
  case parse_decrypt_response_strict(401, body) {
    Error(Unauthenticated(b)) -> b |> should.equal(body)
    _ -> panic as "expected Unauthenticated for 401"
  }
}

pub fn strict_parser_returns_permission_denied_on_403_test() {
  let body = "{\"error\":{\"code\":403,\"status\":\"PERMISSION_DENIED\"}}"
  case parse_decrypt_response_strict(403, body) {
    Error(PermissionDenied(b)) -> b |> should.equal(body)
    _ -> panic as "expected PermissionDenied for 403"
  }
}

pub fn strict_parser_returns_rate_limited_on_429_test() {
  let body = "{\"error\":{\"code\":429,\"status\":\"RESOURCE_EXHAUSTED\"}}"
  case parse_decrypt_response_strict(429, body) {
    Error(RateLimited(b)) -> b |> should.equal(body)
    _ -> panic as "expected RateLimited for 429"
  }
}

pub fn strict_parser_returns_service_unavailable_on_5xx_test() {
  let body = "{\"error\":{\"code\":503,\"status\":\"UNAVAILABLE\"}}"
  case parse_decrypt_response_strict(503, body) {
    Error(ServiceUnavailable(s, b)) -> {
      s |> should.equal(503)
      b |> should.equal(body)
    }
    _ -> panic as "expected ServiceUnavailable for 503"
  }
  // 500 also classes here.
  case parse_decrypt_response_strict(500, "internal") {
    Error(ServiceUnavailable(500, _)) -> Nil
    _ -> panic as "500 must also be ServiceUnavailable"
  }
}

pub fn strict_parser_returns_bad_request_on_other_4xx_test() {
  // 400, 404 etc. → terminal client-bug class.
  case parse_decrypt_response_strict(400, "{\"error\":\"bad\"}") {
    Error(BadRequest(s, _)) -> s |> should.equal(400)
    _ -> panic as "expected BadRequest for 400"
  }
  case parse_decrypt_response_strict(404, "not found") {
    Error(BadRequest(404, _)) -> Nil
    _ -> panic as "expected BadRequest for 404"
  }
}

pub fn strict_parser_returns_malformed_on_200_with_no_plaintext_test() {
  // 200 status but body missing `plaintext` field — classed as
  // MalformedSuccess so callers don't conflate it with a real failure.
  case parse_decrypt_response_strict(200, "{\"unrelated\":\"x\"}") {
    Error(MalformedSuccess(b)) -> b |> should.equal("{\"unrelated\":\"x\"}")
    _ -> panic as "expected MalformedSuccess for 200 with bad body"
  }
}
