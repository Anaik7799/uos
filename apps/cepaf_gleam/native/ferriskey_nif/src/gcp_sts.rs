//! GCP Workload Identity Federation — STS token exchange (Bridge 2).
//!
//! Surface (3 NIFs):
//!   gcp_sts_exchange(realm_id, user_id, audience, scope, target_sa, ttl_s)
//!     -> {access_token, sa_principal, expires_at}
//!   gcp_sts_cache_get(cache_key) -> {found, access_token, sa_principal, expires_at}
//!   gcp_sts_cache_invalidate(cache_key) -> {existed}
//!
//! ## Wire format (RFC 8693 token exchange)
//! POST https://sts.googleapis.com/v1/token
//! Content-Type: application/x-www-form-urlencoded
//!
//!   grant_type=urn:ietf:params:oauth:grant-type:token-exchange
//!   audience=//iam.googleapis.com/projects/<num>/locations/global/workloadIdentityPools/<pool>/providers/<provider>
//!   scope=https://www.googleapis.com/auth/cloud-platform
//!   requested_token_type=urn:ietf:params:oauth:token-type:access_token
//!   subject_token=<FerrisKey-issued JWT>
//!   subject_token_type=urn:ietf:params:oauth:token-type:jwt
//!
//! Response:
//!   { "access_token": "...", "issued_token_type": "...", "token_type": "Bearer",
//!     "expires_in": 3600 }
//!
//! ## SC-GCP-IAM compliance
//! - 002: RFC 8693 conformant (subject_token_type=jwt)
//! - 003: cache TTL = min(returned_exp, 55 min) — see `compute_cache_ttl`
//! - 005: GDPR EU residency — STS endpoint is global by GCP design, but the
//!   *resulting access token* is bound to a SA whose downstream calls MUST
//!   target europe-north1 endpoints (enforced by region-pin lint elsewhere).
//! - 009: token bucket 60 rpm/realm — handled by caller; not enforced here.
//!
//! ## Phase 4 scope
//! This module ships the **request builder + response parser + cache** as
//! pure logic, fully testable offline. The actual reqwest call is wired but
//! tests never hit the network — they verify the form-body shape, response
//! decode, and cache semantics.

use anyhow::{Context, Result};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::audit;
use crate::realm;

pub const STS_ENDPOINT: &str = "https://sts.googleapis.com/v1/token";
pub const SUBJECT_TOKEN_TYPE_JWT: &str = "urn:ietf:params:oauth:token-type:jwt";
pub const REQUESTED_TOKEN_TYPE_ACCESS: &str =
    "urn:ietf:params:oauth:token-type:access_token";
pub const GRANT_TYPE_TOKEN_EXCHANGE: &str =
    "urn:ietf:params:oauth:grant-type:token-exchange";
pub const SCOPE_CLOUD_PLATFORM: &str = "https://www.googleapis.com/auth/cloud-platform";

/// Hard cap on cache TTL — SC-GCP-IAM-003.
const MAX_CACHE_TTL_SECONDS: i64 = 55 * 60;

#[derive(Debug, Clone, Serialize)]
pub struct StsRequest {
    pub audience: String,
    pub scope: String,
    pub subject_token: String,
    pub target_sa: Option<String>,
}

impl StsRequest {
    pub fn build_form_body(&self) -> String {
        let mut parts = vec![
            ("grant_type", GRANT_TYPE_TOKEN_EXCHANGE.to_string()),
            ("audience", self.audience.clone()),
            ("scope", self.scope.clone()),
            ("requested_token_type", REQUESTED_TOKEN_TYPE_ACCESS.to_string()),
            ("subject_token", self.subject_token.clone()),
            ("subject_token_type", SUBJECT_TOKEN_TYPE_JWT.to_string()),
        ];
        if let Some(sa) = &self.target_sa {
            parts.push(("requested_subject", sa.clone()));
        }
        parts
            .iter()
            .map(|(k, v)| format!("{}={}", urlencoding::encode(k), urlencoding::encode(v)))
            .collect::<Vec<_>>()
            .join("&")
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct StsResponseRaw {
    pub access_token: String,
    #[serde(default)]
    pub token_type: String,
    pub expires_in: i64,
    #[serde(default)]
    pub issued_token_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CachedToken {
    pub access_token: String,
    pub sa_principal: String,
    /// Unix epoch seconds; computed as `now + min(expires_in, MAX_CACHE_TTL)`.
    pub expires_at: i64,
    /// Always present in the response we serialize back to the Gleam wrapper.
    pub cache_key: String,
}

/// Compute cache TTL clamped per SC-GCP-IAM-003.
pub fn compute_cache_ttl(returned_expires_in: i64) -> i64 {
    if returned_expires_in <= 0 {
        0
    } else if returned_expires_in > MAX_CACHE_TTL_SECONDS {
        MAX_CACHE_TTL_SECONDS
    } else {
        returned_expires_in
    }
}

/// Cache key = sha256(realm_id | sub | scope | target_sa | audience). Stable
/// across re-exchanges so concurrent callers share the same cache row.
pub fn make_cache_key(
    realm_id: &str,
    sub: &str,
    audience: &str,
    scope: &str,
    target_sa: Option<&str>,
) -> String {
    let mut h = Sha256::new();
    h.update(realm_id.as_bytes());
    h.update(b"|");
    h.update(sub.as_bytes());
    h.update(b"|");
    h.update(audience.as_bytes());
    h.update(b"|");
    h.update(scope.as_bytes());
    h.update(b"|");
    h.update(target_sa.unwrap_or("").as_bytes());
    let digest = h.finalize();
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(digest)
}

fn ensure_table(conn: &rusqlite::Connection) -> Result<()> {
    // The schema already creates `gcp_sts_cache` in db.rs. Idempotent guard
    // here so unit tests that bypass `db::init` still work.
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS gcp_sts_cache (
            cache_key     TEXT PRIMARY KEY,
            access_token  TEXT NOT NULL,
            sa_principal  TEXT NOT NULL,
            issued_at     INTEGER NOT NULL,
            expires_at    INTEGER NOT NULL
        );",
    )?;
    Ok(())
}

pub fn cache_get(db_path: &str, cache_key: &str) -> Result<Option<CachedToken>> {
    let conn = realm::open_for_test(db_path)?;
    ensure_table(&conn)?;
    let now = realm::now_secs_pub();
    let row: Option<(String, String, i64)> = conn
        .query_row(
            "SELECT access_token, sa_principal, expires_at FROM gcp_sts_cache
             WHERE cache_key=?1 AND expires_at > ?2",
            params![cache_key, now],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()?;
    Ok(row.map(|(at, sa, exp)| CachedToken {
        access_token: at,
        sa_principal: sa,
        expires_at: exp,
        cache_key: cache_key.to_string(),
    }))
}

pub fn cache_set(
    db_path: &str,
    cache_key: &str,
    access_token: &str,
    sa_principal: &str,
    expires_in_secs: i64,
) -> Result<CachedToken> {
    let conn = realm::open_for_test(db_path)?;
    ensure_table(&conn)?;
    let now = realm::now_secs_pub();
    let ttl = compute_cache_ttl(expires_in_secs);
    let expires_at = now + ttl;
    conn.execute(
        "INSERT OR REPLACE INTO gcp_sts_cache(cache_key,access_token,sa_principal,issued_at,expires_at)
         VALUES(?1,?2,?3,?4,?5)",
        params![cache_key, access_token, sa_principal, now, expires_at],
    )?;
    Ok(CachedToken {
        access_token: access_token.to_string(),
        sa_principal: sa_principal.to_string(),
        expires_at,
        cache_key: cache_key.to_string(),
    })
}

pub fn cache_invalidate(db_path: &str, cache_key: &str) -> Result<bool> {
    let conn = realm::open_for_test(db_path)?;
    ensure_table(&conn)?;
    let n = conn.execute(
        "DELETE FROM gcp_sts_cache WHERE cache_key=?1",
        params![cache_key],
    )?;
    if n > 0 {
        audit::emit("gcp_sts.invalidate", &serde_json::json!({"key": cache_key}));
    }
    Ok(n > 0)
}

/// Result envelope for `gcp_sts_exchange`. Even when the network call fails
/// (or is short-circuited by an offline test environment), the request body
/// is still returned so callers can audit what *would* have been sent.
#[derive(Debug, Serialize)]
pub struct ExchangeResult {
    pub ok: bool,
    pub cache_key: String,
    pub form_body: String,
    pub endpoint: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cached: Option<CachedToken>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Exchange a FerrisKey JWT for a GCP access token. Cache hit returns
/// immediately; cache miss issues a real STS POST via the shared tokio
/// runtime (`runtime::get`).
///
/// In Phase 4 substrate, the actual HTTP call is gated behind a feature
/// flag-equivalent: callers can pass `dry_run=true` to skip the network and
/// receive `{ok:true, form_body, endpoint, cache_key}` so unit tests verify
/// the wire shape without needing GCP credentials.
pub fn exchange(
    db_path: &str,
    realm_id: &str,
    sub: &str,
    audience: &str,
    scope: &str,
    target_sa: Option<&str>,
    subject_token: &str,
    dry_run: bool,
) -> Result<ExchangeResult> {
    let cache_key = make_cache_key(realm_id, sub, audience, scope, target_sa);
    if let Some(cached) = cache_get(db_path, &cache_key)? {
        return Ok(ExchangeResult {
            ok: true,
            cache_key,
            form_body: String::new(),
            endpoint: STS_ENDPOINT.to_string(),
            cached: Some(cached),
            error: None,
        });
    }
    let req = StsRequest {
        audience: audience.to_string(),
        scope: scope.to_string(),
        subject_token: subject_token.to_string(),
        target_sa: target_sa.map(|s| s.to_string()),
    };
    let form_body = req.build_form_body();
    audit::emit(
        "gcp_sts.exchange.attempt",
        &serde_json::json!({
            "realm_id": realm_id,
            "sub": sub,
            "audience": audience,
            "scope": scope,
            "target_sa": target_sa,
            "cache_key": cache_key,
            "dry_run": dry_run,
        }),
    );
    if dry_run {
        return Ok(ExchangeResult {
            ok: true,
            cache_key,
            form_body,
            endpoint: STS_ENDPOINT.to_string(),
            cached: None,
            error: None,
        });
    }
    // Live path — block_on on the shared runtime. Errors don't propagate as
    // panics; they land in `error` so the BEAM caller can route to the
    // RETE-UL `IamSaKeyRotationDue` / `JwksPublishFailed` rules.
    let rt = crate::runtime::get();
    let endpoint = STS_ENDPOINT.to_string();
    let body_clone = form_body.clone();
    let result: Result<StsResponseRaw> = rt.block_on(async move {
        let client = reqwest::Client::new();
        let resp = client
            .post(&endpoint)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(body_clone)
            .send()
            .await
            .context("STS POST")?;
        let status = resp.status();
        let text = resp.text().await.context("STS body read")?;
        if !status.is_success() {
            anyhow::bail!("STS returned {status}: {text}");
        }
        let parsed: StsResponseRaw =
            serde_json::from_str(&text).context("STS response decode")?;
        Ok(parsed)
    });

    match result {
        Ok(r) => {
            let sa = target_sa.unwrap_or("").to_string();
            let cached =
                cache_set(db_path, &cache_key, &r.access_token, &sa, r.expires_in)?;
            audit::emit(
                "gcp_sts.exchange.ok",
                &serde_json::json!({"cache_key": cache_key, "expires_at": cached.expires_at}),
            );
            Ok(ExchangeResult {
                ok: true,
                cache_key,
                form_body,
                endpoint: STS_ENDPOINT.to_string(),
                cached: Some(cached),
                error: None,
            })
        }
        Err(e) => Ok(ExchangeResult {
            ok: false,
            cache_key,
            form_body,
            endpoint: STS_ENDPOINT.to_string(),
            cached: None,
            error: Some(e.to_string()),
        }),
    }
}

// Need to re-import the base64 Engine for make_cache_key.
use base64::Engine as _;

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh() -> (tempfile::TempDir, String) {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("ferriskey.db").to_str().unwrap().to_string();
        crate::db::init(&path).unwrap();
        (tmp, path)
    }

    #[test]
    fn ttl_is_clamped_to_55_min() {
        assert_eq!(compute_cache_ttl(7200), MAX_CACHE_TTL_SECONDS); // 2h capped
        assert_eq!(compute_cache_ttl(3600), 3300); // 1h capped to 55m
        assert_eq!(compute_cache_ttl(60), 60); // 1m allowed
        assert_eq!(compute_cache_ttl(0), 0);
        assert_eq!(compute_cache_ttl(-1), 0);
    }

    #[test]
    fn cache_key_is_deterministic_and_distinguishing() {
        let a = make_cache_key("r1", "u1", "aud1", "scope1", Some("sa1"));
        let b = make_cache_key("r1", "u1", "aud1", "scope1", Some("sa1"));
        assert_eq!(a, b);
        let c = make_cache_key("r1", "u1", "aud1", "scope1", Some("sa2"));
        assert_ne!(a, c);
        let d = make_cache_key("r1", "u2", "aud1", "scope1", Some("sa1"));
        assert_ne!(a, d);
    }

    #[test]
    fn form_body_contains_all_rfc8693_fields() {
        let req = StsRequest {
            audience: "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/p/providers/v".to_string(),
            scope: SCOPE_CLOUD_PLATFORM.to_string(),
            subject_token: "eyJ.foo.bar".to_string(),
            target_sa: Some("c3i-scim@x.iam.gserviceaccount.com".to_string()),
        };
        let body = req.build_form_body();
        assert!(body.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange"));
        assert!(body.contains("subject_token_type=urn%3Aietf%3Aparams%3Aoauth%3Atoken-type%3Ajwt"));
        assert!(body.contains("requested_token_type=urn%3Aietf%3Aparams%3Aoauth%3Atoken-type%3Aaccess_token"));
        assert!(body.contains("subject_token=eyJ.foo.bar"));
        assert!(body.contains("requested_subject="));
    }

    #[test]
    fn cache_set_then_get() {
        let (_tmp, path) = fresh();
        let key = make_cache_key("r1", "u1", "aud", "scope", Some("sa"));
        cache_set(&path, &key, "ya29.token", "sa@x", 3600).unwrap();
        let got = cache_get(&path, &key).unwrap().unwrap();
        assert_eq!(got.access_token, "ya29.token");
        assert_eq!(got.sa_principal, "sa@x");
    }

    #[test]
    fn cache_get_returns_none_after_expiry_simulated() {
        let (_tmp, path) = fresh();
        let key = make_cache_key("r1", "u1", "aud", "scope", None);
        // Insert with negative TTL → already expired.
        let conn = realm::open_for_test(&path).unwrap();
        let now = realm::now_secs_pub();
        conn.execute(
            "INSERT INTO gcp_sts_cache(cache_key,access_token,sa_principal,issued_at,expires_at)
             VALUES(?1,?2,?3,?4,?5)",
            params![key, "stale", "", now - 100, now - 50],
        )
        .unwrap();
        assert!(cache_get(&path, &key).unwrap().is_none());
    }

    #[test]
    fn cache_invalidate_returns_existed_then_false() {
        let (_tmp, path) = fresh();
        let key = make_cache_key("r1", "u1", "aud", "scope", None);
        cache_set(&path, &key, "tok", "sa", 60).unwrap();
        assert!(cache_invalidate(&path, &key).unwrap());
        assert!(!cache_invalidate(&path, &key).unwrap());
    }

    #[test]
    fn exchange_dry_run_returns_form_body_without_network() {
        let (_tmp, path) = fresh();
        let r = exchange(
            &path,
            "r1",
            "alice",
            "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/c3i/providers/v",
            SCOPE_CLOUD_PLATFORM,
            Some("c3i-scim@x.iam.gserviceaccount.com"),
            "eyJ.fake.jwt",
            true,
        )
        .unwrap();
        assert!(r.ok);
        assert_eq!(r.endpoint, STS_ENDPOINT);
        assert!(r.form_body.contains("grant_type=urn%3Aietf"));
        assert!(r.form_body.contains("subject_token=eyJ.fake.jwt"));
        assert!(r.cached.is_none(), "dry-run does not populate cache");
        assert!(!r.cache_key.is_empty());
    }

    #[test]
    fn exchange_dry_run_then_cache_hit_short_circuits() {
        let (_tmp, path) = fresh();
        // Pre-populate cache row matching the deterministic cache_key.
        let key = make_cache_key("r1", "u1", "aud", "scope", Some("sa"));
        cache_set(&path, &key, "cached.token", "sa@x", 60).unwrap();
        let r = exchange(
            &path, "r1", "u1", "aud", "scope", Some("sa"),
            "subject.jwt", false,
        )
        .unwrap();
        // Cache hit short-circuits before any network call — `error` is None,
        // `cached` populated, `form_body` empty.
        assert!(r.ok);
        assert_eq!(r.error, None);
        assert!(r.form_body.is_empty());
        let c = r.cached.unwrap();
        assert_eq!(c.access_token, "cached.token");
    }
}
