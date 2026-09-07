//! SQLite WAL store for FerrisKey IAM data.
//!
//! Schema is the authoritative on-disk representation of every IAM object.
//! Cross-node convergence rides the existing Zenoh xholon CRDT plane (the
//! daemon replicates this DB the same way it replicates Smriti.db).
//!
//! Tables (Phase 1 substrate; Phase 2+ NIFs INSERT/UPDATE):
//!   realms              — realm CRUD + GCP project binding
//!   users               — user CRUD + bcrypt password hash
//!   groups              — group CRUD
//!   roles               — role CRUD + fractal layer mask
//!   user_roles          — N:M user→role
//!   group_members       — N:M group→user
//!   signing_keys        — signing key history (rotation, kid, alg)
//!   audit_log           — append-only audit trail (SC-FERRISKEY-NIF-006)
//!   scim_outbound_queue — durable queue for outbound SCIM PUSH retries
//!   gcp_sts_cache       — GCP access-token cache (TTL ≤ 55 min)
//!
//! SC-FERRISKEY-NIF-007 — WAL mode + synchronous=NORMAL + 30 s busy_timeout.
//! SC-FERRISKEY-NIF-008 — signing_keys keeps both current + previous (7-day
//! overlap) so JWKS publishes both during rotation.

use anyhow::{Context, Result};
use rusqlite::Connection;
use std::path::Path;

pub const SCHEMA_VERSION: i64 = 1;

/// Initialize the SQLite database at `path`. Idempotent: re-running applies
/// any pending migrations and leaves an already-current DB untouched.
pub fn init(path: &str) -> Result<i64> {
    if let Some(parent) = Path::new(path).parent() {
        std::fs::create_dir_all(parent).with_context(|| {
            format!("ferriskey_nif: failed to create parent dir for {path}")
        })?;
    }
    let conn = Connection::open(path)
        .with_context(|| format!("ferriskey_nif: failed to open {path}"))?;
    apply_pragmas(&conn)?;
    apply_schema(&conn)?;
    Ok(SCHEMA_VERSION)
}

fn apply_pragmas(conn: &Connection) -> Result<()> {
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "synchronous", "NORMAL")?;
    conn.pragma_update(None, "busy_timeout", 30_000)?;
    conn.pragma_update(None, "foreign_keys", "ON")?;
    Ok(())
}

fn apply_schema(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS realms (
            id            TEXT PRIMARY KEY,
            name          TEXT NOT NULL UNIQUE,
            issuer_url    TEXT NOT NULL,
            gcp_binding   TEXT,                  -- JSON: {project_id, region, wif_pool}
            created_at    INTEGER NOT NULL,
            updated_at    INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS users (
            id            TEXT PRIMARY KEY,
            realm_id      TEXT NOT NULL REFERENCES realms(id) ON DELETE CASCADE,
            sub           TEXT NOT NULL,         -- OIDC subject claim
            username      TEXT NOT NULL,
            email         TEXT NOT NULL,
            password_hash TEXT,                  -- bcrypt; NULL for federated-only
            mfa_enrolled  INTEGER NOT NULL DEFAULT 0,
            attrs         TEXT NOT NULL DEFAULT '{}',  -- SCIM extensions JSON
            created_at    INTEGER NOT NULL,
            updated_at    INTEGER NOT NULL,
            UNIQUE(realm_id, username)
        );

        CREATE TABLE IF NOT EXISTS groups (
            id            TEXT PRIMARY KEY,
            realm_id      TEXT NOT NULL REFERENCES realms(id) ON DELETE CASCADE,
            name          TEXT NOT NULL,
            display_name  TEXT,
            attrs         TEXT NOT NULL DEFAULT '{}',
            created_at    INTEGER NOT NULL,
            updated_at    INTEGER NOT NULL,
            UNIQUE(realm_id, name)
        );

        CREATE TABLE IF NOT EXISTS roles (
            id            TEXT PRIMARY KEY,
            realm_id      TEXT NOT NULL REFERENCES realms(id) ON DELETE CASCADE,
            name          TEXT NOT NULL,
            -- 8-bit fractal layer mask: bit i set means access to layer Li.
            -- c3i-admin    = 0b11111111 (255), all 8 layers
            -- c3i-operator = 0b11111110 (254), L1-L7
            -- c3i-viewer   = 0b11110000 (240), L4-L7
            -- c3i-service  = 0b01111000 (120), L3-L6
            layer_mask    INTEGER NOT NULL,
            requires_mfa  INTEGER NOT NULL DEFAULT 0,
            created_at    INTEGER NOT NULL,
            UNIQUE(realm_id, name)
        );

        CREATE TABLE IF NOT EXISTS user_roles (
            user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            role_id       TEXT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
            granted_at    INTEGER NOT NULL,
            granted_by    TEXT,
            PRIMARY KEY (user_id, role_id)
        );

        CREATE TABLE IF NOT EXISTS group_members (
            group_id      TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            added_at      INTEGER NOT NULL,
            PRIMARY KEY (group_id, user_id)
        );

        CREATE TABLE IF NOT EXISTS signing_keys (
            kid           TEXT PRIMARY KEY,
            realm_id      TEXT NOT NULL REFERENCES realms(id) ON DELETE CASCADE,
            alg           TEXT NOT NULL CHECK (alg IN ('RS256','ES256','EdDSA')),
            -- Public key in JWK form; private material lives in RustyVault
            -- per SC-FERRISKEY-NIF-010 and is referenced by `vault_secret_name`.
            public_jwk    TEXT NOT NULL,
            vault_secret_name TEXT NOT NULL,
            created_at    INTEGER NOT NULL,
            rotated_at    INTEGER,                -- when superseded
            retired_at    INTEGER                 -- when removed from JWKS
        );

        CREATE TABLE IF NOT EXISTS audit_log (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            ts            INTEGER NOT NULL,
            realm_id      TEXT,
            actor         TEXT NOT NULL,
            action        TEXT NOT NULL,
            target        TEXT,
            outcome       TEXT NOT NULL CHECK (outcome IN ('ok','denied','error')),
            details       TEXT NOT NULL DEFAULT '{}'   -- JSON
        );
        CREATE INDEX IF NOT EXISTS idx_audit_log_ts ON audit_log(ts DESC);
        CREATE INDEX IF NOT EXISTS idx_audit_log_realm ON audit_log(realm_id, ts DESC);

        CREATE TABLE IF NOT EXISTS scim_outbound_queue (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            target        TEXT NOT NULL,         -- 'cloud_identity_groups' | 'admin_sdk_directory'
            op            TEXT NOT NULL,         -- 'create' | 'update' | 'delete'
            resource_type TEXT NOT NULL,         -- 'User' | 'Group'
            payload       TEXT NOT NULL,
            attempts      INTEGER NOT NULL DEFAULT 0,
            next_attempt_at INTEGER NOT NULL,
            last_error    TEXT,
            created_at    INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_scim_queue_due
            ON scim_outbound_queue(next_attempt_at);

        CREATE TABLE IF NOT EXISTS gcp_sts_cache (
            cache_key     TEXT PRIMARY KEY,      -- sha256(jwt_sub | scope | sa)
            access_token  TEXT NOT NULL,
            sa_principal  TEXT NOT NULL,
            issued_at     INTEGER NOT NULL,
            expires_at    INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_gcp_sts_expires
            ON gcp_sts_cache(expires_at);

        CREATE TABLE IF NOT EXISTS schema_meta (
            key           TEXT PRIMARY KEY,
            value         TEXT NOT NULL
        );
        "#,
    )?;
    conn.execute(
        "INSERT OR REPLACE INTO schema_meta(key,value) VALUES('version', ?1)",
        rusqlite::params![SCHEMA_VERSION.to_string()],
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn schema_init_idempotent() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("ferriskey.db");
        let p = path.to_str().unwrap();
        assert_eq!(init(p).unwrap(), SCHEMA_VERSION);
        // re-running must not error
        assert_eq!(init(p).unwrap(), SCHEMA_VERSION);
    }
}
