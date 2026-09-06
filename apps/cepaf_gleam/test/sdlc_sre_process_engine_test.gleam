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
  tiers |> should.equal([TierOperation, TierTask, TierSlice, TierEpoch, TierPin])

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
