//! crypto — AES-256-GCM authenticated encryption envelope for kv_entries.value.
//!
//! Wave 7 Track 1 (task 116494073339521648).
//!
//! ## Scope
//!
//! Provides authenticated encryption (confidentiality + integrity) of secret
//! plaintext bytes using AES-256-GCM (NIST SP 800-38D). The wire envelope is:
//!
//! ```text
//! envelope = nonce(12 bytes) || ciphertext(N bytes, includes 16-byte auth tag)
//! ```
//!
//! `aes-gcm` (RustCrypto) embeds the 16-byte authentication tag at the tail of
//! the ciphertext output. Decryption verifies the tag and rejects tampered or
//! truncated inputs with `DecryptionFailed` / `MalformedEnvelope`.
//!
//! ## STAMP
//!
//! - **SC-VAULT-002** — KEK never plaintext on disk. The KEK lives only inside
//!   `Zeroizing<Vec<u8>>` and is zeroed on drop. This module never persists the
//!   KEK; callers pass it by reference for each encrypt/decrypt.
//! - **SC-VAULT-CRYPTO-001** — Western crypto only. `aes-gcm` is RustCrypto,
//!   audited, no Tongsuo. The CI gate `cargo tree | grep -iE 'tongsuo|sm[234]'`
//!   MUST remain empty.
//! - **SC-VAULT-006** — Fail-closed on tag mismatch. A tampered ciphertext or
//!   wrong KEK returns `DecryptionFailed`. Callers MUST surface the error
//!   rather than fall through to a fake plaintext (Stub-That-Lies guard,
//!   [zk-3346fc607a1ef9e6]).
//!
//! ## Design notes
//!
//! - **Nonce**: 12 bytes (96 bits, AES-GCM standard). Generated via OS RNG
//!   per encrypt — assert in `nonce_is_random_per_encrypt` test.
//! - **Key length**: 32 bytes (AES-256). Shorter keys → `InvalidKekLength`.
//! - **Plaintext bound**: `aes-gcm` bounds plaintext at 2^36 - 32 bytes; we do
//!   not enforce a smaller bound here because secret values are kilobyte-scale.
//! - **Empty plaintext**: explicitly tested — encrypts and decrypts to zero
//!   bytes (auth tag still validates the empty payload).
//!
//! ## Wire format compatibility
//!
//! `serialize` / `deserialize` use a simple `nonce || ciphertext` byte
//! concatenation. There is NO version byte; future format changes (e.g.
//! AES-GCM-SIV migration) MUST add a leading version byte and bump
//! `MalformedEnvelope` parsing accordingly. Today the format is implicit
//! version 1.

use aes_gcm::aead::{Aead, AeadCore, KeyInit, OsRng};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use thiserror::Error;
use zeroize::Zeroizing;

/// Length of the GCM nonce in bytes (96 bits, NIST SP 800-38D recommended).
pub const NONCE_LEN: usize = 12;

/// Length of the AES-256 key in bytes.
pub const KEK_LEN: usize = 32;

/// Length of the GCM authentication tag in bytes (embedded at ciphertext tail).
pub const TAG_LEN: usize = 16;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum CryptoError {
    /// KEK was not exactly 32 bytes (AES-256 requires a 256-bit key).
    #[error("kek length must be 32 bytes (got {0})")]
    InvalidKekLength(usize),

    /// `Aead::encrypt` returned an internal error. Should be unreachable on
    /// well-formed inputs but propagated honestly per Stub-That-Lies guard.
    #[error("encryption failed: {0}")]
    EncryptionFailed(String),

    /// Decryption failed. Either wrong KEK, tampered ciphertext, or tampered
    /// nonce. The `aes-gcm` crate intentionally does not distinguish these
    /// cases (timing-safe). Callers MUST treat this as fail-closed.
    #[error("decryption failed (auth tag mismatch or wrong key)")]
    DecryptionFailed,

    /// Serialized envelope is shorter than `NONCE_LEN + TAG_LEN`, or otherwise
    /// structurally invalid before decryption is even attempted.
    #[error("malformed envelope: {0}")]
    MalformedEnvelope(String),
}

/// In-memory representation of an encrypted secret.
///
/// Store as `serialize(&envelope)` bytes in `kv_entries.value`. Reconstruct via
/// `deserialize(bytes)` before decrypting.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EncryptionEnvelope {
    /// Random per-encrypt nonce. Never reused with the same KEK (GCM
    /// catastrophically loses confidentiality on nonce reuse — OsRng provides
    /// 96 bits of entropy per call, collision probability negligible for the
    /// vault's secret cardinality).
    pub nonce: [u8; NONCE_LEN],

    /// Ciphertext with embedded 16-byte auth tag (aes-gcm convention).
    pub ciphertext: Vec<u8>,
}

/// Encrypt `plaintext` under `kek`. Returns a fresh envelope with a random
/// nonce.
///
/// # Errors
/// - `InvalidKekLength` if `kek.len() != 32`
/// - `EncryptionFailed` on AEAD internal failure (should be unreachable)
pub fn encrypt(
    plaintext: &[u8],
    kek: &Zeroizing<Vec<u8>>,
) -> Result<EncryptionEnvelope, CryptoError> {
    if kek.len() != KEK_LEN {
        return Err(CryptoError::InvalidKekLength(kek.len()));
    }
    let key = Key::<Aes256Gcm>::from_slice(kek.as_slice());
    let cipher = Aes256Gcm::new(key);
    let nonce_bytes = Aes256Gcm::generate_nonce(&mut OsRng);
    let ciphertext = cipher
        .encrypt(&nonce_bytes, plaintext)
        .map_err(|e| CryptoError::EncryptionFailed(format!("{:?}", e)))?;
    let mut nonce = [0u8; NONCE_LEN];
    nonce.copy_from_slice(nonce_bytes.as_slice());
    Ok(EncryptionEnvelope { nonce, ciphertext })
}

/// Decrypt `envelope` under `kek`. Returns the plaintext wrapped in
/// `Zeroizing` so it zeros on drop.
///
/// # Errors
/// - `InvalidKekLength` if `kek.len() != 32`
/// - `DecryptionFailed` if the auth tag does not validate (tampered ciphertext
///   or wrong KEK — `aes-gcm` deliberately does not distinguish these cases)
pub fn decrypt(
    envelope: &EncryptionEnvelope,
    kek: &Zeroizing<Vec<u8>>,
) -> Result<Zeroizing<Vec<u8>>, CryptoError> {
    if kek.len() != KEK_LEN {
        return Err(CryptoError::InvalidKekLength(kek.len()));
    }
    let key = Key::<Aes256Gcm>::from_slice(kek.as_slice());
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(&envelope.nonce);
    let plaintext = cipher
        .decrypt(nonce, envelope.ciphertext.as_ref())
        .map_err(|_| CryptoError::DecryptionFailed)?;
    Ok(Zeroizing::new(plaintext))
}

/// Serialize an envelope to wire bytes: `nonce(12) || ciphertext`.
///
/// Total length is `NONCE_LEN + envelope.ciphertext.len()`.
pub fn serialize(env: &EncryptionEnvelope) -> Vec<u8> {
    let mut out = Vec::with_capacity(NONCE_LEN + env.ciphertext.len());
    out.extend_from_slice(&env.nonce);
    out.extend_from_slice(&env.ciphertext);
    out
}

/// Parse wire bytes back into an envelope.
///
/// # Errors
/// - `MalformedEnvelope` if `bytes.len() < NONCE_LEN + TAG_LEN` (cannot contain
///   even an empty plaintext + tag).
pub fn deserialize(bytes: &[u8]) -> Result<EncryptionEnvelope, CryptoError> {
    if bytes.len() < NONCE_LEN + TAG_LEN {
        return Err(CryptoError::MalformedEnvelope(format!(
            "envelope too short: {} bytes (need at least {})",
            bytes.len(),
            NONCE_LEN + TAG_LEN
        )));
    }
    let mut nonce = [0u8; NONCE_LEN];
    nonce.copy_from_slice(&bytes[..NONCE_LEN]);
    let ciphertext = bytes[NONCE_LEN..].to_vec();
    Ok(EncryptionEnvelope { nonce, ciphertext })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn good_kek() -> Zeroizing<Vec<u8>> {
        Zeroizing::new(vec![0x42u8; KEK_LEN])
    }

    fn other_kek() -> Zeroizing<Vec<u8>> {
        Zeroizing::new(vec![0x99u8; KEK_LEN])
    }

    #[test]
    fn encrypt_then_decrypt_roundtrip() {
        let kek = good_kek();
        let plaintext = b"synthetic-secret-token-value-12345";
        let env = encrypt(plaintext, &kek).expect("encrypt ok");
        let dec = decrypt(&env, &kek).expect("decrypt ok");
        assert_eq!(dec.as_slice(), plaintext);
    }

    #[test]
    fn decrypt_with_wrong_kek_fails_auth() {
        let plaintext = b"super-secret";
        let env = encrypt(plaintext, &good_kek()).expect("encrypt ok");
        let err = decrypt(&env, &other_kek()).expect_err("must fail");
        assert_eq!(err, CryptoError::DecryptionFailed);
    }

    #[test]
    fn decrypt_tampered_ciphertext_fails_auth() {
        let kek = good_kek();
        let mut env = encrypt(b"untampered", &kek).expect("encrypt ok");
        // Flip a bit in the ciphertext middle (not in the tag) — GCM detects.
        env.ciphertext[0] ^= 0x01;
        let err = decrypt(&env, &kek).expect_err("must fail");
        assert_eq!(err, CryptoError::DecryptionFailed);
    }

    #[test]
    fn decrypt_truncated_envelope_returns_malformed() {
        // Less than NONCE_LEN + TAG_LEN = 28 bytes — cannot deserialize.
        let too_short = vec![0u8; 10];
        let err = deserialize(&too_short).expect_err("must fail");
        match err {
            CryptoError::MalformedEnvelope(_) => {}
            other => panic!("expected MalformedEnvelope, got {:?}", other),
        }
    }

    #[test]
    fn serialize_deserialize_roundtrip() {
        let kek = good_kek();
        let env = encrypt(b"payload", &kek).expect("encrypt ok");
        let bytes = serialize(&env);
        let env2 = deserialize(&bytes).expect("deserialize ok");
        assert_eq!(env, env2);
        let dec = decrypt(&env2, &kek).expect("decrypt ok");
        assert_eq!(dec.as_slice(), b"payload");
    }

    #[test]
    fn encrypt_with_short_kek_returns_invalid_length() {
        let short = Zeroizing::new(vec![0u8; 16]); // 128-bit, not 256-bit
        let err = encrypt(b"x", &short).expect_err("must fail");
        assert_eq!(err, CryptoError::InvalidKekLength(16));
    }

    #[test]
    fn nonce_is_random_per_encrypt() {
        let kek = good_kek();
        let e1 = encrypt(b"same plaintext", &kek).expect("encrypt 1");
        let e2 = encrypt(b"same plaintext", &kek).expect("encrypt 2");
        assert_ne!(
            e1.nonce, e2.nonce,
            "nonces MUST be random per encrypt (GCM catastrophic on reuse)"
        );
        // Both decrypt back to the same plaintext.
        assert_eq!(
            decrypt(&e1, &kek).expect("d1").as_slice(),
            decrypt(&e2, &kek).expect("d2").as_slice()
        );
    }

    #[test]
    fn empty_plaintext_encrypts_and_decrypts() {
        let kek = good_kek();
        let env = encrypt(b"", &kek).expect("encrypt empty");
        // ciphertext should still contain the 16-byte auth tag.
        assert_eq!(env.ciphertext.len(), TAG_LEN);
        let dec = decrypt(&env, &kek).expect("decrypt empty");
        assert!(dec.is_empty());
    }
}
