/// SERBAN-1 — Probabilistic Safety Shield Tests — 15-test suite
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-SIL4-001, SC-SIL4-006, SC-SAFETY-001, SC-FUNC-001,
///        SC-GUARD-001, SC-GLM-UI-001, SC-MUDA-001
/// Ultrathink: Focus #5 (Formal Verification), #10 (HA Seamless Upgrades)
///
/// यत्र योगेश्वरः कृष्णः — Where there is formal safety, there is mastery (Gita 18.78)
import cepaf_gleam/ha/probabilistic_shield.{
  Safe, ShieldState, Uncertain, Unsafe, check_decision, init, safe_threshold,
  safety_rate, summary, to_json, unsafe_threshold, verdict_to_json,
  verdict_to_string,
}
import gleam/string
import gleeunit/should

// ===========================================================================
// init — zero state
// ===========================================================================

pub fn init_decisions_checked_zero_test() {
  let s = init()
  s.decisions_checked |> should.equal(0)
}

pub fn init_safe_count_zero_test() {
  let s = init()
  s.safe_count |> should.equal(0)
}

pub fn init_unsafe_count_zero_test() {
  let s = init()
  s.unsafe_count |> should.equal(0)
}

pub fn init_uncertain_count_zero_test() {
  let s = init()
  s.uncertain_count |> should.equal(0)
}

// ===========================================================================
// check_decision — threshold logic
// ===========================================================================

pub fn check_decision_high_health_low_risk_is_safe_test() {
  // health=1.0, risk=0.0 → combined=1.0 ≥ 0.7 → Safe
  let #(s2, verdict) = check_decision(init(), 1.0, 0.0)
  verdict |> should.equal(Safe)
  s2.safe_count |> should.equal(1)
  s2.decisions_checked |> should.equal(1)
}

pub fn check_decision_zero_health_is_unsafe_test() {
  // health=0.0, risk=anything → combined=0.0 ≤ 0.3 → Unsafe
  let #(s2, verdict) = check_decision(init(), 0.0, 0.5)
  verdict |> should.equal(Unsafe)
  s2.unsafe_count |> should.equal(1)
}

pub fn check_decision_mid_range_is_uncertain_test() {
  // health=0.6, risk=0.3 → combined = 0.6 × 0.7 = 0.42
  // 0.42 is between 0.3 and 0.7 → Uncertain
  let #(s2, verdict) = check_decision(init(), 0.6, 0.3)
  case verdict {
    Uncertain(_) -> s2.uncertain_count |> should.equal(1)
    _ -> should.fail()
  }
}

pub fn check_decision_uncertain_confidence_in_range_test() {
  // combined must be in (0.3, 0.7)
  let #(_, verdict) = check_decision(init(), 0.6, 0.3)
  case verdict {
    Uncertain(c) -> {
      let ok = c >. unsafe_threshold && c <. safe_threshold
      ok |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn check_decision_clamps_health_above_one_test() {
  // health=2.0 should be clamped to 1.0 — still Safe
  let #(_, verdict) = check_decision(init(), 2.0, 0.0)
  verdict |> should.equal(Safe)
}

pub fn check_decision_clamps_risk_above_one_test() {
  // risk=2.0 → clamped to 1.0 → combined = health × 0.0 = 0.0 → Unsafe
  let #(_, verdict) = check_decision(init(), 1.0, 2.0)
  verdict |> should.equal(Unsafe)
}

pub fn check_decision_increments_total_each_call_test() {
  let s0 = init()
  let #(s1, _) = check_decision(s0, 1.0, 0.0)
  let #(s2, _) = check_decision(s1, 0.0, 0.5)
  let #(s3, _) = check_decision(s2, 0.6, 0.3)
  s3.decisions_checked |> should.equal(3)
}

// ===========================================================================
// safety_rate
// ===========================================================================

pub fn safety_rate_empty_state_is_one_test() {
  safety_rate(init()) |> should.equal(1.0)
}

pub fn safety_rate_all_safe_is_one_test() {
  let s0 = init()
  let #(s1, _) = check_decision(s0, 1.0, 0.0)
  let #(s2, _) = check_decision(s1, 1.0, 0.0)
  safety_rate(s2) |> should.equal(1.0)
}

pub fn safety_rate_half_safe_test() {
  let s0 = init()
  let #(s1, _) = check_decision(s0, 1.0, 0.0)
  let #(s2, _) = check_decision(s1, 0.0, 0.5)
  let rate = safety_rate(s2)
  // 1 safe out of 2 = 0.5
  rate |> should.equal(0.5)
}

// ===========================================================================
// Serialisation
// ===========================================================================

pub fn to_json_contains_decisions_checked_test() {
  let #(s, _) = check_decision(init(), 1.0, 0.0)
  let j = to_json(s)
  string.contains(j, "\"decisions_checked\":1") |> should.be_true
}

pub fn verdict_to_json_safe_test() {
  let j = verdict_to_json(Safe)
  string.contains(j, "\"safe\"") |> should.be_true
}

pub fn verdict_to_json_unsafe_test() {
  let j = verdict_to_json(Unsafe)
  string.contains(j, "\"unsafe\"") |> should.be_true
}

pub fn verdict_to_json_uncertain_contains_confidence_test() {
  let j = verdict_to_json(Uncertain(0.5))
  string.contains(j, "\"uncertain\"") |> should.be_true
  string.contains(j, "confidence") |> should.be_true
}

pub fn verdict_to_string_all_variants_test() {
  verdict_to_string(Safe) |> should.equal("Safe")
  verdict_to_string(Unsafe) |> should.equal("Unsafe")
  let u = verdict_to_string(Uncertain(0.42))
  string.contains(u, "Uncertain") |> should.be_true
}

pub fn summary_contains_checked_label_test() {
  let s =
    ShieldState(
      decisions_checked: 3,
      safe_count: 2,
      unsafe_count: 0,
      uncertain_count: 1,
    )
  let txt = summary(s)
  string.contains(txt, "checked=3") |> should.be_true
}
