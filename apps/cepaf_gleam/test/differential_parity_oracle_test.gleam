// =============================================================================
// [C3I-SIL6-MSTS] DIFFERENTIAL PARITY ORACLE TEST SUITE (SC-PARITY-001)
// =============================================================================

import cepaf_gleam/services/differential_parity_oracle.{
  AstSecurityClassifier, GospelContractSpecification, ModelExecutionResult,
  ReteUlRuleEngine,
}
import gleeunit/should

pub fn rete_ul_parity_congruence_test() {
  let gleam_res =
    ModelExecutionResult(
      engine_name: "Gleam/OTP Rete-UL",
      outcome_label: "ARBITRATE_PRIORITY_INVERSION",
      score: 25.0,
      digest_sha256: "sha256-gleam-rete-001",
      latency_us: 18,
    )

  let ocaml_res =
    ModelExecutionResult(
      engine_name: "Hermes OCaml Rete-UL Oracle",
      outcome_label: "ARBITRATE_PRIORITY_INVERSION",
      score: 25.0,
      digest_sha256: "sha256-ocaml-rete-001",
      latency_us: 42,
    )

  let report =
    differential_parity_oracle.evaluate_differential_parity(
      "fix-rete-001",
      ReteUlRuleEngine,
      gleam_res,
      ocaml_res,
      1.0,
    )

  report.algebraic_parity |> should.be_true
  report.divergence_acceptable |> should.be_true
  report.score_divergence |> should.equal(0.0)
}

pub fn ast_security_parity_divergence_detected_test() {
  let gleam_res =
    ModelExecutionResult(
      engine_name: "Gleam AST Scanner",
      outcome_label: "NUL_BYTE_INJECTION",
      score: 1.0,
      digest_sha256: "sha256-gleam-ast-001",
      latency_us: 12,
    )

  let ocaml_res =
    ModelExecutionResult(
      engine_name: "Hermes OCaml Parser Oracle",
      outcome_label: "CLEAN_PARSE",
      score: 0.0,
      digest_sha256: "sha256-ocaml-ast-001",
      latency_us: 35,
    )

  let report =
    differential_parity_oracle.evaluate_differential_parity(
      "fix-ast-002",
      AstSecurityClassifier,
      gleam_res,
      ocaml_res,
      5.0,
    )

  // Disagreeing outcome labels must flag algebraic parity divergence
  report.algebraic_parity |> should.be_false
}

pub fn gospel_contract_parity_test() {
  let gleam_res =
    ModelExecutionResult(
      engine_name: "Gleam Gospel Verifier",
      outcome_label: "CONTRACT_VALIDATED",
      score: 100.0,
      digest_sha256: "sha256-gospel-gleam",
      latency_us: 15,
    )

  let ocaml_res =
    ModelExecutionResult(
      engine_name: "Hermes Gospel Oracle",
      outcome_label: "CONTRACT_VALIDATED",
      score: 100.0,
      digest_sha256: "sha256-gospel-ocaml",
      latency_us: 28,
    )

  let report =
    differential_parity_oracle.evaluate_differential_parity(
      "fix-gospel-003",
      GospelContractSpecification,
      gleam_res,
      ocaml_res,
      0.1,
    )

  report.algebraic_parity |> should.be_true
}
