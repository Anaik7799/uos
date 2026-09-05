//// Vault KEK — typed Gleam wrapper around the kek_chain Rust module.
////
//// Pass-22: exposes argon2id passphrase derivation, OS-RNG salt generation,
//// and TPM device probe via the rusty_vault_nif NIF surface.
////
//// SC-VAULT-021: argon2id with memory=64MB, iterations=3, parallelism=4
//// SC-VAULT-002: derived master key MUST be passed straight to vault_unseal
////              and dropped immediately; do not stash anywhere else.
//// SC-VAULT-007: callers (vault_supervisor.gleam) walk TPM → passphrase → KMS
////              in that order; this module exposes the passphrase + TPM-probe
////              primitives. KMS DR remains in Slice C step C3.

import gleam/int

// =====================================================================
// Errors
// =====================================================================

pub type KekError {
  /// Salt was shorter than 16 bytes (SC-VAULT-021 requires fresh per-vault salt).
  SaltTooShort(actual_len: Int)
  /// argon2 internal parameter rejection.
  BadParam(reason: String)
  /// argon2 derivation failed (e.g., output buffer too small).
  DeriveFailed(reason: String)
  /// Output length must be 32 bytes for AES-256.
  BadOutputLen(actual_len: Int)
  /// NIF returned an unrecognized error tuple.
  Unknown(payload: String)
}

// =====================================================================
// FFI bindings
// =====================================================================

// Pass-23: route through rusty_vault_safe.erl which wraps the NIF in try/catch.
// This means Gleam callers get a typed Result(_, _) even when the .so isn't loaded.
@external(erlang, "rusty_vault_safe", "safe_kek_derive")
fn ffi_derive_master_key(
  passphrase: BitArray,
  salt: BitArray,
) -> Result(BitArray, #(String, String))

@external(erlang, "rusty_vault_safe", "safe_kek_generate_salt")
fn ffi_generate_salt() -> Result(BitArray, String)

@external(erlang, "rusty_vault_safe", "safe_kek_tpm_present")
fn ffi_tpm_present(override_path: String) -> Bool

// =====================================================================
// Public API
// =====================================================================

/// Derive a 32-byte master key from a passphrase + salt via argon2id.
///
/// SC-VAULT-021 parameters baked into the NIF (cannot be overridden).
/// SC-VAULT-002: caller MUST pass the returned BitArray directly to
///              vault.unseal/2 and drop it immediately. Do not store.
pub fn derive_master_key(
  passphrase: BitArray,
  salt: BitArray,
) -> Result(BitArray, KekError) {
  case ffi_derive_master_key(passphrase, salt) {
    Ok(master) -> Ok(master)
    Error(#(code, msg)) ->
      case code {
        "salt_too_short" ->
          Error(SaltTooShort(actual_len: parse_int_or_zero(msg)))
        "bad_param" -> Error(BadParam(reason: msg))
        "derive_failed" -> Error(DeriveFailed(reason: msg))
        "bad_output_len" ->
          Error(BadOutputLen(actual_len: parse_int_or_zero(msg)))
        "nif_unavailable" -> Error(Unknown(payload: "nif_unavailable:" <> msg))
        "nif_exception" -> Error(Unknown(payload: "nif_exception:" <> msg))
        _ -> Error(Unknown(payload: code <> ":" <> msg))
      }
  }
}

/// Generate a fresh 16-byte salt via OS RNG. Persisted alongside vault state.
pub fn generate_salt() -> Result(BitArray, String) {
  ffi_generate_salt()
}

/// Probe whether `/dev/tpm0` (or override path) exists.
/// Returns `True` iff the path resolves; does NOT attempt unseal.
pub fn tpm_present(override_path: String) -> Bool {
  ffi_tpm_present(override_path)
}

/// Convenience: probe the canonical `/dev/tpm0` path with no override.
pub fn tpm_present_default() -> Bool {
  ffi_tpm_present("")
}

// =====================================================================
// Helpers
// =====================================================================

fn parse_int_or_zero(s: String) -> Int {
  case int.parse(s) {
    Ok(n) -> n
    Error(_) -> 0
  }
}
