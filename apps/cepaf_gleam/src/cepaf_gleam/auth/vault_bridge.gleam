//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/auth/vault_bridge</module>
////     <fsharp-lineage>New</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-VAULT-003, SC-VAULT-005, SC-VAULT-006, SC-FERRISKEY-NIF-010, SC-GCP-IAM-006</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Plaintext secret references ↪ rusty_vault_nif `vault_kv_*` calls.
////       No secret value crosses this module boundary except via the NIF.
////       In-process — SC-VAULT-005 hot-path-no-network satisfied.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// LIVE vault bridge — every IAM secret in the FerrisKey-NIF subsystem is
//// stored and retrieved via `rusty_vault_nif` (existing crate at
//// `lib/cepaf_gleam/native/rusty_vault_nif/`). This module wraps the
//// `vault_kv_put` / `vault_kv_get` Erlang shim with typed Gleam APIs and
//// the canonical IAM secret-path conventions.
////
//// ## Vault handoff workflow (SC-FERRISKEY-NIF-010)
////
//// ```
//// 1. ferriskey_nif.signing_key_rotate(db, realm, "EdDSA")
////      → returns { kid, seed_b64, vault_path, public_jwk }
//// 2. vault_bridge.put_signing_key_seed(handle, vault_path, seed_b64)
////      → calls rusty_vault_nif.vault_kv_put(...)
//// 3. ferriskey_nif.signing_key_purge_local(db, kid)
////      → drops the SQLite fallback row
//// ```
////
//// After step 3, the only on-disk copy of the seed lives in vault.
//// `token_issue_with_seed` is the hot-path JWT minter; it accepts the seed
//// from `vault_bridge.get_signing_key_seed` (see rules/iam-ferriskey-nif.md).

import gleam/bit_array
import gleam/dynamic.{type Dynamic}

// ---------------------------------------------------------------------------
// External bindings — rusty_vault_nif (existing crate)
// ---------------------------------------------------------------------------

@external(erlang, "rusty_vault_nif", "vault_kv_put")
fn nif_vault_kv_put(
  handle: Dynamic,
  name: String,
  value: BitArray,
  ttl: Int,
  max_ttl: Int,
) -> Result(Dynamic, Dynamic)

@external(erlang, "rusty_vault_nif", "vault_kv_get")
fn nif_vault_kv_get(handle: Dynamic, name: String) -> Result(BitArray, Dynamic)

@external(erlang, "rusty_vault_nif", "vault_kv_destroy")
fn nif_vault_kv_destroy(
  handle: Dynamic,
  name: String,
  version: Int,
) -> Result(Dynamic, Dynamic)

// ---------------------------------------------------------------------------
// Vault paths (SC-FERRISKEY-NIF-010, SC-GCP-IAM-006)
// ---------------------------------------------------------------------------

/// FerrisKey signing-key vault paths. `kid` is the JWT key id.
pub fn signing_key_path(alg: String, kid: String) -> String {
  "iam/signing/" <> alg <> "/" <> kid
}

/// GCP service-account key vault path.
pub fn gcp_sa_path(sa_short: String) -> String {
  "iam/gcp-sa/" <> sa_short
}

/// SCIM provisioning bearer token (Google → us inbound).
pub const scim_provisioning_token_path: String = "iam/scim/provisioning-token"

/// OIDC client secret per RP client.
pub fn oidc_client_secret_path(client_id: String) -> String {
  "iam/oidc/clients/" <> client_id
}

// ---------------------------------------------------------------------------
// TTL policy (consumed by RustyVault `secret_policy` table)
// ---------------------------------------------------------------------------

pub type TtlSeconds {
  TtlSeconds(value: Int)
}

pub const ttl_signing_key: TtlSeconds = TtlSeconds(7_776_000)

// 90 days

pub const ttl_gcp_sa: TtlSeconds = TtlSeconds(2_592_000)

// 30 days

pub const ttl_scim_token: TtlSeconds = TtlSeconds(604_800)

// 7 days

pub const ttl_oidc_client: TtlSeconds = TtlSeconds(15_552_000)

// 180 days

// ---------------------------------------------------------------------------
// Secret kinds — one variant per IAM secret class
// ---------------------------------------------------------------------------

pub type SecretKind {
  SigningKeyRs256
  SigningKeyEs256
  SigningKeyEd25519
  GcpSaScim
  GcpSaBackup
  GcpSaLogging
  GcpSaPubsub
  ScimProvisioning
  OidcClient
}

pub fn ttl_for(kind: SecretKind) -> TtlSeconds {
  case kind {
    SigningKeyRs256 -> ttl_signing_key
    SigningKeyEs256 -> ttl_signing_key
    SigningKeyEd25519 -> ttl_signing_key
    GcpSaScim -> ttl_gcp_sa
    GcpSaBackup -> ttl_gcp_sa
    GcpSaLogging -> ttl_gcp_sa
    GcpSaPubsub -> ttl_gcp_sa
    ScimProvisioning -> ttl_scim_token
    OidcClient -> ttl_oidc_client
  }
}

// ---------------------------------------------------------------------------
// Public API — typed wrappers around rusty_vault_nif
// ---------------------------------------------------------------------------

pub type VaultError {
  VaultPutFailed(reason: String)
  VaultGetFailed(reason: String)
  VaultDestroyFailed(reason: String)
}

/// Store an Ed25519 signing-key seed in vault. Called immediately after
/// `ferriskey_nif.signing_key_export_seed` returns. The seed is treated as
/// opaque bytes (BitArray); the vault enforces TTL and KEK encryption.
pub fn put_signing_key_seed(
  handle: Dynamic,
  vault_path: String,
  seed_b64: String,
) -> Result(Nil, VaultError) {
  let TtlSeconds(ttl) = ttl_signing_key
  let max_ttl = ttl * 2
  // Convert b64 string to BitArray for the NIF — vault stores the textual
  // base64 representation so callers can round-trip without rehashing.
  let value = bit_array.from_string(seed_b64)
  case nif_vault_kv_put(handle, vault_path, value, ttl, max_ttl) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(VaultPutFailed(reason: describe(e)))
  }
}

/// Fetch an Ed25519 signing-key seed from vault. Returns the base64 string
/// that `ferriskey_nif.token_issue_with_seed` expects.
pub fn get_signing_key_seed(
  handle: Dynamic,
  vault_path: String,
) -> Result(String, VaultError) {
  case nif_vault_kv_get(handle, vault_path) {
    Ok(value) ->
      case bit_array.to_string(value) {
        Ok(s) -> Ok(s)
        Error(_) -> Error(VaultGetFailed(reason: "invalid_utf8"))
      }
    Error(e) -> Error(VaultGetFailed(reason: describe(e)))
  }
}

/// Store a GCP SA key in vault. Returns the canonical path so subsequent
/// `gcp_sts_exchange` calls can reference it. SC-GCP-IAM-006.
pub fn put_gcp_sa_key(
  handle: Dynamic,
  sa_short: String,
  key_pem: String,
) -> Result(String, VaultError) {
  let path = gcp_sa_path(sa_short)
  let TtlSeconds(ttl) = ttl_gcp_sa
  let max_ttl = ttl * 2
  let value = bit_array.from_string(key_pem)
  case nif_vault_kv_put(handle, path, value, ttl, max_ttl) {
    Ok(_) -> Ok(path)
    Error(e) -> Error(VaultPutFailed(reason: describe(e)))
  }
}

/// Destroy a vault entry — used during signing-key retirement after the
/// 7-day overlap window per SC-FERRISKEY-NIF-008.
pub fn destroy(
  handle: Dynamic,
  vault_path: String,
  version: Int,
) -> Result(Nil, VaultError) {
  case nif_vault_kv_destroy(handle, vault_path, version) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(VaultDestroyFailed(reason: describe(e)))
  }
}

@external(erlang, "erlang", "term_to_binary")
fn term_to_binary(term: Dynamic) -> BitArray

fn describe(d: Dynamic) -> String {
  case bit_array.to_string(term_to_binary(d)) {
    Ok(s) -> s
    Error(_) -> "vault_error"
  }
}
