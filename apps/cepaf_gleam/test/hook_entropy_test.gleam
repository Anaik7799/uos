//// hook_entropy_test.gleam
//// Tests for cepaf_gleam/ha/hook_entropy — Shannon entropy alarm.
//// STAMP: SC-BOOTSTRAP-005, SC-FRAC-RRF-001
////
//// Per [zk-3346fc607a1ef9e6]: all asserts use real entropy values, not placeholders.
//// Per [zk-c14e1d23afff486c]: pure computation, no blocking I/O.

import cepaf_gleam/ha/hook_entropy.{
  DaemonDown, DegradedStale, LockStale, OtherFailure, Success, Timeout,
  entropy_alarm_high, shannon_entropy_bits,
}
import gleam/list
import gleeunit/should

// ---------------------------------------------------------------------------
// T1 — All-success window → H ≈ 0.0, alarm false
// ---------------------------------------------------------------------------
// A window of identical outcomes has p(Success) = 1.0.
// H = -(1.0 * log2(1.0)) = -(1.0 * 0.0) = 0.0
pub fn all_success_entropy_is_zero_test() {
  let outcomes = list.repeat(Success, 20)
  let h = shannon_entropy_bits(outcomes)
  // H should be exactly 0.0 for a degenerate distribution.
  h |> should.equal(0.0)
}

pub fn all_success_alarm_is_false_test() {
  let outcomes = list.repeat(Success, 20)
  entropy_alarm_high(outcomes, 0.5) |> should.equal(False)
}

// ---------------------------------------------------------------------------
// T2 — Uniform distribution over 5 outcomes → H ≈ 2.32 bits, alarm true
// ---------------------------------------------------------------------------
// H(uniform-5) = log2(5) ≈ 2.3219 bits.
// We use 4 copies of each of 5 outcomes (20 total) for exact uniformity.
pub fn uniform_five_entropy_approximately_2_32_test() {
  let outcomes =
    list.flatten([
      list.repeat(Success, 4),
      list.repeat(DegradedStale, 4),
      list.repeat(DaemonDown, 4),
      list.repeat(LockStale, 4),
      list.repeat(Timeout, 4),
    ])
  let h = shannon_entropy_bits(outcomes)
  // log2(5) ≈ 2.3219.  Accept within ±0.01 bits.
  let lower = 2.31
  let upper = 2.33
  let in_range = h >=. lower && h <=. upper
  in_range |> should.equal(True)
}

pub fn uniform_five_alarm_is_true_test() {
  let outcomes =
    list.flatten([
      list.repeat(Success, 4),
      list.repeat(DegradedStale, 4),
      list.repeat(DaemonDown, 4),
      list.repeat(LockStale, 4),
      list.repeat(Timeout, 4),
    ])
  // Default threshold 0.5 bits — uniform-5 at ~2.32 bits clears it.
  entropy_alarm_high(outcomes, 0.5) |> should.equal(True)
}

// ---------------------------------------------------------------------------
// T3 — All-failure window → H ≈ 0.0, alarm false
// ---------------------------------------------------------------------------
// p(DaemonDown) = 1.0 → H = 0.0.
// Note: rule C-1 BayesianHealthLow fires separately; C-2 should NOT fire here.
pub fn all_failure_entropy_is_zero_test() {
  let outcomes = list.repeat(DaemonDown, 10)
  let h = shannon_entropy_bits(outcomes)
  h |> should.equal(0.0)
}

pub fn all_failure_alarm_is_false_test() {
  let outcomes = list.repeat(DaemonDown, 10)
  entropy_alarm_high(outcomes, 0.5) |> should.equal(False)
}

// ---------------------------------------------------------------------------
// T4 — Mixed 70/30 split → H computed correctly (within 0.01 bits)
// ---------------------------------------------------------------------------
// 7 × Success + 3 × OtherFailure (total 10).
// p1 = 0.7, p2 = 0.3
// H = -(0.7*log2(0.7) + 0.3*log2(0.3))
//   = -(0.7*(-0.5146) + 0.3*(-1.7370))
//   = -((-0.3602) + (-0.5211))
//   = 0.8813 bits
pub fn mixed_70_30_entropy_test() {
  let outcomes =
    list.flatten([list.repeat(Success, 7), list.repeat(OtherFailure, 3)])
  let h = shannon_entropy_bits(outcomes)
  // Accept within ±0.01 bits of 0.8813.
  let lower = 0.87
  let upper = 0.89
  let in_range = h >=. lower && h <=. upper
  in_range |> should.equal(True)
}

pub fn mixed_70_30_alarm_above_threshold_test() {
  let outcomes =
    list.flatten([list.repeat(Success, 7), list.repeat(OtherFailure, 3)])
  // 0.88 bits > 0.5 threshold → alarm true
  entropy_alarm_high(outcomes, 0.5) |> should.equal(True)
}

pub fn mixed_70_30_alarm_below_high_threshold_test() {
  let outcomes =
    list.flatten([list.repeat(Success, 7), list.repeat(OtherFailure, 3)])
  // 0.88 bits < 1.5 threshold → alarm false
  entropy_alarm_high(outcomes, 1.5) |> should.equal(False)
}

// ---------------------------------------------------------------------------
// T5 — Empty window → H = 0.0 (no NaN, no crash)
// ---------------------------------------------------------------------------
pub fn empty_window_entropy_is_zero_test() {
  let h = shannon_entropy_bits([])
  h |> should.equal(0.0)
}

pub fn empty_window_alarm_is_false_test() {
  entropy_alarm_high([], 0.5) |> should.equal(False)
}

// ---------------------------------------------------------------------------
// T6 — Single outcome → H = 0.0 regardless of which outcome
// ---------------------------------------------------------------------------
pub fn single_outcome_entropy_is_zero_test() {
  let h = shannon_entropy_bits([Timeout])
  h |> should.equal(0.0)
}

// ---------------------------------------------------------------------------
// T7 — Uniform over all 6 outcomes → H ≈ 2.585 bits (log2(6))
// ---------------------------------------------------------------------------
// log2(6) ≈ 2.5849.  Accept within ±0.01.
pub fn uniform_six_entropy_approximately_2_58_test() {
  let outcomes =
    list.flatten([
      list.repeat(Success, 3),
      list.repeat(DegradedStale, 3),
      list.repeat(DaemonDown, 3),
      list.repeat(LockStale, 3),
      list.repeat(Timeout, 3),
      list.repeat(OtherFailure, 3),
    ])
  let h = shannon_entropy_bits(outcomes)
  let lower = 2.57
  let upper = 2.6
  let in_range = h >=. lower && h <=. upper
  in_range |> should.equal(True)
}
