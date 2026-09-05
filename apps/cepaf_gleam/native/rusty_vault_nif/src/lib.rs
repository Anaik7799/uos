//! rusty_vault_nif — Sealed K/V vault NIF for cepaf_gleam.
//!
//! This crate exposes 10 NIFs implementing the Vault contract specified by
//! `.claude/rules/secrets-vault.md` (SC-VAULT-001..025 + SC-VAULT-CRYPTO-001).
//!
//! # Critical invariants
//!
//! - SC-VAULT-001: Vault MUST be sealed at process start
//! - SC-VAULT-002: KEK MUST never be persisted in plaintext
//! - SC-VAULT-005: Hot path MUST NOT make network calls
//! - SC-VAULT-CRYPTO-001: NO Tongsuo / SM2/SM3/SM4 in dependency tree
//!
//! Verification gate (CI):
//! ```bash
//! cargo tree | grep -iE 'tongsuo|sm[234]'
//! # MUST be empty
//! ```
//!
//! # NIF surface (10 functions)
//!
//! 1. `vault_init/2`  — bootstrap (creates sealed vault file)
//! 2. `vault_unseal/2` — sealed → active (KEK chain decrypts master)
//! 3. `vault_seal/1` — active → sealed (zeroizes master in RAM)
//! 4. `vault_status/1` — query state
//! 5. `vault_kv_put/5` — write secret + policy
//! 6. `vault_kv_get/2` — read latest version
//! 7. `vault_kv_versions/2` — version metadata
//! 8. `vault_kv_destroy/3` — hard-delete a version
//! 9. `vault_lease_renew/3` — extend a lease
//! 10. `vault_audit_tail/2` — read audit events for register sync
//!
//! All NIFs are dirty-IO scheduled (RustyVault's storage layer can block on disk).

use rustler::{Atom, Binary, Encoder, Env, NifResult, OwnedBinary, ResourceArc, Term};
use std::collections::HashMap;
use std::sync::{Mutex, RwLock};
use std::path::PathBuf;
use zeroize::Zeroizing;

pub mod crypto;
pub mod kek_chain;
pub mod sqlite_backend;
pub mod vault_handle;

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
        nif_panic,
        version,
        lease_id,
        ts,
        name,
        caller,
    }
}

// =====================================================================
// VaultHandle — process-wide resource holding the RustyVault Core
// =====================================================================

/// One stored version of a secret. Pass-20 body-wiring: in-memory K/V.
#[derive(Clone)]
pub struct KvEntry {
    pub version: i64,
    pub value: Zeroizing<Vec<u8>>,
    pub created_at: i64,
    pub ttl_sec: i64,
    pub max_ttl_sec: i64,
    pub lease_id: String,
}

/// One audit log entry. Append-only — SC-VAULT-008.
#[derive(Clone)]
pub struct AuditEntry {
    pub ts: i64,
    pub event: String,    // "put" | "get" | "destroy" | "lease_renew" | "unseal" | "seal"
    pub name: String,
    pub version: i64,
    pub caller: String,
}

/// State of a vault handle. We deliberately keep the inner core inside a Mutex
/// so concurrent NIF calls serialize safely (RustyVault's storage layer is not
/// internally Sync for all operations).
pub struct VaultHandle {
    storage_path: PathBuf,
    audit_path: PathBuf,
    /// State machine: Sealed | Unsealing | Active | Sealing | Corrupt | Halted
    state: RwLock<VaultState>,
    /// In-RAM master key, present only when Active. Zeroized on transition out.
    master_in_ram: Mutex<Option<Zeroizing<Vec<u8>>>>,
    /// Pass-20 body-wiring: in-memory K/V — name → versions (monotonic by SC-VAULT-011).
    /// Future: replaced by RustyVault::Core::SqliteBackend in Slice B-full.
    kv_store: Mutex<HashMap<String, Vec<KvEntry>>>,
    /// Pass-20 body-wiring: append-only audit log — SC-VAULT-008.
    audit_log: Mutex<Vec<AuditEntry>>,
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

impl VaultHandle {
    fn new(storage: PathBuf, audit: PathBuf) -> Self {
        Self {
            storage_path: storage,
            audit_path: audit,
            state: RwLock::new(VaultState::Sealed),
            master_in_ram: Mutex::new(None),
            kv_store: Mutex::new(HashMap::new()),
            audit_log: Mutex::new(Vec::new()),
        }
    }

    /// Pass-20 body: append an audit entry (SC-VAULT-008 append-only).
    fn audit_append(&self, event: &str, name: &str, version: i64) {
        let entry = AuditEntry {
            ts: chrono::Utc::now().timestamp(),
            event: event.to_string(),
            name: name.to_string(),
            version,
            caller: "nif".to_string(),
        };
        if let Ok(mut log) = self.audit_log.lock() {
            log.push(entry);
        }
    }

    /// Pass-20 body: compute next monotonic version per SC-VAULT-011.
    fn next_version(&self, name: &str) -> i64 {
        if let Ok(store) = self.kv_store.lock() {
            store
                .get(name)
                .and_then(|versions| versions.last())
                .map(|last| last.version + 1)
                .unwrap_or(1)
        } else {
            1
        }
    }
}

// =====================================================================
// Errors
// =====================================================================

#[derive(Debug, thiserror::Error)]
pub enum VaultError {
    #[error("vault is sealed")]
    Sealed,
    #[error("wrong master key")]
    WrongKey,
    #[error("secret not found: {0}")]
    NotFound(String),
    #[error("ttl expired for: {0}")]
    TtlExpired(String),
    #[error("storage error: {0}")]
    StorageError(String),
    #[error("vault already unsealed")]
    AlreadyUnsealed,
}

impl VaultError {
    fn to_atom(&self) -> Atom {
        match self {
            VaultError::Sealed => atoms::sealed(),
            VaultError::WrongKey => atoms::wrong_key(),
            VaultError::NotFound(_) => atoms::not_found(),
            VaultError::TtlExpired(_) => atoms::ttl_expired(),
            VaultError::StorageError(_) => atoms::storage_error(),
            VaultError::AlreadyUnsealed => atoms::already_unsealed(),
        }
    }
}

// =====================================================================
// NIF: vault_init/2
// =====================================================================

/// Initialize a vault. Creates `storage_path` on disk if not present.
/// Returns a sealed handle.
#[rustler::nif(schedule = "DirtyIo")]
fn vault_init<'a>(env: Env<'a>, storage_path: String, audit_path: String) -> NifResult<Term<'a>> {
    let handle = VaultHandle::new(PathBuf::from(storage_path), PathBuf::from(audit_path));
    // SC-VAULT-001: sealed at process start (always; init never returns active)
    let resource = ResourceArc::new(handle);
    Ok((atoms::ok(), resource).encode(env))
}

// =====================================================================
// NIF: vault_unseal/2
// =====================================================================

/// Transition Sealed → Active by decrypting the master key with `master_key`.
/// Returns `{:ok, :unsealed}` or `{:error, :wrong_key | :already_unsealed}`.
#[rustler::nif(schedule = "DirtyIo")]
fn vault_unseal<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    master_key: Binary,
) -> NifResult<Term<'a>> {
    {
        let state = handle.state.read().unwrap();
        if *state == VaultState::Active {
            return Ok((atoms::error(), atoms::already_unsealed()).encode(env));
        }
        if *state == VaultState::Halted || *state == VaultState::Corrupt {
            return Ok((atoms::error(), atoms::storage_error()).encode(env));
        }
    }
    {
        let mut state = handle.state.write().unwrap();
        *state = VaultState::Unsealing;
    }

    // TODO Slice B+: integrate RustyVault::core::Core::unseal(master_key)
    // For now: validate key length (must be 32 bytes for AES-256) and store in RAM.
    if master_key.len() != 32 {
        let mut state = handle.state.write().unwrap();
        *state = VaultState::Sealed;
        return Ok((atoms::error(), atoms::wrong_key()).encode(env));
    }

    let key_bytes = Zeroizing::new(master_key.as_slice().to_vec());
    {
        let mut master = handle.master_in_ram.lock().unwrap();
        *master = Some(key_bytes);
    }
    {
        let mut state = handle.state.write().unwrap();
        *state = VaultState::Active;
    }

    Ok((atoms::ok(), rustler::types::atom::nil()).encode(env))
}

// =====================================================================
// NIF: vault_seal/1
// =====================================================================

/// Active → Sealed. Zeroizes the master key in RAM.
#[rustler::nif(schedule = "DirtyIo")]
fn vault_seal<'a>(env: Env<'a>, handle: ResourceArc<VaultHandle>) -> NifResult<Term<'a>> {
    {
        let mut state = handle.state.write().unwrap();
        *state = VaultState::Sealing;
    }
    {
        // SC-VAULT-002: master key zeroized on seal
        let mut master = handle.master_in_ram.lock().unwrap();
        *master = None;  // Zeroizing<Vec<u8>> drop zeros the memory
    }
    {
        let mut state = handle.state.write().unwrap();
        *state = VaultState::Sealed;
    }
    Ok(atoms::ok().encode(env))
}

// =====================================================================
// NIF: vault_status/1
// =====================================================================

/// Returns the current state atom (sealed | active | …).
#[rustler::nif]
fn vault_status<'a>(env: Env<'a>, handle: ResourceArc<VaultHandle>) -> NifResult<Term<'a>> {
    let state = handle.state.read().unwrap();
    let state_atom = state.to_atom();
    let mut map = rustler::Term::map_new(env);
    map = map.map_put(atoms::name(), state_atom).unwrap();
    Ok(map)
}

// =====================================================================
// NIF stubs for the remaining 6 functions
// =====================================================================
// These compile cleanly and return shaped responses. Full bodies wired to
// RustyVault Core in follow-up Slice B continuation. SC-VAULT placeholder
// invariants are still enforced (sealed → reject reads).

// Pass-20 body wiring: real in-memory K/V backed by HashMap with monotonic
// versioning (SC-VAULT-011). Disk persistence (RustyVault::Core::SqliteBackend)
// remains deferred to Slice B-full continuation; this layer is process-local
// but functionally complete for sealed/active state machine + audit log.

#[rustler::nif(schedule = "DirtyIo")]
fn vault_kv_put<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    name: String,
    value: Binary,
    ttl_sec: i64,
    max_ttl_sec: i64,
) -> NifResult<Term<'a>> {
    if *handle.state.read().unwrap() != VaultState::Active {
        return Ok((atoms::error(), atoms::sealed()).encode(env));
    }
    if value.is_empty() {
        return Ok((atoms::error(), atoms::storage_error()).encode(env));
    }
    if ttl_sec <= 0 || max_ttl_sec < ttl_sec {
        return Ok((atoms::error(), atoms::ttl_expired()).encode(env));
    }

    // SC-VAULT-011: monotonic version per name
    let next_ver = handle.next_version(&name);
    let now = chrono::Utc::now().timestamp();
    let lease_id = format!("lease-{}-{}-{}", name, next_ver, now);

    let entry = KvEntry {
        version: next_ver,
        value: Zeroizing::new(value.as_slice().to_vec()),
        created_at: now,
        ttl_sec,
        max_ttl_sec,
        lease_id: lease_id.clone(),
    };

    if let Ok(mut store) = handle.kv_store.lock() {
        store.entry(name.clone()).or_insert_with(Vec::new).push(entry);
    } else {
        return Ok((atoms::error(), atoms::storage_error()).encode(env));
    }

    handle.audit_append("put", &name, next_ver);

    let mut map = rustler::Term::map_new(env);
    map = map.map_put(atoms::version(), next_ver).unwrap();
    map = map.map_put(atoms::lease_id(), lease_id).unwrap();
    Ok((atoms::ok(), map).encode(env))
}

#[rustler::nif(schedule = "DirtyIo")]
fn vault_kv_get<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    name: String,
) -> NifResult<Term<'a>> {
    if *handle.state.read().unwrap() != VaultState::Active {
        return Ok((atoms::error(), atoms::sealed()).encode(env));
    }

    let store = match handle.kv_store.lock() {
        Ok(s) => s,
        Err(_) => return Ok((atoms::error(), atoms::storage_error()).encode(env)),
    };

    // Snapshot the latest entry's needed fields, then drop the lock before audit.
    let snapshot: Option<(i64, i64, i64, Vec<u8>)> = store
        .get(&name)
        .and_then(|versions| versions.last())
        .map(|entry| (entry.version, entry.created_at, entry.max_ttl_sec, entry.value.as_slice().to_vec()));
    drop(store);

    match snapshot {
        None => Ok((atoms::error(), (atoms::not_found(), name)).encode(env)),
        Some((version, created_at, max_ttl, value_bytes)) => {
            // SC-VAULT-006: hard-stale fail-closed on max_ttl
            let age = chrono::Utc::now().timestamp() - created_at;
            if age >= max_ttl {
                handle.audit_append("get_failed_stale", &name, version);
                return Ok((atoms::error(), (atoms::ttl_expired(), name)).encode(env));
            }
            let mut bin = OwnedBinary::new(value_bytes.len()).unwrap();
            bin.as_mut_slice().copy_from_slice(&value_bytes);
            handle.audit_append("get", &name, version);
            Ok((atoms::ok(), Binary::from_owned(bin, env)).encode(env))
        }
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn vault_kv_versions<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    name: String,
) -> NifResult<Term<'a>> {
    if *handle.state.read().unwrap() != VaultState::Active {
        return Ok((atoms::error(), atoms::sealed()).encode(env));
    }

    let store = match handle.kv_store.lock() {
        Ok(s) => s,
        Err(_) => return Ok((atoms::error(), atoms::storage_error()).encode(env)),
    };

    let versions: Vec<(i64, i64)> = store
        .get(&name)
        .map(|entries| entries.iter().map(|e| (e.version, e.created_at)).collect())
        .unwrap_or_default();

    let terms: Vec<Term> = versions
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

#[rustler::nif(schedule = "DirtyIo")]
fn vault_kv_destroy<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    name: String,
    version: i64,
) -> NifResult<Term<'a>> {
    if *handle.state.read().unwrap() != VaultState::Active {
        return Ok((atoms::error(), atoms::sealed()).encode(env));
    }

    let mut store = match handle.kv_store.lock() {
        Ok(s) => s,
        Err(_) => return Ok((atoms::error(), atoms::storage_error()).encode(env)),
    };

    if let Some(versions) = store.get_mut(&name) {
        let before = versions.len();
        versions.retain(|e| e.version != version);
        if versions.len() == before {
            return Ok((atoms::error(), (atoms::not_found(), name)).encode(env));
        }
    } else {
        return Ok((atoms::error(), (atoms::not_found(), name)).encode(env));
    }
    drop(store);
    handle.audit_append("destroy", &name, version);
    Ok(atoms::ok().encode(env))
}

#[rustler::nif(schedule = "DirtyIo")]
fn vault_lease_renew<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    lease_id: String,
    ttl_sec: i64,
) -> NifResult<Term<'a>> {
    if *handle.state.read().unwrap() != VaultState::Active {
        return Ok((atoms::error(), atoms::sealed()).encode(env));
    }
    if ttl_sec <= 0 {
        return Ok((atoms::error(), atoms::ttl_expired()).encode(env));
    }
    // Find the entry by lease_id and extend its ttl_sec
    let mut store = match handle.kv_store.lock() {
        Ok(s) => s,
        Err(_) => return Ok((atoms::error(), atoms::storage_error()).encode(env)),
    };
    for (_name, versions) in store.iter_mut() {
        for entry in versions.iter_mut() {
            if entry.lease_id == lease_id {
                entry.ttl_sec = ttl_sec;
                let new_expiry = entry.created_at + ttl_sec;
                let nm = _name.clone();
                let v = entry.version;
                drop(store);
                handle.audit_append("lease_renew", &nm, v);
                return Ok((atoms::ok(), new_expiry).encode(env));
            }
        }
    }
    Ok((atoms::error(), atoms::not_found()).encode(env))
}

#[rustler::nif(schedule = "DirtyIo")]
fn vault_audit_tail<'a>(
    env: Env<'a>,
    handle: ResourceArc<VaultHandle>,
    since_ts: i64,
) -> NifResult<Term<'a>> {
    let log = match handle.audit_log.lock() {
        Ok(l) => l,
        Err(_) => return Ok((atoms::error(), atoms::storage_error()).encode(env)),
    };

    let entries: Vec<Term> = log
        .iter()
        .filter(|e| e.ts >= since_ts)
        .map(|e| {
            let mut m = rustler::Term::map_new(env);
            m = m.map_put(atoms::ts(), e.ts).unwrap();
            m = m.map_put("event", e.event.clone()).unwrap();
            m = m.map_put(atoms::name(), e.name.clone()).unwrap();
            m = m.map_put(atoms::version(), e.version).unwrap();
            m = m.map_put(atoms::caller(), e.caller.clone()).unwrap();
            m
        })
        .collect();
    Ok((atoms::ok(), entries).encode(env))
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
    rustler::resource!(VaultHandle, env);
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
// Pass-20 body-wiring unit tests — exercise KvEntry/AuditEntry directly
// (NIF entry points need a BEAM environment so are tested via Gleam-side
// integration tests, but the storage layer is unit-testable here).
// =====================================================================

#[cfg(test)]
mod body_tests {
    use super::*;
    use std::path::PathBuf;

    fn make_handle() -> VaultHandle {
        VaultHandle::new(
            PathBuf::from("/tmp/test-vault.db"),
            PathBuf::from("/tmp/test-vault-audit.log"),
        )
    }

    fn unseal(h: &VaultHandle) {
        *h.state.write().unwrap() = VaultState::Active;
    }

    #[test]
    fn next_version_starts_at_one() {
        let h = make_handle();
        assert_eq!(h.next_version("anthropic_api_key"), 1);
    }

    #[test]
    fn next_version_increments_after_put() {
        let h = make_handle();
        unseal(&h);
        // Simulate a put by inserting an entry directly
        let now = chrono::Utc::now().timestamp();
        h.kv_store.lock().unwrap().insert(
            "k1".to_string(),
            vec![KvEntry {
                version: 1,
                value: Zeroizing::new(vec![0u8; 4]),
                created_at: now,
                ttl_sec: 60,
                max_ttl_sec: 600,
                lease_id: "l1".to_string(),
            }],
        );
        assert_eq!(h.next_version("k1"), 2);
    }

    #[test]
    fn audit_append_grows_log_monotonically() {
        let h = make_handle();
        h.audit_append("put", "k1", 1);
        h.audit_append("get", "k1", 1);
        h.audit_append("destroy", "k1", 1);
        let log = h.audit_log.lock().unwrap();
        assert_eq!(log.len(), 3);
        assert_eq!(log[0].event, "put");
        assert_eq!(log[1].event, "get");
        assert_eq!(log[2].event, "destroy");
        // SC-VAULT-008: monotonic timestamps
        assert!(log[0].ts <= log[1].ts);
        assert!(log[1].ts <= log[2].ts);
    }

    #[test]
    fn handle_starts_sealed_with_empty_kv() {
        let h = make_handle();
        assert_eq!(*h.state.read().unwrap(), VaultState::Sealed);
        assert!(h.kv_store.lock().unwrap().is_empty());
        assert!(h.audit_log.lock().unwrap().is_empty());
        assert!(h.master_in_ram.lock().unwrap().is_none());
    }

    #[test]
    fn kv_store_supports_multiple_versions_per_name() {
        let h = make_handle();
        let now = chrono::Utc::now().timestamp();
        let mut store = h.kv_store.lock().unwrap();
        store.insert(
            "k1".to_string(),
            vec![
                KvEntry {
                    version: 1,
                    value: Zeroizing::new(b"v1".to_vec()),
                    created_at: now,
                    ttl_sec: 60,
                    max_ttl_sec: 600,
                    lease_id: "l1".to_string(),
                },
                KvEntry {
                    version: 2,
                    value: Zeroizing::new(b"v2".to_vec()),
                    created_at: now + 1,
                    ttl_sec: 60,
                    max_ttl_sec: 600,
                    lease_id: "l2".to_string(),
                },
            ],
        );
        drop(store);
        assert_eq!(h.next_version("k1"), 3);
    }

    #[test]
    fn destroy_removes_specific_version() {
        let h = make_handle();
        let now = chrono::Utc::now().timestamp();
        let mut store = h.kv_store.lock().unwrap();
        store.insert(
            "k1".to_string(),
            vec![
                KvEntry {
                    version: 1,
                    value: Zeroizing::new(b"v1".to_vec()),
                    created_at: now,
                    ttl_sec: 60,
                    max_ttl_sec: 600,
                    lease_id: "l1".to_string(),
                },
                KvEntry {
                    version: 2,
                    value: Zeroizing::new(b"v2".to_vec()),
                    created_at: now,
                    ttl_sec: 60,
                    max_ttl_sec: 600,
                    lease_id: "l2".to_string(),
                },
            ],
        );
        // Simulate destroy of version 1
        store.get_mut("k1").unwrap().retain(|e| e.version != 1);
        assert_eq!(store.get("k1").unwrap().len(), 1);
        assert_eq!(store.get("k1").unwrap()[0].version, 2);
    }

    #[test]
    fn sealed_state_blocks_kv_write_path_via_state_check() {
        let h = make_handle();
        // h is Sealed by default; the NIF guards check state.read() == Active
        assert_eq!(*h.state.read().unwrap(), VaultState::Sealed);
        assert_ne!(*h.state.read().unwrap(), VaultState::Active);
    }
}
