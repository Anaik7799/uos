// =============================================================================
// hook_latency_test.gleam — Hook Latency Tracker Tests (SA3)
// =============================================================================
// Tests for ha/hook_latency.gleam
//
// Coverage categories addressed:
//   C1 Page Structure  — init() returns empty tracker with zero counters
//   C2 Status Badges   — is_within_budget / summary reflect state correctly
//   C3 Data Grids      — record() accumulates multiple timings
//   C4 Timeline        — slowest() correctly identifies max-duration hook
//   C5 Interactive     — make_timing() computes duration and timed_out correctly
//   C6 Media/Rich      — summary() contains all key labels
//   C7 AI Advisory     — timeout_count() counts exceeded-budget hooks
//   C8 Action Button   — average_ms() returns 0.0 on empty tracker (safety gate)
//
// STAMP: SC-MUDA-001, SC-ARCH-SPLIT-002, SC-OODA-ACCEL-003
// Layer: L1_ATOMIC_DEBUG
// =============================================================================

import cepaf_gleam/ha/hook_latency
import gleam/string
import gleeunit/should

// =============================================================================
// C1 — init() structure
// =============================================================================

pub fn init_total_hooks_zero_test() {
  hook_latency.init().total_hooks
  |> should.equal(0)
}

pub fn init_total_duration_zero_test() {
  hook_latency.init().total_duration_ms
  |> should.equal(0)
}

pub fn init_timings_empty_test() {
  hook_latency.init().timings
  |> should.equal([])
}

// =============================================================================
// C5 — make_timing constructor
// =============================================================================

pub fn make_timing_computes_duration_test() {
  let t = hook_latency.make_timing("SessionStart", 1000, 1050)
  t.duration_ms
  |> should.equal(50)
}

pub fn make_timing_hook_name_preserved_test() {
  let t = hook_latency.make_timing("UserPromptSubmit", 0, 80)
  t.hook_name
  |> should.equal("UserPromptSubmit")
}

pub fn make_timing_not_timed_out_when_under_budget_test() {
  let t = hook_latency.make_timing("PostToolUse", 0, 150)
  t.timed_out
  |> should.be_false()
}

pub fn make_timing_timed_out_at_timeout_threshold_test() {
  // timeout_ms = 200; duration = 200 → timed_out = True
  let t = hook_latency.make_timing("Stop", 0, 200)
  t.timed_out
  |> should.be_true()
}

pub fn make_timing_timed_out_above_threshold_test() {
  let t = hook_latency.make_timing("SlowHook", 0, 500)
  t.timed_out
  |> should.be_true()
}

// =============================================================================
// C3 — record() accumulation
// =============================================================================

pub fn record_increments_total_hooks_test() {
  let t = hook_latency.make_timing("H", 0, 40)
  let tracker = hook_latency.init() |> hook_latency.record(t)
  tracker.total_hooks
  |> should.equal(1)
}

pub fn record_accumulates_duration_test() {
  let t1 = hook_latency.make_timing("A", 0, 30)
  let t2 = hook_latency.make_timing("B", 100, 160)
  let tracker =
    hook_latency.init()
    |> hook_latency.record(t1)
    |> hook_latency.record(t2)
  tracker.total_duration_ms
  |> should.equal(90)
}

pub fn record_two_hooks_total_count_test() {
  let t1 = hook_latency.make_timing("A", 0, 20)
  let t2 = hook_latency.make_timing("B", 0, 25)
  let tracker =
    hook_latency.init()
    |> hook_latency.record(t1)
    |> hook_latency.record(t2)
  tracker.total_hooks
  |> should.equal(2)
}

// =============================================================================
// C8 — average_ms edge cases
// =============================================================================

pub fn average_ms_empty_tracker_is_zero_test() {
  hook_latency.init()
  |> hook_latency.average_ms()
  |> should.equal(0.0)
}

pub fn average_ms_single_hook_equals_duration_test() {
  let t = hook_latency.make_timing("H", 0, 80)
  let tracker = hook_latency.init() |> hook_latency.record(t)
  hook_latency.average_ms(tracker)
  |> should.equal(80.0)
}

pub fn average_ms_two_hooks_is_mean_test() {
  let t1 = hook_latency.make_timing("A", 0, 60)
  let t2 = hook_latency.make_timing("B", 0, 100)
  let tracker =
    hook_latency.init()
    |> hook_latency.record(t1)
    |> hook_latency.record(t2)
  hook_latency.average_ms(tracker)
  |> should.equal(80.0)
}

// =============================================================================
// C4 — slowest() identification
// =============================================================================

pub fn slowest_empty_tracker_is_error_test() {
  hook_latency.init()
  |> hook_latency.slowest()
  |> should.be_error()
}

pub fn slowest_single_hook_returns_it_test() {
  let t = hook_latency.make_timing("Only", 0, 55)
  let tracker = hook_latency.init() |> hook_latency.record(t)
  case hook_latency.slowest(tracker) {
    Ok(s) -> s.hook_name |> should.equal("Only")
    Error(_) -> should.fail()
  }
}

pub fn slowest_returns_max_duration_test() {
  let fast = hook_latency.make_timing("Fast", 0, 20)
  let slow = hook_latency.make_timing("Slow", 0, 180)
  let medium = hook_latency.make_timing("Medium", 0, 90)
  let tracker =
    hook_latency.init()
    |> hook_latency.record(fast)
    |> hook_latency.record(slow)
    |> hook_latency.record(medium)
  case hook_latency.slowest(tracker) {
    Ok(s) -> s.hook_name |> should.equal("Slow")
    Error(_) -> should.fail()
  }
}

// =============================================================================
// C7 — timeout_count
// =============================================================================

pub fn timeout_count_zero_when_none_exceed_test() {
  let t = hook_latency.make_timing("H", 0, 50)
  let tracker = hook_latency.init() |> hook_latency.record(t)
  hook_latency.timeout_count(tracker)
  |> should.equal(0)
}

pub fn timeout_count_one_when_one_exceeds_test() {
  let ok = hook_latency.make_timing("Fast", 0, 50)
  let slow = hook_latency.make_timing("Slow", 0, 250)
  let tracker =
    hook_latency.init()
    |> hook_latency.record(ok)
    |> hook_latency.record(slow)
  hook_latency.timeout_count(tracker)
  |> should.equal(1)
}

// =============================================================================
// C2 — is_within_budget
// =============================================================================

pub fn within_budget_true_for_fast_hooks_test() {
  let t = hook_latency.make_timing("H", 0, 50)
  hook_latency.init()
  |> hook_latency.record(t)
  |> hook_latency.is_within_budget()
  |> should.be_true()
}

pub fn within_budget_false_for_slow_hooks_test() {
  // average must exceed 100 ms
  let t = hook_latency.make_timing("Slow", 0, 150)
  hook_latency.init()
  |> hook_latency.record(t)
  |> hook_latency.is_within_budget()
  |> should.be_false()
}

// =============================================================================
// C6 — summary()
// =============================================================================

pub fn summary_contains_hooks_label_test() {
  hook_latency.init()
  |> hook_latency.summary()
  |> string.contains("hooks=")
  |> should.be_true()
}

pub fn summary_contains_status_label_test() {
  hook_latency.init()
  |> hook_latency.summary()
  |> string.contains("status=")
  |> should.be_true()
}

pub fn summary_is_non_empty_test() {
  hook_latency.init()
  |> hook_latency.summary()
  |> string.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}

pub fn summary_within_budget_status_test() {
  let t = hook_latency.make_timing("H", 0, 40)
  hook_latency.init()
  |> hook_latency.record(t)
  |> hook_latency.summary()
  |> string.contains("WITHIN_BUDGET")
  |> should.be_true()
}
