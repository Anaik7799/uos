//// =============================================================================
//// [C3I-SIL6-MSTS] iam/objects — canonical 12 IAM objects shared across all
//// L0-L7 fractal binding modules.
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam/objects</module></identity>
////   <fractal-topology><layer>L2_COMPONENT</layer></fractal-topology>
////   <compliance><stamp-controls>SC-FRAC-RRF-001..010</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================

/// The 12 canonical IAM objects per `.claude/rules/iam-ferriskey-nif.md`
/// §"Full fractal integration — L0-L7 × all-objects matrix".
pub type IamObject {
  User
  Group
  Role
  Realm
  Token
  Jwks
  AccessToken
  ScimOp
  AuditEvent
  GcpPolicy
  GcpRecommendation
  OrgPolicy
}

pub fn all_objects() -> List(IamObject) {
  [
    User,
    Group,
    Role,
    Realm,
    Token,
    Jwks,
    AccessToken,
    ScimOp,
    AuditEvent,
    GcpPolicy,
    GcpRecommendation,
    OrgPolicy,
  ]
}

pub fn name(o: IamObject) -> String {
  case o {
    User -> "User"
    Group -> "Group"
    Role -> "Role"
    Realm -> "Realm"
    Token -> "Token"
    Jwks -> "Jwks"
    AccessToken -> "AccessToken"
    ScimOp -> "ScimOp"
    AuditEvent -> "AuditEvent"
    GcpPolicy -> "GcpPolicy"
    GcpRecommendation -> "GcpRecommendation"
    OrgPolicy -> "OrgPolicy"
  }
}

pub type FractalCell {
  FractalCell(layer: String, object: IamObject, binding: String)
}
