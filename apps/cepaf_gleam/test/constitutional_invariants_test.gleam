import cepaf_gleam/agents/hive_mind_decider.{
  AgentSignal, LongTerm24h, MediumTerm1h, ShortTerm10m,
  compute_forecast, decision_to_json, ingest_signal, init_hive_mind,
  predict_risk, synthesize_decision,
}
import cepaf_gleam/fractal/l0_constitutional.{
  Fail, Pass, Psi0Existence, Psi10CyberneticHomeostasis, Psi1Regeneration,
  Psi2History, Psi3Verification, Psi4HumanAlignment, Psi5Truthfulness,
  Psi6HardwareInviolability, Psi7ProvenanceCeiling, Psi8SubstratePurity,
  Psi9SaPlanExclusivity, PsiCheck, VoteApprove, VoteReject,
  Omega01FounderPrimacy, Omega02LineageProtection, Omega03EthicalBoundary,
  Omega04HumanSurvival, Omega05MutualTermination,
  Omega06RevisionBoundFreshness, Omega07ComputableDoctorAuthority,
  Omega08TriSovereignQuorum, Omega09HiveMindResonance,
  ReconfigurationProposal, ReconfigurationRatified, ReconfigurationRejected,
  RollbackState, cast_vote, compute_constitutional_health, evaluate_reconfiguration,
  is_zero_fenced_axiom, new_consensus, omega_directive_to_string,
  omega_mutual_termination, psi_invariant_to_string,
}
import gleam/json
import gleam/option.{None, Some}
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

  omega_directive_to_string(Omega06RevisionBoundFreshness)
  |> should.equal("Omega-0.6 Revision-Bound Freshness")

  omega_directive_to_string(Omega07ComputableDoctorAuthority)
  |> should.equal("Omega-0.7 Computable Doctor Authority")

  omega_directive_to_string(Omega08TriSovereignQuorum)
  |> should.equal("Omega-0.8 Tri-Sovereign Quorum")

  omega_directive_to_string(Omega09HiveMindResonance)
  |> should.equal("Omega-0.9 Hive Mind Resonance")
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

pub fn psi_invariant_strings_all_11_test() {
  psi_invariant_to_string(Psi0Existence)
  |> should.equal("Psi-0 Existence")

  psi_invariant_to_string(Psi1Regeneration)
  |> should.equal("Psi-1 Regeneration")

  psi_invariant_to_string(Psi2History)
  |> should.equal("Psi-2 History")

  psi_invariant_to_string(Psi3Verification)
  |> should.equal("Psi-3 Verification")

  psi_invariant_to_string(Psi4HumanAlignment)
  |> should.equal("Psi-4 Human Alignment")

  psi_invariant_to_string(Psi5Truthfulness)
  |> should.equal("Psi-5 Truthfulness")

  psi_invariant_to_string(Psi6HardwareInviolability)
  |> should.equal("Psi-6 Hardware Inviolability")

  psi_invariant_to_string(Psi7ProvenanceCeiling)
  |> should.equal("Psi-7 Provenance Ceiling")

  psi_invariant_to_string(Psi8SubstratePurity)
  |> should.equal("Psi-8 Substrate Purity")

  psi_invariant_to_string(Psi9SaPlanExclusivity)
  |> should.equal("Psi-9 Sa-Plan Exclusivity")

  psi_invariant_to_string(Psi10CyberneticHomeostasis)
  |> should.equal("Psi-10 Cybernetic Homeostasis")
}

pub fn zero_fenced_axioms_test() {
  is_zero_fenced_axiom(Psi0Existence) |> should.equal(True)
  is_zero_fenced_axiom(Psi4HumanAlignment) |> should.equal(True)
  is_zero_fenced_axiom(Psi6HardwareInviolability) |> should.equal(True)
  is_zero_fenced_axiom(Psi7ProvenanceCeiling) |> should.equal(True)
  is_zero_fenced_axiom(Psi9SaPlanExclusivity) |> should.equal(True)

  is_zero_fenced_axiom(Psi1Regeneration) |> should.equal(False)
  is_zero_fenced_axiom(Psi2History) |> should.equal(False)
  is_zero_fenced_axiom(Psi3Verification) |> should.equal(False)
  is_zero_fenced_axiom(Psi5Truthfulness) |> should.equal(False)
  is_zero_fenced_axiom(Psi8SubstratePurity) |> should.equal(False)
  is_zero_fenced_axiom(Psi10CyberneticHomeostasis) |> should.equal(False)

  // Critical zero-fencing on hardware inviolability failure
  let checks_with_psi6_fail = [
    PsiCheck(Psi0Existence, Pass, "pass"),
    PsiCheck(Psi6HardwareInviolability, Fail, "osd_wipe_blocked"),
  ]
  compute_constitutional_health(checks_with_psi6_fail)
  |> should.equal(0.0)

  // Critical zero-fencing on provenance ceiling failure
  let checks_with_psi7_fail = [
    PsiCheck(Psi0Existence, Pass, "pass"),
    PsiCheck(Psi7ProvenanceCeiling, Fail, "ev_108_unadmitted"),
  ]
  compute_constitutional_health(checks_with_psi7_fail)
  |> should.equal(0.0)

  // Critical zero-fencing on sa-plan exclusivity failure
  let checks_with_psi9_fail = [
    PsiCheck(Psi0Existence, Pass, "pass"),
    PsiCheck(Psi9SaPlanExclusivity, Fail, "unledgered_side_effect"),
  ]
  compute_constitutional_health(checks_with_psi9_fail)
  |> should.equal(0.0)
}

pub fn hive_mind_decider_test() {
  let hm = init_hive_mind()
  hm.epoch |> should.equal(1)
  hm.current_health |> should.equal(1.0)

  let signal_agy =
    AgentSignal(
      agent_id: "agy",
      signal_type: "observation",
      confidence: 0.99,
      sentiment: "harmonic",
      cognitive_narrative: "System converging rapidly to Lyapunov attractor",
      evidence_ref: "sha256-evidence-agy",
      timestamp_us: 1788880000000,
    )

  let hm2 = ingest_signal(hm, signal_agy)
  hm2.current_health |> should.equal(0.99)

  // Forecast projection
  let forecast_short = compute_forecast(hm2, ShortTerm10m)
  forecast_short.is_convergent |> should.equal(True)

  let forecast_med = compute_forecast(hm2, MediumTerm1h)
  forecast_med.is_convergent |> should.equal(True)

  let forecast_long = compute_forecast(hm2, LongTerm24h)
  forecast_long.is_convergent |> should.equal(True)

  // Risk prediction for safe action
  let safe_risk = predict_risk("prop-safe-001", "SANDISK-SDCZ48", 93, True)
  safe_risk.zero_fence_violation_risk |> should.equal(False)
  safe_risk.failure_probability |> should.equal(0.01)

  // Risk prediction for root drive violation
  let bad_drive_risk = predict_risk("prop-bad-001", "25503L801736", 93, True)
  bad_drive_risk.zero_fence_violation_risk |> should.equal(True)
  bad_drive_risk.failure_probability |> should.equal(1.0)

  // Risk prediction for unadmitted EV cycle
  let bad_ev_risk = predict_risk("prop-bad-002", "SANDISK-SDCZ48", 108, True)
  bad_ev_risk.zero_fence_violation_risk |> should.equal(True)

  // Decision synthesis: ratified safe action
  let safe_dec =
    synthesize_decision(
      hm2,
      "dec-001",
      "deploy_c3i_module",
      "SANDISK-SDCZ48",
      93,
      Some("task-c360"),
    )
  safe_dec.is_ratified |> should.equal(True)
  safe_dec.consensus_score |> should.equal(1.0)

  // Decision synthesis: rejected drive wipe action
  let bad_dec =
    synthesize_decision(
      hm2,
      "dec-002",
      "wipe_drive",
      "25503L801736",
      93,
      Some("task-c360"),
    )
  bad_dec.is_ratified |> should.equal(False)

  // JSON serialization
  let dec_json = decision_to_json(safe_dec)
  should.be_true(dec_json != json.null())
}

