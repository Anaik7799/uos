//// L5 Cognitive — UI / advisory / reasoning.
//// SC-FRAC-RRF-001, SC-MSTS L5_COGNITIVE, SC-GLM-UI-001.

import cepaf_gleam/iam/objects.{
  type FractalCell, type IamObject, AccessToken, AuditEvent, FractalCell,
  GcpPolicy, GcpRecommendation, Group, Jwks, OrgPolicy, Realm, Role, ScimOp,
  Token, User,
}

pub const layer_id: String = "L5_COGNITIVE"

pub fn binding(o: IamObject) -> String {
  case o {
    User -> "Lustre /iam admin — user table row + drill-down + MFA badge"
    Group -> "Lustre /iam — group tile + member list editor"
    Role -> "Lustre /iam — role table + layer-mask visual"
    Realm -> "Lustre /iam — realm switcher + issuer_url display"
    Token -> "Lustre /iam — token panel (active sessions, recent issues)"
    Jwks -> "Lustre /iam — JWKS viewer (current + rotating keys, ages)"
    AccessToken -> "Lustre /iam — GCP STS panel (cache hits, exp countdown)"
    ScimOp -> "Lustre /iam — SCIM queue tile (depth, last error, retry timer)"
    AuditEvent ->
      "Lustre /iam — audit log scroll + filter by action/realm/outcome"
    GcpPolicy -> "Lustre /iam — policy viewer (bindings + conditions)"
    GcpRecommendation ->
      "Lustre /iam — Recommender tile (weekly review, 2oo3 to apply)"
    OrgPolicy -> "Lustre /iam — Org Policy read-only display"
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
