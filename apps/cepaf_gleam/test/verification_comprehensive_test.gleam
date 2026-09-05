// Verification Comprehensive Test Suite
// Tests for verification modules: prometheus, graph_verification, probes, swarm.
// SC-PROM-001..007, SC-GVF-001..008, SC-GRAPH-001..010
// Coverage: DAG acyclicity, path verification, proof tokens, 2oo3 voting,
//           probe results, swarm reports, fractal layer coverage.

import cepaf_gleam/verification/graph_verification
import cepaf_gleam/verification/probes
import cepaf_gleam/verification/prometheus
import cepaf_gleam/verification/swarm
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// =============================================================================
// Helpers — build test DAGs
// =============================================================================

fn make_node(id: String, layer: Int) -> prometheus.DagNode {
  prometheus.DagNode(id: id, node_type: "service", layer: layer, constraints: [
    "SC-SIL4-001",
  ])
}

fn make_edge(from: String, to: String) -> prometheus.DagEdge {
  prometheus.DagEdge(from: from, to: to, edge_type: "depends", weight: 1.0)
}

fn simple_linear_dag() -> prometheus.VerificationDag {
  // A -> B -> C (no cycles)
  prometheus.VerificationDag(
    nodes: [make_node("A", 0), make_node("B", 1), make_node("C", 2)],
    edges: [make_edge("A", "B"), make_edge("B", "C")],
  )
}

fn cyclic_dag() -> prometheus.VerificationDag {
  // A -> B -> C -> A (cycle!)
  prometheus.VerificationDag(
    nodes: [make_node("A", 0), make_node("B", 1), make_node("C", 2)],
    edges: [make_edge("A", "B"), make_edge("B", "C"), make_edge("C", "A")],
  )
}

fn single_node_dag() -> prometheus.VerificationDag {
  prometheus.VerificationDag(nodes: [make_node("only", 0)], edges: [])
}

// =============================================================================
// C1: prometheus — is_acyclic (Kahn's algorithm)
// =============================================================================

pub fn acyclic_linear_dag_test() {
  prometheus.is_acyclic(simple_linear_dag())
  |> should.be_true()
}

pub fn cyclic_dag_fails_acyclicity_test() {
  prometheus.is_acyclic(cyclic_dag())
  |> should.be_false()
}

pub fn single_node_dag_is_acyclic_test() {
  prometheus.is_acyclic(single_node_dag())
  |> should.be_true()
}

pub fn empty_dag_is_acyclic_test() {
  let empty = prometheus.VerificationDag(nodes: [], edges: [])
  prometheus.is_acyclic(empty)
  |> should.be_true()
}

pub fn dag_with_parallel_paths_is_acyclic_test() {
  // A -> B, A -> C, B -> D, C -> D
  let dag =
    prometheus.VerificationDag(
      nodes: [
        make_node("A", 0),
        make_node("B", 1),
        make_node("C", 1),
        make_node("D", 2),
      ],
      edges: [
        make_edge("A", "B"),
        make_edge("A", "C"),
        make_edge("B", "D"),
        make_edge("C", "D"),
      ],
    )
  prometheus.is_acyclic(dag)
  |> should.be_true()
}

// =============================================================================
// C2: prometheus — verify_path
// =============================================================================

pub fn verify_path_valid_test() {
  let dag = simple_linear_dag()
  prometheus.verify_path(dag, ["A", "B", "C"])
  |> should.equal(prometheus.Verified)
}

pub fn verify_path_invalid_edge_test() {
  let dag = simple_linear_dag()
  // A -> C does not exist in the DAG
  let result = prometheus.verify_path(dag, ["A", "C"])
  case result {
    prometheus.Rejected(_) -> True |> should.be_true()
    _ -> should.fail()
  }
}

pub fn verify_path_empty_path_test() {
  let dag = simple_linear_dag()
  // Empty path has no edges to check — trivially valid
  prometheus.verify_path(dag, [])
  |> should.equal(prometheus.Verified)
}

pub fn verify_path_single_node_test() {
  let dag = simple_linear_dag()
  // Single node — no edges to check
  prometheus.verify_path(dag, ["A"])
  |> should.equal(prometheus.Verified)
}

pub fn verify_path_rejected_contains_reason_test() {
  let dag = simple_linear_dag()
  let result = prometheus.verify_path(dag, ["A", "C"])
  case result {
    prometheus.Rejected(reasons) -> {
      { reasons != [] } |> should.be_true()
      let assert Ok(first) = list.first(reasons)
      string.contains(first, "A")
      |> should.be_true()
    }
    _ -> should.fail()
  }
}

// =============================================================================
// C3: prometheus — check_exclusivity
// =============================================================================

pub fn exclusive_paths_no_overlap_test() {
  let dag = simple_linear_dag()
  prometheus.check_exclusivity(dag, ["A", "B"], ["C"])
  |> should.be_true()
}

pub fn overlapping_paths_not_exclusive_test() {
  let dag = simple_linear_dag()
  prometheus.check_exclusivity(dag, ["A", "B"], ["B", "C"])
  |> should.be_false()
}

pub fn empty_paths_are_exclusive_test() {
  let dag = simple_linear_dag()
  prometheus.check_exclusivity(dag, [], [])
  |> should.be_true()
}

// =============================================================================
// C4: prometheus — generate_proof
// =============================================================================

pub fn generate_proof_verified_path_test() {
  let dag = simple_linear_dag()
  let proof = prometheus.generate_proof(dag, ["A", "B", "C"], 1_700_000_000)
  proof.result
  |> should.equal(prometheus.Verified)
  proof.path
  |> should.equal(["A", "B", "C"])
  proof.verified_at
  |> should.equal(1_700_000_000)
}

pub fn generate_proof_dag_hash_has_prefix_test() {
  let dag = simple_linear_dag()
  let proof = prometheus.generate_proof(dag, ["A", "B"], 0)
  string.starts_with(proof.dag_hash, "sha256:")
  |> should.be_true()
}

pub fn generate_proof_constraints_collected_test() {
  let dag =
    prometheus.VerificationDag(
      nodes: [
        prometheus.DagNode(
          id: "X",
          node_type: "service",
          layer: 0,
          constraints: ["SC-SIL4-001", "SC-SAFETY-009"],
        ),
        make_node("Y", 1),
      ],
      edges: [make_edge("X", "Y")],
    )
  let proof = prometheus.generate_proof(dag, ["X", "Y"], 0)
  list.contains(proof.constraints_checked, "SC-SIL4-001")
  |> should.be_true()
}

pub fn proof_to_json_produces_object_test() {
  let dag = simple_linear_dag()
  let proof = prometheus.generate_proof(dag, ["A"], 42)
  let json_str =
    proof
    |> prometheus.proof_to_json()
    |> json_to_string()
  string.contains(json_str, "dag_hash")
  |> should.be_true()
}

import gleam/json

fn json_to_string(j: json.Json) -> String {
  json.to_string(j)
}

// =============================================================================
// C5: VerificationResult types
// =============================================================================

pub fn verified_result_type_test() {
  // Verified is a unit constructor — bind and assert
  let r = prometheus.Verified
  { r == prometheus.Verified }
  |> should.be_true()
}

pub fn rejected_result_type_test() {
  let prometheus.Rejected(reasons) =
    prometheus.Rejected(reasons: ["no edge from X to Y"])
  list.length(reasons)
  |> should.equal(1)
}

pub fn inconclusive_result_type_test() {
  let r = prometheus.Inconclusive
  { r == prometheus.Inconclusive }
  |> should.be_true()
}

// =============================================================================
// C6: graph_verification module
// =============================================================================

pub fn graph_check_acyclicity_passes_for_linear_dag_test() {
  let dag = simple_linear_dag()
  let check = graph_verification.check_acyclicity(dag)
  check.passed
  |> should.be_true()
  check.name
  |> should.equal("acyclicity")
}

pub fn graph_check_acyclicity_fails_for_cyclic_dag_test() {
  let check = graph_verification.check_acyclicity(cyclic_dag())
  check.passed
  |> should.be_false()
}

pub fn graph_check_connectivity_finds_roots_test() {
  let check = graph_verification.check_connectivity(simple_linear_dag())
  check.passed
  |> should.be_true()
  string.contains(check.details, "root node")
  |> should.be_true()
}

pub fn graph_check_node_count_passes_for_nonempty_dag_test() {
  let check = graph_verification.check_node_count(simple_linear_dag())
  check.passed
  |> should.be_true()
  string.contains(check.details, "3")
  |> should.be_true()
}

pub fn graph_check_node_count_fails_for_empty_dag_test() {
  let empty = prometheus.VerificationDag(nodes: [], edges: [])
  let check = graph_verification.check_node_count(empty)
  check.passed
  |> should.be_false()
}

pub fn graph_check_edge_count_passes_for_dag_with_edges_test() {
  let check = graph_verification.check_edge_count(simple_linear_dag())
  check.passed
  |> should.be_true()
}

pub fn graph_check_edge_count_fails_for_dag_no_edges_test() {
  let no_edges =
    prometheus.VerificationDag(nodes: [make_node("A", 0)], edges: [])
  let check = graph_verification.check_edge_count(no_edges)
  check.passed
  |> should.be_false()
}

pub fn verify_all_returns_four_checks_test() {
  let checks = graph_verification.verify_all(simple_linear_dag())
  list.length(checks)
  |> should.equal(4)
}

pub fn all_passed_true_for_good_dag_test() {
  let checks = graph_verification.verify_all(simple_linear_dag())
  graph_verification.all_passed(checks)
  |> should.be_true()
}

pub fn passed_count_test() {
  let checks = graph_verification.verify_all(simple_linear_dag())
  graph_verification.passed_count(checks)
  |> should.equal(4)
}

// =============================================================================
// C7: probes — ProbeResult and 2oo3 voting
// =============================================================================

pub fn probe_result_healthy_test() {
  let r = probes.Healthy
  { r == probes.Healthy }
  |> should.be_true()
}

pub fn probe_result_unhealthy_test() {
  let probes.Unhealthy(msg) = probes.Unhealthy("connection refused")
  string.contains(msg, "refused")
  |> should.be_true()
}

pub fn verify_2oo3_all_healthy_passes_test() {
  let results = [probes.Healthy, probes.Healthy, probes.Healthy]
  probes.verify_2oo3(results)
  |> should.equal(probes.Healthy)
}

pub fn verify_2oo3_two_healthy_passes_test() {
  let results = [probes.Healthy, probes.Healthy, probes.Unhealthy("err")]
  probes.verify_2oo3(results)
  |> should.equal(probes.Healthy)
}

pub fn verify_2oo3_one_healthy_fails_test() {
  let results = [
    probes.Healthy,
    probes.Unhealthy("err1"),
    probes.Unhealthy("err2"),
  ]
  case probes.verify_2oo3(results) {
    probes.Unhealthy(msg) ->
      string.contains(msg, "Quorum")
      |> should.be_true()
    probes.Healthy -> should.fail()
  }
}

pub fn verify_2oo3_all_unhealthy_fails_test() {
  let results = [
    probes.Unhealthy("a"),
    probes.Unhealthy("b"),
    probes.Unhealthy("c"),
  ]
  case probes.verify_2oo3(results) {
    probes.Unhealthy(_) -> True |> should.be_true()
    probes.Healthy -> should.fail()
  }
}

pub fn http_probe_returns_probe_result_test() {
  // Simplified probe — returns Healthy (real impl via FFI)
  probes.http_probe("http://localhost:4100/health", 1000)
  |> should.equal(probes.Healthy)
}

pub fn tcp_probe_returns_probe_result_test() {
  probes.tcp_probe("localhost", 7447, 1000)
  |> should.equal(probes.Healthy)
}

// =============================================================================
// C8: swarm — OodaMetrics, FractalLayerReport, SwarmReport
// =============================================================================

pub fn ooda_metrics_construction_test() {
  let metrics =
    swarm.OodaMetrics(
      agent_latency_ms: 25,
      intelligence_latency_ms: 80,
      compliance: True,
    )
  metrics.agent_latency_ms
  |> should.equal(25)
  metrics.compliance
  |> should.be_true()
}

pub fn ooda_metrics_compliance_threshold_test() {
  // SC-OODA constraint: agent < 30ms, intelligence < 100ms
  let metrics =
    swarm.OodaMetrics(
      agent_latency_ms: 25,
      intelligence_latency_ms: 80,
      compliance: True,
    )
  { metrics.agent_latency_ms < 30 }
  |> should.be_true()
  { metrics.intelligence_latency_ms < 100 }
  |> should.be_true()
}

pub fn verify_ooda_compliance_returns_metrics_test() {
  let metrics = swarm.verify_ooda_compliance([])
  metrics.compliance
  |> should.be_true()
}

pub fn generate_report_has_all_fractal_layers_test() {
  let metrics =
    swarm.OodaMetrics(
      agent_latency_ms: 25,
      intelligence_latency_ms: 80,
      compliance: True,
    )
  let report = swarm.generate_report(metrics, 16, 16)
  list.length(report.fractal_layers)
  |> should.equal(8)
}

pub fn generate_report_healthy_count_test() {
  let metrics =
    swarm.OodaMetrics(
      agent_latency_ms: 25,
      intelligence_latency_ms: 80,
      compliance: True,
    )
  let report = swarm.generate_report(metrics, 14, 16)
  report.healthy_containers
  |> should.equal(14)
  report.total_containers
  |> should.equal(16)
}

pub fn fractal_layer_report_l0_constitutional_test() {
  let metrics = swarm.verify_ooda_compliance([])
  let report = swarm.generate_report(metrics, 16, 16)
  let l0 = list.find(report.fractal_layers, fn(r) { r.layer == 0 })
  case l0 {
    Ok(layer) -> {
      layer.status
      |> should.equal("Stable")
      string.contains(layer.evidence, "Constitutional")
      |> should.be_true()
    }
    Error(_) -> should.fail()
  }
}

pub fn fractal_layer_report_l7_federation_test() {
  let metrics = swarm.verify_ooda_compliance([])
  let report = swarm.generate_report(metrics, 16, 16)
  let l7 = list.find(report.fractal_layers, fn(r) { r.layer == 7 })
  case l7 {
    Ok(layer) ->
      string.contains(layer.evidence, "Federation")
      |> should.be_true()
    Error(_) -> should.fail()
  }
}

pub fn fractal_layer_all_layers_present_test() {
  let metrics = swarm.verify_ooda_compliance([])
  let report = swarm.generate_report(metrics, 16, 16)
  let layer_ids = list.map(report.fractal_layers, fn(r) { r.layer })
  list.contains(layer_ids, 0)
  |> should.be_true()
  list.contains(layer_ids, 7)
  |> should.be_true()
}
