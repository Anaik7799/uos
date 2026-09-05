//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/explanation_viz</module>
////     <fsharp-lineage>None — novel explainability visualisation (F18)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Explainability graph construction and multi-format rendering for RETE-UL
////       rule decisions. Converts rule chains and supporting facts into a
////       directed ExplanationGraph, then renders to text tree, Mermaid diagram,
////       DOT graph, or JSON. Zero I/O — pure functional state-in / state-out.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-BIO-EVO-001, SC-MUDA-001, SC-FUNC-001, SC-GLM-UI-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       RETE-UL rule chain ↪ ExplanationGraph (nodes + edges).
////       Each rule becomes a RuleNode; each fact becomes a FactNode;
////       the final decision becomes a DecisionNode.
////     </morphism>
////     <morphism type="surjective" loss="graphviz-attributes">
////       Full DOT attribute set ↠ minimal digraph syntax.
////       Mitigation: Only id/label exported; styling left to caller.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// EXPLANATION VISUALISATION — F18
//// SC-BIO-EVO-001: Homeostasis — operator must understand why a decision was made
////
//// Builds ExplanationGraph from RETE-UL outputs and renders to four formats:
////   TextTree      — ASCII-indented human-readable tree
////   MermaidDiagram — Mermaid graph TD for web rendering
////   DotGraph      — Graphviz digraph for pipeline tools
////   JsonGraph     — JSON for API consumers
////
//// STAMP: SC-BIO-EVO-001, SC-MUDA-001, SC-FUNC-001, SC-GLM-UI-001

import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/string

// ---------------------------------------------------------------------------
// Public Types
// ---------------------------------------------------------------------------

/// Semantic kind of a node in the explanation graph
pub type ExplanationNodeKind {
  RuleNode
  FactNode
  DecisionNode
  CausalNode
}

/// A single node in the explanation graph
pub type ExplanationNode {
  ExplanationNode(
    id: String,
    label: String,
    kind: ExplanationNodeKind,
    weight: Float,
  )
}

/// A directed edge between two nodes
pub type ExplanationEdge {
  ExplanationEdge(from: String, to: String, label: String, strength: Float)
}

/// Complete explanation graph for a single decision
pub type ExplanationGraph {
  ExplanationGraph(
    nodes: List(ExplanationNode),
    edges: List(ExplanationEdge),
    root_decision: String,
  )
}

/// Output format for graph rendering
pub type ExplanationFormat {
  TextTree
  MermaidDiagram
  DotGraph
  JsonGraph
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

/// Create an empty explanation graph for the given root decision label
pub fn graph_new(root_decision: String) -> ExplanationGraph {
  ExplanationGraph(nodes: [], edges: [], root_decision: root_decision)
}

/// Add a node to the graph (appended; duplicates allowed for flexibility)
pub fn add_node(
  graph: ExplanationGraph,
  node: ExplanationNode,
) -> ExplanationGraph {
  ExplanationGraph(..graph, nodes: list.flatten([graph.nodes, [node]]))
}

/// Add a directed edge to the graph
pub fn add_edge(
  graph: ExplanationGraph,
  edge: ExplanationEdge,
) -> ExplanationGraph {
  ExplanationGraph(..graph, edges: list.flatten([graph.edges, [edge]]))
}

// ---------------------------------------------------------------------------
// Auto-Construction from Rule Chain
// ---------------------------------------------------------------------------

/// Build an explanation graph from a RETE-UL rule evaluation result.
///
/// Creates:
///   - one RuleNode  for rule_name
///   - one FactNode  per fact in facts
///   - one DecisionNode for decision
///   - edges: each fact -> rule, rule -> decision
pub fn from_rule_chain(
  rule_name: String,
  facts: List(String),
  decision: String,
) -> ExplanationGraph {
  let rule_id = "rule_" <> rule_name
  let decision_id = "decision_" <> decision
  let rule_node =
    ExplanationNode(id: rule_id, label: rule_name, kind: RuleNode, weight: 0.8)
  let decision_node =
    ExplanationNode(
      id: decision_id,
      label: decision,
      kind: DecisionNode,
      weight: 1.0,
    )
  let fact_nodes =
    list.map(facts, fn(f) {
      ExplanationNode(id: "fact_" <> f, label: f, kind: FactNode, weight: 0.5)
    })
  let fact_to_rule_edges =
    list.map(facts, fn(f) {
      ExplanationEdge(
        from: "fact_" <> f,
        to: rule_id,
        label: "supports",
        strength: 0.7,
      )
    })
  let rule_to_decision =
    ExplanationEdge(
      from: rule_id,
      to: decision_id,
      label: "fires",
      strength: 1.0,
    )
  let all_nodes = list.flatten([fact_nodes, [rule_node], [decision_node]])
  let all_edges = list.flatten([fact_to_rule_edges, [rule_to_decision]])
  ExplanationGraph(nodes: all_nodes, edges: all_edges, root_decision: decision)
}

// ---------------------------------------------------------------------------
// Rendering — dispatch
// ---------------------------------------------------------------------------

/// Render the graph to the requested format
pub fn render(graph: ExplanationGraph, format: ExplanationFormat) -> String {
  case format {
    TextTree -> render_text_tree(graph)
    MermaidDiagram -> render_mermaid(graph)
    DotGraph -> render_dot(graph)
    JsonGraph -> render_json(graph)
  }
}

// ---------------------------------------------------------------------------
// Rendering — TextTree
// ---------------------------------------------------------------------------

/// Render as an ASCII-indented text tree
pub fn render_text_tree(graph: ExplanationGraph) -> String {
  let header = "Decision: " <> graph.root_decision
  let node_lines =
    list.map(graph.nodes, fn(n) {
      "  [" <> node_kind_to_string(n.kind) <> "] " <> n.label
    })
  let edge_lines =
    list.map(graph.edges, fn(e) {
      "  " <> e.from <> " --" <> e.label <> "--> " <> e.to
    })
  let all_lines = list.flatten([[header], node_lines, ["Edges:"], edge_lines])
  string.join(all_lines, "\n")
}

// ---------------------------------------------------------------------------
// Rendering — Mermaid
// ---------------------------------------------------------------------------

/// Render as a Mermaid graph TD diagram
pub fn render_mermaid(graph: ExplanationGraph) -> String {
  let header = "graph TD"
  let node_lines =
    list.map(graph.nodes, fn(n) {
      "  " <> sanitise_id(n.id) <> "[" <> n.label <> "]"
    })
  let edge_lines =
    list.map(graph.edges, fn(e) {
      "  "
      <> sanitise_id(e.from)
      <> " -->|"
      <> e.label
      <> "| "
      <> sanitise_id(e.to)
    })
  let all_lines = list.flatten([[header], node_lines, edge_lines])
  string.join(all_lines, "\n")
}

// ---------------------------------------------------------------------------
// Rendering — DOT
// ---------------------------------------------------------------------------

/// Render as a Graphviz digraph
pub fn render_dot(graph: ExplanationGraph) -> String {
  let header = "digraph explanation {"
  let node_lines =
    list.map(graph.nodes, fn(n) {
      "  " <> sanitise_id(n.id) <> " [label=\"" <> n.label <> "\"];"
    })
  let edge_lines =
    list.map(graph.edges, fn(e) {
      "  "
      <> sanitise_id(e.from)
      <> " -> "
      <> sanitise_id(e.to)
      <> " [label=\""
      <> e.label
      <> "\"];"
    })
  let footer = "}"
  let all_lines = list.flatten([[header], node_lines, edge_lines, [footer]])
  string.join(all_lines, "\n")
}

// ---------------------------------------------------------------------------
// Rendering — JSON
// ---------------------------------------------------------------------------

/// Render as a JSON object (hand-crafted, no gleam/json dependency needed here)
pub fn render_json(graph: ExplanationGraph) -> String {
  let node_jsons =
    list.map(graph.nodes, fn(n) {
      "{"
      <> "\"id\":\""
      <> n.id
      <> "\","
      <> "\"label\":\""
      <> n.label
      <> "\","
      <> "\"kind\":\""
      <> node_kind_to_string(n.kind)
      <> "\","
      <> "\"weight\":"
      <> float.to_string(n.weight)
      <> "}"
    })
  let edge_jsons =
    list.map(graph.edges, fn(e) {
      "{"
      <> "\"from\":\""
      <> e.from
      <> "\","
      <> "\"to\":\""
      <> e.to
      <> "\","
      <> "\"label\":\""
      <> e.label
      <> "\","
      <> "\"strength\":"
      <> float.to_string(e.strength)
      <> "}"
    })
  "{"
  <> "\"root_decision\":\""
  <> graph.root_decision
  <> "\","
  <> "\"nodes\":["
  <> string.join(node_jsons, ",")
  <> "],"
  <> "\"edges\":["
  <> string.join(edge_jsons, ",")
  <> "]}"
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

/// Number of nodes in the graph
pub fn node_count(graph: ExplanationGraph) -> Int {
  list.length(graph.nodes)
}

/// Number of edges in the graph
pub fn edge_count(graph: ExplanationGraph) -> Int {
  list.length(graph.edges)
}

/// Nodes sorted by weight descending — highest-weight first
pub fn importance_ranking(graph: ExplanationGraph) -> List(#(String, Float)) {
  let pairs = list.map(graph.nodes, fn(n) { #(n.label, n.weight) })
  list.sort(pairs, fn(a, b) {
    case a.1 >. b.1 {
      True -> order.Lt
      False ->
        case a.1 <. b.1 {
          True -> order.Gt
          False -> order.Eq
        }
    }
  })
}

/// One-line summary of the graph
pub fn summary(graph: ExplanationGraph) -> String {
  "ExplanationGraph["
  <> graph.root_decision
  <> "] nodes="
  <> int.to_string(node_count(graph))
  <> " edges="
  <> int.to_string(edge_count(graph))
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn node_kind_to_string(kind: ExplanationNodeKind) -> String {
  case kind {
    RuleNode -> "rule"
    FactNode -> "fact"
    DecisionNode -> "decision"
    CausalNode -> "causal"
  }
}

/// Replace characters that break Mermaid/DOT IDs
fn sanitise_id(id: String) -> String {
  id
  |> string.replace(" ", "_")
  |> string.replace("-", "_")
  |> string.replace(".", "_")
}
