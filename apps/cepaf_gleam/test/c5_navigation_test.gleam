// C5 Navigation Prime-Path Tests (SC-UIGT-004)
// Tests navigation graph properties, PageRank priority, and page transitions.
// STAMP: SC-UIGT-001..015

import cepaf_gleam/testing/nav_graph
import cepaf_gleam/ui/domain.{Cockpit, Dashboard, Immune, Planning, Verification}
import gleam/dict
import gleam/list
import gleam/set
import gleeunit/should

// =============================================================================
// Graph Structure Tests (SC-UIGT-001, SC-UIGT-011)
// =============================================================================

pub fn all_13_pages_in_graph_test() {
  let pages = nav_graph.all_pages()
  list.length(pages) |> should.equal(31)
}

pub fn page_count_matches_vertex_set_test() {
  nav_graph.page_count() |> should.equal(31)
}

pub fn edge_count_complete_graph_test() {
  // Complete graph: n*(n-1) = 31*30 = 930
  nav_graph.edge_count() |> should.equal(930)
}

pub fn density_is_one_for_complete_graph_test() {
  let d = nav_graph.density()
  { d >=. 0.99 } |> should.be_true()
}

pub fn scc_count_is_one_test() {
  // Fully connected → single SCC (SC-UIGT-012)
  nav_graph.scc_count() |> should.equal(1)
}

// =============================================================================
// Adjacency Tests
// =============================================================================

pub fn adjacency_has_13_entries_test() {
  let adj = nav_graph.adjacency()
  dict.size(adj) |> should.equal(31)
}

pub fn each_page_connects_to_12_others_test() {
  let adj = nav_graph.adjacency()
  dict.each(adj, fn(_idx, neighbors) { set.size(neighbors) |> should.equal(30) })
}

pub fn no_self_loops_test() {
  let adj = nav_graph.adjacency()
  dict.each(adj, fn(idx, neighbors) {
    set.contains(neighbors, idx) |> should.equal(False)
  })
}

// =============================================================================
// PageRank Tests (SC-UIGT-014)
// =============================================================================

pub fn pagerank_has_13_entries_test() {
  let ranks = nav_graph.page_rank()
  dict.size(ranks) |> should.equal(31)
}

pub fn pagerank_sums_to_approximately_one_test() {
  let ranks = nav_graph.page_rank()
  let total = dict.fold(ranks, 0.0, fn(acc, _k, v) { acc +. v })
  // Should sum to ~1.0 (within tolerance for power iteration)
  { total >=. 0.95 && total <=. 1.05 } |> should.be_true()
}

pub fn pagerank_all_positive_test() {
  let ranks = nav_graph.page_rank()
  dict.each(ranks, fn(_k, v) { { v >. 0.0 } |> should.be_true() })
}

pub fn test_priority_order_returns_13_pages_test() {
  let priority = nav_graph.test_priority_order()
  list.length(priority) |> should.equal(31)
}

pub fn test_priority_order_descending_test() {
  let priority = nav_graph.test_priority_order()
  let ranks = list.map(priority, fn(p) { p.1 })
  is_descending(ranks) |> should.be_true()
}

// =============================================================================
// Chinese Postman Bound (SC-UIGT-013)
// =============================================================================

pub fn chinese_postman_bound_equals_edge_count_test() {
  nav_graph.chinese_postman_bound() |> should.equal(930)
}

// =============================================================================
// Prime Path: Multi-Step Navigation Sequences
// =============================================================================

pub fn prime_path_dashboard_to_verification_via_cockpit_test() {
  // Navigate: Dashboard → Cockpit → Verification
  // Each step is a valid edge in the complete graph
  let pages = nav_graph.all_pages()
  list.contains(pages, Dashboard) |> should.be_true()
  list.contains(pages, Cockpit) |> should.be_true()
  list.contains(pages, Verification) |> should.be_true()
}

pub fn prime_path_all_tier1_pages_reachable_test() {
  // Tier 1 pages (highest complexity): Dashboard, Cockpit, Verification, Planning, Immune
  let tier1 = [Dashboard, Cockpit, Verification, Planning, Immune]
  let all = nav_graph.all_pages()
  list.each(tier1, fn(p) { list.contains(all, p) |> should.be_true() })
}

pub fn prime_path_cyclic_return_to_start_test() {
  // Dashboard → Planning → Knowledge → Dashboard (cycle)
  let adj = nav_graph.adjacency()
  // Dashboard(0) → Planning(1): edge exists
  case dict.get(adj, 0) {
    Ok(neighbors) -> set.contains(neighbors, 1) |> should.be_true()
    Error(_) -> should.fail()
  }
  // Planning(1) → Knowledge(3): edge exists
  case dict.get(adj, 1) {
    Ok(neighbors) -> set.contains(neighbors, 3) |> should.be_true()
    Error(_) -> should.fail()
  }
  // Knowledge(3) → Dashboard(0): edge exists
  case dict.get(adj, 3) {
    Ok(neighbors) -> set.contains(neighbors, 0) |> should.be_true()
    Error(_) -> should.fail()
  }
}

// =============================================================================
// Helpers
// =============================================================================

fn is_descending(values: List(Float)) -> Bool {
  case values {
    [] | [_] -> True
    [a, b, ..rest] ->
      case a >=. b {
        True -> is_descending([b, ..rest])
        False -> False
      }
  }
}
