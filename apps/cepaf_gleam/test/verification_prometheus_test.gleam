// =============================================================================
// PROMETHEUS Verification, Navigation Graph, and Graph Verification Tests
// =============================================================================
// STAMP: SC-PROM-001..007, SC-GVF-001..008, SC-UIGT-001..014, SC-GRAPH-001..010
// Target: ~25 tests covering prometheus, nav_graph, and graph_verification.
// =============================================================================

import cepaf_gleam/testing/nav_graph
import cepaf_gleam/verification/graph_verification
import cepaf_gleam/verification/prometheus.{
  type VerificationDag, DagEdge, DagNode, Rejected, VerificationDag, Verified,
}
import gleam/dict
import gleam/float
import gleam/list
import gleeunit/should

// =============================================================================
// Test DAG fixtures
// =============================================================================

/// Simple acyclic DAG: A -> B -> C
fn simple_acyclic_dag() -> VerificationDag {
  VerificationDag(
    nodes: [
      DagNode("A", "page", 0, []),
      DagNode("B", "page", 0, []),
      DagNode("C", "page", 0, []),
    ],
    edges: [
      DagEdge("A", "B", "nav", 1.0),
      DagEdge("B", "C", "nav", 1.0),
    ],
  )
}

/// Cyclic DAG: A -> B -> C -> A
fn cyclic_dag() -> VerificationDag {
  VerificationDag(
    nodes: [
      DagNode("A", "page", 0, []),
      DagNode("B", "page", 0, []),
      DagNode("C", "page", 0, []),
    ],
    edges: [
      DagEdge("A", "B", "nav", 1.0),
      DagEdge("B", "C", "nav", 1.0),
      DagEdge("C", "A", "nav", 1.0),
    ],
  )
}

/// Empty DAG (no nodes, no edges)
fn empty_dag() -> VerificationDag {
  VerificationDag(nodes: [], edges: [])
}

// =============================================================================
// 1. PROMETHEUS — is_acyclic
// =============================================================================

pub fn prometheus_acyclic_simple_dag_test() {
  prometheus.is_acyclic(simple_acyclic_dag())
  |> should.be_true()
}

pub fn prometheus_acyclic_cyclic_dag_returns_false_test() {
  prometheus.is_acyclic(cyclic_dag())
  |> should.be_false()
}

pub fn prometheus_acyclic_empty_dag_test() {
  prometheus.is_acyclic(empty_dag())
  |> should.be_true()
}

// =============================================================================
// 2. PROMETHEUS — verify_path
// =============================================================================

pub fn prometheus_verify_path_valid_test() {
  let result = prometheus.verify_path(simple_acyclic_dag(), ["A", "B", "C"])
  result |> should.equal(Verified)
}

pub fn prometheus_verify_path_partial_valid_test() {
  let result = prometheus.verify_path(simple_acyclic_dag(), ["A", "B"])
  result |> should.equal(Verified)
}

pub fn prometheus_verify_path_missing_edge_rejected_test() {
  // A -> C is not a valid edge in simple_acyclic_dag
  let result = prometheus.verify_path(simple_acyclic_dag(), ["A", "C"])
  case result {
    Rejected(_reasons) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn prometheus_verify_path_reversed_rejected_test() {
  // C -> B is not a valid edge (edges go A->B->C, not backwards)
  let result = prometheus.verify_path(simple_acyclic_dag(), ["C", "B"])
  case result {
    Rejected(_reasons) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

// =============================================================================
// 3. PROMETHEUS — check_exclusivity
// =============================================================================

pub fn prometheus_check_exclusivity_non_overlapping_test() {
  prometheus.check_exclusivity(simple_acyclic_dag(), ["A", "B"], ["C"])
  |> should.be_true()
}

pub fn prometheus_check_exclusivity_overlapping_test() {
  // B appears in both paths
  prometheus.check_exclusivity(simple_acyclic_dag(), ["A", "B"], ["B", "C"])
  |> should.be_false()
}

pub fn prometheus_check_exclusivity_disjoint_paths_test() {
  prometheus.check_exclusivity(simple_acyclic_dag(), ["A"], ["B", "C"])
  |> should.be_true()
}

// =============================================================================
// 4. PROMETHEUS — generate_proof
// =============================================================================

pub fn prometheus_generate_proof_valid_path_test() {
  let token =
    prometheus.generate_proof(simple_acyclic_dag(), ["A", "B", "C"], 0)
  token.result |> should.equal(Verified)
}

pub fn prometheus_generate_proof_invalid_path_test() {
  // A -> C has no direct edge
  let token = prometheus.generate_proof(simple_acyclic_dag(), ["A", "C"], 0)
  case token.result {
    Rejected(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn prometheus_generate_proof_has_dag_hash_test() {
  let token = prometheus.generate_proof(simple_acyclic_dag(), ["A", "B"], 42)
  // Hash must start with "sha256:"
  let starts_with_sha = token.dag_hash |> string_starts_with("sha256:")
  starts_with_sha |> should.be_true()
}

pub fn prometheus_generate_proof_timestamp_test() {
  let token = prometheus.generate_proof(simple_acyclic_dag(), ["A", "B"], 9999)
  token.verified_at |> should.equal(9999)
}

// Helper — check string prefix without importing gleam/string directly
fn string_starts_with(s: String, prefix: String) -> Bool {
  let prefix_len = string_byte_size(prefix)
  let s_len = string_byte_size(s)
  case s_len >= prefix_len {
    False -> False
    True -> string_slice(s, 0, prefix_len) == prefix
  }
}

// Use gleam/string for helpers — imported at the bottom to keep fixtures clean
import gleam/string

fn string_byte_size(s: String) -> Int {
  string.length(s)
}

fn string_slice(s: String, start: Int, length: Int) -> String {
  string.slice(s, start, length)
}

// =============================================================================
// 5. Navigation Graph (nav_graph)
// =============================================================================

pub fn nav_graph_all_pages_count_test() {
  nav_graph.all_pages()
  |> list.length()
  |> should.equal(31)
}

pub fn nav_graph_page_count_test() {
  nav_graph.page_count()
  |> should.equal(31)
}

pub fn nav_graph_edge_count_test() {
  // Complete directed graph: n * (n-1) = 31 * 30 = 930
  nav_graph.edge_count()
  |> should.equal(930)
}

pub fn nav_graph_density_test() {
  // Complete graph => density = 1.0
  nav_graph.density()
  |> should.equal(1.0)
}

pub fn nav_graph_page_rank_has_30_entries_test() {
  nav_graph.page_rank()
  |> dict.size()
  |> should.equal(31)
}

pub fn nav_graph_page_rank_values_positive_test() {
  let ranks = nav_graph.page_rank()
  let values = dict.values(ranks)
  list.all(values, fn(v) { v >. 0.0 })
  |> should.be_true()
}

pub fn nav_graph_page_rank_sums_to_one_test() {
  let ranks = nav_graph.page_rank()
  let values = dict.values(ranks)
  let total = list.fold(values, 0.0, fn(acc, v) { acc +. v })
  // Should be approximately 1.0 — within 0.01
  let diff = float.absolute_value(total -. 1.0)
  { diff <. 0.01 }
  |> should.be_true()
}

pub fn nav_graph_test_priority_order_has_30_entries_test() {
  nav_graph.test_priority_order()
  |> list.length()
  |> should.equal(31)
}

pub fn nav_graph_chinese_postman_bound_equals_edge_count_test() {
  nav_graph.chinese_postman_bound()
  |> should.equal(nav_graph.edge_count())
}

pub fn nav_graph_scc_count_test() {
  nav_graph.scc_count()
  |> should.equal(1)
}

// =============================================================================
// 6. Graph Verification (graph_verification)
// =============================================================================

pub fn graph_verification_verify_all_returns_4_checks_test() {
  graph_verification.verify_all(simple_acyclic_dag())
  |> list.length()
  |> should.equal(4)
}

pub fn graph_verification_check_acyclicity_passes_for_acyclic_dag_test() {
  let check = graph_verification.check_acyclicity(simple_acyclic_dag())
  check.passed |> should.be_true()
}

pub fn graph_verification_check_acyclicity_fails_for_cyclic_dag_test() {
  let check = graph_verification.check_acyclicity(cyclic_dag())
  check.passed |> should.be_false()
}

pub fn graph_verification_check_connectivity_passes_when_roots_exist_test() {
  // simple_acyclic_dag: "A" has no incoming edges => it is a root
  let check = graph_verification.check_connectivity(simple_acyclic_dag())
  check.passed |> should.be_true()
}

pub fn graph_verification_check_node_count_passes_non_empty_test() {
  let check = graph_verification.check_node_count(simple_acyclic_dag())
  check.passed |> should.be_true()
}

pub fn graph_verification_check_edge_count_passes_non_empty_test() {
  let check = graph_verification.check_edge_count(simple_acyclic_dag())
  check.passed |> should.be_true()
}

pub fn graph_verification_all_passed_true_for_valid_dag_test() {
  let checks = graph_verification.verify_all(simple_acyclic_dag())
  graph_verification.all_passed(checks)
  |> should.be_true()
}

pub fn graph_verification_passed_count_correct_test() {
  let checks = graph_verification.verify_all(simple_acyclic_dag())
  graph_verification.passed_count(checks)
  |> should.equal(4)
}
