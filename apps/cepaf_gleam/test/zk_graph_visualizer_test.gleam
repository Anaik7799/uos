import cepaf_gleam/ui/lustre/zk_graph_visualizer
import gleeunit/should

pub fn canonical_zk_graph_construction_test() {
  let graph = zk_graph_visualizer.build_canonical_zk_graph()
  // Must contain all 16 ADRs plus MOC (at least 17 nodes)
  let node_count = zk_graph_visualizer.node_count(graph)
  should.be_true(node_count >= 17)
  let edge_count = zk_graph_visualizer.edge_count(graph)
  should.be_true(edge_count >= 20)
}

pub fn graph_strongly_connected_test() {
  let graph = zk_graph_visualizer.build_canonical_zk_graph()
  zk_graph_visualizer.verify_graph_strongly_connected(graph)
  |> should.be_true()
}

pub fn graph_modularity_threshold_test() {
  let graph = zk_graph_visualizer.build_canonical_zk_graph()
  // Louvain modularity Q must exceed 0.40 for structured communities
  should.be_true(graph.modularity_q >=. 0.4)
}

pub fn cluster_color_mapping_test() {
  zk_graph_visualizer.calculate_cluster_color(0) |> should.equal("#58a6ff")
  // Blue
  zk_graph_visualizer.calculate_cluster_color(1) |> should.equal("#3fb950")
  // Green
  zk_graph_visualizer.calculate_cluster_color(2) |> should.equal("#bc8cff")
  // Purple
  zk_graph_visualizer.calculate_cluster_color(3) |> should.equal("#f0883e")
  // Amber
}

pub fn render_svg_graph_html_test() {
  let graph = zk_graph_visualizer.build_canonical_zk_graph()
  let html = zk_graph_visualizer.render_svg_graph_html(graph)
  should.be_true(zk_graph_visualizer.string_contains(html, "<svg"))
  should.be_true(zk_graph_visualizer.string_contains(html, "ADR-001"))
  should.be_true(zk_graph_visualizer.string_contains(html, "</svg>"))
}
