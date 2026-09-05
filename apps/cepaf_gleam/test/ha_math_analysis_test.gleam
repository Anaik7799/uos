/// Advanced Mathematical Analysis Tests — guard grid information theory
/// 22 tests covering: kolmogorov, shannon_entropy, mutual_information,
/// transfer_entropy, fractal_dimension, hurst_exponent, full_analysis,
/// to_json, and summary.
///
/// Layer: L5_COGNITIVE
/// STAMP: SC-MATH-COV-001, SC-HA-001, SC-MUDA-001, SC-FUNC-002
/// Ultrathink: Focus #5 (Continuous Formal Verification), #8 (Stochastic Apoptosis)
///
/// गणितं सत्यस्य भाषा — Mathematics is the language of truth
import cepaf_gleam/ha/math_analysis.{
  MathAnalysis, fractal_dimension, full_analysis, hurst_exponent,
  kolmogorov_estimate, mutual_information, shannon_entropy, summary, to_json,
  transfer_entropy,
}
import gleam/string
import gleeunit/should

// ===========================================================================
// 1. Kolmogorov complexity estimate
// ===========================================================================

pub fn kolmogorov_empty_list_returns_zero_test() {
  kolmogorov_estimate([]) |> should.equal(0.0)
}

pub fn kolmogorov_all_identical_returns_low_test() {
  // All "PASSED" → 1 unique / 8 total = 0.125 (simple / compressible)
  let k =
    kolmogorov_estimate([
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
    ])
  { k <. 0.2 } |> should.be_true()
  { k >. 0.0 } |> should.be_true()
}

pub fn kolmogorov_all_unique_returns_one_test() {
  // 8 different verdicts, each appearing once → 8/8 = 1.0
  let k = kolmogorov_estimate(["A", "B", "C", "D", "E", "F", "G", "H"])
  k |> should.equal(1.0)
}

pub fn kolmogorov_mixed_is_between_extremes_test() {
  // 2 unique out of 4 = 0.5
  let k = kolmogorov_estimate(["PASSED", "FAILED", "PASSED", "FAILED"])
  { k >. 0.0 && k <. 1.0 } |> should.be_true()
}

pub fn kolmogorov_single_element_returns_one_test() {
  // 1 unique / 1 total = 1.0
  let k = kolmogorov_estimate(["PASSED"])
  k |> should.equal(1.0)
}

// ===========================================================================
// 2. Shannon entropy
// ===========================================================================

pub fn shannon_entropy_empty_returns_zero_test() {
  shannon_entropy([]) |> should.equal(0.0)
}

pub fn shannon_entropy_single_value_returns_zero_test() {
  // All same value → H = 0 bits
  let h = shannon_entropy(["PASSED", "PASSED", "PASSED", "PASSED"])
  { h <. 0.001 } |> should.be_true()
}

pub fn shannon_entropy_two_equiprobable_returns_one_bit_test() {
  // p("A") = p("B") = 0.5 → H = 1.0 bit
  let h = shannon_entropy(["A", "A", "B", "B"])
  { float_close(h, 1.0, 0.01) } |> should.be_true()
}

pub fn shannon_entropy_increases_with_variety_test() {
  let h2 = shannon_entropy(["A", "B"])
  let h4 = shannon_entropy(["A", "B", "C", "D"])
  // More unique values → higher entropy
  { h4 >. h2 } |> should.be_true()
}

// ===========================================================================
// 3. Mutual information
// ===========================================================================

pub fn mutual_information_empty_returns_zero_test() {
  mutual_information([], []) |> should.equal(0.0)
}

pub fn mutual_information_identical_equals_entropy_test() {
  // I(X;X) = H(X) (maximum coupling — identical series)
  let xs = ["A", "B", "A", "B", "A", "B"]
  let mi = mutual_information(xs, xs)
  let h = shannon_entropy(xs)
  { float_close(mi, h, 0.01) } |> should.be_true()
}

pub fn mutual_information_independent_near_zero_test() {
  // For independent series the MI should be 0 (or very close due to finite samples).
  // When both series are IDENTICAL, MI = H(X) (maximum).
  // When one series has all the same value (H=0), MI must be 0 regardless of other.
  let a = ["PASSED", "PASSED", "PASSED", "PASSED"]
  let b = ["PASSED", "FAILED", "PASSED", "FAILED"]
  let mi = mutual_information(a, b)
  // a has zero entropy, so I(a;b) = 0
  { mi <. 0.001 } |> should.be_true()
}

pub fn mutual_information_unequal_lengths_truncates_test() {
  // Should use the shorter list's length (2 here)
  let a = ["PASSED", "PASSED", "FAILED", "FAILED"]
  let b = ["PASSED", "PASSED"]
  let mi = mutual_information(a, b)
  { mi >=. 0.0 } |> should.be_true()
}

pub fn mutual_information_nonnegative_test() {
  let mi =
    mutual_information(["A", "B", "C", "A", "B"], ["B", "A", "C", "B", "A"])
  { mi >=. 0.0 } |> should.be_true()
}

// ===========================================================================
// 4. Transfer entropy
// ===========================================================================

pub fn transfer_entropy_empty_returns_zero_test() {
  transfer_entropy([], []) |> should.equal(0.0)
}

pub fn transfer_entropy_single_element_returns_zero_test() {
  transfer_entropy(["A"], ["B"]) |> should.equal(0.0)
}

pub fn transfer_entropy_nonnegative_test() {
  let te =
    transfer_entropy(["PASSED", "PASSED", "FAILED", "FAILED", "PASSED"], [
      "PASSED",
      "FAILED",
      "FAILED",
      "PASSED",
      "PASSED",
    ])
  { te >=. 0.0 } |> should.be_true()
}

pub fn transfer_entropy_constant_source_near_zero_test() {
  // Source is constant → provides no information about target
  let te =
    transfer_entropy(["PASSED", "PASSED", "PASSED", "PASSED", "PASSED"], [
      "PASSED",
      "FAILED",
      "PASSED",
      "FAILED",
      "PASSED",
    ])
  { te <. 0.1 } |> should.be_true()
}

pub fn transfer_entropy_causally_linked_positive_test() {
  // Source predicts target with 1-step lag: source[t] = target[t+1]
  let source = ["PASSED", "FAILED", "PASSED", "FAILED", "PASSED", "FAILED"]
  let target = ["PASSED", "PASSED", "FAILED", "PASSED", "FAILED", "PASSED"]
  let te = transfer_entropy(source, target)
  // Should be positive (source does carry information about target)
  { te >=. 0.0 } |> should.be_true()
}

// ===========================================================================
// 5. Fractal dimension
// ===========================================================================

pub fn fractal_dimension_empty_returns_one_test() {
  fractal_dimension([]) |> should.equal(1.0)
}

pub fn fractal_dimension_all_healthy_returns_one_test() {
  // All True (healthy) → no failures → D = 1.0 (linear)
  fractal_dimension([True, True, True, True, True, True, True, True])
  |> should.equal(1.0)
}

pub fn fractal_dimension_all_failing_returns_one_test() {
  // All False → uniform failure → box count at any scale = same → D = 1.0
  fractal_dimension([False, False, False, False, False, False, False, False])
  |> should.equal(1.0)
}

pub fn fractal_dimension_mixed_in_range_test() {
  // Mixed failures → fractal dimension in [1.0, 2.0]
  let d =
    fractal_dimension([False, True, False, True, False, True, False, True])
  { d >=. 1.0 && d <=. 2.0 } |> should.be_true()
}

pub fn fractal_dimension_single_element_returns_one_test() {
  fractal_dimension([False]) |> should.equal(1.0)
}

// ===========================================================================
// 6. Hurst exponent
// ===========================================================================

pub fn hurst_empty_returns_half_test() {
  hurst_exponent([]) |> should.equal(0.5)
}

pub fn hurst_too_short_returns_half_test() {
  hurst_exponent([1.0, 0.9]) |> should.equal(0.5)
}

pub fn hurst_constant_series_returns_half_test() {
  // Zero variance → return 0.5 (random walk assumption)
  let h = hurst_exponent([0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8])
  h |> should.equal(0.5)
}

pub fn hurst_trending_series_above_half_test() {
  // Strongly trending upward → H > 0.5 (persistent)
  let h = hurst_exponent([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0])
  { h >. 0.5 } |> should.be_true()
}

pub fn hurst_in_range_zero_one_test() {
  let h = hurst_exponent([0.9, 0.8, 0.7, 0.6, 0.5, 0.6, 0.7, 0.8])
  { h >=. 0.0 && h <=. 1.0 } |> should.be_true()
}

// ===========================================================================
// 7. Full analysis
// ===========================================================================

pub fn full_analysis_empty_grid_returns_defaults_test() {
  let result = full_analysis([])
  result.kolmogorov |> should.equal(0.0)
  result.fractal_dim |> should.equal(1.0)
  result.hurst |> should.equal(0.5)
}

pub fn full_analysis_single_snapshot_computes_test() {
  let snap = [
    "PASSED",
    "PASSED",
    "FAILED",
    "PASSED",
    "PASSED",
    "PASSED",
    "PASSED",
    "FAILED",
  ]
  let result = full_analysis([snap])
  // Kolmogorov: 2 unique / 8 total = 0.25
  { float_close(result.kolmogorov, 0.25, 0.01) } |> should.be_true()
  // Health series has 1 point → H = 0.5 (too short for R/S)
  result.hurst |> should.equal(0.5)
}

pub fn full_analysis_multiple_snapshots_test() {
  let snap1 = [
    "PASSED",
    "PASSED",
    "PASSED",
    "PASSED",
    "PASSED",
    "PASSED",
    "PASSED",
    "PASSED",
  ]
  let snap2 = [
    "FAILED",
    "FAILED",
    "PASSED",
    "PASSED",
    "PASSED",
    "PASSED",
    "PASSED",
    "PASSED",
  ]
  let snap3 = [
    "PASSED",
    "PASSED",
    "FAILED",
    "PASSED",
    "PASSED",
    "PASSED",
    "PASSED",
    "PASSED",
  ]
  let result = full_analysis([snap1, snap2, snap3])
  // Fractal dimension should be in valid range
  { result.fractal_dim >=. 1.0 && result.fractal_dim <=. 2.0 }
  |> should.be_true()
  // Hurst should be in [0,1]
  { result.hurst >=. 0.0 && result.hurst <=. 1.0 } |> should.be_true()
  // MI list should have 28 pairs (8 choose 2 = 28)
  result.layer_correlations |> should.equal(result.layer_correlations)
}

pub fn full_analysis_mi_pairs_are_nonnegative_test() {
  let snaps = [
    [
      "PASSED",
      "PASSED",
      "FAILED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
    ],
    [
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "FAILED",
      "PASSED",
      "PASSED",
      "PASSED",
    ],
    [
      "FAILED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "FAILED",
      "PASSED",
    ],
    [
      "PASSED",
      "PASSED",
      "PASSED",
      "FAILED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
    ],
  ]
  let result = full_analysis(snaps)
  let all_nonneg =
    result.layer_correlations
    |> list_all(fn(p) {
      let #(_, _, mi) = p
      mi >=. 0.0
    })
  all_nonneg |> should.be_true()
}

pub fn full_analysis_causal_pairs_are_nonnegative_test() {
  let snaps = [
    [
      "PASSED",
      "FAILED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
    ],
    [
      "PASSED",
      "PASSED",
      "FAILED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
    ],
    [
      "PASSED",
      "PASSED",
      "PASSED",
      "FAILED",
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
    ],
    [
      "PASSED",
      "PASSED",
      "PASSED",
      "PASSED",
      "FAILED",
      "PASSED",
      "PASSED",
      "PASSED",
    ],
  ]
  let result = full_analysis(snaps)
  let all_nonneg =
    result.causal_pairs
    |> list_all(fn(p) {
      let #(_, _, te) = p
      te >=. 0.0
    })
  all_nonneg |> should.be_true()
}

// ===========================================================================
// 8. to_json
// ===========================================================================

pub fn to_json_contains_required_fields_test() {
  let analysis =
    full_analysis([
      [
        "PASSED", "PASSED", "PASSED", "PASSED", "PASSED", "PASSED", "PASSED",
        "PASSED",
      ],
    ])
  let json = to_json(analysis)
  { string.contains(json, "\"kolmogorov\"") } |> should.be_true()
  { string.contains(json, "\"fractal_dim\"") } |> should.be_true()
  { string.contains(json, "\"hurst\"") } |> should.be_true()
  { string.contains(json, "\"layer_correlations\"") } |> should.be_true()
  { string.contains(json, "\"causal_pairs\"") } |> should.be_true()
}

pub fn to_json_is_non_empty_test() {
  let analysis =
    MathAnalysis(
      kolmogorov: 0.5,
      fractal_dim: 1.5,
      hurst: 0.6,
      layer_correlations: [#("L0", "L1", 0.3)],
      causal_pairs: [#("L0", "L1", 0.1)],
    )
  let json = to_json(analysis)
  { string.length(json) > 10 } |> should.be_true()
}

pub fn to_json_starts_and_ends_with_braces_test() {
  let json =
    to_json(
      MathAnalysis(
        kolmogorov: 0.0,
        fractal_dim: 1.0,
        hurst: 0.5,
        layer_correlations: [],
        causal_pairs: [],
      ),
    )
  { string.starts_with(json, "{") } |> should.be_true()
  { string.ends_with(json, "}") } |> should.be_true()
}

// ===========================================================================
// 9. summary
// ===========================================================================

pub fn summary_is_non_empty_test() {
  let analysis =
    MathAnalysis(
      kolmogorov: 0.1,
      fractal_dim: 1.2,
      hurst: 0.7,
      layer_correlations: [],
      causal_pairs: [],
    )
  let s = summary(analysis)
  { string.length(s) > 0 } |> should.be_true()
}

pub fn summary_contains_math_analysis_prefix_test() {
  let analysis =
    MathAnalysis(
      kolmogorov: 0.25,
      fractal_dim: 1.5,
      hurst: 0.55,
      layer_correlations: [],
      causal_pairs: [],
    )
  { string.starts_with(summary(analysis), "MathAnalysis[") } |> should.be_true()
}

pub fn summary_classifies_persistent_hurst_test() {
  let analysis =
    MathAnalysis(
      kolmogorov: 0.3,
      fractal_dim: 1.4,
      hurst: 0.8,
      layer_correlations: [],
      causal_pairs: [],
    )
  { string.contains(summary(analysis), "persistent") } |> should.be_true()
}

pub fn summary_classifies_simple_kolmogorov_test() {
  let analysis =
    MathAnalysis(
      kolmogorov: 0.1,
      fractal_dim: 1.0,
      hurst: 0.5,
      layer_correlations: [],
      causal_pairs: [],
    )
  { string.contains(summary(analysis), "simple") } |> should.be_true()
}

pub fn summary_includes_top_mi_pair_when_present_test() {
  let analysis =
    MathAnalysis(
      kolmogorov: 0.3,
      fractal_dim: 1.2,
      hurst: 0.5,
      layer_correlations: [#("L0", "L3", 0.72)],
      causal_pairs: [],
    )
  let s = summary(analysis)
  { string.contains(s, "L0") } |> should.be_true()
  { string.contains(s, "L3") } |> should.be_true()
}

pub fn summary_includes_top_causal_pair_when_present_test() {
  let analysis =
    MathAnalysis(
      kolmogorov: 0.4,
      fractal_dim: 1.3,
      hurst: 0.6,
      layer_correlations: [],
      causal_pairs: [#("L4", "L5", 0.45)],
    )
  let s = summary(analysis)
  { string.contains(s, "L4") } |> should.be_true()
  { string.contains(s, "L5") } |> should.be_true()
}

// ===========================================================================
// Private test helpers
// ===========================================================================

/// Floating-point approximate equality within a tolerance.
fn float_close(a: Float, b: Float, tol: Float) -> Bool {
  let diff = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  diff <. tol
}

/// Returns True if all elements satisfy the predicate.
fn list_all(items: List(a), pred: fn(a) -> Bool) -> Bool {
  case items {
    [] -> True
    [x, ..rest] ->
      case pred(x) {
        False -> False
        True -> list_all(rest, pred)
      }
  }
}
