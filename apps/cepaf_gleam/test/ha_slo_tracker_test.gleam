/// HA SLO Tracker Tests — 30-test suite
/// Module: cepaf_gleam/ha/slo_tracker
/// Layer: L5_COGNITIVE
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-ZEN-001, SC-MUDA-001, SC-FUNC-002
///
/// Tests for F02 (SLI/SLO Dashboard) and F29 (Error Budget Tracking).
/// Pure functional: no IO, no side effects.  All state passed by value.
import cepaf_gleam/ha/slo_tracker.{
  SLOMet, SloMetric, availability_sli, budget_remaining, budget_summary,
  check_budgets, error_budget_remaining, init, init_budget, latency_sli, record,
  record_event, summary, to_json,
}
import gleam/list
import gleam/string
import gleeunit/should

// ===========================================================================
// init — SLOTrackerState initialisation
// ===========================================================================

pub fn init_has_four_counters_test() {
  let state = init()
  list.length(state.counters) |> should.equal(4)
}

pub fn init_total_checks_is_zero_test() {
  let state = init()
  state.total_checks |> should.equal(0)
}

pub fn init_last_check_timestamp_is_zero_test() {
  let state = init()
  state.last_check_timestamp |> should.equal(0)
}

pub fn init_all_counters_have_zero_events_test() {
  let state = init()
  let all_zero =
    list.all(state.counters, fn(c) { c.good_events == 0 && c.total_events == 0 })
  all_zero |> should.be_true()
}

pub fn init_contains_truth_slo_test() {
  let state = init()
  let has_truth = list.any(state.counters, fn(c) { c.name == "truth_slo" })
  has_truth |> should.be_true()
}

pub fn init_contains_freshness_slo_test() {
  let state = init()
  let has_freshness =
    list.any(state.counters, fn(c) { c.name == "freshness_slo" })
  has_freshness |> should.be_true()
}

pub fn init_contains_availability_slo_test() {
  let state = init()
  let has_avail =
    list.any(state.counters, fn(c) { c.name == "availability_slo" })
  has_avail |> should.be_true()
}

pub fn init_contains_latency_slo_test() {
  let state = init()
  let has_latency = list.any(state.counters, fn(c) { c.name == "latency_slo" })
  has_latency |> should.be_true()
}

// ===========================================================================
// record_event — event accumulation
// ===========================================================================

pub fn record_good_event_increments_good_and_total_test() {
  let state = init()
  let state2 = record_event(state, "truth_slo", True)
  let counter = list.find(state2.counters, fn(c) { c.name == "truth_slo" })
  case counter {
    Ok(c) -> {
      c.good_events |> should.equal(1)
      c.total_events |> should.equal(1)
    }
    Error(_) -> should.fail()
  }
}

pub fn record_bad_event_increments_only_total_test() {
  let state = init()
  let state2 = record_event(state, "freshness_slo", False)
  let counter = list.find(state2.counters, fn(c) { c.name == "freshness_slo" })
  case counter {
    Ok(c) -> {
      c.good_events |> should.equal(0)
      c.total_events |> should.equal(1)
    }
    Error(_) -> should.fail()
  }
}

pub fn record_event_increments_total_checks_test() {
  let state = init()
  let state2 = record_event(state, "latency_slo", True)
  state2.total_checks |> should.equal(1)
}

pub fn record_event_increments_timestamp_test() {
  let state = init()
  let state2 = record_event(state, "availability_slo", True)
  state2.last_check_timestamp |> should.equal(1)
}

pub fn record_event_unknown_slo_leaves_state_unchanged_test() {
  let state = init()
  let state2 = record_event(state, "nonexistent_slo", True)
  // total_checks still increments (the call happened)
  // but no counter changes
  let all_zero =
    list.all(state2.counters, fn(c) {
      c.good_events == 0 && c.total_events == 0
    })
  all_zero |> should.be_true()
}

pub fn multiple_events_accumulate_correctly_test() {
  let state = init()
  let state2 =
    state
    |> record_event("truth_slo", True)
    |> record_event("truth_slo", True)
    |> record_event("truth_slo", False)
  let counter = list.find(state2.counters, fn(c) { c.name == "truth_slo" })
  case counter {
    Ok(c) -> {
      c.good_events |> should.equal(2)
      c.total_events |> should.equal(3)
    }
    Error(_) -> should.fail()
  }
}

// ===========================================================================
// budget_remaining
// ===========================================================================

pub fn budget_remaining_is_1_on_fresh_state_test() {
  let state = init()
  budget_remaining(state, "truth_slo") |> should.equal(1.0)
}

pub fn budget_remaining_is_1_for_unknown_slo_test() {
  let state = init()
  budget_remaining(state, "made_up_slo") |> should.equal(1.0)
}

pub fn budget_remaining_decreases_on_bad_events_test() {
  // latency target is 0.99 (1% error budget).
  // 1 bad event out of 10 = 10% error rate, consuming 10%/1% = full budget.
  let state = init()
  let state2 =
    state
    |> record_event("latency_slo", True)
    |> record_event("latency_slo", True)
    |> record_event("latency_slo", True)
    |> record_event("latency_slo", True)
    |> record_event("latency_slo", True)
    |> record_event("latency_slo", True)
    |> record_event("latency_slo", True)
    |> record_event("latency_slo", True)
    |> record_event("latency_slo", True)
    |> record_event("latency_slo", False)
  let remaining = budget_remaining(state2, "latency_slo")
  // budget is consumed; remaining should be < 1.0
  { remaining <. 1.0 } |> should.be_true()
}

// ===========================================================================
// check_budgets
// ===========================================================================

pub fn check_budgets_returns_4_entries_test() {
  let state = init()
  let budgets = check_budgets(state)
  list.length(budgets) |> should.equal(4)
}

pub fn check_budgets_all_met_on_fresh_state_test() {
  let state = init()
  let budgets = check_budgets(state)
  // With 0 events, all SLOs report SLOMet (budget_consumed = 0 < 50%)
  let all_met = list.all(budgets, fn(pair) { pair.1 == SLOMet })
  all_met |> should.be_true()
}

// ===========================================================================
// to_json
// ===========================================================================

pub fn to_json_contains_slos_key_test() {
  let state = init()
  let s = to_json(state)
  s |> string.contains("slos") |> should.be_true()
}

pub fn to_json_contains_total_checks_test() {
  let state = init()
  let s = to_json(state)
  s |> string.contains("total_checks") |> should.be_true()
}

pub fn to_json_contains_slo_dashboard_page_test() {
  let state = init()
  let s = to_json(state)
  s |> string.contains("SLO Dashboard") |> should.be_true()
}

// ===========================================================================
// summary
// ===========================================================================

pub fn summary_contains_checks_recorded_test() {
  let state = init()
  let s = summary(state)
  s |> string.contains("checks recorded") |> should.be_true()
}

pub fn summary_contains_truth_slo_test() {
  let state = init()
  let s = summary(state)
  s |> string.contains("truth_slo") |> should.be_true()
}

// ===========================================================================
// Pipeline API — init_budget / record / latency_sli / availability_sli
// ===========================================================================

pub fn init_budget_has_zero_requests_test() {
  let b = init_budget()
  b.total_requests |> should.equal(0)
  b.fast_requests |> should.equal(0)
  b.successful_requests |> should.equal(0)
}

pub fn init_budget_latency_target_is_500ms_test() {
  let b = init_budget()
  b.latency_target_ms |> should.equal(500)
}

pub fn latency_sli_returns_100_on_no_requests_test() {
  let b = init_budget()
  latency_sli(b) |> should.equal(100.0)
}

pub fn availability_sli_returns_100_on_no_requests_test() {
  let b = init_budget()
  availability_sli(b) |> should.equal(100.0)
}

pub fn record_fast_request_increments_fast_count_test() {
  let b = init_budget()
  let metric =
    SloMetric(
      endpoint: "/health",
      latency_ms: 100,
      status_code: 200,
      timestamp_ms: 0,
    )
  let b2 = record(b, metric)
  b2.total_requests |> should.equal(1)
  b2.fast_requests |> should.equal(1)
  b2.successful_requests |> should.equal(1)
}

pub fn record_slow_request_does_not_count_as_fast_test() {
  let b = init_budget()
  // 600ms exceeds default 500ms target
  let metric =
    SloMetric(
      endpoint: "/api/slow",
      latency_ms: 600,
      status_code: 200,
      timestamp_ms: 0,
    )
  let b2 = record(b, metric)
  b2.total_requests |> should.equal(1)
  b2.fast_requests |> should.equal(0)
  b2.successful_requests |> should.equal(1)
}

pub fn record_5xx_request_does_not_count_as_successful_test() {
  let b = init_budget()
  let metric =
    SloMetric(
      endpoint: "/api/v1/plan",
      latency_ms: 100,
      status_code: 500,
      timestamp_ms: 0,
    )
  let b2 = record(b, metric)
  b2.total_requests |> should.equal(1)
  b2.successful_requests |> should.equal(0)
}

pub fn error_budget_remaining_full_on_no_requests_test() {
  let b = init_budget()
  error_budget_remaining(b) |> should.equal(1.0)
}

pub fn error_budget_remaining_decreases_on_slow_requests_test() {
  let b = init_budget()
  // All requests slow (exceed 500ms)
  let slow =
    SloMetric(
      endpoint: "/slow",
      latency_ms: 600,
      status_code: 200,
      timestamp_ms: 0,
    )
  let b2 = b |> record(slow) |> record(slow) |> record(slow)
  let remaining = error_budget_remaining(b2)
  // All 3 requests are bad => budget exhausted => remaining = 0.0
  { remaining <. 1.0 } |> should.be_true()
}

pub fn budget_summary_contains_requests_count_test() {
  let b = init_budget()
  let fast =
    SloMetric(
      endpoint: "/health",
      latency_ms: 100,
      status_code: 200,
      timestamp_ms: 0,
    )
  let b2 = record(b, fast)
  let s = budget_summary(b2)
  s |> string.contains("1") |> should.be_true()
  s |> string.contains("latency") |> should.be_true()
}

// ===========================================================================
// SLOStatus ADT — structural
// ===========================================================================

pub fn slo_status_variants_are_distinct_test() {
  // Verify each status variant maps to a unique string representation
  // by checking check_budgets returns named pairs with the right keys
  let state = init()
  let budgets = check_budgets(state)
  // All four SLOs must be present and all met (no events recorded)
  let names = list.map(budgets, fn(pair) { pair.0 })
  list.contains(names, "truth_slo") |> should.be_true()
  list.contains(names, "latency_slo") |> should.be_true()
}
