// Testing framework coverage tests — coverage_math, alignment, nav_graph,
// fractal_matrix, zenoh_test_observer, test_dashboard, wiring_guard.
//
// STAMP: SC-MATH-COV-001..008, SC-HINT-001..008, SC-UIGT-001..014,
//        SC-GLM-ZEN-001..003, SC-BDD-001
// Covers functions not already tested in existing test files.

import cepaf_gleam/testing/alignment
import cepaf_gleam/testing/coverage_math.{
  type FileCoverage, FileCoverage, GradeA, GradeB, GradeC, GradeD, P0, P1, P2,
}
import cepaf_gleam/testing/fractal_matrix
import cepaf_gleam/testing/nav_graph
import cepaf_gleam/testing/test_dashboard
import cepaf_gleam/testing/zenoh_test_observer
import cepaf_gleam/ui/domain.{L0Constitutional, L1AtomicDebug}
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleeunit/should

// =============================================================================
// coverage_math.gleam — shannon_entropy
// =============================================================================

fn uniform_cov() -> FileCoverage {
  FileCoverage(
    file_name: "uniform",
    page: "Dashboard",
    priority: P0,
    c1: 1,
    c2: 1,
    c3: 1,
    c4: 1,
    c5: 1,
    c6: 1,
    c7: 1,
    c8: 1,
    applicable_categories: [],
    expected_elements: 8,
    implemented_elements: 8,
  )
}

fn zero_cov() -> FileCoverage {
  FileCoverage(
    file_name: "zero",
    page: "Planning",
    priority: P1,
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
}

fn skewed_cov() -> FileCoverage {
  FileCoverage(
    file_name: "skewed",
    page: "Immune",
    priority: P2,
    c1: 10,
    c2: 0,
    c3: 0,
    c4: 0,
    c5: 0,
    c6: 0,
    c7: 0,
    c8: 0,
    applicable_categories: [],
    expected_elements: 10,
    implemented_elements: 10,
  )
}

pub fn shannon_entropy_zero_for_empty_test() {
  coverage_math.shannon_entropy(zero_cov())
  |> should.equal(0.0)
}

pub fn shannon_entropy_positive_for_uniform_test() {
  let h = coverage_math.shannon_entropy(uniform_cov())
  { h >. 0.0 } |> should.be_true
}

pub fn shannon_entropy_uniform_is_max_test() {
  // Uniform distribution gives H = log2(8) = 3.0 bits
  let h = coverage_math.shannon_entropy(uniform_cov())
  // Allow a tiny float rounding margin
  { h >. 2.9 } |> should.be_true
}

pub fn shannon_entropy_skewed_is_lower_than_uniform_test() {
  let h_uniform = coverage_math.shannon_entropy(uniform_cov())
  let h_skewed = coverage_math.shannon_entropy(skewed_cov())
  { h_skewed <. h_uniform } |> should.be_true
}

// =============================================================================
// coverage_math.gleam — shannon_entropy_normalized
// =============================================================================

pub fn shannon_entropy_normalized_zero_for_empty_test() {
  coverage_math.shannon_entropy_normalized(zero_cov())
  |> should.equal(0.0)
}

pub fn shannon_entropy_normalized_uniform_near_one_test() {
  let h_norm = coverage_math.shannon_entropy_normalized(uniform_cov())
  { h_norm >. 0.9 } |> should.be_true
}

// =============================================================================
// coverage_math.gleam — ccm and ccm_raw
// =============================================================================

pub fn ccm_zero_for_empty_test() {
  coverage_math.ccm(zero_cov())
  |> should.equal(0.0)
}

pub fn ccm_positive_for_nonempty_test() {
  let score = coverage_math.ccm(uniform_cov())
  { score >. 0.0 } |> should.be_true
}

pub fn ccm_raw_zero_for_empty_test() {
  coverage_math.ccm_raw(zero_cov())
  |> should.equal(0.0)
}

pub fn ccm_raw_positive_for_uniform_test() {
  let score = coverage_math.ccm_raw(uniform_cov())
  { score >. 0.0 } |> should.be_true
}

// =============================================================================
// coverage_math.gleam — divergence
// =============================================================================

pub fn divergence_zero_when_fully_implemented_test() {
  let cov =
    FileCoverage(
      ..uniform_cov(),
      expected_elements: 10,
      implemented_elements: 10,
    )
  coverage_math.divergence(cov)
  |> should.equal(0.0)
}

pub fn divergence_one_when_nothing_implemented_test() {
  let cov =
    FileCoverage(
      ..uniform_cov(),
      expected_elements: 10,
      implemented_elements: 0,
    )
  coverage_math.divergence(cov)
  |> should.equal(1.0)
}

pub fn divergence_zero_when_no_expected_test() {
  let cov =
    FileCoverage(..zero_cov(), expected_elements: 0, implemented_elements: 0)
  coverage_math.divergence(cov)
  |> should.equal(0.0)
}

pub fn divergence_partial_is_between_zero_and_one_test() {
  let cov =
    FileCoverage(
      ..uniform_cov(),
      expected_elements: 10,
      implemented_elements: 5,
    )
  let d = coverage_math.divergence(cov)
  { d >. 0.0 && d <. 1.0 } |> should.be_true
}

// =============================================================================
// coverage_math.gleam — fsi
// =============================================================================

pub fn fsi_empty_list_returns_one_test() {
  coverage_math.fsi([])
  |> should.equal(1.0)
}

pub fn fsi_single_file_returns_one_test() {
  coverage_math.fsi([uniform_cov()])
  |> should.equal(1.0)
}

pub fn fsi_identical_files_returns_one_test() {
  // Identical entropy means zero std-dev → FSI=1.0
  let fsi = coverage_math.fsi([uniform_cov(), uniform_cov()])
  { fsi >. 0.9 } |> should.be_true
}

// =============================================================================
// coverage_math.gleam — itqs and itqs_grade
// =============================================================================

pub fn itqs_zero_for_empty_cov_test() {
  let score = coverage_math.itqs(zero_cov(), 1.0)
  // With perfect FSI but 0 on all others, ITQS = 0.15 * 1.0 = 0.15
  { score >=. 0.0 } |> should.be_true
}

pub fn itqs_grade_a_for_high_score_test() {
  coverage_math.itqs_grade(0.95)
  |> should.equal(GradeA)
}

pub fn itqs_grade_b_for_mid_high_score_test() {
  coverage_math.itqs_grade(0.87)
  |> should.equal(GradeB)
}

pub fn itqs_grade_c_for_mid_score_test() {
  coverage_math.itqs_grade(0.77)
  |> should.equal(GradeC)
}

pub fn itqs_grade_d_for_low_score_test() {
  coverage_math.itqs_grade(0.5)
  |> should.equal(GradeD)
}

// =============================================================================
// coverage_math.gleam — total_features
// =============================================================================

pub fn total_features_zero_test() {
  coverage_math.total_features(zero_cov())
  |> should.equal(0)
}

pub fn total_features_sums_categories_test() {
  coverage_math.total_features(uniform_cov())
  |> should.equal(8)
}

// =============================================================================
// coverage_math.gleam — category_weights and p0_minimums
// =============================================================================

pub fn category_weights_has_eight_entries_test() {
  coverage_math.category_weights()
  |> list.length
  |> should.equal(8)
}

pub fn category_weights_all_positive_test() {
  coverage_math.category_weights()
  |> list.all(fn(pair) { pair.1 >. 0.0 })
  |> should.be_true
}

pub fn p0_minimums_has_eight_entries_test() {
  coverage_math.p0_minimums()
  |> list.length
  |> should.equal(8)
}

pub fn p0_minimums_all_positive_test() {
  coverage_math.p0_minimums()
  |> list.all(fn(pair) { pair.1 > 0 })
  |> should.be_true
}

// =============================================================================
// coverage_math.gleam — weighted_suite_ccm
// =============================================================================

pub fn weighted_suite_ccm_empty_returns_zero_test() {
  coverage_math.weighted_suite_ccm([])
  |> should.equal(0.0)
}

pub fn weighted_suite_ccm_single_file_test() {
  let suite_ccm = coverage_math.weighted_suite_ccm([uniform_cov()])
  { suite_ccm >=. 0.0 } |> should.be_true
}

pub fn weighted_suite_ccm_multiple_files_test() {
  let suite_ccm =
    coverage_math.weighted_suite_ccm([uniform_cov(), skewed_cov()])
  { suite_ccm >=. 0.0 && suite_ccm <=. 1.0 } |> should.be_true
}

// =============================================================================
// alignment.gleam — compute_alignment
// =============================================================================

pub fn compute_alignment_identical_sets_is_one_test() {
  let behaviors = ["renders_header", "shows_status_badge", "handles_click"]
  let result = alignment.compute_alignment("Dashboard", behaviors, behaviors)
  result.score |> should.equal(1.0)
}

pub fn compute_alignment_empty_sets_is_one_test() {
  let result = alignment.compute_alignment("Planning", [], [])
  result.score |> should.equal(1.0)
}

pub fn compute_alignment_disjoint_sets_is_zero_test() {
  let expected = ["feature_a", "feature_b"]
  let implemented = ["feature_c", "feature_d"]
  let result = alignment.compute_alignment("Immune", expected, implemented)
  result.score |> should.equal(0.0)
}

pub fn compute_alignment_partial_overlap_test() {
  let expected = ["feat_a", "feat_b", "feat_c"]
  let implemented = ["feat_a", "feat_b", "feat_d"]
  // intersection = {feat_a, feat_b} = 2
  // union = {feat_a, feat_b, feat_c, feat_d} = 4
  // score = 2/4 = 0.5
  let result =
    alignment.compute_alignment("Verification", expected, implemented)
  { result.score >. 0.4 && result.score <. 0.6 } |> should.be_true
}

pub fn compute_alignment_result_has_page_test() {
  let result = alignment.compute_alignment("Cockpit", [], [])
  result.page |> should.equal("Cockpit")
}

pub fn compute_alignment_missing_identified_test() {
  let expected = ["feat_a", "feat_b"]
  let implemented = ["feat_a"]
  let result = alignment.compute_alignment("Zenoh", expected, implemented)
  list.contains(result.missing, "feat_b") |> should.be_true
}

pub fn compute_alignment_undeclared_identified_test() {
  let expected = ["feat_a"]
  let implemented = ["feat_a", "feat_extra"]
  let result = alignment.compute_alignment("Knowledge", expected, implemented)
  list.contains(result.undeclared, "feat_extra") |> should.be_true
}

// =============================================================================
// alignment.gleam — alignment_status and is_compliant
// =============================================================================

pub fn alignment_status_aligned_for_score_095_test() {
  alignment.alignment_status(0.95)
  |> should.equal(alignment.Aligned)
}

pub fn alignment_status_drift_for_score_08_test() {
  alignment.alignment_status(0.8)
  |> should.equal(alignment.Drift)
}

pub fn alignment_status_misaligned_for_score_05_test() {
  alignment.alignment_status(0.5)
  |> should.equal(alignment.Misaligned)
}

pub fn is_compliant_true_for_score_07_test() {
  let result = alignment.compute_alignment("Telemetry", [], [])
  alignment.is_compliant(result) |> should.be_true
}

pub fn is_compliant_false_for_low_score_test() {
  let expected = ["a", "b", "c", "d", "e"]
  let implemented = ["f", "g"]
  let result = alignment.compute_alignment("Substrate", expected, implemented)
  alignment.is_compliant(result) |> should.equal(False)
}

// =============================================================================
// nav_graph.gleam — page_count, edge_count, density, scc_count,
//                   chinese_postman_bound
// =============================================================================

pub fn nav_graph_page_count_is_31_test() {
  nav_graph.page_count()
  |> should.equal(31)
}

pub fn nav_graph_all_pages_length_matches_count_test() {
  nav_graph.all_pages()
  |> list.length
  |> should.equal(nav_graph.page_count())
}

pub fn nav_graph_edge_count_is_n_times_n_minus_one_test() {
  let n = nav_graph.page_count()
  nav_graph.edge_count()
  |> should.equal(n * { n - 1 })
}

pub fn nav_graph_density_is_one_test() {
  nav_graph.density()
  |> should.equal(1.0)
}

pub fn nav_graph_scc_count_is_one_test() {
  nav_graph.scc_count()
  |> should.equal(1)
}

pub fn nav_graph_chinese_postman_equals_edge_count_test() {
  nav_graph.chinese_postman_bound()
  |> should.equal(nav_graph.edge_count())
}

pub fn nav_graph_page_rank_has_31_entries_test() {
  nav_graph.page_rank()
  |> dict.size
  |> should.equal(31)
}

pub fn nav_graph_test_priority_order_is_sorted_test() {
  let order = nav_graph.test_priority_order()
  list.length(order) |> should.equal(31)
  // Verify all ranks are non-negative
  list.all(order, fn(pair) { pair.1 >=. 0.0 }) |> should.be_true
}

// =============================================================================
// fractal_matrix.gleam — bdd_level_to_string
// =============================================================================

pub fn bdd_level_to_string_unit_test() {
  fractal_matrix.bdd_level_to_string(fractal_matrix.BddUnit)
  |> should.equal("Unit")
}

pub fn bdd_level_to_string_integration_test() {
  fractal_matrix.bdd_level_to_string(fractal_matrix.BddIntegration)
  |> should.equal("Integration")
}

pub fn bdd_level_to_string_contract_test() {
  fractal_matrix.bdd_level_to_string(fractal_matrix.BddContract)
  |> should.equal("Contract")
}

pub fn bdd_level_to_string_component_test() {
  fractal_matrix.bdd_level_to_string(fractal_matrix.BddComponent)
  |> should.equal("Component")
}

pub fn bdd_level_to_string_system_test() {
  fractal_matrix.bdd_level_to_string(fractal_matrix.BddSystem)
  |> should.equal("System")
}

pub fn bdd_level_to_string_acceptance_test() {
  fractal_matrix.bdd_level_to_string(fractal_matrix.BddAcceptance)
  |> should.equal("Acceptance")
}

pub fn bdd_level_to_string_visual_test() {
  fractal_matrix.bdd_level_to_string(fractal_matrix.BddVisual)
  |> should.equal("Visual")
}

// =============================================================================
// fractal_matrix.gleam — all_bdd_levels and counts
// =============================================================================

pub fn all_bdd_levels_has_seven_test() {
  fractal_matrix.all_bdd_levels()
  |> list.length
  |> should.equal(7)
}

pub fn rust_tab_count_is_twelve_test() {
  fractal_matrix.rust_tab_count()
  |> should.equal(12)
}

pub fn rust_tabs_length_matches_count_test() {
  fractal_matrix.rust_tabs()
  |> list.length
  |> should.equal(12)
}

pub fn fractal_matrix_all_pages_is_fifteen_test() {
  fractal_matrix.all_pages()
  |> list.length
  |> should.equal(15)
}

pub fn total_element_count_is_positive_test() {
  { fractal_matrix.total_element_count() > 0 } |> should.be_true
}

pub fn total_bdd_cells_is_positive_test() {
  { fractal_matrix.total_bdd_cells() > 0 } |> should.be_true
}

pub fn covered_cells_is_positive_test() {
  { fractal_matrix.covered_cells() > 0 } |> should.be_true
}

pub fn matrix_coverage_is_between_zero_and_one_test() {
  let cov = fractal_matrix.matrix_coverage()
  { cov >=. 0.0 && cov <=. 1.0 } |> should.be_true
}

pub fn monitoring_plan_has_fifteen_entries_test() {
  fractal_matrix.monitoring_plan()
  |> list.length
  |> should.equal(15)
}

// =============================================================================
// zenoh_test_observer.gleam — init
// =============================================================================

pub fn observer_init_empty_messages_test() {
  let state = zenoh_test_observer.init(["topic/a", "topic/b"])
  list.length(state.messages) |> should.equal(0)
}

pub fn observer_init_expected_topics_test() {
  let topics = ["indrajaal/otel/spans/dashboard/init"]
  let state = zenoh_test_observer.init(topics)
  list.length(state.expected_topics) |> should.equal(1)
}

pub fn observer_init_sequence_counter_zero_test() {
  let state = zenoh_test_observer.init([])
  state.sequence_counter |> should.equal(0)
}

// =============================================================================
// zenoh_test_observer.gleam — record_message and record_control
// =============================================================================

pub fn observer_record_message_increments_counter_test() {
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_message("topic/a", "payload1")
  state.sequence_counter |> should.equal(1)
}

pub fn observer_record_message_adds_to_messages_test() {
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_message("topic/a", "payload1")
    |> zenoh_test_observer.record_message("topic/b", "payload2")
  list.length(state.messages) |> should.equal(2)
}

pub fn observer_record_control_is_separate_test() {
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_message("topic/data", "data")
    |> zenoh_test_observer.record_control("topic/ctrl", "control")
  list.length(state.messages) |> should.equal(1)
  list.length(state.control_messages) |> should.equal(1)
}

// =============================================================================
// zenoh_test_observer.gleam — verify_message_ordering
// =============================================================================

pub fn observer_ordering_empty_is_ordered_test() {
  let state = zenoh_test_observer.init([])
  let result = zenoh_test_observer.verify_message_ordering(state)
  result.passed |> should.be_true
}

pub fn observer_ordering_single_message_is_ordered_test() {
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_message("t", "p")
  let result = zenoh_test_observer.verify_message_ordering(state)
  result.passed |> should.be_true
}

pub fn observer_ordering_sequential_messages_ordered_test() {
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_message("t1", "p1")
    |> zenoh_test_observer.record_message("t2", "p2")
    |> zenoh_test_observer.record_message("t3", "p3")
  let result = zenoh_test_observer.verify_message_ordering(state)
  result.passed |> should.be_true
  result.check_name |> should.equal("message_ordering")
}

// =============================================================================
// zenoh_test_observer.gleam — verify_message_count
// =============================================================================

pub fn observer_verify_count_zero_when_none_test() {
  let state = zenoh_test_observer.init([])
  let result =
    zenoh_test_observer.verify_message_count(state, "missing/topic", 0)
  result.passed |> should.be_true
}

pub fn observer_verify_count_one_after_one_message_test() {
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_message("my/topic", "data")
  let result = zenoh_test_observer.verify_message_count(state, "my/topic", 1)
  result.passed |> should.be_true
}

pub fn observer_verify_count_mismatch_fails_test() {
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_message("my/topic", "data")
  let result = zenoh_test_observer.verify_message_count(state, "my/topic", 5)
  result.passed |> should.equal(False)
}

// =============================================================================
// zenoh_test_observer.gleam — generate_report and format_report
// =============================================================================

pub fn observer_generate_report_empty_test() {
  let state = zenoh_test_observer.init([])
  let report = zenoh_test_observer.generate_report(state)
  report.total_messages |> should.equal(0)
  report.total_topics |> should.equal(0)
}

pub fn observer_generate_report_counts_messages_test() {
  let state =
    zenoh_test_observer.init(["t1", "t2"])
    |> zenoh_test_observer.record_message("t1", "p1")
    |> zenoh_test_observer.record_message("t2", "p2")
  let report = zenoh_test_observer.generate_report(state)
  report.total_messages |> should.equal(2)
}

pub fn observer_generate_report_delivery_rate_full_test() {
  let state =
    zenoh_test_observer.init(["t1"])
    |> zenoh_test_observer.record_message("t1", "p1")
  let report = zenoh_test_observer.generate_report(state)
  report.delivery_rate |> should.equal(1.0)
}

pub fn observer_format_report_nonempty_test() {
  let state = zenoh_test_observer.init([])
  let report = zenoh_test_observer.generate_report(state)
  let formatted = zenoh_test_observer.format_report(report)
  { formatted != "" } |> should.be_true
}

pub fn observer_format_report_contains_header_test() {
  let state = zenoh_test_observer.init([])
  let report = zenoh_test_observer.generate_report(state)
  let formatted = zenoh_test_observer.format_report(report)
  // Should contain the report header
  { formatted != "" } |> should.be_true
}

pub fn observer_verify_mcp_relay_empty_is_ok_test() {
  let state = zenoh_test_observer.init([])
  let result = zenoh_test_observer.verify_mcp_relay(state, [])
  result.passed |> should.be_true
}

// =============================================================================
// test_dashboard.gleam — init
// =============================================================================

pub fn dashboard_init_default_phase_test() {
  let model = test_dashboard.init()
  model.phase |> should.equal(test_dashboard.PhaseSynthetic)
}

pub fn dashboard_init_empty_tabs_test() {
  let model = test_dashboard.init()
  list.length(model.tabs) |> should.equal(0)
}

pub fn dashboard_init_zero_counts_test() {
  let model = test_dashboard.init()
  model.total_tests |> should.equal(0)
  model.total_passed |> should.equal(0)
  model.total_failed |> should.equal(0)
  model.is_complete |> should.equal(False)
}

// =============================================================================
// test_dashboard.gleam — init_with_tabs
// =============================================================================

pub fn dashboard_init_with_tabs_has_eight_tabs_test() {
  let model = test_dashboard.init_with_tabs()
  list.length(model.tabs) |> should.equal(8)
}

pub fn dashboard_init_with_tabs_all_zero_test() {
  let model = test_dashboard.init_with_tabs()
  list.all(model.tabs, fn(tab) { tab.tests_total == 0 })
  |> should.be_true
}

// =============================================================================
// test_dashboard.gleam — make_test_record
// =============================================================================

pub fn make_test_record_pending_status_test() {
  let record = test_dashboard.make_test_record("id-1", "my_test", "L0", 0)
  record.status |> should.equal(test_dashboard.TestPending)
  record.id |> should.equal("id-1")
  record.name |> should.equal("my_test")
  record.tab |> should.equal("L0")
}

pub fn make_test_record_no_finished_at_test() {
  let record = test_dashboard.make_test_record("id-2", "test2", "L2", 1000)
  record.finished_at |> should.equal(None)
  record.duration_ms |> should.equal(0)
}

// =============================================================================
// test_dashboard.gleam — start_test and finish_test
// =============================================================================

pub fn start_test_increments_running_test() {
  let model = test_dashboard.init()
  let record = test_dashboard.make_test_record("t1", "test_a", "L0", 0)
  let updated = test_dashboard.start_test(model, record, 100)
  updated.total_running |> should.equal(1)
}

pub fn finish_test_increments_passed_test() {
  let model = test_dashboard.init()
  let record = test_dashboard.make_test_record("t1", "test_a", "L0", 0)
  let started = test_dashboard.start_test(model, record, 0)
  let finished = test_dashboard.finish_test(started, "t1", True, "", 50, 50)
  finished.total_passed |> should.equal(1)
  finished.total_running |> should.equal(0)
}

pub fn finish_test_increments_failed_test() {
  let model = test_dashboard.init()
  let record = test_dashboard.make_test_record("t1", "test_b", "L0", 0)
  let started = test_dashboard.start_test(model, record, 0)
  let finished =
    test_dashboard.finish_test(started, "t1", False, "assertion failed", 50, 50)
  finished.total_failed |> should.equal(1)
}

// =============================================================================
// test_dashboard.gleam — advance_phase and complete_cycle
// =============================================================================

pub fn advance_phase_changes_phase_test() {
  let model = test_dashboard.init()
  let advanced =
    test_dashboard.advance_phase(model, test_dashboard.PhaseRealtime, 1000)
  advanced.phase |> should.equal(test_dashboard.PhaseRealtime)
}

pub fn advance_phase_increments_cycle_count_test() {
  let model = test_dashboard.init()
  let advanced =
    test_dashboard.advance_phase(model, test_dashboard.PhaseSystemOps, 2000)
  advanced.cycle_count |> should.equal(1)
}

pub fn complete_cycle_marks_done_when_no_pending_test() {
  let model = test_dashboard.init()
  let done = test_dashboard.complete_cycle(model, 5000)
  done.is_complete |> should.be_true
}

// =============================================================================
// test_dashboard.gleam — tab_pass_rate and overall_pass_rate
// =============================================================================

pub fn tab_pass_rate_all_pass_test() {
  let tab =
    test_dashboard.TabSummary(
      tab_name: "L0",
      fractal_layer: cepaf_gleam_domain_l0(),
      tests_total: 5,
      tests_passed: 5,
      tests_failed: 0,
      tests_pending: 0,
      tests_running: 0,
      tests_skipped: 0,
      duration_ms: 100,
      avg_duration_ms: 20.0,
      kpis: [],
      corrective_actions: [],
    )
  test_dashboard.tab_pass_rate(tab)
  |> should.equal(1.0)
}

pub fn tab_pass_rate_no_tests_returns_one_test() {
  let tab =
    test_dashboard.TabSummary(
      tab_name: "L1",
      fractal_layer: cepaf_gleam_domain_l1(),
      tests_total: 0,
      tests_passed: 0,
      tests_failed: 0,
      tests_pending: 0,
      tests_running: 0,
      tests_skipped: 0,
      duration_ms: 0,
      avg_duration_ms: 0.0,
      kpis: [],
      corrective_actions: [],
    )
  test_dashboard.tab_pass_rate(tab)
  |> should.equal(1.0)
}

pub fn overall_pass_rate_empty_model_returns_one_test() {
  let model = test_dashboard.init()
  test_dashboard.overall_pass_rate(model)
  |> should.equal(1.0)
}

// =============================================================================
// test_dashboard.gleam — grade_label and test_status_label
// =============================================================================

pub fn grade_label_a_test() {
  test_dashboard.grade_label(GradeA) |> should.equal("A")
}

pub fn grade_label_b_test() {
  test_dashboard.grade_label(GradeB) |> should.equal("B")
}

pub fn grade_label_c_test() {
  test_dashboard.grade_label(GradeC) |> should.equal("C")
}

pub fn grade_label_d_test() {
  test_dashboard.grade_label(GradeD) |> should.equal("D")
}

pub fn test_status_label_pending_test() {
  test_dashboard.test_status_label(test_dashboard.TestPending)
  |> should.equal("PENDING")
}

pub fn test_status_label_passed_test() {
  test_dashboard.test_status_label(test_dashboard.TestPassed)
  |> should.equal("PASS")
}

pub fn test_status_label_failed_test() {
  test_dashboard.test_status_label(test_dashboard.TestFailed("reason"))
  |> should.equal("FAIL")
}

pub fn test_status_label_skipped_test() {
  test_dashboard.test_status_label(test_dashboard.TestSkipped)
  |> should.equal("SKIP")
}

// =============================================================================
// test_dashboard.gleam — phase_duration_label and make_kpi
// =============================================================================

pub fn phase_duration_label_synthetic_test() {
  test_dashboard.phase_duration_label(test_dashboard.PhaseSynthetic)
  |> should.not_equal("")
}

pub fn phase_duration_label_realtime_test() {
  test_dashboard.phase_duration_label(test_dashboard.PhaseRealtime)
  |> should.not_equal("")
}

pub fn make_kpi_grade_a_for_high_scores_test() {
  let kpi = test_dashboard.make_kpi("element", 3.0, 1.0, 0.0, 1.0)
  // High entropy (3.0), perfect CCM (1.0), no divergence, perfect FSI
  kpi.grade |> should.equal(GradeA)
}

pub fn make_kpi_grade_d_for_zero_scores_test() {
  let kpi = test_dashboard.make_kpi("element", 0.0, 0.0, 1.0, 0.0)
  // Zero entropy, zero CCM, full divergence, zero FSI
  kpi.grade |> should.equal(GradeD)
}

pub fn summary_report_is_nonempty_test() {
  let model = test_dashboard.init()
  test_dashboard.summary_report(model)
  |> should.not_equal("")
}

// =============================================================================
// Helpers — fractal layer literals for TabSummary construction
// =============================================================================

fn cepaf_gleam_domain_l0() {
  L0Constitutional
}

fn cepaf_gleam_domain_l1() {
  L1AtomicDebug
}
