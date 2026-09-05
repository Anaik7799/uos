/// Dynamic Topology Tests — C1-C8 Gold Standard
/// STAMP: SC-HA-001, SC-ZENOH-001, SC-BIO-EVO-001
import cepaf_gleam/ha/dynamic_topology as dt
import gleam/list
import gleeunit/should

// C1: Structure
pub fn new_topology_empty_test() {
  let t = dt.new()
  dt.node_count(t) |> should.equal(0)
  dt.edge_count(t) |> should.equal(0)
}

// C2: Node discovery
pub fn node_joined_test() {
  let node = dt.TopologyNode("n1", "compute", 1.0, 100, 100)
  let t = dt.new() |> dt.apply_event(dt.NodeJoined(node))
  dt.node_count(t) |> should.equal(1)
}

pub fn node_left_test() {
  let node = dt.TopologyNode("n1", "compute", 1.0, 100, 100)
  let t =
    dt.new()
    |> dt.apply_event(dt.NodeJoined(node))
    |> dt.apply_event(dt.NodeLeft("n1"))
  dt.node_count(t) |> should.equal(0)
}

// C3: Edge discovery
pub fn edge_discovered_test() {
  let n1 = dt.TopologyNode("a", "compute", 1.0, 100, 100)
  let n2 = dt.TopologyNode("b", "compute", 1.0, 100, 100)
  let edge = dt.TopologyEdge("a", "b", 5.0, 1000.0, 100)
  let t =
    dt.new()
    |> dt.apply_event(dt.NodeJoined(n1))
    |> dt.apply_event(dt.NodeJoined(n2))
    |> dt.apply_event(dt.EdgeDiscovered(edge))
  dt.edge_count(t) |> should.equal(1)
}

pub fn edge_lost_test() {
  let n1 = dt.TopologyNode("a", "compute", 1.0, 100, 100)
  let n2 = dt.TopologyNode("b", "compute", 1.0, 100, 100)
  let edge = dt.TopologyEdge("a", "b", 5.0, 1000.0, 100)
  let t =
    dt.new()
    |> dt.apply_event(dt.NodeJoined(n1))
    |> dt.apply_event(dt.NodeJoined(n2))
    |> dt.apply_event(dt.EdgeDiscovered(edge))
    |> dt.apply_event(dt.EdgeLost("a", "b"))
  dt.edge_count(t) |> should.equal(0)
}

// C4: Neighbors
pub fn neighbors_test() {
  let t =
    dt.new()
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("a", "c", 1.0, 100, 100)))
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("b", "c", 1.0, 100, 100)))
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("c", "c", 1.0, 100, 100)))
    |> dt.apply_event(
      dt.EdgeDiscovered(dt.TopologyEdge("a", "b", 1.0, 100.0, 100)),
    )
    |> dt.apply_event(
      dt.EdgeDiscovered(dt.TopologyEdge("a", "c", 1.0, 100.0, 100)),
    )
  let nbrs = dt.neighbors(t, "a")
  list.length(nbrs) |> should.equal(2)
}

// C5: Connected components (partition detection)
pub fn single_component_test() {
  let t =
    dt.new()
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("a", "c", 1.0, 100, 100)))
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("b", "c", 1.0, 100, 100)))
    |> dt.apply_event(
      dt.EdgeDiscovered(dt.TopologyEdge("a", "b", 1.0, 100.0, 100)),
    )
  let cc = dt.connected_components(t)
  list.length(cc) |> should.equal(1)
  dt.is_connected(t) |> should.be_true()
}

pub fn partition_detected_test() {
  let t =
    dt.new()
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("a", "c", 1.0, 100, 100)))
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("b", "c", 1.0, 100, 100)))
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("c", "c", 1.0, 100, 100)))
    |> dt.apply_event(
      dt.EdgeDiscovered(dt.TopologyEdge("a", "b", 1.0, 100.0, 100)),
    )
  // c is isolated — no edges to a or b
  let cc = dt.connected_components(t)
  list.length(cc) |> should.equal(2)
  dt.is_connected(t) |> should.be_false()
}

// C6: Health
pub fn topology_health_test() {
  let t =
    dt.new()
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("a", "c", 0.8, 100, 100)))
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("b", "c", 1.0, 100, 100)))
  let h = dt.topology_health(t)
  { h >. 0.89 && h <. 0.91 } |> should.be_true()
}

// C7: Stale nodes + prune
pub fn stale_nodes_test() {
  let t =
    dt.new()
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("old", "c", 1.0, 100, 100)))
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("new", "c", 1.0, 500, 500)))
  let stale = dt.stale_nodes(t, 600, 200)
  list.length(stale) |> should.equal(1)
}

pub fn prune_stale_test() {
  let t =
    dt.new()
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("old", "c", 1.0, 100, 100)))
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("new", "c", 1.0, 500, 500)))
    |> dt.prune_stale(600, 200)
  dt.node_count(t) |> should.equal(1)
}

// C8: Summary + find
pub fn summary_nonempty_test() {
  let s = dt.summary(dt.new())
  { s != "" } |> should.be_true()
}

pub fn find_node_test() {
  let t =
    dt.new()
    |> dt.apply_event(
      dt.NodeJoined(dt.TopologyNode("x", "router", 0.9, 100, 100)),
    )
  case dt.find_node(t, "x") {
    Ok(n) -> n.kind |> should.equal("router")
    _ -> should.fail()
  }
}

pub fn generation_increments_test() {
  let t =
    dt.new()
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("a", "c", 1.0, 100, 100)))
    |> dt.apply_event(dt.NodeJoined(dt.TopologyNode("b", "c", 1.0, 100, 100)))
  t.generation |> should.equal(2)
}
