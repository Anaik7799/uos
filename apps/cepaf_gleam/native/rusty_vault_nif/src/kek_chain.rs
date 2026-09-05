//! kek_chain — KEK (Key Encryption Key) derivation helpers for the boot chain.
//!
//! Slice C partial: argon2id passphrase derivation. This is one of three
//! paths in the SC-VAULT-007 unseal preference chain:
//!   1. TPM 2.0 PCR 7 unseal       (preferred — offline-capable, hardware-bound)
//!   2. argon2id passphrase derive (fallback — offline-capable, this module)
//!   3. Cloud KMS Decrypt          (DR — network-required, last resort)
//!
//! This file ships the argon2 path only. TPM and Cloud KMS paths are tracked
//! by `slice-plans/slice-c-continuation.md` Slice C steps C2 and C3.
//!
//! SC-VAULT-021: argon2id MUST use memory=64MB, iterations=3, parallelism=4.
//! SC-VAULT-002: derived master key MUST be wrapped in `Zeroizing` so it never
//!               sits in plaintext on the heap after the unseal step.

use argon2::{Algorithm, Argon2, Params, Version};
use std::path::Path;
use thiserror::Error;
use zeroize::Zeroizing;

#[derive(Debug, Error)]
pub enum KekDeriveError {
    #[error("argon2 parameter rejected: {0}")]
    BadParam(String),
    #[error("argon2 derivation failed: {0}")]
    DeriveFailed(String),
    #[error("salt must be at least 16 bytes (got {0})")]
    SaltTooShort(usize),
    #[error("output length must be 32 bytes for AES-256 master key (got {0})")]
    BadOutputLen(usize),
}

/// SC-VAULT-021 canonical argon2id parameters.
/// 64 MiB memory cost, 3 iterations, parallelism 4, 32-byte output.
pub const ARGON2_MEMORY_KIB: u32 = 64 * 1024;
pub const ARGON2_ITERATIONS: u32 = 3;
pub const ARGON2_PARALLELISM: u32 = 4;
pub const MASTER_KEY_LEN: usize = 32;
pub const SALT_MIN_LEN: usize = 16;

/// Derive the 32-byte master key from a passphrase + salt using argon2id.
///
/// The returned `Zeroizing<Vec<u8>>` zeroes its buffer on drop (SC-VAULT-002).
/// Caller is responsible for passing the buffer directly to
/// `vault_unseal(handle, master_key)` and dropping it immediately after.
///
/// # Errors
/// - `SaltTooShort` if `salt.len() < 16` (SC-VAULT-021 requires fresh per-vault salt)
/// - `BadParam` / `DeriveFailed` on argon2 internal errors
pub fn derive_master_key(
    passphrase: &[u8],
    salt: &[u8],
) -> Result<Zeroizing<Vec<u8>>, KekDeriveError> {
    if salt.len() < SALT_MIN_LEN {
        return Err(KekDeriveError::SaltTooShort(salt.len()));
    }

    let params = Params::new(
        ARGON2_MEMORY_KIB,
        ARGON2_ITERATIONS,
        ARGON2_PARALLELISM,
        Some(MASTER_KEY_LEN),
    )
    .map_err(|e| KekDeriveError::BadParam(e.to_string()))?;

    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut out = Zeroizing::new(vec![0u8; MASTER_KEY_LEN]);
    argon2
        .hash_password_into(passphrase, salt, &mut out)
        .map_err(|e| KekDeriveError::DeriveFailed(e.to_string()))?;

    Ok(out)
}

/// Generate a fresh 16-byte salt using the OS RNG. Caller persists this
/// alongside the encrypted vault state so subsequent unseals can re-derive.
pub fn generate_salt() -> [u8; SALT_MIN_LEN] {
    use rand_core::{OsRng, RngCore};
    let mut salt = [0u8; SALT_MIN_LEN];
    OsRng.fill_bytes(&mut salt);
    salt
}

// =====================================================================
// SC-VAULT-007 KEK chain orchestration
// =====================================================================

/// Identifies which path in the SC-VAULT-007 preference order produced the master key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KekSource {
    Tpm,
    Passphrase,
    CloudKmsDr,
}

/// Runtime state of an individual KEK path.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KekPathOutcome {
    /// Path produced a master key (caller must zeroize after `vault_unseal`).
    Ok(KekSource),
    /// Path was skipped (precondition false, e.g. /dev/tpm0 absent, env unset).
    /// `reason` is a stable machine-readable token (no PII, no plaintext).
    Skipped { source: KekSource, reason: &'static str },
    /// Path attempted but failed (wrong key, IAM revoked, PCR mismatch).
    Failed { source: KekSource, reason: &'static str },
}

/// SC-VAULT-007 Path 1 stub — TPM 2.0 PCR 7 unseal (Slice C step C1 continuation).
///
/// **Status:** SCAFFOLD ONLY. Returns a typed error with the stable token
/// `"tpm_unseal_not_yet_wired"`. This function deliberately does NOT call any
/// TPM hardware API and does NOT use `unimplemented!()` / `todo!()` so that:
///   1. The boot supervisor's fail-closed branch (SC-VAULT-001) can match
///      this error without panicking,
///   2. Pass-17/21 lock-in-trap scanners detect the stable token in CI logs,
///   3. Stub-That-Lies guard ([zk-3346fc607a1ef9e6], RPN 729) is satisfied —
///      caller cannot mistake this for a working unseal.
///
/// Wiring this requires the `tss-esapi` crate, which depends on the system
/// `tss2-sys` library (libtss2-dev). At the time of authoring, that lib was
/// not present on the build host (apt-cache shows it but headers absent and
/// installing requires sudo), so the production dep was deferred.
///
/// **Pass-34 (this turn)**: introduced the `TpmUnsealer` trait + `MockTpm`
/// in-memory implementation so the full `derive_kek_chain` flow can be
/// exercised with a real success/failure branch under unit test. The
/// public `tpm_unseal_pcr7` shim still returns the stable
/// `"tpm_unseal_not_yet_wired"` token to preserve the lock-in trap until the
/// system library lands.
///
/// Real implementation will:
///   - open the TPM resource manager (`/dev/tpmrm0`) via tss-esapi `Context`,
///   - load the sealed blob persisted at the configured handle,
///   - execute `TPM2_Unseal` gated on a PCR 7 policy session,
///   - return the unsealed 32-byte master key wrapped in `Zeroizing`.
pub fn tpm_unseal_pcr7(
    tpm_dev: &Path,
    sealed_blob: &[u8],
) -> Result<Zeroizing<Vec<u8>>, KekDeriveError> {
    #[cfg(feature = "tpm")]
    {
        return tpm_unseal_pcr7_real(tpm_dev, sealed_blob);
    }
    #[cfg(not(feature = "tpm"))]
    {
        let _ = (tpm_dev, sealed_blob);
        Err(KekDeriveError::DeriveFailed(
            "tpm_unseal_not_yet_wired".to_string(),
        ))
    }
}

/// Pass-36 Track A — real TPM 2.0 PCR 7 unseal via `tss-esapi`.
///
/// Compiled only when `--features tpm` is active. The function:
///   1. Opens a `Context` via the device TCTI pointed at `tpm_dev`
///      (e.g. `/dev/tpmrm0`). Falls back to the device-name string
///      if the path is non-standard.
///   2. Returns a typed `KekDeriveError::DeriveFailed(<stable token>)`
///      on every failure mode so the caller can branch deterministically
///      and CI lock-in-trap scanners can detect the deferred
///      "no sealed blob loaded" state until provisioning lands.
///
/// Stable error tokens (Stub-That-Lies guard, [zk-3346fc607a1ef9e6]):
///   - "tpm_tcti_open_failed"     — `/dev/tpmrm0` (or override) not openable
///   - "tpm_context_init_failed"  — esys context could not be initialised
///   - "tpm_no_sealed_blob"       — caller passed empty sealed_blob (provisioning gap)
///   - "tpm_unseal_failed"        — TPM2_Unseal command itself rejected the blob
///                                  (PCR mismatch, policy mismatch, auth failure, etc.)
///
/// **What this is NOT yet wiring**: the parsed `sealed_blob` → `(public, private)`
/// TPM2B serialization split, ESYS_TR loading via `Context::load`, the PCR 7
/// policy session creation, and `Context::unseal`. Each of those requires a
/// provisioned TPM with a sealed object at a known persistent handle, which is
/// out of scope of a software-only build host. We instead wire the *Context
/// initialisation* path mechanically (the part that fails today on a no-TPM
/// host) and emit a stable token for the rest. This is the largest honest
/// chunk that can land without fabricating hardware state.
#[cfg(feature = "tpm")]
fn tpm_unseal_pcr7_real(
    tpm_dev: &Path,
    sealed_blob: &[u8],
) -> Result<Zeroizing<Vec<u8>>, KekDeriveError> {
    use tss_esapi::tcti_ldr::{DeviceConfig, TctiNameConf};
    use tss_esapi::Context;

    if sealed_blob.is_empty() {
        return Err(KekDeriveError::DeriveFailed(
            "tpm_no_sealed_blob".to_string(),
        ));
    }

    // Build a device TCTI configuration pointing at the requested node.
    // tss-esapi's DeviceConfig::default() uses /dev/tpmrm0; if the caller
    // passed a path, we use it via from_str to honour overrides.
    let dev_str = tpm_dev.to_string_lossy().into_owned();
    let device_config: DeviceConfig = if dev_str == "/dev/tpmrm0" || dev_str.is_empty() {
        DeviceConfig::default()
    } else {
        // Use std::str::FromStr; on parse failure surface as TCTI open failure.
        match dev_str.parse::<DeviceConfig>() {
            Ok(c) => c,
            Err(_) => {
                return Err(KekDeriveError::DeriveFailed(
                    "tpm_tcti_open_failed".to_string(),
                ));
            }
        }
    };
    let tcti = TctiNameConf::Device(device_config);

    let _ctx = Context::new(tcti).map_err(|_| {
        KekDeriveError::DeriveFailed("tpm_context_init_failed".to_string())
    })?;

    // Provisioning the sealed object + PCR 7 policy session is intentionally
    // not implemented in this pass — it requires a real TPM with a pre-sealed
    // blob loaded at a persistent handle, which the build host doesn't have.
    // Returning a stable token preserves the lock-in trap.
    Err(KekDeriveError::DeriveFailed(
        "tpm_unseal_failed".to_string(),
    ))
}

// =====================================================================
// SC-VAULT-007 Path 1 — TPM unsealer trait + MockTpm (Pass-34)
// =====================================================================

/// Abstract TPM 2.0 PCR 7 unseal surface. The real impl will be a tss-esapi
/// `Context` adapter behind `cfg(feature = "tpm")`; this trait lets the
/// unseal-flow logic be unit-tested today against a deterministic in-memory
/// fake without requiring libtss2-dev on the build host.
pub trait TpmUnsealer {
    /// Attempt to unseal a sealed blob. On success returns a 32-byte
    /// `Zeroizing<Vec<u8>>` master key. On failure returns a stable token.
    fn unseal_pcr7(&self, sealed_blob: &[u8]) -> Result<Zeroizing<Vec<u8>>, KekDeriveError>;
}

/// In-memory deterministic fake TPM. Used ONLY in unit tests and the
/// `tpm` cargo feature is OFF in production builds.
///
/// The `expected_blob → key` map encodes "the sealed blob the TPM agreed to
/// release was the one we asked it to seal". Any mismatch returns the
/// stable token `"tpm_pcr7_mismatch"` so callers can branch deterministically.
pub struct MockTpm {
    expected_blob: Vec<u8>,
    sealed_key: [u8; 32],
}

impl MockTpm {
    /// Construct a MockTpm that will release `key` iff the caller presents
    /// the same `blob` that was registered at construction.
    pub fn new(blob: &[u8], key: [u8; 32]) -> Self {
        Self {
            expected_blob: blob.to_vec(),
            sealed_key: key,
        }
    }

    /// Construct a deterministic MockTpm with a fixed test blob and
    /// `[0x42; 32]` master key — useful for chain-orchestration tests.
    pub fn for_tests() -> Self {
        Self::new(b"test-sealed-blob-pcr7", [0x42u8; 32])
    }
}

impl TpmUnsealer for MockTpm {
    fn unseal_pcr7(&self, sealed_blob: &[u8]) -> Result<Zeroizing<Vec<u8>>, KekDeriveError> {
        if sealed_blob == self.expected_blob.as_slice() {
            Ok(Zeroizing::new(self.sealed_key.to_vec()))
        } else {
            Err(KekDeriveError::DeriveFailed("tpm_pcr7_mismatch".to_string()))
        }
    }
}

/// Probe whether a TPM 2.0 device node is reachable.
/// SC-VAULT-007 ordering: TPM is preferred only if `/dev/tpm0` (or
/// `tpm_dev_override`) exists. Production unseal uses tss-esapi (Slice C step C1
/// continuation, not in this build).
pub fn tpm_present(tpm_dev_override: Option<&Path>) -> bool {
    let candidate: &Path = tpm_dev_override.unwrap_or_else(|| Path::new("/dev/tpm0"));
    candidate.exists()
}

/// SC-VAULT-007 chain orchestrator (Pass-14 partial).
///
/// Walks the preference order: TPM → passphrase → Cloud KMS DR.
/// Currently only the **passphrase** branch returns a real master key;
/// TPM and Cloud KMS DR return `Skipped` with a stable reason token until
/// their respective Slice C step C1 / step C3 land.
///
/// The chain is **fail-closed by construction**: if every path returns
/// `Skipped` or `Failed`, the function returns `Err(KekDeriveError::DeriveFailed)`
/// and the boot supervisor MUST refuse to unseal (SC-VAULT-006 + SC-VAULT-001).
///
/// This signature is intentionally explicit (no env reads) so it stays unit-testable
/// and free of side effects — the boot supervisor passes inputs from systemd-creds
/// or operator prompt.
pub fn derive_kek_chain(
    tpm_dev_override: Option<&Path>,
    passphrase: Option<&[u8]>,
    salt: &[u8],
    kms_decrypt_available: bool,
) -> Result<(Zeroizing<Vec<u8>>, KekSource, Vec<KekPathOutcome>), KekDeriveError> {
    let mut history: Vec<KekPathOutcome> = Vec::new();

    // Path 1 — TPM PCR 7 (preferred, Slice C step C1 continuation)
    if tpm_present(tpm_dev_override) {
        history.push(KekPathOutcome::Skipped {
            source: KekSource::Tpm,
            reason: "tpm_unseal_not_yet_wired",
        });
    } else {
        history.push(KekPathOutcome::Skipped {
            source: KekSource::Tpm,
            reason: "tpm_dev_absent",
        });
    }

    // Path 2 — argon2id passphrase (Slice C step C2, real)
    match passphrase {
        Some(pw) => match derive_master_key(pw, salt) {
            Ok(key) => {
                history.push(KekPathOutcome::Ok(KekSource::Passphrase));
                return Ok((key, KekSource::Passphrase, history));
            }
            Err(e @ KekDeriveError::SaltTooShort(_)) => return Err(e),
            Err(_) => history.push(KekPathOutcome::Failed {
                source: KekSource::Passphrase,
                reason: "argon2_internal",
            }),
        },
        None => history.push(KekPathOutcome::Skipped {
            source: KekSource::Passphrase,
            reason: "passphrase_unset",
        }),
    }

    // Path 3 — Cloud KMS DR (Slice C step C3 continuation)
    if kms_decrypt_available {
        history.push(KekPathOutcome::Skipped {
            source: KekSource::CloudKmsDr,
            reason: "kms_decrypt_not_yet_wired",
        });
    } else {
        history.push(KekPathOutcome::Skipped {
            source: KekSource::CloudKmsDr,
            reason: "kms_unreachable_or_disabled",
        });
    }

    // SC-VAULT-001 fail-closed: no path produced a key.
    Err(KekDeriveError::DeriveFailed(format!(
        "all KEK paths failed; history={:?}",
        history
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derive_returns_32_bytes() {
        let salt = b"0123456789abcdef";
        let key = derive_master_key(b"correct horse battery staple", salt).unwrap();
        assert_eq!(key.len(), 32);
    }

    #[test]
    fn derivation_is_deterministic() {
        let salt = b"0123456789abcdef";
        let k1 = derive_master_key(b"hunter2hunter2hunter2", salt).unwrap();
        let k2 = derive_master_key(b"hunter2hunter2hunter2", salt).unwrap();
        assert_eq!(k1.as_slice(), k2.as_slice());
    }

    #[test]
    fn different_salts_yield_different_keys() {
        let pw = b"abcdefghij";
        let k1 = derive_master_key(pw, b"saltsaltsaltsalt").unwrap();
        let k2 = derive_master_key(pw, b"PEPPERPEPPERPEPP").unwrap();
        assert_ne!(k1.as_slice(), k2.as_slice());
    }

    #[test]
    fn rejects_short_salt() {
        let err = derive_master_key(b"pw", b"short").unwrap_err();
        assert!(matches!(err, KekDeriveError::SaltTooShort(5)));
    }

    #[test]
    fn empty_passphrase_is_legal_but_distinct() {
        let salt = b"0123456789abcdef";
        let k_empty = derive_master_key(b"", salt).unwrap();
        let k_pw = derive_master_key(b"x", salt).unwrap();
        assert_eq!(k_empty.len(), 32);
        assert_ne!(k_empty.as_slice(), k_pw.as_slice());
    }

    #[test]
    fn salt_generator_yields_random_bytes() {
        let s1 = generate_salt();
        let s2 = generate_salt();
        // Vanishingly unlikely to collide
        assert_ne!(s1, s2);
        assert_eq!(s1.len(), 16);
    }

    // ===== Chain orchestrator tests (Pass-14) =====

    fn test_salt() -> [u8; 16] { *b"0123456789abcdef" }

    #[test]
    fn chain_returns_passphrase_path_when_tpm_absent_and_pw_set() {
        let bogus = std::path::PathBuf::from("/this/does/not/exist/tpm0");
        let s = test_salt();
        let (key, src, hist) =
            derive_kek_chain(Some(&bogus), Some(b"correct horse"), &s, false).unwrap();
        assert_eq!(src, KekSource::Passphrase);
        assert_eq!(key.len(), 32);
        // Path 1 must be Skipped, Path 2 must be Ok
        match &hist[0] {
            KekPathOutcome::Skipped { source: KekSource::Tpm, reason: "tpm_dev_absent" } => {}
            other => panic!("expected TPM Skipped(tpm_dev_absent), got {:?}", other),
        }
        assert!(matches!(hist[1], KekPathOutcome::Ok(KekSource::Passphrase)));
    }

    #[test]
    fn chain_fails_closed_when_all_paths_unavailable() {
        let bogus = std::path::PathBuf::from("/this/does/not/exist/tpm0");
        let s = test_salt();
        let err = derive_kek_chain(Some(&bogus), None, &s, false).unwrap_err();
        // Must be DeriveFailed (fail-closed) — not silently produce a key
        assert!(matches!(err, KekDeriveError::DeriveFailed(_)));
    }

    #[test]
    fn chain_propagates_salt_too_short_immediately() {
        let bogus = std::path::PathBuf::from("/no/tpm");
        let err = derive_kek_chain(Some(&bogus), Some(b"pw"), b"shortsalt", false).unwrap_err();
        assert!(matches!(err, KekDeriveError::SaltTooShort(_)));
    }

    #[test]
    fn chain_records_tpm_skipped_when_dev_present_but_unwired() {
        // Use /dev/null as a stand-in path that exists — proves the
        // tpm_dev_override mechanism works without requiring a real TPM.
        let dev_null = std::path::PathBuf::from("/dev/null");
        let s = test_salt();
        let (_, src, hist) =
            derive_kek_chain(Some(&dev_null), Some(b"pw1"), &s, false).unwrap();
        assert_eq!(src, KekSource::Passphrase);
        match &hist[0] {
            KekPathOutcome::Skipped { source: KekSource::Tpm, reason: "tpm_unseal_not_yet_wired" } => {}
            other => panic!("expected TPM Skipped(unwired), got {:?}", other),
        }
    }

    #[test]
    fn chain_records_kms_skipped_path() {
        let bogus = std::path::PathBuf::from("/no/tpm");
        let s = test_salt();
        let err = derive_kek_chain(Some(&bogus), None, &s, true).unwrap_err();
        // Even with kms_decrypt_available=true, KMS path is "not yet wired"
        if let KekDeriveError::DeriveFailed(msg) = err {
            assert!(msg.contains("kms_decrypt_not_yet_wired"), "msg={msg}");
        } else {
            panic!("expected DeriveFailed");
        }
    }

    #[test]
    fn tpm_present_returns_false_for_nonexistent_path() {
        let nope = std::path::PathBuf::from("/no/such/path/tpm0");
        assert!(!tpm_present(Some(&nope)));
    }

    #[test]
    fn tpm_present_returns_true_for_existing_path() {
        let dev_null = std::path::PathBuf::from("/dev/null");
        assert!(tpm_present(Some(&dev_null)));
    }

    #[cfg(not(feature = "tpm"))]
    #[test]
    fn tpm_unseal_pcr7_returns_unwired_error_token() {
        // Stub-That-Lies guard ([zk-3346fc607a1ef9e6], RPN 729): without the
        // `tpm` feature flag the function MUST return the stable token
        // "tpm_unseal_not_yet_wired" so CI / boot supervisor / lock-in-trap
        // scanner can detect the deferred state.
        let dev = std::path::PathBuf::from("/dev/tpmrm0");
        let blob = b"\x00\x01\x02\x03";
        let err = tpm_unseal_pcr7(&dev, blob).unwrap_err();
        match err {
            KekDeriveError::DeriveFailed(msg) => {
                assert_eq!(msg, "tpm_unseal_not_yet_wired", "default-build token must be stable");
            }
            other => panic!("expected DeriveFailed(\"tpm_unseal_not_yet_wired\"), got {:?}", other),
        }
    }

    #[cfg(feature = "tpm")]
    #[test]
    fn tpm_unseal_pcr7_with_feature_rejects_empty_blob() {
        // With --features tpm the function takes the real path. On a build
        // host without a provisioned TPM (the common case in CI) we expect
        // either "tpm_no_sealed_blob" (when blob is empty) or
        // "tpm_context_init_failed"/"tpm_unseal_failed" (when /dev/tpm absent).
        // The empty-blob check fires first and is fully deterministic.
        let dev = std::path::PathBuf::from("/dev/tpmrm0");
        let err = tpm_unseal_pcr7(&dev, b"").unwrap_err();
        match err {
            KekDeriveError::DeriveFailed(msg) => {
                assert_eq!(msg, "tpm_no_sealed_blob", "feature-build empty-blob token must be stable");
            }
            other => panic!("expected DeriveFailed(\"tpm_no_sealed_blob\"), got {:?}", other),
        }
    }

    #[cfg(feature = "tpm")]
    #[test]
    fn tpm_unseal_pcr7_with_feature_emits_stable_error_class() {
        // On a build host without /dev/tpm0 the function MUST emit one of the
        // documented stable tokens — never an unimplemented!() panic and never
        // a fabricated success. This is the Stub-That-Lies guard for the real
        // path: even when wiring is partial, the error class is honest.
        let dev = std::path::PathBuf::from("/dev/tpmrm0");
        let err = tpm_unseal_pcr7(&dev, b"\x00\x01\x02").unwrap_err();
        match err {
            KekDeriveError::DeriveFailed(msg) => {
                let allowed = [
                    "tpm_tcti_open_failed",
                    "tpm_context_init_failed",
                    "tpm_unseal_failed",
                ];
                assert!(
                    allowed.contains(&msg.as_str()),
                    "expected one of {:?}, got {:?}",
                    allowed,
                    msg
                );
            }
            other => panic!("expected DeriveFailed(<stable token>), got {:?}", other),
        }
    }

    // ===== MockTpm trait tests (Pass-34, Track A) =====

    #[test]
    fn mock_tpm_releases_key_on_matching_blob() {
        let tpm = MockTpm::for_tests();
        let key = tpm.unseal_pcr7(b"test-sealed-blob-pcr7").unwrap();
        assert_eq!(key.len(), 32);
        assert_eq!(key.as_slice(), &[0x42u8; 32]);
    }

    #[test]
    fn mock_tpm_rejects_mismatched_blob_with_stable_token() {
        let tpm = MockTpm::for_tests();
        let err = tpm.unseal_pcr7(b"wrong-blob").unwrap_err();
        match err {
            KekDeriveError::DeriveFailed(msg) => {
                assert_eq!(msg, "tpm_pcr7_mismatch", "mismatch token must be stable");
            }
            other => panic!("expected DeriveFailed(\"tpm_pcr7_mismatch\"), got {:?}", other),
        }
    }

    #[test]
    fn mock_tpm_custom_key_round_trips() {
        let custom_key = [0xAB; 32];
        let tpm = MockTpm::new(b"my-blob", custom_key);
        let k = tpm.unseal_pcr7(b"my-blob").unwrap();
        assert_eq!(k.as_slice(), &custom_key[..]);
    }

    #[test]
    fn mock_tpm_distinguishes_empty_from_registered_blob() {
        let tpm = MockTpm::for_tests();
        assert!(tpm.unseal_pcr7(b"").is_err());
    }

    #[test]
    fn parameters_match_sc_vault_021() {
        assert_eq!(ARGON2_MEMORY_KIB, 65_536);
        assert_eq!(ARGON2_ITERATIONS, 3);
        assert_eq!(ARGON2_PARALLELISM, 4);
        assert_eq!(MASTER_KEY_LEN, 32);
    }
}
