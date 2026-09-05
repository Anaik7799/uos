/// Counterfactual Explainer Tests — Guard rule decision explanation (SERBAN-3)
///
/// 12 tests covering: explain, nearest_flip, summary, to_json.
///
/// Layer: L5_COGNITIVE
/// STAMP: SC-OODA-001, SC-VER-001, SC-MUDA-001, SC-SIL4-001
/// Ultrathink: Focus #5 (Continuous Formal Verification),
///              Focus #6 (Embedded SLM Cognitive Kernels)
///
/// यत्र नायस्तु पूज्यन्ते — Where understanding is honoured, there is wisdom
import cepaf_gleam/ha/counterfactual.{
  type Counterfactual, Counterfactual, explain, nearest_flip, summary, to_json,
}
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// ===========================================================================
// 1. explain — parameter-level counterfactual generation
// ===========================================================================

pub fn explain_healthy_system_no_health_cf_test() {
  // health = 0.9 (well above 0.8 pass threshold): no health counterfactual for fail→pass
  let cfs = explain("rule-health", 0.9, 1.5, 0, 0, -0.1)
  // Should only contain a health cf for pass→fail direction
  let health_cfs =
    list_filter(cfs, fn(c: Counterfactual) { c.flip_parameter == "health" })
  // There should be a flip-to-fail counterfactual since health > pass threshold
  { list_length(health_cfs) >= 1 } |> should.be_true()
}

pub fn explain_failing_health_produces_health_cf_test() {
  // health = 0.2 (below 0.4 fail threshold): verdict=False, flip needed
  let cfs = explain("rule-health", 0.2, 1.5, 0, 0, -0.1)
  let health_cfs =
    list_filter(cfs, fn(c: Counterfactual) { c.flip_parameter == "health" })
  { list_length(health_cfs) >= 1 } |> should.be_true()
}

pub fn explain_high_entropy_produces_entropy_cf_test() {
  // entropy = 3.0 > 2.5 threshold → failing; expect entropy counterfactual
  let cfs = explain("rule-entropy", 0.9, 3.0, 0, 0, -0.1)
  let ecfs =
    list_filter(cfs, fn(c: Counterfactual) { c.flip_parameter == "entropy" })
  { list_length(ecfs) >= 1 } |> should.be_true()
}

pub fn explain_low_entropy_no_entropy_cf_test() {
  // entropy = 1.0 < 2.5 → passing; no entropy cf
  let cfs = explain("rule-entropy", 0.9, 1.0, 0, 0, -0.1)
  let ecfs =
    list_filter(cfs, fn(c: Counterfactual) { c.flip_parameter == "entropy" })
  list_length(ecfs) |> should.equal(0)
}

pub fn explain_deep_cascade_produces_cascade_cf_test() {
  // cascade = 5 > 3 threshold → failing
  let cfs = explain("rule-cascade", 0.9, 1.5, 5, 0, -0.1)
  let ccfs =
    list_filter(cfs, fn(c: Counterfactual) { c.flip_parameter == "cascade" })
  { list_length(ccfs) >= 1 } |> should.be_true()
}

pub fn explain_many_failures_produces_failure_cf_test() {
  // failures = 8 > 5 threshold → failing
  let cfs = explain("rule-failures", 0.9, 1.5, 0, 8, -0.1)
  let fcfs =
    list_filter(cfs, fn(c: Counterfactual) { c.flip_parameter == "failures" })
  { list_length(fcfs) >= 1 } |> should.be_true()
}

pub fn explain_positive_lyapunov_produces_lyapunov_cf_test() {
  // lyapunov = 0.5 > 0.0 → unstable → failing
  let cfs = explain("rule-lyapunov", 0.9, 1.5, 0, 0, 0.5)
  let lcfs =
    list_filter(cfs, fn(c: Counterfactual) { c.flip_parameter == "lyapunov" })
  { list_length(lcfs) >= 1 } |> should.be_true()
}

pub fn explain_all_nominal_returns_only_pass_to_fail_cfs_test() {
  // Fully healthy system: health=0.9, entropy=1.0, cascade=0, failures=0, lyapunov=-0.5
  let cfs = explain("rule-nominal", 0.9, 1.0, 0, 0, -0.5)
  // For a fully passing system, only pass→fail flips can exist
  let all_currently_passing =
    list_all(cfs, fn(c: Counterfactual) { c.current_verdict == True })
  all_currently_passing |> should.be_true()
}

// ===========================================================================
// 2. nearest_flip
// ===========================================================================

pub fn nearest_flip_empty_list_returns_none_test() {
  nearest_flip([]) |> should.equal(None)
}

pub fn nearest_flip_single_element_returns_it_test() {
  let cf =
    Counterfactual(
      rule_id: "r",
      current_verdict: False,
      flip_parameter: "health",
      flip_value: 0.81,
      original_value: 0.2,
    )
  nearest_flip([cf]) |> should.equal(Some(cf))
}

pub fn nearest_flip_selects_minimum_delta_test() {
  let cf_big =
    Counterfactual(
      rule_id: "r",
      current_verdict: False,
      flip_parameter: "health",
      flip_value: 0.9,
      original_value: 0.1,
    )
  // delta = 0.8
  let cf_small =
    Counterfactual(
      rule_id: "r",
      current_verdict: False,
      flip_parameter: "entropy",
      flip_value: 2.49,
      original_value: 2.6,
    )
  // delta = 0.11
  let result = nearest_flip([cf_big, cf_small])
  result |> should.equal(Some(cf_small))
}

// ===========================================================================
// 3. summary and to_json
// ===========================================================================

pub fn summary_empty_list_contains_no_counterfactuals_test() {
  let s = summary([])
  { string.contains(s, "No counterfactuals") } |> should.be_true()
}

pub fn to_json_produces_array_brackets_test() {
  let j = to_json([])
  j |> should.equal("[]")
}

pub fn to_json_nonempty_contains_rule_id_key_test() {
  let cf =
    Counterfactual(
      rule_id: "test-rule",
      current_verdict: True,
      flip_parameter: "health",
      flip_value: 0.39,
      original_value: 0.9,
    )
  let j = to_json([cf])
  { string.contains(j, "\"rule_id\"") } |> should.be_true()
  { string.contains(j, "test-rule") } |> should.be_true()
}

// ===========================================================================
// Helpers
// ===========================================================================

fn list_filter(xs: List(a), pred: fn(a) -> Bool) -> List(a) {
  case xs {
    [] -> []
    [h, ..t] ->
      case pred(h) {
        True -> [h, ..list_filter(t, pred)]
        False -> list_filter(t, pred)
      }
  }
}

fn list_length(xs: List(a)) -> Int {
  case xs {
    [] -> 0
    [_, ..t] -> 1 + list_length(t)
  }
}

fn list_all(xs: List(a), pred: fn(a) -> Bool) -> Bool {
  case xs {
    [] -> True
    [h, ..t] ->
      case pred(h) {
        False -> False
        True -> list_all(t, pred)
      }
  }
}
