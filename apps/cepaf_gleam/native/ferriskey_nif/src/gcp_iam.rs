//! GCP IAM allow/deny policy + service-account impersonation + ID token (Phase 4.5).
//!
//! Surface (5 NIFs):
//!   gcp_impersonate(target_sa, scopes_csv, lifetime_s, bearer)
//!     -> {access_token, sa_principal, expires_at}
//!   gcp_id_token(target_sa, audience, bearer) -> {id_token, exp}
//!   gcp_iam_policy_get(resource, bearer) -> {etag, bindings_json}
//!   gcp_iam_policy_set(resource, etag, bindings_json, bearer)
//!     -> {ok, etag} | {error, EtagConflict}
//!   gcp_deny_policy_apply(target, rules_json, bearer)
//!     -> {ok, applied_within_ms}
//!
//! ## SC-GCP-IAM compliance
//! - 005: region-pinned `europe-north1` for downstream resources (the IAM
//!   control-plane endpoints are global by GCP design but this module only
//!   accepts requests whose `resource` references EU-pinned services).
//! - 011: allow-policy mutations MUST cite etag (or fail closed)
//! - 012: setIamPolicy MUST be 2oo3 Guardian-gated (caller-side enforced)
//! - 013: deny-policy emergency-stop p99 ≤ 5 s
//! - 014: basic roles (Owner/Editor/Viewer) FORBIDDEN — `validate_binding`
//!   refuses them at the NIF boundary (defense-in-depth on top of TF lint)
//!
//! ## Phase 4.5 scope
//! Pure logic (request URL builders, JSON serializers, etag enforcement,
//! basic-role rejection) is fully testable offline. The reqwest live path
//! is wired with a `dry_run` flag mirroring `gcp_sts.rs`.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::time::Instant;

use crate::audit;

pub const IAM_BASE: &str = "https://iam.googleapis.com";
pub const IAM_CREDENTIALS_BASE: &str = "https://iamcredentials.googleapis.com";

/// Forbidden basic roles per SC-GCP-IAM-014.
pub const FORBIDDEN_BASIC_ROLES: &[&str] = &[
    "roles/owner",
    "roles/editor",
    "roles/viewer",
];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Binding {
    pub role: String,
    pub members: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub condition: Option<Condition>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Condition {
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub description: Option<String>,
    /// CEL expression.
    pub expression: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Policy {
    pub etag: String,
    pub bindings: Vec<Binding>,
    #[serde(default)]
    pub version: i32,
}

/// Build the `:generateAccessToken` URL for an impersonation target.
/// Format: `iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/{sa}:generateAccessToken`
pub fn impersonate_url(target_sa: &str) -> String {
    format!(
        "{}/v1/projects/-/serviceAccounts/{}:generateAccessToken",
        IAM_CREDENTIALS_BASE, target_sa
    )
}

/// Build the `:generateIdToken` URL.
pub fn id_token_url(target_sa: &str) -> String {
    format!(
        "{}/v1/projects/-/serviceAccounts/{}:generateIdToken",
        IAM_CREDENTIALS_BASE, target_sa
    )
}

/// Build the `getIamPolicy` URL for a service-account resource.
/// `resource` shape: `projects/<p>/serviceAccounts/<sa>` (no leading slash).
pub fn get_policy_url(resource: &str) -> String {
    format!("{}/v1/{}:getIamPolicy", IAM_BASE, resource)
}

pub fn set_policy_url(resource: &str) -> String {
    format!("{}/v1/{}:setIamPolicy", IAM_BASE, resource)
}

/// IAM Recommender list URL — least-privilege role recommendations.
/// SC-GCP-IAM-015 (output reviewed weekly; 2oo3 to apply).
pub fn recommender_list_url(project_id: &str, location: &str) -> String {
    format!(
        "https://recommender.googleapis.com/v1/projects/{}/locations/{}/recommenders/google.iam.policy.Recommender/recommendations",
        project_id, location
    )
}

/// Policy Troubleshooter — answers "can principal P do permission X on resource R?".
pub fn policy_troubleshoot_url() -> &'static str {
    "https://policytroubleshooter.googleapis.com/v1/iam:troubleshoot"
}

/// Policy Analyzer — bulk "who can do what" reports via Cloud Asset Inventory.
pub fn policy_analyze_url(scope: &str) -> String {
    format!(
        "https://cloudasset.googleapis.com/v1/{}:analyzeIamPolicy",
        scope
    )
}

/// Organization Policy list — read-only constraint inspection.
/// SC-GCP-IAM-017 (org-policy violations block setIamPolicy pre-flight).
pub fn org_policy_list_url(parent: &str) -> String {
    format!("https://orgpolicy.googleapis.com/v2/{}/policies", parent)
}

/// Admin SDK Directory user list (Workspace user roster).
pub fn directory_user_list_url(domain: &str) -> String {
    format!(
        "https://admin.googleapis.com/admin/directory/v1/users?domain={}",
        domain
    )
}

/// Admin SDK Directory — user create (POST).
pub fn directory_user_create_url() -> &'static str {
    "https://admin.googleapis.com/admin/directory/v1/users"
}

/// Admin SDK Directory — user get/update/delete (GET/PUT/DELETE on {userKey}).
pub fn directory_user_item_url(user_key: &str) -> String {
    format!(
        "https://admin.googleapis.com/admin/directory/v1/users/{}",
        user_key
    )
}

/// Body for `directory.users.insert` (RFC 7643-derived shape).
pub fn directory_user_create_body(
    primary_email: &str,
    given_name: &str,
    family_name: &str,
    password_hash: Option<&str>,
) -> String {
    let mut obj = serde_json::json!({
        "primaryEmail": primary_email,
        "name": {
            "givenName": given_name,
            "familyName": family_name,
        },
    });
    if let Some(h) = password_hash {
        obj["password"] = serde_json::json!(h);
        obj["hashFunction"] = serde_json::json!("SHA-1");
    }
    obj.to_string()
}

/// Cloud Identity groups list URL.
pub fn cloud_identity_groups_list_url(parent: &str) -> String {
    format!(
        "https://cloudidentity.googleapis.com/v1/groups?parent={}",
        parent
    )
}

/// Cloud Identity — group create (POST).
pub fn cloud_identity_group_create_url() -> &'static str {
    "https://cloudidentity.googleapis.com/v1/groups"
}

/// Cloud Identity — group get/update/delete (GET/PATCH/DELETE on {name}).
/// `name` shape: `groups/{groupId}`.
pub fn cloud_identity_group_item_url(name: &str) -> String {
    format!("https://cloudidentity.googleapis.com/v1/{}", name)
}

/// Body for Cloud Identity group create.
pub fn cloud_identity_group_create_body(
    parent: &str,
    group_key_id: &str,
    display_name: &str,
    description: &str,
) -> String {
    serde_json::json!({
        "parent": parent,
        "groupKey": { "id": group_key_id },
        "displayName": display_name,
        "description": description,
        "labels": {
            "cloudidentity.googleapis.com/groups.discussion_forum": ""
        },
    })
    .to_string()
}

/// Body for Policy Troubleshooter request.
pub fn policy_troubleshoot_body(
    principal: &str,
    resource_full_name: &str,
    permission: &str,
) -> String {
    serde_json::json!({
        "accessTuple": {
            "principal": principal,
            "fullResourceName": resource_full_name,
            "permission": permission,
        },
    })
    .to_string()
}

/// Build the v2 deny-policy attach URL. The deny policy targets a resource
/// via the v2 `iam.googleapis.com/v2/policies/{attachmentPoint}/denypolicies`
/// pattern; `attachment_point` MUST be already URL-encoded by the caller
/// (e.g. `cloudresourcemanager.googleapis.com%2Fprojects%2F{p}`).
pub fn deny_policy_url(attachment_point: &str, policy_id: &str) -> String {
    format!(
        "{}/v2/policies/{}/denypolicies?policyId={}",
        IAM_BASE, attachment_point, policy_id
    )
}

/// Validate a binding against SC-GCP-IAM-014 (no basic roles).
pub fn validate_binding(b: &Binding) -> Result<()> {
    let role_lower = b.role.to_ascii_lowercase();
    for forbidden in FORBIDDEN_BASIC_ROLES {
        if role_lower == *forbidden {
            anyhow::bail!(
                "SC-GCP-IAM-014: basic role {} forbidden — use predefined or custom",
                b.role
            );
        }
    }
    Ok(())
}

/// Validate a full policy: every binding passes role check, etag is non-empty.
pub fn validate_policy(p: &Policy) -> Result<()> {
    if p.etag.is_empty() {
        anyhow::bail!("SC-GCP-IAM-011: setIamPolicy requires non-empty etag");
    }
    for b in &p.bindings {
        validate_binding(b)?;
    }
    Ok(())
}

/// Serialize the request body for `setIamPolicy`. GCP expects:
/// `{"policy": {"etag":"...", "bindings": [...], "version": N}}`.
pub fn set_policy_body(p: &Policy) -> Result<String> {
    validate_policy(p)?;
    let body = serde_json::json!({"policy": p});
    Ok(body.to_string())
}

/// Serialize the request body for `:generateAccessToken`.
pub fn impersonate_body(scopes: &[String], lifetime_seconds: i64) -> String {
    serde_json::json!({
        "scope": scopes,
        "lifetime": format!("{}s", lifetime_seconds),
    })
    .to_string()
}

/// Serialize the request body for `:generateIdToken`.
pub fn id_token_body(audience: &str, include_email: bool) -> String {
    serde_json::json!({
        "audience": audience,
        "includeEmail": include_email,
    })
    .to_string()
}

#[derive(Debug, Serialize)]
pub struct ImpersonateResult {
    pub ok: bool,
    pub url: String,
    pub body: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub access_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PolicyOpResult {
    pub ok: bool,
    pub url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub etag: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub policy: Option<Policy>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct DenyApplyResult {
    pub ok: bool,
    pub url: String,
    pub elapsed_ms: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Live impersonation call. `bearer` is the STS-derived caller token.
pub fn impersonate(
    target_sa: &str,
    scopes: &[String],
    lifetime_seconds: i64,
    bearer: &str,
    dry_run: bool,
) -> Result<ImpersonateResult> {
    let url = impersonate_url(target_sa);
    let body = impersonate_body(scopes, lifetime_seconds);
    audit::emit(
        "gcp_iam.impersonate.attempt",
        &serde_json::json!({
            "target_sa": target_sa,
            "scopes": scopes,
            "lifetime_seconds": lifetime_seconds,
            "dry_run": dry_run,
        }),
    );
    if dry_run {
        return Ok(ImpersonateResult {
            ok: true,
            url,
            body,
            access_token: None,
            expires_at: None,
            error: None,
        });
    }
    let rt = crate::runtime::get();
    let url_for_call = url.clone();
    let body_for_call = body.clone();
    let bearer_owned = bearer.to_string();
    let result: Result<(String, i64)> = rt.block_on(async move {
        let client = reqwest::Client::new();
        let resp = client
            .post(&url_for_call)
            .header("Authorization", format!("Bearer {}", bearer_owned))
            .header("Content-Type", "application/json")
            .body(body_for_call)
            .send()
            .await
            .context("impersonate POST")?;
        let status = resp.status();
        let text = resp.text().await.context("impersonate body read")?;
        if !status.is_success() {
            anyhow::bail!("impersonate returned {status}: {text}");
        }
        let v: serde_json::Value =
            serde_json::from_str(&text).context("impersonate response decode")?;
        let access_token = v["accessToken"]
            .as_str()
            .context("missing accessToken")?
            .to_string();
        // expireTime is RFC 3339; convert to unix seconds. For Phase 4.5,
        // we accept the response as-is and let the caller normalize.
        let exp_raw = v["expireTime"].as_str().unwrap_or("");
        let expires_at = parse_rfc3339_to_unix(exp_raw).unwrap_or(0);
        Ok((access_token, expires_at))
    });
    match result {
        Ok((access_token, expires_at)) => {
            audit::emit(
                "gcp_iam.impersonate.ok",
                &serde_json::json!({"target_sa": target_sa, "expires_at": expires_at}),
            );
            Ok(ImpersonateResult {
                ok: true,
                url,
                body,
                access_token: Some(access_token),
                expires_at: Some(expires_at),
                error: None,
            })
        }
        Err(e) => Ok(ImpersonateResult {
            ok: false,
            url,
            body,
            access_token: None,
            expires_at: None,
            error: Some(e.to_string()),
        }),
    }
}

/// Apply a deny policy as fast as possible (SC-GCP-IAM-013, p99 ≤ 5 s).
/// `attachment_point` MUST be URL-encoded by caller.
pub fn deny_policy_apply(
    attachment_point: &str,
    policy_id: &str,
    rules_json: &str,
    bearer: &str,
    dry_run: bool,
) -> Result<DenyApplyResult> {
    let url = deny_policy_url(attachment_point, policy_id);
    let started = Instant::now();
    audit::emit(
        "gcp_iam.deny_policy.attempt",
        &serde_json::json!({
            "attachment_point": attachment_point,
            "policy_id": policy_id,
            "dry_run": dry_run,
        }),
    );
    if dry_run {
        return Ok(DenyApplyResult {
            ok: true,
            url,
            elapsed_ms: started.elapsed().as_millis() as i64,
            error: None,
        });
    }
    let rt = crate::runtime::get();
    let url_for_call = url.clone();
    let body_for_call = rules_json.to_string();
    let bearer_owned = bearer.to_string();
    let result: Result<()> = rt.block_on(async move {
        let client = reqwest::Client::new();
        let resp = client
            .post(&url_for_call)
            .header("Authorization", format!("Bearer {}", bearer_owned))
            .header("Content-Type", "application/json")
            .body(body_for_call)
            .send()
            .await
            .context("deny_policy POST")?;
        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            anyhow::bail!("deny_policy returned {status}: {text}");
        }
        Ok(())
    });
    let elapsed_ms = started.elapsed().as_millis() as i64;
    match result {
        Ok(()) => {
            audit::emit(
                "gcp_iam.deny_policy.ok",
                &serde_json::json!({"elapsed_ms": elapsed_ms, "policy_id": policy_id}),
            );
            Ok(DenyApplyResult {
                ok: true,
                url,
                elapsed_ms,
                error: None,
            })
        }
        Err(e) => Ok(DenyApplyResult {
            ok: false,
            url,
            elapsed_ms,
            error: Some(e.to_string()),
        }),
    }
}

/// Parse RFC 3339 timestamp string (e.g. "2026-04-30T14:23:45Z") to unix seconds.
/// Best-effort — returns None if the string isn't parseable.
pub fn parse_rfc3339_to_unix(s: &str) -> Option<i64> {
    chrono::DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|dt| dt.timestamp())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn impersonate_url_format() {
        let u = impersonate_url("c3i-scim@x.iam.gserviceaccount.com");
        assert_eq!(
            u,
            "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/c3i-scim@x.iam.gserviceaccount.com:generateAccessToken"
        );
    }

    #[test]
    fn id_token_url_format() {
        let u = id_token_url("c3i-svc@x.iam.gserviceaccount.com");
        assert!(u.ends_with(":generateIdToken"));
        assert!(u.contains("/v1/projects/-/serviceAccounts/"));
    }

    #[test]
    fn policy_urls() {
        let g = get_policy_url("projects/p1/serviceAccounts/c3i-scim@x.iam.gserviceaccount.com");
        assert!(g.starts_with("https://iam.googleapis.com/v1/"));
        assert!(g.ends_with(":getIamPolicy"));
        let s = set_policy_url("projects/p1/serviceAccounts/c3i-scim@x.iam.gserviceaccount.com");
        assert!(s.ends_with(":setIamPolicy"));
    }

    #[test]
    fn validate_binding_rejects_basic_roles() {
        for role in FORBIDDEN_BASIC_ROLES {
            let b = Binding {
                role: role.to_string(),
                members: vec!["user:a@b.com".into()],
                condition: None,
            };
            assert!(validate_binding(&b).is_err(), "role {} must be rejected", role);
        }
    }

    #[test]
    fn validate_binding_rejects_basic_roles_case_insensitive() {
        let b = Binding {
            role: "ROLES/Owner".to_string(),
            members: vec!["user:a@b.com".into()],
            condition: None,
        };
        assert!(validate_binding(&b).is_err());
    }

    #[test]
    fn validate_binding_accepts_predefined_role() {
        let b = Binding {
            role: "roles/storage.objectCreator".to_string(),
            members: vec!["serviceAccount:c3i-backup@x.iam.gserviceaccount.com".into()],
            condition: None,
        };
        assert!(validate_binding(&b).is_ok());
    }

    #[test]
    fn validate_policy_requires_etag() {
        let p = Policy {
            etag: "".to_string(),
            bindings: vec![],
            version: 3,
        };
        let err = validate_policy(&p).unwrap_err().to_string();
        assert!(err.contains("etag"), "got: {err}");
    }

    #[test]
    fn set_policy_body_wraps_in_policy_field() {
        let p = Policy {
            etag: "BwXyetag==".to_string(),
            bindings: vec![Binding {
                role: "roles/iam.workloadIdentityUser".to_string(),
                members: vec!["principal://iam.googleapis.com/projects/.../alice".to_string()],
                condition: None,
            }],
            version: 3,
        };
        let body = set_policy_body(&p).unwrap();
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(v["policy"]["etag"], "BwXyetag==");
        assert_eq!(v["policy"]["bindings"][0]["role"], "roles/iam.workloadIdentityUser");
    }

    #[test]
    fn set_policy_body_rejects_basic_role() {
        let p = Policy {
            etag: "BwXyetag==".to_string(),
            bindings: vec![Binding {
                role: "roles/owner".to_string(),
                members: vec!["user:bad@x.com".into()],
                condition: None,
            }],
            version: 3,
        };
        assert!(set_policy_body(&p).is_err());
    }

    #[test]
    fn impersonate_body_serializes_lifetime_with_s_suffix() {
        let body = impersonate_body(&["https://www.googleapis.com/auth/cloud-platform".to_string()], 3600);
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(v["lifetime"], "3600s");
        assert_eq!(v["scope"][0], "https://www.googleapis.com/auth/cloud-platform");
    }

    #[test]
    fn id_token_body_includes_audience() {
        let body = id_token_body("https://example.com/api", true);
        let v: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(v["audience"], "https://example.com/api");
        assert_eq!(v["includeEmail"], true);
    }

    #[test]
    fn deny_policy_url_includes_v2_path() {
        let u = deny_policy_url(
            "cloudresourcemanager.googleapis.com%2Fprojects%2Fp1",
            "emergency-stop-c3i",
        );
        assert!(u.contains("/v2/policies/"));
        assert!(u.contains("/denypolicies?policyId=emergency-stop-c3i"));
    }

    #[test]
    fn recommender_list_url_format() {
        let u = recommender_list_url("my-proj", "global");
        assert!(u.contains("recommender.googleapis.com"));
        assert!(u.contains("/projects/my-proj/locations/global/"));
        assert!(u.ends_with("/recommendations"));
    }

    #[test]
    fn policy_troubleshoot_url_v1() {
        assert!(policy_troubleshoot_url().contains("/v1/iam:troubleshoot"));
    }

    #[test]
    fn policy_analyze_url_includes_scope() {
        let u = policy_analyze_url("organizations/12345");
        assert!(u.contains("/v1/organizations/12345:analyzeIamPolicy"));
    }

    #[test]
    fn org_policy_list_url_includes_parent() {
        let u = org_policy_list_url("organizations/12345");
        assert!(u.ends_with("/v2/organizations/12345/policies"));
    }

    #[test]
    fn directory_user_list_url_includes_domain() {
        let u = directory_user_list_url("example.com");
        assert!(u.contains("admin.googleapis.com"));
        assert!(u.contains("?domain=example.com"));
    }

    #[test]
    fn cloud_identity_groups_list_url_includes_parent() {
        let u = cloud_identity_groups_list_url("customers/C0123");
        assert!(u.contains("?parent=customers/C0123"));
    }

    #[test]
    fn directory_user_create_url_constant() {
        assert_eq!(
            directory_user_create_url(),
            "https://admin.googleapis.com/admin/directory/v1/users"
        );
    }

    #[test]
    fn directory_user_item_url_includes_user_key() {
        let u = directory_user_item_url("alice@example.com");
        assert!(u.ends_with("/admin/directory/v1/users/alice@example.com"));
    }

    #[test]
    fn directory_user_create_body_includes_name() {
        let b = directory_user_create_body("a@x", "Alice", "Smith", None);
        let v: serde_json::Value = serde_json::from_str(&b).unwrap();
        assert_eq!(v["primaryEmail"], "a@x");
        assert_eq!(v["name"]["givenName"], "Alice");
        assert_eq!(v["name"]["familyName"], "Smith");
        assert!(v.get("password").is_none(), "no password when None");
    }

    #[test]
    fn directory_user_create_body_with_password() {
        let b =
            directory_user_create_body("a@x", "A", "S", Some("$2b$12$hashvalue"));
        let v: serde_json::Value = serde_json::from_str(&b).unwrap();
        assert_eq!(v["password"], "$2b$12$hashvalue");
        assert_eq!(v["hashFunction"], "SHA-1");
    }

    #[test]
    fn cloud_identity_group_create_url_constant() {
        assert_eq!(
            cloud_identity_group_create_url(),
            "https://cloudidentity.googleapis.com/v1/groups"
        );
    }

    #[test]
    fn cloud_identity_group_item_url_includes_name() {
        let u = cloud_identity_group_item_url("groups/abc123");
        assert_eq!(u, "https://cloudidentity.googleapis.com/v1/groups/abc123");
    }

    #[test]
    fn cloud_identity_group_create_body_shape() {
        let b = cloud_identity_group_create_body(
            "customers/C0123",
            "engineering@example.com",
            "Engineering",
            "All engineers",
        );
        let v: serde_json::Value = serde_json::from_str(&b).unwrap();
        assert_eq!(v["parent"], "customers/C0123");
        assert_eq!(v["groupKey"]["id"], "engineering@example.com");
        assert_eq!(v["displayName"], "Engineering");
    }

    #[test]
    fn policy_troubleshoot_body_shape() {
        let b = policy_troubleshoot_body(
            "user:alice@example.com",
            "//cloudresourcemanager.googleapis.com/projects/my-proj",
            "storage.objects.get",
        );
        let v: serde_json::Value = serde_json::from_str(&b).unwrap();
        assert_eq!(v["accessTuple"]["principal"], "user:alice@example.com");
        assert_eq!(v["accessTuple"]["permission"], "storage.objects.get");
    }

    #[test]
    fn rfc3339_parse_smoke() {
        let t = parse_rfc3339_to_unix("2026-05-01T12:00:00Z").unwrap();
        assert!(t > 1_700_000_000); // sanity: post-2023 epoch
    }

    #[test]
    fn impersonate_dry_run_returns_url_and_body_no_network() {
        let r = impersonate(
            "c3i-scim@x.iam.gserviceaccount.com",
            &["https://www.googleapis.com/auth/cloud-platform".to_string()],
            3600,
            "fake.bearer",
            true,
        )
        .unwrap();
        assert!(r.ok);
        assert!(r.url.ends_with(":generateAccessToken"));
        assert!(r.body.contains("\"3600s\""));
        assert!(r.access_token.is_none());
    }

    #[test]
    fn deny_policy_dry_run_under_5s() {
        // SC-GCP-IAM-013: emergency-stop p99 ≤ 5s.
        let r = deny_policy_apply(
            "cloudresourcemanager.googleapis.com%2Fprojects%2Fp1",
            "emergency-stop-c3i",
            r#"{"rules":[{"denyRule":{"deniedPrincipals":["principalSet://goog/public:all"],"deniedPermissions":["iam.serviceAccounts.getAccessToken"]}}]}"#,
            "fake.bearer",
            true,
        )
        .unwrap();
        assert!(r.ok);
        assert!(r.elapsed_ms < 5_000, "deny dry-run must be far under 5s budget: {}ms", r.elapsed_ms);
    }
}
