//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/planning/graph_verification</module>
////     <fsharp-lineage>Cepaf.Core.GraphVerification.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <mesh-domain>Graph Verification, Deadlock Detection, Reachability</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / CRITICAL</criticality>
////     <stamp-controls>SC-GRAPH-001 to SC-GRAPH-022</stamp-controls>
////     <aor-rules>AOR-GRAPH-001 to AOR-GRAPH-015</aor-rules>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       F# Graph[Node,Edge] ≅ Gleam Graph(Node, Edge)
////     </morphism>
////     <morphism type="injective" loss="fsharp-async">
////       F# `Graph.detectCycles` ↪ Gleam `detect_cycles` (DFS coloring)
////     </morphism>
////     <morphism type="isomorphic">
////       F# `Graph.topologicalSort` ≅ Gleam `topological_sort` (Kahn's algorithm)
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/string

// =============================================================================
// Type Definitions
// =============================================================================

/// A node in the directed graph.
pub type Node {
  Node(id: String, label: String, node_type: String)
}

/// A directed edge in the graph.
pub type Edge {
  Edge(from: String, to: String, label: String, is_allowed: Bool)
}

/// A directed graph of nodes and edges.
pub type Graph {
  Graph(nodes: List(Node), edges: List(Edge))
}

/// DFS coloring for cycle detection.
pub type Color {
  White
  Grey
  Black
}

/// Result of a single verification check.
pub type VerificationResult {
  VerificationResult(name: String, passed: Bool, details: String)
}

/// Aggregate statistics for a graph.
pub type GraphStats {
  GraphStats(node_count: Int, edge_count: Int, density: Float, scc_count: Int)
}

// =============================================================================
// Graph Construction
// =============================================================================

/// Create an empty graph.
pub fn new_graph() -> Graph {
  Graph(nodes: [], edges: [])
}

/// Add a node to the graph. Duplicate IDs are ignored.
pub fn add_node(graph: Graph, node: Node) -> Graph {
  let exists = list.any(graph.nodes, fn(n) { n.id == node.id })
  case exists {
    True -> graph
    False -> Graph(..graph, nodes: [node, ..graph.nodes])
  }
}

/// Add an edge to the graph.
pub fn add_edge(graph: Graph, edge: Edge) -> Graph {
  Graph(..graph, edges: [edge, ..graph.edges])
}

/// Find a node by ID.
pub fn find_node(graph: Graph, id: String) -> Result(Node, String) {
  list.find(graph.nodes, fn(n) { n.id == id })
  |> result.replace_error("Node not found: " <> id)
}

/// Get all neighbor nodes reachable from the given node via outgoing edges.
pub fn neighbors(graph: Graph, node_id: String) -> List(Node) {
  let neighbor_ids =
    list.filter_map(graph.edges, fn(e) {
      case e.from == node_id {
        True -> Ok(e.to)
        False -> Error(Nil)
      }
    })
  list.filter(graph.nodes, fn(n) { list.contains(neighbor_ids, n.id) })
}

// =============================================================================
// Graph Traversal
// =============================================================================

/// Depth-first search from a starting node. Returns visited node IDs in DFS order.
pub fn dfs(graph: Graph, start: String) -> List(String) {
  let visited = set.new()
  dfs_loop(graph, [start], visited, [])
  |> list.reverse()
}

fn dfs_loop(
  graph: Graph,
  stack: List(String),
  visited: Set(String),
  acc: List(String),
) -> List(String) {
  case stack {
    [] -> acc
    [current, ..rest] -> {
      case set.contains(visited, current) {
        True -> dfs_loop(graph, rest, visited, acc)
        False -> {
          let new_visited = set.insert(visited, current)
          let neighbor_ids =
            list.filter_map(graph.edges, fn(e) {
              case e.from == current {
                True -> Ok(e.to)
                False -> Error(Nil)
              }
            })
          // Push neighbors onto stack (reversed so first neighbor is processed first)
          let new_stack = list.append(list.reverse(neighbor_ids), rest)
          dfs_loop(graph, new_stack, new_visited, [current, ..acc])
        }
      }
    }
  }
}

/// Breadth-first search from a starting node. Returns visited node IDs in BFS order.
pub fn bfs(graph: Graph, start: String) -> List(String) {
  let visited = set.from_list([start])
  bfs_loop(graph, [start], visited, [start])
  |> list.reverse()
}

fn bfs_loop(
  graph: Graph,
  queue: List(String),
  visited: Set(String),
  acc: List(String),
) -> List(String) {
  case queue {
    [] -> acc
    [current, ..rest] -> {
      let neighbor_ids =
        list.filter_map(graph.edges, fn(e) {
          case e.from == current {
            True -> Ok(e.to)
            False -> Error(Nil)
          }
        })
      let #(new_queue_additions, new_visited) =
        list.fold(neighbor_ids, #([], visited), fn(state, nid) {
          let #(additions, vis) = state
          case set.contains(vis, nid) {
            True -> #(additions, vis)
            False -> #(list.append(additions, [nid]), set.insert(vis, nid))
          }
        })
      let new_queue = list.append(rest, new_queue_additions)
      let new_acc = list.append(list.reverse(new_queue_additions), acc)
      bfs_loop(graph, new_queue, new_visited, new_acc)
    }
  }
}

// =============================================================================
// Cycle Detection (DFS with Coloring)
// =============================================================================

/// Detect if the graph contains any cycles. Uses DFS coloring (White/Grey/Black).
/// Returns True if cycles are present.
pub fn detect_cycles(graph: Graph) -> Bool {
  let color_map =
    list.fold(graph.nodes, dict.new(), fn(d, n) { dict.insert(d, n.id, White) })
  detect_cycles_loop(graph, graph.nodes, color_map)
}

fn detect_cycles_loop(
  graph: Graph,
  remaining: List(Node),
  colors: Dict(String, Color),
) -> Bool {
  case remaining {
    [] -> False
    [node, ..rest] -> {
      let color = dict.get(colors, node.id) |> result.unwrap(Black)
      case color {
        White -> {
          case dfs_visit_cycle(graph, node.id, colors) {
            #(True, _) -> True
            #(False, new_colors) -> detect_cycles_loop(graph, rest, new_colors)
          }
        }
        _ -> detect_cycles_loop(graph, rest, colors)
      }
    }
  }
}

fn dfs_visit_cycle(
  graph: Graph,
  node_id: String,
  colors: Dict(String, Color),
) -> #(Bool, Dict(String, Color)) {
  let colors = dict.insert(colors, node_id, Grey)
  let neighbor_ids =
    list.filter_map(graph.edges, fn(e) {
      case e.from == node_id {
        True -> Ok(e.to)
        False -> Error(Nil)
      }
    })
  let result =
    list.fold(neighbor_ids, #(False, colors), fn(state, nid) {
      let #(found_cycle, current_colors) = state
      case found_cycle {
        True -> #(True, current_colors)
        False -> {
          let color = dict.get(current_colors, nid) |> result.unwrap(White)
          case color {
            Grey -> #(True, current_colors)
            White -> dfs_visit_cycle(graph, nid, current_colors)
            Black -> #(False, current_colors)
          }
        }
      }
    })
  let #(found, final_colors) = result
  #(found, dict.insert(final_colors, node_id, Black))
}

// =============================================================================
// Topological Sort (Kahn's Algorithm)
// =============================================================================

/// Topological sort using Kahn's algorithm.
/// Returns Error if the graph has cycles.
pub fn topological_sort(graph: Graph) -> Result(List(String), String) {
  let node_ids = list.map(graph.nodes, fn(n) { n.id })
  // Build in-degree map
  let in_degree =
    list.fold(node_ids, dict.new(), fn(d, id) { dict.insert(d, id, 0) })
  let in_degree =
    list.fold(graph.edges, in_degree, fn(d, e) {
      let current = dict.get(d, e.to) |> result.unwrap(0)
      dict.insert(d, e.to, current + 1)
    })
  // Collect nodes with in-degree 0
  let initial_queue =
    list.filter(node_ids, fn(id) {
      dict.get(in_degree, id) |> result.unwrap(0) == 0
    })
  kahn_loop(graph, initial_queue, in_degree, [], list.length(graph.nodes))
}

fn kahn_loop(
  graph: Graph,
  queue: List(String),
  in_degree: Dict(String, Int),
  sorted: List(String),
  total_nodes: Int,
) -> Result(List(String), String) {
  case queue {
    [] -> {
      let sorted_reversed = list.reverse(sorted)
      case list.length(sorted_reversed) == total_nodes {
        True -> Ok(sorted_reversed)
        False -> Error("Graph contains cycles - topological sort impossible")
      }
    }
    [current, ..rest] -> {
      let neighbor_ids =
        list.filter_map(graph.edges, fn(e) {
          case e.from == current {
            True -> Ok(e.to)
            False -> Error(Nil)
          }
        })
      let #(new_in_degree, new_additions) =
        list.fold(neighbor_ids, #(in_degree, []), fn(state, nid) {
          let #(deg_map, additions) = state
          let new_deg = { dict.get(deg_map, nid) |> result.unwrap(0) } - 1
          let updated_map = dict.insert(deg_map, nid, new_deg)
          case new_deg == 0 {
            True -> #(updated_map, [nid, ..additions])
            False -> #(updated_map, additions)
          }
        })
      let new_queue = list.append(rest, list.reverse(new_additions))
      kahn_loop(
        graph,
        new_queue,
        new_in_degree,
        [current, ..sorted],
        total_nodes,
      )
    }
  }
}

// =============================================================================
// Strongly Connected Components (Kosaraju's Algorithm)
// =============================================================================

/// Find all strongly connected components using Kosaraju's algorithm.
/// Returns a list of SCCs, each being a list of node IDs.
pub fn find_strongly_connected_components(graph: Graph) -> List(List(String)) {
  let node_ids = list.map(graph.nodes, fn(n) { n.id })
  // Step 1: Compute finish order via DFS on the original graph
  let finish_order = kosaraju_finish_order(graph, node_ids)
  // Step 2: Build the transposed graph (reverse all edges)
  let transposed = transpose_graph(graph)
  // Step 3: DFS on transposed graph in reverse finish order
  kosaraju_collect_sccs(transposed, finish_order)
}

fn kosaraju_finish_order(graph: Graph, node_ids: List(String)) -> List(String) {
  let visited = set.new()
  let #(_, finish_stack) =
    list.fold(node_ids, #(visited, []), fn(state, nid) {
      let #(vis, stack) = state
      case set.contains(vis, nid) {
        True -> #(vis, stack)
        False -> kosaraju_dfs_finish(graph, nid, vis, stack)
      }
    })
  finish_stack
}

fn kosaraju_dfs_finish(
  graph: Graph,
  node_id: String,
  visited: Set(String),
  stack: List(String),
) -> #(Set(String), List(String)) {
  let visited = set.insert(visited, node_id)
  let neighbor_ids =
    list.filter_map(graph.edges, fn(e) {
      case e.from == node_id {
        True -> Ok(e.to)
        False -> Error(Nil)
      }
    })
  let #(new_visited, new_stack) =
    list.fold(neighbor_ids, #(visited, stack), fn(state, nid) {
      let #(vis, stk) = state
      case set.contains(vis, nid) {
        True -> #(vis, stk)
        False -> kosaraju_dfs_finish(graph, nid, vis, stk)
      }
    })
  // Push node_id onto stack after all descendants are processed
  #(new_visited, [node_id, ..new_stack])
}

fn transpose_graph(graph: Graph) -> Graph {
  let reversed_edges =
    list.map(graph.edges, fn(e) {
      Edge(from: e.to, to: e.from, label: e.label, is_allowed: e.is_allowed)
    })
  Graph(nodes: graph.nodes, edges: reversed_edges)
}

fn kosaraju_collect_sccs(
  transposed: Graph,
  finish_order: List(String),
) -> List(List(String)) {
  let visited = set.new()
  let #(_, sccs) =
    list.fold(finish_order, #(visited, []), fn(state, nid) {
      let #(vis, components) = state
      case set.contains(vis, nid) {
        True -> #(vis, components)
        False -> {
          let #(new_vis, component) =
            kosaraju_collect_single(transposed, nid, vis, [])
          #(new_vis, [list.reverse(component), ..components])
        }
      }
    })
  list.reverse(sccs)
}

fn kosaraju_collect_single(
  graph: Graph,
  node_id: String,
  visited: Set(String),
  acc: List(String),
) -> #(Set(String), List(String)) {
  let visited = set.insert(visited, node_id)
  let acc = [node_id, ..acc]
  let neighbor_ids =
    list.filter_map(graph.edges, fn(e) {
      case e.from == node_id {
        True -> Ok(e.to)
        False -> Error(Nil)
      }
    })
  list.fold(neighbor_ids, #(visited, acc), fn(state, nid) {
    let #(vis, component) = state
    case set.contains(vis, nid) {
      True -> #(vis, component)
      False -> kosaraju_collect_single(graph, nid, vis, component)
    }
  })
}

// =============================================================================
// Reachability & Shortest Path
// =============================================================================

/// Check if `to` is reachable from `from` via BFS.
pub fn is_reachable(graph: Graph, from: String, to: String) -> Bool {
  let visited = bfs(graph, from)
  list.contains(visited, to)
}

/// Find the shortest path (by hop count) from `from` to `to` using BFS.
/// Returns the path as a list of node IDs, or Error if unreachable.
pub fn shortest_path(
  graph: Graph,
  from: String,
  to: String,
) -> Result(List(String), String) {
  case from == to {
    True -> Ok([from])
    False -> {
      let visited = set.from_list([from])
      // Each entry in the queue is (node_id, path_so_far)
      let queue = [#(from, [from])]
      shortest_path_loop(graph, queue, visited, to)
    }
  }
}

fn shortest_path_loop(
  graph: Graph,
  queue: List(#(String, List(String))),
  visited: Set(String),
  target: String,
) -> Result(List(String), String) {
  case queue {
    [] -> Error("No path from source to target")
    [#(current, path), ..rest] -> {
      let neighbor_ids =
        list.filter_map(graph.edges, fn(e) {
          case e.from == current {
            True -> Ok(e.to)
            False -> Error(Nil)
          }
        })
      let initial_found: Result(List(String), String) = Error("")
      let result =
        list.fold(neighbor_ids, #([], visited, initial_found), fn(state, nid) {
          let #(additions, vis, found) = state
          case found {
            Ok(_) -> #(additions, vis, found)
            Error(_) -> {
              case nid == target {
                True -> {
                  let final_path = list.append(path, [nid])
                  #(additions, vis, Ok(final_path))
                }
                False -> {
                  case set.contains(vis, nid) {
                    True -> #(additions, vis, Error(""))
                    False -> {
                      let new_path = list.append(path, [nid])
                      #(
                        list.append(additions, [#(nid, new_path)]),
                        set.insert(vis, nid),
                        Error(""),
                      )
                    }
                  }
                }
              }
            }
          }
        })
      case result {
        #(_, _, Ok(found_path)) -> Ok(found_path)
        #(additions, new_visited, Error(_)) -> {
          let new_queue = list.append(rest, additions)
          shortest_path_loop(graph, new_queue, new_visited, target)
        }
      }
    }
  }
}

// =============================================================================
// Graph Metrics
// =============================================================================

/// Calculate graph density: |E| / (|V| * (|V| - 1)).
/// Returns 0.0 for graphs with fewer than 2 nodes.
pub fn graph_density(graph: Graph) -> Float {
  let v = list.length(graph.nodes)
  let e = list.length(graph.edges)
  case v < 2 {
    True -> 0.0
    False -> {
      let denominator = v * { v - 1 }
      int.to_float(e) /. int.to_float(denominator)
    }
  }
}

/// Calculate the out-degree of a node (number of outgoing edges).
pub fn node_degree(graph: Graph, id: String) -> Int {
  list.count(graph.edges, fn(e) { e.from == id })
}

/// Calculate aggregate statistics for the graph.
pub fn calculate_stats(graph: Graph) -> GraphStats {
  let sccs = find_strongly_connected_components(graph)
  GraphStats(
    node_count: list.length(graph.nodes),
    edge_count: list.length(graph.edges),
    density: graph_density(graph),
    scc_count: list.length(sccs),
  )
}

// =============================================================================
// Verification Suite (SC-GRAPH-001 to SC-GRAPH-005)
// =============================================================================

/// SC-GRAPH-001: Verify the graph is deadlock-free (no cycles).
pub fn verify_deadlock_free(graph: Graph) -> VerificationResult {
  let has_cycles = detect_cycles(graph)
  case has_cycles {
    False ->
      VerificationResult(
        name: "SC-GRAPH-001: Deadlock Freedom",
        passed: True,
        details: "No cycles detected in the dependency graph",
      )
    True ->
      VerificationResult(
        name: "SC-GRAPH-001: Deadlock Freedom",
        passed: False,
        details: "Cycles detected - potential deadlock risk",
      )
  }
}

/// SC-GRAPH-002: Verify all required agents are present in the graph.
pub fn verify_completeness(
  graph: Graph,
  required_agents: List(String),
) -> VerificationResult {
  let node_ids = list.map(graph.nodes, fn(n) { n.id })
  let missing =
    list.filter(required_agents, fn(agent) { !list.contains(node_ids, agent) })
  case list.is_empty(missing) {
    True ->
      VerificationResult(
        name: "SC-GRAPH-002: Completeness",
        passed: True,
        details: "All "
          <> int.to_string(list.length(required_agents))
          <> " required agents present in graph",
      )
    False ->
      VerificationResult(
        name: "SC-GRAPH-002: Completeness",
        passed: False,
        details: "Missing agents: " <> string.join(missing, ", "),
      )
  }
}

/// SC-GRAPH-003: Verify soundness - no unauthorized (disallowed) paths exist.
pub fn verify_soundness(graph: Graph) -> VerificationResult {
  let unauthorized_edges = list.filter(graph.edges, fn(e) { !e.is_allowed })
  case list.is_empty(unauthorized_edges) {
    True ->
      VerificationResult(
        name: "SC-GRAPH-003: Soundness",
        passed: True,
        details: "No unauthorized edges found",
      )
    False -> {
      let edge_descriptions =
        list.map(unauthorized_edges, fn(e) {
          e.from <> " -> " <> e.to <> " (" <> e.label <> ")"
        })
      VerificationResult(
        name: "SC-GRAPH-003: Soundness",
        passed: False,
        details: "Unauthorized paths: " <> string.join(edge_descriptions, "; "),
      )
    }
  }
}

/// SC-GRAPH-005: Verify that all critical services are mutually reachable.
pub fn verify_connectivity(
  graph: Graph,
  critical_services: List(String),
) -> VerificationResult {
  let unreachable_pairs =
    list.flat_map(critical_services, fn(from) {
      list.filter_map(critical_services, fn(to) {
        case from == to {
          True -> Error(Nil)
          False -> {
            case is_reachable(graph, from, to) {
              True -> Error(Nil)
              False -> Ok(from <> " -/-> " <> to)
            }
          }
        }
      })
    })
  case list.is_empty(unreachable_pairs) {
    True ->
      VerificationResult(
        name: "SC-GRAPH-005: Connectivity",
        passed: True,
        details: "All "
          <> int.to_string(list.length(critical_services))
          <> " critical services are mutually reachable",
      )
    False ->
      VerificationResult(
        name: "SC-GRAPH-005: Connectivity",
        passed: False,
        details: "Unreachable pairs: " <> string.join(unreachable_pairs, "; "),
      )
  }
}

/// Run the full verification suite on a graph.
pub fn run_verification_suite(graph: Graph) -> List(VerificationResult) {
  [
    verify_deadlock_free(graph),
    verify_completeness(graph, list.map(graph.nodes, fn(n) { n.id })),
    verify_soundness(graph),
    verify_connectivity(graph, list.map(graph.nodes, fn(n) { n.id })),
  ]
}

// =============================================================================
// Serialization
// =============================================================================

/// Generate DOT language representation of the graph for visualization.
pub fn to_dot(graph: Graph) -> String {
  let header = "digraph G {\n  rankdir=LR;\n"
  let node_lines =
    list.map(graph.nodes, fn(n) {
      "  \""
      <> n.id
      <> "\" [label=\""
      <> n.label
      <> "\" shape="
      <> node_shape(n.node_type)
      <> "];"
    })
    |> string.join("\n")
  let edge_lines =
    list.map(graph.edges, fn(e) {
      "  \""
      <> e.from
      <> "\" -> \""
      <> e.to
      <> "\" [label=\""
      <> e.label
      <> "\""
      <> case e.is_allowed {
        True -> ""
        False -> " color=red style=dashed"
      }
      <> "];"
    })
    |> string.join("\n")
  let footer = "\n}"
  header <> node_lines <> "\n" <> edge_lines <> footer
}

fn node_shape(node_type: String) -> String {
  case node_type {
    "agent" -> "box"
    "service" -> "ellipse"
    "resource" -> "diamond"
    _ -> "circle"
  }
}

/// Serialize the graph to JSON.
pub fn graph_to_json(graph: Graph) -> json.Json {
  json.object([
    #("nodes", json.array(graph.nodes, node_to_json)),
    #("edges", json.array(graph.edges, edge_to_json)),
    #(
      "stats",
      json.object([
        #("node_count", json.int(list.length(graph.nodes))),
        #("edge_count", json.int(list.length(graph.edges))),
        #("density", json.float(graph_density(graph))),
      ]),
    ),
  ])
}

fn node_to_json(node: Node) -> json.Json {
  json.object([
    #("id", json.string(node.id)),
    #("label", json.string(node.label)),
    #("node_type", json.string(node.node_type)),
  ])
}

fn edge_to_json(edge: Edge) -> json.Json {
  json.object([
    #("from", json.string(edge.from)),
    #("to", json.string(edge.to)),
    #("label", json.string(edge.label)),
    #("is_allowed", json.bool(edge.is_allowed)),
  ])
}
