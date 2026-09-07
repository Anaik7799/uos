//! Role CRUD beyond the seeded c3i-* set (4 of 18 in Phase 2).
//!
//! Phase 2 surface:
//!   role_create(realm_id, name, layer_mask, requires_mfa) -> Role
//!   role_list(realm_id)                                   -> [Role]   (incl. seeded 4)
//!   role_assign(user_id, role_id)                         -> {assigned}
//!   role_revoke(user_id, role_id)                         -> {existed}
//!
//! `role_create` is for tenancy-specific roles (e.g. `c3i-billing-reader`).
//! It MUST NOT replace the four seeded roles — their layer_mask invariants
//! are the L0-L7 mapping pinned by SC-IAM-003 and validated by
//! `realm::tests::admin_role_has_full_layer_mask`.

use anyhow::{Context, Result};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::audit;
use crate::realm;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Role {
    pub id: String,
    pub realm_id: String,
    pub name: String,
    /// 8-bit fractal-layer mask. Bit `i` set ⇒ access to layer L_i.
    pub layer_mask: i64,
    pub requires_mfa: bool,
    pub created_at: i64,
}

pub fn create(
    db_path: &str,
    realm_id: &str,
    name: &str,
    layer_mask: i64,
    requires_mfa: bool,
) -> Result<Role> {
    let conn = realm::open_for_test(db_path)?;
    let now = realm::now_secs_pub();
    let id = realm::new_id_pub();
    conn.execute(
        "INSERT INTO roles(id,realm_id,name,layer_mask,requires_mfa,created_at)
         VALUES(?1,?2,?3,?4,?5,?6)",
        params![id, realm_id, name, layer_mask, requires_mfa as i64, now],
    )
    .with_context(|| format!("role.create({name})"))?;
    audit::emit(
        "role.create",
        &serde_json::json!({"id": id, "realm_id": realm_id, "name": name, "mask": layer_mask}),
    );
    Ok(Role {
        id,
        realm_id: realm_id.to_string(),
        name: name.to_string(),
        layer_mask,
        requires_mfa,
        created_at: now,
    })
}

pub fn list(db_path: &str, realm_id: &str) -> Result<Vec<Role>> {
    let conn = realm::open_for_test(db_path)?;
    let mut stmt = conn.prepare(
        "SELECT id,realm_id,name,layer_mask,requires_mfa,created_at
         FROM roles WHERE realm_id=?1 ORDER BY name",
    )?;
    let rows = stmt.query_map(params![realm_id], |r| {
        let mfa: i64 = r.get(4)?;
        Ok(Role {
            id: r.get(0)?,
            realm_id: r.get(1)?,
            name: r.get(2)?,
            layer_mask: r.get(3)?,
            requires_mfa: mfa != 0,
            created_at: r.get(5)?,
        })
    })?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r?);
    }
    Ok(out)
}

/// Grant a role to a user. Idempotent. Audit-logged. The `granted_by`
/// optional caller principal is captured for SC-IAM-006 audit trails.
pub fn assign(db_path: &str, user_id: &str, role_id: &str, granted_by: Option<&str>) -> Result<bool> {
    let conn = realm::open_for_test(db_path)?;
    let already: Option<i64> = conn
        .query_row(
            "SELECT 1 FROM user_roles WHERE user_id=?1 AND role_id=?2",
            params![user_id, role_id],
            |r| r.get(0),
        )
        .optional()?;
    if already.is_some() {
        return Ok(false);
    }
    let now = realm::now_secs_pub();
    conn.execute(
        "INSERT INTO user_roles(user_id,role_id,granted_at,granted_by)
         VALUES(?1,?2,?3,?4)",
        params![user_id, role_id, now, granted_by],
    )?;
    audit::emit(
        "role.assign",
        &serde_json::json!({
            "user_id": user_id,
            "role_id": role_id,
            "granted_by": granted_by,
        }),
    );
    Ok(true)
}

pub fn revoke(db_path: &str, user_id: &str, role_id: &str) -> Result<bool> {
    let conn = realm::open_for_test(db_path)?;
    let n = conn.execute(
        "DELETE FROM user_roles WHERE user_id=?1 AND role_id=?2",
        params![user_id, role_id],
    )?;
    if n > 0 {
        audit::emit(
            "role.revoke",
            &serde_json::json!({"user_id": user_id, "role_id": role_id}),
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
    fn list_includes_seeded_four() {
        let (_tmp, path, realm_id) = fresh_realm();
        let names: Vec<String> = list(&path, &realm_id).unwrap().into_iter().map(|r| r.name).collect();
        assert!(names.contains(&"c3i-admin".to_string()));
        assert!(names.contains(&"c3i-operator".to_string()));
        assert!(names.contains(&"c3i-viewer".to_string()));
        assert!(names.contains(&"c3i-service".to_string()));
    }

    #[test]
    fn create_custom_role() {
        let (_tmp, path, realm_id) = fresh_realm();
        // L4-L6 only, no MFA
        let mask = 0b0111_0000;
        let r = create(&path, &realm_id, "c3i-billing-reader", mask, false).unwrap();
        assert_eq!(r.layer_mask, mask);
        assert!(!r.requires_mfa);
        assert_eq!(list(&path, &realm_id).unwrap().len(), 5);
    }

    #[test]
    fn assign_then_revoke_idempotent() {
        let (_tmp, path, realm_id) = fresh_realm();
        let u = crate::user::create(&path, &realm_id, "alice", "a@x", Some("p")).unwrap();
        let admin_role = list(&path, &realm_id).unwrap()
            .into_iter()
            .find(|r| r.name == "c3i-admin")
            .unwrap();
        assert!(assign(&path, &u.id, &admin_role.id, Some("system")).unwrap());
        assert!(!assign(&path, &u.id, &admin_role.id, Some("system")).unwrap());
        assert!(revoke(&path, &u.id, &admin_role.id).unwrap());
        assert!(!revoke(&path, &u.id, &admin_role.id).unwrap());
    }

    #[test]
    fn assigning_admin_role_drives_password_verify_mfa_required() {
        // Cross-module wiring: assigning c3i-admin (requires_mfa=1) to a
        // user whose mfa_enrolled=false must trigger mfa_required=true on
        // password verify. This is the SC-IAM-004 pattern.
        let (_tmp, path, realm_id) = fresh_realm();
        let u = crate::user::create(&path, &realm_id, "alice", "a@x", Some("s3cret")).unwrap();
        let admin_role = list(&path, &realm_id).unwrap()
            .into_iter()
            .find(|r| r.name == "c3i-admin")
            .unwrap();
        assign(&path, &u.id, &admin_role.id, Some("system")).unwrap();
        let pv = crate::user::password_verify(&path, &u.id, "s3cret").unwrap();
        assert!(pv.ok);
        assert!(pv.mfa_required, "c3i-admin requires MFA — SC-IAM-004");
    }
}
