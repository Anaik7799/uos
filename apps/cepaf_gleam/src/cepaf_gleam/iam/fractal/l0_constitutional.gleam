//// =============================================================================
//// [C3I-SIL6-MSTS] L0 Constitutional bindings for IAM objects.
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam/fractal/l0_constitutional</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-FRAC-RRF-001, SC-IAM-003, SC-IAM-004, SC-FERRISKEY-NIF-008, SC-FERRISKEY-NIF-010</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// L0 — invariants that MUST hold or the system is unsafe. Constitutional
//// safety bindings for each IAM object that touches L0.

import cepaf_gleam/iam/objects.{
  type FractalCell, type IamObject, AccessToken, AuditEvent, FractalCell,
  GcpPolicy, GcpRecommendation, Group, Jwks, OrgPolicy, Realm, Role, ScimOp,
  Token, User,
}

pub const layer_id: String = "L0_CONSTITUTIONAL"

/// Per-object L0 binding — the constitutional invariant the object must
/// preserve to remain safe. Failure to preserve this MUST trigger Jidoka
/// halt + Guardian escalation.
pub fn binding(o: IamObject) -> String {
  case o {
    User -> "Psi-2: user.delete reversible (audit-log captures pre-state)"
    Group -> "role-membership invariant: |group_members| ∈ ℕ"
    Role ->
      "layer_mask invariant: c3i-admin=0xFF, operator=0xFE, viewer=0xF0, service=0x78"
    Realm -> "issuer_url stable across rotation (GCP WIF trust anchor)"
    Token -> "Psi-3: exp > iat > 0; sig verifies under cited kid"
    Jwks ->
      "kid uniqueness; current+rotating overlap ≤ 7d (SC-FERRISKEY-NIF-008)"
    AccessToken -> "expires_at ≤ now + 55min (SC-GCP-IAM-003)"
    ScimOp -> "schema_urn ∈ canonical RFC 7643 set"
    AuditEvent -> "append-only — no UPDATE/DELETE on audit_log"
    GcpPolicy -> "etag-locked: setIamPolicy MUST cite current etag"
    GcpRecommendation -> "recommendation hash stable (idempotent re-fetch)"
    OrgPolicy -> "constraint stable; FerrisKey treats as read-only"
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
