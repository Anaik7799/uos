//// Vault GCP Secret Manager — pure request builders for the sync actor.
////
//// Slice D partial (Pass-28): assembles URLs, headers, and JSON bodies for
//// the GCP Secret Manager REST API:
////   - GET    /v1/projects/{P}/secrets                  (list secrets)
////   - GET    /v1/projects/{P}/secrets/{S}/versions/latest:access  (read)
////   - POST   /v1/projects/{P}/secrets/{S}:addVersion   (write)
////
//// No HTTP performed; the supervisor's sync actor (vault_sync_actor.gleam)
//// will plug in the reqwest call. Mirrors the vault_kms.gleam pattern from
//// Pass-26 — same `HttpRequest` envelope, same ADC token wrapper, same
//// SC-VAULT-017 europe-north1 + SC-VAULT-018 IAM minimum-roles invariants.
////
//// Pure functions — exhaustively unit-testable without ADC tokens or network.

import gleam/string

// =====================================================================
// Types
// =====================================================================

/// Reference to a Secret Manager secret. SC-VAULT-019 mandates the keyring
/// for CMEK encryption is *separate* from the KEK DR keyring; this module
/// doesn't enforce keyring directly (that's a server-side IAM check), but
/// the project + region MUST be the EU project per SC-VAULT-017.
pub type SecretManagerRef {
  SecretManagerRef(project: String, secret_id: String)
}

/// Bearer token from ADC (matches vault_kms.AdcToken; kept distinct so
/// each module is self-contained).
pub type SmAdcToken {
  SmAdcToken(value: String)
}

/// HTTP envelope (matches vault_kms.HttpRequest shape).
pub type SmRequest {
  SmRequest(
    method: String,
    url: String,
    headers: List(#(String, String)),
    body: String,
  )
}

/// Validation errors.
pub type SmRefError {
  EmptyProject
  EmptySecretId
  InvalidSecretId(reason: String)
}

// =====================================================================
// Validation
// =====================================================================

/// SC-VAULT-013 requires per-secret policy rows; secret_id MUST be
/// snake_case ASCII lowercase + digits, max 255 chars (GCP limit).
pub fn validate_ref(
  ref: SecretManagerRef,
) -> Result(SecretManagerRef, SmRefError) {
  case ref.project, ref.secret_id {
    "", _ -> Error(EmptyProject)
    _, "" -> Error(EmptySecretId)
    _, sid -> {
      case is_valid_secret_id(sid) {
        True -> Ok(ref)
        False ->
          Error(InvalidSecretId(
            reason: "secret_id must be snake_case ascii (got: " <> sid <> ")",
          ))
      }
    }
  }
}

fn is_valid_secret_id(s: String) -> Bool {
  // GCP allows [a-zA-Z0-9_-], 1-255 chars. We tighten to lowercase+digits+_
  // for our naming convention. Empty already rejected above.
  let len = string.length(s)
  case len > 0 && len <= 255 {
    False -> False
    True -> all_lowercase_ascii_or_underscore(string.to_graphemes(s))
  }
}

fn all_lowercase_ascii_or_underscore(chars: List(String)) -> Bool {
  case chars {
    [] -> True
    [c, ..rest] ->
      case is_valid_char(c) {
        True -> all_lowercase_ascii_or_underscore(rest)
        False -> False
      }
  }
}

fn is_valid_char(c: String) -> Bool {
  case c {
    "_" -> True
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" -> True
    "k" | "l" | "m" | "n" | "o" | "p" | "q" | "r" | "s" | "t" -> True
    "u" | "v" | "w" | "x" | "y" | "z" -> True
    _ -> False
  }
}

// =====================================================================
// Path builders
// =====================================================================

pub fn secret_resource_path(ref: SecretManagerRef) -> String {
  string.concat(["projects/", ref.project, "/secrets/", ref.secret_id])
}

pub fn version_access_path(ref: SecretManagerRef, version: String) -> String {
  string.concat([
    secret_resource_path(ref),
    "/versions/",
    version,
    ":access",
  ])
}

// =====================================================================
// Request builders
// =====================================================================

/// GET …/secrets — list all secrets for a project (paged).
pub fn build_list_request(
  project: String,
  page_size: Int,
  token: SmAdcToken,
) -> Result(SmRequest, SmRefError) {
  case project {
    "" -> Error(EmptyProject)
    _ -> {
      let url =
        string.concat([
          "https://secretmanager.googleapis.com/v1/projects/",
          project,
          "/secrets?pageSize=",
          int_to_s(page_size),
        ])
      Ok(SmRequest(
        method: "GET",
        url: url,
        headers: bearer_headers(token),
        body: "",
      ))
    }
  }
}

/// GET …/secrets/{S}/versions/{V}:access — read latest version (or specific).
pub fn build_access_request(
  ref: SecretManagerRef,
  version: String,
  token: SmAdcToken,
) -> Result(SmRequest, SmRefError) {
  case validate_ref(ref) {
    Error(e) -> Error(e)
    Ok(valid_ref) -> {
      let url =
        string.concat([
          "https://secretmanager.googleapis.com/v1/",
          version_access_path(valid_ref, version),
        ])
      Ok(SmRequest(
        method: "GET",
        url: url,
        headers: bearer_headers(token),
        body: "",
      ))
    }
  }
}

/// POST …/secrets/{S}:addVersion — push a new version. SC-VAULT-011 monotonic
/// versioning is enforced by GCP server-side.
pub fn build_add_version_request(
  ref: SecretManagerRef,
  payload_b64: String,
  token: SmAdcToken,
) -> Result(SmRequest, SmRefError) {
  case validate_ref(ref) {
    Error(e) -> Error(e)
    Ok(valid_ref) -> {
      let url =
        string.concat([
          "https://secretmanager.googleapis.com/v1/",
          secret_resource_path(valid_ref),
          ":addVersion",
        ])
      let body =
        string.concat([
          "{\"payload\":{\"data\":\"",
          payload_b64,
          "\"}}",
        ])
      Ok(SmRequest(
        method: "POST",
        url: url,
        headers: bearer_headers_json(token),
        body: body,
      ))
    }
  }
}

// =====================================================================
// Response parsers (string-pure)
// =====================================================================

/// Parse `{"payload":{"data":"<base64>"}}` from access response.
pub fn parse_access_response(body: String) -> Result(String, String) {
  case string.contains(body, "\"data\":\"") {
    False -> Error("no payload.data in response")
    True -> {
      let after = string.split(body, "\"data\":\"")
      case after {
        [_, rest] -> {
          let parts = string.split(rest, "\"")
          case parts {
            [b64, ..] -> Ok(b64)
            _ -> Error("malformed data field")
          }
        }
        _ -> Error("data field appears multiple times")
      }
    }
  }
}

/// Parse the `name` field from addVersion response (returns full version path).
pub fn parse_add_version_response(body: String) -> Result(String, String) {
  case string.contains(body, "\"name\":\"") {
    False -> Error("no name field in response")
    True -> {
      let after = string.split(body, "\"name\":\"")
      case after {
        [_, rest] -> {
          let parts = string.split(rest, "\"")
          case parts {
            [name, ..] -> Ok(name)
            _ -> Error("malformed name field")
          }
        }
        _ -> Error("name field appears multiple times")
      }
    }
  }
}

// =====================================================================
// Helpers
// =====================================================================

fn bearer_headers(token: SmAdcToken) -> List(#(String, String)) {
  [
    #("Authorization", "Bearer " <> token.value),
    #("Accept", "application/json"),
  ]
}

fn bearer_headers_json(token: SmAdcToken) -> List(#(String, String)) {
  [
    #("Authorization", "Bearer " <> token.value),
    #("Content-Type", "application/json"),
    #("Accept", "application/json"),
  ]
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_s(n: Int) -> String

// =====================================================================
// Pass-35 Track D — strict response parsers
// =====================================================================
//
// Same rationale as vault_kms.parse_decrypt_response_strict (Pass-35 Track C):
// the upcoming HTTP transport needs to distinguish retriable from terminal
// failures. Both `list` and `access` get strict variants; `addVersion` is
// deferred (its body shape is currently unused by callers and would expand
// scope).
//
// Status class mapping (per Secret Manager REST docs):
//   200       → Ok(parsed)   iff body parses
//   401       → Unauthenticated  (token expired) — retriable
//   403       → PermissionDenied (IAM SA lacks accessor role) — terminal
//   404       → NotFound (secret_id doesn't exist in project) — terminal
//   429       → RateLimited (per-project rate limit) — retriable
//   5xx       → ServiceUnavailable — retriable
//   other 4xx → BadRequest — terminal
//
// `404` is split out from the generic 4xx bucket because it is the most
// common terminal error during sync (operator added a secret name to
// `secret_policy` but hasn't pushed to GCP yet). Treating it as a distinct
// variant lets the dashboard show a specific "missing in GCP" alarm
// without conflating it with malformed-request bugs.

pub type SmHttpError {
  Unauthenticated(body: String)
  PermissionDenied(body: String)
  NotFound(body: String)
  RateLimited(body: String)
  ServiceUnavailable(status: Int, body: String)
  BadRequest(status: Int, body: String)
  MalformedSuccess(body: String)
}

/// Strict variant of `parse_access_response/1` taking HTTP status + body.
/// Returns `Ok(payload_b64)` on 200, otherwise a structured `SmHttpError`.
pub fn parse_access_response_strict(
  status: Int,
  body: String,
) -> Result(String, SmHttpError) {
  case status {
    200 ->
      case parse_access_response(body) {
        Ok(b64) -> Ok(b64)
        Error(_) -> Error(MalformedSuccess(body: body))
      }
    s -> Error(classify_sm_status(s, body))
  }
}

/// Strict variant for the `list` endpoint. Returns the raw body on 200
/// (caller pages via JSON) so we don't impose a parser shape here; on
/// non-200 returns a structured error matching `parse_access_response_strict`.
pub fn parse_list_response_strict(
  status: Int,
  body: String,
) -> Result(String, SmHttpError) {
  case status {
    200 -> Ok(body)
    s -> Error(classify_sm_status(s, body))
  }
}

fn classify_sm_status(status: Int, body: String) -> SmHttpError {
  case status {
    401 -> Unauthenticated(body: body)
    403 -> PermissionDenied(body: body)
    404 -> NotFound(body: body)
    429 -> RateLimited(body: body)
    s if s >= 500 && s < 600 -> ServiceUnavailable(status: s, body: body)
    s -> BadRequest(status: s, body: body)
  }
}
