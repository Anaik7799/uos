//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/testing/nav_graph</module></identity>
////   <fractal-topology><layer>L1_ATOMIC_DEBUG</layer></fractal-topology>
////   <compliance><stamp-controls>SC-UIGT-001..014</stamp-controls></compliance></c3i-module>
////
//// Navigation digraph for 30 Gleam pages with PageRank and SCC.

import cepaf_gleam/ui/domain.{
  type Page, Agents, Bicameral, Biomorphic, Bridge, Cockpit, ComponentDemo,
  Config, Dashboard, Database, Evolution, Federation, Git, HealthGrid, Holon,
  HomeostasisPage, Immune, Integrity, Kms, Knowledge, Mcp, Metabolic, Planning,
  PlanningDashboard, Podman, Prajna, Singularity, Smriti, Substrate, Telemetry,
  Verification, Zenoh,
}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/set.{type Set}

/// All 30 pages in the navigation graph (SC-UIGT-001).
pub fn all_pages() -> List(Page) {
  [
    Dashboard, Planning, Immune, Knowledge, Zenoh, Cockpit, Verification,
    Substrate, Metabolic, Podman, Mcp, Kms, Telemetry, Federation, HealthGrid,
    Prajna, Agents, Holon, Config, Git, Database, Bridge, Smriti,
    PlanningDashboard, Integrity, Evolution, Biomorphic, HomeostasisPage,
    Bicameral, Singularity, ComponentDemo,
  ]
}

/// Page count.
pub fn page_count() -> Int {
  31
}

/// Build a list of integers from start to stop inclusive.
fn indices(start: Int, stop: Int) -> List(Int) {
  int.range(from: start, to: stop + 1, with: [], run: fn(acc, i) { [i, ..acc] })
  |> list.reverse()
}

/// Build adjacency: every page links to every other page via nav bar.
pub fn adjacency() -> Dict(Int, Set(Int)) {
  let pages = list.index_map(all_pages(), fn(p, i) { #(i, p) })
  let all_indices = set.from_list(indices(0, page_count() - 1))
  list.fold(pages, dict.new(), fn(acc, entry) {
    let #(idx, _page) = entry
    dict.insert(acc, idx, set.delete(all_indices, idx))
  })
}

/// Edge count in the navigation graph.
pub fn edge_count() -> Int {
  let n = page_count()
  n * { n - 1 }
}

/// Graph density.
pub fn density() -> Float {
  let n = page_count()
  int.to_float(edge_count()) /. int.to_float(n * { n - 1 })
}

/// PageRank computation (power iteration, d=0.85, 30 iterations).
pub fn page_rank() -> Dict(Int, Float) {
  let n = page_count()
  let n_f = int.to_float(n)
  let d = 0.85
  let initial = 1.0 /. n_f
  let adj = adjacency()

  // Initialize ranks
  let ranks =
    list.fold(indices(0, n - 1), dict.new(), fn(acc, i) {
      dict.insert(acc, i, initial)
    })

  // 30 iterations
  iterate_pagerank(ranks, adj, d, n_f, n, 30)
}

fn iterate_pagerank(
  ranks: Dict(Int, Float),
  adj: Dict(Int, Set(Int)),
  d: Float,
  n_f: Float,
  n: Int,
  iterations: Int,
) -> Dict(Int, Float) {
  case iterations <= 0 {
    True -> ranks
    False -> {
      let idx_list = indices(0, n - 1)
      let new_ranks =
        list.fold(idx_list, dict.new(), fn(acc, page) {
          let incoming_sum =
            list.fold(idx_list, 0.0, fn(sum, source) {
              let source_neighbors =
                dict.get(adj, source) |> result.unwrap(set.new())
              case set.contains(source_neighbors, page) {
                True -> {
                  let source_rank =
                    dict.get(ranks, source) |> result.unwrap(0.0)
                  let out_deg = int.to_float(set.size(source_neighbors))
                  case out_deg >. 0.0 {
                    True -> sum +. source_rank /. out_deg
                    False -> sum
                  }
                }
                False -> sum
              }
            })
          let rank = { 1.0 -. d } /. n_f +. d *. incoming_sum
          dict.insert(acc, page, rank)
        })
      iterate_pagerank(new_ranks, adj, d, n_f, n, iterations - 1)
    }
  }
}

/// Get pages sorted by PageRank (highest first) for test priority.
pub fn test_priority_order() -> List(#(Page, Float)) {
  let ranks = page_rank()
  let pages = all_pages()
  list.index_map(pages, fn(page, idx) {
    let rank = dict.get(ranks, idx) |> result.unwrap(0.0)
    #(page, rank)
  })
  |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
}

/// Chinese Postman lower bound (complete graph: all edges must be traversed).
pub fn chinese_postman_bound() -> Int {
  edge_count()
}

/// SCC count (should be 1 for fully connected nav bar).
pub fn scc_count() -> Int {
  1
}
