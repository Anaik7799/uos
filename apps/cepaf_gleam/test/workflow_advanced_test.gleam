/// Advanced workflow pattern tests — WF-14, WF-16, WF-19, WF-21
/// Layer: L4_SYSTEM
/// STAMP: SC-HA-001, SC-GLM-UI-003, SC-TRUTH-001, SC-MUDA-001
import cepaf_gleam/ha/workflow_advanced.{
  DagEdge, DagNode, RateLimiter, add_edge, add_node, child_to_json,
  complete_child, continue_as_new, continue_to_json, dag_summary, dag_to_json,
  fail_child, init_dag, init_limiter, is_at_capacity, limiter_summary,
  limiter_to_json, release, should_continue, spawn_child, to_dot, to_mermaid,
  try_acquire, utilization,
}
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// spawn_child / complete_child / fail_child
// ---------------------------------------------------------------------------

pub fn spawn_child_sets_pending_status_test() {
  let child = spawn_child("wf-parent-1", "health_check")
  child.status |> should.equal("pending")
}

pub fn spawn_child_binds_parent_id_test() {
  let child = spawn_child("wf-parent-2", "deploy")
  child.parent_id |> should.equal("wf-parent-2")
}

pub fn spawn_child_sets_workflow_type_test() {
  let child = spawn_child("wf-parent-3", "ooda_cycle")
  child.workflow_type |> should.equal("ooda_cycle")
}

pub fn spawn_child_result_is_empty_test() {
  let child = spawn_child("wf-parent-4", "preflight")
  child.result |> should.equal("")
}

pub fn complete_child_sets_completed_status_test() {
  let child = spawn_child("wf-p", "act") |> complete_child("ok")
  child.status |> should.equal("completed")
}

pub fn complete_child_preserves_result_test() {
  let child = spawn_child("wf-p", "act") |> complete_child("all_good")
  child.result |> should.equal("all_good")
}

pub fn fail_child_sets_failed_status_test() {
  let child = spawn_child("wf-p", "act") |> fail_child("timeout")
  child.status |> should.equal("failed")
}

pub fn fail_child_preserves_error_test() {
  let child = spawn_child("wf-p", "act") |> fail_child("nif_crash")
  child.result |> should.equal("nif_crash")
}

pub fn child_to_json_contains_child_id_test() {
  let child = spawn_child("wf-p", "sync")
  child_to_json(child) |> string.contains("child_id") |> should.be_true()
}

pub fn child_to_json_contains_parent_id_test() {
  let child = spawn_child("wf-q", "sync")
  child_to_json(child) |> string.contains("wf-q") |> should.be_true()
}

pub fn child_to_json_contains_status_test() {
  let child = spawn_child("wf-r", "sync") |> complete_child("done")
  child_to_json(child) |> string.contains("completed") |> should.be_true()
}

// ---------------------------------------------------------------------------
// continue_as_new / should_continue
// ---------------------------------------------------------------------------

pub fn continue_as_new_preserves_generation_test() {
  let c = continue_as_new("ooda_loop", 3, "{}", "history_full")
  c.generation |> should.equal(3)
}

pub fn continue_as_new_preserves_type_test() {
  let c = continue_as_new("deploy_pipeline", 1, "{}", "reset")
  c.workflow_type |> should.equal("deploy_pipeline")
}

pub fn continue_as_new_preserves_state_test() {
  let c = continue_as_new("sync", 2, "{\"key\":\"val\"}", "size")
  c.carry_over_state |> should.equal("{\"key\":\"val\"}")
}

pub fn continue_as_new_preserves_reason_test() {
  let c = continue_as_new("sync", 1, "", "history_too_large")
  c.reason |> should.equal("history_too_large")
}

pub fn should_continue_true_at_threshold_test() {
  should_continue(1000, 1000) |> should.be_true()
}

pub fn should_continue_true_above_threshold_test() {
  should_continue(1500, 1000) |> should.be_true()
}

pub fn should_continue_false_below_threshold_test() {
  should_continue(500, 1000) |> should.be_false()
}

pub fn continue_to_json_contains_generation_test() {
  let c = continue_as_new("t", 7, "", "r")
  continue_to_json(c) |> string.contains("7") |> should.be_true()
}

pub fn continue_to_json_contains_workflow_type_test() {
  let c = continue_as_new("my_workflow", 1, "", "r")
  continue_to_json(c) |> string.contains("my_workflow") |> should.be_true()
}

// ---------------------------------------------------------------------------
// DAG — init / add_node / add_edge
// ---------------------------------------------------------------------------

pub fn init_dag_has_empty_nodes_test() {
  init_dag().nodes |> should.equal([])
}

pub fn init_dag_has_empty_edges_test() {
  init_dag().edges |> should.equal([])
}

pub fn add_node_increases_node_count_test() {
  let node =
    DagNode(
      id: "n1",
      label: "Fetch",
      node_type: "activity",
      status: "completed",
      duration_ms: 50,
    )
  let dag = init_dag() |> add_node(node)
  dag.nodes |> should.equal([node])
}

pub fn add_edge_increases_edge_count_test() {
  let edge = DagEdge(from: "n1", to: "n2", label: "ok")
  let dag = init_dag() |> add_edge(edge)
  dag.edges |> should.equal([edge])
}

pub fn dag_summary_reflects_counts_test() {
  let node =
    DagNode(
      id: "n1",
      label: "L",
      node_type: "activity",
      status: "completed",
      duration_ms: 10,
    )
  let edge = DagEdge(from: "n1", to: "n2", label: "")
  let dag = init_dag() |> add_node(node) |> add_edge(edge)
  dag_summary(dag) |> string.contains("nodes=1") |> should.be_true()
}

pub fn dag_summary_counts_completed_test() {
  let node =
    DagNode(
      id: "n1",
      label: "L",
      node_type: "activity",
      status: "completed",
      duration_ms: 0,
    )
  let dag = init_dag() |> add_node(node)
  dag_summary(dag) |> string.contains("completed=1") |> should.be_true()
}

pub fn dag_summary_counts_failed_test() {
  let node =
    DagNode(
      id: "n1",
      label: "L",
      node_type: "activity",
      status: "failed",
      duration_ms: 0,
    )
  let dag = init_dag() |> add_node(node)
  dag_summary(dag) |> string.contains("failed=1") |> should.be_true()
}

pub fn to_mermaid_contains_flowchart_keyword_test() {
  to_mermaid(init_dag()) |> string.contains("flowchart") |> should.be_true()
}

pub fn to_mermaid_contains_node_label_test() {
  let node =
    DagNode(
      id: "step1",
      label: "CheckHealth",
      node_type: "activity",
      status: "running",
      duration_ms: 0,
    )
  let dag = init_dag() |> add_node(node)
  to_mermaid(dag) |> string.contains("CheckHealth") |> should.be_true()
}

pub fn to_mermaid_contains_edge_arrow_test() {
  let edge = DagEdge(from: "a", to: "b", label: "next")
  let dag = init_dag() |> add_edge(edge)
  to_mermaid(dag) |> string.contains("-->") |> should.be_true()
}

pub fn to_dot_contains_digraph_keyword_test() {
  to_dot(init_dag()) |> string.contains("digraph") |> should.be_true()
}

pub fn to_dot_contains_node_id_test() {
  let node =
    DagNode(
      id: "mynode",
      label: "L",
      node_type: "workflow",
      status: "pending",
      duration_ms: 0,
    )
  let dag = init_dag() |> add_node(node)
  to_dot(dag) |> string.contains("mynode") |> should.be_true()
}

pub fn dag_to_json_contains_nodes_key_test() {
  dag_to_json(init_dag()) |> string.contains("nodes") |> should.be_true()
}

pub fn dag_to_json_contains_edges_key_test() {
  dag_to_json(init_dag()) |> string.contains("edges") |> should.be_true()
}

pub fn dag_to_json_contains_node_id_test() {
  let node =
    DagNode(
      id: "json_node",
      label: "L",
      node_type: "activity",
      status: "completed",
      duration_ms: 5,
    )
  let dag = init_dag() |> add_node(node)
  dag_to_json(dag) |> string.contains("json_node") |> should.be_true()
}

// ---------------------------------------------------------------------------
// Rate limiter
// ---------------------------------------------------------------------------

pub fn init_limiter_sets_max_concurrent_test() {
  init_limiter(5).max_concurrent |> should.equal(5)
}

pub fn init_limiter_starts_with_zero_active_test() {
  init_limiter(5).current_active |> should.equal(0)
}

pub fn try_acquire_succeeds_when_below_capacity_test() {
  let #(_, acquired) = try_acquire(init_limiter(3))
  acquired |> should.be_true()
}

pub fn try_acquire_increments_current_active_test() {
  let #(l, _) = try_acquire(init_limiter(3))
  l.current_active |> should.equal(1)
}

pub fn try_acquire_increments_total_processed_test() {
  let #(l, _) = try_acquire(init_limiter(3))
  l.total_processed |> should.equal(1)
}

pub fn try_acquire_fails_at_capacity_test() {
  let limiter =
    RateLimiter(
      max_concurrent: 2,
      current_active: 2,
      total_processed: 2,
      total_rejected: 0,
      queue_depth: 0,
    )
  let #(_, acquired) = try_acquire(limiter)
  acquired |> should.be_false()
}

pub fn try_acquire_increments_rejected_when_full_test() {
  let limiter =
    RateLimiter(
      max_concurrent: 1,
      current_active: 1,
      total_processed: 1,
      total_rejected: 0,
      queue_depth: 0,
    )
  let #(l, _) = try_acquire(limiter)
  l.total_rejected |> should.equal(1)
}

pub fn release_decrements_active_test() {
  let #(l, _) = try_acquire(init_limiter(3))
  release(l).current_active |> should.equal(0)
}

pub fn release_does_not_go_below_zero_test() {
  let l = init_limiter(3)
  release(l).current_active |> should.equal(0)
}

pub fn is_at_capacity_true_when_full_test() {
  let limiter =
    RateLimiter(
      max_concurrent: 2,
      current_active: 2,
      total_processed: 2,
      total_rejected: 0,
      queue_depth: 0,
    )
  is_at_capacity(limiter) |> should.be_true()
}

pub fn is_at_capacity_false_when_not_full_test() {
  is_at_capacity(init_limiter(5)) |> should.be_false()
}

pub fn utilization_zero_for_empty_limiter_test() {
  utilization(init_limiter(4)) |> should.equal(0.0)
}

pub fn utilization_one_when_fully_loaded_test() {
  let limiter =
    RateLimiter(
      max_concurrent: 4,
      current_active: 4,
      total_processed: 4,
      total_rejected: 0,
      queue_depth: 0,
    )
  utilization(limiter) |> should.equal(1.0)
}

pub fn utilization_handles_zero_max_test() {
  let limiter =
    RateLimiter(
      max_concurrent: 0,
      current_active: 0,
      total_processed: 0,
      total_rejected: 0,
      queue_depth: 0,
    )
  utilization(limiter) |> should.equal(0.0)
}

pub fn limiter_to_json_contains_max_concurrent_test() {
  limiter_to_json(init_limiter(10))
  |> string.contains("max_concurrent")
  |> should.be_true()
}

pub fn limiter_to_json_contains_value_test() {
  limiter_to_json(init_limiter(10))
  |> string.contains("10")
  |> should.be_true()
}

pub fn limiter_summary_contains_active_test() {
  limiter_summary(init_limiter(8))
  |> string.contains("active=0/8")
  |> should.be_true()
}

pub fn limiter_summary_contains_processed_test() {
  let #(l, _) = try_acquire(init_limiter(3))
  limiter_summary(l) |> string.contains("processed=1") |> should.be_true()
}
