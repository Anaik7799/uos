//// vault_gcp_sm_test — Pass-28 exhaustive coverage of pure GCP Secret Manager
//// request builders. Mirrors vault_kms_test.gleam pattern from Pass-26.

import cepaf_gleam/vault_gcp_sm.{
  type SecretManagerRef, type SmAdcToken, BadRequest, EmptyProject,
  EmptySecretId, InvalidSecretId, MalformedSuccess, NotFound, PermissionDenied,
  RateLimited, SecretManagerRef, ServiceUnavailable, SmAdcToken, Unauthenticated,
  build_access_request, build_add_version_request, build_list_request,
  parse_access_response, parse_access_response_strict,
  parse_add_version_response, parse_list_response_strict, secret_resource_path,
  validate_ref, version_access_path,
}
import gleam/list
import gleam/string
import gleeunit/should

fn good_ref() -> SecretManagerRef {
  SecretManagerRef(
    project: "durable-limiter-457011-u7",
    secret_id: "anthropic_api_key",
  )
}

fn good_token() -> SmAdcToken {
  SmAdcToken(value: "ya29.a0AfH6SMC...")
}

// =====================================================================
// validate_ref
// =====================================================================

pub fn validate_accepts_canonical_ref_test() {
  validate_ref(good_ref()) |> should.equal(Ok(good_ref()))
}

pub fn validate_rejects_empty_project_test() {
  let bad = SecretManagerRef(project: "", secret_id: "k1")
  validate_ref(bad) |> should.equal(Error(EmptyProject))
}

pub fn validate_rejects_empty_secret_id_test() {
  let bad = SecretManagerRef(project: "p", secret_id: "")
  validate_ref(bad) |> should.equal(Error(EmptySecretId))
}

pub fn validate_rejects_uppercase_in_secret_id_test() {
  let bad = SecretManagerRef(project: "p", secret_id: "Anthropic_API_Key")
  case validate_ref(bad) {
    Error(InvalidSecretId(_)) -> Nil
    _ -> panic as "expected InvalidSecretId for uppercase"
  }
}

pub fn validate_rejects_dash_in_secret_id_test() {
  let bad = SecretManagerRef(project: "p", secret_id: "anthropic-api-key")
  case validate_ref(bad) {
    Error(InvalidSecretId(_)) -> Nil
    _ -> panic as "expected InvalidSecretId for dash"
  }
}

pub fn validate_accepts_underscore_and_digits_test() {
  let r = SecretManagerRef(project: "p", secret_id: "key_v2_2026")
  validate_ref(r) |> should.equal(Ok(r))
}

// =====================================================================
// Path builders
// =====================================================================

pub fn secret_resource_path_assembles_correctly_test() {
  secret_resource_path(good_ref())
  |> should.equal(
    "projects/durable-limiter-457011-u7/secrets/anthropic_api_key",
  )
}

pub fn version_access_path_assembles_correctly_test() {
  version_access_path(good_ref(), "latest")
  |> should.equal(
    "projects/durable-limiter-457011-u7/secrets/anthropic_api_key/versions/latest:access",
  )
}

pub fn version_access_path_works_for_specific_version_test() {
  version_access_path(good_ref(), "42")
  |> should.equal(
    "projects/durable-limiter-457011-u7/secrets/anthropic_api_key/versions/42:access",
  )
}

// =====================================================================
// build_list_request
// =====================================================================

pub fn list_request_uses_get_method_test() {
  let assert Ok(req) =
    build_list_request("durable-limiter-457011-u7", 100, good_token())
  req.method |> should.equal("GET")
}

pub fn list_request_url_includes_page_size_test() {
  let assert Ok(req) = build_list_request("p", 50, good_token())
  string.contains(req.url, "pageSize=50") |> should.equal(True)
}

pub fn list_request_targets_secretmanager_v1_test() {
  let assert Ok(req) = build_list_request("p", 100, good_token())
  string.starts_with(req.url, "https://secretmanager.googleapis.com/v1/")
  |> should.equal(True)
}

pub fn list_request_rejects_empty_project_test() {
  build_list_request("", 100, good_token()) |> should.equal(Error(EmptyProject))
}

// =====================================================================
// build_access_request
// =====================================================================

pub fn access_request_uses_get_method_test() {
  let assert Ok(req) = build_access_request(good_ref(), "latest", good_token())
  req.method |> should.equal("GET")
}

pub fn access_request_url_targets_versions_access_test() {
  let assert Ok(req) = build_access_request(good_ref(), "latest", good_token())
  string.ends_with(req.url, "/versions/latest:access") |> should.equal(True)
}

pub fn access_request_includes_bearer_token_test() {
  let assert Ok(req) =
    build_access_request(good_ref(), "latest", SmAdcToken(value: "tok123"))
  let auth =
    list.find(req.headers, fn(p) {
      let #(k, _) = p
      k == "Authorization"
    })
  case auth {
    Ok(#(_, v)) -> v |> should.equal("Bearer tok123")
    _ -> panic as "no Authorization header"
  }
}

pub fn access_request_propagates_validation_errors_test() {
  let bad = SecretManagerRef(project: "p", secret_id: "BAD-NAME")
  case build_access_request(bad, "latest", good_token()) {
    Error(InvalidSecretId(_)) -> Nil
    _ -> panic as "expected InvalidSecretId"
  }
}

// =====================================================================
// build_add_version_request
// =====================================================================

pub fn add_version_uses_post_method_test() {
  let assert Ok(req) =
    build_add_version_request(good_ref(), "ZGF0YQ==", good_token())
  req.method |> should.equal("POST")
}

pub fn add_version_url_targets_addversion_test() {
  let assert Ok(req) = build_add_version_request(good_ref(), "x", good_token())
  string.ends_with(req.url, ":addVersion") |> should.equal(True)
}

pub fn add_version_body_wraps_payload_data_test() {
  let assert Ok(req) =
    build_add_version_request(good_ref(), "ZGF0YQ==", good_token())
  string.contains(req.body, "\"data\":\"ZGF0YQ==\"") |> should.equal(True)
  string.contains(req.body, "\"payload\":") |> should.equal(True)
}

pub fn add_version_content_type_is_json_test() {
  let assert Ok(req) = build_add_version_request(good_ref(), "x", good_token())
  let ct =
    list.find(req.headers, fn(p) {
      let #(k, _) = p
      k == "Content-Type"
    })
  case ct {
    Ok(#(_, "application/json")) -> Nil
    _ -> panic as "Content-Type not application/json"
  }
}

// =====================================================================
// Response parsers
// =====================================================================

pub fn parse_access_extracts_data_field_test() {
  let body =
    "{\"name\":\"projects/p/secrets/k/versions/1\",\"payload\":{\"data\":\"c2VjcmV0\"}}"
  parse_access_response(body) |> should.equal(Ok("c2VjcmV0"))
}

pub fn parse_access_returns_error_on_missing_data_test() {
  let body = "{\"error\":{\"code\":403}}"
  case parse_access_response(body) {
    Error(_) -> Nil
    _ -> panic as "expected error on missing data"
  }
}

pub fn parse_add_version_extracts_name_test() {
  let body =
    "{\"name\":\"projects/p/secrets/k/versions/2\",\"state\":\"ENABLED\"}"
  parse_add_version_response(body)
  |> should.equal(Ok("projects/p/secrets/k/versions/2"))
}

pub fn parse_add_version_returns_error_on_missing_name_test() {
  let body = "{\"error\":{\"code\":403}}"
  case parse_add_version_response(body) {
    Error(_) -> Nil
    _ -> panic as "expected error on missing name"
  }
}

// =====================================================================
// Pass-35 Track D — strict response parsers (status-class split)
// =====================================================================

pub fn access_strict_returns_ok_on_200_with_data_field_test() {
  let body = "{\"payload\":{\"data\":\"cGF5bG9hZA==\"}}"
  parse_access_response_strict(200, body)
  |> should.equal(Ok("cGF5bG9hZA=="))
}

pub fn access_strict_returns_unauthenticated_on_401_test() {
  let body = "{\"error\":{\"code\":401}}"
  case parse_access_response_strict(401, body) {
    Error(Unauthenticated(b)) -> b |> should.equal(body)
    _ -> panic as "expected Unauthenticated for 401"
  }
}

pub fn access_strict_returns_permission_denied_on_403_test() {
  let body = "{\"error\":{\"code\":403,\"status\":\"PERMISSION_DENIED\"}}"
  case parse_access_response_strict(403, body) {
    Error(PermissionDenied(b)) -> b |> should.equal(body)
    _ -> panic as "expected PermissionDenied for 403"
  }
}

pub fn access_strict_returns_not_found_on_404_test() {
  // 404 split out from generic 4xx — common operator-onboarding state.
  let body = "{\"error\":{\"code\":404,\"status\":\"NOT_FOUND\"}}"
  case parse_access_response_strict(404, body) {
    Error(NotFound(b)) -> b |> should.equal(body)
    _ -> panic as "expected NotFound for 404"
  }
}

pub fn access_strict_returns_rate_limited_on_429_test() {
  case parse_access_response_strict(429, "rate limited") {
    Error(RateLimited(b)) -> b |> should.equal("rate limited")
    _ -> panic as "expected RateLimited for 429"
  }
}

pub fn access_strict_returns_service_unavailable_on_5xx_test() {
  case parse_access_response_strict(503, "{\"err\":\"unavailable\"}") {
    Error(ServiceUnavailable(s, _)) -> s |> should.equal(503)
    _ -> panic as "expected ServiceUnavailable for 503"
  }
  case parse_access_response_strict(500, "internal") {
    Error(ServiceUnavailable(500, _)) -> Nil
    _ -> panic as "500 must also be ServiceUnavailable"
  }
}

pub fn access_strict_returns_bad_request_on_other_4xx_test() {
  case parse_access_response_strict(400, "bad") {
    Error(BadRequest(s, _)) -> s |> should.equal(400)
    _ -> panic as "expected BadRequest for 400"
  }
  // 418 (teapot) — sanity check the catch-all.
  case parse_access_response_strict(418, "i'm a teapot") {
    Error(BadRequest(418, _)) -> Nil
    _ -> panic as "expected BadRequest for 418"
  }
}

pub fn access_strict_returns_malformed_on_200_without_data_field_test() {
  case parse_access_response_strict(200, "{\"unrelated\":\"x\"}") {
    Error(MalformedSuccess(b)) -> b |> should.equal("{\"unrelated\":\"x\"}")
    _ -> panic as "expected MalformedSuccess on 200 with no data"
  }
}

pub fn list_strict_returns_body_on_200_test() {
  // The list parser deliberately returns raw body on 200 — paging belongs
  // in the caller. This test pins that contract.
  let body = "{\"secrets\":[{\"name\":\"projects/p/secrets/k\"}]}"
  parse_list_response_strict(200, body)
  |> should.equal(Ok(body))
}

pub fn list_strict_returns_structured_error_on_404_test() {
  case parse_list_response_strict(404, "not found") {
    Error(NotFound(_)) -> Nil
    _ -> panic as "expected NotFound from list_strict on 404"
  }
}
