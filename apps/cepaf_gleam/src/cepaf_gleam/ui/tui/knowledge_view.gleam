/// TUI view for Knowledge (Smriti) plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/knowledge/domain.{
  type KnowledgeNode, Atomic, Ecosystem, Molecular, Organism, level_to_string,
}
import cepaf_gleam/ui/lustre/knowledge.{type KnowledgeModel}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: KnowledgeModel) -> String {
  let header = visuals.with_color("  KNOWLEDGE (SMRITI)", "cyan")
  let summary = render_summary(model)
  let nodes = render_nodes(knowledge.filtered_nodes(model))
  string.join([header, summary, "", nodes], "\n")
}

fn render_summary(model: KnowledgeModel) -> String {
  let a = knowledge.node_count_by_level(model.nodes, Atomic)
  let m = knowledge.node_count_by_level(model.nodes, Molecular)
  let o = knowledge.node_count_by_level(model.nodes, Organism)
  let e = knowledge.node_count_by_level(model.nodes, Ecosystem)
  "  Nodes: "
  <> int.to_string(list.length(model.nodes))
  <> "  Links: "
  <> int.to_string(list.length(model.links))
  <> "\n  "
  <> visuals.with_color("A:" <> int.to_string(a), "blue")
  <> " "
  <> visuals.with_color("M:" <> int.to_string(m), "cyan")
  <> " "
  <> visuals.with_color("O:" <> int.to_string(o), "green")
  <> " "
  <> visuals.with_color("E:" <> int.to_string(e), "magenta")
}

fn render_nodes(nodes: List(KnowledgeNode)) -> String {
  nodes
  |> list.take(10)
  |> list.map(fn(n) {
    let entropy_bar = visuals.render_progress_bar(n.entropy, 10)
    "  "
    <> level_to_string(n.level)
    <> " "
    <> n.title
    <> " "
    <> entropy_bar
    <> " H="
    <> float.to_string(n.entropy)
  })
  |> string.join("\n")
}
