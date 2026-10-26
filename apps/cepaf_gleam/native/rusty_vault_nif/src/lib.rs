//! rusty_vault_nif — Sealed K/V vault NIF for cepaf_gleam.
//!
//! This crate exposes 10 vault NIFs plus 3 KEK-chain NIFs implementing the
//! Vault contract specified by `.claude/rules/secrets-vault.md`
//! (SC-VAULT-001..025 + SC-VAULT-CRYPTO-001).
//!
//! # Critical invariants
//!
//! - SC-VAULT-001: Vault MUST be sealed at process start
//! - SC-VAULT-002: KEK MUST never be persisted in plaintext
//! - SC-VAULT-005: Hot path MUST NOT make network calls
//! - SC-VAULT-006: reads fail closed (sealed, stale, undecryptable)
//! - SC-VAULT-008: the audit log is append-only (SQL triggers refuse
//!   UPDATE and DELETE)
//! - SC-VAULT-011: versions are monotonic per name (composite primary key)
//! - SC-VAULT-012: WAL journal, synchronous=FULL
//! - SC-VAULT-CRYPTO-001: NO Tongsuo / SM2/SM3/SM4 in dependency tree
//!
//! Verification gate (CI):
//! ```bash
//! cargo tree | grep -iE 'tongsuo|sm[234]'
//! # MUST be empty
//! ```
//!
//! # VF-01 closure (2026-10-26)
//!
//! Until this revision the NIF resource kept its key-value store and audit
//! log in RAM and `vault_unseal` accepted any 32-byte key (a documented
//! TODO). The resource now owns the disk-backed handle
//! (`vault_handle::DiskVaultHandle` over `sqlite_backend::SqliteKvBackend`):
//! every secret is stored as an AES-256-GCM envelope under the unsealed
//! master key, the audit trail is a table with append-only triggers, and the
//! first unseal of a vault writes an encrypted verifier row that every later
//! unseal must decrypt, so a wrong key is refused and the vault stays sealed.
//! Nothing is cached in the handle beyond the master key, so a fresh handle
//! (or a fresh BEAM) on the same file reads what an earlier one wrote.
//!
//! # NIF surface (10 vault functions)
//!
//! 1. `vault_init/2`  — open or create the sqlite file; always sealed
//! 2. `vault_unseal/2` — sealed → active after the verifier row decrypts
//! 3. `vault_seal/1` — active → sealed (zeroizes master in RAM)
//! 4. `vault_status/1` — query state
//! 5. `vault_kv_put/5` — write secret + policy
//! 6. `vault_kv_get/2` — read latest version
//! 7. `vault_kv_versions/2` — version metadata
//! 8. `vault_kv_destroy/3` — hard-delete a version
//! 9. `vault_lease_renew/3` — extend a lease
//! 10. `vault_audit_tail/2` — read audit events for register sync
//!
//! All vault NIFs are dirty-IO scheduled (the storage layer blocks on disk).

use rustler::{Atom, Binary, Encoder, Env, NifResult, OwnedBinary, ResourceArc, Term};
use std::path::{Path, PathBuf};
use std::sync::RwLock;
use zeroize::Zeroizing;

pub mod crypto;
pub mod kek_chain;
pub mod sqlite_backend;
pub mod vault_handle;

use crypto::CryptoError;
use vault_handle::{DiskVaultHandle, VaultHandleError};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        sealed,
        active,
        unsealing,
        sealing,
        corrupt,
        halted,
        wrong_key,
        not_found,
        ttl_expired,
        storage_error,
        already_unsealed,
        decrypt_failed,
        invalid_name,
        nif_panic,
        version,
        lease_id,
        ts,
        name,
        caller,
        storage,
    }
}

// =====================================================================
// VaultHandle — process-wide resource owning the disk-backed vault
// =====================================================================

/// Default file name when `storage_path` names a directory.
pub const DEFAULT_DB_FILE: &str = "vault.sqlite3";

/// State of a vault handle as reported to the BEAM.
pub struct VaultHandle {
    /// The sqlite file actually opened.
    storage_path: PathBuf,
    /// Recorded for status; the audit trail lives in the sqlite file.
    audit_path: PathBuf,
    /// State machine: Sealed | Unsealing | Active | Sealing | Corrupt | Halted
    state: RwLock<VaultState>,
    /// The disk-backed vault: sqlite rows, AES-256-GCM envelopes, the
    /// in-RAM master key (zeroized on seal) and the verifier row.
    disk: DiskVaultHandle,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VaultState {
    Sealed,
    Unsealing,
    Active,
    Sealing,
    Corrupt,
    Halted,
}

impl VaultState {
    fn to_atom(&self) -> Atom {
        match self {
            VaultState::Sealed => atoms::sealed(),
            VaultState::Unsealing => atoms::unsealing(),
            VaultState::Active => atoms::active(),
            VaultState::Sealing => atoms::sealing(),
            VaultState::Corrupt => atoms::corrupt(),
            VaultState::Halted => atoms::halted(),
        }
    }
}

/// A `storage_path` that names an existing directory, or ends in a path
/// separator, resolves to `<dir>/vault.sqlite3`; anything else is the file.
pub fn resolve_db_path(storage_path: &str) -> PathBuf {
    let p = Path::new(storage_path);
    if p.is_dir() || storage_path.ends_with('/') {
        p.join(DEFAULT_DB_FILE)
    } else {
        p.to_path_buf()
    }
}

/// Longest secret name accepted.
pub const MAX_NAME_BYTES: usize = 512;

/// A secret name is non-empty, at most `MAX_NAME_BYTES` bytes, and carries
/// no control byte (0x00..0x1f, 0x7f). Checked before any disk access
/// (VAULT_NIF_REVIEW hostile inputs 7 and 8).
pub fn valid_name(name: &str) -> bool {
    !name.is_empty() && name.len() <= MAX_NAME_BYTES && !name.bytes().any(|b| b < 0x20 || b == 0x7f)
}

impl VaultHandle {
    /// Open or create the vault file. Returns a sealed handle, or the
    /// backend error when the file cannot be opened or migrated.
    pub fn open(storage_path: &str, audit_path: &str) -> Result<Self, VaultHandleError> {
        let db = resolve_db_path(storage_path);
        if let Some(parent) = db.parent() {
            if !parent.as_os_str().is_empty() {
                // Best effort: a missing parent surfaces as the open error below.
                let _ = std::fs::create_dir_all(parent);
            }
        }
        let disk = DiskVaultHandle::new(&db)?;
        Ok(Self {
            storage_path: db,
            audit_path: PathBuf::from(audit_path),
            state: RwLock::new(VaultState::Sealed),
            disk,
        })
    }

    fn set_state(&self, s: VaultState) {
        if let Ok(mut st) = self.state.write() {
            *st = s;
        }
    }

    fn state(&self) -> VaultState {
        self.state.read().map(|s| s.clone()).unwrap_or(VaultState::Halted)
    }

    fn is_active(&self) -> bool {
        self.state() == VaultState::Active
    }
}

/// Map a disk-handle error to the atom the BEAM contract names.
fn error_atom(e: &VaultHandleError) -> Atom {
    match e {
        VaultHandleError::Sealed => atoms::sealed(),
        VaultHandleError::AlreadyUnsealed => atoms::already_unsealed(),
        VaultHandleError::BadMasterKeyLen(_) => atoms::wrong_key(),
        VaultHandleError::WrongKey => atoms::wrong_key(),
        VaultHandleError::NotFound(_) => atoms::not_found(),
        VaultHandleError::Crypto(CryptoError::DecryptionFailed) => atoms::decrypt_failed(),
        VaultHandleError::Crypto(_) => atoms::storage_error(),
        VaultHandleError::Backend(_) => atoms::storage_error(),
    }
}

// =====================================================================
// NIF: vault_init/2
// =====================================================================

/// Open or create the vault at `storage_path`. Always returns a sealed
/// handle (SC-VAULT-001), or `{error, storage_error}` when the file cannot
/// be opened.
#[rustler::nif(schedule = "DirtyIo")]
fn vault_init<'a>(env: Env<'a>, storage_path: String, audit_path: String) -> NifResult<Term<'a>> {
    match VaultHandle::open(&storage_path, &audit_path) {
        Ok(handle) => Ok((atoms::ok(), ResourceArc::new(handle)).encode(env)),
        Err(_) => Ok((atoms::error(), atoms::storage_error()).encode(env)),
    }
}

// =====================================================================
// NIF: vault_unseal/2
// =====================================================================

/// Transition Sealed → Active when `master_key` decrypts the verifier row
/// (the first unseal of an empty vault establishes the key).
/// Returns `{ok, nil}` or `{error, wrong_key | already_unsealed | storage_error}`.
#[rustler::nif(schedule = "DirtyIo")]
fn vault_unseal<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    master_key: Binary,
) -> NifResult<Term<'a>> {
    match handle.state() {
        VaultState::Active => return Ok((atoms::error(), atoms::already_unsealed()).encode(env)),
        VaultState::Halted | VaultState::Corrupt => {
            return Ok((atoms::error(), atoms::storage_error()).encode(env))
        }
        _ => {}
    }
    handle.set_state(VaultState::Unsealing);
    let key = Zeroizing::new(master_key.as_slice().to_vec());
    match handle.disk.unseal_verified(key) {
        Ok(()) => {
            handle.set_state(VaultState::Active);
            Ok((atoms::ok(), rustler::types::atom::nil()).encode(env))
        }
        Err(VaultHandleError::AlreadyUnsealed) => {
            handle.set_state(VaultState::Active);
            Ok((atoms::error(), atoms::already_unsealed()).encode(env))
        }
        Err(VaultHandleError::Crypto(CryptoError::DecryptionFailed)) | Err(VaultHandleError::WrongKey) => {
            handle.set_state(VaultState::Sealed);
            Ok((atoms::error(), atoms::wrong_key()).encode(env))
        }
        Err(VaultHandleError::Crypto(_)) => {
            // The verifier row is not an envelope: the file is not ours.
            handle.set_state(VaultState::Corrupt);
            Ok((atoms::error(), atoms::storage_error()).encode(env))
        }
        Err(e) => {
            handle.set_state(VaultState::Sealed);
            Ok((atoms::error(), error_atom(&e)).encode(env))
        }
    }
}

// =====================================================================
// NIF: vault_seal/1
// =====================================================================

/// Active → Sealed. Zeroizes the master key in RAM (SC-VAULT-002).
#[rustler::nif(schedule = "DirtyIo")]
fn vault_seal<'a>(env: Env<'a>, handle: ResourceArc<VaultHandle>) -> NifResult<Term<'a>> {
    handle.set_state(VaultState::Sealing);
    handle.disk.seal();
    handle.set_state(VaultState::Sealed);
    Ok(atoms::ok().encode(env))
}

// =====================================================================
// NIF: vault_status/1
// =====================================================================

/// Returns `#{name => State, storage => Path}`.
#[rustler::nif]
fn vault_status<'a>(env: Env<'a>, handle: ResourceArc<VaultHandle>) -> NifResult<Term<'a>> {
    let state_atom = handle.state().to_atom();
    let mut map = rustler::Term::map_new(env);
    map = map.map_put(atoms::name(), state_atom).unwrap();
    map = map
        .map_put(atoms::storage(), handle.storage_path.to_string_lossy().to_string())
        .unwrap();
    let _ = &handle.audit_path;
    Ok(map)
}

// =====================================================================
// NIF: vault_kv_put/5
// =====================================================================

#[rustler::nif(schedule = "DirtyIo")]
fn vault_kv_put<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    name: String,
    value: Binary,
    ttl_sec: i64,
    max_ttl_sec: i64,
) -> NifResult<Term<'a>> {
    if !handle.is_active() {
        return Ok((atoms::error(), atoms::sealed()).encode(env));
    }
    if !valid_name(&name) {
        return Ok((atoms::error(), (atoms::invalid_name(), name)).encode(env));
    }
    if value.is_empty() {
        return Ok((atoms::error(), atoms::storage_error()).encode(env));
    }
    if ttl_sec <= 0 || max_ttl_sec < ttl_sec {
        return Ok((atoms::error(), atoms::ttl_expired()).encode(env));
    }
    match handle.disk.put_with_lease(&name, value.as_slice(), ttl_sec, max_ttl_sec) {
        Ok((version, lease_id)) => {
            let mut map = rustler::Term::map_new(env);
            map = map.map_put(atoms::version(), version).unwrap();
            map = map.map_put(atoms::lease_id(), lease_id).unwrap();
            Ok((atoms::ok(), map).encode(env))
        }
        Err(e) => Ok((atoms::error(), error_atom(&e)).encode(env)),
    }
}

// =====================================================================
// NIF: vault_kv_get/2
// =====================================================================

#[rustler::nif(schedule = "DirtyIo")]
fn vault_kv_get<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    name: String,
) -> NifResult<Term<'a>> {
    if !handle.is_active() {
        return Ok((atoms::error(), atoms::sealed()).encode(env));
    }
    if !valid_name(&name) {
        return Ok((atoms::error(), (atoms::invalid_name(), name)).encode(env));
    }
    match handle.disk.get_latest_meta(&name) {
        Ok((version, plaintext, created_at, _ttl, max_ttl, _lease)) => {
            // SC-VAULT-006: hard-stale fail-closed on max_ttl
            let age = chrono::Utc::now().timestamp() - created_at;
            if age >= max_ttl {
                handle.disk.audit_event("get_failed_stale", &name, version);
                return Ok((atoms::error(), (atoms::ttl_expired(), name)).encode(env));
            }
            let mut bin = OwnedBinary::new(plaintext.len()).unwrap();
            bin.as_mut_slice().copy_from_slice(&plaintext);
            handle.disk.audit_event("get", &name, version);
            Ok((atoms::ok(), Binary::from_owned(bin, env)).encode(env))
        }
        Err(VaultHandleError::NotFound(_)) => {
            Ok((atoms::error(), (atoms::not_found(), name)).encode(env))
        }
        Err(VaultHandleError::Crypto(CryptoError::DecryptionFailed)) => {
            handle.disk.audit_event("get_failed_decrypt", &name, 0);
            Ok((atoms::error(), (atoms::decrypt_failed(), name)).encode(env))
        }
        Err(e) => Ok((atoms::error(), error_atom(&e)).encode(env)),
    }
}

// =====================================================================
// NIF: vault_kv_versions/2
// =====================================================================

#[rustler::nif(schedule = "DirtyIo")]
fn vault_kv_versions<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    name: String,
) -> NifResult<Term<'a>> {
    if !handle.is_active() {
        return Ok((atoms::error(), atoms::sealed()).encode(env));
    }
    if !valid_name(&name) {
        return Ok((atoms::error(), (atoms::invalid_name(), name)).encode(env));
    }
    match handle.disk.versions_with_ts(&name) {
        Ok(rows) => {
            let terms: Vec<Term> = rows
                .into_iter()
                .map(|(v, ts)| {
                    let mut m = rustler::Term::map_new(env);
                    m = m.map_put(atoms::version(), v).unwrap();
                    m = m.map_put(atoms::ts(), ts).unwrap();
                    m
                })
                .collect();
            Ok((atoms::ok(), terms).encode(env))
        }
        Err(e) => Ok((atoms::error(), error_atom(&e)).encode(env)),
    }
}

// =====================================================================
// NIF: vault_kv_destroy/3
// =====================================================================

#[rustler::nif(schedule = "DirtyIo")]
fn vault_kv_destroy<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    name: String,
    version: i64,
) -> NifResult<Term<'a>> {
    if !handle.is_active() {
        return Ok((atoms::error(), atoms::sealed()).encode(env));
    }
    if !valid_name(&name) {
        return Ok((atoms::error(), (atoms::invalid_name(), name)).encode(env));
    }
    match handle.disk.destroy(&name, version) {
        Ok(true) => Ok(atoms::ok().encode(env)),
        Ok(false) => Ok((atoms::error(), (atoms::not_found(), name)).encode(env)),
        Err(e) => Ok((atoms::error(), error_atom(&e)).encode(env)),
    }
}

// =====================================================================
// NIF: vault_lease_renew/3
// =====================================================================

#[rustler::nif(schedule = "DirtyIo")]
fn vault_lease_renew<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    lease_id: String,
    ttl_sec: i64,
) -> NifResult<Term<'a>> {
    if !handle.is_active() {
        return Ok((atoms::error(), atoms::sealed()).encode(env));
    }
    if ttl_sec <= 0 {
        return Ok((atoms::error(), atoms::ttl_expired()).encode(env));
    }
    match handle.disk.lease_renew(&lease_id, ttl_sec) {
        Ok(Some(new_expiry)) => Ok((atoms::ok(), new_expiry).encode(env)),
        Ok(None) => Ok((atoms::error(), atoms::not_found()).encode(env)),
        Err(e) => Ok((atoms::error(), error_atom(&e)).encode(env)),
    }
}

// =====================================================================
// NIF: vault_audit_tail/2
// =====================================================================

/// Audit rows with `ts >= since_ts`. Readable while sealed: the trail is
/// not a secret and register sync must observe seal events.
#[rustler::nif(schedule = "DirtyIo")]
fn vault_audit_tail<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    since_ts: i64,
) -> NifResult<Term<'a>> {
    match handle.disk.audit_tail(since_ts) {
        Ok(rows) => {
            let entries: Vec<Term> = rows
                .into_iter()
                .map(|(ts, event, name, version, caller)| {
                    let mut m = rustler::Term::map_new(env);
                    m = m.map_put(atoms::ts(), ts).unwrap();
                    m = m.map_put("event", event).unwrap();
                    m = m.map_put(atoms::name(), name).unwrap();
                    m = m.map_put(atoms::version(), version).unwrap();
                    m = m.map_put(atoms::caller(), caller).unwrap();
                    m
                })
                .collect();
            Ok((atoms::ok(), entries).encode(env))
        }
        Err(e) => Ok((atoms::error(), error_atom(&e)).encode(env)),
    }
}

// =====================================================================
// Pass-22: kek_chain NIF entry points (exposes argon2 + tpm_present + salt)
// =====================================================================

/// Derive a 32-byte master key from a passphrase + salt via argon2id.
/// SC-VAULT-021: 64MB/3iter/parallelism=4. SC-VAULT-002: caller must zeroize.
#[rustler::nif(schedule = "DirtyIo")]
fn kek_derive_master_key<'a>(
    env: Env<'a>,
    passphrase: Binary,
    salt: Binary,
) -> NifResult<Term<'a>> {
    match kek_chain::derive_master_key(passphrase.as_slice(), salt.as_slice()) {
        Ok(master) => {
            let mut bin = OwnedBinary::new(master.len()).unwrap();
            bin.as_mut_slice().copy_from_slice(master.as_slice());
            Ok((atoms::ok(), Binary::from_owned(bin, env)).encode(env))
        }
        Err(kek_chain::KekDeriveError::SaltTooShort(n)) => {
            Ok((atoms::error(), ("salt_too_short", n.to_string())).encode(env))
        }
        Err(kek_chain::KekDeriveError::BadParam(msg)) => {
            Ok((atoms::error(), ("bad_param", msg)).encode(env))
        }
        Err(kek_chain::KekDeriveError::DeriveFailed(msg)) => {
            Ok((atoms::error(), ("derive_failed", msg)).encode(env))
        }
        Err(kek_chain::KekDeriveError::BadOutputLen(n)) => {
            Ok((atoms::error(), ("bad_output_len", n.to_string())).encode(env))
        }
    }
}

/// Generate a fresh 16-byte salt from the OS RNG. Caller persists alongside
/// vault state so subsequent unseals can re-derive deterministically.
#[rustler::nif]
fn kek_generate_salt<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    let salt = kek_chain::generate_salt();
    let mut bin = OwnedBinary::new(salt.len()).unwrap();
    bin.as_mut_slice().copy_from_slice(&salt);
    Ok((atoms::ok(), Binary::from_owned(bin, env)).encode(env))
}

/// Probe whether `/dev/tpm0` (or override path) exists on this host.
/// Returns true iff the path resolves; does NOT attempt unseal.
#[rustler::nif]
fn kek_tpm_present<'a>(env: Env<'a>, override_path: String) -> NifResult<Term<'a>> {
    let p = if override_path.is_empty() {
        None
    } else {
        Some(std::path::Path::new(&override_path))
    };
    let p_buf;
    let p_ref = match p {
        Some(s) => Some(s),
        None => {
            p_buf = std::path::PathBuf::from("/dev/tpm0");
            Some(p_buf.as_path())
        }
    };
    let present = kek_chain::tpm_present(p_ref);
    Ok(present.encode(env))
}

// =====================================================================
// rustler init
// =====================================================================

fn on_load(env: Env, _info: Term) -> bool {
    let _ = rustler::resource!(VaultHandle, env);
    true
}

rustler::init!(
    "rusty_vault_nif",
    [
        vault_init,
        vault_unseal,
        vault_seal,
        vault_status,
        vault_kv_put,
        vault_kv_get,
        vault_kv_versions,
        vault_kv_destroy,
        vault_lease_renew,
        vault_audit_tail,
        kek_derive_master_key,
        kek_generate_salt,
        kek_tpm_present,
    ],
    load = on_load
);

// =====================================================================
// VF-01 laws — exercised on the resource type without a BEAM. The NIF
// functions themselves are thin adapters over these calls.
// =====================================================================

#[cfg(test)]
mod vf01_laws {
    use super::*;
    use tempfile::tempdir;

    fn key(b: u8) -> Zeroizing<Vec<u8>> {
        Zeroizing::new(vec![b; 32])
    }

    #[test]
    fn init_is_sealed_and_creates_the_file() {
        let dir = tempdir().unwrap();
        let db = dir.path().join("v.sqlite3");
        let h = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
        assert_eq!(h.state(), VaultState::Sealed);
        assert!(db.exists());
        assert!(h.disk.get_latest_meta("k").is_err(), "sealed reads fail closed");
    }

    #[test]
    fn directory_storage_path_resolves_to_a_file_inside_it() {
        let dir = tempdir().unwrap();
        let h = VaultHandle::open(dir.path().to_str().unwrap(), "unused").unwrap();
        assert_eq!(h.storage_path, dir.path().join(DEFAULT_DB_FILE));
        assert!(h.storage_path.exists());
    }

    #[test]
    fn law_persistence_a_put_in_one_handle_is_read_by_a_fresh_handle() {
        let dir = tempdir().unwrap();
        let db = dir.path().join("p.sqlite3");
        {
            let a = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
            a.disk.unseal_verified(key(0x11)).unwrap();
            let (v, lease) = a.disk.put_with_lease("telegram/bot_token", b"123:abc", 60, 600).unwrap();
            assert_eq!(v, 1);
            assert!(lease.starts_with("lease-telegram/bot_token-1-"));
        } // handle dropped: nothing survives in RAM
        let b = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
        b.disk.unseal_verified(key(0x11)).unwrap();
        let (v, pt, _c, _t, _m, _l) = b.disk.get_latest_meta("telegram/bot_token").unwrap();
        assert_eq!((v, pt.as_slice()), (1, &b"123:abc"[..]));
        assert_eq!(b.disk.versions_with_ts("telegram/bot_token").unwrap().len(), 1);
    }

    #[test]
    fn law_wrong_key_is_refused_and_the_vault_stays_sealed() {
        let dir = tempdir().unwrap();
        let db = dir.path().join("w.sqlite3");
        {
            let a = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
            a.disk.unseal_verified(key(0x11)).unwrap();
            a.disk.put_with_lease("k", b"v", 60, 600).unwrap();
        }
        let b = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
        let err = b.disk.unseal_verified(key(0x22)).unwrap_err();
        assert!(matches!(err, VaultHandleError::WrongKey), "got {err:?}");
        assert!(matches!(b.disk.get_latest_meta("k").unwrap_err(), VaultHandleError::Sealed));
        // the right key still works afterwards
        b.disk.unseal_verified(key(0x11)).unwrap();
        assert_eq!(b.disk.get_latest_meta("k").unwrap().1, b"v");
    }

    #[test]
    fn law_short_key_is_refused_before_touching_the_verifier() {
        let dir = tempdir().unwrap();
        let db = dir.path().join("s.sqlite3");
        let a = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
        let err = a.disk.unseal_verified(Zeroizing::new(vec![1u8; 16])).unwrap_err();
        assert!(matches!(err, VaultHandleError::BadMasterKeyLen(16)));
        // no verifier was established, so a 32-byte key still establishes it
        a.disk.unseal_verified(key(0x33)).unwrap();
    }

    #[test]
    fn law_ciphertext_on_disk_never_contains_the_plaintext() {
        let dir = tempdir().unwrap();
        let db = dir.path().join("c.sqlite3");
        let a = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
        a.disk.unseal_verified(key(0x44)).unwrap();
        let secret = b"8660817750:AAAA-not-a-real-token-but-long-enough-to-find";
        a.disk.put_with_lease("t", secret, 60, 600).unwrap();
        let bytes = std::fs::read(&db).unwrap();
        let wal = std::fs::read(db.with_extension("sqlite3-wal")).unwrap_or_default();
        let hay = [bytes, wal].concat();
        assert!(!hay.windows(secret.len()).any(|w| w == secret), "plaintext leaked to disk");
        assert!(!hay.windows(32).any(|w| w == &[0x44u8; 32][..]), "master key leaked to disk");
    }

    #[test]
    fn law_stale_read_fails_closed_on_max_ttl() {
        let dir = tempdir().unwrap();
        let db = dir.path().join("t.sqlite3");
        let a = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
        a.disk.unseal_verified(key(0x55)).unwrap();
        a.disk.put_with_lease("k", b"v", 1, 1).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        let (_v, _pt, created_at, _t, max_ttl, _l) = a.disk.get_latest_meta("k").unwrap();
        assert!(chrono::Utc::now().timestamp() - created_at >= max_ttl);
    }

    #[test]
    fn law_destroy_versions_and_lease_renew_are_disk_operations() {
        let dir = tempdir().unwrap();
        let db = dir.path().join("d.sqlite3");
        let a = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
        a.disk.unseal_verified(key(0x66)).unwrap();
        let (_, l1) = a.disk.put_with_lease("k", b"v1", 60, 600).unwrap();
        let (_, _l2) = a.disk.put_with_lease("k", b"v2", 60, 600).unwrap();
        assert_eq!(a.disk.versions_with_ts("k").unwrap().iter().map(|r| r.0).collect::<Vec<_>>(), vec![1, 2]);
        assert!(a.disk.destroy("k", 1).unwrap());
        assert!(!a.disk.destroy("k", 1).unwrap());
        assert_eq!(a.disk.versions_with_ts("k").unwrap().len(), 1);
        assert!(a.disk.lease_renew(&l1, 120).unwrap().is_none(), "destroyed row has no lease");
        let b = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
        b.disk.unseal_verified(key(0x66)).unwrap();
        let (_v, _pt, created, _t, _m, lease2) = b.disk.get_latest_meta("k").unwrap();
        assert_eq!(b.disk.lease_renew(&lease2, 120).unwrap(), Some(created + 120));
    }

    #[test]
    fn law_secret_names_reject_empty_control_bytes_and_oversize() {
        assert!(valid_name("telegram/staging/bot_token"));
        assert!(valid_name("k"));
        assert!(valid_name(&"a".repeat(MAX_NAME_BYTES)));
        assert!(!valid_name(""), "empty name (reviewer probe 8)");
        assert!(!valid_name("k\0nul"), "NUL byte (reviewer probe 7)");
        assert!(!valid_name("k\nx"), "newline");
        assert!(!valid_name("k\x7f"), "DEL");
        assert!(!valid_name(&"a".repeat(MAX_NAME_BYTES + 1)), "oversize");
        assert!(valid_name("名前/ключ"), "non-ASCII text is a name, not a control byte");
    }

    #[test]
    fn law_audit_is_append_only_and_survives_a_fresh_handle() {
        let dir = tempdir().unwrap();
        let db = dir.path().join("a.sqlite3");
        {
            let a = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
            a.disk.unseal_verified(key(0x77)).unwrap();
            a.disk.put_with_lease("k", b"v", 60, 600).unwrap();
            a.disk.seal();
        }
        let b = VaultHandle::open(db.to_str().unwrap(), "unused").unwrap();
        let rows = b.disk.audit_tail(0).unwrap();
        let events: Vec<&str> = rows.iter().map(|r| r.1.as_str()).collect();
        assert_eq!(events, vec!["key_established", "unseal", "put", "seal"]);
        let conn = rusqlite::Connection::open(&db).unwrap();
        assert!(conn.execute("UPDATE audit_log SET event = 'x'", []).is_err(), "UPDATE must be refused");
        assert!(conn.execute("DELETE FROM audit_log", []).is_err(), "DELETE must be refused");
        assert_eq!(b.disk.audit_tail(0).unwrap().len(), 4);
    }
}
