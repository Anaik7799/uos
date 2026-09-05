//// L3 Transaction — DB CRUD + state mutations.
//// SC-FRAC-RRF-001, SC-MSTS L3_TRANSACTION, SC-FERRISKEY-NIF-007.

import cepaf_gleam/iam/objects.{
  type FractalCell, type IamObject, AccessToken, AuditEvent, FractalCell,
  GcpPolicy, GcpRecommendation, Group, Jwks, OrgPolicy, Realm, Role, ScimOp,
  Token, User,
}

pub const layer_id: String = "L3_TRANSACTION"

pub fn binding(o: IamObject) -> String {
  case o {
    User ->
      "users table — INSERT/UPDATE/DELETE with FK cascade to user_roles + group_members"
    Group -> "groups table + group_members N:M"
    Role -> "roles table + user_roles N:M (granted_at, granted_by audited)"
    Realm -> "realms table — DELETE cascades to all child entities"
    Token -> "no persistence (stateless JWT)"
    Jwks -> "signing_keys table — current/rotating/retired status machine"
    AccessToken -> "gcp_sts_cache table — expires_at-aware, indexed"
    ScimOp -> "scim_outbound_queue table — durable retry, exponential backoff"
    AuditEvent ->
      "audit_log table — append-only INSERT, no UPDATE/DELETE (SC-VALUE-GUARD-001)"
    GcpPolicy -> "no local persistence (GCP-side authoritative)"
    GcpRecommendation -> "no local persistence (Recommender API authoritative)"
    OrgPolicy -> "no local persistence (Org Policy authoritative)"
  }
}

pub fn cells() -> List(FractalCell) {
  list_map(objects.all_objects(), fn(o) {
    FractalCell(layer: layer_id, object: o, binding: binding(o))
  })
}

fn list_map(xs: List(a), f: fn(a) -> b) -> List(b) {
  case xs {
    [] -> []
    [h, ..t] -> [f(h), ..list_map(t, f)]
  }
}
