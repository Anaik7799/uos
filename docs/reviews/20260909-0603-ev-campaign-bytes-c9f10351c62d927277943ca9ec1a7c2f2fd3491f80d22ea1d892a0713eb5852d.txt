// =============================================================================
// [C3I-SIL6-MSTS] CRDT HEALTH BRIDGE TEST SUITE (SC-HEALTH-001)
// =============================================================================

import cepaf_gleam/crdt/health_bridge.{
  detect_divergent_nodes, empty_health_map, evaluate_quorum,
  merge_health_maps, record_health,
}
import gleeunit/should

pub fn record_and_merge_health_test() {
  let map0 = empty_health_map()

  // Node nas-1 is healthy and stable
  let map1 =
    record_health(
      map0,
      "nas-1",
      0.95,
      -0.05,
      True,
      "closed",
      1_700_000_000_000_000,
    )

  // Node vm-1 reports slightly degraded but stable
  let map2 =
    record_health(
      map0,
      "vm-1",
      0.80,
      -0.01,
      True,
      "closed",
      1_700_000_000_050_000,
    )

  // Node worker-3 reports diverging Lyapunov exponent and tripped breaker
  let map3 =
    record_health(
      map0,
      "worker-3",
      0.40,
      0.15,
      False,
      "open",
      1_700_000_000_080_000,
    )

  let cluster = merge_health_maps(merge_health_maps(map1, map2), map3)

  // 2 out of 3 nodes are healthy (66.7%)
  let #(quorum_met, _avg_health, healthy_count, total_count) =
    evaluate_quorum(cluster, 0.66)

  quorum_met |> should.be_true()
  healthy_count |> should.equal(2)
  total_count |> should.equal(3)

  // Divergent nodes should isolate worker-3
  let divergent = detect_divergent_nodes(cluster)
  divergent |> should.equal(["worker-3"])
}

pub fn health_telemetry_lww_convergence_test() {
  let map0 = empty_health_map()

  // Initial state for node-1
  let map_a =
    record_health(
      map0,
      "node-1",
      0.50,
      0.10,
      False,
      "open",
      1_000_000,
    )

  // Newer update from node-1 showing recovery
  let map_b =
    record_health(
      map0,
      "node-1",
      0.98,
      -0.08,
      True,
      "closed",
      2_000_000,
    )

  let converged = merge_health_maps(map_a, map_b)
  let #(quorum_met, avg_health, healthy_count, total_count) =
    evaluate_quorum(converged, 0.9)

  quorum_met |> should.be_true()
  healthy_count |> should.equal(1)
  total_count |> should.equal(1)
  avg_health |> should.equal(0.98)
}
