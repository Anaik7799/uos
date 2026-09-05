//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/auth/ferriskey_nif</module>
////     <fsharp-lineage>New — no F# predecessor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-FERRISKEY-NIF-001, SC-FERRISKEY-NIF-002, SC-FERRISKEY-NIF-009</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Rust cdylib NIF ↪ Erlang :ferriskey_nif module ↪ Gleam typed wrapper.
////       JSON strings cross the FFI boundary (zero-impedance). All decoding
////       happens in this module; downstream callers see typed Result(T, Error).
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Typed Gleam wrapper over the ferriskey_nif Rust cdylib.
////
//// Phase 1 surface: ping + db_init. Phases 2-5 add realm/user/group/role/
//// token/jwks/gcp_sts/gcp_iam/gcp_directory/scim — all returning JSON
//// strings decoded into typed ADTs in this module's siblings.
////
//// STAMP: SC-FERRISKEY-NIF-001..010, SC-WIRE-001 (every Model field added
////        here MUST update wiring_guard.gleam in the same commit).

import gleam/dynamic/decode
import gleam/json
import gleam/result

// ---------------------------------------------------------------------------
// External NIF bindings (Erlang module: ferriskey_nif)
// ---------------------------------------------------------------------------

@external(erlang, "ferriskey_nif", "ferriskey_ping")
fn nif_ping() -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_db_init")
fn nif_db_init(db_path: String) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_realm_create")
fn nif_realm_create(
  db_path: String,
  name: String,
  issuer_url: String,
  gcp_binding_json: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_realm_get")
fn nif_realm_get(db_path: String, id_or_name: String) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_realm_list")
fn nif_realm_list(db_path: String) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_realm_delete")
fn nif_realm_delete(db_path: String, id: String) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_user_create")
fn nif_user_create(
  db_path: String,
  realm_id: String,
  username: String,
  email: String,
  password: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_user_get")
fn nif_user_get(db_path: String, id_or_sub: String) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_user_list")
fn nif_user_list(db_path: String, realm_id: String) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_user_update")
fn nif_user_update(
  db_path: String,
  id: String,
  fields_json: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_user_delete")
fn nif_user_delete(db_path: String, id: String) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_user_password_verify")
fn nif_user_password_verify(
  db_path: String,
  id: String,
  password: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_group_create")
fn nif_group_create(
  db_path: String,
  realm_id: String,
  name: String,
  display_name: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_group_list")
fn nif_group_list(db_path: String, realm_id: String) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_group_add_member")
fn nif_group_add_member(
  db_path: String,
  group_id: String,
  user_id: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_group_remove_member")
fn nif_group_remove_member(
  db_path: String,
  group_id: String,
  user_id: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_role_create")
fn nif_role_create(
  db_path: String,
  realm_id: String,
  name: String,
  layer_mask: Int,
  requires_mfa: Bool,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_role_list")
fn nif_role_list(db_path: String, realm_id: String) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_role_assign")
fn nif_role_assign(
  db_path: String,
  user_id: String,
  role_id: String,
  granted_by: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_role_revoke")
fn nif_role_revoke(
  db_path: String,
  user_id: String,
  role_id: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_signing_key_rotate")
fn nif_signing_key_rotate(
  db_path: String,
  realm_id: String,
  alg: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_token_issue")
fn nif_token_issue(
  db_path: String,
  realm_id: String,
  user_id: String,
  audience: String,
  scopes_csv: String,
  ttl_seconds: Int,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_token_validate")
fn nif_token_validate(db_path: String, jwt: String) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_jwks_publish")
fn nif_jwks_publish(db_path: String, realm_id: String) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_jwks_get_cached")
fn nif_jwks_get_cached(
  db_path: String,
  realm_id: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_gcp_sts_exchange")
fn nif_gcp_sts_exchange(
  db_path: String,
  realm_id: String,
  sub: String,
  audience: String,
  scope: String,
  target_sa: String,
  subject_token: String,
  dry_run: Bool,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_gcp_sts_cache_get")
fn nif_gcp_sts_cache_get(
  db_path: String,
  cache_key: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_gcp_sts_cache_invalidate")
fn nif_gcp_sts_cache_invalidate(
  db_path: String,
  cache_key: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_signing_key_export_seed")
fn nif_signing_key_export_seed(
  db_path: String,
  kid: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_signing_key_purge_local")
fn nif_signing_key_purge_local(
  db_path: String,
  kid: String,
) -> Result(String, String)

@external(erlang, "ferriskey_nif", "ferriskey_token_issue_with_seed")
fn nif_token_issue_with_seed(
  db_path: String,
  realm_id: String,
  user_id: String,
  audience: String,
  scopes_csv: String,
  ttl_seconds: Int,
  kid: String,
  seed_b64: String,
) -> Result(String, String)

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

pub type PingResponse {
  PingResponse(version: String, phase: Int, runtime_ok: Bool)
}

pub type DbInitResponse {
  DbInitResponse(schema_version: Int)
}

pub type Realm {
  Realm(
    id: String,
    name: String,
    issuer_url: String,
    created_at: Int,
    updated_at: Int,
  )
}

pub type RealmGetResponse {
  RealmFound(realm: Realm)
  RealmNotFound
}

pub type User {
  User(
    id: String,
    realm_id: String,
    sub: String,
    username: String,
    email: String,
    mfa_enrolled: Bool,
    created_at: Int,
    updated_at: Int,
  )
}

pub type UserGetResponse {
  UserFound(user: User)
  UserNotFound
}

pub type PasswordVerifyResponse {
  PasswordVerify(ok: Bool, mfa_required: Bool)
}

pub type Group {
  Group(
    id: String,
    realm_id: String,
    name: String,
    display_name: String,
    created_at: Int,
    updated_at: Int,
  )
}

pub type Role {
  Role(
    id: String,
    realm_id: String,
    name: String,
    layer_mask: Int,
    requires_mfa: Bool,
    created_at: Int,
  )
}

pub type RotateResult {
  RotateResult(
    kid: String,
    alg: String,
    /// Ed25519 seed (URL-safe base64). MUST be persisted via
    /// vault_bridge.put_signing_key_seed then dropped via
    /// signing_key_purge_local. SC-FERRISKEY-NIF-010.
    seed_b64: String,
    vault_path: String,
  )
}

pub type SeedExport {
  SeedExport(kid: String, seed_b64: String, vault_path: String)
}

pub type IssuedToken {
  IssuedToken(jwt: String, exp: Int, kid: String, alg: String)
}

pub type TokenClaims {
  TokenClaims(
    iss: String,
    sub: String,
    aud: String,
    exp: Int,
    iat: Int,
    realm: String,
  )
}

pub type ValidationResult {
  ValidValid(claims: TokenClaims)
  ValidInvalid(error: String)
}

pub type JwksResponse {
  JwksResponse(jwks_json: String)
}

pub type JwksCacheResponse {
  JwksCacheResponse(jwks_json: String, age_ms: Int, hit: Bool)
}

pub type CachedToken {
  CachedToken(
    access_token: String,
    sa_principal: String,
    expires_at: Int,
    cache_key: String,
  )
}

pub type ExchangeResult {
  ExchangeResult(
    ok: Bool,
    cache_key: String,
    form_body: String,
    endpoint: String,
    cached: Result(CachedToken, Nil),
    error: Result(String, Nil),
  )
}

pub type StsCacheGetResponse {
  StsCacheHit(cached: CachedToken)
  StsCacheMiss
}

pub type IamError {
  NifNotLoaded
  DecodeFailed(String)
  IamFailure(String)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Liveness probe. Confirms the NIF loaded, runtime is bootable.
pub fn ping() -> Result(PingResponse, IamError) {
  case nif_ping() {
    Ok(json_str) -> decode_ping(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Initialize SQLite schema at the given path. Idempotent.
pub fn db_init(db_path: String) -> Result(DbInitResponse, IamError) {
  case nif_db_init(db_path) {
    Ok(json_str) -> decode_db_init(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Create a realm. Auto-seeds c3i-{admin,operator,viewer,service} roles
/// (SC-IAM-003 exhaustive mapping, layer_masks preserved from rbac.gleam).
pub fn realm_create(
  db_path: String,
  name: String,
  issuer_url: String,
  gcp_binding_json: String,
) -> Result(Realm, IamError) {
  case nif_realm_create(db_path, name, issuer_url, gcp_binding_json) {
    Ok(json_str) -> decode_realm(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Look up a realm by id or name.
pub fn realm_get(
  db_path: String,
  id_or_name: String,
) -> Result(RealmGetResponse, IamError) {
  case nif_realm_get(db_path, id_or_name) {
    Ok(json_str) -> decode_realm_get(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// List all realms.
pub fn realm_list(db_path: String) -> Result(List(Realm), IamError) {
  case nif_realm_list(db_path) {
    Ok(json_str) -> decode_realm_list(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Delete a realm by id. Returns whether it existed (cascade deletes users/
/// groups/roles per FK ON DELETE CASCADE).
pub fn realm_delete(db_path: String, id: String) -> Result(Bool, IamError) {
  case nif_realm_delete(db_path, id) {
    Ok(json_str) -> decode_realm_delete(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Create a user. Pass `password=""` for federated-only users.
pub fn user_create(
  db_path: String,
  realm_id: String,
  username: String,
  email: String,
  password: String,
) -> Result(User, IamError) {
  case nif_user_create(db_path, realm_id, username, email, password) {
    Ok(json_str) -> decode_user(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Look up a user by id or OIDC subject claim.
pub fn user_get(
  db_path: String,
  id_or_sub: String,
) -> Result(UserGetResponse, IamError) {
  case nif_user_get(db_path, id_or_sub) {
    Ok(json_str) -> decode_user_get(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// List users in a realm.
pub fn user_list(
  db_path: String,
  realm_id: String,
) -> Result(List(User), IamError) {
  case nif_user_list(db_path, realm_id) {
    Ok(json_str) -> decode_user_list(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Update user fields. `fields_json` is a JSON object with optional
/// `email`, `username`, `mfa_enrolled`, `password`, `attrs` keys.
pub fn user_update(
  db_path: String,
  id: String,
  fields_json: String,
) -> Result(UserGetResponse, IamError) {
  case nif_user_update(db_path, id, fields_json) {
    Ok(json_str) -> decode_user_update(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Delete a user. Cascades to user_roles + group_members.
pub fn user_delete(db_path: String, id: String) -> Result(Bool, IamError) {
  case nif_user_delete(db_path, id) {
    Ok(json_str) -> decode_realm_delete(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Verify password. Returns `{ok, mfa_required}`. SC-IAM-004:
/// `mfa_required = true` iff caller must step up before L0 access.
pub fn user_password_verify(
  db_path: String,
  id: String,
  password: String,
) -> Result(PasswordVerifyResponse, IamError) {
  case nif_user_password_verify(db_path, id, password) {
    Ok(json_str) -> decode_password_verify(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Create a group. Pass `display_name=""` for none.
pub fn group_create(
  db_path: String,
  realm_id: String,
  name: String,
  display_name: String,
) -> Result(Group, IamError) {
  case nif_group_create(db_path, realm_id, name, display_name) {
    Ok(json_str) -> decode_group(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

pub fn group_list(
  db_path: String,
  realm_id: String,
) -> Result(List(Group), IamError) {
  case nif_group_list(db_path, realm_id) {
    Ok(json_str) -> decode_group_list(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Add a user to a group. Idempotent. Returns `True` if newly added.
pub fn group_add_member(
  db_path: String,
  group_id: String,
  user_id: String,
) -> Result(Bool, IamError) {
  case nif_group_add_member(db_path, group_id, user_id) {
    Ok(json_str) -> decode_added(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

pub fn group_remove_member(
  db_path: String,
  group_id: String,
  user_id: String,
) -> Result(Bool, IamError) {
  case nif_group_remove_member(db_path, group_id, user_id) {
    Ok(json_str) -> decode_realm_delete(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Create a custom (non-seeded) role. SC-IAM-003 — does NOT replace
/// the seeded c3i-{admin,operator,viewer,service} roles.
pub fn role_create(
  db_path: String,
  realm_id: String,
  name: String,
  layer_mask: Int,
  requires_mfa: Bool,
) -> Result(Role, IamError) {
  case nif_role_create(db_path, realm_id, name, layer_mask, requires_mfa) {
    Ok(json_str) -> decode_role(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

pub fn role_list(
  db_path: String,
  realm_id: String,
) -> Result(List(Role), IamError) {
  case nif_role_list(db_path, realm_id) {
    Ok(json_str) -> decode_role_list(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Grant role to user. Pass `granted_by=""` for system-initiated grants.
pub fn role_assign(
  db_path: String,
  user_id: String,
  role_id: String,
  granted_by: String,
) -> Result(Bool, IamError) {
  case nif_role_assign(db_path, user_id, role_id, granted_by) {
    Ok(json_str) -> decode_assigned(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

pub fn role_revoke(
  db_path: String,
  user_id: String,
  role_id: String,
) -> Result(Bool, IamError) {
  case nif_role_revoke(db_path, user_id, role_id) {
    Ok(json_str) -> decode_realm_delete(json_str)
    Error(e) -> Error(IamFailure(e))
  }
}

// ---------------------------------------------------------------------------
// Phase 3 — token issuer + JWKS
// ---------------------------------------------------------------------------

/// Rotate signing key. Demotes previous current to rotating (7-d overlap
/// per SC-FERRISKEY-NIF-008). `alg` MUST be `"EdDSA"` in Phase 3.
pub fn signing_key_rotate(
  db_path: String,
  realm_id: String,
  alg: String,
) -> Result(RotateResult, IamError) {
  case nif_signing_key_rotate(db_path, realm_id, alg) {
    Ok(s) -> decode_rotate(s)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Issue a JWT signed by the realm's current key. `scopes_csv` is comma-separated.
pub fn token_issue(
  db_path: String,
  realm_id: String,
  user_id: String,
  audience: String,
  scopes_csv: String,
  ttl_seconds: Int,
) -> Result(IssuedToken, IamError) {
  case
    nif_token_issue(
      db_path,
      realm_id,
      user_id,
      audience,
      scopes_csv,
      ttl_seconds,
    )
  {
    Ok(s) -> decode_issued(s)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Validate a JWT. Returns `ValidValid(claims)` or `ValidInvalid(error)`.
pub fn token_validate(
  db_path: String,
  jwt: String,
) -> Result(ValidationResult, IamError) {
  case nif_token_validate(db_path, jwt) {
    Ok(s) -> decode_validation(s)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Publish the JWKS document for a realm — current + rotating keys.
/// This is the source for GCP WIF `jwks_uri` (Bridge 1).
pub fn jwks_publish(
  db_path: String,
  realm_id: String,
) -> Result(JwksResponse, IamError) {
  case nif_jwks_publish(db_path, realm_id) {
    Ok(s) -> decode_jwks_publish(s)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Hot-path JWKS read — in-process cache (5 min TTL, SC-FERRISKEY-NIF-004).
pub fn jwks_get_cached(
  db_path: String,
  realm_id: String,
) -> Result(JwksCacheResponse, IamError) {
  case nif_jwks_get_cached(db_path, realm_id) {
    Ok(s) -> decode_jwks_cache(s)
    Error(e) -> Error(IamFailure(e))
  }
}

// ---------------------------------------------------------------------------
// Phase 4 — GCP STS exchange (Bridge 2)
// ---------------------------------------------------------------------------

/// Exchange a FerrisKey JWT for a GCP access token via RFC 8693 STS.
///
/// `audience` is the GCP Workload Identity Pool resource path:
///   `//iam.googleapis.com/projects/<num>/locations/global/workloadIdentityPools/<pool>/providers/<provider>`
/// `scope` is the OAuth scope (typically `https://www.googleapis.com/auth/cloud-platform`).
/// `target_sa` is the impersonation target SA email or `""` for none.
/// `dry_run=True` returns the form body without making the network call —
/// used by tests + offline auditing.
pub fn gcp_sts_exchange(
  db_path: String,
  realm_id: String,
  sub: String,
  audience: String,
  scope: String,
  target_sa: String,
  subject_token: String,
  dry_run: Bool,
) -> Result(ExchangeResult, IamError) {
  case
    nif_gcp_sts_exchange(
      db_path,
      realm_id,
      sub,
      audience,
      scope,
      target_sa,
      subject_token,
      dry_run,
    )
  {
    Ok(s) -> decode_exchange(s)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Look up a cached GCP access token by cache_key. Returns `StsCacheMiss` if
/// the row is absent or expired.
pub fn gcp_sts_cache_get(
  db_path: String,
  cache_key: String,
) -> Result(StsCacheGetResponse, IamError) {
  case nif_gcp_sts_cache_get(db_path, cache_key) {
    Ok(s) -> decode_sts_cache_get(s)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Force-evict a cached STS token. Returns whether the row existed.
pub fn gcp_sts_cache_invalidate(
  db_path: String,
  cache_key: String,
) -> Result(Bool, IamError) {
  case nif_gcp_sts_cache_invalidate(db_path, cache_key) {
    Ok(s) -> decode_realm_delete(s)
    Error(e) -> Error(IamFailure(e))
  }
}

// ---------------------------------------------------------------------------
// Phase 8 — Vault-backed signing-key handoff (3 NIFs)
// ---------------------------------------------------------------------------

/// Export an Ed25519 seed for vault transfer. Returns `{kid, seed_b64, vault_path}`.
pub fn signing_key_export_seed(
  db_path: String,
  kid: String,
) -> Result(SeedExport, IamError) {
  case nif_signing_key_export_seed(db_path, kid) {
    Ok(s) -> decode_seed_export(s)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Drop the local SQLite copy of a signing-key seed once vault has it.
/// Idempotent. Completes SC-FERRISKEY-NIF-010.
pub fn signing_key_purge_local(
  db_path: String,
  kid: String,
) -> Result(Bool, IamError) {
  case nif_signing_key_purge_local(db_path, kid) {
    Ok(s) -> decode_realm_delete(s)
    Error(e) -> Error(IamFailure(e))
  }
}

/// Issue a JWT using a vault-supplied seed. Hot-path replacement for
/// `token_issue` once `signing_key_purge_local` has run.
pub fn token_issue_with_seed(
  db_path: String,
  realm_id: String,
  user_id: String,
  audience: String,
  scopes_csv: String,
  ttl_seconds: Int,
  kid: String,
  seed_b64: String,
) -> Result(IssuedToken, IamError) {
  case
    nif_token_issue_with_seed(
      db_path,
      realm_id,
      user_id,
      audience,
      scopes_csv,
      ttl_seconds,
      kid,
      seed_b64,
    )
  {
    Ok(s) -> decode_issued(s)
    Error(e) -> Error(IamFailure(e))
  }
}

// ---------------------------------------------------------------------------
// Decoders
// ---------------------------------------------------------------------------

fn group_decoder() -> decode.Decoder(Group) {
  use id <- decode.field("id", decode.string)
  use realm_id <- decode.field("realm_id", decode.string)
  use name <- decode.field("name", decode.string)
  use display_name <- decode.optional_field("display_name", "", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use updated_at <- decode.field("updated_at", decode.int)
  decode.success(Group(
    id:,
    realm_id:,
    name:,
    display_name:,
    created_at:,
    updated_at:,
  ))
}

fn decode_group(s: String) -> Result(Group, IamError) {
  json.parse(s, group_decoder())
  |> result.map_error(fn(_) { DecodeFailed("group") })
}

fn decode_group_list(s: String) -> Result(List(Group), IamError) {
  let decoder = {
    use groups <- decode.field("groups", decode.list(group_decoder()))
    decode.success(groups)
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("group_list") })
}

fn role_decoder() -> decode.Decoder(Role) {
  use id <- decode.field("id", decode.string)
  use realm_id <- decode.field("realm_id", decode.string)
  use name <- decode.field("name", decode.string)
  use layer_mask <- decode.field("layer_mask", decode.int)
  use requires_mfa <- decode.field("requires_mfa", decode.bool)
  use created_at <- decode.field("created_at", decode.int)
  decode.success(Role(
    id:,
    realm_id:,
    name:,
    layer_mask:,
    requires_mfa:,
    created_at:,
  ))
}

fn decode_role(s: String) -> Result(Role, IamError) {
  json.parse(s, role_decoder())
  |> result.map_error(fn(_) { DecodeFailed("role") })
}

fn decode_role_list(s: String) -> Result(List(Role), IamError) {
  let decoder = {
    use roles <- decode.field("roles", decode.list(role_decoder()))
    decode.success(roles)
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("role_list") })
}

fn decode_added(s: String) -> Result(Bool, IamError) {
  let decoder = {
    use added <- decode.field("added", decode.bool)
    decode.success(added)
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("added") })
}

fn decode_assigned(s: String) -> Result(Bool, IamError) {
  let decoder = {
    use assigned <- decode.field("assigned", decode.bool)
    decode.success(assigned)
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("assigned") })
}

fn decode_ping(s: String) -> Result(PingResponse, IamError) {
  let decoder = {
    use version <- decode.field("version", decode.string)
    use phase <- decode.field("phase", decode.int)
    decode.success(PingResponse(version:, phase:, runtime_ok: True))
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("ping") })
}

fn decode_db_init(s: String) -> Result(DbInitResponse, IamError) {
  let decoder = {
    use schema_version <- decode.field("schema_version", decode.int)
    decode.success(DbInitResponse(schema_version:))
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("db_init") })
}

fn realm_decoder() -> decode.Decoder(Realm) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use issuer_url <- decode.field("issuer_url", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use updated_at <- decode.field("updated_at", decode.int)
  decode.success(Realm(id:, name:, issuer_url:, created_at:, updated_at:))
}

fn decode_realm(s: String) -> Result(Realm, IamError) {
  json.parse(s, realm_decoder())
  |> result.map_error(fn(_) { DecodeFailed("realm") })
}

fn decode_exchange(s: String) -> Result(ExchangeResult, IamError) {
  let decoder = {
    use ok <- decode.field("ok", decode.bool)
    use cache_key <- decode.field("cache_key", decode.string)
    use form_body <- decode.field("form_body", decode.string)
    use endpoint <- decode.field("endpoint", decode.string)
    decode.success(ExchangeResult(
      ok: ok,
      cache_key: cache_key,
      form_body: form_body,
      endpoint: endpoint,
      cached: Error(Nil),
      error: Error(Nil),
    ))
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("exchange") })
}

fn cached_token_decoder() {
  use access_token <- decode.field("access_token", decode.string)
  use sa_principal <- decode.field("sa_principal", decode.string)
  use expires_at <- decode.field("expires_at", decode.int)
  use cache_key <- decode.field("cache_key", decode.string)
  decode.success(CachedToken(
    access_token: access_token,
    sa_principal: sa_principal,
    expires_at: expires_at,
    cache_key: cache_key,
  ))
}

fn decode_sts_cache_get(s: String) -> Result(StsCacheGetResponse, IamError) {
  let decoder = {
    use hit <- decode.field("hit", decode.bool)
    case hit {
      False -> decode.success(StsCacheMiss)
      True -> {
        use cached <- decode.field("cached", cached_token_decoder())
        decode.success(StsCacheHit(cached: cached))
      }
    }
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("sts_cache_get") })
}

fn decode_realm_get(s: String) -> Result(RealmGetResponse, IamError) {
  let decoder = {
    use found <- decode.field("found", decode.bool)
    case found {
      False -> decode.success(RealmNotFound)
      True -> {
        use realm <- decode.field("realm", realm_decoder())
        decode.success(RealmFound(realm:))
      }
    }
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("realm_get") })
}

fn decode_realm_list(s: String) -> Result(List(Realm), IamError) {
  let decoder = {
    use realms <- decode.field("realms", decode.list(realm_decoder()))
    decode.success(realms)
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("realm_list") })
}

fn decode_realm_delete(s: String) -> Result(Bool, IamError) {
  let decoder = {
    use existed <- decode.field("existed", decode.bool)
    decode.success(existed)
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("realm_delete") })
}

fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field("id", decode.string)
  use realm_id <- decode.field("realm_id", decode.string)
  use sub <- decode.field("sub", decode.string)
  use username <- decode.field("username", decode.string)
  use email <- decode.field("email", decode.string)
  use mfa_enrolled <- decode.field("mfa_enrolled", decode.bool)
  use created_at <- decode.field("created_at", decode.int)
  use updated_at <- decode.field("updated_at", decode.int)
  decode.success(User(
    id:,
    realm_id:,
    sub:,
    username:,
    email:,
    mfa_enrolled:,
    created_at:,
    updated_at:,
  ))
}

fn decode_user(s: String) -> Result(User, IamError) {
  json.parse(s, user_decoder())
  |> result.map_error(fn(_) { DecodeFailed("user") })
}

fn decode_user_get(s: String) -> Result(UserGetResponse, IamError) {
  let decoder = {
    use found <- decode.field("found", decode.bool)
    case found {
      False -> decode.success(UserNotFound)
      True -> {
        use user <- decode.field("user", user_decoder())
        decode.success(UserFound(user:))
      }
    }
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("user_get") })
}

fn decode_user_list(s: String) -> Result(List(User), IamError) {
  let decoder = {
    use users <- decode.field("users", decode.list(user_decoder()))
    decode.success(users)
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("user_list") })
}

/// `user_update` returns either a full User (on hit) or `{found:false}`
/// (when the id did not exist). Re-uses the user_get decode shape.
fn decode_user_update(s: String) -> Result(UserGetResponse, IamError) {
  // Try the "missed" shape first; if that fails, try to decode a full User.
  let miss_decoder = {
    use found <- decode.field("found", decode.bool)
    case found {
      False -> decode.success(UserNotFound)
      True -> decode.failure(UserNotFound, "expected_full_user")
    }
  }
  case json.parse(s, miss_decoder) {
    Ok(UserNotFound) -> Ok(UserNotFound)
    _ -> {
      json.parse(s, user_decoder())
      |> result.map(UserFound)
      |> result.map_error(fn(_) { DecodeFailed("user_update") })
    }
  }
}

fn decode_password_verify(s: String) -> Result(PasswordVerifyResponse, IamError) {
  let decoder = {
    use ok <- decode.field("ok", decode.bool)
    use mfa_required <- decode.field("mfa_required", decode.bool)
    decode.success(PasswordVerify(ok:, mfa_required:))
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("password_verify") })
}

fn decode_rotate(s: String) -> Result(RotateResult, IamError) {
  let decoder = {
    use kid <- decode.field("kid", decode.string)
    use alg <- decode.field("alg", decode.string)
    use seed_b64 <- decode.field("seed_b64", decode.string)
    use vault_path <- decode.field("vault_path", decode.string)
    decode.success(RotateResult(kid:, alg:, seed_b64:, vault_path:))
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("rotate") })
}

fn decode_seed_export(s: String) -> Result(SeedExport, IamError) {
  let decoder = {
    use kid <- decode.field("kid", decode.string)
    use seed_b64 <- decode.field("seed_b64", decode.string)
    use vault_path <- decode.field("vault_path", decode.string)
    decode.success(SeedExport(kid:, seed_b64:, vault_path:))
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("seed_export") })
}

fn decode_issued(s: String) -> Result(IssuedToken, IamError) {
  let decoder = {
    use jwt <- decode.field("jwt", decode.string)
    use exp <- decode.field("exp", decode.int)
    use kid <- decode.field("kid", decode.string)
    use alg <- decode.field("alg", decode.string)
    decode.success(IssuedToken(jwt:, exp:, kid:, alg:))
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("issued") })
}

fn claims_decoder() -> decode.Decoder(TokenClaims) {
  use iss <- decode.field("iss", decode.string)
  use sub <- decode.field("sub", decode.string)
  use aud <- decode.field("aud", decode.string)
  use exp <- decode.field("exp", decode.int)
  use iat <- decode.field("iat", decode.int)
  use realm <- decode.field("realm", decode.string)
  decode.success(TokenClaims(iss:, sub:, aud:, exp:, iat:, realm:))
}

fn decode_validation(s: String) -> Result(ValidationResult, IamError) {
  let decoder = {
    use ok <- decode.field("ok", decode.bool)
    case ok {
      False -> {
        use err <- decode.optional_field("error", "unknown", decode.string)
        decode.success(ValidInvalid(error: err))
      }
      True -> {
        use claims <- decode.field("claims", claims_decoder())
        decode.success(ValidValid(claims:))
      }
    }
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("validation") })
}

fn decode_jwks_publish(s: String) -> Result(JwksResponse, IamError) {
  let decoder = {
    use j <- decode.field("jwks_json", decode.string)
    decode.success(JwksResponse(jwks_json: j))
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("jwks_publish") })
}

fn decode_jwks_cache(s: String) -> Result(JwksCacheResponse, IamError) {
  let decoder = {
    use j <- decode.field("jwks_json", decode.string)
    use age_ms <- decode.field("age_ms", decode.int)
    use hit <- decode.field("hit", decode.bool)
    decode.success(JwksCacheResponse(jwks_json: j, age_ms:, hit:))
  }
  json.parse(s, decoder)
  |> result.map_error(fn(_) { DecodeFailed("jwks_cache") })
}
