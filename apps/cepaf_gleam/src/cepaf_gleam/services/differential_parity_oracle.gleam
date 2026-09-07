// =============================================================================
// [C3I-SIL6-MSTS] HERMES OCAML DIFFERENTIAL PARITY ORACLE (SC-PARITY-001, E06)
// =============================================================================
// Evaluates algebraic equivalence between Gleam/OTP control plane models and
// Hermes OCaml evidence oracles (engines/hermes).
// Verifies:
// 1. Rete-UL forward-chaining conflict resolution parity.
// 2. AST structural security anomaly classification parity.
// 3. Gospel contract precondition & postcondition parity.
// =============================================================================

import gleam/crypto
import gleam/json
import gleam/string

// -----------------------------------------------------------------------------
// 1. Types & Parity Fixtures
// -----------------------------------------------------------------------------

pub type ParityDomain {
  ReteUlRuleEngine
  AstSecurityClassifier
  GospelContractSpecification
  LyapunovStabilityProof
}

pub type ModelExecutionResult {
  ModelExecutionResult(
    engine_name: String,
    outcome_label: String,
    score: Float,
    digest_sha256: String,
    latency_us: Int,
  )
}

pub type DifferentialParityReport {
  DifferentialParityReport(
    fixture_id: String,
    domain: ParityDomain,
    gleam_result: ModelExecutionResult,
    ocaml_result: ModelExecutionResult,
    algebraic_parity: Bool,
    score_divergence: Float,
    divergence_acceptable: Bool,
    parity_certificate: String,
  )
}

// -----------------------------------------------------------------------------
// 2. Parity Evaluation Algebra
// -----------------------------------------------------------------------------

pub fn evaluate_differential_parity(
  fixture_id: String,
  domain: ParityDomain,
  gleam_result: ModelExecutionResult,
  ocaml_result: ModelExecutionResult,
  max_divergence_pct: Float,
) -> DifferentialParityReport {
  let label_match = gleam_result.outcome_label == ocaml_result.outcome_label
  let score_div =
    case gleam_result.score >=. ocaml_result.score {
      True -> gleam_result.score -. ocaml_result.score
      False -> ocaml_result.score -. gleam_result.score
    }

  let div_pct = case gleam_result.score == 0.0 && ocaml_result.score == 0.0 {
    True -> 0.0
    False -> {
      let denom = case gleam_result.score >. 0.0 {
        True -> gleam_result.score
        False -> 1.0
      }
      { score_div /. denom } *. 100.0
    }
  }

  let div_acceptable = div_pct <=. max_divergence_pct
  let parity_ok = label_match && div_acceptable

  let cert =
    compute_parity_certificate(
      fixture_id,
      domain,
      gleam_result.digest_sha256,
      ocaml_result.digest_sha256,
      parity_ok,
    )

  DifferentialParityReport(
    fixture_id: fixture_id,
    domain: domain,
    gleam_result: gleam_result,
    ocaml_result: ocaml_result,
    algebraic_parity: parity_ok,
    score_divergence: div_pct,
    divergence_acceptable: div_acceptable,
    parity_certificate: cert,
  )
}

fn compute_parity_certificate(
  fixture_id: String,
  domain: ParityDomain,
  g_digest: String,
  o_digest: String,
  passed: Bool,
) -> String {
  let pass_str = case passed {
    True -> "PARITY_CONSERVED"
    False -> "PARITY_DIVERGED"
  }
  let raw =
    fixture_id
    <> ":"
    <> domain_to_string(domain)
    <> ":"
    <> g_digest
    <> ":"
    <> o_digest
    <> ":"
    <> pass_str

  crypto.hash(crypto.Sha256, <<raw:utf8>>)
  |> string.inspect
}

pub fn domain_to_string(d: ParityDomain) -> String {
  case d {
    ReteUlRuleEngine -> "rete_ul_rule_engine"
    AstSecurityClassifier -> "ast_security_classifier"
    GospelContractSpecification -> "gospel_contract_spec"
    LyapunovStabilityProof -> "lyapunov_stability_proof"
  }
}

pub fn domain_from_string(s: String) -> Result(ParityDomain, String) {
  case string.lowercase(s) {
    "rete_ul_rule_engine" | "rete" -> Ok(ReteUlRuleEngine)
    "ast_security_classifier" | "ast" -> Ok(AstSecurityClassifier)
    "gospel_contract_spec" | "gospel" -> Ok(GospelContractSpecification)
    "lyapunov_stability_proof" | "lyapunov" -> Ok(LyapunovStabilityProof)
    _ -> Error("unknown_parity_domain: " <> s)
  }
}

// -----------------------------------------------------------------------------
// 3. JSON Serialization
// -----------------------------------------------------------------------------

pub fn execution_result_to_json(r: ModelExecutionResult) -> json.Json {
  json.object([
    #("engine_name", json.string(r.engine_name)),
    #("outcome_label", json.string(r.outcome_label)),
    #("score", json.float(r.score)),
    #("digest_sha256", json.string(r.digest_sha256)),
    #("latency_us", json.int(r.latency_us)),
  ])
}

pub fn parity_report_to_json(rep: DifferentialParityReport) -> json.Json {
  json.object([
    #("fixture_id", json.string(rep.fixture_id)),
    #("domain", json.string(domain_to_string(rep.domain))),
    #("gleam_result", execution_result_to_json(rep.gleam_result)),
    #("ocaml_result", execution_result_to_json(rep.ocaml_result)),
    #("algebraic_parity", json.bool(rep.algebraic_parity)),
    #("score_divergence_pct", json.float(rep.score_divergence)),
    #("divergence_acceptable", json.bool(rep.divergence_acceptable)),
    #("parity_certificate", json.string(rep.parity_certificate)),
  ])
}

pub fn parity_report_to_json_string(rep: DifferentialParityReport) -> String {
  parity_report_to_json(rep) |> json.to_string
}
