//! JWKS publication + cache (Phase 3).
//!
//! Surface (2 NIFs):
//!   jwks_publish(realm_id)        -> {jwks_json}
//!   jwks_get_cached(realm_id)     -> {jwks_json, age_ms, hit}
//!
//! `jwks_publish` reads `signing_keys` for the realm, returns ALL non-retired
//! keys (current + rotating) so consumers can verify tokens during the 7-day
//! overlap window mandated by SC-FERRISKEY-NIF-008.
//!
//! `jwks_get_cached` provides the in-process cache that the Wisp
//! `/.well-known/jwks.json` endpoint serves on the hot path:
//!   - TTL = 5 min hard / 4 min soft (SC-FERRISKEY-NIF-004)
//!   - lock-free read via RwLock
//!   - lazy refresh on miss; soft-refresh deferred to JwksCacheActor
//!
//! GCP Workload Identity Federation Bridge 1: this is the JWKS GCP fetches
//! at WIF-provider create time and re-fetches on `kid` miss.

use anyhow::{Context, Result};
use once_cell::sync::Lazy;
use rusqlite::params;
use serde::Serialize;
use std::collections::HashMap;
use std::sync::RwLock;
use std::time::Instant;

use crate::realm;

#[derive(Debug, Clone, Serialize)]
pub struct CacheEntry {
    pub jwks_json: String,
    /// Age in milliseconds since cached.
    pub age_ms: i64,
    pub hit: bool,
}

struct CacheRow {
    jwks_json: String,
    cached_at: Instant,
}

static CACHE: Lazy<RwLock<HashMap<String, CacheRow>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

const TTL_MS: i64 = 300_000; // 5 min — SC-FERRISKEY-NIF-004

/// Build the JWKS document from current+rotating signing keys for a realm.
/// Always live (no cache); the cache wrapper lives in `get_cached`.
pub fn publish(db_path: &str, realm_id: &str) -> Result<String> {
    let conn = realm::open_for_test(db_path)?;
    let mut stmt = conn.prepare(
        "SELECT public_jwk FROM signing_keys
         WHERE realm_id=?1 AND retired_at IS NULL
         ORDER BY rotated_at IS NULL DESC, created_at DESC",
    )?;
    let keys_iter = stmt.query_map(params![realm_id], |r| {
        let s: String = r.get(0)?;
        Ok(s)
    })?;
    let mut keys = Vec::new();
    for k in keys_iter {
        let parsed: serde_json::Value =
            serde_json::from_str(&k?).context("public_jwk parse")?;
        keys.push(parsed);
    }
    let jwks = serde_json::json!({"keys": keys});
    Ok(jwks.to_string())
}

/// Hot-path JWKS read. Returns cache hit if fresh (<5 min), otherwise refreshes.
pub fn get_cached(db_path: &str, realm_id: &str) -> Result<CacheEntry> {
    {
        let read = CACHE.read().unwrap();
        if let Some(row) = read.get(realm_id) {
            let age_ms = row.cached_at.elapsed().as_millis() as i64;
            if age_ms < TTL_MS {
                return Ok(CacheEntry {
                    jwks_json: row.jwks_json.clone(),
                    age_ms,
                    hit: true,
                });
            }
        }
    }
    // Miss / stale — refresh under write lock.
    let fresh = publish(db_path, realm_id)?;
    {
        let mut write = CACHE.write().unwrap();
        write.insert(
            realm_id.to_string(),
            CacheRow {
                jwks_json: fresh.clone(),
                cached_at: Instant::now(),
            },
        );
    }
    Ok(CacheEntry {
        jwks_json: fresh,
        age_ms: 0,
        hit: false,
    })
}

/// Force-evict the cache for a realm. Called after `signing_key_rotate`.
pub fn invalidate(realm_id: &str) {
    let mut write = CACHE.write().unwrap();
    write.remove(realm_id);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_realm() -> (tempfile::TempDir, String, String) {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("ferriskey.db").to_str().unwrap().to_string();
        crate::db::init(&path).unwrap();
        let r = realm::create(&path, "c3i", "https://x/realms/c3i", None).unwrap();
        (tmp, path, r.id)
    }

    #[test]
    fn publish_empty_when_no_keys() {
        let (_tmp, path, realm_id) = fresh_realm();
        let jwks: serde_json::Value = serde_json::from_str(&publish(&path, &realm_id).unwrap()).unwrap();
        assert_eq!(jwks["keys"].as_array().unwrap().len(), 0);
    }

    #[test]
    fn publish_includes_current_and_rotating() {
        let (_tmp, path, realm_id) = fresh_realm();
        let _first = crate::token::rotate(&path, &realm_id, "EdDSA").unwrap();
        let _second = crate::token::rotate(&path, &realm_id, "EdDSA").unwrap();
        let jwks: serde_json::Value = serde_json::from_str(&publish(&path, &realm_id).unwrap()).unwrap();
        let keys = jwks["keys"].as_array().unwrap();
        assert_eq!(keys.len(), 2, "JWKS must include current + rotating during overlap");
        for k in keys {
            assert_eq!(k["kty"], "OKP");
            assert_eq!(k["alg"], "EdDSA");
        }
    }

    #[test]
    fn get_cached_then_hit() {
        let (_tmp, path, realm_id) = fresh_realm();
        invalidate(&realm_id);
        crate::token::rotate(&path, &realm_id, "EdDSA").unwrap();
        let first = get_cached(&path, &realm_id).unwrap();
        assert!(!first.hit, "first read is a miss");
        let second = get_cached(&path, &realm_id).unwrap();
        assert!(second.hit, "second read within TTL is a hit");
        assert_eq!(first.jwks_json, second.jwks_json);
    }

    #[test]
    fn invalidate_forces_refresh() {
        let (_tmp, path, realm_id) = fresh_realm();
        invalidate(&realm_id);
        crate::token::rotate(&path, &realm_id, "EdDSA").unwrap();
        let _first = get_cached(&path, &realm_id).unwrap();
        invalidate(&realm_id);
        let after = get_cached(&path, &realm_id).unwrap();
        assert!(!after.hit, "after invalidate must miss");
    }
}
