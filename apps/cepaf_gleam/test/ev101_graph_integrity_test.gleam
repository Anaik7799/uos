import cepaf_gleam/knowledge/sheaf_engine as graph
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should

fn node(id) {
  graph.SheafNode(id, id, graph.ZkAdr, "L5", [], [], [], 0.5)
}

fn empty() {
  graph.SheafGraph([], 0, 1.0)
}

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
    let outs =
      list.filter_map(edges, fn(e) {
        case e.0 == n.id {
          True -> Ok(e.1)
          False -> Error(Nil)
        }
      })
    let ins =
      list.filter_map(edges, fn(e) {
        case e.1 == n.id {
          True -> Ok(e.0)
          False -> Error(Nil)
        }
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
  let g =
    nodes(["a", "b", "c"])
    |> graph.add_transclusion("a", "b")
    |> graph.add_transclusion("b", "a")
    |> graph.add_transclusion("c", "b")
  let replacement =
    graph.SheafNode(..node("a"), title: "replacement", outbound_transclusions: [
      "c",
    ])
  let updated = graph.add_node(g, replacement)
  oracle(updated, [#("a", "c"), #("b", "a"), #("c", "b")])
  find(updated, "a").title |> should.equal("replacement")
}

pub fn missing_reciprocity_is_not_consistent_test() {
  let a = graph.SheafNode(..node("a"), outbound_transclusions: ["b"])
  let malformed = graph.SheafGraph([a, node("b"), node("isolated")], 1, 1.0)
  graph.compute_cohomology_consistency(malformed) |> should.equal(0.0)
  let inbound_only = graph.SheafNode(..node("b"), inbound_references: ["a"])
  graph.compute_cohomology_consistency(graph.SheafGraph(
    [node("a"), inbound_only],
    0,
    1.0,
  ))
  |> should.equal(0.0)
}

pub fn initialized_metrics_are_observed_test() {
  let g = graph.init_sheaf_graph()
  g.cohomology_score |> should.equal(graph.compute_cohomology_consistency(g))
}

pub fn legacy_size_refusal_is_atomic_test() {
  let g = nodes(["a"])
  graph.add_node(
    g,
    graph.SheafNode(..node("b"), title: string.repeat("x", 1025)),
  )
  |> should.equal(g)
}

fn selected(mask, choices) {
  case choices {
    [] -> []
    [edge, ..rest] -> {
      let tail = selected(mask / 2, rest)
      case mask % 2 {
        0 -> tail
        _ -> [edge, ..tail]
      }
    }
  }
}

fn range(first, last) {
  case first > last {
    True -> []
    False -> [first, ..range(first + 1, last)]
  }
}

pub fn every_three_node_directed_graph_matches_edge_set_oracle_test() {
  let ids = ["a", "b", "c"]
  let all = list.flat_map(ids, fn(a) { list.map(ids, fn(b) { #(a, b) }) })
  list.each(range(0, 511), fn(mask) {
    let edges = selected(mask, all)
    let g =
      list.fold(edges, nodes(ids), fn(g, e) {
        graph.add_transclusion(g, e.0, e.1)
      })
    oracle(g, edges)
    list.fold(edges, g, fn(g, e) { graph.add_transclusion(g, e.0, e.1) })
    |> should.equal(g)
    let replacement =
      graph.SheafNode(..node("a"), outbound_transclusions: ["b"])
    let replaced = graph.add_node(g, replacement)
    oracle(replaced, [#("a", "b"), ..list.filter(edges, fn(e) { e.0 != "a" })])
  })
}

pub fn node_limit_refusal_preserves_existing_graph_test() {
  let ids = list.map(range(1, 64), int.to_string)
  let g = nodes(ids)
  list.length(g.nodes) |> should.equal(64)
  graph.add_node(g, node("overflow")) |> should.equal(g)
}

fn from_edges(ids: List(String), edges: List(#(String, String))) {
  let ns =
    list.map(ids, fn(id) {
      let outs =
        list.filter_map(edges, fn(e) {
          case e.0 == id {
            True -> Ok(e.1)
            False -> Error(Nil)
          }
        })
      let ins =
        list.filter_map(edges, fn(e) {
          case e.1 == id {
            True -> Ok(e.0)
            False -> Error(Nil)
          }
        })
      graph.SheafNode(
        ..node(id),
        outbound_transclusions: outs,
        inbound_references: ins,
      )
    })
  graph.SheafGraph(ns, list.length(edges), 1.0)
}

pub fn exact_edge_quota_duplicate_and_replacement_test() {
  let ids = list.map(range(1, 16), int.to_string)
  let all = list.flat_map(ids, fn(a) { list.map(ids, fn(b) { #(a, b) }) })
  let g = from_edges(["spare", ..ids], all)
  graph.validate_graph(g) |> should.equal(Ok(Nil))
  graph.try_add_transclusion(g, "1", "1") |> should.equal(Ok(g))
  graph.try_add_transclusion(g, "1", "spare")
  |> should.equal(Error(graph.EdgeLimit))
  graph.add_transclusion(g, "1", "spare") |> should.equal(g)
  let assert Ok(reduced) = graph.try_add_node(g, node("1"))
  let expected = list.filter(all, fn(e) { e.0 != "1" })
  oracle(reduced, expected)
  let assert Ok(_) = graph.try_add_transclusion(reduced, "1", "spare")
}

pub fn typed_missing_and_malformed_input_refusals_test() {
  let g = nodes(["a", "b"])
  graph.try_add_transclusion(g, "a", "missing")
  |> should.equal(Error(graph.MissingNode("missing")))
  graph.try_add_transclusion(g, "missing", "b")
  |> should.equal(Error(graph.MissingNode("missing")))
  graph.try_add_node(
    g,
    graph.SheafNode(..node("c"), outbound_transclusions: ["missing"]),
  )
  |> should.equal(Error(graph.MissingNode("missing")))
  graph.try_add_node(
    g,
    graph.SheafNode(..node("c"), outbound_transclusions: ["a", "a"]),
  )
  |> should.equal(Error(graph.InvalidGraph))
  let bad = graph.SheafGraph(..g, total_transclusions: 99)
  graph.validate_graph(bad) |> should.equal(Error(graph.InvalidGraph))
  graph.add_node(bad, node("c")) |> should.equal(bad)
  graph.add_transclusion(bad, "a", "b") |> should.equal(bad)
  graph.lookup_transclusions(bad, "a") |> should.equal([])
  graph.semantic_search(bad, "a", 0.0) |> should.equal([])
}

pub fn duplicate_dangling_and_inbound_only_metric_penalties_test() {
  let good = from_edges(["a", "b", "c"], [#("a", "b")])
  let a = find(good, "a")
  let b = find(good, "b")
  let dangling = graph.SheafNode(..a, outbound_transclusions: ["missing", "b"])
  let score =
    graph.compute_cohomology_consistency(graph.SheafGraph(
      [dangling, b, node("c")],
      2,
      1.0,
    ))
  score |> should.equal(2.0 /. 3.0)
  let duplicated = graph.SheafNode(..a, outbound_transclusions: ["b", "b"])
  graph.compute_cohomology_consistency(graph.SheafGraph([duplicated, b], 2, 1.0))
  |> should.equal(0.0)
  let repeated_in = graph.SheafNode(..b, inbound_references: ["a", "a"])
  graph.compute_cohomology_consistency(graph.SheafGraph(
    [a, repeated_in],
    1,
    1.0,
  ))
  |> should.equal(0.0)
  graph.compute_cohomology_consistency(graph.SheafGraph([a, b, b], 1, 1.0))
  |> should.equal(0.0)
  graph.compute_cohomology_consistency(empty()) |> should.equal(1.0)
}

pub fn exact_metadata_boundaries_and_invalid_ids_test() {
  let valid =
    graph.SheafNode(
      ..node(string.repeat("i", 256)),
      title: string.repeat("t", 1024),
      tags: list.repeat("tag", 16),
    )
  let assert Ok(g) = graph.try_add_node(empty(), valid)
  graph.validate_graph(g) |> should.equal(Ok(Nil))
  list.each(
    [
      graph.SheafNode(..valid, id: ""),
      graph.SheafNode(..valid, id: string.repeat("i", 257)),
      graph.SheafNode(..valid, title: string.repeat("t", 1025)),
      graph.SheafNode(..valid, tags: list.repeat("tag", 17)),
      graph.SheafNode(..valid, centrality_score: -0.1),
      graph.SheafNode(..valid, centrality_score: 1.1),
    ],
    fn(n) {
      graph.try_add_node(empty(), n) |> should.equal(Error(graph.MetadataLimit))
    },
  )
  graph.semantic_search(g, string.repeat("q", 1025), 0.0) |> should.equal([])
}

pub fn replacement_inbound_cache_is_derived_not_imported_test() {
  let g = nodes(["a", "b"]) |> graph.add_transclusion("b", "a")
  let replacement =
    graph.SheafNode(
      ..node("a"),
      inbound_references: ["fake"],
      outbound_transclusions: ["a"],
    )
  let assert Ok(updated) = graph.try_add_node(g, replacement)
  oracle(updated, [#("b", "a"), #("a", "a")])
  graph.lookup_transclusions(updated, "a") |> list.length |> should.equal(2)
}

pub fn oversized_public_graph_is_refused_before_read_or_mutation_test() {
  let bad =
    graph.SheafGraph(
      list.map(range(1, 65), fn(i) { node(int.to_string(i)) }),
      0,
      1.0,
    )
  graph.validate_graph(bad) |> should.equal(Error(graph.NodeLimit))
  graph.compute_cohomology_consistency(bad) |> should.equal(0.0)
  graph.add_node(bad, node("a")) |> should.equal(bad)
  graph.semantic_search(bad, "a", 0.0) |> should.equal([])
  let huge =
    graph.SheafNode(..node("a"), outbound_transclusions: list.repeat("a", 65))
  graph.try_add_node(empty(), huge) |> should.equal(Error(graph.MetadataLimit))
}

pub fn every_two_node_raw_adjacency_metric_matches_pair_oracle_test() {
  let ids = ["a", "b"]
  let pairs = list.flat_map(ids, fn(a) { list.map(ids, fn(b) { #(a, b) }) })
  list.each(range(0, 255), fn(mask) {
    let outgoing = selected(mask % 16, pairs)
    let incoming = selected(mask / 16, pairs)
    let ns =
      list.map(ids, fn(id) {
        let outs =
          list.filter_map(outgoing, fn(e) {
            case e.0 == id {
              True -> Ok(e.1)
              False -> Error(Nil)
            }
          })
        let ins =
          list.filter_map(incoming, fn(e) {
            case e.1 == id {
              True -> Ok(e.0)
              False -> Error(Nil)
            }
          })
        graph.SheafNode(
          ..node(id),
          outbound_transclusions: outs,
          inbound_references: ins,
        )
      })
    let denominator = list.length(outgoing) + list.length(incoming)
    let mutual =
      list.length(
        list.filter(pairs, fn(e) {
          list.contains(outgoing, e) && list.contains(incoming, e)
        }),
      )
    let expected = case denominator {
      0 -> 1.0
      _ -> int.to_float(2 * mutual) /. int.to_float(denominator)
    }
    graph.compute_cohomology_consistency(graph.SheafGraph(
      ns,
      list.length(outgoing),
      0.0,
    ))
    |> should.equal(expected)
  })
}

pub fn asymmetric_raw_edge_limit_cannot_emit_consistency_credit_test() {
  let ids = list.map(range(1, 17), int.to_string)
  let pairs = list.flat_map(ids, fn(a) { list.map(ids, fn(b) { #(a, b) }) })
  let outgoing = list.take(pairs, 257)
  let incoming = list.take(pairs, 255)
  let g = from_edges(ids, outgoing)
  let ns =
    list.map(g.nodes, fn(n) {
      let ins =
        list.filter_map(incoming, fn(e) {
          case e.1 == n.id {
            True -> Ok(e.0)
            False -> Error(Nil)
          }
        })
      graph.SheafNode(..n, inbound_references: ins)
    })
  let oversized = graph.SheafGraph(ns, 257, 1.0)
  graph.compute_cohomology_consistency(oversized) |> should.equal(0.0)
  graph.validate_graph(oversized) |> should.equal(Error(graph.EdgeLimit))
}
