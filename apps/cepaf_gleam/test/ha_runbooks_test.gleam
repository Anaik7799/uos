/// HA Runbook Library tests — F03 Automated Runbook Library
/// SC-HA-001, SC-SIL4-001, SC-FUNC-003
/// Layer: L4_SYSTEM
import cepaf_gleam/ha/runbooks.{
  CircuitBreakerOpen, ErrorBudgetExhausted, HealthCheckFailed,
  InvariantViolation, ManualTrigger, StalenessDetected,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// C1: catalog size and basic structure
// ---------------------------------------------------------------------------

pub fn runbook_count_is_ten_test() {
  runbooks.runbook_count() |> should.equal(10)
}

pub fn all_runbooks_returns_ten_items_test() {
  list.length(runbooks.all_runbooks()) |> should.equal(10)
}

pub fn all_ids_are_unique_test() {
  let ids = list.map(runbooks.all_runbooks(), fn(rb) { rb.id })
  let unique = list.unique(ids)
  list.length(unique) |> should.equal(list.length(ids))
}

pub fn all_runbooks_have_steps_test() {
  runbooks.all_runbooks()
  |> list.all(fn(rb) { rb.steps != [] })
  |> should.be_true()
}

pub fn all_step_orders_start_at_one_test() {
  let first_orders =
    runbooks.all_runbooks()
    |> list.flat_map(fn(rb) { rb.steps })
    |> list.filter(fn(s) { s.order == 1 })
  // every runbook must have an order=1 step
  list.length(first_orders) |> should.equal(10)
}

// ---------------------------------------------------------------------------
// C2: trigger-to-runbook lookup
// ---------------------------------------------------------------------------

pub fn runbook_for_health_check_failed_nif_test() {
  let result = runbooks.runbook_for_trigger(HealthCheckFailed("c3i_nif"))
  result |> should.be_ok()
  let assert Ok(rb) = result
  rb.id |> should.equal("RB-001")
}

pub fn runbook_for_manual_trigger_test() {
  let result = runbooks.runbook_for_trigger(ManualTrigger)
  result |> should.be_ok()
  let assert Ok(rb) = result
  rb.id |> should.equal("RB-010")
}

pub fn runbook_for_invariant_violation_test() {
  let result = runbooks.runbook_for_trigger(InvariantViolation("I-01"))
  result |> should.be_ok()
}

pub fn runbook_for_staleness_detected_test() {
  let result = runbooks.runbook_for_trigger(StalenessDetected(60))
  result |> should.be_ok()
  let assert Ok(rb) = result
  rb.id |> should.equal("RB-009")
}

pub fn runbook_for_circuit_breaker_open_test() {
  let result =
    runbooks.runbook_for_trigger(CircuitBreakerOpen("inference_tier_1"))
  result |> should.be_ok()
  let assert Ok(rb) = result
  rb.id |> should.equal("RB-005")
}

pub fn runbook_for_error_budget_exhausted_test() {
  let result = runbooks.runbook_for_trigger(ErrorBudgetExhausted("truth_slo"))
  result |> should.be_ok()
  let assert Ok(rb) = result
  rb.id |> should.equal("RB-006")
}

pub fn runbook_for_unknown_component_returns_error_test() {
  let result = runbooks.runbook_for_trigger(HealthCheckFailed("does_not_exist"))
  result |> should.be_error()
}

// ---------------------------------------------------------------------------
// C3: severity and layer classification
// ---------------------------------------------------------------------------

pub fn rb001_is_p0_test() {
  let assert Ok(rb) = runbooks.runbook_for_trigger(HealthCheckFailed("c3i_nif"))
  rb.severity |> should.equal("P0")
}

pub fn rb010_is_p0_l0_test() {
  let assert Ok(rb) = runbooks.runbook_for_trigger(ManualTrigger)
  rb.severity |> should.equal("P0")
  rb.layer |> should.equal("L0_CONSTITUTIONAL")
}

pub fn rb009_is_p2_test() {
  let assert Ok(rb) = runbooks.runbook_for_trigger(StalenessDetected(60))
  rb.severity |> should.equal("P2")
}

pub fn all_layers_are_valid_fractal_layers_test() {
  let valid = [
    "L0_CONSTITUTIONAL",
    "L1_ATOMIC_DEBUG",
    "L2_COMPONENT",
    "L3_TRANSACTION",
    "L4_SYSTEM",
    "L5_COGNITIVE",
    "L6_ECOSYSTEM",
    "L7_FEDERATION",
  ]
  runbooks.all_runbooks()
  |> list.all(fn(rb) { list.contains(valid, rb.layer) })
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// C4: duration estimates are positive
// ---------------------------------------------------------------------------

pub fn all_estimated_durations_positive_test() {
  runbooks.all_runbooks()
  |> list.all(fn(rb) { rb.estimated_duration_ms > 0 })
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// C5: JSON serialisation
// ---------------------------------------------------------------------------

pub fn to_json_contains_count_test() {
  let json_str = runbooks.to_json(runbooks.all_runbooks())
  string.contains(json_str, "\"count\"") |> should.be_true()
}

pub fn to_json_contains_runbooks_array_test() {
  let json_str = runbooks.to_json(runbooks.all_runbooks())
  string.contains(json_str, "\"runbooks\"") |> should.be_true()
}

pub fn to_json_contains_rb001_id_test() {
  let json_str = runbooks.to_json(runbooks.all_runbooks())
  string.contains(json_str, "RB-001") |> should.be_true()
}

pub fn to_json_empty_list_test() {
  let json_str = runbooks.to_json([])
  string.contains(json_str, "\"count\":0") |> should.be_true()
}
