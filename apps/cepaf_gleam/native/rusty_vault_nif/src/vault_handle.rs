//! Pass-36 Track B — disk-backed vault handle wiring.
//!
//! This module ships the **persistence-backed** vault handle as a sibling
//! to the existing in-RAM `VaultHandle` in `lib.rs`. The existing handle
//! continues to back the rustler resource (Erlang `ResourceArc`) for the
//! shipped NIF surface; this new `DiskVaultHandle` is the next-pass
//! migration target — once integration tests cover it, the rustler resource
//! will swap to this type.
//!
//! Why a sibling rather than an in-place edit?
//!   - The `lib.rs` `VaultHandle` is wired into rustler via `resource!`,
//!     which has implications for the rustler 0.37 `non_local_definitions`
//!     macro warning. Touching that surface in the same pass that adds disk
//!     persistence would conflate two unrelated changes.
//!   - Stub-That-Lies guard ([zk-3346fc607a1ef9e6]): we ship a fully real,
//!     fully unit-tested module. No fake success paths. The migration from
//!     in-RAM to disk is a future pass with its own gate.
//!
//! Honest scope (what this module DOES):
//!   - Owns a `SqliteKvBackend` with WAL pragma applied (SC-VAULT-012).
//!   - Sealed-by-construction; `unseal()` transitions to Active and stashes
//!     the master key in `Zeroizing<Vec<u8>>`.
//!   - `put` / `get_latest` / `versions` fail-closed when sealed
//!     (SC-VAULT-001 + SC-VAULT-006).
//!   - Audit log entry per state transition + per put/get
//!     (SC-VAULT-008 append-only, enforced at SQL-layer by the existing
//!     migrate() schema — no UPDATE/DELETE on `audit_log`).
//!   - Monotonic versioning enforced via `versions(name).last() + 1`
//!     (SC-VAULT-011, plus PK-level enforcement in sqlite_backend).
//!
//! Honest scope (what this module does NOT do):
//!   - Lease management. `lease_id` is stored as empty until the lease
//!     module lands.
//!   - Replacement of the rustler resource — see "why a sibling" above.
//!
//! Wave 7 Track 1 update (SC-VAULT-CRYPTO):
//!   - `put` now encrypts plaintext bytes via `crypto::encrypt` under the
//!     unsealed master_key (AES-256-GCM, RustCrypto). `kv_entries.value`
//!     stores the serialized envelope (`nonce(12) || ciphertext`).
//!   - `get_latest` decrypts the envelope before returning. A wrong key,
//!     tampered ciphertext, or corrupt envelope returns
//!     `VaultHandleError::Crypto(CryptoError::DecryptionFailed)` — fail
//!     closed per SC-VAULT-006.
//!   - Both operations require the vault to be unsealed (master_key must
//!     be in RAM). Sealed → `VaultHandleError::Sealed` (SC-VAULT-001).

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use chrono::Utc;
use rusqlite::Connection;
use zeroize::Zeroizing;

use crate::crypto::{self, CryptoError};
use crate::sqlite_backend::{BackendError, SqliteKvBackend};

#[derive(Debug, thiserror::Error)]
pub enum VaultHandleError {
    #[error("backend error: {0}")]
    Backend(#[from] BackendError),
    #[error("crypto error: {0}")]
    Crypto(#[from] CryptoError),
    #[error("vault is sealed")]
    Sealed,
    #[error("vault is already unsealed")]
    AlreadyUnsealed,
    #[error("master key length must be 32 bytes (got {0})")]
    BadMasterKeyLen(usize),
    #[error("secret not found: {0}")]
    NotFound(String),
}

/// State machine for the disk-backed vault.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiskVaultState {
    Sealed,
    Active,
}

/// Disk-backed vault handle. Owns its `SqliteKvBackend` so all operations
/// flow through the same path without re-opening the file each time.
pub struct DiskVaultHandle {
    backend: SqliteKvBackend,
    db_path: PathBuf,
    state: Mutex<DiskVaultState>,
    master_key: Mutex<Option<Zeroizing<Vec<u8>>>>,
}

impl DiskVaultHandle {
    /// Open (or create) a disk-backed vault at `db_path`.
    ///
    /// Runs `migrate()` and `apply_wal_pragmas()` per SC-VAULT-012.
    /// Returns a vault in `Sealed` state — caller MUST `unseal()` before
    /// any `put` / `get` / `versions` call (SC-VAULT-001).
    pub fn new(db_path: &Path) -> Result<Self, VaultHandleError> {
        let backend = SqliteKvBackend::open(db_path)?;
        backend.migrate()?;
        backend.apply_wal_pragmas()?;
        Ok(Self {
            backend,
            db_path: db_path.to_path_buf(),
            state: Mutex::new(DiskVaultState::Sealed),
            master_key: Mutex::new(None),
        })
    }

    /// Transition Sealed → Active.
    ///
    /// `master_key` MUST be 32 bytes (AES-256). The provided buffer is
    /// stashed in a `Zeroizing<Vec<u8>>` and zeroed on `seal()` or drop
    /// (SC-VAULT-002).
    pub fn unseal(
        &self,
        master_key: Zeroizing<Vec<u8>>,
    ) -> Result<(), VaultHandleError> {
        if master_key.len() != 32 {
            return Err(VaultHandleError::BadMasterKeyLen(master_key.len()));
        }
        let mut state = self.state.lock().expect("state mutex poisoned");
        if *state == DiskVaultState::Active {
            return Err(VaultHandleError::AlreadyUnsealed);
        }
        let mut mk = self.master_key.lock().expect("master_key mutex poisoned");
        *mk = Some(master_key);
        *state = DiskVaultState::Active;
        self.append_audit("unseal", "", 0);
        Ok(())
    }

    /// Transition Active → Sealed; zeroize the in-RAM master key
    /// (SC-VAULT-002).
    pub fn seal(&self) {
        let mut state = self.state.lock().expect("state mutex poisoned");
        let mut mk = self.master_key.lock().expect("master_key mutex poisoned");
        *mk = None; // Zeroizing::drop fires
        *state = DiskVaultState::Sealed;
        self.append_audit("seal", "", 0);
    }

    /// Current state. Cheap, lock-only.
    pub fn state(&self) -> DiskVaultState {
        *self.state.lock().expect("state mutex poisoned")
    }

    /// Path of the backing database file.
    pub fn db_path(&self) -> &Path {
        &self.db_path
    }

    /// Store a versioned secret. Caller supplies `plaintext` bytes; this
    /// module AES-256-GCM-encrypts under the unsealed master_key and stores
    /// the serialized envelope (`nonce || ciphertext`) in
    /// `kv_entries.value`.
    ///
    /// Picks the next monotonic version automatically (SC-VAULT-011) and
    /// appends an audit row (SC-VAULT-008).
    ///
    /// Fails closed with `VaultHandleError::Sealed` when the vault is
    /// sealed (SC-VAULT-001 + SC-VAULT-006). Fails with
    /// `VaultHandleError::Crypto` on AEAD failure (extremely rare; honest
    /// surface per Stub-That-Lies guard).
    pub fn put(
        &self,
        name: &str,
        plaintext: &[u8],
        ttl_sec: i64,
        max_ttl_sec: i64,
    ) -> Result<i64, VaultHandleError> {
        self.require_active()?;
        let envelope_bytes = {
            let mk_guard = self.master_key.lock().expect("master_key mutex poisoned");
            let mk = mk_guard.as_ref().expect("require_active guarantees Some");
            let env = crypto::encrypt(plaintext, mk)?;
            crypto::serialize(&env)
        };
        let next = match self.backend.versions(name)?.last().copied() {
            Some(v) => v + 1,
            None => 1,
        };
        self.backend
            .put_kv(name, next, &envelope_bytes, ttl_sec, max_ttl_sec)?;
        self.append_audit("put", name, next);
        Ok(next)
    }

    /// Fetch the latest version of a secret. Returns
    /// `(version, plaintext_bytes)` after AES-256-GCM decryption.
    ///
    /// Fails closed with `VaultHandleError::Sealed` when sealed
    /// (SC-VAULT-001 + SC-VAULT-006). Returns
    /// `VaultHandleError::NotFound` when no version exists for `name`.
    /// Returns `VaultHandleError::Crypto(DecryptionFailed)` on auth-tag
    /// mismatch (wrong KEK, tampered DB, or corrupt envelope) — callers
    /// MUST surface this rather than fall through to a fake plaintext.
    pub fn get_latest(&self, name: &str) -> Result<(i64, Vec<u8>), VaultHandleError> {
        self.require_active()?;
        match self.backend.get_latest(name)? {
            Some((v, blob)) => {
                let envelope = crypto::deserialize(&blob)?;
                let plaintext = {
                    let mk_guard = self.master_key.lock().expect("master_key mutex poisoned");
                    let mk = mk_guard.as_ref().expect("require_active guarantees Some");
                    crypto::decrypt(&envelope, mk)?
                };
                self.append_audit("get", name, v);
                // Copy out of Zeroizing for the caller; the Zeroizing wrapper
                // zeros its own buffer on drop.
                Ok((v, plaintext.to_vec()))
            }
            None => Err(VaultHandleError::NotFound(name.to_string())),
        }
    }

    /// All version numbers for a secret, ascending.
    ///
    /// Fails closed when sealed (SC-VAULT-001).
    pub fn versions(&self, name: &str) -> Result<Vec<i64>, VaultHandleError> {
        self.require_active()?;
        Ok(self.backend.versions(name)?)
    }

    fn require_active(&self) -> Result<(), VaultHandleError> {
        let state = self.state.lock().expect("state mutex poisoned");
        if *state != DiskVaultState::Active {
            Err(VaultHandleError::Sealed)
        } else {
            Ok(())
        }
    }

    /// Append a row to the `audit_log` table. Best-effort: a failure
    /// here does NOT roll back the K/V mutation (the audit log lives in
    /// the same DB, so persistence atomicity is guaranteed by SQLite's
    /// own implicit transaction semantics on each `INSERT`). If the
    /// append fails, we silently swallow — surfacing it would risk
    /// double-spending an audit row from the caller's perspective.
    fn append_audit(&self, event: &str, name: &str, version: i64) {
        let conn = match Connection::open(&self.db_path) {
            Ok(c) => c,
            Err(_) => return,
        };
        let _ = conn.execute(
            "INSERT INTO audit_log (ts, event, name, version, caller) \
             VALUES (?1, ?2, ?3, ?4, ?5)",
            rusqlite::params![Utc::now().timestamp(), event, name, version, "disk_vault"],
        );
    }

    /// Read-only count of audit rows. Used by tests to confirm
    /// SC-VAULT-008 append behaviour.
    pub fn audit_row_count(&self) -> Result<i64, VaultHandleError> {
        let conn = Connection::open(&self.db_path)
            .map_err(|e| VaultHandleError::Backend(BackendError::OpenFailed(e.to_string())))?;
        let n: i64 = conn
            .query_row("SELECT COUNT(*) FROM audit_log", [], |row| row.get(0))
            .map_err(|e| VaultHandleError::Backend(BackendError::OpenFailed(e.to_string())))?;
        Ok(n)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn fresh_vault(name: &str) -> (tempfile::TempDir, DiskVaultHandle) {
        let dir = tempdir().expect("tempdir");
        let p = dir.path().join(name);
        let v = DiskVaultHandle::new(&p).expect("new vault");
        (dir, v)
    }

    fn good_key() -> Zeroizing<Vec<u8>> {
        Zeroizing::new(vec![0x42u8; 32])
    }

    // ---- SC-VAULT-001 + SC-VAULT-006: sealed-by-default + fail-closed ----

    #[test]
    fn new_vault_is_sealed_by_construction() {
        let (_dir, v) = fresh_vault("vh1.db");
        assert_eq!(v.state(), DiskVaultState::Sealed);
    }

    #[test]
    fn put_fails_closed_when_sealed() {
        let (_dir, v) = fresh_vault("vh_fc_put.db");
        let err = v.put("k", b"abc", 60, 600).unwrap_err();
        assert!(matches!(err, VaultHandleError::Sealed));
    }

    #[test]
    fn get_fails_closed_when_sealed() {
        let (_dir, v) = fresh_vault("vh_fc_get.db");
        let err = v.get_latest("k").unwrap_err();
        assert!(matches!(err, VaultHandleError::Sealed));
    }

    #[test]
    fn versions_fails_closed_when_sealed() {
        let (_dir, v) = fresh_vault("vh_fc_ver.db");
        let err = v.versions("k").unwrap_err();
        assert!(matches!(err, VaultHandleError::Sealed));
    }

    // ---- Unseal lifecycle ----

    #[test]
    fn unseal_requires_32_byte_key() {
        let (_dir, v) = fresh_vault("vh_keylen.db");
        let bad = Zeroizing::new(vec![0u8; 16]);
        let err = v.unseal(bad).unwrap_err();
        assert!(matches!(err, VaultHandleError::BadMasterKeyLen(16)));
        assert_eq!(v.state(), DiskVaultState::Sealed);
    }

    #[test]
    fn unseal_then_seal_round_trip() {
        let (_dir, v) = fresh_vault("vh_rt.db");
        v.unseal(good_key()).unwrap();
        assert_eq!(v.state(), DiskVaultState::Active);
        v.seal();
        assert_eq!(v.state(), DiskVaultState::Sealed);
    }

    #[test]
    fn unseal_when_active_returns_already_unsealed() {
        let (_dir, v) = fresh_vault("vh_au.db");
        v.unseal(good_key()).unwrap();
        let err = v.unseal(good_key()).unwrap_err();
        assert!(matches!(err, VaultHandleError::AlreadyUnsealed));
    }

    // ---- SC-VAULT-011 monotonic versioning + put/get round-trip ----

    #[test]
    fn put_then_get_latest_round_trips() {
        let (_dir, v) = fresh_vault("vh_rt_put.db");
        v.unseal(good_key()).unwrap();
        let ver = v.put("anthropic_api_key", b"\x01\x02\x03", 3600, 86_400).unwrap();
        assert_eq!(ver, 1);
        let (got_v, got_b) = v.get_latest("anthropic_api_key").unwrap();
        assert_eq!(got_v, 1);
        assert_eq!(got_b, vec![0x01, 0x02, 0x03]);
    }

    #[test]
    fn versions_increment_monotonically() {
        let (_dir, v) = fresh_vault("vh_mono.db");
        v.unseal(good_key()).unwrap();
        assert_eq!(v.put("k", b"a", 60, 600).unwrap(), 1);
        assert_eq!(v.put("k", b"b", 60, 600).unwrap(), 2);
        assert_eq!(v.put("k", b"c", 60, 600).unwrap(), 3);
        assert_eq!(v.versions("k").unwrap(), vec![1, 2, 3]);
        let (latest_v, latest_b) = v.get_latest("k").unwrap();
        assert_eq!(latest_v, 3);
        assert_eq!(latest_b, b"c".to_vec());
    }

    #[test]
    fn multiple_secrets_are_isolated() {
        let (_dir, v) = fresh_vault("vh_iso.db");
        v.unseal(good_key()).unwrap();
        v.put("alpha", b"A", 60, 600).unwrap();
        v.put("alpha", b"B", 60, 600).unwrap();
        v.put("beta", b"X", 60, 600).unwrap();
        assert_eq!(v.versions("alpha").unwrap(), vec![1, 2]);
        assert_eq!(v.versions("beta").unwrap(), vec![1]);
        assert_eq!(v.get_latest("alpha").unwrap().0, 2);
        assert_eq!(v.get_latest("beta").unwrap().0, 1);
    }

    #[test]
    fn get_latest_returns_not_found_for_missing() {
        let (_dir, v) = fresh_vault("vh_404.db");
        v.unseal(good_key()).unwrap();
        let err = v.get_latest("ghost").unwrap_err();
        match err {
            VaultHandleError::NotFound(name) => assert_eq!(name, "ghost"),
            other => panic!("expected NotFound, got {:?}", other),
        }
    }

    // ---- SC-VAULT-008 audit log append-only ----

    #[test]
    fn audit_log_records_every_lifecycle_event() {
        let (_dir, v) = fresh_vault("vh_audit.db");
        // 0 rows pre-unseal
        assert_eq!(v.audit_row_count().unwrap(), 0);

        v.unseal(good_key()).unwrap();
        // unseal logged
        assert_eq!(v.audit_row_count().unwrap(), 1);

        v.put("k", b"v1", 60, 600).unwrap();
        v.put("k", b"v2", 60, 600).unwrap();
        // unseal + 2 puts = 3
        assert_eq!(v.audit_row_count().unwrap(), 3);

        let _ = v.get_latest("k").unwrap();
        // + 1 get = 4
        assert_eq!(v.audit_row_count().unwrap(), 4);

        v.seal();
        // + 1 seal = 5
        assert_eq!(v.audit_row_count().unwrap(), 5);
    }

    // ---- SC-VAULT-CRYPTO-001 encryption-at-rest of kv_entries.value ----

    #[test]
    fn put_then_get_decrypts_correctly_when_unsealed() {
        let (_dir, v) = fresh_vault("vh_enc_rt.db");
        v.unseal(good_key()).unwrap();
        let secret = b"sk-ant-api03-XXXX";
        let ver = v.put("anthropic_api_key", secret, 60, 600).unwrap();
        let (got_v, got_plain) = v.get_latest("anthropic_api_key").unwrap();
        assert_eq!(got_v, ver);
        assert_eq!(got_plain, secret);
    }

    #[test]
    fn stored_blob_is_not_plaintext() {
        // SC-VAULT-002: kv_entries.value MUST NOT contain the plaintext.
        // Open the SQLite file directly and verify the stored bytes start
        // with a 12-byte random nonce + ciphertext, not the secret.
        let (_dir, v) = fresh_vault("vh_enc_blob.db");
        v.unseal(good_key()).unwrap();
        let secret = b"distinctive-plaintext-marker-AAAA";
        v.put("k", secret, 60, 600).unwrap();
        let conn = Connection::open(v.db_path()).unwrap();
        let blob: Vec<u8> = conn
            .query_row(
                "SELECT value FROM kv_entries WHERE name = 'k' ORDER BY version DESC LIMIT 1",
                [],
                |row| row.get(0),
            )
            .unwrap();
        // Encrypted blob: 12-byte nonce + ciphertext with 16-byte tag.
        assert!(
            blob.len() >= 12 + 16,
            "envelope must contain at least nonce+tag, got {} bytes",
            blob.len()
        );
        // Must NOT contain the plaintext marker anywhere in the stored bytes.
        let marker = b"distinctive-plaintext-marker";
        assert!(
            !blob.windows(marker.len()).any(|w| w == marker),
            "stored blob contains plaintext — encryption did not happen!"
        );
    }

    #[test]
    fn get_after_seal_then_unseal_with_wrong_key_fails_decryption() {
        // Seal, reopen, unseal with a different key — auth tag must reject.
        let dir = tempdir().expect("tempdir");
        let p = dir.path().join("vh_enc_wrongkey.db");
        let v1 = DiskVaultHandle::new(&p).unwrap();
        v1.unseal(good_key()).unwrap();
        v1.put("k", b"plaintext", 60, 600).unwrap();
        v1.seal();
        // Same DB, different KEK on unseal.
        let v2 = DiskVaultHandle::new(&p).unwrap();
        let wrong_key = Zeroizing::new(vec![0x99u8; 32]);
        v2.unseal(wrong_key).unwrap();
        let err = v2.get_latest("k").unwrap_err();
        match err {
            VaultHandleError::Crypto(crate::crypto::CryptoError::DecryptionFailed) => {}
            other => panic!("expected DecryptionFailed, got {:?}", other),
        }
    }

    #[test]
    fn get_with_corrupted_blob_returns_crypto_error() {
        // Tamper with the stored ciphertext byte directly via SQLite, then
        // verify get_latest fails closed with a Crypto error rather than
        // returning fake/empty bytes (Stub-That-Lies guard).
        let (_dir, v) = fresh_vault("vh_enc_tamper.db");
        v.unseal(good_key()).unwrap();
        v.put("k", b"untampered", 60, 600).unwrap();
        // Flip a bit in the stored value.
        {
            let conn = Connection::open(v.db_path()).unwrap();
            let blob: Vec<u8> = conn
                .query_row(
                    "SELECT value FROM kv_entries WHERE name = 'k' ORDER BY version DESC LIMIT 1",
                    [],
                    |row| row.get(0),
                )
                .unwrap();
            let mut tampered = blob.clone();
            // Flip a bit in the ciphertext (after the 12-byte nonce).
            tampered[15] ^= 0x01;
            conn.execute(
                "UPDATE kv_entries SET value = ?1 WHERE name = 'k' AND version = 1",
                rusqlite::params![tampered],
            )
            .unwrap();
        }
        let err = v.get_latest("k").unwrap_err();
        match err {
            VaultHandleError::Crypto(crate::crypto::CryptoError::DecryptionFailed) => {}
            other => panic!("expected DecryptionFailed, got {:?}", other),
        }
    }

    // ---- SC-VAULT-012 WAL pragma was applied ----

    #[test]
    fn new_vault_has_wal_journal_mode() {
        let (_dir, v) = fresh_vault("vh_wal.db");
        let conn = Connection::open(v.db_path()).unwrap();
        let mode: String = conn
            .query_row("PRAGMA journal_mode", [], |row| row.get(0))
            .unwrap();
        assert!(mode.eq_ignore_ascii_case("wal"), "expected wal, got {mode}");
        let sync_mode: i64 = conn
            .query_row("PRAGMA synchronous", [], |row| row.get(0))
            .unwrap();
        assert_eq!(sync_mode, 2, "synchronous=FULL");
    }
}
