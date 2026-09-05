/// Explanation Visualisation — 15-test suite
/// Layer: L5_COGNITIVE
/// STAMP: SC-BIO-EVO-001, SC-MUDA-001, SC-GLM-UI-001
///
/// SC-BIO-EVO-001: Homeostasis — operator must understand why a decision was made
import cepaf_gleam/ha/explanation_viz.{
  DecisionNode, DotGraph, ExplanationEdge, ExplanationNode, FactNode, JsonGraph,
  MermaidDiagram, RuleNode, TextTree, add_edge, add_node, edge_count,
  from_rule_chain, graph_new, importance_ranking, node_count, render, render_dot,
  render_json, render_mermaid, render_text_tree, summary,
}
import gleam/string
import gleeunit/should

// ===========================================================================
// Constructors
// ===========================================================================

pub fn graph_new_is_empty_test() {
  let g = graph_new("restart_container")
  node_count(g) |> should.equal(0)
  edge_count(g) |> should.equal(0)
  g.root_decision |> should.equal("restart_container")
}

pub fn add_node_increments_count_test() {
  let g = graph_new("d1")
  let n =
    ExplanationNode(id: "n1", label: "rule_a", kind: RuleNode, weight: 0.9)
  let g2 = add_node(g, n)
  node_count(g2) |> should.equal(1)
}

pub fn add_edge_increments_count_test() {
  let g = graph_new("d1")
  let e =
    ExplanationEdge(from: "n1", to: "n2", label: "supports", strength: 0.8)
  let g2 = add_edge(g, e)
  edge_count(g2) |> should.equal(1)
}

// ===========================================================================
// from_rule_chain
// ===========================================================================

pub fn from_rule_chain_creates_correct_node_count_test() {
  // 2 facts + 1 rule + 1 decision = 4 nodes
  let g = from_rule_chain("EmergencyStop", ["cpu_high", "quorum_lost"], "halt")
  node_count(g) |> should.equal(4)
}

pub fn from_rule_chain_creates_correct_edge_count_test() {
  // 2 fact→rule edges + 1 rule→decision edge = 3 edges
  let g = from_rule_chain("EmergencyStop", ["cpu_high", "quorum_lost"], "halt")
  edge_count(g) |> should.equal(3)
}

pub fn from_rule_chain_root_decision_set_test() {
  let g = from_rule_chain("Rule", ["fact1"], "my_decision")
  g.root_decision |> should.equal("my_decision")
}

pub fn from_rule_chain_single_fact_test() {
  // 1 fact + 1 rule + 1 decision = 3 nodes; 1 + 1 = 2 edges
  let g = from_rule_chain("R", ["f1"], "dec")
  node_count(g) |> should.equal(3)
  edge_count(g) |> should.equal(2)
}

// ===========================================================================
// Rendering — TextTree
// ===========================================================================

pub fn render_text_tree_contains_decision_test() {
  let g = from_rule_chain("Rule", ["fact1"], "halt")
  let txt = render_text_tree(g)
  txt |> string.contains("halt") |> should.equal(True)
}

pub fn render_dispatch_text_tree_test() {
  let g = from_rule_chain("R", ["f"], "d")
  render(g, TextTree) |> string.contains("Decision:") |> should.equal(True)
}

// ===========================================================================
// Rendering — Mermaid
// ===========================================================================

pub fn render_mermaid_starts_with_graph_td_test() {
  let g = from_rule_chain("R", ["f"], "d")
  let txt = render_mermaid(g)
  txt |> string.starts_with("graph TD") |> should.equal(True)
}

pub fn render_dispatch_mermaid_test() {
  let g = from_rule_chain("R", ["f"], "d")
  render(g, MermaidDiagram)
  |> string.starts_with("graph TD")
  |> should.equal(True)
}

// ===========================================================================
// Rendering — DOT
// ===========================================================================

pub fn render_dot_starts_with_digraph_test() {
  let g = from_rule_chain("R", ["f"], "d")
  let txt = render_dot(g)
  txt |> string.starts_with("digraph explanation {") |> should.equal(True)
}

pub fn render_dispatch_dot_test() {
  let g = from_rule_chain("R", ["f"], "d")
  render(g, DotGraph) |> string.starts_with("digraph") |> should.equal(True)
}

// ===========================================================================
// Rendering — JSON
// ===========================================================================

pub fn render_json_contains_root_decision_test() {
  let g = from_rule_chain("R", ["f"], "my_halt")
  let txt = render_json(g)
  txt |> string.contains("my_halt") |> should.equal(True)
}

pub fn render_dispatch_json_test() {
  let g = from_rule_chain("R", ["f"], "d")
  render(g, JsonGraph) |> string.contains("nodes") |> should.equal(True)
}

// ===========================================================================
// Importance Ranking & Summary
// ===========================================================================

pub fn importance_ranking_highest_weight_first_test() {
  let g =
    graph_new("d")
    |> add_node(ExplanationNode(
      id: "a",
      label: "low",
      kind: FactNode,
      weight: 0.2,
    ))
    |> add_node(ExplanationNode(
      id: "b",
      label: "high",
      kind: DecisionNode,
      weight: 1.0,
    ))
  let ranked = importance_ranking(g)
  case ranked {
    [#(first, _), ..] -> first |> should.equal("high")
    [] -> should.fail()
  }
}

pub fn summary_non_empty_test() {
  let g = from_rule_chain("R", ["f1", "f2"], "decision")
  summary(g) |> should.not_equal("")
}
