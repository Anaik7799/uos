// ==============================================================================
// [UOS-SDLC-SRE-TEST] Comprehensive Test Suite for SDLC, SRE & Verification
// ==============================================================================

import cepaf_gleam/sdlc/sdlc_sre_process_engine.{
  CastIncidentRecord, DivergenceRecord, EquivExactParity,
  EquivJustifiedDivergence, HazardH4StorageInterlockBypassed,
  LossL1FalseConformance, MutantKilled, MutantRecord, MutantSurvived, TierEpoch,
  TierOperation, TierPin, TierSlice, TierTask, algebraic_step_name,
  canonical_algebraic_steps, canonical_lifecycle_specs, check_stpa_hazard_safety,
  evaluate_divergence_ledger, format_cast_incident_entry,
  lifecycle_tier_to_string, stpa_loss_to_string, verify_slice_mutation_adequacy,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn lifecycle_specs_completeness_test() {
  let specs = canonical_lifecycle_specs()
  list.length(specs) |> should.equal(5)

  let tiers = list.map(specs, fn(s) { s.tier })
  tiers
  |> should.equal([TierOperation, TierTask, TierSlice, TierEpoch, TierPin])

  let names = list.map(tiers, lifecycle_tier_to_string)
  names |> should.equal(["Operation", "Task", "Slice", "Epoch", "Pin"])
}

pub fn algebraic_steps_completeness_test() {
  let steps = canonical_algebraic_steps()
  list.length(steps) |> should.equal(9)

  let first_step = list.first(steps)
  let assert Ok(s1) = first_step
  algebraic_step_name(s1) |> should.equal("1. Semantic Domain")
}

pub fn stpa_hazard_and_losses_test() {
  stpa_loss_to_string(LossL1FalseConformance)
  |> string.contains("False Conformance Claim")
  |> should.equal(True)

  // NVMe OS drive 25503L801736 must fail safety check for Hazard H4
  check_stpa_hazard_safety(HazardH4StorageInterlockBypassed, "25503L801736")
  |> should.equal(False)

  // Secondary/data drive passes
  check_stpa_hazard_safety(HazardH4StorageInterlockBypassed, "S67NNX0W123456")
  |> should.equal(True)
}

pub fn mutation_adequacy_scoring_test() {
  let passing_mutants = [
    MutantRecord(
      id: "MUT-01",
      slice_id: "SLICE-FPP-01",
      target_file: "agent_taxonomy.gleam",
      mutation_desc: "Flip base-ID disjointness comparator",
      expected_failing_law: "LAW-DMC-DISJOINT",
      verdict: MutantKilled("base_id_window_disjointness_dmc_test"),
    ),
    MutantRecord(
      id: "MUT-02",
      slice_id: "SLICE-FPP-01",
      target_file: "master_verification_registry.gleam",
      mutation_desc: "Return 72 instead of 96 agents",
      expected_failing_law: "LAW-AGENT-COUNT",
      verdict: MutantKilled("master_c3i_96_agent_ecology_test"),
    ),
  ]

  let #(total, killed, equiv, rate, passes) =
    verify_slice_mutation_adequacy(passing_mutants)
  total |> should.equal(2)
  killed |> should.equal(2)
  equiv |> should.equal(0)
  rate |> should.equal(1.0)
  passes |> should.equal(True)

  // Test failing scenario with a survived mutant
  let failing_mutants = [
    MutantRecord(
      id: "MUT-03",
      slice_id: "SLICE-FPP-02",
      target_file: "intent.gleam",
      mutation_desc: "Unchecked drive access",
      expected_failing_law: "LAW-STORAGE-INTERLOCK",
      verdict: MutantSurvived("Test suite did not assert drive serial"),
    ),
  ]
  let #(_t2, _k2, _e2, _r2, passes2) =
    verify_slice_mutation_adequacy(failing_mutants)
  passes2 |> should.equal(False)
}

pub fn divergence_ledger_evaluation_test() {
  let records = [
    DivergenceRecord(
      id: "DIV-01",
      opcode_or_function: "lists:map/2",
      pinned_oracle: "OTP-30.0-rc0",
      verdict: EquivExactParity,
      plan_reference: "OTP30_PARITY_PLAN.md §10",
    ),
    DivergenceRecord(
      id: "DIV-02",
      opcode_or_function: "on_load/1",
      pinned_oracle: "OTP-30.0-rc0",
      verdict: EquivJustifiedDivergence("Deferred to Epoch E4 dynamic loader"),
      plan_reference: "OTP30_E1_PLAN.md Task 15",
    ),
  ]

  let #(total, exact, justified, passes) = evaluate_divergence_ledger(records)
  total |> should.equal(2)
  exact |> should.equal(1)
  justified |> should.equal(1)
  passes |> should.equal(True)
}

pub fn cast_incident_formatting_test() {
  let incident =
    CastIncidentRecord(
      incident_id: "CAST-20260906-01",
      timestamp: "2026-09-06T11:00:00Z",
      red_gate_name: "G-CHECKLIST",
      root_cause: "Missing fractal tag in generated markdown",
      uca_prevented: "UCA-DOC-UNVERIFIED",
      resolution_status: "RESOLVED",
    )

  let entry = format_cast_incident_entry(incident)
  string.contains(entry, "CAST-20260906-01") |> should.equal(True)
  string.contains(entry, "G-CHECKLIST") |> should.equal(True)
  string.contains(entry, "RESOLVED") |> should.equal(True)
}

pub fn smt_evidence_obligation_test() {
  // Test valid proof: negation asserted, Unsat returned, and non-trivial control Sat
  sdlc_sre_process_engine.evaluate_smt_obligation(
    True,
    sdlc_sre_process_engine.SmtUnsat,
    True,
  )
  |> should.equal(True)

  // Fail case 1: Theorem asserted directly instead of negation
  sdlc_sre_process_engine.evaluate_smt_obligation(
    False,
    sdlc_sre_process_engine.SmtUnsat,
    True,
  )
  |> should.equal(False)

  // Fail case 2: Solver returned Sat (counterexample exists)
  sdlc_sre_process_engine.evaluate_smt_obligation(
    True,
    sdlc_sre_process_engine.SmtSat("x = 0"),
    True,
  )
  |> should.equal(False)

  // Fail case 3: Solver returned Unknown (must fail closed)
  sdlc_sre_process_engine.evaluate_smt_obligation(
    True,
    sdlc_sre_process_engine.SmtUnknown,
    True,
  )
  |> should.equal(False)

  // Fail case 4: Negative control was not Sat (tautology / vacuous proof caught)
  sdlc_sre_process_engine.evaluate_smt_obligation(
    True,
    sdlc_sre_process_engine.SmtUnsat,
    False,
  )
  |> should.equal(False)
}

pub fn chaos_invariant_test() {
  // Safe run: invariant holds
  let verdict_pass =
    sdlc_sre_process_engine.evaluate_chaos_experiment(
      sdlc_sre_process_engine.FaultClockSkewInjection,
      True,
    )
  case verdict_pass {
    sdlc_sre_process_engine.ChaosInvariantHeld(_) -> True
    _ -> False
  }
  |> should.equal(True)

  // Unsafe run: invariant violated -> trips STPA hazard and loss
  let verdict_fail =
    sdlc_sre_process_engine.evaluate_chaos_experiment(
      sdlc_sre_process_engine.FaultConcurrentWriterContention,
      False,
    )
  case verdict_fail {
    sdlc_sre_process_engine.ChaosInvariantViolated(hazard, loss) -> {
      hazard |> should.equal(sdlc_sre_process_engine.HazardH3EvidenceDiverged)
      loss |> should.equal(sdlc_sre_process_engine.LossL3EvidenceContamination)
      True
    }
    _ -> False
  }
  |> should.equal(True)
}

pub fn fixture_totality_rule_test() {
  // Symmetric operands tested and real artifact executed
  sdlc_sre_process_engine.check_fixture_totality(True, True)
  |> should.equal(True)

  // Missing symmetric operand position test
  sdlc_sre_process_engine.check_fixture_totality(False, True)
  |> should.equal(False)

  // Missing real artifact execution
  sdlc_sre_process_engine.check_fixture_totality(True, False)
  |> should.equal(False)
}

pub fn bayesian_forecasting_preflight_test() {
  let spec =
    sdlc_sre_process_engine.BayesianForecastingSpec(
      prior_duration_ms: 120.0,
      variance: 15.0,
      observed_fuel: 450,
      confidence_interval: 0.95,
    )

  // Within budget
  case sdlc_sre_process_engine.evaluate_forecasting_preflight(spec, 1000) {
    sdlc_sre_process_engine.ForecastWithinBudget(remaining) -> {
      remaining |> should.equal(550)
      True
    }
    _ -> False
  }
  |> should.equal(True)

  // Budget exhausted
  case sdlc_sre_process_engine.evaluate_forecasting_preflight(spec, 300) {
    sdlc_sre_process_engine.ForecastBudgetExhausted(required, quota) -> {
      required |> should.equal(450)
      quota |> should.equal(300)
      True
    }
    _ -> False
  }
  |> should.equal(True)
}

pub fn component_packet_validation_test() {
  let valid_packet =
    sdlc_sre_process_engine.ComponentPacket(
      name: "C3I-DeterministicFlightController",
      signature: "fn update(Telemetry) -> FlightState",
      semantic_domain: "Closed aerospace manifold state",
      oracle: "Initial Erlang reference engine",
      final_encoding: "Gleam BEAM actor with typed message queue",
      homomorphism_law: "denote(Final) == denote(Oracle)",
      generator: "Seeded telemetry generator with boundary perturbation",
      mutants: [
        "Invert pitch-rate sensor sign",
        "Drop heartbeat packet at tick 100",
      ],
      judge: "Differential oracle + EUnit law assertions",
      governor: "Fail-closed safety interlock & Prajna circuit breaker",
      documentation: "docs/design/20260906-1330-uos-256-agent-ecology-specification.md",
      durable_evidence: "SQLite verification tracking ledger row",
    )

  sdlc_sre_process_engine.validate_component_packet(valid_packet)
  |> should.equal(True)

  // Invalid packet with insufficient mutants (< 2)
  let invalid_packet =
    sdlc_sre_process_engine.ComponentPacket(..valid_packet, mutants: [
      "Single mutant",
    ])
  sdlc_sre_process_engine.validate_component_packet(invalid_packet)
  |> should.equal(False)
}

pub fn fractal_layer_ladder_and_planes_test() {
  sdlc_sre_process_engine.fractal_layer_ladder_ordinal(
    sdlc_sre_process_engine.L0Boundary,
  )
  |> should.equal(0)
  sdlc_sre_process_engine.fractal_layer_ladder_ordinal(
    sdlc_sre_process_engine.L10Governance,
  )
  |> should.equal(10)

  sdlc_sre_process_engine.fractal_layer_ladder_to_string(
    sdlc_sre_process_engine.L5Representation,
  )
  |> should.equal("L5_Representation")

  sdlc_sre_process_engine.orthogonal_plane_to_string(
    sdlc_sre_process_engine.OrchestrationPlane,
  )
  |> should.equal("orchestration")

  sdlc_sre_process_engine.verification_stratum_to_string(
    sdlc_sre_process_engine.StratumAAlgebraicCore,
  )
  |> string.contains("Algebraic Core")
  |> should.equal(True)
}

pub fn fcopsr_production_readiness_test() {
  let all_green =
    sdlc_sre_process_engine.FcopsrStatus(
      functional_parity: True,
      capability_completeness: True,
      operational_honesty: True,
      performance: True,
      scalability: True,
      realtime_behavior: True,
    )
  sdlc_sre_process_engine.evaluate_fcopsr_readiness(all_green)
  |> should.equal(True)

  // One failing axis fails the whole conjunction
  let degraded =
    sdlc_sre_process_engine.FcopsrStatus(..all_green, performance: False)
  sdlc_sre_process_engine.evaluate_fcopsr_readiness(degraded)
  |> should.equal(False)
}

pub fn capability_poset_state_test() {
  sdlc_sre_process_engine.is_at_least_capability(
    sdlc_sre_process_engine.PosetEq,
    sdlc_sre_process_engine.PosetEquiv,
  )
  |> should.equal(True)

  sdlc_sre_process_engine.is_at_least_capability(
    sdlc_sre_process_engine.PosetUntested,
    sdlc_sre_process_engine.PosetEquiv,
  )
  |> should.equal(False)
}

pub fn forecast_honesty_evaluation_test() {
  let green_forecast =
    sdlc_sre_process_engine.ForecastHonestyReport(
      confidence: sdlc_sre_process_engine.ConfidenceMeasured,
      cost_sum: 1250,
      is_available: True,
    )
  sdlc_sre_process_engine.evaluate_forecast_honesty(green_forecast)
  |> should.equal(True)

  // Unavailable_observed remains non-green
  let unavailable_report =
    sdlc_sre_process_engine.ForecastHonestyReport(
      ..green_forecast,
      is_available: False,
    )
  sdlc_sre_process_engine.evaluate_forecast_honesty(unavailable_report)
  |> should.equal(False)

  // Unknown confidence remains non-green
  let unknown_report =
    sdlc_sre_process_engine.ForecastHonestyReport(
      ..green_forecast,
      confidence: sdlc_sre_process_engine.ConfidenceUnknown,
    )
  sdlc_sre_process_engine.evaluate_forecast_honesty(unknown_report)
  |> should.equal(False)
}

pub fn agent_topology_and_oodavr_test() {
  sdlc_sre_process_engine.agent_topology_role_to_string(
    sdlc_sre_process_engine.L0ProgrammeIntegration,
  )
  |> should.equal("L0_Programme_Integration")

  sdlc_sre_process_engine.agent_topology_role_to_string(
    sdlc_sre_process_engine.L3IndependentVerifier,
  )
  |> should.equal("L3_Independent_Verifier")

  sdlc_sre_process_engine.oodavr_stage_to_string(
    sdlc_sre_process_engine.OodavrVerify,
  )
  |> should.equal("VERIFY")

  sdlc_sre_process_engine.oodavr_stage_to_string(
    sdlc_sre_process_engine.OodavrRecord,
  )
  |> should.equal("RECORD")
}
