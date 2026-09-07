//! # ferriskey_nif — Local-first IAM NIF for cepaf_gleam
//!
//! Embeds FerrisKey (vendored at `sub-projects/ferriskey-vendored/`) as a Rust
//! cdylib loaded into BEAM, providing in-process realm/user/group/role/token
//! management plus Google Cloud IAM federation (Workload Identity Federation,
//! STS token exchange, service-account impersonation, SCIM 2.0 inbound +
//! outbound, Admin SDK Directory, Cloud Identity Groups, IAM Recommender,
//! Policy Troubleshooter, Policy Analyzer, Organization Policy).
//!
//! ## Architecture
//!
//! ```text
//!   Wisp HTTP / Lustre / TUI
//!        │
//!   auth/ferriskey_nif.gleam (typed wrapper)
//!        │  (erlang :ferriskey_nif shim)
//!   ferriskey_nif (this crate, cdylib)
//!        ├── runtime.rs   — OnceCell<tokio::Runtime>
//!        ├── db.rs        — SQLite WAL r2d2 pool, 8 tables
//!        ├── audit.rs     — OTel span → Zenoh `indrajaal/l0/iam/**`
//!        ├── (Phase 2)  realm/user/group/role.rs
//!        ├── (Phase 3)  token/jwks_cache.rs
//!        ├── (Phase 4)  gcp_sts/gcp_iam/gcp_directory.rs
//!        ├── (Phase 5)  scim.rs
//!        └── (Phase 8)  vault_bridge.rs
//! ```
//!
//! ## STAMP
//! - SC-FERRISKEY-NIF-001..010 (NIF lifecycle, runtime, JWKS cache, audit, WAL,
//!   key rotation, panic isolation, vault-backed signing keys)
//! - SC-GCP-IAM-001..020 (WIF, STS, allow/deny policies, Recommender,
//!   Policy Troubleshooter, Org Policy, region pinning, basic-role ban)
//! - SC-VAULT-001..025 (consumed via vault_bridge — never plaintext on disk)
//! - SC-AUTH-001..008 / SC-IAM-001..008 (extended to NIF-mode)
//! - SC-WIRE-001..007 (wiring guard mandates same-commit updates to
//!   wiring_guard.gleam for any new Model field)
//! - SC-CPIG-011 (parallel sub-agent dispatch for >2 independent tracks)

mod runtime;
mod db;
mod audit;
mod realm;
mod user;
mod group;
mod role;
mod token;
mod jwks;
mod gcp_sts;
mod gcp_iam;
mod scim;

use rustler::{Encoder, Env, NifResult, Term};

mod atoms {
    rustler::atoms! { ok, error, ferriskey_nif_v0_1_0 }
}

/// Liveness probe — confirms the NIF loaded, runtime is bootable, DB pool is
/// reachable. Returns `{:ok, "ferriskey_nif_v0_1_0"}` on success.
///
/// SC-FERRISKEY-NIF-001 (NIF cdylib loads on BEAM start).
#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_ping<'a>(env: Env<'a>) -> NifResult<Term<'a>> {
    // Eagerly initialize the runtime so a startup misconfiguration surfaces
    // here rather than on the first GCP STS or SCIM call.
    let _rt = runtime::get();
    let resp = serde_json::json!({
        "ok": true,
        "version": "0.1.0",
        "phase": 1,
        "subsystems": {
            "runtime": "initialized",
            "db": "deferred-to-phase-2",
            "audit": "stub",
        },
    })
    .to_string();
    Ok((atoms::ok(), resp).encode(env))
}

/// Initialize the SQLite schema (idempotent migrations). Phase 1 stub —
/// returns `{:ok, "schema_v1"}` after applying migrations.
///
/// SC-FERRISKEY-NIF-007 (WAL mode), SC-FERRISKEY-NIF-006 (audit emission).
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_db_init<'a>(env: Env<'a>, db_path: String) -> NifResult<Term<'a>> {
    match db::init(&db_path) {
        Ok(version) => {
            audit::emit("db.init", &serde_json::json!({"path": db_path, "version": version}));
            let resp = serde_json::json!({"ok": true, "schema_version": version}).to_string();
            Ok((atoms::ok(), resp).encode(env))
        }
        Err(e) => {
            let resp =
                serde_json::json!({"ok": false, "error": e.to_string()}).to_string();
            Ok((atoms::error(), resp).encode(env))
        }
    }
}

// ---------------------------------------------------------------------------
// Phase 2 — realm CRUD (4 of 18 NIFs)
// ---------------------------------------------------------------------------

/// Create a realm. Returns the freshly-minted Realm as JSON.
/// Args: db_path, name, issuer_url, gcp_binding_json ("" for none).
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_realm_create<'a>(
    env: Env<'a>,
    db_path: String,
    name: String,
    issuer_url: String,
    gcp_binding_json: String,
) -> NifResult<Term<'a>> {
    let gcp_binding = if gcp_binding_json.trim().is_empty() {
        None
    } else {
        serde_json::from_str(&gcp_binding_json).ok()
    };
    match realm::create(&db_path, &name, &issuer_url, gcp_binding) {
        Ok(r) => json_ok(env, &r),
        Err(e) => json_err(env, &e.to_string()),
    }
}

/// Look up a realm by id or name. Returns `{"found":bool,"realm":...}`.
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_realm_get<'a>(
    env: Env<'a>,
    db_path: String,
    id_or_name: String,
) -> NifResult<Term<'a>> {
    match realm::get(&db_path, &id_or_name) {
        Ok(Some(r)) => json_ok(env, &serde_json::json!({"found": true, "realm": r})),
        Ok(None) => json_ok(env, &serde_json::json!({"found": false})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

/// List all realms. Returns `{"realms":[...]}`.
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_realm_list<'a>(env: Env<'a>, db_path: String) -> NifResult<Term<'a>> {
    match realm::list(&db_path) {
        Ok(rs) => json_ok(env, &serde_json::json!({"realms": rs})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

/// Delete a realm by id. Returns `{"existed":bool}`. Cascades to users/groups/roles.
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_realm_delete<'a>(
    env: Env<'a>,
    db_path: String,
    id: String,
) -> NifResult<Term<'a>> {
    match realm::delete(&db_path, &id) {
        Ok(existed) => json_ok(env, &serde_json::json!({"existed": existed})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

// ---------------------------------------------------------------------------
// Phase 2 — user CRUD (6 of 18 NIFs)
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_user_create<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
    username: String,
    email: String,
    password: String,
) -> NifResult<Term<'a>> {
    let pwd = if password.is_empty() { None } else { Some(password.as_str()) };
    match user::create(&db_path, &realm_id, &username, &email, pwd) {
        Ok(u) => json_ok(env, &u),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_user_get<'a>(
    env: Env<'a>,
    db_path: String,
    id_or_sub: String,
) -> NifResult<Term<'a>> {
    match user::get(&db_path, &id_or_sub) {
        Ok(Some(u)) => json_ok(env, &serde_json::json!({"found": true, "user": u})),
        Ok(None) => json_ok(env, &serde_json::json!({"found": false})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_user_list<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
) -> NifResult<Term<'a>> {
    match user::list(&db_path, &realm_id) {
        Ok(us) => json_ok(env, &serde_json::json!({"users": us})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_user_update<'a>(
    env: Env<'a>,
    db_path: String,
    id: String,
    fields_json: String,
) -> NifResult<Term<'a>> {
    let upd: user::UserUpdate = match serde_json::from_str(&fields_json) {
        Ok(u) => u,
        Err(e) => return json_err(env, &format!("decode_fields: {e}")),
    };
    match user::update(&db_path, &id, upd) {
        Ok(Some(u)) => json_ok(env, &u),
        Ok(None) => json_ok(env, &serde_json::json!({"found": false})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_user_delete<'a>(
    env: Env<'a>,
    db_path: String,
    id: String,
) -> NifResult<Term<'a>> {
    match user::delete(&db_path, &id) {
        Ok(existed) => json_ok(env, &serde_json::json!({"existed": existed})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

/// SCIM-filter-driven user list — end-to-end FMEA #4 defense at the BEAM
/// boundary. Parses an RFC 7644 filter string, emits parameterized SQL via
/// `scim::user_filter_to_sql`, executes through rusqlite's safe positional
/// binding. Unknown attributes return error rather than passing through.
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_user_list_filtered<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
    scim_filter: String,
) -> NifResult<Term<'a>> {
    match user::list_filtered(&db_path, &realm_id, &scim_filter) {
        Ok(users) => json_ok(env, &serde_json::json!({"users": users})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_user_password_verify<'a>(
    env: Env<'a>,
    db_path: String,
    id: String,
    password: String,
) -> NifResult<Term<'a>> {
    match user::password_verify(&db_path, &id, &password) {
        Ok(pv) => json_ok(env, &pv),
        Err(e) => json_err(env, &e.to_string()),
    }
}

// ---------------------------------------------------------------------------
// Phase 2 — group CRUD (4 of 18 NIFs)
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_group_create<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
    name: String,
    display_name: String,
) -> NifResult<Term<'a>> {
    let dn = if display_name.is_empty() { None } else { Some(display_name.as_str()) };
    match group::create(&db_path, &realm_id, &name, dn) {
        Ok(g) => json_ok(env, &g),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_group_list<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
) -> NifResult<Term<'a>> {
    match group::list(&db_path, &realm_id) {
        Ok(gs) => json_ok(env, &serde_json::json!({"groups": gs})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_group_add_member<'a>(
    env: Env<'a>,
    db_path: String,
    group_id: String,
    user_id: String,
) -> NifResult<Term<'a>> {
    match group::add_member(&db_path, &group_id, &user_id) {
        Ok(added) => json_ok(env, &serde_json::json!({"added": added})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_group_remove_member<'a>(
    env: Env<'a>,
    db_path: String,
    group_id: String,
    user_id: String,
) -> NifResult<Term<'a>> {
    match group::remove_member(&db_path, &group_id, &user_id) {
        Ok(existed) => json_ok(env, &serde_json::json!({"existed": existed})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

// ---------------------------------------------------------------------------
// Phase 2 — role grant/revoke + custom roles (4 of 18 NIFs)
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_role_create<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
    name: String,
    layer_mask: i64,
    requires_mfa: bool,
) -> NifResult<Term<'a>> {
    match role::create(&db_path, &realm_id, &name, layer_mask, requires_mfa) {
        Ok(r) => json_ok(env, &r),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_role_list<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
) -> NifResult<Term<'a>> {
    match role::list(&db_path, &realm_id) {
        Ok(rs) => json_ok(env, &serde_json::json!({"roles": rs})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_role_assign<'a>(
    env: Env<'a>,
    db_path: String,
    user_id: String,
    role_id: String,
    granted_by: String,
) -> NifResult<Term<'a>> {
    let gb = if granted_by.is_empty() { None } else { Some(granted_by.as_str()) };
    match role::assign(&db_path, &user_id, &role_id, gb) {
        Ok(assigned) => json_ok(env, &serde_json::json!({"assigned": assigned})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_role_revoke<'a>(
    env: Env<'a>,
    db_path: String,
    user_id: String,
    role_id: String,
) -> NifResult<Term<'a>> {
    match role::revoke(&db_path, &user_id, &role_id) {
        Ok(existed) => json_ok(env, &serde_json::json!({"existed": existed})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

// ---------------------------------------------------------------------------
// Phase 3 — token + JWKS (5 of 5 NIFs)
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_signing_key_rotate<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
    alg: String,
) -> NifResult<Term<'a>> {
    match token::rotate(&db_path, &realm_id, &alg) {
        Ok(r) => {
            jwks::invalidate(&realm_id);
            json_ok(env, &r)
        }
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_token_issue<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
    user_id: String,
    audience: String,
    scopes_csv: String,
    ttl_seconds: i64,
) -> NifResult<Term<'a>> {
    let scopes: Vec<String> = if scopes_csv.is_empty() {
        Vec::new()
    } else {
        scopes_csv.split(',').map(|s| s.trim().to_string()).collect()
    };
    match token::issue(&db_path, &realm_id, &user_id, &audience, &scopes, ttl_seconds) {
        Ok(t) => json_ok(env, &t),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_token_validate<'a>(
    env: Env<'a>,
    db_path: String,
    jwt: String,
) -> NifResult<Term<'a>> {
    match token::validate(&db_path, &jwt) {
        Ok(v) => json_ok(env, &v),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_jwks_publish<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
) -> NifResult<Term<'a>> {
    match jwks::publish(&db_path, &realm_id) {
        Ok(j) => json_ok(env, &serde_json::json!({"jwks_json": j})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_jwks_get_cached<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
) -> NifResult<Term<'a>> {
    match jwks::get_cached(&db_path, &realm_id) {
        Ok(c) => json_ok(env, &c),
        Err(e) => json_err(env, &e.to_string()),
    }
}

// ---------------------------------------------------------------------------
// Phase 4 — GCP STS exchange + cache (3 NIFs)
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_sts_exchange<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
    sub: String,
    audience: String,
    scope: String,
    target_sa: String,
    subject_token: String,
    dry_run: bool,
) -> NifResult<Term<'a>> {
    let sa_opt = if target_sa.is_empty() { None } else { Some(target_sa.as_str()) };
    match gcp_sts::exchange(
        &db_path,
        &realm_id,
        &sub,
        &audience,
        &scope,
        sa_opt,
        &subject_token,
        dry_run,
    ) {
        Ok(r) => json_ok(env, &r),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_sts_cache_get<'a>(
    env: Env<'a>,
    db_path: String,
    cache_key: String,
) -> NifResult<Term<'a>> {
    match gcp_sts::cache_get(&db_path, &cache_key) {
        Ok(Some(c)) => json_ok(env, &serde_json::json!({"found": true, "cached": c})),
        Ok(None) => json_ok(env, &serde_json::json!({"found": false})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_sts_cache_invalidate<'a>(
    env: Env<'a>,
    db_path: String,
    cache_key: String,
) -> NifResult<Term<'a>> {
    match gcp_sts::cache_invalidate(&db_path, &cache_key) {
        Ok(existed) => json_ok(env, &serde_json::json!({"existed": existed})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

// ---------------------------------------------------------------------------
// Phase 5.5 — SCIM NIF wrappers (5 NIFs)
// ---------------------------------------------------------------------------

/// Parse a SCIM 2.0 filter string into a typed AST as JSON. Returns
/// `{ok:true, ast: <serde_json::Value>}` on success, error JSON on failure.
/// This is the safe-by-construction defense against FMEA #4 (SQL injection):
/// the AST is the only output, no string-emit path.
#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_scim_filter_parse<'a>(env: Env<'a>, filter: String) -> NifResult<Term<'a>> {
    match scim::parse_filter(&filter) {
        Ok(ast) => json_ok(env, &serde_json::json!({"ok": true, "ast": format!("{:?}", ast)})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

/// Convert a SCIM User payload to an internal User. SC-GCP-IAM-004 enforced.
#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_scim_user_to_internal<'a>(
    env: Env<'a>,
    scim_json: String,
    realm_id: String,
) -> NifResult<Term<'a>> {
    let scim: scim::ScimUser = match serde_json::from_str(&scim_json) {
        Ok(u) => u,
        Err(e) => return json_err(env, &format!("decode_scim: {e}")),
    };
    match scim::user_to_internal(&scim, &realm_id) {
        Ok(u) => json_ok(env, &u),
        Err(e) => json_err(env, &e.to_string()),
    }
}

/// Convert an internal User to a SCIM 2.0 User payload (RFC 7643 §4.1).
#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_scim_internal_to_user<'a>(
    env: Env<'a>,
    db_path: String,
    user_id: String,
    base_url: String,
) -> NifResult<Term<'a>> {
    let user_opt = match user::get(&db_path, &user_id) {
        Ok(u) => u,
        Err(e) => return json_err(env, &e.to_string()),
    };
    let u = match user_opt {
        Some(u) => u,
        None => return json_ok(env, &serde_json::json!({"found": false})),
    };
    let s = scim::internal_to_user(&u, &base_url);
    json_ok(env, &serde_json::json!({"found": true, "scim_user": s}))
}

/// Enqueue an outbound SCIM op for delivery to Cloud Identity / Admin SDK.
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_scim_outbound_enqueue<'a>(
    env: Env<'a>,
    db_path: String,
    target: String,
    op: String,
    resource_type: String,
    payload: String,
) -> NifResult<Term<'a>> {
    match scim::enqueue_outbound(&db_path, &target, &op, &resource_type, &payload) {
        Ok(id) => json_ok(env, &serde_json::json!({"id": id, "queued": true})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

/// Drain due outbound SCIM ops (for the supervisor's ScimOutboundActor).
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_scim_outbound_drain<'a>(
    env: Env<'a>,
    db_path: String,
    now: i64,
    limit: i64,
) -> NifResult<Term<'a>> {
    match scim::drain_due(&db_path, now, limit as i32) {
        Ok(ops) => json_ok(env, &serde_json::json!({"ops": ops})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

// ---------------------------------------------------------------------------
// Phase 4.6 — GCP IAM impersonation + emergency-stop deny (2 NIFs)
// ---------------------------------------------------------------------------

/// Generate a GCP access token via service-account impersonation
/// (`iamcredentials.googleapis.com/v1/.../{sa}:generateAccessToken`).
/// `dry_run=true` returns `{ok, url, body}` without network — for offline
/// audits and tests.
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_impersonate<'a>(
    env: Env<'a>,
    target_sa: String,
    scopes_csv: String,
    lifetime_seconds: i64,
    bearer: String,
    dry_run: bool,
) -> NifResult<Term<'a>> {
    let scopes: Vec<String> = scopes_csv
        .split(',')
        .filter(|s| !s.trim().is_empty())
        .map(|s| s.trim().to_string())
        .collect();
    match gcp_iam::impersonate(&target_sa, &scopes, lifetime_seconds, &bearer, dry_run) {
        Ok(r) => json_ok(env, &r),
        Err(e) => json_err(env, &e.to_string()),
    }
}

/// Apply a deny policy as the canonical emergency-stop pathway.
/// SC-GCP-IAM-013: p99 ≤ 5 s.
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_deny_policy_apply<'a>(
    env: Env<'a>,
    attachment_point: String,
    policy_id: String,
    rules_json: String,
    bearer: String,
    dry_run: bool,
) -> NifResult<Term<'a>> {
    match gcp_iam::deny_policy_apply(
        &attachment_point,
        &policy_id,
        &rules_json,
        &bearer,
        dry_run,
    ) {
        Ok(r) => json_ok(env, &r),
        Err(e) => json_err(env, &e.to_string()),
    }
}

/// Generate an ID token via `iamcredentials.googleapis.com/v1/.../{sa}:generateIdToken`.
/// Used by Cloud Run / Cloud Functions for cross-service auth.
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_id_token<'a>(
    env: Env<'a>,
    target_sa: String,
    audience: String,
    bearer: String,
    dry_run: bool,
) -> NifResult<Term<'a>> {
    let url = gcp_iam::id_token_url(&target_sa);
    let body = gcp_iam::id_token_body(&audience, true);
    audit::emit(
        "gcp_iam.id_token.attempt",
        &serde_json::json!({"target_sa": target_sa, "audience": audience, "dry_run": dry_run}),
    );
    if dry_run {
        return json_ok(
            env,
            &serde_json::json!({"ok": true, "url": url, "body": body, "id_token": null}),
        );
    }
    let rt = crate::runtime::get();
    let url_for = url.clone();
    let body_for = body.clone();
    let bearer_for = bearer.clone();
    let result = rt.block_on(async move {
        let client = reqwest::Client::new();
        let resp = client
            .post(&url_for)
            .header("Authorization", format!("Bearer {}", bearer_for))
            .header("Content-Type", "application/json")
            .body(body_for)
            .send()
            .await;
        match resp {
            Ok(r) => {
                let status = r.status();
                let text = r.text().await.unwrap_or_default();
                if !status.is_success() {
                    return Err(format!("id_token returned {status}: {text}"));
                }
                let v: serde_json::Value = serde_json::from_str(&text)
                    .map_err(|e| format!("decode: {e}"))?;
                Ok(v["token"].as_str().unwrap_or_default().to_string())
            }
            Err(e) => Err(format!("id_token POST: {e}")),
        }
    });
    match result {
        Ok(token) => {
            audit::emit("gcp_iam.id_token.ok", &serde_json::json!({"target_sa": target_sa}));
            json_ok(env, &serde_json::json!({"ok": true, "url": url, "id_token": token}))
        }
        Err(e) => json_err(env, &e),
    }
}

/// Get the IAM allow-policy for a resource. Returns `{etag, bindings}`.
/// `resource` shape: `projects/<p>/serviceAccounts/<sa>` (no leading slash).
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_iam_policy_get<'a>(
    env: Env<'a>,
    resource: String,
    bearer: String,
    dry_run: bool,
) -> NifResult<Term<'a>> {
    let url = gcp_iam::get_policy_url(&resource);
    audit::emit(
        "gcp_iam.policy_get.attempt",
        &serde_json::json!({"resource": resource, "dry_run": dry_run}),
    );
    if dry_run {
        return json_ok(env, &serde_json::json!({"ok": true, "url": url}));
    }
    let rt = crate::runtime::get();
    let url_for = url.clone();
    let bearer_for = bearer.clone();
    let result = rt.block_on(async move {
        let client = reqwest::Client::new();
        let resp = client
            .post(&url_for)
            .header("Authorization", format!("Bearer {}", bearer_for))
            .header("Content-Type", "application/json")
            .body("{}")
            .send()
            .await;
        match resp {
            Ok(r) => {
                let status = r.status();
                let text = r.text().await.unwrap_or_default();
                if !status.is_success() {
                    return Err(format!("policy_get returned {status}: {text}"));
                }
                Ok(text)
            }
            Err(e) => Err(format!("policy_get POST: {e}")),
        }
    });
    match result {
        Ok(body) => json_ok(env, &serde_json::json!({"ok": true, "url": url, "policy_json": body})),
        Err(e) => json_err(env, &e),
    }
}

/// Set the IAM allow-policy. SC-GCP-IAM-011 enforces non-empty etag at the
/// validator boundary. SC-GCP-IAM-012 requires 2oo3 Guardian gating
/// (caller-side enforcement).
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_iam_policy_set<'a>(
    env: Env<'a>,
    resource: String,
    policy_json: String,
    bearer: String,
    dry_run: bool,
) -> NifResult<Term<'a>> {
    let url = gcp_iam::set_policy_url(&resource);
    let policy: gcp_iam::Policy = match serde_json::from_str(&policy_json) {
        Ok(p) => p,
        Err(e) => return json_err(env, &format!("decode_policy: {e}")),
    };
    let body = match gcp_iam::set_policy_body(&policy) {
        Ok(b) => b,
        Err(e) => return json_err(env, &e.to_string()),
    };
    audit::emit(
        "gcp_iam.policy_set.attempt",
        &serde_json::json!({"resource": resource, "etag": policy.etag, "dry_run": dry_run}),
    );
    if dry_run {
        return json_ok(env, &serde_json::json!({"ok": true, "url": url, "body": body}));
    }
    let rt = crate::runtime::get();
    let url_for = url.clone();
    let body_for = body.clone();
    let bearer_for = bearer.clone();
    let result = rt.block_on(async move {
        let client = reqwest::Client::new();
        let resp = client
            .post(&url_for)
            .header("Authorization", format!("Bearer {}", bearer_for))
            .header("Content-Type", "application/json")
            .body(body_for)
            .send()
            .await;
        match resp {
            Ok(r) => {
                let status = r.status();
                let text = r.text().await.unwrap_or_default();
                if status.as_u16() == 409 {
                    return Err(format!("etag_conflict: {text}"));
                }
                if !status.is_success() {
                    return Err(format!("policy_set returned {status}: {text}"));
                }
                Ok(text)
            }
            Err(e) => Err(format!("policy_set POST: {e}")),
        }
    });
    match result {
        Ok(body) => {
            audit::emit("gcp_iam.policy_set.ok", &serde_json::json!({"resource": resource}));
            json_ok(env, &serde_json::json!({"ok": true, "url": url, "policy_json": body}))
        }
        Err(e) => json_err(env, &e),
    }
}

// ---------------------------------------------------------------------------
// Phase 4.8 — Admin SDK Directory user CRUD + Cloud Identity group CRUD
// (8 NIFs, dry-run-only; URL+body builders proven in gcp_iam.rs)
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_directory_user_create<'a>(
    env: Env<'a>,
    primary_email: String,
    given_name: String,
    family_name: String,
    password_hash: String,
) -> NifResult<Term<'a>> {
    let url = gcp_iam::directory_user_create_url();
    let pwd = if password_hash.is_empty() { None } else { Some(password_hash.as_str()) };
    let body = gcp_iam::directory_user_create_body(&primary_email, &given_name, &family_name, pwd);
    json_ok(env, &serde_json::json!({"ok": true, "url": url, "body": body, "method": "POST"}))
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_directory_user_get<'a>(
    env: Env<'a>,
    user_key: String,
) -> NifResult<Term<'a>> {
    let url = gcp_iam::directory_user_item_url(&user_key);
    json_ok(env, &serde_json::json!({"ok": true, "url": url, "method": "GET"}))
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_directory_user_update<'a>(
    env: Env<'a>,
    user_key: String,
    body_json: String,
) -> NifResult<Term<'a>> {
    let url = gcp_iam::directory_user_item_url(&user_key);
    json_ok(env, &serde_json::json!({"ok": true, "url": url, "body": body_json, "method": "PUT"}))
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_directory_user_delete<'a>(
    env: Env<'a>,
    user_key: String,
) -> NifResult<Term<'a>> {
    let url = gcp_iam::directory_user_item_url(&user_key);
    json_ok(env, &serde_json::json!({"ok": true, "url": url, "method": "DELETE"}))
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_cloud_identity_group_create<'a>(
    env: Env<'a>,
    parent: String,
    group_key_id: String,
    display_name: String,
    description: String,
) -> NifResult<Term<'a>> {
    let url = gcp_iam::cloud_identity_group_create_url();
    let body = gcp_iam::cloud_identity_group_create_body(
        &parent, &group_key_id, &display_name, &description,
    );
    json_ok(env, &serde_json::json!({"ok": true, "url": url, "body": body, "method": "POST"}))
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_cloud_identity_group_get<'a>(
    env: Env<'a>,
    name: String,
) -> NifResult<Term<'a>> {
    let url = gcp_iam::cloud_identity_group_item_url(&name);
    json_ok(env, &serde_json::json!({"ok": true, "url": url, "method": "GET"}))
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_cloud_identity_group_update<'a>(
    env: Env<'a>,
    name: String,
    body_json: String,
) -> NifResult<Term<'a>> {
    let url = gcp_iam::cloud_identity_group_item_url(&name);
    json_ok(env, &serde_json::json!({"ok": true, "url": url, "body": body_json, "method": "PATCH"}))
}

#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_gcp_cloud_identity_group_delete<'a>(
    env: Env<'a>,
    name: String,
) -> NifResult<Term<'a>> {
    let url = gcp_iam::cloud_identity_group_item_url(&name);
    json_ok(env, &serde_json::json!({"ok": true, "url": url, "method": "DELETE"}))
}

// ---------------------------------------------------------------------------
// Phase 8 — Vault-backed signing-key handoff (3 NIFs)
// ---------------------------------------------------------------------------

/// Export an Ed25519 seed for vault storage. Returns `{kid, seed_b64, vault_path}`.
/// Caller MUST persist seed_b64 to vault under vault_path then call
/// `ferriskey_signing_key_purge_local` to complete the handoff.
#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_signing_key_export_seed<'a>(
    env: Env<'a>,
    db_path: String,
    kid: String,
) -> NifResult<Term<'a>> {
    match token::export_seed(&db_path, &kid) {
        Ok(s) => json_ok(env, &s),
        Err(e) => json_err(env, &e.to_string()),
    }
}

/// Drop the local SQLite copy of a signing-key seed once vault has it.
/// Idempotent. SC-FERRISKEY-NIF-010 completes here.
#[rustler::nif(schedule = "DirtyIo")]
fn ferriskey_signing_key_purge_local<'a>(
    env: Env<'a>,
    db_path: String,
    kid: String,
) -> NifResult<Term<'a>> {
    match token::purge_local_seed(&db_path, &kid) {
        Ok(existed) => json_ok(env, &serde_json::json!({"existed": existed})),
        Err(e) => json_err(env, &e.to_string()),
    }
}

/// Issue a JWT using a vault-supplied seed. Hot-path replacement for
/// `ferriskey_token_issue` once `ferriskey_signing_key_purge_local` has run.
#[rustler::nif(schedule = "DirtyCpu")]
fn ferriskey_token_issue_with_seed<'a>(
    env: Env<'a>,
    db_path: String,
    realm_id: String,
    user_id: String,
    audience: String,
    scopes_csv: String,
    ttl_seconds: i64,
    kid: String,
    seed_b64: String,
) -> NifResult<Term<'a>> {
    let scopes: Vec<String> = if scopes_csv.is_empty() {
        Vec::new()
    } else {
        scopes_csv.split(',').map(|s| s.trim().to_string()).collect()
    };
    match token::issue_with_seed(
        &db_path, &realm_id, &user_id, &audience, &scopes, ttl_seconds, &kid, &seed_b64,
    ) {
        Ok(t) => json_ok(env, &t),
        Err(e) => json_err(env, &e.to_string()),
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn json_ok<'a, T: serde::Serialize>(env: Env<'a>, v: &T) -> NifResult<Term<'a>> {
    let body = serde_json::to_string(v).unwrap_or_else(|e| {
        format!(r#"{{"ok":false,"error":"serialize:{}"}}"#, e)
    });
    Ok((atoms::ok(), body).encode(env))
}

fn json_err<'a>(env: Env<'a>, msg: &str) -> NifResult<Term<'a>> {
    let body = serde_json::json!({"ok": false, "error": msg}).to_string();
    Ok((atoms::error(), body).encode(env))
}

rustler::init!("ferriskey_nif");
