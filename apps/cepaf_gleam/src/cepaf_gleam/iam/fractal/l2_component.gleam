//// L2 Component — pure parsers / value objects.
//// SC-FRAC-RRF-001, SC-MSTS L2_COMPONENT.

import cepaf_gleam/iam/objects.{
  type FractalCell, type IamObject, AccessToken, AuditEvent, FractalCell,
  GcpPolicy, GcpRecommendation, Group, Jwks, OrgPolicy, Realm, Role, ScimOp,
  Token, User,
}

pub const layer_id: String = "L2_COMPONENT"

pub fn binding(o: IamObject) -> String {
  case o {
    User -> "scim.User parser — RFC 7643 §4.1 schema"
    Group -> "scim.Group parser — RFC 7643 §4.2"
    Role -> "rbac.role_to_permission mapper (auth/rbac.gleam)"
    Realm -> "realm parser + issuer_url validator"
    Token -> "JWT header parser (kid extraction)"
    Jwks -> "JWK parser — kty=OKP/RSA/EC validation"
    AccessToken -> "GCP STS response parser (RFC 8693 §2.2)"
    ScimOp -> "SCIM filter AST parser — no string-concat to SQL (FMEA #4)"
    AuditEvent -> "json encoder — structured fields only (no free-form msg)"
    GcpPolicy -> "GCP allow-policy bindings parser"
    GcpRecommendation -> "Recommender response parser"
    OrgPolicy -> "OrgPolicy constraint parser"
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
