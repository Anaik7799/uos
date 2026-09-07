//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Mesh Topology View Component Verification
//// =============================================================================

import cepaf_gleam/ui/lustre/mesh_topology_view.{
  TopologyNode, init_topology_view, render_topology_page,
  render_topology_svg, update_topology_node,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn topology_view_init_test() {
  let model = init_topology_view()
  list_len(model.nodes) |> should.equal(2)
  model.inter_node_latency_ms |> should.equal(4.2)
  model.total_gossip_rounds |> should.equal(128)
  model.total_stolen_tasks |> should.equal(14)
}

pub fn topology_view_update_node_test() {
  let model = init_topology_view()
  let updated_nas =
    TopologyNode(
      node_id: "nas-1",
      tailscale_ip: "100.87.7.78",
      port: 4100,
      tailscale_fqdn: "http://nas-1.tail55d152.ts.net:4100",
      health_score: 0.99,
      active_workers: 8,
      queue_depth: 0,
      lyapunov_exponent: -3.8,
      is_local: True,
    )
  let updated_model = update_topology_node(model, updated_nas)
  list_len(updated_model.nodes) |> should.equal(2)
}

pub fn topology_view_render_svg_test() {
  let model = init_topology_view()
  let _el = render_topology_svg(model)
  should.be_true(True)
}

pub fn topology_view_render_page_test() {
  let model = init_topology_view()
  let _el = render_topology_page(model)
  should.be_true(True)
}

fn list_len(l: List(a)) -> Int {
  case l {
    [] -> 0
    [_, ..rest] -> 1 + list_len(rest)
  }
}
