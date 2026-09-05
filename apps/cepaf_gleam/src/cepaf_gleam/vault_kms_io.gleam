//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/vault_kms_io</module>
////     <fsharp-lineage>N/A (Gleam-first cloud DR root)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-VAULT-007, SC-VAULT-013, SC-VAULT-017, SC-VAULT-019</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="surjective" loss="ffi_stub">
////       HTTP transport ↠ Erlang FFI returning truthful
////       {error, "http_not_yet_wired"}. Future commit wires hackney/gun
////       against cloudkms.googleapis.com per SC-VAULT-007 / SC-VAULT-017
////       (europe-north1 only) invariants. Pre-FFI input validation via
////       Pass-26 builders (vault_kms.validate_key_ref) catches invalid
////       refs locally regardless of transport state.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
//// Vault KMS I/O — HTTP wrapper around Pass-26 vault_kms request builder.
////
//// Slice C-C3 (this module): Stub-That-Lies-safe HTTP I/O wrapper. The Erlang
//// shim returns truthful {error, "http_not_yet_wired"}; the convenience
//// `decrypt` function MUST validate input via vault_kms.build_decrypt_request
//// BEFORE calling FFI so that invalid-input failures (wrong region, empty
//// project) are caught locally and only the network gap reaches the
//// (currently stubbed) transport.
////
//// Per SC-VAULT-005: hot path MUST NOT make network calls; this module is
//// invoked only from the supervisor's KMS unseal path (SC-VAULT-007), which
//// runs out-of-band on boot.

import cepaf_gleam/vault_kms.{
  type AdcToken, type HttpRequest, type KeyRefError, type KmsKeyRef,
  EmptyCryptoKey, EmptyKeyring, EmptyProject, HttpRequest, WrongRegion,
}

// =====================================================================
// FFI
// =====================================================================

@external(erlang, "vault_kms_io_ffi", "execute_request")
fn ffi_execute(
  method: String,
  url: String,
  headers: List(#(String, String)),
  body: String,
) -> Result(String, String)

// =====================================================================
// Public surface
// =====================================================================

/// Execute an arbitrary HttpRequest. Today the Erlang shim returns
/// Error("http_not_yet_wired") — honest per Stub-That-Lies guard
/// ([zk-3346fc607a1ef9e6]).
pub fn execute(req: HttpRequest) -> Result(String, String) {
  let HttpRequest(method, url, headers, body) = req
  ffi_execute(method, url, headers, body)
}

/// Decrypt a base64 ciphertext via Cloud KMS cryptoKeys.decrypt.
///
/// Validation order (fail-fast):
///   1. vault_kms.build_decrypt_request validates KmsKeyRef (SC-VAULT-017
///      region check, non-empty fields). Fails here NEVER reach FFI.
///   2. ffi_execute (currently stubbed) returns http_not_yet_wired.
///   3. On hypothetical transport success, vault_kms.parse_decrypt_response
///      extracts the plaintext field.
///
/// Returns Ok(plaintext_b64) on success, or a typed error string.
pub fn decrypt(
  ref: KmsKeyRef,
  token: AdcToken,
  ciphertext_b64: String,
) -> Result(String, String) {
  case vault_kms.build_decrypt_request(ref, token, ciphertext_b64) {
    Error(e) -> Error(format_key_ref_error(e))
    Ok(req) ->
      case execute(req) {
        Error(http_err) -> Error(http_err)
        Ok(body) -> vault_kms.parse_decrypt_response(body)
      }
  }
}

// =====================================================================
// Helpers
// =====================================================================

fn format_key_ref_error(e: KeyRefError) -> String {
  case e {
    EmptyProject -> "empty_project"
    EmptyKeyring -> "empty_keyring"
    EmptyCryptoKey -> "empty_crypto_key"
    WrongRegion(actual) -> "wrong_region: " <> actual
  }
}
