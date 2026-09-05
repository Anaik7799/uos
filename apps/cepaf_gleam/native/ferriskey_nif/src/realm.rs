//! Realm CRUD NIFs.
//!
//! A realm is the root tenancy unit: it owns users, groups, roles, signing
//! keys, and (optionally) a GCP binding. The default C3I realm is `c3i`,
//! whose issuer URL is published to GCP Workload Identity Federation.
//!
//! Phase 2 surface (4 NIFs):
//!   realm_create(name, issuer_url, gcp_binding_json) -> {id, ...}
//!   realm_get(id_or_name)                            -> {realm} | not_found
//!   realm_list()                                     -> [{realm}, ...]
//!   realm_delete(id)                                 -> {ok} | not_found
//!
//! SC-FERRISKEY-NIF-006 — every write op emits an audit span.
//! SC-FERRISKEY-NIF-007 — SQLite WAL r2d2 pool.
//! SC-VAULT-006 — fail-closed on hard-stale state (delegated to caller).

use anyhow::{Context, Result};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::audit;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Realm {
    pub id: String,
    pub name: String,
    pub issuer_url: String,
    pub gcp_binding: Option<serde_json::Value>,
    pub created_at: i64,
    pub updated_at: i64,
}

fn open(db_path: &str) -> Result<Connection> {
    if !Path::new(db_path).exists() {
        anyhow::bail!("ferriskey_nif: db not initialized at {db_path} — call ferriskey_db_init first");
    }
    let conn = Connection::open(db_path)
        .with_context(|| format!("realm: failed to open {db_path}"))?;
    conn.pragma_update(None, "busy_timeout", 30_000)?;
    Ok(conn)
}

/// Sibling-module helpers — exposed so `user.rs`, `group.rs`, `role.rs`
/// share the same connection-open / id-generation / time semantics.
pub(crate) fn open_for_test(db_path: &str) -> Result<Connection> {
    open(db_path)
}

pub(crate) fn now_secs_pub() -> i64 {
    now_secs()
}

pub(crate) fn new_id_pub() -> String {
    new_id()
}

fn now_secs() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn new_id() -> String {
    uuid::Uuid::now_v7().to_string()
}

/// Create a realm. Returns the freshly-minted Realm with an assigned UUID-v7 id.
pub fn create(
    db_path: &str,
    name: &str,
    issuer_url: &str,
    gcp_binding: Option<serde_json::Value>,
) -> Result<Realm> {
    let conn = open(db_path)?;
    let realm = Realm {
        id: new_id(),
        name: name.to_string(),
        issuer_url: issuer_url.to_string(),
        gcp_binding,
        created_at: now_secs(),
        updated_at: now_secs(),
    };
    let gcp_json = realm
        .gcp_binding
        .as_ref()
        .map(|v| v.to_string());
    conn.execute(
        "INSERT INTO realms(id,name,issuer_url,gcp_binding,created_at,updated_at)
         VALUES(?1,?2,?3,?4,?5,?6)",
        params![
            realm.id,
            realm.name,
            realm.issuer_url,
            gcp_json,
            realm.created_at,
            realm.updated_at,
        ],
    )
    .with_context(|| format!("realm.create({name})"))?;

    seed_roles(&conn, &realm.id)?;

    audit::emit(
        "realm.create",
        &serde_json::json!({"id": realm.id, "name": realm.name, "issuer": realm.issuer_url}),
    );
    Ok(realm)
}

/// Look up a realm by id (uuid) or name. Returns None on miss.
pub fn get(db_path: &str, id_or_name: &str) -> Result<Option<Realm>> {
    let conn = open(db_path)?;
    let mut stmt = conn.prepare(
        "SELECT id,name,issuer_url,gcp_binding,created_at,updated_at FROM realms WHERE id=?1 OR name=?1 LIMIT 1",
    )?;
    let row = stmt
        .query_row(params![id_or_name], realm_from_row)
        .optional()
        .context("realm.get")?;
    Ok(row)
}

/// List all realms.
pub fn list(db_path: &str) -> Result<Vec<Realm>> {
    let conn = open(db_path)?;
    let mut stmt = conn.prepare(
        "SELECT id,name,issuer_url,gcp_binding,created_at,updated_at FROM realms ORDER BY created_at",
    )?;
    let rows = stmt.query_map([], realm_from_row)?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r?);
    }
    Ok(out)
}

/// Delete a realm by id. Cascades to users/groups/roles via FK ON DELETE CASCADE.
/// Returns true if the row existed.
pub fn delete(db_path: &str, id: &str) -> Result<bool> {
    let conn = open(db_path)?;
    let n = conn.execute("DELETE FROM realms WHERE id=?1", params![id])?;
    if n > 0 {
        audit::emit("realm.delete", &serde_json::json!({"id": id}));
    }
    Ok(n > 0)
}

fn realm_from_row(row: &rusqlite::Row) -> rusqlite::Result<Realm> {
    let gcp_str: Option<String> = row.get(3)?;
    let gcp_binding = gcp_str
        .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok());
    Ok(Realm {
        id: row.get(0)?,
        name: row.get(1)?,
        issuer_url: row.get(2)?,
        gcp_binding,
        created_at: row.get(4)?,
        updated_at: row.get(5)?,
    })
}

/// Seed the canonical c3i-{admin,operator,viewer,service} roles for a freshly-
/// created realm. The layer_mask preserves the fractal-layer mapping defined in
/// `auth/rbac.gleam:80-101` so the typed Gleam ADT stays the source of truth.
///
/// SC-IAM-003 — exhaustive role mapping.
/// SC-IAM-004 — c3i-admin requires MFA for L0 ops.
fn seed_roles(conn: &Connection, realm_id: &str) -> Result<()> {
    // bit i set = access to layer Li (L0..L7)
    const ADMIN_MASK: i64 = 0b1111_1111;     // L0-L7 (255)
    const OPERATOR_MASK: i64 = 0b1111_1110;  // L1-L7 (254)
    const VIEWER_MASK: i64 = 0b1111_0000;    // L4-L7 (240)
    const SERVICE_MASK: i64 = 0b0111_1000;   // L3-L6 (120)

    let now = now_secs();
    let seed = [
        ("c3i-admin", ADMIN_MASK, true),
        ("c3i-operator", OPERATOR_MASK, false),
        ("c3i-viewer", VIEWER_MASK, false),
        ("c3i-service", SERVICE_MASK, false),
    ];
    for (name, mask, requires_mfa) in seed {
        conn.execute(
            "INSERT INTO roles(id,realm_id,name,layer_mask,requires_mfa,created_at)
             VALUES(?1,?2,?3,?4,?5,?6)",
            params![new_id(), realm_id, name, mask, requires_mfa as i64, now],
        )
        .with_context(|| format!("seed_roles({name})"))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_db() -> (tempfile::TempDir, String) {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("ferriskey.db").to_str().unwrap().to_string();
        crate::db::init(&path).unwrap();
        (tmp, path)
    }

    #[test]
    fn create_then_get() {
        let (_tmp, path) = fresh_db();
        let r = create(&path, "c3i", "https://vm-1.tail55d152.ts.net:4100/realms/c3i", None).unwrap();
        let got = get(&path, "c3i").unwrap().expect("found");
        assert_eq!(got.id, r.id);
        assert_eq!(got.name, "c3i");
    }

    #[test]
    fn list_returns_created() {
        let (_tmp, path) = fresh_db();
        create(&path, "c3i", "https://x", None).unwrap();
        create(&path, "c3i-staging", "https://y", None).unwrap();
        let all = list(&path).unwrap();
        assert_eq!(all.len(), 2);
    }

    #[test]
    fn delete_returns_existed() {
        let (_tmp, path) = fresh_db();
        let r = create(&path, "c3i", "https://x", None).unwrap();
        assert!(delete(&path, &r.id).unwrap());
        assert!(!delete(&path, &r.id).unwrap());
    }

    #[test]
    fn seed_roles_inserts_four() {
        let (_tmp, path) = fresh_db();
        let r = create(&path, "c3i", "https://x", None).unwrap();
        let conn = open(&path).unwrap();
        let n: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM roles WHERE realm_id=?1",
                params![r.id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(n, 4);
    }

    #[test]
    fn admin_role_has_full_layer_mask() {
        let (_tmp, path) = fresh_db();
        let r = create(&path, "c3i", "https://x", None).unwrap();
        let conn = open(&path).unwrap();
        let mask: i64 = conn
            .query_row(
                "SELECT layer_mask FROM roles WHERE realm_id=?1 AND name='c3i-admin'",
                params![r.id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(mask, 0b1111_1111);
    }
}
