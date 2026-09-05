//// =============================================================================
//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/testing/coverage_math</module>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////     <mesh-domain>Mathematical Coverage Framework</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6</criticality>
////     <stamp-controls>SC-MATH-COV-001 to SC-MATH-COV-008</stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// Mathematical coverage framework for Gleam UI tests.
//// All formulas are pure functions operating on test file metadata.
//// STAMP: SC-MATH-COV-001..008

import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/result

// =============================================================================
// External FFI for logarithm  (Erlang math module — no stdlib wrapper)
// =============================================================================

@external(erlang, "math", "log")
fn math_log(x: Float) -> Float

fn ln2() -> Float {
  math_log(2.0)
}

fn log2(x: Float) -> Float {
  float.divide(math_log(x), ln2())
  |> result.unwrap(0.0)
}

// =============================================================================
// Type Definitions
// =============================================================================

/// Test file priority classification.
/// P0 = safety-critical, P1 = core, P2 = domain, P3 = style.
pub type Priority {
  P0
  P1
  P2
  P3
}

/// ITQS score grade derived from the computed score.
pub type Grade {
  GradeA
  GradeB
  GradeC
  GradeD
}

/// Per-file coverage metadata.
/// c1..c8 represent the number of implemented features in each
/// of the eight coverage categories.
pub type FileCoverage {
  FileCoverage(
    file_name: String,
    page: String,
    priority: Priority,
    c1: Int,
    c2: Int,
    c3: Int,
    c4: Int,
    c5: Int,
    c6: Int,
    c7: Int,
    c8: Int,
    applicable_categories: List(String),
    expected_elements: Int,
    implemented_elements: Int,
  )
}

// =============================================================================
// Public API
// =============================================================================

/// Shannon entropy H = -sum(p_i * log2(p_i)) across the eight coverage
/// category proportions.  Returns 0.0 for a zero-feature file.
/// STAMP: SC-MATH-COV-001
pub fn shannon_entropy(cov: FileCoverage) -> Float {
  let total = int.to_float(total_features(cov))
  case float.compare(total, 0.0) {
    order.Gt -> {
      let counts = [
        cov.c1, cov.c2, cov.c3, cov.c4, cov.c5, cov.c6, cov.c7, cov.c8,
      ]
      let probs =
        list.map(counts, fn(c) {
          float.divide(int.to_float(c), total)
          |> result.unwrap(0.0)
        })
      probs
      |> list.filter(fn(p) {
        case float.compare(p, 0.0) {
          order.Gt -> True
          _ -> False
        }
      })
      |> list.fold(0.0, fn(acc, p) {
        float.add(acc, float.negate(float.multiply(p, log2(p))))
      })
    }
    _ -> 0.0
  }
}

/// Normalised Shannon entropy H_norm = H / 3.0 (max entropy for 8 categories
/// is log2(8) = 3.0 bits).
/// STAMP: SC-MATH-COV-002
pub fn shannon_entropy_normalized(cov: FileCoverage) -> Float {
  float.divide(shannon_entropy(cov), 3.0)
  |> result.unwrap(0.0)
}

/// Composite Coverage Metric — calibrated weighted average measuring each
/// category against its P0 minimum requirement.
/// CCM = sum(w_i * min(c_i / min_i, 1.0)) / sum(w_i)
/// When all categories meet their P0 minimums, CCM = 1.0.
/// Returns 0.0 when there are no features at all.
/// STAMP: SC-MATH-COV-003
pub fn ccm(cov: FileCoverage) -> Float {
  let weights = list.map(category_weights(), fn(w) { w.1 })
  let mins = list.map(p0_minimums(), fn(m) { m.1 })
  let counts = [cov.c1, cov.c2, cov.c3, cov.c4, cov.c5, cov.c6, cov.c7, cov.c8]
  let total = int.to_float(total_features(cov))

  case float.compare(total, 0.0) {
    order.Gt -> {
      // Pair each (count, weight, min_required) together
      let triples = list.zip(counts, list.zip(weights, mins))

      let weight_sum =
        list.fold(triples, 0.0, fn(acc, t) { float.add(acc, t.1.0) })

      case float.compare(weight_sum, 0.0) {
        order.Gt -> {
          let weighted_sum =
            list.fold(triples, 0.0, fn(acc, t) {
              let #(count, #(w, min_req)) = t
              let ratio =
                float.divide(int.to_float(count), int.to_float(min_req))
                |> result.unwrap(0.0)
              let capped = float.clamp(ratio, min: 0.0, max: 1.0)
              float.add(acc, float.multiply(w, capped))
            })
          float.divide(weighted_sum, weight_sum)
          |> result.unwrap(0.0)
        }
        _ -> 0.0
      }
    }
    _ -> 0.0
  }
}

/// Raw CCM — original proportion-based formula (kept for backwards
/// compatibility and audit purposes).
/// CCM_raw = sum(w_i * (c_i / total)) / sum(w_i)
/// STAMP: SC-MATH-COV-003
pub fn ccm_raw(cov: FileCoverage) -> Float {
  let weights = category_weights()
  let counts = [cov.c1, cov.c2, cov.c3, cov.c4, cov.c5, cov.c6, cov.c7, cov.c8]
  let total = int.to_float(total_features(cov))

  let paired = list.zip(counts, list.map(weights, fn(w) { w.1 }))

  let weight_sum =
    list.fold(paired, 0.0, fn(acc, pair) { float.add(acc, pair.1) })

  case
    float.compare(total, 0.0) == order.Gt
    && float.compare(weight_sum, 0.0) == order.Gt
  {
    True -> {
      let weighted_sum =
        list.fold(paired, 0.0, fn(acc, pair) {
          let #(count, w) = pair
          let proportion =
            float.divide(int.to_float(count), total)
            |> result.unwrap(0.0)
          float.add(acc, float.multiply(w, proportion))
        })
      float.divide(weighted_sum, weight_sum)
      |> result.unwrap(0.0)
    }
    False -> 0.0
  }
}

/// Element-level divergence D_EA = |expected \ tested| / |expected|.
/// Measures the fraction of expected elements not yet tested.
/// Returns 0.0 when expected_elements is zero (no divergence).
/// STAMP: SC-MATH-COV-004
pub fn divergence(cov: FileCoverage) -> Float {
  case cov.expected_elements > 0 {
    True -> {
      let missing = cov.expected_elements - cov.implemented_elements
      let missing_clamped = case missing < 0 {
        True -> 0
        False -> missing
      }
      float.divide(
        int.to_float(missing_clamped),
        int.to_float(cov.expected_elements),
      )
      |> result.unwrap(0.0)
    }
    False -> 0.0
  }
}

/// Fleet Stability Index — measures how uniform entropy is across the suite.
/// FSI = 1 - (stddev(H) / mean(H)).
/// Returns 1.0 (perfect stability) for a single-file suite or zero-mean.
/// STAMP: SC-MATH-COV-005
pub fn fsi(coverages: List(FileCoverage)) -> Float {
  let entropies = list.map(coverages, shannon_entropy)
  let mu = mean(entropies)
  case float.compare(mu, 0.0) {
    order.Gt -> {
      let sigma = stddev(entropies)
      let ratio =
        float.divide(sigma, mu)
        |> result.unwrap(0.0)
      float.clamp(1.0 -. ratio, min: 0.0, max: 1.0)
    }
    _ -> 1.0
  }
}

/// Integrated Test Quality Score.
/// ITQS = 0.25 * H_norm + 0.35 * CCM + 0.25 * (1 - D_EA) + 0.15 * FSI
/// STAMP: SC-MATH-COV-006
pub fn itqs(cov: FileCoverage, suite_fsi: Float) -> Float {
  let h_norm = shannon_entropy_normalized(cov)
  let ccm_score = ccm(cov)
  let d_ea = divergence(cov)
  let coverage_term = float.clamp(1.0 -. d_ea, min: 0.0, max: 1.0)

  let score =
    float.add(
      float.multiply(0.25, h_norm),
      float.add(
        float.multiply(0.35, ccm_score),
        float.add(
          float.multiply(0.25, coverage_term),
          float.multiply(0.15, suite_fsi),
        ),
      ),
    )

  float.clamp(score, min: 0.0, max: 1.0)
}

/// Convert an ITQS score to a letter grade.
/// A >= 0.90, B >= 0.85, C >= 0.75, D < 0.75
/// STAMP: SC-MATH-COV-007
pub fn itqs_grade(score: Float) -> Grade {
  case score >=. 0.9 {
    True -> GradeA
    False ->
      case score >=. 0.85 {
        True -> GradeB
        False ->
          case score >=. 0.75 {
            True -> GradeC
            False -> GradeD
          }
      }
  }
}

/// Total feature count across all eight categories.
pub fn total_features(cov: FileCoverage) -> Int {
  cov.c1 + cov.c2 + cov.c3 + cov.c4 + cov.c5 + cov.c6 + cov.c7 + cov.c8
}

/// Canonical weight vector for the eight coverage categories.
/// C1 = 1.0 (basic rendering), increasing to C8 = 3.0 (error handling).
/// STAMP: SC-MATH-COV-008
pub fn category_weights() -> List(#(String, Float)) {
  [
    #("C1_Rendering", 1.0),
    #("C2_Interaction", 1.5),
    #("C3_StateManagement", 2.0),
    #("C4_RealTimeUpdates", 2.0),
    #("C5_Navigation", 1.5),
    #("C6_Accessibility", 2.5),
    #("C7_Performance", 2.5),
    #("C8_ErrorHandling", 3.0),
  ]
}

/// Minimum feature count per category for P0 files.
/// Returns a list of (category_name, minimum_required) pairs.
pub fn p0_minimums() -> List(#(String, Int)) {
  [
    #("C1_Rendering", 3),
    #("C2_Interaction", 3),
    #("C3_StateManagement", 2),
    #("C4_RealTimeUpdates", 2),
    #("C5_Navigation", 2),
    #("C6_Accessibility", 3),
    #("C7_Performance", 2),
    #("C8_ErrorHandling", 3),
  ]
}

// =============================================================================
// Enhanced Coverage Functions (Batch 5: CCM >= 0.90, ITQS >= 0.85)
// =============================================================================

/// Compute per-element KPI for a list of file coverages.
/// Returns (file_name, ccm, itqs, d_ea, grade) tuples.
pub fn per_element_kpi(
  coverages: List(FileCoverage),
) -> List(#(String, Float, Float, Float, Grade)) {
  let suite_fsi = fsi(coverages)
  list.map(coverages, fn(cov) {
    let ccm_val = ccm(cov)
    let itqs_val = itqs(cov, suite_fsi)
    let d_ea = divergence(cov)
    let grade = itqs_grade(itqs_val)
    #(cov.file_name, ccm_val, itqs_val, d_ea, grade)
  })
}

/// Identify which elements need category improvements to reach target CCM.
/// Returns (file_name, category_name, gap) tuples.
pub fn corrective_actions_for_ccm_gap(
  coverages: List(FileCoverage),
  target: Float,
) -> List(#(String, String, Float)) {
  list.flat_map(coverages, fn(cov) {
    let current_ccm = ccm(cov)
    case current_ccm <. target {
      True -> {
        let gap = target -. current_ccm
        [#(cov.file_name, "C8_ErrorHandling", gap)]
      }
      False -> []
    }
  })
}

/// Compute weighted suite-level CCM across all file coverages.
pub fn weighted_suite_ccm(coverages: List(FileCoverage)) -> Float {
  case coverages {
    [] -> 0.0
    _ -> {
      let ccms = list.map(coverages, ccm)
      let total = list.fold(ccms, 0.0, float.add)
      float.divide(total, int.to_float(list.length(ccms)))
      |> result.unwrap(0.0)
    }
  }
}

// =============================================================================
// Private helpers
// =============================================================================

fn mean(values: List(Float)) -> Float {
  case values {
    [] -> 0.0
    _ -> {
      let n = int.to_float(list.length(values))
      let total = list.fold(values, 0.0, float.add)
      float.divide(total, n)
      |> result.unwrap(0.0)
    }
  }
}

fn stddev(values: List(Float)) -> Float {
  case values {
    [] -> 0.0
    [_] -> 0.0
    _ -> {
      let mu = mean(values)
      let n = int.to_float(list.length(values))
      let variance =
        list.fold(values, 0.0, fn(acc, x) {
          let diff = x -. mu
          float.add(acc, float.multiply(diff, diff))
        })
      let variance_mean =
        float.divide(variance, n)
        |> result.unwrap(0.0)
      float.square_root(variance_mean)
      |> result.unwrap(0.0)
    }
  }
}
