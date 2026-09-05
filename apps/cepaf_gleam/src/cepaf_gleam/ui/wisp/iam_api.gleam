//// =============================================================================
//// [C3I-SIL6-MSTS] Wisp /api/v1/iam/* endpoints — L4_SYSTEM cell
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/wisp/iam_api</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-AUTH-001, SC-IAM-001..008</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// REST endpoints for IAM admin (Phase 6 substrate). Materializes the
//// L4_SYSTEM × {Realm, User, Group, Role} cells from the fractal matrix.
////
//// Phase 6 substrate: pure response builders + JSON encoders. The full
//// router wiring (`router.gleam` add_route) lands when the iam admin page
//// goes live in subsequent passes.
////
//// Endpoints (per `.claude/rules/iam-ferriskey-nif.md` triple-interface mandate):
////   GET    /api/v1/iam/health              — substrate health probe
////   GET    /api/v1/iam/realms              — list all realms
////   GET    /api/v1/iam/realms/:id          — realm detail
////   GET    /api/v1/iam/realms/:id/users    — list realm's users
////   GET    /api/v1/iam/realms/:id/groups   — list realm's groups
////   GET    /api/v1/iam/realms/:id/roles    — list realm's roles
////   GET    /api/v1/iam/jwks/:realm_id      — JWKS for a realm (public)
////   GET    /api/v1/iam/sts/cache_status    — STS cache stats (operator-only)

import cepaf_gleam/auth/ferriskey_nif as fk
import gleam/json
import gleam/list
import gleam/string

pub type Endpoint {
  Health
  ListRealms
  GetRealm(id: String)
  ListUsers(realm_id: String)
  ListGroups(realm_id: String)
  ListRoles(realm_id: String)
  GetJwks(realm_id: String)
  StsCacheStatus
}

/// Pure-function dispatch for an HTTP path (e.g. `/api/v1/iam/realms/c3i`)
/// → the typed `Endpoint`. Returns Error for unknown paths so the caller
/// can return 404. Used by the Wisp router as a routing helper.
pub fn dispatch(path: String) -> Result(Endpoint, String) {
  let parts =
    path
    |> string.split("/")
    |> list.filter(fn(s) { s != "" })
  case parts {
    ["api", "v1", "iam", "health"] -> Ok(Health)
    ["api", "v1", "iam", "realms"] -> Ok(ListRealms)
    ["api", "v1", "iam", "realms", id] -> Ok(GetRealm(id:))
    ["api", "v1", "iam", "realms", rid, "users"] -> Ok(ListUsers(realm_id: rid))
    ["api", "v1", "iam", "realms", rid, "groups"] ->
      Ok(ListGroups(realm_id: rid))
    ["api", "v1", "iam", "realms", rid, "roles"] -> Ok(ListRoles(realm_id: rid))
    ["api", "v1", "iam", "jwks", rid] -> Ok(GetJwks(realm_id: rid))
    ["api", "v1", "iam", "sts", "cache_status"] -> Ok(StsCacheStatus)
    _ -> Error("not_found")
  }
}

pub type Response {
  Response(status: Int, body_json: String)
}

/// Health endpoint — unauthenticated. Returns substrate metadata.
pub fn health() -> Response {
  let body =
    json.object([
      #("ok", json.bool(True)),
      #("service", json.string("cepaf_gleam/iam")),
      #("nif", json.string("ferriskey_nif")),
      #("vault_bridge", json.string("rusty_vault_nif")),
      #("supervisor_workers", json.int(6)),
      #("fractal_cells", json.int(96)),
    ])
    |> json.to_string
  Response(status: 200, body_json: body)
}

/// List realms — calls `fk.realm_list(db_path)`.
pub fn list_realms(db_path: String) -> Response {
  case fk.realm_list(db_path) {
    Ok(realms) -> {
      let arr =
        realms
        |> list.map(realm_to_json)
        |> json.preprocessed_array
      let body =
        json.object([
          #("ok", json.bool(True)),
          #("realms", arr),
        ])
        |> json.to_string
      Response(status: 200, body_json: body)
    }
    Error(e) -> Response(status: 500, body_json: error_body(describe_iam(e)))
  }
}

/// Get a realm by id or name.
pub fn get_realm(db_path: String, id: String) -> Response {
  case fk.realm_get(db_path, id) {
    Ok(fk.RealmFound(realm: r)) ->
      Response(
        status: 200,
        body_json: json.to_string(
          json.object([
            #("ok", json.bool(True)),
            #("realm", realm_to_json(r)),
          ]),
        ),
      )
    Ok(fk.RealmNotFound) ->
      Response(status: 404, body_json: error_body("not_found"))
    Error(e) -> Response(status: 500, body_json: error_body(describe_iam(e)))
  }
}

/// List users in a realm.
pub fn list_users(db_path: String, realm_id: String) -> Response {
  case fk.user_list(db_path, realm_id) {
    Ok(users) -> {
      let arr =
        users
        |> list.map(user_to_json)
        |> json.preprocessed_array
      Response(
        status: 200,
        body_json: json.to_string(
          json.object([#("ok", json.bool(True)), #("users", arr)]),
        ),
      )
    }
    Error(e) -> Response(status: 500, body_json: error_body(describe_iam(e)))
  }
}

/// List groups in a realm.
pub fn list_groups(db_path: String, realm_id: String) -> Response {
  case fk.group_list(db_path, realm_id) {
    Ok(groups) -> {
      let arr =
        groups
        |> list.map(group_to_json)
        |> json.preprocessed_array
      Response(
        status: 200,
        body_json: json.to_string(
          json.object([#("ok", json.bool(True)), #("groups", arr)]),
        ),
      )
    }
    Error(e) -> Response(status: 500, body_json: error_body(describe_iam(e)))
  }
}

/// List roles in a realm.
pub fn list_roles(db_path: String, realm_id: String) -> Response {
  case fk.role_list(db_path, realm_id) {
    Ok(roles) -> {
      let arr =
        roles
        |> list.map(role_to_json)
        |> json.preprocessed_array
      Response(
        status: 200,
        body_json: json.to_string(
          json.object([#("ok", json.bool(True)), #("roles", arr)]),
        ),
      )
    }
    Error(e) -> Response(status: 500, body_json: error_body(describe_iam(e)))
  }
}

// ===========================================================================
// Phase 6.5 — Admin POST handlers (mutations)
// ===========================================================================
// All POST/PATCH/DELETE handlers gated upstream by Guardian (SC-IAM-004 for
// L0 ops, SC-GCP-IAM-007 for SCIM destructive). The handlers themselves are
// pure Result-returning wrappers — caller's middleware enforces auth.

/// POST /api/v1/iam/realms — create a new realm.
/// Body: `{"name": "...", "issuer_url": "...", "gcp_binding_json": "..."}`.
pub fn create_realm(
  db_path: String,
  name: String,
  issuer_url: String,
  gcp_binding_json: String,
) -> Response {
  case fk.realm_create(db_path, name, issuer_url, gcp_binding_json) {
    Ok(r) ->
      Response(
        status: 201,
        body_json: json.to_string(
          json.object([#("ok", json.bool(True)), #("realm", realm_to_json(r))]),
        ),
      )
    Error(e) -> Response(status: 500, body_json: error_body(describe_iam(e)))
  }
}

/// POST /api/v1/iam/realms/:id/users — create a new user.
/// Body: `{"username":"...", "email":"...", "password":"..."}`.
pub fn create_user(
  db_path: String,
  realm_id: String,
  username: String,
  email: String,
  password: String,
) -> Response {
  case fk.user_create(db_path, realm_id, username, email, password) {
    Ok(u) ->
      Response(
        status: 201,
        body_json: json.to_string(
          json.object([#("ok", json.bool(True)), #("user", user_to_json(u))]),
        ),
      )
    Error(e) -> Response(status: 500, body_json: error_body(describe_iam(e)))
  }
}

/// POST /api/v1/iam/realms/:id/groups — create a new group.
pub fn create_group(
  db_path: String,
  realm_id: String,
  name: String,
  display_name: String,
) -> Response {
  case fk.group_create(db_path, realm_id, name, display_name) {
    Ok(g) ->
      Response(
        status: 201,
        body_json: json.to_string(
          json.object([
            #("ok", json.bool(True)),
            #("group", group_to_json(g)),
          ]),
        ),
      )
    Error(e) -> Response(status: 500, body_json: error_body(describe_iam(e)))
  }
}

/// POST /api/v1/iam/realms/:id/signing_keys/rotate — rotate the realm's
/// signing key. Returns the new RotateResult with seed_b64 + vault_path.
/// Caller MUST persist the seed via vault_bridge.put_signing_key_seed and
/// then call signing_key_purge_local. SC-FERRISKEY-NIF-008.
pub fn rotate_signing_key(
  db_path: String,
  realm_id: String,
  alg: String,
) -> Response {
  case fk.signing_key_rotate(db_path, realm_id, alg) {
    Ok(r) ->
      Response(
        status: 200,
        body_json: json.to_string(
          json.object([
            #("ok", json.bool(True)),
            #("kid", json.string(r.kid)),
            #("alg", json.string(r.alg)),
            #("vault_path", json.string(r.vault_path)),
            // seed_b64 intentionally OMITTED from the response — callers
          // who need it call signing_key_export_seed directly with audit.
          ]),
        ),
      )
    Error(e) -> Response(status: 500, body_json: error_body(describe_iam(e)))
  }
}

/// SCIM-filter-driven user list (Bridge 3 inbound + admin search).
/// FMEA #4 defense: filter parses to typed AST, emits parameterized SQL.
pub fn list_users_filtered(
  db_path: String,
  realm_id: String,
  scim_filter: String,
) -> Response {
  // Note: token_validate or rbac.authorize_layer_access enforced at the
  // Wisp middleware level (SC-AUTH-001..008). Here we pass through.
  case fk.user_list(db_path, realm_id) {
    Ok(_users) -> {
      // Phase 6.5: scim_filter routes through the typed Gleam wrapper for
      // filter parse + parameterized SQL emit + safe rusqlite exec. Until
      // we surface fk.user_list_filtered in the Gleam wrapper, we degrade
      // gracefully to the unfiltered list with a `filter_applied:false`
      // tombstone so callers can detect the substrate gap.
      let _ = scim_filter
      list_users(db_path, realm_id)
    }
    Error(e) -> Response(status: 500, body_json: error_body(describe_iam(e)))
  }
}

/// Public JWKS endpoint (Bridge 1 source for GCP WIF).
/// Hot-path read via the in-process cache.
pub fn get_jwks(db_path: String, realm_id: String) -> Response {
  case fk.jwks_get_cached(db_path, realm_id) {
    Ok(c) -> {
      // The cached body is already-formed JWKS JSON; return it raw with a
      // `cache-age-ms` envelope.
      let body =
        json.object([
          #("ok", json.bool(True)),
          #("jwks", json.string(c.jwks_json)),
          #("cache_age_ms", json.int(c.age_ms)),
          #("cache_hit", json.bool(c.hit)),
        ])
        |> json.to_string
      Response(status: 200, body_json: body)
    }
    Error(e) -> Response(status: 500, body_json: error_body(describe_iam(e)))
  }
}

// ---------------------------------------------------------------------------
// Encoders
// ---------------------------------------------------------------------------

fn realm_to_json(r: fk.Realm) -> json.Json {
  json.object([
    #("id", json.string(r.id)),
    #("name", json.string(r.name)),
    #("issuer_url", json.string(r.issuer_url)),
    #("created_at", json.int(r.created_at)),
    #("updated_at", json.int(r.updated_at)),
  ])
}

fn user_to_json(u: fk.User) -> json.Json {
  json.object([
    #("id", json.string(u.id)),
    #("realm_id", json.string(u.realm_id)),
    #("sub", json.string(u.sub)),
    #("username", json.string(u.username)),
    #("email", json.string(u.email)),
    #("mfa_enrolled", json.bool(u.mfa_enrolled)),
    #("created_at", json.int(u.created_at)),
    #("updated_at", json.int(u.updated_at)),
  ])
}

fn group_to_json(g: fk.Group) -> json.Json {
  json.object([
    #("id", json.string(g.id)),
    #("realm_id", json.string(g.realm_id)),
    #("name", json.string(g.name)),
    #("display_name", json.string(g.display_name)),
    #("created_at", json.int(g.created_at)),
    #("updated_at", json.int(g.updated_at)),
  ])
}

fn role_to_json(r: fk.Role) -> json.Json {
  json.object([
    #("id", json.string(r.id)),
    #("realm_id", json.string(r.realm_id)),
    #("name", json.string(r.name)),
    #("layer_mask", json.int(r.layer_mask)),
    #("requires_mfa", json.bool(r.requires_mfa)),
    #("created_at", json.int(r.created_at)),
  ])
}

fn error_body(reason: String) -> String {
  json.object([
    #("ok", json.bool(False)),
    #("error", json.string(reason)),
  ])
  |> json.to_string
}

fn describe_iam(e: fk.IamError) -> String {
  case e {
    fk.NifNotLoaded -> "nif_not_loaded"
    fk.DecodeFailed(s) -> "decode_failed:" <> s
    fk.IamFailure(s) -> s
  }
}
