//// [C3I-SIL6-MSTS] TEST SUITE
//// <c3i-test>
////   <target>cepaf_gleam/semantics/algebraic_atlas</target>
////   <compliance>SC-INTENT-ATLAS-001, SC-CHECKLIST-001</compliance>
//// </c3i-test>

import cepaf_gleam/semantics/algebraic_atlas as atlas
import gleeunit/should

pub fn chart_indices_roundtrip_test() {
  atlas.chart_to_int(atlas.L0Constitutional) |> should.equal(0)
  atlas.chart_to_int(atlas.L1AtomicKernel) |> should.equal(1)
  atlas.chart_to_int(atlas.L2Homeostasis) |> should.equal(2)
  atlas.chart_to_int(atlas.L3Transactions) |> should.equal(3)
  atlas.chart_to_int(atlas.L4SystemDaemons) |> should.equal(4)
  atlas.chart_to_int(atlas.L5CognitiveOODA) |> should.equal(5)
  atlas.chart_to_int(atlas.L6SwarmMesh) |> should.equal(6)
  atlas.chart_to_int(atlas.L7Federation) |> should.equal(7)
  atlas.chart_to_int(atlas.L8Verification) |> should.equal(8)
  atlas.chart_to_int(atlas.L9Sovereignty) |> should.equal(9)

  atlas.int_to_chart(0) |> should.equal(Ok(atlas.L0Constitutional))
  atlas.int_to_chart(4) |> should.equal(Ok(atlas.L4SystemDaemons))
  atlas.int_to_chart(9) |> should.equal(Ok(atlas.L9Sovereignty))
  atlas.int_to_chart(10) |> should.be_error
}

pub fn transition_morphisms_cocycle_test() {
  let id0 = atlas.identity_morphism(atlas.L0Constitutional)
  id0.source_chart |> should.equal(atlas.L0Constitutional)
  id0.target_chart |> should.equal(atlas.L0Constitutional)
  id0.is_compatible |> should.equal(True)

  let phi_01 =
    atlas.TransitionMorphism(
      source_chart: atlas.L0Constitutional,
      target_chart: atlas.L1AtomicKernel,
      transform_name: "phi_01",
      is_compatible: True,
    )

  let phi_12 =
    atlas.TransitionMorphism(
      source_chart: atlas.L1AtomicKernel,
      target_chart: atlas.L2Homeostasis,
      transform_name: "phi_12",
      is_compatible: True,
    )

  // Compatible composition: phi_01 o phi_12
  let composed_res = atlas.compose_morphisms(phi_01, phi_12)
  composed_res |> should.be_ok
  let assert Ok(composed) = composed_res
  composed.source_chart |> should.equal(atlas.L0Constitutional)
  composed.target_chart |> should.equal(atlas.L2Homeostasis)
  composed.is_compatible |> should.equal(True)

  // Incompatible composition: phi_01 o phi_34
  let phi_34 =
    atlas.TransitionMorphism(
      source_chart: atlas.L3Transactions,
      target_chart: atlas.L4SystemDaemons,
      transform_name: "phi_34",
      is_compatible: True,
    )
  atlas.compose_morphisms(phi_01, phi_34) |> should.be_error
}

fn sample_trace_coords(layer: Int, epoch: Int) -> atlas.TraceCoordinates {
  atlas.TraceCoordinates(
    timestamp_us: 1_788_800_000_000_000,
    layer_id: layer,
    holon_id: "holon-c3i-super-01",
    causal_epoch: epoch,
    shannon_entropy_bits: 2.85,
    lyapunov_energy: 0.012,
    cyclomatic_complexity: 94,
    divergence_ppm: 120,
    itqs_quality: 0.96,
    quarantine_flags: 0,
    worker_hash: "worker-6e132c1c",
    plan_digest: "plan-intent-atlas-c221",
    parent_digest: "digest-c220-43c88218",
  )
}

pub fn denotational_intent_success_valuation_test() {
  let initial_state =
    atlas.ChartState(
      chart: atlas.L0Constitutional,
      coordinates: sample_trace_coords(0, 100),
      payload_json: "{\"status\":\"nominal\"}",
      constitutional_health: 1.0,
    )

  let intent =
    atlas.DeclarativeIntent(
      intent_id: "intent-migrate-to-l1",
      proposer_holon: "holon-c3i-super-01",
      source_chart: atlas.L0Constitutional,
      target_chart: atlas.L1AtomicKernel,
      action: "kernel-arena-provision",
      required_preconditions: ["pre_arena_quiesced"],
      guaranteed_postconditions: ["post_arena_ready"],
      preserves_constitutional_invariants: True,
    )

  let outcome = atlas.evaluate_denotational_intent(intent, initial_state)
  case outcome {
    atlas.DenotationalSuccess(final_state, receipt) -> {
      final_state.chart |> should.equal(atlas.L1AtomicKernel)
      final_state.coordinates.layer_id |> should.equal(1)
      final_state.coordinates.causal_epoch |> should.equal(101)
      final_state.constitutional_health |> should.equal(1.0)
      should.be_true(receipt != "")
    }
    atlas.DenotationalVetoed(_, reason) -> {
      panic as { "Expected DenotationalSuccess but received Veto: " <> reason }
    }
  }
}

pub fn denotational_intent_veto_cases_test() {
  let healthy_state =
    atlas.ChartState(
      chart: atlas.L0Constitutional,
      coordinates: sample_trace_coords(0, 100),
      payload_json: "{}",
      constitutional_health: 1.0,
    )

  // 1. Source chart mismatch
  let mismatch_intent =
    atlas.DeclarativeIntent(
      intent_id: "intent-mismatch",
      proposer_holon: "holon-bad",
      source_chart: atlas.L3Transactions,
      target_chart: atlas.L4SystemDaemons,
      action: "mutate",
      required_preconditions: [],
      guaranteed_postconditions: [],
      preserves_constitutional_invariants: True,
    )
  case atlas.evaluate_denotational_intent(mismatch_intent, healthy_state) {
    atlas.DenotationalVetoed("intent-mismatch", _) -> should.be_true(True)
    _ -> panic as "Expected veto on source chart mismatch"
  }

  // 2. Constitutional Invariant Breach
  let breach_intent =
    atlas.DeclarativeIntent(
      intent_id: "intent-breach",
      proposer_holon: "holon-bad",
      source_chart: atlas.L0Constitutional,
      target_chart: atlas.L1AtomicKernel,
      action: "wipe-storage",
      required_preconditions: [],
      guaranteed_postconditions: [],
      preserves_constitutional_invariants: False,
    )
  case atlas.evaluate_denotational_intent(breach_intent, healthy_state) {
    atlas.DenotationalVetoed("intent-breach", _) -> should.be_true(True)
    _ -> panic as "Expected veto on invariant breach"
  }

  // 3. Degraded System Health
  let degraded_state =
    atlas.ChartState(
      chart: atlas.L0Constitutional,
      coordinates: sample_trace_coords(0, 100),
      payload_json: "{}",
      constitutional_health: 0.72,
    )
  let valid_intent =
    atlas.DeclarativeIntent(
      intent_id: "intent-valid",
      proposer_holon: "holon-ok",
      source_chart: atlas.L0Constitutional,
      target_chart: atlas.L1AtomicKernel,
      action: "probe",
      required_preconditions: [],
      guaranteed_postconditions: [],
      preserves_constitutional_invariants: True,
    )
  case atlas.evaluate_denotational_intent(valid_intent, degraded_state) {
    atlas.DenotationalVetoed("intent-valid", _) -> should.be_true(True)
    _ -> panic as "Expected veto on degraded health"
  }
}

pub fn sheaf_gluing_test() {
  let sections = [
    #(atlas.L0Constitutional, "shared-state-alpha"),
    #(atlas.L1AtomicKernel, "shared-state-alpha"),
    #(atlas.L2Homeostasis, "shared-state-beta"),
  ]

  let valid_overlaps = [
    #(atlas.L0Constitutional, atlas.L1AtomicKernel, "shared-state-alpha"),
  ]
  atlas.verify_sheaf_gluing(sections, valid_overlaps) |> should.be_ok

  let invalid_overlaps = [
    #(atlas.L1AtomicKernel, atlas.L2Homeostasis, "shared-state-alpha"),
  ]
  atlas.verify_sheaf_gluing(sections, invalid_overlaps) |> should.be_error
}
