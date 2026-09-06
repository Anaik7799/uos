import cepaf_gleam/ui/lustre/hyperdimensional_zk_hologram
import gleeunit/should

pub fn zk_hologram_cluster_modularity_test() {
  let hologram = hyperdimensional_zk_hologram.build_canonical_hologram()
  should.be_true(hologram.modularity_q >=. 0.70)
  should.equal(hologram.active_clusters_count, 4)
}

pub fn zk_hologram_node_and_edge_count_test() {
  let hologram = hyperdimensional_zk_hologram.build_canonical_hologram()
  should.be_true(hyperdimensional_zk_hologram.node_count(hologram) >= 16)
  should.be_true(hyperdimensional_zk_hologram.edge_count(hologram) >= 20)
}

pub fn zk_hologram_transclusion_depth_test() {
  let hologram = hyperdimensional_zk_hologram.build_canonical_hologram()
  should.be_true(hologram.max_transclusion_depth <= 16)
  should.equal(hologram.cycle_detected, False)
}
