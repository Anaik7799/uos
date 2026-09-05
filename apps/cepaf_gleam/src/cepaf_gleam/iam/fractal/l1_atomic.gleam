//// =============================================================================
//// [C3I-SIL6-MSTS] L1 Atomic/NIF bindings for IAM objects.
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam/fractal/l1_atomic</module></identity>
////   <fractal-topology><layer>L1_ATOMIC_DEBUG</layer></fractal-topology>
////   <compliance><stamp-controls>SC-FERRISKEY-NIF-001..009</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// L1 — atomic NIF entry points + telemetry tracing. Each IAM object names
//// the ferriskey_nif function family that owns it.

import cepaf_gleam/iam/objects.{
  type FractalCell, type IamObject, AccessToken, AuditEvent, FractalCell,
  GcpPolicy, GcpRecommendation, Group, Jwks, OrgPolicy, Realm, Role, ScimOp,
  Token, User,
}

pub const layer_id: String = "L1_ATOMIC_DEBUG"

pub fn binding(o: IamObject) -> String {
  case o {
    User ->
      "ferriskey_user_{create,get,list,update,delete,password_verify} — bcrypt verify in NIF"
    Group -> "ferriskey_group_{create,list,add_member,remove_member}"
    Role -> "ferriskey_role_{create,list,assign,revoke}"
    Realm ->
      "ferriskey_realm_{create,get,list,delete} + auto-seed of 4 c3i-* roles"
    Token ->
      "ferriskey_token_{issue,validate,issue_with_seed} via jsonwebtoken EdDSA"
    Jwks -> "ferriskey_jwks_{publish,get_cached} + jwks_cache RwLock"
    AccessToken ->
      "ferriskey_gcp_sts_{exchange,cache_get,cache_invalidate} reqwest + tokio runtime"
    ScimOp -> "ferriskey_scim_* (Phase 5) — RFC 7643 filter AST parser"
    AuditEvent -> "audit::emit() — tracing target ferriskey_nif::audit"
    GcpPolicy ->
      "ferriskey_gcp_iam_policy_{get,set} (Phase 4.5) — etag-locked HTTP"
    GcpRecommendation -> "ferriskey_gcp_recommender_list (Phase 4.5)"
    OrgPolicy -> "ferriskey_gcp_org_policy_list (Phase 4.5) — read-only"
  }
}

pub fn cells() -> List(FractalCell) {
  objects.all_objects()
  |> list_map(fn(o) {
    FractalCell(layer: layer_id, object: o, binding: binding(o))
  })
}

fn list_map(xs: List(a), f: fn(a) -> b) -> List(b) {
  case xs {
    [] -> []
    [h, ..t] -> [f(h), ..list_map(t, f)]
  }
}
