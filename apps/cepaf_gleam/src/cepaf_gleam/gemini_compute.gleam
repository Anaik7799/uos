//// =============================================================================
//// [C3I-SIL6-MSTS] GEMINI COMPUTE MODULE
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/gemini_compute</module>
////     <fsharp-lineage>None — Gemini-specific compute bridge</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-ZK-GEMINI-001..006</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Gemini Code invokes this module via:
////   cd lib/cepaf_gleam && gleam run -m gemini_compute
////
//// It bridges Gemini to the system's own computational capabilities.

import cepaf_gleam/graphene
import cepaf_gleam/testing/nav_graph
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/order
import gleam/string

pub fn main() {
  io.println("C3I Gemini Compute Bridge v1.0")
  io.println("==============================")
  nav_health()
  graph_tools()
}

/// Navigation graph health — SCC, density, page count
pub fn nav_health() {
  io.println("")
  io.println("=== NAVIGATION GRAPH ===")
  let pages = nav_graph.all_pages()
  let page_count = list.length(pages)
  let edge_count = nav_graph.edge_count()
  let scc = nav_graph.scc_count()

  io.println("  Pages: " <> int.to_string(page_count))
  io.println("  Edges: " <> int.to_string(edge_count))
  io.println(
    "  SCC: "
    <> int.to_string(scc)
    <> case scc {
      1 -> " PASS (all reachable)"
      _ -> " FAIL (unreachable pages!)"
    },
  )

  // PageRank
  let ranked = nav_graph.page_rank()
  let ranked_list =
    ranked
    |> dict.to_list()
    |> list.sort(fn(a, b) { float_compare(b.1, a.1) })
    |> list.take(5)

  io.println("  PageRank top 5:")
  list.each(ranked_list, fn(entry) {
    io.println(
      "    #" <> int.to_string(entry.0) <> ": " <> string.inspect(entry.1),
    )
  })
}

fn float_compare(a: Float, b: Float) -> order.Order {
  case a <. b {
    True -> order.Lt
    False ->
      case a >. b {
        True -> order.Gt
        False -> order.Eq
      }
  }
}

/// Demonstrate Graphene NIF graph tools
pub fn graph_tools() {
  io.println("")
  io.println("=== GRAPHENE NIF TOOLS ===")

  // BFS example
  case
    graphene.graphene_bfs_typed(
      ["Dashboard", "Planning", "Immune", "Zenoh"],
      [
        #("Dashboard", "Planning", 1),
        #("Dashboard", "Immune", 1),
        #("Planning", "Zenoh", 1),
      ],
      "Dashboard",
    )
  {
    Ok(result) -> io.println("  BFS from Dashboard: " <> result)
    Error(e) -> io.println("  BFS error: " <> e)
  }

  // SCC example
  case
    graphene.graphene_scc_typed(["A", "B", "C"], [
      #("A", "B", 1),
      #("B", "C", 1),
      #("C", "A", 1),
    ])
  {
    Ok(result) -> io.println("  SCC test: " <> result)
    Error(e) -> io.println("  SCC error: " <> e)
  }

  // Topological sort (boot DAG)
  case
    graphene.graphene_topological_sort_typed(
      ["Zenoh", "DB", "Obs", "App1", "Cortex"],
      [
        #("Zenoh", "DB", 1),
        #("DB", "Obs", 1),
        #("Obs", "App1", 1),
        #("App1", "Cortex", 1),
      ],
    )
  {
    Ok(result) -> io.println("  Boot DAG sort: " <> result)
    Error(e) -> io.println("  Toposort error: " <> e)
  }

  io.println("")
  io.println("Gemini Compute Bridge ready. 125 NIF functions available.")
}
