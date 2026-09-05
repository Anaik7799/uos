// STAMP: SC-PROM-001..007, SC-GVF-001..008, SC-GRAPH-001..010
// AOR: AOR-VER-001
// Criticality: Level 2 (HIGH)
//
// Coverage tests for the verification/ package.
// Targets previously untested modules:
//   - verification/prometheus.gleam
//   - verification/probes.gleam
//   - verification/swarm.gleam
//   - verification/graph_verification.gleam

import cepaf_gleam/verification/graph_verification as ver_graph
import cepaf_gleam/verification/probes
import cepaf_gleam/verification/prometheus
import cepaf_gleam/verification/swarm
import gleam/list
import gleeunit/should

// =============================================================================
// prometheus.gleam — DAG types, is_acyclic, verify_path, check_exclusivity,
//                    generate_proof, proof_to_json
// =============================================================================

pub fn dag_node_construction_test() {
  let node =
    prometheus.DagNode(
      id: "boot",
      node_type: "container",
      layer: 0,
      constraints: ["SC-SIL4-001", "SC-BOOT-001"],
    )
  node.id |> should.equal("boot")
  node.node_type |> should.equal("container")
  node.layer |> should.equal(0)
  list.length(node.constraints) |> should.equal(2)
}

pub fn dag_edge_construction_test() {
  let edge =
    prometheus.DagEdge(
      from: "db",
      to: "app",
      edge_type: "depends_on",
      weight: 1.0,
    )
  edge.from |> should.equal("db")
  edge.to |> should.equal("app")
  edge.edge_type |> should.equal("depends_on")
}

pub fn verification_dag_construction_test() {
  let nodes = [
    prometheus.DagNode(id: "n1", node_type: "svc", layer: 1, constraints: []),
    prometheus.DagNode(id: "n2", node_type: "svc", layer: 2, constraints: []),
  ]
  let edges = [
    prometheus.DagEdge(from: "n1", to: "n2", edge_type: "seq", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  list.length(dag.nodes) |> should.equal(2)
  list.length(dag.edges) |> should.equal(1)
}

pub fn verification_result_verified_test() {
  let result = prometheus.Verified
  case result {
    prometheus.Verified -> should.be_true(True)
    //     _ -> should.fail()
  }
}

pub fn verification_result_rejected_test() {
  let result = prometheus.Rejected(reasons: ["no edge from A to B"])
  case result {
    prometheus.Rejected(reasons:) -> {
      list.length(reasons) |> should.equal(1)
    }
    //     _ -> should.fail()
  }
}

pub fn verification_result_inconclusive_test() {
  let result = prometheus.Inconclusive
  case result {
    prometheus.Inconclusive -> should.be_true(True)
    //     _ -> should.fail()
  }
}

pub fn is_acyclic_empty_dag_test() {
  let dag = prometheus.VerificationDag(nodes: [], edges: [])
  prometheus.is_acyclic(dag) |> should.be_true()
}

pub fn is_acyclic_simple_dag_test() {
  // A -> B -> C (acyclic)
  let nodes = [
    prometheus.DagNode(id: "A", node_type: "t", layer: 0, constraints: []),
    prometheus.DagNode(id: "B", node_type: "t", layer: 1, constraints: []),
    prometheus.DagNode(id: "C", node_type: "t", layer: 2, constraints: []),
  ]
  let edges = [
    prometheus.DagEdge(from: "A", to: "B", edge_type: "e", weight: 1.0),
    prometheus.DagEdge(from: "B", to: "C", edge_type: "e", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  prometheus.is_acyclic(dag) |> should.be_true()
}

pub fn is_acyclic_cyclic_dag_test() {
  // A -> B -> A (cycle)
  let nodes = [
    prometheus.DagNode(id: "A", node_type: "t", layer: 0, constraints: []),
    prometheus.DagNode(id: "B", node_type: "t", layer: 1, constraints: []),
  ]
  let edges = [
    prometheus.DagEdge(from: "A", to: "B", edge_type: "e", weight: 1.0),
    prometheus.DagEdge(from: "B", to: "A", edge_type: "e", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  prometheus.is_acyclic(dag) |> should.be_false()
}

pub fn verify_path_valid_test() {
  let nodes = [
    prometheus.DagNode(id: "X", node_type: "t", layer: 0, constraints: []),
    prometheus.DagNode(id: "Y", node_type: "t", layer: 1, constraints: []),
  ]
  let edges = [
    prometheus.DagEdge(from: "X", to: "Y", edge_type: "e", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  let result = prometheus.verify_path(dag, ["X", "Y"])
  case result {
    prometheus.Verified -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn verify_path_invalid_test() {
  let nodes = [
    prometheus.DagNode(id: "X", node_type: "t", layer: 0, constraints: []),
    prometheus.DagNode(id: "Y", node_type: "t", layer: 1, constraints: []),
  ]
  let edges = []
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  // No edge X->Y
  let result = prometheus.verify_path(dag, ["X", "Y"])
  case result {
    prometheus.Rejected(reasons:) -> {
      list.is_empty(reasons) |> should.be_false()
    }
    _ -> should.fail()
  }
}

pub fn verify_path_empty_path_test() {
  let dag = prometheus.VerificationDag(nodes: [], edges: [])
  let result = prometheus.verify_path(dag, [])
  case result {
    prometheus.Verified -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn check_exclusivity_non_overlapping_test() {
  let dag = prometheus.VerificationDag(nodes: [], edges: [])
  let exclusive = prometheus.check_exclusivity(dag, ["A", "B"], ["C", "D"])
  exclusive |> should.be_true()
}

pub fn check_exclusivity_overlapping_test() {
  let dag = prometheus.VerificationDag(nodes: [], edges: [])
  let exclusive = prometheus.check_exclusivity(dag, ["A", "B"], ["B", "C"])
  exclusive |> should.be_false()
}

pub fn generate_proof_verified_test() {
  let nodes = [
    prometheus.DagNode(id: "start", node_type: "svc", layer: 0, constraints: [
      "SC-BOOT-001",
    ]),
    prometheus.DagNode(id: "end", node_type: "svc", layer: 1, constraints: [
      "SC-BOOT-002",
    ]),
  ]
  let edges = [
    prometheus.DagEdge(from: "start", to: "end", edge_type: "seq", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  let proof = prometheus.generate_proof(dag, ["start", "end"], 1_000_000)
  proof.verified_at |> should.equal(1_000_000)
  proof.path |> should.equal(["start", "end"])
  case proof.result {
    prometheus.Verified -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn generate_proof_rejected_test() {
  let dag = prometheus.VerificationDag(nodes: [], edges: [])
  // No edge between these nodes
  let proof = prometheus.generate_proof(dag, ["A", "B"], 999)
  case proof.result {
    prometheus.Rejected(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn proof_to_json_test() {
  let nodes = [
    prometheus.DagNode(id: "p", node_type: "t", layer: 0, constraints: []),
    prometheus.DagNode(id: "q", node_type: "t", layer: 1, constraints: []),
  ]
  let edges = [
    prometheus.DagEdge(from: "p", to: "q", edge_type: "e", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  let proof = prometheus.generate_proof(dag, ["p", "q"], 12_345)
  // Should not panic — JSON serialisation succeeds
  let _json = prometheus.proof_to_json(proof)
  should.be_true(True)
}

// =============================================================================
// probes.gleam — ProbeResult constructors, verify_2oo3
// =============================================================================

pub fn probe_result_healthy_test() {
  let r = probes.Healthy
  case r {
    probes.Healthy -> should.be_true(True)
    //     _ -> should.fail()
  }
}

pub fn probe_result_unhealthy_test() {
  let r = probes.Unhealthy("connection refused")
  case r {
    probes.Unhealthy(msg) -> {
      msg |> should.equal("connection refused")
    }
    //     _ -> should.fail()
  }
}

pub fn verify_2oo3_all_healthy_test() {
  let results = [probes.Healthy, probes.Healthy, probes.Healthy]
  let verdict = probes.verify_2oo3(results)
  case verdict {
    probes.Healthy -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn verify_2oo3_quorum_met_test() {
  // 2 healthy, 1 unhealthy — quorum (2/3)
  let results = [
    probes.Healthy,
    probes.Healthy,
    probes.Unhealthy("timeout"),
  ]
  let verdict = probes.verify_2oo3(results)
  case verdict {
    probes.Healthy -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn verify_2oo3_quorum_not_met_test() {
  // 1 healthy, 2 unhealthy — quorum NOT met
  let results = [
    probes.Healthy,
    probes.Unhealthy("timeout"),
    probes.Unhealthy("refused"),
  ]
  let verdict = probes.verify_2oo3(results)
  case verdict {
    probes.Unhealthy(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn verify_2oo3_all_unhealthy_test() {
  let results = [
    probes.Unhealthy("a"),
    probes.Unhealthy("b"),
    probes.Unhealthy("c"),
  ]
  let verdict = probes.verify_2oo3(results)
  case verdict {
    probes.Unhealthy(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn verify_2oo3_empty_list_test() {
  // 0 healthy out of 0 — quorum not met
  let verdict = probes.verify_2oo3([])
  case verdict {
    probes.Unhealthy(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

// =============================================================================
// swarm.gleam — OodaMetrics, FractalLayerReport, SwarmReport, generate_report
// =============================================================================

pub fn ooda_metrics_construction_test() {
  let m =
    swarm.OodaMetrics(
      agent_latency_ms: 25,
      intelligence_latency_ms: 80,
      compliance: True,
    )
  m.agent_latency_ms |> should.equal(25)
  m.intelligence_latency_ms |> should.equal(80)
  m.compliance |> should.be_true()
}

pub fn fractal_layer_report_construction_test() {
  let r = swarm.FractalLayerReport(layer: 0, status: "Stable", evidence: "ok")
  r.layer |> should.equal(0)
  r.status |> should.equal("Stable")
  r.evidence |> should.equal("ok")
}

pub fn swarm_report_construction_test() {
  let metrics =
    swarm.OodaMetrics(
      agent_latency_ms: 20,
      intelligence_latency_ms: 90,
      compliance: True,
    )
  let layers = [
    swarm.FractalLayerReport(layer: 0, status: "Stable", evidence: "ok"),
  ]
  let report =
    swarm.SwarmReport(
      healthy_containers: 14,
      total_containers: 16,
      ooda_metrics: metrics,
      fractal_layers: layers,
    )
  report.healthy_containers |> should.equal(14)
  report.total_containers |> should.equal(16)
  report.ooda_metrics.compliance |> should.be_true()
  list.length(report.fractal_layers) |> should.equal(1)
}

pub fn verify_ooda_compliance_returns_metrics_test() {
  let telemetry = ["span1", "span2", "span3"]
  let metrics = swarm.verify_ooda_compliance(telemetry)
  // Contract: agent < 30ms, intelligence < 100ms
  { metrics.agent_latency_ms < 30 } |> should.be_true()
  { metrics.intelligence_latency_ms < 100 } |> should.be_true()
  metrics.compliance |> should.be_true()
}

pub fn generate_report_produces_8_layers_test() {
  let metrics =
    swarm.OodaMetrics(
      agent_latency_ms: 22,
      intelligence_latency_ms: 75,
      compliance: True,
    )
  let report = swarm.generate_report(metrics, 16, 16)
  // generate_report always returns exactly 8 fractal layer reports (L0-L7)
  list.length(report.fractal_layers) |> should.equal(8)
  report.healthy_containers |> should.equal(16)
  report.total_containers |> should.equal(16)
}

pub fn generate_report_layer_indices_test() {
  let metrics =
    swarm.OodaMetrics(
      agent_latency_ms: 10,
      intelligence_latency_ms: 50,
      compliance: True,
    )
  let report = swarm.generate_report(metrics, 8, 16)
  let layers = report.fractal_layers
  // Layer 0 should be the first (Constitutional)
  let assert Ok(l0) = list.first(layers)
  l0.layer |> should.equal(0)
  // Layer 7 should be the last (Federation)
  let rev = list.reverse(layers)
  let assert Ok(l7) = list.first(rev)
  l7.layer |> should.equal(7)
}

// =============================================================================
// verification/graph_verification.gleam — GraphCheck, verify_all, check_*,
//                                          all_passed, passed_count
// =============================================================================

pub fn graph_check_construction_test() {
  let check =
    ver_graph.GraphCheck(name: "acyclicity", passed: True, details: "ok")
  check.name |> should.equal("acyclicity")
  check.passed |> should.be_true()
  check.details |> should.equal("ok")
}

pub fn check_acyclicity_acyclic_dag_test() {
  let nodes = [
    prometheus.DagNode(id: "X", node_type: "t", layer: 0, constraints: []),
    prometheus.DagNode(id: "Y", node_type: "t", layer: 1, constraints: []),
  ]
  let edges = [
    prometheus.DagEdge(from: "X", to: "Y", edge_type: "e", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  let check = ver_graph.check_acyclicity(dag)
  check.name |> should.equal("acyclicity")
  check.passed |> should.be_true()
}

pub fn check_acyclicity_cyclic_dag_test() {
  let nodes = [
    prometheus.DagNode(id: "A", node_type: "t", layer: 0, constraints: []),
    prometheus.DagNode(id: "B", node_type: "t", layer: 1, constraints: []),
  ]
  let edges = [
    prometheus.DagEdge(from: "A", to: "B", edge_type: "e", weight: 1.0),
    prometheus.DagEdge(from: "B", to: "A", edge_type: "e", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  let check = ver_graph.check_acyclicity(dag)
  check.passed |> should.be_false()
}

pub fn check_connectivity_has_roots_test() {
  let nodes = [
    prometheus.DagNode(id: "root", node_type: "t", layer: 0, constraints: []),
    prometheus.DagNode(id: "child", node_type: "t", layer: 1, constraints: []),
  ]
  let edges = [
    prometheus.DagEdge(from: "root", to: "child", edge_type: "e", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  let check = ver_graph.check_connectivity(dag)
  check.name |> should.equal("connectivity")
  check.passed |> should.be_true()
}

pub fn check_node_count_positive_test() {
  let nodes = [
    prometheus.DagNode(id: "n1", node_type: "t", layer: 0, constraints: []),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: [])
  let check = ver_graph.check_node_count(dag)
  check.name |> should.equal("node_count")
  check.passed |> should.be_true()
}

pub fn check_node_count_empty_test() {
  let dag = prometheus.VerificationDag(nodes: [], edges: [])
  let check = ver_graph.check_node_count(dag)
  check.passed |> should.be_false()
}

pub fn check_edge_count_positive_test() {
  let nodes = [
    prometheus.DagNode(id: "a", node_type: "t", layer: 0, constraints: []),
    prometheus.DagNode(id: "b", node_type: "t", layer: 1, constraints: []),
  ]
  let edges = [
    prometheus.DagEdge(from: "a", to: "b", edge_type: "e", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  let check = ver_graph.check_edge_count(dag)
  check.name |> should.equal("edge_count")
  check.passed |> should.be_true()
}

pub fn check_edge_count_empty_test() {
  let nodes = [
    prometheus.DagNode(id: "a", node_type: "t", layer: 0, constraints: []),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: [])
  let check = ver_graph.check_edge_count(dag)
  check.passed |> should.be_false()
}

pub fn verify_all_returns_four_checks_test() {
  let nodes = [
    prometheus.DagNode(id: "m", node_type: "t", layer: 0, constraints: []),
    prometheus.DagNode(id: "n", node_type: "t", layer: 1, constraints: []),
  ]
  let edges = [
    prometheus.DagEdge(from: "m", to: "n", edge_type: "e", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  let checks = ver_graph.verify_all(dag)
  // verify_all returns: acyclicity, connectivity, node_count, edge_count
  list.length(checks) |> should.equal(4)
}

pub fn all_passed_all_true_test() {
  let checks = [
    ver_graph.GraphCheck(name: "a", passed: True, details: "ok"),
    ver_graph.GraphCheck(name: "b", passed: True, details: "ok"),
  ]
  ver_graph.all_passed(checks) |> should.be_true()
}

pub fn all_passed_one_false_test() {
  let checks = [
    ver_graph.GraphCheck(name: "a", passed: True, details: "ok"),
    ver_graph.GraphCheck(name: "b", passed: False, details: "fail"),
  ]
  ver_graph.all_passed(checks) |> should.be_false()
}

pub fn passed_count_mixed_test() {
  let checks = [
    ver_graph.GraphCheck(name: "a", passed: True, details: ""),
    ver_graph.GraphCheck(name: "b", passed: False, details: ""),
    ver_graph.GraphCheck(name: "c", passed: True, details: ""),
  ]
  ver_graph.passed_count(checks) |> should.equal(2)
}

pub fn passed_count_all_failed_test() {
  let checks = [
    ver_graph.GraphCheck(name: "x", passed: False, details: ""),
    ver_graph.GraphCheck(name: "y", passed: False, details: ""),
  ]
  ver_graph.passed_count(checks) |> should.equal(0)
}

pub fn full_good_dag_passes_all_checks_test() {
  let nodes = [
    prometheus.DagNode(id: "r", node_type: "svc", layer: 0, constraints: [
      "SC-BOOT-001",
    ]),
    prometheus.DagNode(id: "s", node_type: "svc", layer: 1, constraints: [
      "SC-BOOT-002",
    ]),
    prometheus.DagNode(id: "t", node_type: "svc", layer: 2, constraints: []),
  ]
  let edges = [
    prometheus.DagEdge(from: "r", to: "s", edge_type: "dep", weight: 1.0),
    prometheus.DagEdge(from: "s", to: "t", edge_type: "dep", weight: 1.0),
  ]
  let dag = prometheus.VerificationDag(nodes: nodes, edges: edges)
  let checks = ver_graph.verify_all(dag)
  ver_graph.all_passed(checks) |> should.be_true()
  ver_graph.passed_count(checks) |> should.equal(4)
}
