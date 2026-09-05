//// =============================================================================
//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/testing/alignment</module>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>Human Intent Alignment Verification</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6</criticality>
////     <stamp-controls>SC-HINT-001 to SC-HINT-008</stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// Human Intent alignment score computation.
//// Compares EXPECTED behaviors from Human-Specified Intent against
//// AS-IS behaviors from Lustre module source.
//// STAMP: SC-HINT-001..008

import gleam/float
import gleam/int
import gleam/order
import gleam/result
import gleam/set

// =============================================================================
// Type Definitions
// =============================================================================

/// Qualitative alignment classification derived from the numeric score.
/// Aligned  >= 0.9  — no action required
/// Drift    >= 0.7  — flag for human review
/// Misaligned < 0.7 — P1 alert, block agent modifications (SC-HINT-006)
pub type AlignmentStatus {
  Aligned
  Drift
  Misaligned
}

/// Complete alignment result for one page.
pub type AlignmentResult {
  AlignmentResult(
    page: String,
    score: Float,
    status: AlignmentStatus,
    expected_behaviors: List(String),
    implemented_behaviors: List(String),
    missing: List(String),
    undeclared: List(String),
  )
}

// =============================================================================
// Public API
// =============================================================================

/// Compute the alignment score between human-specified intent and implemented
/// behaviors, then package the full result.
///
/// Formula (Jaccard-style):
///   Alignment = |EXPECTED ∩ AS-IS| / |EXPECTED ∪ AS-IS|
///
/// Exact string matching is used here; callers may pre-normalise strings
/// (lower-case, trim) before passing them in.
///
/// STAMP: SC-HINT-003, SC-HINT-005
pub fn compute_alignment(
  page: String,
  expected: List(String),
  implemented: List(String),
) -> AlignmentResult {
  let expected_set = set.from_list(expected)
  let implemented_set = set.from_list(implemented)

  // intersection: behaviors present in both sets
  let intersection = set.intersection(of: expected_set, and: implemented_set)
  // union: all behaviors across both sets
  let union_set = set.union(of: expected_set, and: implemented_set)

  let intersection_size = int.to_float(set.size(intersection))
  let union_size = int.to_float(set.size(union_set))

  let score = case float.compare(union_size, 0.0) {
    // Empty sets are trivially aligned
    order.Eq -> 1.0
    _ ->
      float.divide(intersection_size, union_size)
      |> result.unwrap(0.0)
  }

  // missing: expected but not implemented
  let missing =
    set.difference(from: expected_set, minus: implemented_set)
    |> set.to_list

  // undeclared: implemented but not declared in human intent
  let undeclared =
    set.difference(from: implemented_set, minus: expected_set)
    |> set.to_list

  AlignmentResult(
    page: page,
    score: score,
    status: alignment_status(score),
    expected_behaviors: expected,
    implemented_behaviors: implemented,
    missing: missing,
    undeclared: undeclared,
  )
}

/// Classify a numeric alignment score into a status value.
/// >= 0.9  -> Aligned
/// >= 0.7  -> Drift
/// < 0.7   -> Misaligned  (triggers P1 alert per SC-HINT-006)
pub fn alignment_status(score: Float) -> AlignmentStatus {
  case score >=. 0.9 {
    True -> Aligned
    False ->
      case score >=. 0.7 {
        True -> Drift
        False -> Misaligned
      }
  }
}

/// Returns True when the alignment result meets the minimum compliance
/// threshold (score >= 0.7).  Misaligned results MUST block agent
/// modifications per SC-HINT-006.
pub fn is_compliant(result: AlignmentResult) -> Bool {
  result.score >=. 0.7
}
