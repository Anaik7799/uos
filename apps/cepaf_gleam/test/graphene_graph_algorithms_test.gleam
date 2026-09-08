//// Behavioural laws for the pure-Erlang graph algorithms in `graphene_nif`.
////
//// The pre-existing tests in graphene_render_test.gleam only assert
//// `should.be_ok()`, which is why the previous stub facade passed them: a
//// function returning a constant is still `Ok`. These tests assert the ANSWER.
////
//// Reference graph (directed, weighted):
////
////     E --1--> A --1--> B --2--> C --1--> D
////              |                 ^
////              +-------4---------+
////
//// A->D is 4 via A,B,C,D and 5 via A,C,D, so a real shortest path must choose
//// the three-hop route. D has no outgoing edge; nothing reaches E.

import cepaf_gleam/graphene
import gleam/string
import gleeunit/should

const nodes = "[\"A\",\"B\",\"C\",\"D\",\"E\"]"

const edges = "[[\"A\",\"B\",1],[\"A\",\"C\",4],[\"B\",\"C\",2],[\"C\",\"D\",1],[\"E\",\"A\",1]]"

/// A 3-cycle: one strongly connected component, no topological order.
const cyc_nodes = "[\"A\",\"B\",\"C\"]"

const cyc_edges = "[[\"A\",\"B\",1],[\"B\",\"C\",1],[\"C\",\"A\",1]]"

fn body(r: Result(String, String)) -> String {
  case r {
    Ok(s) -> s
    Error(e) -> "ERROR:" <> e
  }
}

fn contains(r: Result(String, String), needle: String) -> Bool {
  string.contains(body(r), needle)
}

// --- BFS --------------------------------------------------------------------

/// BFS from A reaches A,B,C,D in level order. E points *into* A and is
/// therefore unreachable, so it must not appear.
pub fn bfs_visits_reachable_in_level_order_test() {
  let r = graphene.graphene_bfs(nodes, edges, "A")
  contains(r, "\"order\":[\"A\",\"B\",\"C\",\"D\"]") |> should.be_true()
}

pub fn bfs_reports_true_depths_test() {
  let r = graphene.graphene_bfs(nodes, edges, "A")
  contains(r, "\"A\":0") |> should.be_true()
  contains(r, "\"B\":1") |> should.be_true()
  contains(r, "\"C\":1") |> should.be_true()
  contains(r, "\"D\":2") |> should.be_true()
}

/// The stub returned only the start node for every graph. This is the
/// regression guard for that exact defect.
pub fn bfs_is_not_a_stub_returning_only_start_test() {
  let r = graphene.graphene_bfs(nodes, edges, "A")
  { body(r) == "{\"depths\":{\"A\":0},\"order\":[\"A\"]}" } |> should.be_false()
}

pub fn bfs_excludes_unreachable_node_test() {
  let r = graphene.graphene_bfs(nodes, edges, "A")
  contains(r, "\"E\"") |> should.be_false()
}

pub fn bfs_unknown_start_yields_empty_order_test() {
  let r = graphene.graphene_bfs(nodes, edges, "ZZZ")
  contains(r, "\"order\":[]") |> should.be_true()
}

// --- DFS --------------------------------------------------------------------

pub fn dfs_follows_depth_first_order_test() {
  let r = graphene.graphene_dfs(nodes, edges, "A")
  contains(r, "\"order\":[\"A\",\"B\",\"C\",\"D\"]") |> should.be_true()
}

// --- Topological sort -------------------------------------------------------

/// E has in-degree 0 and must precede A; D has out-degree 0 and comes last.
pub fn topological_sort_orders_acyclic_graph_test() {
  let r = graphene.graphene_topological_sort(nodes, edges)
  contains(r, "\"order\":[\"E\",\"A\",\"B\",\"C\",\"D\"]") |> should.be_true()
  contains(r, "\"acyclic\":true") |> should.be_true()
}

/// A cyclic graph has NO topological order. The stub returned the input order
/// regardless, which silently claimed an ordering that does not exist.
pub fn topological_sort_refuses_cyclic_graph_test() {
  let r = graphene.graphene_topological_sort(cyc_nodes, cyc_edges)
  contains(r, "\"acyclic\":false") |> should.be_true()
  contains(r, "\"order\":[]") |> should.be_true()
}

// --- Strongly connected components -------------------------------------------

/// A 3-cycle collapses to exactly one component containing all three nodes.
pub fn scc_finds_single_component_in_cycle_test() {
  let r = graphene.graphene_scc(cyc_nodes, cyc_edges)
  contains(r, "\"count\":1") |> should.be_true()
}

/// The acyclic reference graph has five singleton components. The stub always
/// returned one component containing every node.
pub fn scc_finds_five_singletons_in_dag_test() {
  let r = graphene.graphene_scc(nodes, edges)
  contains(r, "\"count\":5") |> should.be_true()
}

// --- Shortest path ----------------------------------------------------------

/// The decisive test: A->D costs 4 via the three-hop route, not 5 via the
/// direct A->C edge, and not the stub's constant 1.0.
pub fn shortest_path_prefers_cheaper_multi_hop_route_test() {
  let r = graphene.graphene_shortest_path(nodes, edges, "A", "D")
  contains(r, "\"path\":[\"A\",\"B\",\"C\",\"D\"]") |> should.be_true()
  contains(r, "\"cost\":4.0") |> should.be_true()
  contains(r, "\"found\":true") |> should.be_true()
}

/// D has no outgoing edges, so no path to A exists. The stub fabricated
/// [From,To] with cost 1.0 for every pair including this one.
pub fn shortest_path_reports_unreachable_rather_than_fabricating_test() {
  let r = graphene.graphene_shortest_path(nodes, edges, "D", "A")
  contains(r, "\"found\":false") |> should.be_true()
  contains(r, "\"cost\":null") |> should.be_true()
  contains(r, "\"cost\":1.0") |> should.be_false()
}

pub fn shortest_path_trivial_self_route_is_zero_cost_test() {
  let r = graphene.graphene_shortest_path(nodes, edges, "A", "A")
  contains(r, "\"cost\":0.0") |> should.be_true()
}

// --- PageRank ---------------------------------------------------------------

/// A symmetric 3-cycle is perfectly balanced: every node holds exactly 1/3.
pub fn pagerank_is_uniform_on_symmetric_cycle_test() {
  let r = graphene.graphene_pagerank(cyc_nodes, cyc_edges, 0.85, 50)
  contains(r, "0.3333333") |> should.be_true()
}

// --- Analysis ---------------------------------------------------------------

/// Directed density is E / (V*(V-1)) = 5/20 = 0.25. The stub hardcoded 0.5.
pub fn analyze_computes_real_directed_density_test() {
  let r = graphene.graphene_analyze(nodes, edges)
  contains(r, "\"vertices\":5") |> should.be_true()
  contains(r, "\"edges\":5") |> should.be_true()
  contains(r, "\"density\":0.25") |> should.be_true()
  contains(r, "\"density\":0.5") |> should.be_false()
}

/// is_dag must be decided by an actual topological sort. The stub always said
/// true, including for graphs that are obviously cyclic.
pub fn analyze_detects_cycle_rather_than_assuming_dag_test() {
  let r = graphene.graphene_analyze(cyc_nodes, cyc_edges)
  contains(r, "\"is_dag\":false") |> should.be_true()
}

pub fn analyze_confirms_dag_on_acyclic_graph_test() {
  let r = graphene.graphene_analyze(nodes, edges)
  contains(r, "\"is_dag\":true") |> should.be_true()
}
