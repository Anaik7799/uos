//// L7 Federation — multi-node consensus + cross-cloud federation.
//// SC-FRAC-RRF-001, SC-MSTS L7_FEDERATION, SC-GCP-IAM-001..020.

import cepaf_gleam/iam/objects.{
  type FractalCell, type IamObject, AccessToken, AuditEvent, FractalCell,
  GcpPolicy, GcpRecommendation, Group, Jwks, OrgPolicy, Realm, Role, ScimOp,
  Token, User,
}

pub const layer_id: String = "L7_FEDERATION"

pub fn binding(o: IamObject) -> String {
  case o {
    User -> "Cloud Identity SCIM peer — inbound provisioning from Workspace"
    Group -> "Admin SDK Directory peer + Cloud Identity Groups peer (outbound)"
    Role -> "n/a — local-only (RBAC is C3I-internal authority)"
    Realm -> "GCP Workload Identity Pool resource — c3i-ferriskey-pool"
    Token -> "GCP STS subject token (RFC 8693) — Bridge 2"
    Jwks -> "GCP WIF jwks_uri fetch (Bridge 1)"
    AccessToken -> "GCP STS issuer (sts.googleapis.com)"
    ScimOp -> "Cloud Identity SCIM client — bidirectional sync"
    AuditEvent ->
      "Cloud Logging sink — c3i-iam-audit log bucket (europe-north1)"
    GcpPolicy -> "GCP IAM allow-policy peer — setIamPolicy / getIamPolicy"
    GcpRecommendation -> "GCP Recommender peer — analyzeIamPolicy results"
    OrgPolicy -> "GCP Organization Policy Service peer — read-only"
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
