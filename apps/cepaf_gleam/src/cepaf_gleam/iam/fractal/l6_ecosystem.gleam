//// L6 Ecosystem — Zenoh mesh + cross-node coordination.
//// SC-FRAC-RRF-001, SC-MSTS L6_ECOSYSTEM, SC-ZMOF-001, SC-FERRISKEY-NIF-006.

import cepaf_gleam/iam/objects.{
  type FractalCell, type IamObject, AccessToken, AuditEvent, FractalCell,
  GcpPolicy, GcpRecommendation, Group, Jwks, OrgPolicy, Realm, Role, ScimOp,
  Token, User,
}

pub const layer_id: String = "L6_ECOSYSTEM"

/// Each IAM object's Zenoh topic (full canonical key expression).
pub fn zenoh_topic(o: IamObject) -> String {
  case o {
    User -> "indrajaal/l0/iam/user/**"
    Group -> "indrajaal/l0/iam/group/**"
    Role -> "indrajaal/l0/iam/role/**"
    Realm -> "indrajaal/l0/iam/realm/**"
    Token -> "indrajaal/l0/iam/token/**"
    Jwks -> "indrajaal/l0/iam/jwks/**"
    AccessToken -> "indrajaal/l7/fed/gcp_sts/**"
    ScimOp -> "indrajaal/l7/fed/scim/**"
    AuditEvent -> "indrajaal/l0/iam/audit/**"
    GcpPolicy -> "indrajaal/l7/fed/gcp_iam/policy/**"
    GcpRecommendation -> "indrajaal/l7/fed/gcp_iam/recommend/**"
    OrgPolicy -> "indrajaal/l7/fed/gcp_iam/org_policy/**"
  }
}

pub fn binding(o: IamObject) -> String {
  "Zenoh topic: " <> zenoh_topic(o)
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
