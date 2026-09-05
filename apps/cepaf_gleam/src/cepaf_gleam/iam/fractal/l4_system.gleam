//// L4 System — process lifecycle + runtime + I/O.
//// SC-FRAC-RRF-001, SC-MSTS L4_SYSTEM.

import cepaf_gleam/iam/objects.{
  type FractalCell, type IamObject, AccessToken, AuditEvent, FractalCell,
  GcpPolicy, GcpRecommendation, Group, Jwks, OrgPolicy, Realm, Role, ScimOp,
  Token, User,
}

pub const layer_id: String = "L4_SYSTEM"

pub fn binding(o: IamObject) -> String {
  case o {
    User -> "tracing event on every NIF call (DirtyCpu/DirtyIo schedule)"
    Group -> "tracing event"
    Role -> "tracing event + RBAC enforcement gate"
    Realm -> "BEAM application config (issuer_url ↔ Wisp listening port)"
    Token -> "OnceCell<tokio::Runtime> for jwt encode/verify"
    Jwks -> "Wisp endpoint /.well-known/jwks.json — published"
    AccessToken ->
      "tokio reqwest::Client (HTTPS via rustls); SC-GCP-IAM-005 region pin"
    ScimOp -> "Wisp /scim/v2/Users + /scim/v2/Groups endpoints"
    AuditEvent -> "log rotation at 100 MB (SC-VAULT-022 sibling)"
    GcpPolicy -> "iamcredentials.googleapis.com, iam.googleapis.com endpoints"
    GcpRecommendation -> "recommender.googleapis.com endpoint (region-pinned)"
    OrgPolicy -> "orgpolicy.googleapis.com endpoint"
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
