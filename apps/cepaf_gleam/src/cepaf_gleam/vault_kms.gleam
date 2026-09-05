//// Vault KMS — pure GCP KMS Decrypt request builder.
////
//// Slice C-C3 partial (Pass-26): assembles the URL, headers, and JSON body
//// for a Cloud KMS `cryptoKeys.decrypt` call, without performing the HTTP
//// request itself. The actual reqwest call lives in the supervisor's KMS
//// path and uses ADC credentials per `backup.rs` reuse pattern.
////
//// Per .claude/rules/secrets-vault.md:
////   SC-VAULT-007: KMS DR is the LAST resort in the unseal chain
////   SC-VAULT-017: GCP region MUST be europe-north1 (GDPR EU residency)
////   SC-VAULT-019: KEK DR keyring MUST be different from CMEK Secret Manager keyring
////
//// Pure functions — exhaustively unit-testable without ADC tokens or network.

import gleam/string

// =====================================================================
// Types
// =====================================================================

/// Identifier for a Cloud KMS crypto key. SC-VAULT-017 enforces europe-north1.
pub type KmsKeyRef {
  KmsKeyRef(
    project: String,
    location: String,
    keyring: String,
    crypto_key: String,
  )
}

/// Bearer token from ADC (Application Default Credentials). Caller resolves
/// via metadata server / service account JSON; this module just wraps it.
pub type AdcToken {
  AdcToken(value: String)
}

/// HTTP request envelope — minimal shape needed by both reqwest (Rust)
/// and gleam_http clients. Body is JSON-encoded utf-8 string.
pub type HttpRequest {
  HttpRequest(
    method: String,
    url: String,
    headers: List(#(String, String)),
    body: String,
  )
}

/// Validation result for `KmsKeyRef`.
pub type KeyRefError {
  EmptyProject
  EmptyKeyring
  EmptyCryptoKey
  WrongRegion(actual: String)
}

// =====================================================================
// Public API
// =====================================================================

/// Validate a `KmsKeyRef` against SC-VAULT-017 + SC-VAULT-019 invariants.
///
/// Returns `Ok(ref)` if all fields are non-empty AND location is
/// `europe-north1`. Returns specific error variant otherwise.
pub fn validate_key_ref(ref: KmsKeyRef) -> Result(KmsKeyRef, KeyRefError) {
  case ref.project, ref.keyring, ref.crypto_key, ref.location {
    "", _, _, _ -> Error(EmptyProject)
    _, "", _, _ -> Error(EmptyKeyring)
    _, _, "", _ -> Error(EmptyCryptoKey)
    _, _, _, "europe-north1" -> Ok(ref)
    _, _, _, other -> Error(WrongRegion(actual: other))
  }
}

/// Build the full Cloud KMS resource path:
///   projects/{P}/locations/{L}/keyRings/{R}/cryptoKeys/{K}
pub fn key_resource_path(ref: KmsKeyRef) -> String {
  string.concat([
    "projects/", ref.project, "/locations/", ref.location, "/keyRings/",
    ref.keyring, "/cryptoKeys/", ref.crypto_key,
  ])
}

/// Build a `cryptoKeys.decrypt` HttpRequest envelope.
///
/// `ciphertext_b64` is the base64-encoded ciphertext (the KEK sealed blob).
/// Caller is responsible for base64-encoding the bytes first; this function
/// stays string-pure for unit testability.
///
/// Per SC-VAULT-007 this only fires after TPM and passphrase paths have
/// failed; the supervisor probes network reachability via a 200ms TCP
/// connect first (cheap fail-fast — avoid DNS hangs).
pub fn build_decrypt_request(
  ref: KmsKeyRef,
  token: AdcToken,
  ciphertext_b64: String,
) -> Result(HttpRequest, KeyRefError) {
  case validate_key_ref(ref) {
    Error(e) -> Error(e)
    Ok(valid_ref) -> {
      let url =
        string.concat([
          "https://cloudkms.googleapis.com/v1/",
          key_resource_path(valid_ref),
          ":decrypt",
        ])
      let body =
        string.concat([
          "{\"ciphertext\":\"",
          ciphertext_b64,
          "\"}",
        ])
      let headers = [
        #("Authorization", "Bearer " <> token.value),
        #("Content-Type", "application/json"),
        #("Accept", "application/json"),
      ]
      Ok(HttpRequest(method: "POST", url: url, headers: headers, body: body))
    }
  }
}

/// Convenience: parse the `plaintext` field from a successful response body.
/// GCP returns `{"plaintext": "<base64-encoded master key>"}` on success.
pub fn parse_decrypt_response(body: String) -> Result(String, String) {
  // Pure-string extractor; full JSON parsing happens in the caller via gleam/json
  case string.contains(body, "\"plaintext\":\"") {
    False -> Error("no plaintext field in response")
    True -> {
      let after = string.split(body, "\"plaintext\":\"")
      case after {
        [_, rest] -> {
          let parts = string.split(rest, "\"")
          case parts {
            [b64, ..] -> Ok(b64)
            _ -> Error("malformed plaintext field")
          }
        }
        _ -> Error("plaintext field appears multiple times")
      }
    }
  }
}

// =====================================================================
// Pass-35 Track C — strict response parser
// =====================================================================
//
// Up to Pass-34 every error path collapsed into a single string. The
// upcoming HTTP transport (hackney/gun, deferred) needs to distinguish
// retriable from terminal failures. `parse_decrypt_response_strict/2`
// classifies the (status, body) pair into a structured `KmsHttpError`
// so the supervisor can decide between back-off-retry, surface-to-LLM,
// or hard-fail to operator.
//
// Status class mapping (per Cloud KMS REST docs):
//   200       → Ok(plaintext_b64) iff body parses
//   401       → Unauthenticated  (token expired / not yet exchanged) — retriable
//   403       → PermissionDenied (IAM SA lacks decrypter role) — terminal
//   429       → ResourceExhausted (per-project rate limit) — retriable w/ backoff
//   5xx       → ServiceUnavailable / Internal — retriable w/ backoff
//   other 4xx → BadRequest — terminal (client bug)
// Stub-That-Lies guard: this is pure parsing; no network. Real HTTP is
// still in `vault_kms_io_ffi.erl` returning `http_not_yet_wired`.

/// Structured error from a Cloud KMS `decrypt` HTTP response.
pub type KmsHttpError {
  Unauthenticated(body: String)
  PermissionDenied(body: String)
  RateLimited(body: String)
  ServiceUnavailable(status: Int, body: String)
  BadRequest(status: Int, body: String)
  MalformedSuccess(body: String)
}

/// Strict variant of `parse_decrypt_response/1` that takes the HTTP status
/// code AND body, returning a structured error per status class. The plain
/// `parse_decrypt_response/1` is preserved unchanged for back-compat with
/// Pass-26 callers that only had the body.
pub fn parse_decrypt_response_strict(
  status: Int,
  body: String,
) -> Result(String, KmsHttpError) {
  case status {
    200 ->
      case parse_decrypt_response(body) {
        Ok(b64) -> Ok(b64)
        Error(_) -> Error(MalformedSuccess(body: body))
      }
    401 -> Error(Unauthenticated(body: body))
    403 -> Error(PermissionDenied(body: body))
    429 -> Error(RateLimited(body: body))
    s if s >= 500 && s < 600 -> Error(ServiceUnavailable(status: s, body: body))
    s -> Error(BadRequest(status: s, body: body))
  }
}
