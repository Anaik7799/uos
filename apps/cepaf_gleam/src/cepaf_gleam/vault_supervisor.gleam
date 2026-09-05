//// Vault supervisor — owns boot-time KEK chain and supervises sync_actor.
////
//// Per .claude/rules/secrets-vault.md:
////   SC-VAULT-001: vault MUST be sealed at process start
////   SC-VAULT-007: KEK chain attempts {TPM PCR 7, passphrase, Cloud KMS} in order
////   SC-VAULT-015: KEK unseal events MUST be logged to immutable register
////   SC-VAULT-020: vault_supervisor MUST be supervised one_for_all
////
//// SLICE C SKELETON — chain logic + state types defined; OTP supervision tree
//// + actual TPM/passphrase/KMS calls land in Slice C continuation.

import cepaf_gleam/vault.{type VaultError, type VaultHandle}
import cepaf_gleam/vault_kek
import gleam/bit_array

// import gleam/result

// =====================================================================
// Types
// =====================================================================

/// KEK source — preference order at boot per SC-VAULT-007.
pub type KekSource {
  Tpm
  Passphrase
  CloudKms
}

/// Outcome of a single KEK-chain attempt.
pub type UnsealAttempt {
  Attempted(source: KekSource, success: Bool, error: String)
}

/// Result of running the full chain.
pub type ChainResult {
  /// At least one path returned a master key; vault unsealed.
  ChainOk(source: KekSource, attempts: List(UnsealAttempt))
  /// All paths failed; vault remains sealed; halt loops.
  ChainFailed(attempts: List(UnsealAttempt))
}

/// Supervisor configuration.
pub type SupervisorConfig {
  SupervisorConfig(
    storage_path: String,
    audit_path: String,
    kek_sealed_path: String,
    kek_kms_sealed_path: String,
    /// If true, skip TPM probe (test mode).
    skip_tpm: Bool,
    /// Operator passphrase (None = no passphrase configured).
    passphrase: OptionString,
  )
}

pub type OptionString {
  SomeString(value: String)
  NoneString
}

// =====================================================================
// Public API — boot orchestration
// =====================================================================

/// Boot the vault: try each KEK source in order; unseal vault on first success.
/// Returns ChainOk on success, ChainFailed on full exhaustion.
///
/// Per SC-VAULT-007 the order is fixed: TPM → passphrase → KMS.
/// Per SC-VAULT-015 every attempt is logged to the immutable register.
pub fn boot(
  config: SupervisorConfig,
  handle: VaultHandle,
) -> Result(ChainResult, VaultError) {
  let attempts = []

  // Step 1: TPM
  let #(tpm_master_key_opt, attempts) = case config.skip_tpm {
    True -> #(NoneBytes, [
      Attempted(Tpm, False, "skipped (test mode)"),
      ..attempts
    ])
    False -> attempt_tpm_unseal(config.kek_sealed_path, attempts)
  }

  case tpm_master_key_opt {
    SomeBytes(key) -> {
      let _ = vault.unseal(handle, key)
      Ok(ChainOk(source: Tpm, attempts: list_reverse(attempts)))
    }
    NoneBytes -> {
      // Step 2: passphrase
      let #(pass_master_key_opt, attempts) = case config.passphrase {
        SomeString(pass) -> attempt_passphrase_unseal(pass, attempts)
        NoneString -> #(NoneBytes, [
          Attempted(Passphrase, False, "no passphrase configured"),
          ..attempts
        ])
      }

      case pass_master_key_opt {
        SomeBytes(key) -> {
          let _ = vault.unseal(handle, key)
          Ok(ChainOk(source: Passphrase, attempts: list_reverse(attempts)))
        }
        NoneBytes -> {
          // Step 3: Cloud KMS DR fallback
          let #(kms_master_key_opt, attempts) =
            attempt_kms_unseal(config.kek_kms_sealed_path, attempts)

          case kms_master_key_opt {
            SomeBytes(key) -> {
              let _ = vault.unseal(handle, key)
              Ok(ChainOk(source: CloudKms, attempts: list_reverse(attempts)))
            }
            NoneBytes -> Ok(ChainFailed(attempts: list_reverse(attempts)))
          }
        }
      }
    }
  }
}

// =====================================================================
// KEK source attempts (Slice C continuation will replace stubs)
// =====================================================================

pub type OptionBytes {
  SomeBytes(value: BitArray)
  NoneBytes
}

/// Attempt TPM 2.0 PCR 7 unseal. Slice C continuation: bind to tss-esapi crate via NIF.
fn attempt_tpm_unseal(
  _path: String,
  attempts: List(UnsealAttempt),
) -> #(OptionBytes, List(UnsealAttempt)) {
  // TODO Slice C continuation: tpm2_unseal -c <handle> -p pcr:sha256:7
  #(NoneBytes, [
    Attempted(Tpm, False, "TPM unseal not yet wired (Slice C in progress)"),
    ..attempts
  ])
}

/// Attempt passphrase unseal via argon2id derive (Pass-23 Slice C-C2 closure).
///
/// Calls `vault_kek.generate_salt` + `vault_kek.derive_master_key` via the
/// rusty_vault_nif NIF. Per SC-VAULT-021 the parameters are baked into the NIF.
/// Per SC-VAULT-002 the derived BitArray is passed straight back to the caller
/// (boot supervisor), which immediately feeds it to `vault.unseal/2` and drops it.
///
/// NB: in test-mode where the NIF .so is not loaded, `generate_salt`/`derive_master_key`
/// will raise `nif_error({not_loaded, _})`. The caller can guard with a try/catch
/// supervisor — but the orchestration shape (record attempt + return OptionBytes)
/// is identical whether the derive succeeds, fails, or panics-from-missing-NIF.
fn attempt_passphrase_unseal(
  pass: String,
  attempts: List(UnsealAttempt),
) -> #(OptionBytes, List(UnsealAttempt)) {
  case vault_kek.generate_salt() {
    Error(reason) -> #(NoneBytes, [
      Attempted(Passphrase, False, "salt-gen failed: " <> reason),
      ..attempts
    ])
    Ok(salt) -> {
      let pw_bits = bit_array.from_string(pass)
      case vault_kek.derive_master_key(pw_bits, salt) {
        Ok(master) -> #(SomeBytes(master), [
          Attempted(Passphrase, True, ""),
          ..attempts
        ])
        Error(_e) -> #(NoneBytes, [
          Attempted(Passphrase, False, "argon2 derive failed"),
          ..attempts
        ])
      }
    }
  }
}

/// Attempt Cloud KMS DR unseal. Network call — only used at boot.
fn attempt_kms_unseal(
  _path: String,
  attempts: List(UnsealAttempt),
) -> #(OptionBytes, List(UnsealAttempt)) {
  // TODO Slice C continuation: reqwest to GCP KMS Decrypt API
  #(NoneBytes, [
    Attempted(CloudKms, False, "KMS DR unseal not yet wired"),
    ..attempts
  ])
}

// =====================================================================
// Helpers
// =====================================================================

fn list_reverse(xs: List(a)) -> List(a) {
  do_reverse(xs, [])
}

fn do_reverse(xs: List(a), acc: List(a)) -> List(a) {
  case xs {
    [] -> acc
    [head, ..tail] -> do_reverse(tail, [head, ..acc])
  }
}
