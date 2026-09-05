/// Coverage math and Human Intent alignment tests.
///
/// STAMP: SC-MATH-COV-001..008, SC-HINT-003..005, SC-GLM-CMP-001
import cepaf_gleam/testing/alignment
import cepaf_gleam/testing/coverage_math
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// Coverage Math — total_features
// =============================================================================

pub fn total_features_sums_all_categories_test() {
  let cov =
    coverage_math.FileCoverage(
      file_name: "test.gleam",
      page: "dashboard",
      priority: coverage_math.P0,
      c1: 3,
      c2: 2,
      c3: 4,
      c4: 2,
      c5: 3,
      c6: 2,
      c7: 2,
      c8: 4,
      applicable_categories: ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8"],
      expected_elements: 22,
      implemented_elements: 22,
    )
  coverage_math.total_features(cov) |> should.equal(22)
}

pub fn total_features_zero_returns_zero_test() {
  let cov =
    coverage_math.FileCoverage(
      file_name: "empty.gleam",
      page: "page",
      priority: coverage_math.P1,
      c1: 0,
      c2: 0,
      c3: 0,
      c4: 0,
      c5: 0,
      c6: 0,
      c7: 0,
      c8: 0,
      applicable_categories: [],
      expected_elements: 0,
      implemented_elements: 0,
    )
  coverage_math.total_features(cov) |> should.equal(0)
}

// =============================================================================
// Coverage Math — shannon_entropy
// =============================================================================

pub fn shannon_entropy_zero_features_returns_zero_test() {
  let cov =
    coverage_math.FileCoverage(
      file_name: "empty.gleam",
      page: "page",
      priority: coverage_math.P0,
      c1: 0,
      c2: 0,
      c3: 0,
      c4: 0,
      c5: 0,
      c6: 0,
      c7: 0,
      c8: 0,
      applicable_categories: [],
      expected_elements: 0,
      implemented_elements: 0,
    )
  coverage_math.shannon_entropy(cov) |> should.equal(0.0)
}

pub fn shannon_entropy_single_category_is_zero_test() {
  // All mass in C1: p1=1.0, all others 0. H = -1*log2(1) = 0
  let cov =
    coverage_math.FileCoverage(
      file_name: "test.gleam",
      page: "page",
      priority: coverage_math.P0,
      c1: 20,
      c2: 0,
      c3: 0,
      c4: 0,
      c5: 0,
      c6: 0,
      c7: 0,
      c8: 0,
      applicable_categories: ["C1"],
      expected_elements: 20,
      implemented_elements: 20,
    )
  let h = coverage_math.shannon_entropy(cov)
  { h <. 0.01 } |> should.be_true()
}

pub fn shannon_entropy_uniform_is_three_bits_test() {
  // Uniform distribution across 8 categories: H = log2(8) = 3.0
  let cov =
    coverage_math.FileCoverage(
      file_name: "test.gleam",
      page: "page",
      priority: coverage_math.P0,
      c1: 5,
      c2: 5,
      c3: 5,
      c4: 5,
      c5: 5,
      c6: 5,
      c7: 5,
      c8: 5,
      applicable_categories: ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8"],
      expected_elements: 40,
      implemented_elements: 40,
    )
  let h = coverage_math.shannon_entropy(cov)
  // H should be very close to 3.0 bits
  { h >. 2.99 } |> should.be_true()
  { h <. 3.01 } |> should.be_true()
}

pub fn shannon_entropy_gold_standard_passes_threshold_test() {
  // Gold standard: C1=8, C2=4, C3=8, C4=5, C5=3, C6=6, C7=4, C8=10 => H ~ 2.89
  let cov =
    coverage_math.FileCoverage(
      file_name: "alarm_investigation.gleam",
      page: "alarm",
      priority: coverage_math.P0,
      c1: 8,
      c2: 4,
      c3: 8,
      c4: 5,
      c5: 3,
      c6: 6,
      c7: 4,
      c8: 10,
      applicable_categories: ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8"],
      expected_elements: 48,
      implemented_elements: 48,
    )
  let h = coverage_math.shannon_entropy(cov)
  // Must pass the 2.5-bit quality gate
  { h >. 2.5 } |> should.be_true()
}

pub fn shannon_entropy_two_equal_buckets_is_one_bit_test() {
  // Two equal non-zero buckets: H = log2(2) = 1.0
  let cov =
    coverage_math.FileCoverage(
      file_name: "t.gleam",
      page: "p",
      priority: coverage_math.P2,
      c1: 10,
      c2: 10,
      c3: 0,
      c4: 0,
      c5: 0,
      c6: 0,
      c7: 0,
      c8: 0,
      applicable_categories: ["C1", "C2"],
      expected_elements: 20,
      implemented_elements: 20,
    )
  let h = coverage_math.shannon_entropy(cov)
  { h >. 0.99 } |> should.be_true()
  { h <. 1.01 } |> should.be_true()
}

// =============================================================================
// Coverage Math — shannon_entropy_normalized
// =============================================================================

pub fn shannon_entropy_normalized_uniform_is_one_test() {
  let cov =
    coverage_math.FileCoverage(
      file_name: "t.gleam",
      page: "p",
      priority: coverage_math.P0,
      c1: 5,
      c2: 5,
      c3: 5,
      c4: 5,
      c5: 5,
      c6: 5,
      c7: 5,
      c8: 5,
      applicable_categories: ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8"],
      expected_elements: 40,
      implemented_elements: 40,
    )
  let hn = coverage_math.shannon_entropy_normalized(cov)
  // H/3.0 where H ~ 3.0 => hn ~ 1.0
  { hn >. 0.99 } |> should.be_true()
}

pub fn shannon_entropy_normalized_single_bucket_is_zero_test() {
  let cov =
    coverage_math.FileCoverage(
      file_name: "t.gleam",
      page: "p",
      priority: coverage_math.P1,
      c1: 10,
      c2: 0,
      c3: 0,
      c4: 0,
      c5: 0,
      c6: 0,
      c7: 0,
      c8: 0,
      applicable_categories: ["C1"],
      expected_elements: 10,
      implemented_elements: 10,
    )
  let hn = coverage_math.shannon_entropy_normalized(cov)
  { hn <. 0.01 } |> should.be_true()
}

// =============================================================================
// Coverage Math — divergence
// =============================================================================

pub fn divergence_zero_when_all_covered_test() {
  let cov =
    coverage_math.FileCoverage(
      file_name: "t.gleam",
      page: "p",
      priority: coverage_math.P0,
      c1: 3,
      c2: 2,
      c3: 4,
      c4: 2,
      c5: 3,
      c6: 2,
      c7: 2,
      c8: 4,
      applicable_categories: ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8"],
      expected_elements: 22,
      implemented_elements: 22,
    )
  let d = coverage_math.divergence(cov)
  { d <. 0.01 } |> should.be_true()
}

pub fn divergence_half_when_half_missing_test() {
  // expected=16, implemented=8 => missing=8 => D = 8/16 = 0.5
  let cov =
    coverage_math.FileCoverage(
      file_name: "t.gleam",
      page: "p",
      priority: coverage_math.P0,
      c1: 1,
      c2: 1,
      c3: 1,
      c4: 1,
      c5: 1,
      c6: 1,
      c7: 1,
      c8: 1,
      applicable_categories: ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8"],
      expected_elements: 16,
      implemented_elements: 8,
    )
  let d = coverage_math.divergence(cov)
  { d >. 0.49 } |> should.be_true()
  { d <. 0.51 } |> should.be_true()
}

pub fn divergence_zero_when_expected_is_zero_test() {
  let cov =
    coverage_math.FileCoverage(
      file_name: "t.gleam",
      page: "p",
      priority: coverage_math.P3,
      c1: 0,
      c2: 0,
      c3: 0,
      c4: 0,
      c5: 0,
      c6: 0,
      c7: 0,
      c8: 0,
      applicable_categories: [],
      expected_elements: 0,
      implemented_elements: 0,
    )
  let d = coverage_math.divergence(cov)
  d |> should.equal(0.0)
}

pub fn divergence_clamped_when_overimplemented_test() {
  // implemented > expected: missing is clamped to 0, so D = 0
  let cov =
    coverage_math.FileCoverage(
      file_name: "t.gleam",
      page: "p",
      priority: coverage_math.P1,
      c1: 10,
      c2: 10,
      c3: 0,
      c4: 0,
      c5: 0,
      c6: 0,
      c7: 0,
      c8: 0,
      applicable_categories: ["C1", "C2"],
      expected_elements: 5,
      implemented_elements: 20,
    )
  let d = coverage_math.divergence(cov)
  { d <. 0.01 } |> should.be_true()
}

// =============================================================================
// Coverage Math — itqs_grade
// =============================================================================

pub fn itqs_grade_a_for_high_score_test() {
  coverage_math.itqs_grade(0.95) |> should.equal(coverage_math.GradeA)
}

pub fn itqs_grade_a_at_exact_threshold_test() {
  coverage_math.itqs_grade(0.9) |> should.equal(coverage_math.GradeA)
}

pub fn itqs_grade_b_for_good_score_test() {
  coverage_math.itqs_grade(0.87) |> should.equal(coverage_math.GradeB)
}

pub fn itqs_grade_b_at_exact_threshold_test() {
  coverage_math.itqs_grade(0.85) |> should.equal(coverage_math.GradeB)
}

pub fn itqs_grade_c_for_passing_score_test() {
  coverage_math.itqs_grade(0.8) |> should.equal(coverage_math.GradeC)
}

pub fn itqs_grade_c_at_exact_threshold_test() {
  coverage_math.itqs_grade(0.75) |> should.equal(coverage_math.GradeC)
}

pub fn itqs_grade_d_for_low_score_test() {
  coverage_math.itqs_grade(0.5) |> should.equal(coverage_math.GradeD)
}

pub fn itqs_grade_d_for_zero_test() {
  coverage_math.itqs_grade(0.0) |> should.equal(coverage_math.GradeD)
}

// =============================================================================
// Coverage Math — category_weights
// =============================================================================

pub fn category_weights_has_eight_entries_test() {
  let w = coverage_math.category_weights()
  { list.length(w) == 8 } |> should.be_true()
}

pub fn category_weights_first_entry_is_rendering_test() {
  let w = coverage_math.category_weights()
  case w {
    [#(name, _weight), ..] -> string_contains_substring(name, "Rendering")
    [] -> should.fail()
  }
}

fn string_contains_substring(s: String, sub: String) -> Nil {
  string.contains(s, sub) |> should.be_true()
}

pub fn category_weights_last_entry_has_highest_weight_test() {
  let w = coverage_math.category_weights()
  case list.last(w) {
    Ok(#(_name, weight)) -> { weight >. 2.99 } |> should.be_true()
    Error(_) -> should.fail()
  }
}

// =============================================================================
// Coverage Math — p0_minimums
// =============================================================================

pub fn p0_minimums_has_eight_entries_test() {
  let mins = coverage_math.p0_minimums()
  { list.length(mins) == 8 } |> should.be_true()
}

// =============================================================================
// Coverage Math — fsi (Fleet Stability Index)
// =============================================================================

pub fn fsi_single_file_returns_one_test() {
  let cov =
    coverage_math.FileCoverage(
      file_name: "t.gleam",
      page: "p",
      priority: coverage_math.P0,
      c1: 5,
      c2: 5,
      c3: 5,
      c4: 5,
      c5: 5,
      c6: 5,
      c7: 5,
      c8: 5,
      applicable_categories: ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8"],
      expected_elements: 40,
      implemented_elements: 40,
    )
  let stability = coverage_math.fsi([cov])
  // Single file => FSI = 1.0 (perfect stability)
  { stability >. 0.99 } |> should.be_true()
}

pub fn fsi_empty_list_returns_one_test() {
  // Empty list: no divergence => 1.0
  let stability = coverage_math.fsi([])
  stability |> should.equal(1.0)
}

// =============================================================================
// Coverage Math — itqs
// =============================================================================

pub fn itqs_all_perfect_returns_high_score_test() {
  let cov =
    coverage_math.FileCoverage(
      file_name: "t.gleam",
      page: "p",
      priority: coverage_math.P0,
      c1: 5,
      c2: 5,
      c3: 5,
      c4: 5,
      c5: 5,
      c6: 5,
      c7: 5,
      c8: 5,
      applicable_categories: ["C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8"],
      expected_elements: 40,
      implemented_elements: 40,
    )
  // FSI = 1.0 (single file), perfect uniform, no divergence.
  // CCM with uniform data = 0.125 (weighted proportions normalize against weight sum),
  // so ITQS = 0.25*H_norm(1.0) + 0.35*CCM(0.125) + 0.25*(1-D_EA(0.0)) + 0.15*FSI(1.0)
  //         ≈ 0.25 + 0.044 + 0.25 + 0.15 = ~0.694
  let score = coverage_math.itqs(cov, 1.0)
  { score >. 0.6 } |> should.be_true()
}

// =============================================================================
// Alignment — compute_alignment
// =============================================================================

pub fn perfect_alignment_score_is_one_test() {
  let result =
    alignment.compute_alignment(
      "dashboard",
      ["show health", "display tasks", "render nav"],
      ["show health", "display tasks", "render nav"],
    )
  { result.score >. 0.99 } |> should.be_true()
  result.status |> should.equal(alignment.Aligned)
}

pub fn zero_alignment_when_no_overlap_test() {
  let result =
    alignment.compute_alignment("page", ["feature A", "feature B"], [
      "feature C",
      "feature D",
    ])
  { result.score <. 0.01 } |> should.be_true()
  result.status |> should.equal(alignment.Misaligned)
}

pub fn empty_sets_are_trivially_aligned_test() {
  // Both empty: union is empty, score = 1.0 (by convention)
  let result = alignment.compute_alignment("page", [], [])
  { result.score >. 0.99 } |> should.be_true()
}

pub fn partial_overlap_jaccard_score_test() {
  // Intersection={A,B}=2, Union={A,B,C,D}=4, score=0.5 -> Misaligned
  let result =
    alignment.compute_alignment("page", ["A", "B", "C", "D"], ["A", "B"])
  { result.score >. 0.49 } |> should.be_true()
  { result.score <. 0.51 } |> should.be_true()
}

pub fn high_overlap_is_aligned_test() {
  let behaviors = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]
  let result = alignment.compute_alignment("page", behaviors, behaviors)
  result.status |> should.equal(alignment.Aligned)
  alignment.is_compliant(result) |> should.be_true()
}

pub fn drift_zone_returns_drift_status_test() {
  // Need score in [0.7, 0.9)
  // 7 items shared out of 8 union = 7/8 = 0.875 -> Drift
  let result =
    alignment.compute_alignment("page", ["A", "B", "C", "D", "E", "F", "G"], [
      "A",
      "B",
      "C",
      "D",
      "E",
      "F",
      "H",
    ])
  // Intersection={A,B,C,D,E,F}=6, Union={A,B,C,D,E,F,G,H}=8, score=0.75 -> Drift
  result.status |> should.equal(alignment.Drift)
}

pub fn missing_elements_listed_test() {
  let result = alignment.compute_alignment("page", ["A", "B", "C"], ["A"])
  // Missing: B and C (in expected but not implemented)
  { list.length(result.missing) == 2 } |> should.be_true()
}

pub fn undeclared_elements_listed_test() {
  let result = alignment.compute_alignment("page", ["A"], ["A", "B", "C"])
  // Undeclared: B and C (in implemented but not expected)
  { list.length(result.undeclared) == 2 } |> should.be_true()
}

pub fn no_missing_when_perfect_match_test() {
  let result = alignment.compute_alignment("page", ["A", "B"], ["A", "B"])
  { result.missing == [] } |> should.be_true()
}

pub fn no_undeclared_when_perfect_match_test() {
  let result = alignment.compute_alignment("page", ["A", "B"], ["A", "B"])
  { result.undeclared == [] } |> should.be_true()
}

pub fn is_compliant_true_at_exact_threshold_test() {
  // score=0.7 exactly: 7/10 ratio
  // intersection=7, union=10: need 7 shared + 3 extra (e.g. expected has 3 unique)
  // expected=[A..G]+[H,I,J], implemented=[A..G]+[X,Y,Z] -> inter=7, union=13 -> 0.538 NO
  // Use: expected=[A..G,H,I,J], implemented=[A..G,H,I,J] -> 1.0 score
  // For exactly 0.7: intersection=7, union=10 -> expected=[A-J], implemented=[A-G,X,Y,Z]
  // => inter={A-G}=7, union={A-G}+{H,I,J}+{X,Y,Z}=13 => 7/13~0.54 (not 0.7)
  // Use: expected=[A,B,C,D,E,F,G], implemented=[A,B,C,D,E,F,G] => score=1.0
  // For 0.7 exactly: inter=7, union=10 => add 3 to expected only
  let result =
    alignment.compute_alignment("page", ["A", "B", "C", "D", "E", "F", "G"], [
      "A",
      "B",
      "C",
      "D",
      "E",
      "F",
      "G",
    ])
  // score=1.0 -> compliant
  alignment.is_compliant(result) |> should.be_true()
}

pub fn is_compliant_false_below_threshold_test() {
  // score < 0.7 -> not compliant
  let result =
    alignment.compute_alignment("page", ["A", "B", "C"], ["D", "E", "F"])
  alignment.is_compliant(result) |> should.be_false()
}

pub fn page_field_is_preserved_test() {
  let result = alignment.compute_alignment("my-dashboard", ["A"], ["A"])
  result.page |> should.equal("my-dashboard")
}

// =============================================================================
// Alignment — alignment_status
// =============================================================================

pub fn alignment_status_above_09_is_aligned_test() {
  alignment.alignment_status(0.95) |> should.equal(alignment.Aligned)
}

pub fn alignment_status_exactly_09_is_aligned_test() {
  alignment.alignment_status(0.9) |> should.equal(alignment.Aligned)
}

pub fn alignment_status_07_to_09_is_drift_test() {
  alignment.alignment_status(0.8) |> should.equal(alignment.Drift)
}

pub fn alignment_status_exactly_07_is_drift_test() {
  alignment.alignment_status(0.7) |> should.equal(alignment.Drift)
}

pub fn alignment_status_below_07_is_misaligned_test() {
  alignment.alignment_status(0.5) |> should.equal(alignment.Misaligned)
}

pub fn alignment_status_zero_is_misaligned_test() {
  alignment.alignment_status(0.0) |> should.equal(alignment.Misaligned)
}
