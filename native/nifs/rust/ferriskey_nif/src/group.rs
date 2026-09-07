//! Group CRUD NIFs (4 of 18 in Phase 2).
//!
//! Phase 2 surface:
//!   group_create(realm_id, name, display_name)  -> Group
//!   group_list(realm_id)                        -> [Group]
//!   group_add_member(group_id, user_id)         -> {added}
//!   group_remove_member(group_id, user_id)      -> {existed}
//!
//! Group state participates in SCIM 2.0 outbound push (Phase 5) and Cloud
//! Identity Groups API mirroring (Phase 4 Bridge 4).

use anyhow::{Context, Result};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::audit;
use crate::realm;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Group {
    pub id: String,
    pub realm_id: String,
    pub name: String,
    pub display_name: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

pub fn create(db_path: &str, realm_id: &str, name: &str, display_name: Option<&str>) -> Result<Group> {
    let conn = realm::open_for_test(db_path)?;
    let now = realm::now_secs_pub();
    let id = realm::new_id_pub();
    conn.execute(
        "INSERT INTO groups(id,realm_id,name,display_name,attrs,created_at,updated_at)
         VALUES(?1,?2,?3,?4,'{}',?5,?6)",
        params![id, realm_id, name, display_name, now, now],
    )
    .with_context(|| format!("group.create({name})"))?;
    audit::emit(
        "group.create",
        &serde_json::json!({"id": id, "realm_id": realm_id, "name": name}),
    );
    Ok(Group {
        id,
        realm_id: realm_id.to_string(),
        name: name.to_string(),
        display_name: display_name.map(|s| s.to_string()),
        created_at: now,
        updated_at: now,
    })
}

pub fn list(db_path: &str, realm_id: &str) -> Result<Vec<Group>> {
    let conn = realm::open_for_test(db_path)?;
    let mut stmt = conn.prepare(
        "SELECT id,realm_id,name,display_name,created_at,updated_at
         FROM groups WHERE realm_id=?1 ORDER BY created_at",
    )?;
    let rows = stmt.query_map(params![realm_id], |r| {
        Ok(Group {
            id: r.get(0)?,
            realm_id: r.get(1)?,
            name: r.get(2)?,
            display_name: r.get(3)?,
            created_at: r.get(4)?,
            updated_at: r.get(5)?,
        })
    })?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r?);
    }
    Ok(out)
}

/// Add user to group. Idempotent — re-adding returns `added=false`.
pub fn add_member(db_path: &str, group_id: &str, user_id: &str) -> Result<bool> {
    let conn = realm::open_for_test(db_path)?;
    let already: Option<i64> = conn
        .query_row(
            "SELECT 1 FROM group_members WHERE group_id=?1 AND user_id=?2",
            params![group_id, user_id],
            |r| r.get(0),
        )
        .optional()?;
    if already.is_some() {
        return Ok(false);
    }
    let now = realm::now_secs_pub();
    conn.execute(
        "INSERT INTO group_members(group_id,user_id,added_at) VALUES(?1,?2,?3)",
        params![group_id, user_id, now],
    )?;
    audit::emit(
        "group.add_member",
        &serde_json::json!({"group_id": group_id, "user_id": user_id}),
    );
    Ok(true)
}

pub fn remove_member(db_path: &str, group_id: &str, user_id: &str) -> Result<bool> {
    let conn = realm::open_for_test(db_path)?;
    let n = conn.execute(
        "DELETE FROM group_members WHERE group_id=?1 AND user_id=?2",
        params![group_id, user_id],
    )?;
    if n > 0 {
        audit::emit(
            "group.remove_member",
            &serde_json::json!({"group_id": group_id, "user_id": user_id}),
        );
    }
    Ok(n > 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_realm() -> (tempfile::TempDir, String, String) {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("ferriskey.db").to_str().unwrap().to_string();
        crate::db::init(&path).unwrap();
        let r = realm::create(&path, "c3i", "https://x", None).unwrap();
        (tmp, path, r.id)
    }

    #[test]
    fn create_and_list() {
        let (_tmp, path, realm_id) = fresh_realm();
        let _ = create(&path, &realm_id, "engineering", Some("Engineering")).unwrap();
        let _ = create(&path, &realm_id, "ops", None).unwrap();
        assert_eq!(list(&path, &realm_id).unwrap().len(), 2);
    }

    #[test]
    fn add_member_is_idempotent() {
        let (_tmp, path, realm_id) = fresh_realm();
        let g = create(&path, &realm_id, "eng", None).unwrap();
        let u = crate::user::create(&path, &realm_id, "alice", "a@x", Some("p")).unwrap();
        assert!(add_member(&path, &g.id, &u.id).unwrap());
        // Second add returns false (already a member, no audit row)
        assert!(!add_member(&path, &g.id, &u.id).unwrap());
    }

    #[test]
    fn remove_member_returns_existed() {
        let (_tmp, path, realm_id) = fresh_realm();
        let g = create(&path, &realm_id, "eng", None).unwrap();
        let u = crate::user::create(&path, &realm_id, "alice", "a@x", Some("p")).unwrap();
        add_member(&path, &g.id, &u.id).unwrap();
        assert!(remove_member(&path, &g.id, &u.id).unwrap());
        assert!(!remove_member(&path, &g.id, &u.id).unwrap());
    }
}
