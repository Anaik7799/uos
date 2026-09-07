//// =============================================================================
//// [C3I-SIL6-MSTS] SEMANTIC SHEAF ENGINE TEST CONTRACT
//// =============================================================================

import cepaf_gleam/knowledge/sheaf_engine.{
  HermesWiki, SheafNode, ZkAdr, add_node, add_transclusion,
  compute_cohomology_consistency, doc_type_to_string, init_sheaf_graph,
  lookup_transclusions, semantic_search,
}
import gleam/list
import gleeunit/should

pub fn sheaf_init_test() {
  let graph = init_sheaf_graph()
  list.length(graph.nodes) |> should.equal(5)
  graph.total_transclusions |> should.equal(7)
  doc_type_to_string(ZkAdr) |> should.equal("zk-adr")
  doc_type_to_string(HermesWiki) |> should.equal("hermes-wiki")
}

pub fn sheaf_add_node_test() {
  let graph = init_sheaf_graph()
  let new_node =
    SheafNode(
      id: "ADR-078",
      title: "Autonomous Semantic Knowledge Sheaf",
      doc_type: ZkAdr,
      fractal_layer: "L5",
      tags: ["#zk-adr", "#sheaf-engine", "#transclusion"],
      outbound_transclusions: ["ADR-077"],
      inbound_references: [],
      centrality_score: 0.95,
    )
  let updated = add_node(graph, new_node)
  list.length(updated.nodes) |> should.equal(6)
}

pub fn sheaf_transclusion_test() {
  let graph = init_sheaf_graph()
  let updated = add_transclusion(graph, "ADR-077", "STAMP-SC-SIL6")
  let neighbors = lookup_transclusions(updated, "ADR-077")
  list.any(neighbors, fn(n) { n.id == "STAMP-SC-SIL6" }) |> should.equal(True)
}

pub fn sheaf_semantic_search_test() {
  let graph = init_sheaf_graph()
  let results = semantic_search(graph, "swarm", 0.3)
  list.length(results) |> should.not_equal(0)
  case list.first(results) {
    Ok(top) -> {
      should.be_true(top.relevance_score >=. 0.3)
    }
    Error(_) -> panic as "Search expected to return matches"
  }
}

pub fn sheaf_cohomology_consistency_test() {
  let graph = init_sheaf_graph()
  let score = compute_cohomology_consistency(graph)
  should.be_true(score >=. 0.95)
}
