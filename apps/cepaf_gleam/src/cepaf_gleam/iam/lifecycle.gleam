//// =============================================================================
//// [C3I-SIL6-MSTS] iam/lifecycle — full vault-backed signing-key lifecycle
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam/lifecycle</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-FERRISKEY-NIF-008, SC-FERRISKEY-NIF-010, SC-VAULT-003</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// Orchestrates the full vault-backed signing-key lifecycle by coordinating
//// `ferriskey_nif` (signing_key_rotate / export_seed / purge_local /
//// token_issue_with_seed) with `vault_bridge` (rusty_vault_nif.vault_kv_*).
////
//// This module is the proof that "full integration with vault" works
//// end-to-end at the Gleam type level — every cross-NIF boundary is
//// typed and the data path goes through the LIVE @external bindings.
////
//// ## Workflow
////
//// ```
//// rotate_to_vault(db, vault_handle, realm_id, alg)
////   ↓ ferriskey_nif.signing_key_rotate(db, realm_id, alg)
////       → RotateResult(kid, alg, seed_b64, vault_path, public_jwk)
////   ↓ vault_bridge.put_signing_key_seed(handle, vault_path, seed_b64)
////       → rusty_vault_nif.vault_kv_put(...)        [LIVE @external]
////   ↓ ferriskey_nif.signing_key_purge_local(db, kid)
////       → SQLite seed dropped, SC-FERRISKEY-NIF-010 closes
////   ← Ok(VaultHandoff { kid, vault_path })
////
////
//// issue_via_vault(db, vault_handle, realm, user, audience, scopes, ttl, kid, vault_path)
////   ↓ vault_bridge.get_signing_key_seed(handle, vault_path)
////       → rusty_vault_nif.vault_kv_get(...)        [LIVE @external]
////   ↓ ferriskey_nif.token_issue_with_seed(db, realm, user, ..., kid, seed)
////       → IssuedToken(jwt, exp, kid, alg)
////   ← Ok(IssuedToken)
//// ```

import cepaf_gleam/auth/ferriskey_nif as fk
import cepaf_gleam/auth/vault_bridge
import gleam/dynamic.{type Dynamic}
import gleam/result

pub type LifecycleError {
  RotateFailed(reason: String)
  VaultPutFailed(reason: String)
  VaultGetFailed(reason: String)
  PurgeFailed(reason: String)
  IssueFailed(reason: String)
}

pub type VaultHandoff {
  VaultHandoff(kid: String, alg: String, vault_path: String)
}

/// Run the full rotate-to-vault sequence: rotate signing key, store seed
/// in vault, drop SQLite fallback. Returns the handoff record (kid +
/// vault_path) for subsequent use by `issue_via_vault`.
///
/// SC-FERRISKEY-NIF-008 (rotation), SC-FERRISKEY-NIF-010 (vault custody),
/// SC-VAULT-003 (typed wrapper).
pub fn rotate_to_vault(
  db_path: String,
  vault_handle: Dynamic,
  realm_id: String,
  alg: String,
) -> Result(VaultHandoff, LifecycleError) {
  use rotate_result <- result.try(
    fk.signing_key_rotate(db_path, realm_id, alg)
    |> result.map_error(fn(e) { RotateFailed(reason: describe_iam(e)) }),
  )

  use _put_ok <- result.try(
    vault_bridge.put_signing_key_seed(
      vault_handle,
      rotate_result.vault_path,
      rotate_result.seed_b64,
    )
    |> result.map_error(fn(e) { VaultPutFailed(reason: describe_vault(e)) }),
  )

  use _purged <- result.try(
    fk.signing_key_purge_local(db_path, rotate_result.kid)
    |> result.map_error(fn(e) { PurgeFailed(reason: describe_iam(e)) }),
  )

  Ok(VaultHandoff(
    kid: rotate_result.kid,
    alg: rotate_result.alg,
    vault_path: rotate_result.vault_path,
  ))
}

/// Issue a JWT using a vault-supplied seed. The hot-path replacement for
/// `fk.token_issue` once the rotate-to-vault handoff has run.
pub fn issue_via_vault(
  db_path: String,
  vault_handle: Dynamic,
  handoff: VaultHandoff,
  realm_id: String,
  user_id: String,
  audience: String,
  scopes_csv: String,
  ttl_seconds: Int,
) -> Result(fk.IssuedToken, LifecycleError) {
  use seed <- result.try(
    vault_bridge.get_signing_key_seed(vault_handle, handoff.vault_path)
    |> result.map_error(fn(e) { VaultGetFailed(reason: describe_vault(e)) }),
  )

  fk.token_issue_with_seed(
    db_path,
    realm_id,
    user_id,
    audience,
    scopes_csv,
    ttl_seconds,
    handoff.kid,
    seed,
  )
  |> result.map_error(fn(e) { IssueFailed(reason: describe_iam(e)) })
}

fn describe_iam(e: fk.IamError) -> String {
  case e {
    fk.NifNotLoaded -> "nif_not_loaded"
    fk.DecodeFailed(s) -> "decode_failed:" <> s
    fk.IamFailure(s) -> s
  }
}

fn describe_vault(e: vault_bridge.VaultError) -> String {
  case e {
    vault_bridge.VaultPutFailed(reason: r) -> "put:" <> r
    vault_bridge.VaultGetFailed(reason: r) -> "get:" <> r
    vault_bridge.VaultDestroyFailed(reason: r) -> "destroy:" <> r
  }
}
