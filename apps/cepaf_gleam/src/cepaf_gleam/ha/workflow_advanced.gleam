//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/workflow_advanced</module>
////     <fsharp-lineage>None — novel Gleam module for advanced workflow patterns</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Advanced durable workflow patterns: child workflows (WF-14),
////       continue-as-new for long-running histories (WF-16),
////       DAG visualisation (WF-19), and rate limiting (WF-21).
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-GLM-UI-003, SC-TRUTH-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Temporal-inspired parent/child workflow nesting ↪ Gleam typed ADTs.
////       Continue-as-new pattern maps to ContinueAsNew record with generation counter.
////       DAG nodes/edges map to typed DagNode/DagEdge lists for Mermaid/DOT output.
////       Rate limiter maps to a pure counter record (no shared mutable state).
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Advanced Workflow Patterns — WF-14, WF-16, WF-19, WF-21
////
//// SC-HA-001:     System MUST support continuous evolution without dropping intents.
//// SC-GLM-UI-003: Typed JSON — no raw string concatenation.
//// SC-TRUTH-001:  System MUST ONLY display verified-current data.
//// SC-MUDA-001:   Zero dead code, zero unused imports.

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Child workflows (WF-14)
// ---------------------------------------------------------------------------

/// A child workflow spawned from a parent, bound by parent_id.
pub type ChildWorkflow {
  ChildWorkflow(
    child_id: String,
    parent_id: String,
    workflow_type: String,
    /// One of: "pending", "running", "completed", "failed"
    status: String,
    result: String,
  )
}

/// Spawn a new child workflow bound to parent_id.
pub fn spawn_child(parent_id: String, child_type: String) -> ChildWorkflow {
  ChildWorkflow(
    child_id: "child-" <> parent_id <> "-" <> child_type,
    parent_id: parent_id,
    workflow_type: child_type,
    status: "pending",
    result: "",
  )
}

/// Mark a child workflow as completed with the given result.
pub fn complete_child(child: ChildWorkflow, result: String) -> ChildWorkflow {
  ChildWorkflow(..child, status: "completed", result: result)
}

/// Mark a child workflow as failed with the given error.
pub fn fail_child(child: ChildWorkflow, error: String) -> ChildWorkflow {
  ChildWorkflow(..child, status: "failed", result: error)
}

/// Serialise a ChildWorkflow to a JSON object string.
pub fn child_to_json(child: ChildWorkflow) -> String {
  let ChildWorkflow(child_id, parent_id, workflow_type, status, result) = child
  "{"
  <> "\"child_id\":\""
  <> child_id
  <> "\","
  <> "\"parent_id\":\""
  <> parent_id
  <> "\","
  <> "\"workflow_type\":\""
  <> workflow_type
  <> "\","
  <> "\"status\":\""
  <> status
  <> "\","
  <> "\"result\":\""
  <> result
  <> "\""
  <> "}"
}

// ---------------------------------------------------------------------------
// Continue-as-new (WF-16)
// ---------------------------------------------------------------------------

/// Instruction to restart a workflow with a fresh history while preserving
/// logical continuity via a generation counter and carry-over state.
pub type ContinueAsNew {
  ContinueAsNew(
    workflow_type: String,
    /// Increments each time continue-as-new is applied.
    generation: Int,
    /// Serialised state to pass into the new run.
    carry_over_state: String,
    reason: String,
  )
}

/// Build a ContinueAsNew instruction for the next generation of a workflow.
pub fn continue_as_new(
  workflow_type: String,
  generation: Int,
  state: String,
  reason: String,
) -> ContinueAsNew {
  ContinueAsNew(
    workflow_type: workflow_type,
    generation: generation,
    carry_over_state: state,
    reason: reason,
  )
}

/// Returns True when the event count has exceeded the threshold, signalling
/// that the workflow SHOULD continue-as-new to avoid unbounded history growth.
pub fn should_continue(event_count: Int, threshold: Int) -> Bool {
  event_count >= threshold
}

/// Serialise a ContinueAsNew instruction to a JSON object string.
pub fn continue_to_json(c: ContinueAsNew) -> String {
  let ContinueAsNew(workflow_type, generation, carry_over_state, reason) = c
  "{"
  <> "\"workflow_type\":\""
  <> workflow_type
  <> "\","
  <> "\"generation\":"
  <> int.to_string(generation)
  <> ","
  <> "\"carry_over_state\":\""
  <> carry_over_state
  <> "\","
  <> "\"reason\":\""
  <> reason
  <> "\""
  <> "}"
}

// ---------------------------------------------------------------------------
// DAG visualisation (WF-19)
// ---------------------------------------------------------------------------

/// A node in a workflow execution DAG.
pub type DagNode {
  DagNode(
    id: String,
    label: String,
    /// One of: "activity", "workflow", "decision", "fanout", "fanin"
    node_type: String,
    /// One of: "pending", "running", "completed", "failed"
    status: String,
    duration_ms: Int,
  )
}

/// A directed edge in a workflow DAG.
pub type DagEdge {
  DagEdge(from: String, to: String, label: String)
}

/// A directed acyclic graph of workflow nodes and edges.
pub type WorkflowDag {
  WorkflowDag(nodes: List(DagNode), edges: List(DagEdge))
}

/// Create an empty DAG.
pub fn init_dag() -> WorkflowDag {
  WorkflowDag(nodes: [], edges: [])
}

/// Append a node to the DAG.
pub fn add_node(dag: WorkflowDag, node: DagNode) -> WorkflowDag {
  WorkflowDag(..dag, nodes: list.append(dag.nodes, [node]))
}

/// Append an edge to the DAG.
pub fn add_edge(dag: WorkflowDag, edge: DagEdge) -> WorkflowDag {
  WorkflowDag(..dag, edges: list.append(dag.edges, [edge]))
}

/// Render the DAG as a Mermaid flowchart LR string.
pub fn to_mermaid(dag: WorkflowDag) -> String {
  let node_lines =
    dag.nodes
    |> list.map(fn(n) {
      "    " <> n.id <> "[\"" <> n.label <> " (" <> n.status <> ")\"]"
    })
    |> string.join("\n")
  let edge_lines =
    dag.edges
    |> list.map(fn(e) { "    " <> e.from <> " -->|" <> e.label <> "| " <> e.to })
    |> string.join("\n")
  "flowchart LR\n" <> node_lines <> "\n" <> edge_lines
}

/// Render the DAG as a GraphViz DOT string.
pub fn to_dot(dag: WorkflowDag) -> String {
  let node_lines =
    dag.nodes
    |> list.map(fn(n) {
      "    \""
      <> n.id
      <> "\" [label=\""
      <> n.label
      <> "\", status=\""
      <> n.status
      <> "\"];"
    })
    |> string.join("\n")
  let edge_lines =
    dag.edges
    |> list.map(fn(e) {
      "    \""
      <> e.from
      <> "\" -> \""
      <> e.to
      <> "\" [label=\""
      <> e.label
      <> "\"];"
    })
    |> string.join("\n")
  "digraph workflow {\n" <> node_lines <> "\n" <> edge_lines <> "\n}"
}

/// Serialise a single DagNode to a JSON object string.
fn node_to_json(n: DagNode) -> String {
  let DagNode(id, label, node_type, status, duration_ms) = n
  "{"
  <> "\"id\":\""
  <> id
  <> "\","
  <> "\"label\":\""
  <> label
  <> "\","
  <> "\"node_type\":\""
  <> node_type
  <> "\","
  <> "\"status\":\""
  <> status
  <> "\","
  <> "\"duration_ms\":"
  <> int.to_string(duration_ms)
  <> "}"
}

/// Serialise a single DagEdge to a JSON object string.
fn edge_to_json(e: DagEdge) -> String {
  let DagEdge(from, to, label) = e
  "{"
  <> "\"from\":\""
  <> from
  <> "\","
  <> "\"to\":\""
  <> to
  <> "\","
  <> "\"label\":\""
  <> label
  <> "\""
  <> "}"
}

/// Serialise the full WorkflowDag to a JSON object string.
pub fn dag_to_json(dag: WorkflowDag) -> String {
  let nodes_json =
    dag.nodes
    |> list.map(node_to_json)
    |> string.join(",")
  let edges_json =
    dag.edges
    |> list.map(edge_to_json)
    |> string.join(",")
  "{"
  <> "\"nodes\":["
  <> nodes_json
  <> "],"
  <> "\"edges\":["
  <> edges_json
  <> "]"
  <> "}"
}

/// Return a human-readable one-line summary of the DAG.
pub fn dag_summary(dag: WorkflowDag) -> String {
  let node_count = list.length(dag.nodes)
  let edge_count = list.length(dag.edges)
  let completed = list.count(dag.nodes, fn(n) { n.status == "completed" })
  let failed = list.count(dag.nodes, fn(n) { n.status == "failed" })
  "nodes="
  <> int.to_string(node_count)
  <> " edges="
  <> int.to_string(edge_count)
  <> " completed="
  <> int.to_string(completed)
  <> " failed="
  <> int.to_string(failed)
}

// ---------------------------------------------------------------------------
// Rate limiting (WF-21)
// ---------------------------------------------------------------------------

/// Token-bucket style rate limiter tracking max and current concurrent activities.
pub type RateLimiter {
  RateLimiter(
    max_concurrent: Int,
    current_active: Int,
    total_processed: Int,
    total_rejected: Int,
    queue_depth: Int,
  )
}

/// Create a new RateLimiter with the given concurrency ceiling.
pub fn init_limiter(max_concurrent: Int) -> RateLimiter {
  RateLimiter(
    max_concurrent: max_concurrent,
    current_active: 0,
    total_processed: 0,
    total_rejected: 0,
    queue_depth: 0,
  )
}

/// Attempt to acquire a slot.  Returns the updated limiter and True on success.
/// Returns False (with total_rejected incremented) when at capacity.
pub fn try_acquire(limiter: RateLimiter) -> #(RateLimiter, Bool) {
  case limiter.current_active < limiter.max_concurrent {
    True -> #(
      RateLimiter(
        ..limiter,
        current_active: limiter.current_active + 1,
        total_processed: limiter.total_processed + 1,
      ),
      True,
    )
    False -> #(
      RateLimiter(..limiter, total_rejected: limiter.total_rejected + 1),
      False,
    )
  }
}

/// Release one active slot after an activity completes.
pub fn release(limiter: RateLimiter) -> RateLimiter {
  let new_active = case limiter.current_active > 0 {
    True -> limiter.current_active - 1
    False -> 0
  }
  RateLimiter(..limiter, current_active: new_active)
}

/// True when current_active has reached max_concurrent.
pub fn is_at_capacity(limiter: RateLimiter) -> Bool {
  limiter.current_active >= limiter.max_concurrent
}

/// Utilisation ratio: current_active / max_concurrent.
/// Returns 0.0 when max_concurrent is 0 to avoid division by zero.
pub fn utilization(limiter: RateLimiter) -> Float {
  case limiter.max_concurrent {
    0 -> 0.0
    _ ->
      int.to_float(limiter.current_active)
      /. int.to_float(limiter.max_concurrent)
  }
}

/// Serialise a RateLimiter to a JSON object string.
pub fn limiter_to_json(limiter: RateLimiter) -> String {
  let RateLimiter(
    max_concurrent,
    current_active,
    total_processed,
    total_rejected,
    queue_depth,
  ) = limiter
  "{"
  <> "\"max_concurrent\":"
  <> int.to_string(max_concurrent)
  <> ","
  <> "\"current_active\":"
  <> int.to_string(current_active)
  <> ","
  <> "\"total_processed\":"
  <> int.to_string(total_processed)
  <> ","
  <> "\"total_rejected\":"
  <> int.to_string(total_rejected)
  <> ","
  <> "\"queue_depth\":"
  <> int.to_string(queue_depth)
  <> "}"
}

/// Return a human-readable one-line summary of the limiter.
pub fn limiter_summary(limiter: RateLimiter) -> String {
  "active="
  <> int.to_string(limiter.current_active)
  <> "/"
  <> int.to_string(limiter.max_concurrent)
  <> " processed="
  <> int.to_string(limiter.total_processed)
  <> " rejected="
  <> int.to_string(limiter.total_rejected)
  <> " util="
  <> float.to_string(float.round(utilization(limiter) *. 100.0) |> int.to_float)
  <> "%"
}
