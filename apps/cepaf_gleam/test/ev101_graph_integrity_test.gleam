import cepaf_gleam/knowledge/sheaf_engine as graph
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should

fn node(id) {
  graph.SheafNode(id, id, graph.ZkAdr, "L5", [], [], [], 0.5)
}

fn empty() { graph.SheafGraph([], 0, 1.0) }

fn nodes(ids) {
  list.fold(ids, empty(), fn(g, id) { graph.add_node(g, node(id)) })
}

fn find(g: graph.SheafGraph, id: String) -> graph.SheafNode {
  let assert Ok(n) = list.find(g.nodes, fn(n) { n.id == id })
  n
}

// Independent finite edge-set oracle: no production adjacency helpers used.
fn oracle(g: graph.SheafGraph, edges: List(#(String, String))) {
  g.total_transclusions |> should.equal(list.length(edges))
  list.each(g.nodes, fn(n) {
    let outs = list.filter_map(edges, fn(e) {
      case e.0 == n.id { True -> Ok(e.1) False -> Error(Nil) }
    })
    let ins = list.filter_map(edges, fn(e) {
      case e.1 == n.id { True -> Ok(e.0) False -> Error(Nil) }
    })
    list.sort(n.outbound_transclusions, string.compare)
    |> should.equal(list.sort(outs, string.compare))
    list.sort(n.inbound_references, string.compare)
    |> should.equal(list.sort(ins, string.compare))
  })
  graph.compute_cohomology_consistency(g) |> should.equal(1.0)
  g.cohomology_score |> should.equal(1.0)
}

pub fn duplicate_edge_is_idempotent_test() {
  let g = nodes(["a", "b"]) |> graph.add_transclusion("a", "b")
  graph.add_transclusion(g, "a", "b") |> should.equal(g)
}

pub fn missing_endpoint_preserves_graph_test() {
  let g = nodes(["a"])
  graph.add_transclusion(g, "a", "missing") |> should.equal(g)
  graph.add_transclusion(g, "missing", "a") |> should.equal(g)
}

pub fn self_edge_has_both_adjacencies_and_one_count_test() {
  let g = nodes(["a"]) |> graph.add_transclusion("a", "a")
  oracle(g, [#("a", "a")])
  graph.add_transclusion(g, "a", "a") |> should.equal(g)
}

pub fn replacement_rebuilds_inbound_without_losing_other_edges_test() {
  let g = nodes(["a", "b", "c"])
    |> graph.add_transclusion("a", "b")
    |> graph.add_transclusion("b", "a")
    |> graph.add_transclusion("c", "b")
  let replacement = graph.SheafNode(..node("a"), title: "replacement", outbound_transclusions: ["c"])
  let updated = graph.add_node(g, replacement)
  oracle(updated, [#("a", "c"), #("b", "a"), #("c", "b")])
  find(updated, "a").title |> should.equal("replacement")
}

pub fn missing_reciprocity_is_not_consistent_test() {
  let a = graph.SheafNode(..node("a"), outbound_transclusions: ["b"])
  let malformed = graph.SheafGraph([a, node("b"), node("isolated")], 1, 1.0)
  graph.compute_cohomology_consistency(malformed) |> should.equal(0.0)
  let inbound_only = graph.SheafNode(..node("b"), inbound_references: ["a"])
  graph.compute_cohomology_consistency(graph.SheafGraph([node("a"), inbound_only], 0, 1.0))
  |> should.equal(0.0)
}

pub fn initialized_metrics_are_observed_test() {
  let g = graph.init_sheaf_graph()
  g.cohomology_score |> should.equal(graph.compute_cohomology_consistency(g))
}

pub fn legacy_size_refusal_is_atomic_test() {
  let g = nodes(["a"])
  graph.add_node(g, graph.SheafNode(..node("b"), title: string.repeat("x", 1025)))
  |> should.equal(g)
}

fn selected(mask, choices) {
  case choices {
    [] -> []
    [edge, ..rest] -> {
      let tail = selected(mask / 2, rest)
      case mask % 2 { 0 -> tail _ -> [edge, ..tail] }
    }
  }
}

fn range(first, last) {
  case first > last { True -> [] False -> [first, ..range(first + 1, last)] }
}

pub fn every_three_node_directed_graph_matches_edge_set_oracle_test() {
  let ids = ["a", "b", "c"]
  let all = list.flat_map(ids, fn(a) { list.map(ids, fn(b) { #(a, b) }) })
  list.each(range(0, 511), fn(mask) {
    let edges = selected(mask, all)
    let g = list.fold(edges, nodes(ids), fn(g, e) { graph.add_transclusion(g, e.0, e.1) })
    oracle(g, edges)
    list.fold(edges, g, fn(g, e) { graph.add_transclusion(g, e.0, e.1) }) |> should.equal(g)
  })
}

pub fn node_limit_refusal_preserves_existing_graph_test() {
  let ids = list.map(range(1, 64), int.to_string)
  let g = nodes(ids)
  list.length(g.nodes) |> should.equal(64)
  graph.add_node(g, node("overflow")) |> should.equal(g)
}
