//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/dynamic_topology</module>
////     <fsharp-lineage>None — novel Gleam implementation</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <mesh-domain>Dynamic topology discovery and partition detection</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-HA-001, SC-ZENOH-001, SC-BIO-EVO-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="constructive">
////       Event-driven topology: NodeJoined/Left, EdgeDiscovered/Lost → live graph.
////       BFS partition detection, health aggregation, stale node pruning.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// DYNAMIC TOPOLOGY DISCOVERY
//// गतिशील टोपोलॉजी खोज
////
//// Extends static nav_graph with runtime discovery events.
//// Supports partition detection via connected components (BFS).
////
//// STAMP: SC-HA-001, SC-ZENOH-001, SC-BIO-EVO-001

import gleam/float
import gleam/int
import gleam/list

/// A node in the dynamic topology.
pub type TopologyNode {
  TopologyNode(
    id: String,
    kind: String,
    health: Float,
    discovered_at: Int,
    last_seen: Int,
  )
}

/// An edge in the dynamic topology.
pub type TopologyEdge {
  TopologyEdge(
    from: String,
    to: String,
    latency_ms: Float,
    bandwidth: Float,
    discovered_at: Int,
  )
}

/// The full dynamic topology state.
pub type DynamicTopology {
  DynamicTopology(
    nodes: List(TopologyNode),
    edges: List(TopologyEdge),
    generation: Int,
    last_discovery: Int,
  )
}

/// Discovery events that mutate the topology.
pub type DiscoveryEvent {
  NodeJoined(node: TopologyNode)
  NodeLeft(node_id: String)
  EdgeDiscovered(edge: TopologyEdge)
  EdgeLost(from: String, to: String)
}

/// Create empty topology.
pub fn new() -> DynamicTopology {
  DynamicTopology(nodes: [], edges: [], generation: 0, last_discovery: 0)
}

/// Apply a discovery event.
pub fn apply_event(
  topo: DynamicTopology,
  event: DiscoveryEvent,
) -> DynamicTopology {
  case event {
    NodeJoined(node) -> {
      let filtered = list.filter(topo.nodes, fn(n) { n.id != node.id })
      DynamicTopology(
        ..topo,
        nodes: [node, ..filtered],
        generation: topo.generation + 1,
        last_discovery: node.discovered_at,
      )
    }
    NodeLeft(id) ->
      DynamicTopology(
        ..topo,
        nodes: list.filter(topo.nodes, fn(n) { n.id != id }),
        edges: list.filter(topo.edges, fn(e) { e.from != id && e.to != id }),
        generation: topo.generation + 1,
      )
    EdgeDiscovered(edge) -> {
      let filtered =
        list.filter(topo.edges, fn(e) {
          { e.from != edge.from || e.to != edge.to }
        })
      DynamicTopology(
        ..topo,
        edges: [edge, ..filtered],
        generation: topo.generation + 1,
        last_discovery: edge.discovered_at,
      )
    }
    EdgeLost(from, to) ->
      DynamicTopology(
        ..topo,
        edges: list.filter(topo.edges, fn(e) {
          { e.from != from || e.to != to }
        }),
        generation: topo.generation + 1,
      )
  }
}

/// Count nodes.
pub fn node_count(topo: DynamicTopology) -> Int {
  list.length(topo.nodes)
}

/// Count edges.
pub fn edge_count(topo: DynamicTopology) -> Int {
  list.length(topo.edges)
}

/// Find node by ID.
pub fn find_node(topo: DynamicTopology, id: String) -> Result(TopologyNode, Nil) {
  list.find(topo.nodes, fn(n) { n.id == id })
}

/// Get neighbor node IDs (undirected: both from→to and to→from).
pub fn neighbors(topo: DynamicTopology, node_id: String) -> List(String) {
  topo.edges
  |> list.filter_map(fn(e) {
    case e.from == node_id {
      True -> Ok(e.to)
      False ->
        case e.to == node_id {
          True -> Ok(e.from)
          False -> Error(Nil)
        }
    }
  })
}

/// Connected components via BFS — detects network partitions.
pub fn connected_components(topo: DynamicTopology) -> List(List(String)) {
  let all_ids = list.map(topo.nodes, fn(n) { n.id })
  do_components(topo, all_ids, [])
}

fn do_components(
  topo: DynamicTopology,
  remaining: List(String),
  acc: List(List(String)),
) -> List(List(String)) {
  case remaining {
    [] -> list.reverse(acc)
    [start, ..] -> {
      let component = bfs(topo, [start], [])
      let new_remaining =
        list.filter(remaining, fn(id) { !list.contains(component, id) })
      do_components(topo, new_remaining, [component, ..acc])
    }
  }
}

fn bfs(
  topo: DynamicTopology,
  queue: List(String),
  visited: List(String),
) -> List(String) {
  case queue {
    [] -> list.reverse(visited)
    [current, ..rest] ->
      case list.contains(visited, current) {
        True -> bfs(topo, rest, visited)
        False -> {
          let nbrs = neighbors(topo, current)
          let unvisited =
            list.filter(nbrs, fn(n) {
              !list.contains(visited, n) && !list.contains(queue, n)
            })
          bfs(topo, list.append(rest, unvisited), [current, ..visited])
        }
      }
  }
}

/// Average health across all nodes.
pub fn topology_health(topo: DynamicTopology) -> Float {
  case list.length(topo.nodes) {
    0 -> 0.0
    n -> {
      let sum = list.fold(topo.nodes, 0.0, fn(acc, node) { acc +. node.health })
      sum /. int.to_float(n)
    }
  }
}

/// Find nodes not seen since max_age.
pub fn stale_nodes(
  topo: DynamicTopology,
  current_time: Int,
  max_age: Int,
) -> List(TopologyNode) {
  list.filter(topo.nodes, fn(n) { current_time - n.last_seen > max_age })
}

/// Remove stale nodes and their edges.
pub fn prune_stale(
  topo: DynamicTopology,
  current_time: Int,
  max_age: Int,
) -> DynamicTopology {
  let stale_ids =
    stale_nodes(topo, current_time, max_age)
    |> list.map(fn(n) { n.id })
  DynamicTopology(
    ..topo,
    nodes: list.filter(topo.nodes, fn(n) { !list.contains(stale_ids, n.id) }),
    edges: list.filter(topo.edges, fn(e) {
      !list.contains(stale_ids, e.from) && !list.contains(stale_ids, e.to)
    }),
    generation: topo.generation + 1,
  )
}

/// Is the topology fully connected? (1 component)
pub fn is_connected(topo: DynamicTopology) -> Bool {
  case list.length(topo.nodes) {
    0 -> True
    _ -> list.length(connected_components(topo)) == 1
  }
}

/// Summary string.
pub fn summary(topo: DynamicTopology) -> String {
  let components = connected_components(topo)
  "Topology(nodes="
  <> int.to_string(node_count(topo))
  <> ", edges="
  <> int.to_string(edge_count(topo))
  <> ", components="
  <> int.to_string(list.length(components))
  <> ", health="
  <> float.to_string(topology_health(topo))
  <> ", gen="
  <> int.to_string(topo.generation)
  <> ")"
}
