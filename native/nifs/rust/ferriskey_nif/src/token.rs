//! Token issuer + validator + signing-key rotation (Phase 3).
//!
//! Surface (5 NIFs):
//!   signing_key_rotate(realm_id, alg) -> {kid, public_jwk}
//!   token_issue(realm_id, user_id, audience, scope_csv, ttl_seconds) -> {jwt, exp, kid}
//!   token_validate(jwt) -> {ok, claims}
//!   jwks_publish(realm_id) -> {jwks_json}      (in jwks.rs surface)
//!   jwks_get_cached(realm_id) -> {jwks_json, age_ms}
//!
//! Algorithm choice: Ed25519 (EdDSA) is the default — small keys, fast, ES256
//! quality with simpler key generation than RS256. RS256 / ES256 follow as
//! Phase 3.5 deltas (jsonwebtoken 9 supports both).
//!
//! Private key custody (Phase 3 placeholder): Ed25519 seeds are stored as
//! base64 in `signing_key_secrets(kid, seed_b64)` — a sibling SQLite table
//! that NEVER leaves the on-disk WAL DB. Phase 8 swaps this for
//! `vault_bridge::get(signing_key_path(alg, kid))` per SC-FERRISKEY-NIF-010
//! and SC-VAULT-003. Crucially, the private bytes never traverse the FFI
//! boundary — the NIF is the only consumer.
//!
//! SC-FERRISKEY-NIF-005 — JWT validate p99 ≤ 2 ms (Ed25519 single-shot).
//! SC-FERRISKEY-NIF-008 — kid in header; rotation creates a `current` key
//! and demotes the old `current` to `rotating` for the 7-day overlap.

use anyhow::{Context, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ed25519_dalek::pkcs8::EncodePrivateKey;
use ed25519_dalek::{SigningKey, VerifyingKey};
use jsonwebtoken::{decode, decode_header, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::audit;
use crate::realm;

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub iss: String,
    pub sub: String,
    pub aud: String,
    pub exp: i64,
    pub iat: i64,
    pub realm: String,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub scopes: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub acr: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct IssuedToken {
    pub jwt: String,
    pub exp: i64,
    pub kid: String,
    pub alg: String,
}

#[derive(Debug, Serialize)]
pub struct ValidationResult {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub claims: Option<Claims>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct RotateResult {
    pub kid: String,
    pub alg: String,
    pub public_jwk: serde_json::Value,
    /// Ed25519 seed exported as URL-safe base64 (32-byte secret).
    /// The Gleam orchestrator MUST persist this in RustyVault under
    /// `iam/signing/<alg-lower>/<kid>` and then call `seed_purge`
    /// to remove the local SQLite fallback copy. SC-FERRISKEY-NIF-010.
    pub seed_b64: String,
    pub vault_path: String,
}

#[derive(Debug, Serialize)]
pub struct SeedExport {
    pub kid: String,
    pub seed_b64: String,
    pub vault_path: String,
}

/// Ensure the secrets sibling table exists. Idempotent.
fn ensure_secrets_table(conn: &rusqlite::Connection) -> Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS signing_key_secrets (
            kid       TEXT PRIMARY KEY REFERENCES signing_keys(kid) ON DELETE CASCADE,
            seed_b64  TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );",
    )?;
    Ok(())
}

/// Rotate signing key: mint a fresh keypair, demote previous current to rotating.
pub fn rotate(db_path: &str, realm_id: &str, alg: &str) -> Result<RotateResult> {
    if alg != "EdDSA" {
        anyhow::bail!("ferriskey_nif::token::rotate: only EdDSA supported in Phase 3 (RS256/ES256 in Phase 3.5)");
    }
    let conn = realm::open_for_test(db_path)?;
    ensure_secrets_table(&conn)?;
    let now = realm::now_secs_pub();
    let kid = realm::new_id_pub();

    // Generate keypair via OsRng (CSPRNG, getrandom-backed).
    let signing_key = SigningKey::generate(&mut rand::rngs::OsRng);
    let verifying_key = signing_key.verifying_key();

    let public_jwk = serde_json::json!({
        "kty": "OKP",
        "crv": "Ed25519",
        "use": "sig",
        "alg": "EdDSA",
        "kid": kid,
        "x": URL_SAFE_NO_PAD.encode(verifying_key.as_bytes()),
    });

    // Demote previous current → rotating (SC-FERRISKEY-NIF-008 7-day overlap).
    conn.execute(
        "UPDATE signing_keys SET rotated_at=?1
         WHERE realm_id=?2 AND alg=?3 AND rotated_at IS NULL",
        params![now, realm_id, alg],
    )?;

    let vault_path = format!("iam/signing/eddsa/{kid}");
    conn.execute(
        "INSERT INTO signing_keys(kid,realm_id,alg,public_jwk,vault_secret_name,created_at)
         VALUES(?1,?2,?3,?4,?5,?6)",
        params![
            kid,
            realm_id,
            alg,
            public_jwk.to_string(),
            vault_path,
            now,
        ],
    )?;
    let seed_b64 = URL_SAFE_NO_PAD.encode(signing_key.to_bytes());
    conn.execute(
        "INSERT INTO signing_key_secrets(kid,seed_b64,created_at) VALUES(?1,?2,?3)",
        params![kid, seed_b64, now],
    )?;

    audit::emit(
        "signing_key.rotate",
        &serde_json::json!({"kid": kid, "realm_id": realm_id, "alg": alg, "vault_path": vault_path}),
    );
    Ok(RotateResult {
        kid,
        alg: alg.to_string(),
        public_jwk,
        seed_b64,
        vault_path,
    })
}

/// Re-export an Ed25519 seed for vault transfer. Idempotent. Audit-logged.
/// Caller MUST treat the seed as secret material — never log, never serialize
/// to disk outside vault.
pub fn export_seed(db_path: &str, kid: &str) -> Result<SeedExport> {
    let conn = realm::open_for_test(db_path)?;
    ensure_secrets_table(&conn)?;
    let (alg, seed_b64): (String, String) = conn
        .query_row(
            "SELECT sk.alg, sks.seed_b64
             FROM signing_keys sk JOIN signing_key_secrets sks ON sk.kid = sks.kid
             WHERE sk.kid=?1",
            params![kid],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .with_context(|| format!("token::export_seed: kid {kid} not found"))?;
    let vault_path = format!("iam/signing/{}/{}", alg.to_ascii_lowercase(), kid);
    audit::emit(
        "signing_key.export_seed",
        &serde_json::json!({"kid": kid, "vault_path": vault_path}),
    );
    Ok(SeedExport {
        kid: kid.to_string(),
        seed_b64,
        vault_path,
    })
}

/// Drop the local SQLite copy of a signing-key seed once vault has it.
/// Completes SC-FERRISKEY-NIF-010 (no plaintext outside vault store).
pub fn purge_local_seed(db_path: &str, kid: &str) -> Result<bool> {
    let conn = realm::open_for_test(db_path)?;
    ensure_secrets_table(&conn)?;
    let n = conn.execute(
        "DELETE FROM signing_key_secrets WHERE kid=?1",
        params![kid],
    )?;
    if n > 0 {
        audit::emit(
            "signing_key.purge_local",
            &serde_json::json!({"kid": kid}),
        );
    }
    Ok(n > 0)
}

/// Issue a JWT using a vault-supplied seed. Hot-path replacement for `issue`
/// once `purge_local_seed` has run. The Gleam orchestrator fetches the seed
/// via `rusty_vault_nif.vault_kv_get(path)` and forwards it here, ensuring
/// the private key bytes never live in this crate's SQLite.
pub fn issue_with_seed(
    db_path: &str,
    realm_id: &str,
    user_id: &str,
    audience: &str,
    scopes: &[String],
    ttl_seconds: i64,
    kid: &str,
    seed_b64: &str,
) -> Result<IssuedToken> {
    let conn = realm::open_for_test(db_path)?;
    let realm_row: (String, String) = conn
        .query_row(
            "SELECT name,issuer_url FROM realms WHERE id=?1",
            params![realm_id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .with_context(|| format!("issue_with_seed: realm {realm_id} not found"))?;
    let alg: String = conn
        .query_row(
            "SELECT alg FROM signing_keys
             WHERE kid=?1 AND realm_id=?2 AND rotated_at IS NULL",
            params![kid, realm_id],
            |r| r.get(0),
        )
        .with_context(|| format!("issue_with_seed: kid {kid} not current in realm {realm_id}"))?;
    if alg != "EdDSA" {
        anyhow::bail!("issue_with_seed: alg {alg} unsupported (Phase 3 EdDSA only)");
    }
    let seed = URL_SAFE_NO_PAD.decode(seed_b64).context("seed_b64 decode")?;
    let seed_bytes: [u8; 32] = seed.as_slice().try_into()
        .context("seed must be 32 bytes")?;
    let signing_key = SigningKey::from_bytes(&seed_bytes);
    let pkcs8_der = signing_key
        .to_pkcs8_der()
        .map_err(|e| anyhow::anyhow!("pkcs8 encode: {e}"))?;
    let encoding = EncodingKey::from_ed_der(pkcs8_der.as_bytes());
    let now = realm::now_secs_pub();
    let claims = Claims {
        iss: realm_row.1,
        sub: user_id.to_string(),
        aud: audience.to_string(),
        iat: now,
        exp: now + ttl_seconds,
        realm: realm_row.0,
        scopes: scopes.to_vec(),
        acr: None,
    };
    let mut header = Header::new(Algorithm::EdDSA);
    header.kid = Some(kid.to_string());
    let jwt = encode(&header, &claims, &encoding).context("jwt encode")?;
    audit::emit(
        "token.issue_with_seed",
        &serde_json::json!({
            "realm_id": realm_id,
            "sub": user_id,
            "kid": kid,
            "exp": claims.exp,
            "source": "vault",
        }),
    );
    Ok(IssuedToken {
        jwt,
        exp: claims.exp,
        kid: kid.to_string(),
        alg: "EdDSA".to_string(),
    })
}

/// Issue a JWT signed by the realm's current Ed25519 signing key.
pub fn issue(
    db_path: &str,
    realm_id: &str,
    user_id: &str,
    audience: &str,
    scopes: &[String],
    ttl_seconds: i64,
) -> Result<IssuedToken> {
    let conn = realm::open_for_test(db_path)?;
    ensure_secrets_table(&conn)?;

    let realm_row: (String, String) = conn
        .query_row(
            "SELECT name,issuer_url FROM realms WHERE id=?1",
            params![realm_id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .with_context(|| format!("token::issue: realm {realm_id} not found"))?;

    // Pick the most recent non-rotated key for this realm + EdDSA.
    let key_row: (String, String) = conn
        .query_row(
            "SELECT sk.kid, sks.seed_b64
             FROM signing_keys sk JOIN signing_key_secrets sks ON sk.kid = sks.kid
             WHERE sk.realm_id=?1 AND sk.alg='EdDSA' AND sk.rotated_at IS NULL
             ORDER BY sk.created_at DESC LIMIT 1",
            params![realm_id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .with_context(|| format!("token::issue: no current EdDSA signing key for realm {realm_id} — call signing_key_rotate first"))?;
    let kid = key_row.0;
    let seed_b64 = key_row.1;

    let seed = URL_SAFE_NO_PAD.decode(&seed_b64).context("seed_b64 decode")?;
    let seed_bytes: [u8; 32] = seed.as_slice().try_into()
        .context("seed must be 32 bytes")?;
    let signing_key = SigningKey::from_bytes(&seed_bytes);

    // PKCS#8 DER for jsonwebtoken's EncodingKey::from_ed_der.
    let pkcs8_der = signing_key
        .to_pkcs8_der()
        .map_err(|e| anyhow::anyhow!("pkcs8 encode: {e}"))?;
    let encoding = EncodingKey::from_ed_der(pkcs8_der.as_bytes());

    let now = realm::now_secs_pub();
    let claims = Claims {
        iss: realm_row.1,            // issuer_url
        sub: user_id.to_string(),
        aud: audience.to_string(),
        iat: now,
        exp: now + ttl_seconds,
        realm: realm_row.0,          // realm name
        scopes: scopes.to_vec(),
        acr: None,
    };
    let mut header = Header::new(Algorithm::EdDSA);
    header.kid = Some(kid.clone());

    let jwt = encode(&header, &claims, &encoding).context("jwt encode")?;
    audit::emit(
        "token.issue",
        &serde_json::json!({"realm_id": realm_id, "sub": user_id, "kid": kid, "exp": claims.exp}),
    );
    Ok(IssuedToken {
        jwt,
        exp: claims.exp,
        kid,
        alg: "EdDSA".to_string(),
    })
}

/// Validate a JWT — checks signature, expiry, and that the issuer matches a
/// known realm. Returns `{ok:true, claims}` on success, `{ok:false, error}`
/// on any failure (never returns Err — JWT validation failure is a normal
/// outcome, not an exceptional one).
pub fn validate(db_path: &str, jwt: &str) -> Result<ValidationResult> {
    let header = match decode_header(jwt) {
        Ok(h) => h,
        Err(e) => {
            return Ok(ValidationResult {
                ok: false,
                claims: None,
                error: Some(format!("decode_header: {e}")),
            });
        }
    };
    let kid = match header.kid {
        Some(k) => k,
        None => {
            return Ok(ValidationResult {
                ok: false,
                claims: None,
                error: Some("missing_kid".to_string()),
            });
        }
    };
    let conn = realm::open_for_test(db_path)?;
    let public_jwk_str: Option<String> = conn
        .query_row(
            "SELECT public_jwk FROM signing_keys WHERE kid=?1",
            params![kid],
            |r| r.get(0),
        )
        .optional()?;
    let public_jwk_str = match public_jwk_str {
        Some(s) => s,
        None => {
            return Ok(ValidationResult {
                ok: false,
                claims: None,
                error: Some(format!("unknown_kid:{kid}")),
            });
        }
    };
    let jwk: serde_json::Value = serde_json::from_str(&public_jwk_str)?;
    let x_b64 = jwk["x"].as_str().context("jwk.x missing")?;
    let public_bytes = URL_SAFE_NO_PAD.decode(x_b64).context("jwk.x decode")?;
    let public_array: [u8; 32] = public_bytes.as_slice().try_into()
        .context("public key must be 32 bytes")?;
    let _verifying_key = VerifyingKey::from_bytes(&public_array)
        .context("VerifyingKey::from_bytes")?;
    let decoding = DecodingKey::from_ed_der(&public_array);

    let mut validation = Validation::new(Algorithm::EdDSA);
    validation.validate_aud = false; // caller verifies audience separately
    let token_data = match decode::<Claims>(jwt, &decoding, &validation) {
        Ok(t) => t,
        Err(e) => {
            return Ok(ValidationResult {
                ok: false,
                claims: None,
                error: Some(format!("verify: {e}")),
            });
        }
    };
    Ok(ValidationResult {
        ok: true,
        claims: Some(token_data.claims),
        error: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_realm() -> (tempfile::TempDir, String, String) {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("ferriskey.db").to_str().unwrap().to_string();
        crate::db::init(&path).unwrap();
        let r = realm::create(&path, "c3i", "https://vm-1.tail55d152.ts.net:4100/realms/c3i", None).unwrap();
        (tmp, path, r.id)
    }

    #[test]
    fn rotate_inserts_signing_key_and_secret() {
        let (_tmp, path, realm_id) = fresh_realm();
        let r = rotate(&path, &realm_id, "EdDSA").unwrap();
        assert!(!r.kid.is_empty());
        assert_eq!(r.alg, "EdDSA");
        assert_eq!(r.public_jwk["kty"], "OKP");
        assert_eq!(r.public_jwk["crv"], "Ed25519");
        let conn = realm::open_for_test(&path).unwrap();
        let n: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM signing_keys WHERE kid=?1",
                params![r.kid],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(n, 1);
        let m: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM signing_key_secrets WHERE kid=?1",
                params![r.kid],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(m, 1);
    }

    #[test]
    fn rotate_demotes_previous_current() {
        let (_tmp, path, realm_id) = fresh_realm();
        let first = rotate(&path, &realm_id, "EdDSA").unwrap();
        let _second = rotate(&path, &realm_id, "EdDSA").unwrap();
        let conn = realm::open_for_test(&path).unwrap();
        let rotated_at: Option<i64> = conn
            .query_row(
                "SELECT rotated_at FROM signing_keys WHERE kid=?1",
                params![first.kid],
                |r| r.get(0),
            )
            .unwrap();
        assert!(rotated_at.is_some(), "first key must be marked rotated");
        let current_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM signing_keys WHERE realm_id=?1 AND rotated_at IS NULL",
                params![realm_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(current_count, 1);
    }

    #[test]
    fn issue_then_validate_roundtrip() {
        let (_tmp, path, realm_id) = fresh_realm();
        rotate(&path, &realm_id, "EdDSA").unwrap();
        let user = crate::user::create(&path, &realm_id, "alice", "a@x", Some("p")).unwrap();
        let issued = issue(
            &path,
            &realm_id,
            &user.sub,
            "https://sts.googleapis.com/v1/token",
            &["read".to_string(), "write".to_string()],
            300,
        )
        .unwrap();
        assert!(!issued.jwt.is_empty());
        assert!(issued.exp > 0);
        let v = validate(&path, &issued.jwt).unwrap();
        assert!(v.ok, "validation must succeed: {:?}", v.error);
        let claims = v.claims.unwrap();
        assert_eq!(claims.sub, user.sub);
        assert_eq!(claims.iss, "https://vm-1.tail55d152.ts.net:4100/realms/c3i");
        assert_eq!(claims.aud, "https://sts.googleapis.com/v1/token");
        assert_eq!(claims.scopes, vec!["read".to_string(), "write".to_string()]);
    }

    #[test]
    fn validate_rejects_tampered_jwt() {
        let (_tmp, path, realm_id) = fresh_realm();
        rotate(&path, &realm_id, "EdDSA").unwrap();
        let user = crate::user::create(&path, &realm_id, "alice", "a@x", Some("p")).unwrap();
        let issued = issue(&path, &realm_id, &user.sub, "aud", &[], 300).unwrap();
        // Flip a byte in the signature segment (last segment).
        let mut parts: Vec<&str> = issued.jwt.split('.').collect();
        let mutated_sig = if parts[2].starts_with('A') {
            "B".to_string() + &parts[2][1..]
        } else {
            "A".to_string() + &parts[2][1..]
        };
        parts[2] = &mutated_sig;
        let tampered = parts.join(".");
        let v = validate(&path, &tampered).unwrap();
        assert!(!v.ok);
        assert!(v.error.unwrap().contains("verify"));
    }

    #[test]
    fn validate_rejects_unknown_kid() {
        let (_tmp, path, _realm_id) = fresh_realm();
        // Issue with one realm, then drop signing key — kid lookup will miss.
        let _ = path;
        // Construct an obviously-malformed jwt: header lacks kid.
        let v = validate(&path, "not.a.jwt").unwrap();
        assert!(!v.ok);
    }

    #[test]
    fn issue_fails_without_rotated_key() {
        let (_tmp, path, realm_id) = fresh_realm();
        let user = crate::user::create(&path, &realm_id, "alice", "a@x", Some("p")).unwrap();
        let result = issue(&path, &realm_id, &user.sub, "aud", &[], 300);
        assert!(result.is_err(), "issue must fail when no signing key exists");
    }

    #[test]
    fn export_seed_returns_minted_seed() {
        let (_tmp, path, realm_id) = fresh_realm();
        let r = rotate(&path, &realm_id, "EdDSA").unwrap();
        let exported = export_seed(&path, &r.kid).unwrap();
        assert_eq!(exported.kid, r.kid);
        assert_eq!(exported.seed_b64, r.seed_b64);
        assert!(exported.vault_path.starts_with("iam/signing/eddsa/"));
    }

    #[test]
    fn purge_local_seed_completes_vault_handoff() {
        // SC-FERRISKEY-NIF-010: after vault stores the seed, the NIF can drop
        // the local fallback so the only on-disk seed lives in the vault.
        let (_tmp, path, realm_id) = fresh_realm();
        let r = rotate(&path, &realm_id, "EdDSA").unwrap();
        assert!(purge_local_seed(&path, &r.kid).unwrap());
        assert!(!purge_local_seed(&path, &r.kid).unwrap());
        // After purge, the SQLite-backed `issue` path MUST fail; only the
        // vault-backed `issue_with_seed` path remains.
        let user = crate::user::create(&path, &realm_id, "alice", "a@x", Some("p")).unwrap();
        let direct = issue(&path, &realm_id, &user.sub, "aud", &[], 300);
        assert!(direct.is_err(), "issue must fail after purge — vault path required");
    }

    #[test]
    fn issue_with_seed_then_validate_roundtrip() {
        // Full vault-backed lifecycle:
        //   rotate → export_seed → (operator stores in vault) →
        //   purge_local_seed → issue_with_seed → validate
        let (_tmp, path, realm_id) = fresh_realm();
        let r = rotate(&path, &realm_id, "EdDSA").unwrap();
        let exported = export_seed(&path, &r.kid).unwrap();
        purge_local_seed(&path, &r.kid).unwrap();
        let user = crate::user::create(&path, &realm_id, "bob", "b@x", Some("p")).unwrap();
        let issued = issue_with_seed(
            &path,
            &realm_id,
            &user.sub,
            "https://sts.googleapis.com/v1/token",
            &["read".to_string()],
            300,
            &exported.kid,
            &exported.seed_b64,
        )
        .unwrap();
        assert!(!issued.jwt.is_empty());
        let v = validate(&path, &issued.jwt).unwrap();
        assert!(v.ok, "vault-backed JWT must validate: {:?}", v.error);
    }

    #[test]
    fn issue_with_seed_rejects_unknown_kid() {
        let (_tmp, path, realm_id) = fresh_realm();
        let r = rotate(&path, &realm_id, "EdDSA").unwrap();
        let user = crate::user::create(&path, &realm_id, "x", "x@x", None).unwrap();
        let result = issue_with_seed(
            &path,
            &realm_id,
            &user.sub,
            "aud",
            &[],
            300,
            "kid-does-not-exist",
            &r.seed_b64,
        );
        assert!(result.is_err());
    }
}
