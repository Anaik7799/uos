// ==============================================================================
// [UOS-BIONIC-TEST] Hermes-Bionic Bridge & 17-Aspect Systemic Integration Tests
// ==============================================================================

import cepaf_gleam/harness/hermes_bionic_bridge.{
  BionicMultiInstance, BionicSingleInstance, DiscoveryOnlyEvidence,
  EvidenceRejected, HsmArmed, InteractiveCli, ParityReceipt, PortIn,
  all_17_aspect_bionic_bindings, all_18_l1_feature_families,
  canonical_l2_capabilities_sample, create_default_lx_control_plane,
  create_fpp_telemetry_component, evaluate_evidence_boundary,
  hermes_bionic_actor_catalog, is_control_plane_safe,
  verify_hermes_bionic_integration,
}
import gleam/list
import gleeunit/should

pub fn all_18_l1_feature_families_test() {
  let families = all_18_l1_feature_families()
  list.length(families) |> should.equal(18)

  let assert Ok(first) = list.first(families)
  first.id |> should.equal("interactive_cli")
  first.family |> should.equal(InteractiveCli)
  first.durable_tasks_count |> should.equal(5)

  // Verify all entries have non-empty source domains
  let all_valid =
    list.all(families, fn(rec) {
      list.length(rec.source_domains) > 0 && rec.durable_tasks_count > 0
    })
  all_valid |> should.be_true()
}

pub fn canonical_l2_capabilities_test() {
  let caps = canonical_l2_capabilities_sample()
  let len = list.length(caps)
  let ok_len = len >= 10
  ok_len |> should.be_true()

  let assert Ok(first) = list.first(caps)
  first.id |> should.equal("repl_session")
  first.family_id |> should.equal("interactive_cli")
  first.status_policy |> should.equal("FailClosed")

  let all_have_anchors =
    list.all(caps, fn(c) {
      list.length(c.source_anchors) > 0 && list.length(c.doc_anchors) > 0
    })
  all_have_anchors |> should.be_true()
}

pub fn evidence_boundary_evaluation_test() {
  // Discovery only: missing runtime observation
  let v1 =
    evaluate_evidence_boundary(
      True,
      False,
      False,
      "sha256-abc",
      "sha256-abc",
    )
  case v1 {
    DiscoveryOnlyEvidence(_) -> True
    _ -> False
  }
  |> should.be_true()

  // Discovery only: missing formal specification (Two-Key rule)
  let v2 =
    evaluate_evidence_boundary(
      True,
      True,
      False,
      "sha256-abc",
      "sha256-abc",
    )
  case v2 {
    DiscoveryOnlyEvidence(_) -> True
    _ -> False
  }
  |> should.be_true()

  // Full Parity Receipt: fresh observation + formal spec + matching digest
  let v3 =
    evaluate_evidence_boundary(
      True,
      True,
      True,
      "sha256-verified-digest",
      "sha256-verified-digest",
    )
  case v3 {
    ParityReceipt(cand, ref, matched) -> {
      cand |> should.equal("sha256-verified-digest")
      ref |> should.equal("sha256-verified-digest")
      matched |> should.be_true()
      True
    }
    _ -> False
  }
  |> should.be_true()

  // Divergent candidate digest rejected fail-closed
  let v4 =
    evaluate_evidence_boundary(
      True,
      True,
      True,
      "sha256-cand-diverged",
      "sha256-ref-authoritative",
    )
  case v4 {
    EvidenceRejected(_) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn lx_control_plane_safety_test() {
  let cp = create_default_lx_control_plane()
  is_control_plane_safe(cp) |> should.be_true()

  // Token budget exceeded
  let bad_tokens_budget =
    hermes_bionic_bridge.TurnBudget(
      allocated_tokens: 1000,
      consumed_tokens: 2000,
      max_tool_invocations: 10,
      used_tool_invocations: 1,
      wall_clock_timeout_ms: 5000,
    )
  let cp_bad_tokens =
    hermes_bionic_bridge.LxControlPlane(
      status: cp.status,
      budget: bad_tokens_budget,
      snapshot: cp.snapshot,
    )
  is_control_plane_safe(cp_bad_tokens) |> should.be_false()

  // Positive Lyapunov exponent (exponential divergence / chaos)
  let bad_lyapunov_snapshot =
    hermes_bionic_bridge.OrientationSnapshot(
      turn_id: "turn-drift",
      phase: "Orient",
      active_hypotheses: ["H-Divergence"],
      entropy_bits: 4.5,
      lyapunov_exponent: 0.85,
    )
  let cp_chaotic =
    hermes_bionic_bridge.LxControlPlane(
      status: cp.status,
      budget: cp.budget,
      snapshot: bad_lyapunov_snapshot,
    )
  is_control_plane_safe(cp_chaotic) |> should.be_false()
}

pub fn fpp_elements_test() {
  let comp = create_fpp_telemetry_component()
  comp.name |> should.equal("C3iTelemetryBroadcaster")
  comp.current_state |> should.equal(HsmArmed)
  list.length(comp.ports) |> should.equal(3)

  let assert Ok(p0) = list.first(comp.ports)
  p0.name |> should.equal("cmdIn")
  p0.direction |> should.equal(PortIn)
}

pub fn all_17_aspect_bindings_test() {
  let bindings = all_17_aspect_bionic_bindings()
  list.length(bindings) |> should.equal(17)

  let all_active = list.all(bindings, fn(b) { b.status == "Active" })
  all_active |> should.be_true()
}

pub fn bionic_actor_catalog_test() {
  let actors = hermes_bionic_actor_catalog()
  let len = list.length(actors)
  let ok_len = len >= 10
  ok_len |> should.be_true()

  // Single instance actors
  let single_instance =
    list.filter(actors, fn(a) { a.mode == BionicSingleInstance })
  let single_len = list.length(single_instance)
  let ok_single = single_len >= 5
  ok_single |> should.be_true()

  // Multi instance actors
  let multi_instance =
    list.filter(actors, fn(a) { a.mode == BionicMultiInstance })
  let multi_len = list.length(multi_instance)
  let ok_multi = multi_len >= 4
  ok_multi |> should.be_true()
}

pub fn full_system_verification_predicate_test() {
  verify_hermes_bionic_integration() |> should.be_true()
}
