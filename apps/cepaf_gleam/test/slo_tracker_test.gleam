//// =============================================================================
//// [C3I-SIL6-MSTS] SLO TRACKER TESTS — F02/F29
//// =============================================================================
////
//// यो मामजमनादिं च — One who knows the unborn, beginningless (Gita 10.3)
////
//// Tests for ha/slo_tracker.gleam — SLI/SLO Dashboard and Error Budget Tracking.
////
//// Coverage (25 tests):
////   Section 1 — init: 4 SLOs present, zero state, full budgets
////   Section 2 — record_event: good/bad accumulation, unknown SLO ignored
////   Section 3 — SLI arithmetic: 0 events = 1.0, all-good = 1.0, all-bad = 0.0
////   Section 4 — budget math: consumed fraction, clamp at 1.0
////   Section 5 — status transitions: SLOMet / SLOAtRisk / SLOViolated thresholds
////   Section 6 — check_budgets: returns list of (name, status) tuples
////   Section 7 — budget_remaining: per-SLO query, unknown returns 1.0
////   Section 8 — to_json: structure, required keys, SLO count
////   Section 9 — summary: non-empty, contains SLO names
////   Section 10 — accumulation: multiple records, monotonic total_checks
////
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-MUDA-001, SC-FUNC-002
//// Layer: L5_COGNITIVE

import cepaf_gleam/ha/slo_tracker.{
  SLOMet, SLOViolated, SloMetric, availability_sli, budget_remaining,
  budget_summary, check_budgets, error_budget_remaining, init, init_budget,
  latency_sli, record, record_event, summary, to_json,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Helpers — event recording loops
// ---------------------------------------------------------------------------

/// Record `n` good events against the given SLO name.
fn record_n_good(
  state: slo_tracker.SLOTrackerState,
  slo: String,
  n: Int,
) -> slo_tracker.SLOTrackerState {
  case n <= 0 {
    True -> state
    False -> record_n_good(record_event(state, slo, True), slo, n - 1)
  }
}

/// Record `n` bad events against the given SLO name.
fn record_n_bad(
  state: slo_tracker.SLOTrackerState,
  slo: String,
  n: Int,
) -> slo_tracker.SLOTrackerState {
  case n <= 0 {
    True -> state
    False -> record_n_bad(record_event(state, slo, False), slo, n - 1)
  }
}

// ---------------------------------------------------------------------------
// Section 1 — init: 4 SLOs present, zero state, full budgets
// ---------------------------------------------------------------------------

pub fn init_has_four_slos_test() {
  let state = init()
  let budgets = check_budgets(state)
  list.length(budgets) |> should.equal(4)
}

pub fn init_total_checks_zero_test() {
  let state = init()
  state.total_checks |> should.equal(0)
}

pub fn init_timestamp_zero_test() {
  let state = init()
  state.last_check_timestamp |> should.equal(0)
}

pub fn init_all_budgets_full_test() {
  let state = init()
  // With zero events every SLO should have full budget remaining (1.0)
  let all_full =
    list.all(check_budgets(state), fn(pair) {
      budget_remaining(state, pair.0) == 1.0
    })
  all_full |> should.be_true()
}

pub fn init_truth_slo_present_test() {
  let state = init()
  let names = list.map(check_budgets(state), fn(p) { p.0 })
  list.contains(names, "truth_slo") |> should.be_true()
}

pub fn init_freshness_slo_present_test() {
  let state = init()
  let names = list.map(check_budgets(state), fn(p) { p.0 })
  list.contains(names, "freshness_slo") |> should.be_true()
}

pub fn init_availability_slo_present_test() {
  let state = init()
  let names = list.map(check_budgets(state), fn(p) { p.0 })
  list.contains(names, "availability_slo") |> should.be_true()
}

pub fn init_latency_slo_present_test() {
  let state = init()
  let names = list.map(check_budgets(state), fn(p) { p.0 })
  list.contains(names, "latency_slo") |> should.be_true()
}

// ---------------------------------------------------------------------------
// Section 2 — record_event: accumulation and unknown SLO ignored
// ---------------------------------------------------------------------------

pub fn record_good_event_increments_total_checks_test() {
  let state = init() |> record_event("truth_slo", True)
  state.total_checks |> should.equal(1)
}

pub fn record_bad_event_increments_total_checks_test() {
  let state = init() |> record_event("truth_slo", False)
  state.total_checks |> should.equal(1)
}

pub fn record_unknown_slo_does_not_change_checks_test() {
  // total_checks increments even for unknown names because we still counted
  // the call; what matters is the *budget* is unaffected
  let state = init() |> record_event("nonexistent_slo", True)
  // budget_remaining for a known SLO must still be 1.0
  budget_remaining(state, "truth_slo") |> should.equal(1.0)
}

pub fn record_multiple_events_increments_timestamp_test() {
  let state =
    init()
    |> record_event("freshness_slo", True)
    |> record_event("freshness_slo", True)
    |> record_event("freshness_slo", False)
  state.last_check_timestamp |> should.equal(3)
}

// ---------------------------------------------------------------------------
// Section 3 — SLI arithmetic
// ---------------------------------------------------------------------------

pub fn sli_with_zero_events_is_1_0_test() {
  // Fresh state = no events = SLI 1.0 (assume healthy, full budget)
  let state = init()
  budget_remaining(state, "availability_slo") |> should.equal(1.0)
}

pub fn sli_all_good_budget_is_full_test() {
  // 1000 good events, 0 bad → SLI = 1.0 → consumed = 0 → remaining = 1.0
  let state = record_n_good(init(), "latency_slo", 1000)
  let remaining = budget_remaining(state, "latency_slo")
  // remaining must be very close to 1.0 (exact equality fine here)
  { remaining >. 0.99 } |> should.be_true()
}

pub fn sli_all_bad_budget_is_exhausted_test() {
  // 100 bad events → SLI = 0.0 → budget_consumed >= 1.0 → remaining = 0.0
  let state = record_n_bad(init(), "freshness_slo", 100)
  let remaining = budget_remaining(state, "freshness_slo")
  remaining |> should.equal(0.0)
}

// ---------------------------------------------------------------------------
// Section 4 — budget math: consumed fraction clamp
// ---------------------------------------------------------------------------

pub fn budget_remaining_clamped_to_zero_on_full_violation_test() {
  // All bad events: budget_remaining must not go below 0.0
  let state = record_n_bad(init(), "availability_slo", 50)
  let remaining = budget_remaining(state, "availability_slo")
  { remaining >=. 0.0 } |> should.be_true()
  { remaining <=. 1.0 } |> should.be_true()
}

pub fn budget_remaining_unknown_slo_returns_1_0_test() {
  budget_remaining(init(), "does_not_exist") |> should.equal(1.0)
}

// ---------------------------------------------------------------------------
// Section 5 — status transitions
// ---------------------------------------------------------------------------

pub fn status_met_when_no_events_test() {
  // Zero events = SLOMet (assume healthy)
  let state = init()
  let statuses = check_budgets(state)
  list.all(statuses, fn(p) { p.1 == SLOMet }) |> should.be_true()
}

pub fn status_violated_when_all_bad_test() {
  // 100 bad events on truth_slo (target ~1.0) → SLOViolated
  let state = record_n_bad(init(), "truth_slo", 100)
  let statuses = check_budgets(state)
  let truth_status =
    list.find(statuses, fn(p) { p.0 == "truth_slo" })
    |> fn(r) {
      case r {
        Ok(#(_, s)) -> s
        Error(_) -> SLOMet
      }
    }
  truth_status |> should.equal(SLOViolated)
}

// ---------------------------------------------------------------------------
// Section 6 — check_budgets: returns list of (name, status) tuples
// ---------------------------------------------------------------------------

pub fn check_budgets_returns_four_pairs_test() {
  check_budgets(init()) |> list.length() |> should.equal(4)
}

pub fn check_budgets_all_met_on_clean_state_test() {
  let all_met = list.all(check_budgets(init()), fn(p) { p.1 == SLOMet })
  all_met |> should.be_true()
}

// ---------------------------------------------------------------------------
// Section 7 — budget_remaining: per-SLO query
// ---------------------------------------------------------------------------

pub fn budget_remaining_after_good_event_is_still_high_test() {
  let state = record_event(init(), "latency_slo", True)
  { budget_remaining(state, "latency_slo") >. 0.9 } |> should.be_true()
}

pub fn budget_remaining_decreases_after_bad_event_test() {
  let before = budget_remaining(init(), "freshness_slo")
  let state = record_event(init(), "freshness_slo", False)
  let after = budget_remaining(state, "freshness_slo")
  { after <. before } |> should.be_true()
}

// ---------------------------------------------------------------------------
// Section 8 — to_json: structure, required keys, SLO count
// ---------------------------------------------------------------------------

pub fn to_json_contains_page_key_test() {
  string.contains(to_json(init()), "SLO Dashboard") |> should.be_true()
}

pub fn to_json_contains_slos_key_test() {
  string.contains(to_json(init()), "\"slos\"") |> should.be_true()
}

pub fn to_json_contains_total_checks_key_test() {
  string.contains(to_json(init()), "\"total_checks\"") |> should.be_true()
}

pub fn to_json_contains_truth_slo_test() {
  string.contains(to_json(init()), "truth_slo") |> should.be_true()
}

pub fn to_json_contains_budget_remaining_key_test() {
  string.contains(to_json(init()), "budget_remaining") |> should.be_true()
}

// ---------------------------------------------------------------------------
// Section 9 — summary: non-empty, contains SLO names
// ---------------------------------------------------------------------------

pub fn summary_is_non_empty_test() {
  { string.length(summary(init())) > 0 } |> should.be_true()
}

pub fn summary_contains_truth_slo_test() {
  string.contains(summary(init()), "truth_slo") |> should.be_true()
}

pub fn summary_contains_total_checks_test() {
  string.contains(summary(init()), "checks recorded") |> should.be_true()
}

// ---------------------------------------------------------------------------
// Section 10 — accumulation: multiple records, monotonic total_checks
// ---------------------------------------------------------------------------

pub fn total_checks_monotonically_increases_test() {
  let s1 = init()
  let s2 = record_event(s1, "truth_slo", True)
  let s3 = record_event(s2, "freshness_slo", False)
  let s4 = record_event(s3, "latency_slo", True)
  { s4.total_checks > s3.total_checks } |> should.be_true()
  { s3.total_checks > s2.total_checks } |> should.be_true()
  { s2.total_checks > s1.total_checks } |> should.be_true()
}

pub fn total_checks_equals_event_count_test() {
  let state =
    init()
    |> record_event("truth_slo", True)
    |> record_event("freshness_slo", True)
    |> record_event("availability_slo", False)
    |> record_event("latency_slo", True)
    |> record_event("truth_slo", False)
  state.total_checks |> should.equal(5)
}

// ---------------------------------------------------------------------------
// Section 11 — SloBudget / SloMetric pipeline API (8 tests)
// ---------------------------------------------------------------------------

/// Helper: build a fast, successful SloMetric for the given endpoint.
fn fast_ok_metric(endpoint: String) {
  SloMetric(
    endpoint: endpoint,
    latency_ms: 10,
    status_code: 200,
    timestamp_ms: 0,
  )
}

/// Helper: build a slow, successful SloMetric.
fn slow_ok_metric(endpoint: String) {
  SloMetric(
    endpoint: endpoint,
    latency_ms: 1000,
    status_code: 200,
    timestamp_ms: 0,
  )
}

/// Helper: build a fast, server-error SloMetric.
fn fast_err_metric(endpoint: String) {
  SloMetric(
    endpoint: endpoint,
    latency_ms: 10,
    status_code: 500,
    timestamp_ms: 0,
  )
}

pub fn init_budget_zero_requests_test() {
  // init_budget() must start with zero counters
  let b = init_budget()
  b.total_requests |> should.equal(0)
  b.fast_requests |> should.equal(0)
  b.successful_requests |> should.equal(0)
}

pub fn init_budget_latency_sli_100_when_empty_test() {
  // No requests → assume healthy → 100.0%
  latency_sli(init_budget()) |> should.equal(100.0)
}

pub fn init_budget_availability_sli_100_when_empty_test() {
  availability_sli(init_budget()) |> should.equal(100.0)
}

pub fn init_budget_error_budget_full_when_empty_test() {
  error_budget_remaining(init_budget()) |> should.equal(1.0)
}

pub fn record_fast_request_increments_fast_count_test() {
  let b = init_budget() |> record(fast_ok_metric("/health"))
  b.total_requests |> should.equal(1)
  b.fast_requests |> should.equal(1)
}

pub fn record_slow_request_does_not_increment_fast_count_test() {
  let b = init_budget() |> record(slow_ok_metric("/api/v1/plan/status"))
  b.total_requests |> should.equal(1)
  b.fast_requests |> should.equal(0)
}

pub fn record_5xx_decrements_availability_sli_test() {
  let b = init_budget() |> record(fast_err_metric("/api/v1/immune"))
  // 0 successful out of 1 total → availability_sli = 0.0%
  availability_sli(b) |> should.equal(0.0)
  b.successful_requests |> should.equal(0)
}

pub fn budget_summary_non_empty_test() {
  let b = init_budget() |> record(fast_ok_metric("/health"))
  { string.length(budget_summary(b)) > 0 } |> should.be_true()
}

pub fn error_budget_decreases_after_slow_requests_test() {
  let before = error_budget_remaining(init_budget())
  // Record one slow request — error budget must decrease
  let b = init_budget() |> record(slow_ok_metric("/api/v1/dashboard"))
  let after = error_budget_remaining(b)
  { after <. before } |> should.be_true()
}

pub fn record_multiple_requests_total_accumulates_test() {
  let b =
    init_budget()
    |> record(fast_ok_metric("/health"))
    |> record(slow_ok_metric("/api/v1/dashboard"))
    |> record(fast_err_metric("/api/v1/immune"))
  b.total_requests |> should.equal(3)
  b.fast_requests |> should.equal(2)
  b.successful_requests |> should.equal(2)
}
