// ==============================================================================
// Unified Operational System (UOS) - Google ADK Engine Test Suite
//
// Tests ADK Agent, Graph Workflow, Session State, Memory, and Evaluation.
// ==============================================================================

import cepaf_gleam/adk/adk_core.{
  AdkEvalCriterion, AdkMessage, AgentNode, Always, AutonomousMode, BeforeAgent,
  ChatMode, DecisionNode, EpisodicMemory, OnSuccess, RoleSystem, RoleUser,
  SemanticMemory, TaskMode, ToolNode, WorkflowEdge, WorkflowNode,
  agent_mode_to_string, append_message, encode_agent_json,
  encode_eval_report_json, evaluate_agent_trajectory, get_state_var,
  lifecycle_hook_phase_to_string, memory_type_to_string, message_role_to_string,
  new_agent, new_session, set_state_var, validate_workflow_graph,
}
import gleam/string

pub fn adk_agent_creation_test() {
  let agent =
    new_agent(
      "c3i-sdlc-graph-orchestrator",
      "C3I SDLC Graph Workflow Orchestrator Agent",
      "google/gemini-2.5-flash",
      AutonomousMode,
      "You orchestrate multi-agent graph workflows.",
      ["mcp_zenoh_bus", "a2a_delegate"],
    )

  let assert True = agent.id == "c3i-sdlc-graph-orchestrator"
  let assert True = agent.mode == AutonomousMode
  let assert True = agent_mode_to_string(agent.mode) == "autonomous"
  let assert True = agent_mode_to_string(ChatMode) == "chat"
  let assert True = agent_mode_to_string(TaskMode) == "task"

  let json_str = encode_agent_json(agent)
  let assert True = string.contains(json_str, "c3i-sdlc-graph-orchestrator")
  let assert True = string.contains(json_str, "autonomous")
}

pub fn adk_session_and_memory_test() {
  let session =
    new_session("sess-101", "agent-01", "2026-09-06T10:45:00.000000Z")
  let assert True = session.session_id == "sess-101"

  let msg1 =
    AdkMessage(
      id: "msg-01",
      role: RoleSystem,
      content: "System prompt active",
      tool_calls: [],
      timestamp: "2026-09-06T10:45:01.000000Z",
    )
  let msg2 =
    AdkMessage(
      id: "msg-02",
      role: RoleUser,
      content: "Run OODA loop cycle",
      tool_calls: [],
      timestamp: "2026-09-06T10:45:02.000000Z",
    )

  let s2 = append_message(session, msg1)
  let s3 = append_message(s2, msg2)
  let assert True = s3.updated_at == "2026-09-06T10:45:02.000000Z"

  let s4 = set_state_var(s3, "iteration", "1")
  let s5 = set_state_var(s4, "status", "executing")
  let assert Ok("1") = get_state_var(s5, "iteration")
  let assert Ok("executing") = get_state_var(s5, "status")
  let assert Error(Nil) = get_state_var(s5, "unknown_var")

  let assert True = message_role_to_string(RoleSystem) == "system"
  let assert True = memory_type_to_string(EpisodicMemory) == "episodic"
  let assert True = memory_type_to_string(SemanticMemory) == "semantic"
  let assert True = lifecycle_hook_phase_to_string(BeforeAgent) == "before_agent"
}

pub fn adk_workflow_graph_test() {
  let node_entry =
    WorkflowNode("node-0", "Start", AgentNode("c3i-sdlc-architect"))
  let node_tool =
    WorkflowNode("node-1", "Compile Code", ToolNode("beam_compiler"))
  let node_decision =
    WorkflowNode("node-2", "Review Gate", DecisionNode("score > 0.9"))

  let edge1 = WorkflowEdge("node-0", "node-1", Always)
  let edge2 = WorkflowEdge("node-1", "node-2", OnSuccess)

  let graph =
    adk_core.AdkWorkflowGraph(
      id: "wf-sdlc-01",
      name: "SDLC Synthesis Pipeline",
      nodes: [node_entry, node_tool, node_decision],
      edges: [edge1, edge2],
      entry_node_id: "node-0",
    )

  let assert True = validate_workflow_graph(graph)
}

pub fn adk_eval_trajectory_test() {
  let criterion1 =
    AdkEvalCriterion(
      id: "crit-01",
      name: "Zero-Muda Purity",
      description: "Must verify 0 Bevy and 0 Graphite",
      weight: 1.0,
      expected_pattern: "Zero-Muda Purity: 0 Bevy, 0 Graphite",
    )
  let criterion2 =
    AdkEvalCriterion(
      id: "crit-02",
      name: "Storage Safety",
      description: "Must verify locked serial 25503L801736",
      weight: 1.0,
      expected_pattern: "25503L801736",
    )

  let output =
    "Agent log: Zero-Muda Purity: 0 Bevy, 0 Graphite verified. Storage serial 25503L801736 locked."

  let report =
    evaluate_agent_trajectory(
      "eval-run-001",
      "c3i-verification-adk-eval",
      output,
      [criterion1, criterion2],
    )

  let assert True = report.passed == True
  let assert True = report.total_criteria == 2
  let assert True = report.passed_criteria == 2
  let assert True = report.score == 1.0

  let json_str = encode_eval_report_json(report)
  let assert True = string.contains(json_str, "eval-run-001")
  let assert True = string.contains(json_str, "0.94")
}
