/// PROMETHEUS verification, graph checks, and swarm report tests.
///
/// Covers the Verification plane triple interface: Lustre MVU state
/// transitions, PROMETHEUS proof tokens, graph check wiring, DAG stats,
/// Wisp API JSON encoding, SwarmReport fractal-layer structure, and TUI
/// render assertions.
///
/// STAMP: SC-PROM-001, SC-PROM-002, SC-GRAPH-001, SC-GLM-UI-001,
///        SC-GLM-UI-007, SC-UIGT-003, SC-UIGT-007, SC-UIGT-009
import cepaf_gleam/ui/lustre/verification.{
  DagUpdated, GraphChecksCompleted, ProofGenerated, ReportReceived,
  StartVerification, all_checks_passed, init, latest_proof_verified,
  proof_result_string, update,
}
import cepaf_gleam/ui/tui/verification_view
import cepaf_gleam/ui/wisp/verification_api
import cepaf_gleam/verification/graph_verification.{GraphCheck}
import cepaf_gleam/verification/prometheus.{
  Inconclusive, ProofToken, Rejected, Verified,
}
import cepaf_gleam/verification/swarm.{OodaMetrics, generate_report}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Lustre MVU — init
// =============================================================================

pub fn verification_init_no_report_test() {
  init().last_report
  |> should.equal(None)
}

pub fn verification_init_not_running_test() {
  init().running
  |> should.equal(False)
}

pub fn verification_init_empty_history_test() {
  init().history
  |> should.equal([])
}

pub fn verification_init_no_proof_test() {
  init().latest_proof
  |> should.equal(None)
}

pub fn verification_init_empty_graph_checks_test() {
  init().graph_checks
  |> should.equal([])
}

pub fn verification_init_dag_counts_are_zero_test() {
  let m = init()
  m.dag_node_count |> should.equal(0)
  m.dag_edge_count |> should.equal(0)
}

// =============================================================================
// Lustre MVU — StartVerification
// =============================================================================

pub fn start_verification_sets_running_test() {
  let m = update(init(), StartVerification)
  m.running |> should.equal(True)
}

// =============================================================================
// Lustre MVU — ReportReceived
// =============================================================================

pub fn report_received_sets_last_report_test() {
  let metrics =
    OodaMetrics(
      agent_latency_ms: 20,
      intelligence_latency_ms: 70,
      compliance: True,
    )
  let report = generate_report(metrics, 14, 16)
  let m = update(init(), ReportReceived(report))
  m.last_report |> should.equal(Some(report))
}

pub fn report_received_clears_running_test() {
  let metrics =
    OodaMetrics(
      agent_latency_ms: 25,
      intelligence_latency_ms: 80,
      compliance: True,
    )
  let report = generate_report(metrics, 16, 16)
  let m0 = update(init(), StartVerification)
  m0.running |> should.equal(True)
  let m1 = update(m0, ReportReceived(report))
  m1.running |> should.equal(False)
}

pub fn report_received_appends_history_test() {
  let metrics =
    OodaMetrics(
      agent_latency_ms: 25,
      intelligence_latency_ms: 80,
      compliance: True,
    )
  let report = generate_report(metrics, 16, 16)
  let m = update(init(), ReportReceived(report))
  list.length(m.history) |> should.equal(1)
}

// =============================================================================
// Lustre MVU — ProofGenerated
// =============================================================================

pub fn proof_generated_sets_latest_proof_test() {
  let proof =
    ProofToken(
      dag_hash: "abc123",
      path: ["node-a", "node-b"],
      verified_at: 1_000_000,
      constraints_checked: ["SC-BOOT-008"],
      result: Verified,
    )
  let m = update(init(), ProofGenerated(proof))
  m.latest_proof |> should.equal(Some(proof))
}

pub fn proof_generated_appends_proof_history_test() {
  let proof =
    ProofToken(
      dag_hash: "def456",
      path: ["n1"],
      verified_at: 2_000_000,
      constraints_checked: [],
      result: Inconclusive,
    )
  let m = update(init(), ProofGenerated(proof))
  list.length(m.proof_history) |> should.equal(1)
}

// =============================================================================
// Lustre MVU — GraphChecksCompleted
// =============================================================================

pub fn graph_checks_completed_sets_checks_test() {
  let checks = [
    GraphCheck(name: "acyclicity", passed: True, details: "ok"),
    GraphCheck(name: "connectivity", passed: True, details: "ok"),
  ]
  let m = update(init(), GraphChecksCompleted(checks))
  m.graph_checks |> should.equal(checks)
}

// =============================================================================
// Lustre MVU — DagUpdated
// =============================================================================

pub fn dag_updated_sets_node_and_edge_count_test() {
  let m = update(init(), DagUpdated(node_count: 8, edge_count: 12))
  m.dag_node_count |> should.equal(8)
  m.dag_edge_count |> should.equal(12)
}

// =============================================================================
// Lustre MVU — all_checks_passed, latest_proof_verified
// =============================================================================

pub fn all_checks_passed_true_when_all_pass_test() {
  let checks = [
    GraphCheck(name: "acyclicity", passed: True, details: "ok"),
    GraphCheck(name: "connectivity", passed: True, details: "ok"),
  ]
  let m = update(init(), GraphChecksCompleted(checks))
  all_checks_passed(m) |> should.be_true()
}

pub fn all_checks_passed_false_when_one_fails_test() {
  let checks = [
    GraphCheck(name: "acyclicity", passed: True, details: "ok"),
    GraphCheck(name: "node_count", passed: False, details: "empty dag"),
  ]
  let m = update(init(), GraphChecksCompleted(checks))
  all_checks_passed(m) |> should.be_false()
}

pub fn all_checks_passed_true_when_no_checks_test() {
  // list.all([], _) returns True (vacuous truth)
  all_checks_passed(init()) |> should.be_true()
}

pub fn latest_proof_verified_true_test() {
  let proof =
    ProofToken(
      dag_hash: "ok",
      path: [],
      verified_at: 0,
      constraints_checked: [],
      result: Verified,
    )
  let m = update(init(), ProofGenerated(proof))
  latest_proof_verified(m) |> should.be_true()
}

pub fn latest_proof_verified_false_when_rejected_test() {
  let proof =
    ProofToken(
      dag_hash: "fail",
      path: [],
      verified_at: 0,
      constraints_checked: [],
      result: Rejected(reasons: ["cycle detected"]),
    )
  let m = update(init(), ProofGenerated(proof))
  latest_proof_verified(m) |> should.be_false()
}

pub fn latest_proof_verified_false_when_no_proof_test() {
  latest_proof_verified(init()) |> should.be_false()
}

// =============================================================================
// proof_result_string
// =============================================================================

pub fn proof_result_string_verified_test() {
  proof_result_string(Verified) |> should.equal("Verified")
}

pub fn proof_result_string_rejected_test() {
  proof_result_string(Rejected(reasons: ["bad edge"]))
  |> should.equal("Rejected")
}

pub fn proof_result_string_inconclusive_test() {
  proof_result_string(Inconclusive) |> should.equal("Inconclusive")
}

// =============================================================================
// Wisp API — proof_token_json
// =============================================================================

pub fn proof_token_json_contains_plane_test() {
  let proof =
    ProofToken(
      dag_hash: "hash-001",
      path: ["a", "b"],
      verified_at: 999,
      constraints_checked: ["SC-PROM-001"],
      result: Verified,
    )
  let j = verification_api.proof_token_json(proof)
  string.contains(j, "verification") |> should.be_true()
}

pub fn proof_token_json_contains_dag_hash_test() {
  let proof =
    ProofToken(
      dag_hash: "myhash",
      path: [],
      verified_at: 0,
      constraints_checked: [],
      result: Verified,
    )
  let j = verification_api.proof_token_json(proof)
  string.contains(j, "myhash") |> should.be_true()
}

// =============================================================================
// Wisp API — dag_status_json
// =============================================================================

pub fn dag_status_json_contains_node_count_test() {
  let j = verification_api.dag_status_json(7, 10, True)
  string.contains(j, "node_count") |> should.be_true()
}

pub fn dag_status_json_acyclic_true_test() {
  let j = verification_api.dag_status_json(3, 2, True)
  string.contains(j, "is_acyclic") |> should.be_true()
}

// =============================================================================
// Wisp API — graph_checks_json
// =============================================================================

pub fn graph_checks_json_empty_has_total_zero_test() {
  let j = verification_api.graph_checks_json([])
  string.contains(j, "\"total_count\":0") |> should.be_true()
}

pub fn graph_checks_json_contains_plane_test() {
  let j = verification_api.graph_checks_json([])
  string.contains(j, "verification") |> should.be_true()
}

// =============================================================================
// SwarmReport — fractal layer structure
// =============================================================================

pub fn swarm_report_has_eight_fractal_layers_test() {
  let metrics =
    OodaMetrics(
      agent_latency_ms: 25,
      intelligence_latency_ms: 80,
      compliance: True,
    )
  let report = generate_report(metrics, 16, 16)
  list.length(report.fractal_layers) |> should.equal(8)
}

pub fn swarm_report_layer_zero_exists_test() {
  let metrics =
    OodaMetrics(
      agent_latency_ms: 25,
      intelligence_latency_ms: 80,
      compliance: True,
    )
  let report = generate_report(metrics, 16, 16)
  let l0 = list.find(report.fractal_layers, fn(l) { l.layer == 0 })
  case l0 {
    Ok(_) -> True
    Error(_) -> False
  }
  |> should.be_true()
}

// =============================================================================
// TUI view — render
// =============================================================================

pub fn verification_render_contains_header_test() {
  let output = verification_view.render(init())
  string.contains(output, "VERIFICATION") |> should.be_true()
}

pub fn verification_render_no_proof_message_test() {
  let output = verification_view.render(init())
  string.contains(output, "No proof") |> should.be_true()
}

pub fn verification_render_with_proof_contains_hash_test() {
  let proof =
    ProofToken(
      dag_hash: "testhash42",
      path: ["x"],
      verified_at: 0,
      constraints_checked: [],
      result: Verified,
    )
  let m = update(init(), ProofGenerated(proof))
  let output = verification_view.render(m)
  string.contains(output, "testhash42") |> should.be_true()
}

pub fn verification_render_with_checks_contains_check_name_test() {
  let checks = [GraphCheck(name: "acyclicity", passed: True, details: "ok")]
  let m = update(init(), GraphChecksCompleted(checks))
  let output = verification_view.render(m)
  string.contains(output, "acyclicity") |> should.be_true()
}
