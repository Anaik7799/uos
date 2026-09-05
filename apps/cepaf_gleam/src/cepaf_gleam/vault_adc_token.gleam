//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/vault_adc_token</module>
////     <fsharp-lineage>N/A (cloud-native ADC token wrapper)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-VAULT-007, SC-VAULT-018</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="surjective" loss="none">
////       Wave 7 Track 3: real ADC user-credentials path. Reads gcloud
////       application_default_credentials.json (or the path in
////       GOOGLE_APPLICATION_CREDENTIALS), validates `type ==
////       "authorized_user"`, exchanges the refresh_token at
////       https://oauth2.googleapis.com/token for an access_token. Honest
////       deferred: service-account JSON exchange (RS256 JWT signing) +
////       GCE metadata-server (option 3) — both out of scope this wave.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
//// Vault ADC Token — Wave 7 Track 3 + Wave 8 Worker 1.
////
//// Resolution chain:
////   1. `GOOGLE_APPLICATION_CREDENTIALS` env var → that path
////   2. `~/.config/gcloud/application_default_credentials.json`
////   3. (deferred) GCE metadata-server
////
//// Supported credential types:
////   - `authorized_user`  → refresh_token grant (Wave 7)
////   - `service_account`  → RS256 JWT-bearer grant (Wave 8 Worker 1)
////
//// Errors (canonical wire vocabulary; tests gate on these strings):
////   - `adc_no_credentials_found`     — no regular file at any candidate path
////   - `adc_unsupported_format`       — file present but not a recognised type,
////                                      or missing required fields
////   - `adc_malformed_json`           — file is not parseable JSON
////   - `adc_token_refresh_failed: …`  — refresh-grant 4xx/5xx or no access_token
////   - `adc_transport_error: …`       — refresh-grant httpc transport failure
////   - `sa_jwt_sign_failed: …`        — RS256 sign / encode failure
////   - `sa_pem_decode_failed: …`      — PEM private-key parse failure
////   - `sa_token_exchange_failed: …`  — JWT-bearer grant 4xx/5xx or no token
////   - `sa_transport_error: …`        — JWT-bearer httpc transport failure
////
//// [zk-3346fc607a1ef9e6] Stub-That-Lies guard: every error path is explicit.
//// NEVER returns a fabricated bearer.

/// SC-VAULT-007: Cloud KMS DR root requires ADC token. Wave 7 wired the
/// authorized_user (gcloud user-credentials) path. Wave 8 Worker 1 adds the
/// service_account RS256 JWT-bearer path. The GCE metadata-server (option 3)
/// remains hardware-bound and deferred.
@external(erlang, "vault_adc_token_ffi", "resolve_token")
fn resolve_token_ffi() -> Result(String, String)

pub fn fetch_metadata_server_token() -> Result(String, String) {
  resolve_token_ffi()
}
