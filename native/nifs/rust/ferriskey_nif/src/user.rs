//! User CRUD NIFs (6 of 18 in Phase 2).
//!
//! Phase 2 surface:
//!   user_create(realm_id, username, email, password_opt) -> User
//!   user_get(id_or_sub)                                  -> {found, user}
//!   user_list(realm_id)                                  -> [User]
//!   user_update(id, fields_json)                         -> User
//!   user_delete(id)                                      -> {existed}
//!   user_password_verify(id, password)                   -> {ok, mfa_required}
//!
//! - Passwords stored as bcrypt cost-12 (SC-FERRISKEY-NIF-006).
//! - `attrs` column carries SCIM 2.0 extensions (RFC 7643 §3.3) for
//!   round-tripping unknown SCIM attributes (Phase 5).
//! - Soft-delete via the User.status state machine is a Phase 5+ concern;
//!   Phase 2 ships hard-delete with FK-cascade to user_roles + group_members.

use anyhow::{Context, Result};
use bcrypt::{hash, verify, DEFAULT_COST};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::audit;
use crate::realm; // shared open() / now_secs() / new_id()

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub realm_id: String,
    pub sub: String,
    pub username: String,
    pub email: String,
    pub mfa_enrolled: bool,
    pub attrs: serde_json::Value,
    pub created_at: i64,
    pub updated_at: i64,
}

/// Fields a `user_update` NIF call may set. Any field omitted is unchanged.
#[derive(Debug, Default, Deserialize)]
pub struct UserUpdate {
    pub email: Option<String>,
    pub username: Option<String>,
    pub mfa_enrolled: Option<bool>,
    pub password: Option<String>,
    pub attrs: Option<serde_json::Value>,
}

/// Result of `user_password_verify`.
#[derive(Debug, Serialize)]
pub struct PasswordVerify {
    pub ok: bool,
    /// True iff the user has any role in the realm with `requires_mfa = 1`
    /// AND the user has not yet enrolled MFA (so the caller MUST step up).
    pub mfa_required: bool,
}

pub fn create(
    db_path: &str,
    realm_id: &str,
    username: &str,
    email: &str,
    password: Option<&str>,
) -> Result<User> {
    let conn = realm::open_for_test(db_path)?;
    let now = realm::now_secs_pub();
    let id = realm::new_id_pub();
    let sub = id.clone(); // OIDC subject = stable id (UUIDv7)
    let pwd_hash = match password {
        Some(p) => Some(hash(p, DEFAULT_COST).context("user.create: bcrypt")?),
        None => None,
    };
    conn.execute(
        "INSERT INTO users(id,realm_id,sub,username,email,password_hash,mfa_enrolled,attrs,created_at,updated_at)
         VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)",
        params![
            id,
            realm_id,
            sub,
            username,
            email,
            pwd_hash,
            0_i64,
            "{}",
            now,
            now,
        ],
    )
    .with_context(|| format!("user.create({username})"))?;
    audit::emit(
        "user.create",
        &serde_json::json!({"id": id, "realm_id": realm_id, "username": username}),
    );
    Ok(User {
        id,
        realm_id: realm_id.to_string(),
        sub,
        username: username.to_string(),
        email: email.to_string(),
        mfa_enrolled: false,
        attrs: serde_json::json!({}),
        created_at: now,
        updated_at: now,
    })
}

pub fn get(db_path: &str, id_or_sub: &str) -> Result<Option<User>> {
    let conn = realm::open_for_test(db_path)?;
    let mut stmt = conn.prepare(
        "SELECT id,realm_id,sub,username,email,mfa_enrolled,attrs,created_at,updated_at
         FROM users WHERE id=?1 OR sub=?1 LIMIT 1",
    )?;
    Ok(stmt
        .query_row(params![id_or_sub], user_from_row)
        .optional()
        .context("user.get")?)
}

pub fn list(db_path: &str, realm_id: &str) -> Result<Vec<User>> {
    let conn = realm::open_for_test(db_path)?;
    let mut stmt = conn.prepare(
        "SELECT id,realm_id,sub,username,email,mfa_enrolled,attrs,created_at,updated_at
         FROM users WHERE realm_id=?1 ORDER BY created_at",
    )?;
    let rows = stmt.query_map(params![realm_id], user_from_row)?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r?);
    }
    Ok(out)
}

/// SCIM-filter-driven user list. Parses the SCIM 2.0 filter string into a
/// typed AST, emits parameterized SQL via the FMEA #4-safe emitter, and
/// executes through rusqlite's positional parameter binding — never
/// concatenates user-supplied bytes into the SQL string.
///
/// This is the end-to-end proof that the SCIM defense works at every
/// layer: parse → typed AST → typed SqlFragment → rusqlite bound exec.
///
/// SC-GCP-IAM-004 (RFC 7644 conformant filter), FMEA #4 mitigation.
pub fn list_filtered(
    db_path: &str,
    realm_id: &str,
    scim_filter: &str,
) -> Result<Vec<User>> {
    use rusqlite::types::ToSql;
    let ast = crate::scim::parse_filter(scim_filter)
        .map_err(|e| anyhow::anyhow!("filter parse: {e}"))?;
    let frag = crate::scim::user_filter_to_sql(&ast)
        .map_err(|e| anyhow::anyhow!("filter emit: {e}"))?;
    let conn = realm::open_for_test(db_path)?;
    // SCIM frag uses ?1..?N. Append realm_id at ?(N+1) to keep numbering
    // consistent — rusqlite binds positional `?` and `?N` together by index
    // so ordering is critical.
    let realm_idx = frag.params.len() + 1;
    let sql = format!(
        "SELECT id,realm_id,sub,username,email,mfa_enrolled,attrs,created_at,updated_at
         FROM users WHERE ({}) AND realm_id = ?{} ORDER BY created_at",
        frag.sql, realm_idx,
    );
    let mut stmt = conn.prepare(&sql)?;
    let mut owned: Vec<Box<dyn ToSql>> = Vec::with_capacity(frag.params.len() + 1);
    for p in &frag.params {
        match p {
            crate::scim::SqlValue::Str(s) => owned.push(Box::new(s.clone())),
            crate::scim::SqlValue::Int(i) => owned.push(Box::new(*i)),
            crate::scim::SqlValue::Bool(b) => owned.push(Box::new(*b)),
            crate::scim::SqlValue::Null => owned.push(Box::new(rusqlite::types::Null)),
        }
    }
    owned.push(Box::new(realm_id.to_string()));
    let bindings: Vec<&dyn ToSql> = owned.iter().map(|b| &**b).collect();
    let rows = stmt.query_map(rusqlite::params_from_iter(bindings.iter()), user_from_row)?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r?);
    }
    Ok(out)
}

pub fn update(db_path: &str, id: &str, upd: UserUpdate) -> Result<Option<User>> {
    let conn = realm::open_for_test(db_path)?;
    let now = realm::now_secs_pub();
    if let Some(email) = &upd.email {
        conn.execute(
            "UPDATE users SET email=?1, updated_at=?2 WHERE id=?3",
            params![email, now, id],
        )?;
    }
    if let Some(username) = &upd.username {
        conn.execute(
            "UPDATE users SET username=?1, updated_at=?2 WHERE id=?3",
            params![username, now, id],
        )?;
    }
    if let Some(mfa) = upd.mfa_enrolled {
        conn.execute(
            "UPDATE users SET mfa_enrolled=?1, updated_at=?2 WHERE id=?3",
            params![mfa as i64, now, id],
        )?;
    }
    if let Some(pwd) = &upd.password {
        let h = hash(pwd, DEFAULT_COST).context("user.update: bcrypt")?;
        conn.execute(
            "UPDATE users SET password_hash=?1, updated_at=?2 WHERE id=?3",
            params![h, now, id],
        )?;
    }
    if let Some(attrs) = &upd.attrs {
        conn.execute(
            "UPDATE users SET attrs=?1, updated_at=?2 WHERE id=?3",
            params![attrs.to_string(), now, id],
        )?;
    }
    audit::emit("user.update", &serde_json::json!({"id": id}));
    get(db_path, id)
}

pub fn delete(db_path: &str, id: &str) -> Result<bool> {
    let conn = realm::open_for_test(db_path)?;
    let n = conn.execute("DELETE FROM users WHERE id=?1", params![id])?;
    if n > 0 {
        audit::emit("user.delete", &serde_json::json!({"id": id}));
    }
    Ok(n > 0)
}

/// Verify password and report whether the user must additionally step up to MFA
/// to access any of their granted roles. Hot path uses `bcrypt::verify` —
/// constant-time at the bcrypt level.
pub fn password_verify(db_path: &str, id: &str, password: &str) -> Result<PasswordVerify> {
    let conn = realm::open_for_test(db_path)?;
    let row: Option<(Option<String>, i64)> = conn
        .query_row(
            "SELECT password_hash, mfa_enrolled FROM users WHERE id=?1 OR sub=?1",
            params![id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?;
    let (hash_opt, mfa_enrolled) = match row {
        None => return Ok(PasswordVerify { ok: false, mfa_required: false }),
        Some(t) => t,
    };
    let hash_str = match hash_opt {
        None => return Ok(PasswordVerify { ok: false, mfa_required: false }),
        Some(h) => h,
    };
    let ok = verify(password, &hash_str).unwrap_or(false);

    // SC-IAM-004 — any granted role with requires_mfa=1 AND user not enrolled
    // means caller must step up before being granted L0 access.
    let needs_mfa: i64 = conn.query_row(
        "SELECT COALESCE(MAX(r.requires_mfa), 0)
         FROM user_roles ur JOIN roles r ON r.id = ur.role_id
         WHERE ur.user_id = ?1",
        params![id],
        |row| row.get(0),
    ).unwrap_or(0);
    let mfa_required = ok && needs_mfa == 1 && mfa_enrolled == 0;
    audit::emit(
        "user.password_verify",
        &serde_json::json!({"id": id, "ok": ok, "mfa_required": mfa_required}),
    );
    Ok(PasswordVerify { ok, mfa_required })
}

fn user_from_row(row: &rusqlite::Row) -> rusqlite::Result<User> {
    let attrs_str: String = row.get(6)?;
    let attrs: serde_json::Value =
        serde_json::from_str(&attrs_str).unwrap_or_else(|_| serde_json::json!({}));
    let mfa_int: i64 = row.get(5)?;
    Ok(User {
        id: row.get(0)?,
        realm_id: row.get(1)?,
        sub: row.get(2)?,
        username: row.get(3)?,
        email: row.get(4)?,
        mfa_enrolled: mfa_int != 0,
        attrs,
        created_at: row.get(7)?,
        updated_at: row.get(8)?,
    })
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
    fn create_and_get_by_id_and_sub() {
        let (_tmp, path, realm_id) = fresh_realm();
        let u = create(&path, &realm_id, "alice", "alice@example.com", Some("s3cret")).unwrap();
        let by_id = get(&path, &u.id).unwrap().unwrap();
        let by_sub = get(&path, &u.sub).unwrap().unwrap();
        assert_eq!(by_id.username, "alice");
        assert_eq!(by_sub.id, u.id);
    }

    #[test]
    fn list_filters_by_realm() {
        let (_tmp, path, r1) = fresh_realm();
        let r2 = realm::create(&path, "staging", "https://y", None).unwrap();
        create(&path, &r1, "alice", "a@x", Some("p")).unwrap();
        create(&path, &r1, "bob", "b@x", None).unwrap();
        create(&path, &r2.id, "carol", "c@x", Some("p")).unwrap();
        assert_eq!(list(&path, &r1).unwrap().len(), 2);
        assert_eq!(list(&path, &r2.id).unwrap().len(), 1);
    }

    #[test]
    fn password_verify_hits_and_misses() {
        let (_tmp, path, realm_id) = fresh_realm();
        let u = create(&path, &realm_id, "alice", "a@x", Some("s3cret")).unwrap();
        assert!(password_verify(&path, &u.id, "s3cret").unwrap().ok);
        assert!(!password_verify(&path, &u.id, "wrong").unwrap().ok);
    }

    #[test]
    fn password_verify_returns_false_for_missing_user() {
        let (_tmp, path, _realm_id) = fresh_realm();
        assert!(!password_verify(&path, "nonexistent", "x").unwrap().ok);
    }

    #[test]
    fn password_verify_returns_false_when_no_password() {
        let (_tmp, path, realm_id) = fresh_realm();
        let u = create(&path, &realm_id, "service", "s@x", None).unwrap();
        assert!(!password_verify(&path, &u.id, "anything").unwrap().ok);
    }

    #[test]
    fn update_email_and_mfa() {
        let (_tmp, path, realm_id) = fresh_realm();
        let u = create(&path, &realm_id, "alice", "a@x", Some("p")).unwrap();
        let upd = UserUpdate {
            email: Some("alice@new.com".to_string()),
            mfa_enrolled: Some(true),
            ..Default::default()
        };
        let after = update(&path, &u.id, upd).unwrap().unwrap();
        assert_eq!(after.email, "alice@new.com");
        assert!(after.mfa_enrolled);
    }

    #[test]
    fn list_filtered_eq_username_returns_only_match() {
        let (_tmp, path, realm_id) = fresh_realm();
        let _ = create(&path, &realm_id, "alice", "a@x", Some("p")).unwrap();
        let _ = create(&path, &realm_id, "bob", "b@x", Some("p")).unwrap();
        let _ = create(&path, &realm_id, "carol", "c@x", Some("p")).unwrap();
        let result = list_filtered(&path, &realm_id, r#"userName eq "bob""#).unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].username, "bob");
    }

    #[test]
    fn list_filtered_co_substring_matches_multiple() {
        let (_tmp, path, realm_id) = fresh_realm();
        create(&path, &realm_id, "alice", "a@example.com", Some("p")).unwrap();
        create(&path, &realm_id, "alex", "alex@example.com", Some("p")).unwrap();
        create(&path, &realm_id, "bob", "b@other.com", Some("p")).unwrap();
        let r = list_filtered(&path, &realm_id, r#"email co "example.com""#).unwrap();
        assert_eq!(r.len(), 2);
    }

    #[test]
    fn list_filtered_and_or_combinator() {
        let (_tmp, path, realm_id) = fresh_realm();
        create(&path, &realm_id, "alice", "a@example.com", Some("p")).unwrap();
        create(&path, &realm_id, "bob", "b@example.com", Some("p")).unwrap();
        create(&path, &realm_id, "carol", "c@other.com", Some("p")).unwrap();
        let r = list_filtered(
            &path,
            &realm_id,
            r#"email co "example.com" and userName ne "bob""#,
        )
        .unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].username, "alice");
    }

    #[test]
    fn list_filtered_isolates_injection_payload_in_param() {
        // The keystone end-to-end proof: even if the user supplies a SQL-
        // injection payload as the filter VALUE, it lands as a bound param
        // and the underlying users table is not damaged. After running
        // the filter (which matches no rows), all 3 users still exist.
        let (_tmp, path, realm_id) = fresh_realm();
        create(&path, &realm_id, "alice", "a@x", Some("p")).unwrap();
        create(&path, &realm_id, "bob", "b@x", Some("p")).unwrap();
        create(&path, &realm_id, "carol", "c@x", Some("p")).unwrap();
        // Run a filter whose value is an injection payload.
        let r = list_filtered(
            &path,
            &realm_id,
            r#"userName eq "x'; DROP TABLE users; --""#,
        )
        .unwrap();
        // The malicious value matches no user → empty result.
        assert_eq!(r.len(), 0);
        // Verify the table survived — list all users.
        let all = list(&path, &realm_id).unwrap();
        assert_eq!(all.len(), 3, "table MUST survive injection attempt");
    }

    #[test]
    fn list_filtered_rejects_unknown_attribute() {
        let (_tmp, path, realm_id) = fresh_realm();
        let result = list_filtered(&path, &realm_id, r#"ssn eq "123""#);
        assert!(result.is_err());
    }

    #[test]
    fn delete_returns_existed_then_false() {
        let (_tmp, path, realm_id) = fresh_realm();
        let u = create(&path, &realm_id, "alice", "a@x", Some("p")).unwrap();
        assert!(delete(&path, &u.id).unwrap());
        assert!(!delete(&path, &u.id).unwrap());
    }
}
