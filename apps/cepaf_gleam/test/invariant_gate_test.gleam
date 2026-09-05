//// =============================================================================
//// [C3I-SIL6-MSTS] INVARIANT GATE TESTS — Satya Plan Sprint 3
//// =============================================================================
////
//// स्वधर्मे निधनं श्रेयः — Better to fail truthfully than succeed with lies.
////
//// Tests for the pre-render invariant gate (ha/invariant_gate.gleam).
////
//// Coverage:
////   Section 1 — valid state passes all invariants (guard returns normal render)
////   Section 2 — I-01: container_count < healthy_count
////   Section 3 — I-02: negative healthy_count
////   Section 4 — I-03: negative container_count
////   Section 5 — I-04: quorum_healthy=true with zero containers
////   Section 6 — guard_render dispatches correctly
////   Section 7 — multiple simultaneous violations
////   Section 8 — violation record field accessors
////
//// STAMP: SC-SATYA-001, SC-TRUTH-001, SC-SIL4-001, SC-GLM-UI-001

import cepaf_gleam/ha/invariant_gate.{
  InvariantViolation, check_state_invariants, guard_render,
}
import cepaf_gleam/ui/state.{
  type SharedMeshState, CockpitDark, OodaObserve, SharedMeshState, ThreatNominal,
  default_state,
}
import gleam/list
import gleam/string
import gleeunit/should
import lustre/element

// ---------------------------------------------------------------------------
// Helper — build a state with custom field overrides from default_state
// ---------------------------------------------------------------------------

fn state_with(
  container_count cc: Int,
  healthy_count hc: Int,
  quorum_healthy qh: Bool,
) -> SharedMeshState {
  SharedMeshState(
    container_count: cc,
    healthy_count: hc,
    threat_level: ThreatNominal,
    ooda_phase: OodaObserve,
    dark_cockpit_mode: CockpitDark,
    zenoh_connected: True,
    quorum_healthy: qh,
    last_updated_ms: 0,
  )
}

// =============================================================================
// Section 1 — Valid state produces zero violations
// =============================================================================

pub fn valid_default_state_no_violations_test() {
  let violations = check_state_invariants(default_state())
  violations |> should.equal([])
}

pub fn valid_all_healthy_no_violations_test() {
  let st =
    state_with(container_count: 16, healthy_count: 16, quorum_healthy: True)
  check_state_invariants(st) |> should.equal([])
}

pub fn valid_partial_healthy_no_violations_test() {
  // 10 of 16 healthy — I-01 passes (16 >= 10), counts >= 0
  let st =
    state_with(container_count: 16, healthy_count: 10, quorum_healthy: False)
  check_state_invariants(st) |> should.equal([])
}

pub fn valid_zero_containers_zero_healthy_no_violations_test() {
  // 0/0 with quorum_healthy=false — no invariant applies
  let st =
    state_with(container_count: 0, healthy_count: 0, quorum_healthy: False)
  check_state_invariants(st) |> should.equal([])
}

pub fn valid_single_container_healthy_test() {
  let st =
    state_with(container_count: 1, healthy_count: 1, quorum_healthy: True)
  check_state_invariants(st) |> should.equal([])
}

// =============================================================================
// Section 2 — I-01: container_count < healthy_count
// =============================================================================

pub fn i01_violation_detected_test() {
  // 5 healthy but only 3 containers — physically impossible
  let st =
    state_with(container_count: 3, healthy_count: 5, quorum_healthy: False)
  let violations = check_state_invariants(st)
  { violations != [] } |> should.be_true()
}

pub fn i01_violation_has_correct_id_test() {
  let st =
    state_with(container_count: 3, healthy_count: 5, quorum_healthy: False)
  let violations = check_state_invariants(st)
  let ids = list.map(violations, fn(v) { v.id })
  list.contains(ids, "I-01") |> should.be_true()
}

pub fn i01_violation_actual_contains_counts_test() {
  let st =
    state_with(container_count: 3, healthy_count: 5, quorum_healthy: False)
  let violations = check_state_invariants(st)
  let i01 = list.find(violations, fn(v) { v.id == "I-01" })
  case i01 {
    Ok(v) -> {
      string.contains(v.actual, "3") |> should.be_true()
      string.contains(v.actual, "5") |> should.be_true()
    }
    Error(_) -> should.fail()
  }
}

pub fn i01_boundary_equal_counts_passes_test() {
  // Exactly equal — I-01 should pass (>= is inclusive)
  let st =
    state_with(container_count: 8, healthy_count: 8, quorum_healthy: True)
  let violations = check_state_invariants(st)
  let ids = list.map(violations, fn(v) { v.id })
  list.contains(ids, "I-01") |> should.be_false()
}

// =============================================================================
// Section 3 — I-02: negative healthy_count
// =============================================================================

pub fn i02_violation_negative_healthy_count_test() {
  let st =
    state_with(container_count: 5, healthy_count: -1, quorum_healthy: False)
  let violations = check_state_invariants(st)
  let ids = list.map(violations, fn(v) { v.id })
  list.contains(ids, "I-02") |> should.be_true()
}

pub fn i02_violation_description_correct_test() {
  let st =
    state_with(container_count: 5, healthy_count: -3, quorum_healthy: False)
  let violations = check_state_invariants(st)
  let i02 = list.find(violations, fn(v) { v.id == "I-02" })
  case i02 {
    Ok(v) -> string.contains(v.description, "non-negative") |> should.be_true()
    Error(_) -> should.fail()
  }
}

pub fn i02_zero_healthy_count_passes_test() {
  // Zero is non-negative — should pass I-02
  let st =
    state_with(container_count: 5, healthy_count: 0, quorum_healthy: False)
  let violations = check_state_invariants(st)
  let ids = list.map(violations, fn(v) { v.id })
  list.contains(ids, "I-02") |> should.be_false()
}

// =============================================================================
// Section 4 — I-03: negative container_count
// =============================================================================

pub fn i03_violation_negative_container_count_test() {
  let st =
    state_with(container_count: -1, healthy_count: 0, quorum_healthy: False)
  let violations = check_state_invariants(st)
  let ids = list.map(violations, fn(v) { v.id })
  list.contains(ids, "I-03") |> should.be_true()
}

pub fn i03_zero_container_count_passes_test() {
  // Zero is non-negative — should pass I-03
  let st =
    state_with(container_count: 0, healthy_count: 0, quorum_healthy: False)
  let violations = check_state_invariants(st)
  let ids = list.map(violations, fn(v) { v.id })
  list.contains(ids, "I-03") |> should.be_false()
}

// =============================================================================
// Section 5 — I-04: quorum_healthy=true with zero containers
// =============================================================================

pub fn i04_violation_quorum_true_zero_containers_test() {
  // quorum_healthy=true, healthy_count=0, container_count=0 → I-04 fires
  let st =
    state_with(container_count: 0, healthy_count: 0, quorum_healthy: True)
  let violations = check_state_invariants(st)
  let ids = list.map(violations, fn(v) { v.id })
  list.contains(ids, "I-04") |> should.be_true()
}

pub fn i04_no_violation_when_quorum_false_test() {
  // I-04 precondition requires quorum_healthy=true — not triggered when false
  let st =
    state_with(container_count: 0, healthy_count: 0, quorum_healthy: False)
  let violations = check_state_invariants(st)
  let ids = list.map(violations, fn(v) { v.id })
  list.contains(ids, "I-04") |> should.be_false()
}

pub fn i04_no_violation_when_not_all_healthy_test() {
  // Precondition: quorum AND healthy==container — partial health means not triggered
  let st =
    state_with(container_count: 10, healthy_count: 8, quorum_healthy: True)
  let violations = check_state_invariants(st)
  let ids = list.map(violations, fn(v) { v.id })
  list.contains(ids, "I-04") |> should.be_false()
}

// =============================================================================
// Section 6 — guard_render dispatches correctly
// =============================================================================

/// A dummy render function — returns a sentinel element
fn sentinel_element(_state: SharedMeshState) -> element.Element(Nil) {
  element.text("RENDERED_OK")
}

pub fn guard_render_valid_state_calls_render_fn_test() {
  let result = guard_render(default_state(), "test-page", sentinel_element)
  // The returned element should be the sentinel, not the fallback
  // We verify by checking the element produces "RENDERED_OK" text indirectly
  // through gleeunit — inspect the string representation
  let rendered = element.to_string(result)
  string.contains(rendered, "RENDERED_OK") |> should.be_true()
}

pub fn guard_render_invalid_state_returns_fallback_test() {
  // I-01 violation: 3 containers but 5 healthy
  let broken =
    state_with(container_count: 3, healthy_count: 5, quorum_healthy: False)
  let result = guard_render(broken, "cockpit", sentinel_element)
  let rendered = element.to_string(result)
  // Fallback contains violation class — NOT the sentinel
  string.contains(rendered, "RENDERED_OK") |> should.be_false()
  string.contains(rendered, "invariant-violation-page") |> should.be_true()
}

pub fn guard_render_fallback_contains_page_name_test() {
  let broken =
    state_with(container_count: 3, healthy_count: 5, quorum_healthy: False)
  let result = guard_render(broken, "dashboard-page", sentinel_element)
  let rendered = element.to_string(result)
  string.contains(rendered, "dashboard-page") |> should.be_true()
}

pub fn guard_render_fallback_contains_violation_id_test() {
  let broken =
    state_with(container_count: 3, healthy_count: 5, quorum_healthy: False)
  let result = guard_render(broken, "immune", sentinel_element)
  let rendered = element.to_string(result)
  string.contains(rendered, "I-01") |> should.be_true()
}

// =============================================================================
// Section 7 — Multiple simultaneous violations
// =============================================================================

pub fn multiple_violations_all_detected_test() {
  // I-02 (negative healthy) + I-03 (negative container) fire together
  let st =
    state_with(container_count: -2, healthy_count: -1, quorum_healthy: False)
  let violations = check_state_invariants(st)
  let ids = list.map(violations, fn(v) { v.id })
  list.contains(ids, "I-02") |> should.be_true()
  list.contains(ids, "I-03") |> should.be_true()
}

pub fn multiple_violations_count_correct_test() {
  // I-01 + I-02 + I-03: container=-2 healthy=-1 means all three geometric checks fail
  let st =
    state_with(container_count: -2, healthy_count: -1, quorum_healthy: False)
  let violations = check_state_invariants(st)
  // I-02 (-1 healthy), I-03 (-2 containers) — both fire
  // I-01: -2 >= -1 is False → also fires
  let count = list.length(violations)
  { count > 1 } |> should.be_true()
}

// =============================================================================
// Section 8 — InvariantViolation record fields
// =============================================================================

pub fn violation_record_id_accessible_test() {
  let v =
    InvariantViolation(
      id: "I-01",
      description: "test",
      expected: "exp",
      actual: "act",
    )
  v.id |> should.equal("I-01")
}

pub fn violation_record_description_accessible_test() {
  let v =
    InvariantViolation(
      id: "I-02",
      description: "healthy_count must be non-negative",
      expected: "healthy_count >= 0",
      actual: "healthy_count=-5",
    )
  v.description |> should.equal("healthy_count must be non-negative")
}

pub fn violation_record_expected_accessible_test() {
  let v =
    InvariantViolation(
      id: "I-03",
      description: "test",
      expected: "container_count >= 0",
      actual: "container_count=-99",
    )
  v.expected |> should.equal("container_count >= 0")
}

pub fn violation_record_actual_accessible_test() {
  let v =
    InvariantViolation(
      id: "I-04",
      description: "test",
      expected: "container_count > 0",
      actual: "container_count=0 with quorum_healthy=true",
    )
  string.contains(v.actual, "quorum_healthy") |> should.be_true()
}
