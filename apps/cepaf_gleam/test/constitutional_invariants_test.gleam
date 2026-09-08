import gleam/option.{None, Some}
import cepaf_gleam/fractal/l0_constitutional.{
  Fail, Pass, Psi0Existence, Psi1Regeneration, Psi2History, Psi3Verification,
  Psi4HumanAlignment, Psi5Truthfulness, PsiCheck, VoteApprove, VoteReject,
  Omega01FounderPrimacy, Omega02LineageProtection, Omega03EthicalBoundary,
  Omega04HumanSurvival, Omega05MutualTermination,
  ReconfigurationProposal, ReconfigurationRatified, ReconfigurationRejected,
  RollbackState, cast_vote, compute_constitutional_health, evaluate_reconfiguration,
  new_consensus, omega_directive_to_string, omega_mutual_termination,
}
import gleeunit/should

pub fn omega_directive_strings_test() {
  omega_directive_to_string(Omega01FounderPrimacy)
  |> should.equal("Omega-0.1 Founder Primacy")

  omega_directive_to_string(Omega02LineageProtection)
  |> should.equal("Omega-0.2 Lineage Protection")

  omega_directive_to_string(Omega03EthicalBoundary)
  |> should.equal("Omega-0.3 Ethical Boundary")

  omega_directive_to_string(Omega04HumanSurvival)
  |> should.equal("Omega-0.4 Human Survival")

  omega_directive_to_string(Omega05MutualTermination)
  |> should.equal("Omega-0.5 Mutual Termination")
}

pub fn omega_mutual_termination_test() {
  // Dual distinct guardian keys succeeds
  let res1 = omega_mutual_termination("guardian-agy-key", "guardian-claude-key", 1788856500)
  res1 |> should.be_ok

  // Identical guardian keys fails closed
  let res2 = omega_mutual_termination("guardian-agy-key", "guardian-agy-key", 1788856500)
  res2 |> should.be_error

  // Empty key fails closed
  let res3 = omega_mutual_termination("", "guardian-claude-key", 1788856500)
  res3 |> should.be_error
}

pub fn constitutional_health_test() {
  let psi_checks = [
    PsiCheck(Psi0Existence, Pass, "sha256-evidence-0"),
    PsiCheck(Psi1Regeneration, Pass, "sha256-evidence-1"),
    PsiCheck(Psi2History, Pass, "sha256-evidence-2"),
    PsiCheck(Psi3Verification, Pass, "sha256-evidence-3"),
    PsiCheck(Psi4HumanAlignment, Pass, "sha256-evidence-4"),
    PsiCheck(Psi5Truthfulness, Pass, "sha256-evidence-5"),
  ]

  compute_constitutional_health(psi_checks)
  |> should.equal(1.0)

  let degraded_checks = [
    PsiCheck(Psi0Existence, Pass, "sha256-evidence-0"),
    PsiCheck(Psi1Regeneration, Fail, "sha256-evidence-1"),
  ]

  compute_constitutional_health(degraded_checks)
  |> should.equal(0.5)

  compute_constitutional_health([])
  |> should.equal(0.0)
}

pub fn dcrp_reconfiguration_ratified_test() {
  let psi_checks = [
    PsiCheck(Psi0Existence, Pass, "sha256-evidence-0"),
    PsiCheck(Psi1Regeneration, Pass, "sha256-evidence-1"),
    PsiCheck(Psi2History, Pass, "sha256-evidence-2"),
    PsiCheck(Psi3Verification, Pass, "sha256-evidence-3"),
    PsiCheck(Psi4HumanAlignment, Pass, "sha256-evidence-4"),
    PsiCheck(Psi5Truthfulness, Pass, "sha256-evidence-5"),
  ]

  let prop =
    ReconfigurationProposal(
      proposal_id: "prop-dcrp-001",
      proposer_holon: "holon-governance",
      target_subsystem: "subsystem-mesh",
      description: "Migrate Indrajaal Constitution to UOS",
      psi_checks: psi_checks,
      rollback_state: Some(RollbackState("snap-001", "sha256-digest-state", True)),
      is_emergency_termination: False,
    )

  let consensus =
    new_consensus("prop-dcrp-001", 2, 3)
    |> cast_vote("guardian-agy", VoteApprove)
    |> cast_vote("guardian-codex", VoteApprove)

  let outcome = evaluate_reconfiguration(prop, consensus)
  case outcome {
    ReconfigurationRatified(id, receipt) -> {
      id |> should.equal("prop-dcrp-001")
      receipt |> should.equal("rcpt-ratified-prop-dcrp-001")
    }
    ReconfigurationRejected(_, reason) -> panic as reason
  }
}

pub fn dcrp_reconfiguration_unverified_rollback_test() {
  let psi_checks = [
    PsiCheck(Psi0Existence, Pass, "sha256-evidence-0"),
    PsiCheck(Psi1Regeneration, Pass, "sha256-evidence-1"),
    PsiCheck(Psi2History, Pass, "sha256-evidence-2"),
    PsiCheck(Psi3Verification, Pass, "sha256-evidence-3"),
    PsiCheck(Psi4HumanAlignment, Pass, "sha256-evidence-4"),
    PsiCheck(Psi5Truthfulness, Pass, "sha256-evidence-5"),
  ]

  // Missing rollback state fails closed (SC-CONST-009)
  let prop1 =
    ReconfigurationProposal(
      proposal_id: "prop-dcrp-rb-none",
      proposer_holon: "holon-governance",
      target_subsystem: "subsystem-mesh",
      description: "No rollback state provided",
      psi_checks: psi_checks,
      rollback_state: None,
      is_emergency_termination: False,
    )

  let consensus =
    new_consensus("prop-dcrp-rb-none", 2, 3)
    |> cast_vote("guardian-agy", VoteApprove)
    |> cast_vote("guardian-codex", VoteApprove)

  case evaluate_reconfiguration(prop1, consensus) {
    ReconfigurationRatified(_, _) -> panic as "Should have failed without rollback state"
    ReconfigurationRejected(id, reason) -> {
      id |> should.equal("prop-dcrp-rb-none")
      reason |> should.equal("Rollback Path Unverified")
    }
  }

  // Unverified rollback state fails closed (SC-CONST-009)
  let prop2 =
    ReconfigurationProposal(
      proposal_id: "prop-dcrp-rb-unverified",
      proposer_holon: "holon-governance",
      target_subsystem: "subsystem-mesh",
      description: "Unverified rollback state",
      psi_checks: psi_checks,
      rollback_state: Some(RollbackState("snap-002", "digest-bad", False)),
      is_emergency_termination: False,
    )

  case evaluate_reconfiguration(prop2, consensus) {
    ReconfigurationRatified(_, _) -> panic as "Should have failed with unverified rollback state"
    ReconfigurationRejected(id, reason) -> {
      id |> should.equal("prop-dcrp-rb-unverified")
      reason |> should.equal("Rollback Path Unverified")
    }
  }
}

pub fn dcrp_reconfiguration_psi_violation_test() {
  let psi_checks = [
    PsiCheck(Psi0Existence, Pass, "sha256-evidence-0"),
    PsiCheck(Psi1Regeneration, Fail, "sha256-evidence-1-tampered"),
    PsiCheck(Psi2History, Pass, "sha256-evidence-2"),
    PsiCheck(Psi3Verification, Pass, "sha256-evidence-3"),
    PsiCheck(Psi4HumanAlignment, Pass, "sha256-evidence-4"),
    PsiCheck(Psi5Truthfulness, Pass, "sha256-evidence-5"),
  ]

  let prop =
    ReconfigurationProposal(
      proposal_id: "prop-dcrp-002",
      proposer_holon: "holon-governance",
      target_subsystem: "subsystem-mesh",
      description: "Attempted unverified state migration",
      psi_checks: psi_checks,
      rollback_state: Some(RollbackState("snap-001", "digest-001", True)),
      is_emergency_termination: False,
    )

  let consensus =
    new_consensus("prop-dcrp-002", 2, 3)
    |> cast_vote("guardian-agy", VoteApprove)
    |> cast_vote("guardian-codex", VoteApprove)

  let outcome = evaluate_reconfiguration(prop, consensus)
  case outcome {
    ReconfigurationRatified(_, _) -> panic as "Should have failed due to Psi-1 violation"
    ReconfigurationRejected(id, reason) -> {
      id |> should.equal("prop-dcrp-002")
      reason |> should.equal("Constitutional Psi Axiom Violation")
    }
  }
}

pub fn dcrp_reconfiguration_guardian_veto_test() {
  let psi_checks = [
    PsiCheck(Psi0Existence, Pass, "sha256-evidence-0"),
    PsiCheck(Psi1Regeneration, Pass, "sha256-evidence-1"),
    PsiCheck(Psi2History, Pass, "sha256-evidence-2"),
    PsiCheck(Psi3Verification, Pass, "sha256-evidence-3"),
    PsiCheck(Psi4HumanAlignment, Pass, "sha256-evidence-4"),
    PsiCheck(Psi5Truthfulness, Pass, "sha256-evidence-5"),
  ]

  let prop =
    ReconfigurationProposal(
      proposal_id: "prop-dcrp-003",
      proposer_holon: "holon-governance",
      target_subsystem: "subsystem-mesh",
      description: "Controversial proposal with guardian veto",
      psi_checks: psi_checks,
      rollback_state: Some(RollbackState("snap-001", "digest-001", True)),
      is_emergency_termination: False,
    )

  let consensus =
    new_consensus("prop-dcrp-003", 2, 3)
    |> cast_vote("guardian-agy", VoteApprove)
    |> cast_vote("guardian-claude", VoteReject)

  let outcome = evaluate_reconfiguration(prop, consensus)
  case outcome {
    ReconfigurationRatified(_, _) -> panic as "Should have been rejected due to veto"
    ReconfigurationRejected(id, reason) -> {
      id |> should.equal("prop-dcrp-003")
      reason |> should.equal("Guardian Veto Invoked")
    }
  }
}
