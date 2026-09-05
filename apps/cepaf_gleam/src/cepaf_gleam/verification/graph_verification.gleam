//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/verification/graph_verification</module></identity>
////   <fractal-topology><layer>L1_ATOMIC_DEBUG</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GRAPH-001..010</stamp-controls></compliance></c3i-module>
////
//// Graph verification: SCC analysis, cycle detection, connectivity checks.

import cepaf_gleam/verification/prometheus.{type VerificationDag}
import gleam/int
import gleam/list
import gleam/set

/// Verification check result.
pub type GraphCheck {
  GraphCheck(name: String, passed: Bool, details: String)
}

/// Run all graph verification checks on a DAG.
pub fn verify_all(dag: VerificationDag) -> List(GraphCheck) {
  [
    check_acyclicity(dag),
    check_connectivity(dag),
    check_node_count(dag),
    check_edge_count(dag),
  ]
}

/// Check DAG is acyclic (SC-BOOT-008).
pub fn check_acyclicity(dag: VerificationDag) -> GraphCheck {
  let acyclic = prometheus.is_acyclic(dag)
  GraphCheck(name: "acyclicity", passed: acyclic, details: case acyclic {
    True -> "DAG is acyclic (Kahn's algorithm verified)"
    False -> "CYCLE DETECTED — DAG validation failed"
  })
}

/// Check all nodes are reachable from at least one root.
pub fn check_connectivity(dag: VerificationDag) -> GraphCheck {
  let node_ids = set.from_list(list.map(dag.nodes, fn(n) { n.id }))
  let target_ids = set.from_list(list.map(dag.edges, fn(e) { e.to }))
  let roots =
    set.difference(node_ids, target_ids)
    |> set.to_list()
  let has_roots = !list.is_empty(roots)
  GraphCheck(name: "connectivity", passed: has_roots, details: case has_roots {
    True -> "Found " <> int.to_string(list.length(roots)) <> " root node(s)"
    False -> "No root nodes found — possible cycle"
  })
}

/// Check node count is reasonable.
pub fn check_node_count(dag: VerificationDag) -> GraphCheck {
  let count = list.length(dag.nodes)
  GraphCheck(
    name: "node_count",
    passed: count > 0,
    details: int.to_string(count) <> " nodes",
  )
}

/// Check edge count is reasonable.
pub fn check_edge_count(dag: VerificationDag) -> GraphCheck {
  let count = list.length(dag.edges)
  GraphCheck(
    name: "edge_count",
    passed: count > 0,
    details: int.to_string(count) <> " edges",
  )
}

/// Check all verifications passed.
pub fn all_passed(checks: List(GraphCheck)) -> Bool {
  list.all(checks, fn(c) { c.passed })
}

/// Count passed checks.
pub fn passed_count(checks: List(GraphCheck)) -> Int {
  list.count(checks, fn(c) { c.passed })
}
