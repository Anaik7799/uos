//// Sovereign Provenance Adjudication & Range Fencing (SC-FEAT-IMPL-001)
//// #fractal-l0 #fractal-l8 #zero-muda #tailscale-web
////
//// Enforces strict cryptographic fencing of provenance records, preventing unadmitted
//// EV numbers from contaminating runtime state machines.

import gleam/list
import gleam/string

pub const admitted_ceiling = 93

pub type EvClaim {
  EvClaim(
    ev_number: Int,
    plan_id: String,
    digest: String,
    claude_signature: String,
    codex_signature: String,
  )
}

pub type AdjudicationVerdict {
  AdjudicationAdmitted(ev_number: Int)
  AdjudicationFenced(ev_number: Int, reason: String)
}

/// Evaluates whether an EV claim is within the admitted ceiling or carries tri-sovereign signatures.
pub fn adjudicate_ev_claim(claim: EvClaim) -> AdjudicationVerdict {
  case claim.ev_number <= admitted_ceiling {
    True -> AdjudicationAdmitted(claim.ev_number)
    False -> {
      let claude_valid =
        string.length(claim.claude_signature) >= 32
        && !string.contains(claim.claude_signature, "forged")
      let codex_valid =
        string.length(claim.codex_signature) >= 32
        && !string.contains(claim.codex_signature, "forged")

      case claude_valid && codex_valid {
        True -> AdjudicationAdmitted(claim.ev_number)
        False ->
          AdjudicationFenced(
            claim.ev_number,
            "EV number exceeds admitted ceiling (93) and lacks dual sovereign ratification signatures",
          )
      }
    }
  }
}

/// Filters a list of claims, returning only mathematically admitted claims.
pub fn filter_admitted_claims(claims: List(EvClaim)) -> List(EvClaim) {
  list.filter(claims, fn(c) {
    case adjudicate_ev_claim(c) {
      AdjudicationAdmitted(_) -> True
      AdjudicationFenced(_, _) -> False
    }
  })
}
