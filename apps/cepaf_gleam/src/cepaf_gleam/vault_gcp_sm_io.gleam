//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/vault_gcp_sm_io</module>
////     <fsharp-lineage>N/A (Gleam-first cloud DR root)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-VAULT-007, SC-VAULT-013, SC-VAULT-017, SC-VAULT-018</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="surjective" loss="ffi_stub">
////       HTTP transport ↠ Erlang FFI returning truthful
////       {error, "http_not_yet_wired"}. Track future work plugs in
////       hackney/gun. Pre-FFI input validation via Pass-28 builders enforces
////       SC-VAULT-013 / SC-VAULT-017 invariants regardless of transport state.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
//// Vault GCP Secret Manager I/O — HTTP wrapper around Pass-28 builders.
////
//// Slice D (this module): Stub-That-Lies-safe HTTP I/O wrapper. The Erlang
//// shim returns truthful {error, "http_not_yet_wired"}; convenience functions
//// MUST validate input via vault_gcp_sm builders BEFORE calling FFI so that
//// invalid-input failures are caught locally and only the network gap reaches
//// the (currently stubbed) transport.

import cepaf_gleam/vault_gcp_sm.{
  type SecretManagerRef, type SmAdcToken, type SmRequest, SmRequest,
}

// =====================================================================
// FFI
// =====================================================================

@external(erlang, "vault_gcp_sm_io_ffi", "execute_request")
fn ffi_execute(
  method: String,
  url: String,
  headers: List(#(String, String)),
  body: String,
) -> Result(String, String)

// =====================================================================
// Public surface
// =====================================================================

/// Execute an arbitrary SmRequest. Today the Erlang shim returns
/// Error("http_not_yet_wired") — honest per Stub-That-Lies guard.
pub fn execute(req: SmRequest) -> Result(String, String) {
  let SmRequest(method, url, headers, body) = req
  ffi_execute(method, url, headers, body)
}

/// List secrets in a project. Validates project before invoking FFI.
pub fn list_secrets(
  project: String,
  page_size: Int,
  token: SmAdcToken,
) -> Result(String, String) {
  case vault_gcp_sm.build_list_request(project, page_size, token) {
    Error(e) -> Error(format_ref_error(e))
    Ok(req) -> execute(req)
  }
}

/// Access (read) a specific version of a secret. Validates ref before FFI;
/// on transport success, parses the payload.data field.
pub fn access_secret(
  ref: SecretManagerRef,
  version: String,
  token: SmAdcToken,
) -> Result(String, String) {
  case vault_gcp_sm.build_access_request(ref, version, token) {
    Error(e) -> Error(format_ref_error(e))
    Ok(req) ->
      case execute(req) {
        Error(http_err) -> Error(http_err)
        Ok(body) -> vault_gcp_sm.parse_access_response(body)
      }
  }
}

/// Add a new version of a secret. Validates ref before FFI; on transport
/// success, parses the version `name` from the response.
pub fn add_version(
  ref: SecretManagerRef,
  payload_b64: String,
  token: SmAdcToken,
) -> Result(String, String) {
  case vault_gcp_sm.build_add_version_request(ref, payload_b64, token) {
    Error(e) -> Error(format_ref_error(e))
    Ok(req) ->
      case execute(req) {
        Error(http_err) -> Error(http_err)
        Ok(body) -> vault_gcp_sm.parse_add_version_response(body)
      }
  }
}

// =====================================================================
// Helpers
// =====================================================================

fn format_ref_error(e: vault_gcp_sm.SmRefError) -> String {
  case e {
    vault_gcp_sm.EmptyProject -> "empty_project"
    vault_gcp_sm.EmptySecretId -> "empty_secret_id"
    vault_gcp_sm.InvalidSecretId(reason) -> "invalid_secret_id: " <> reason
  }
}
