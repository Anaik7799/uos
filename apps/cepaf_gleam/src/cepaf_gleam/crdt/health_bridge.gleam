//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/crdt/health_bridge</module>
////     <fsharp-lineage>N/A — Pure Gleam/BEAM CRDT Health & Homeostasis Bridge</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT</layer>
////     <layer>L6_ECOSYSTEM</layer>
////     <cross-layer-dependencies>
////       <dep layer="L6_ECOSYSTEM">cepaf_gleam/crdt/delta_state</dep>
////       <dep layer="L0_CONSTITUTIONAL">cepaf_gleam/ha/lyapunov_proof</dep>
////       <dep layer="L3_TRANSACTION">cepaf_gleam/prajna/circuit_breaker</dep>
////     </cross-layer-dependencies>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-HEALTH-001, SC-CRDT-001, SC-SIL6-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="convergence">Merging health maps from any partition sequence produces identical cluster state</property>
////     <property name="monotonicity">Latest timestamped telemetry always supersedes stale metrics</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/crdt/delta_state.{type LWWRegister, type NodeId, merge_lww, new_lww_register}
import gleam/int
import gleam/list

/// Node health telemetry snapshot.
pub type NodeHealthTelemetry {
  NodeHealthTelemetry(
    node: NodeId,
    health_score: Float,
    lyapunov_exponent: Float,
    is_stable: Bool,
    breaker_state: String,
    sample_epoch_us: Int,
  )
}

/// Distributed cluster health map: Map of NodeId to LWWRegister(NodeHealthTelemetry).
pub type ClusterHealthMap =
  List(#(NodeId, LWWRegister(NodeHealthTelemetry)))

/// Creates an empty cluster health map.
pub fn empty_health_map() -> ClusterHealthMap {
  []
}

/// Records or updates a node's health telemetry in the cluster health map.
pub fn record_health(
  map: ClusterHealthMap,
  node: NodeId,
  health_score: Float,
  lyapunov_exponent: Float,
  is_stable: Bool,
  breaker_state: String,
  now_us: Int,
) -> ClusterHealthMap {
  let telemetry =
    NodeHealthTelemetry(
      node: node,
      health_score: health_score,
      lyapunov_exponent: lyapunov_exponent,
      is_stable: is_stable,
      breaker_state: breaker_state,
      sample_epoch_us: now_us,
    )
  let reg = new_lww_register(telemetry, now_us, node)

  case list.key_find(map, node) {
    Ok(existing_reg) -> {
      let merged = merge_lww(existing_reg, reg)
      list.key_set(map, node, merged)
    }
    Error(_) -> [#(node, reg), ..map]
  }
}

/// Merges two distributed cluster health maps taking pointwise LWW registers.
pub fn merge_health_maps(
  a: ClusterHealthMap,
  b: ClusterHealthMap,
) -> ClusterHealthMap {
  let merged_from_a =
    list.map(a, fn(pair) {
      let #(node, reg_a) = pair
      case list.key_find(b, node) {
        Ok(reg_b) -> #(node, merge_lww(reg_a, reg_b))
        Error(_) -> #(node, reg_a)
      }
    })

  let keys_in_a = list.map(a, fn(p) { p.0 })
  let missing_from_b =
    list.filter(b, fn(p) { !list.contains(keys_in_a, p.0) })

  list.append(merged_from_a, missing_from_b)
}

/// Evaluates cluster consensus quorum based on health ratio (e.g. 2oo3 or 66.7%).
/// Returns #(is_quorum_met, average_health, healthy_nodes_count, total_nodes_count).
pub fn evaluate_quorum(
  map: ClusterHealthMap,
  quorum_threshold_ratio: Float,
) -> #(Bool, Float, Int, Int) {
  let total_nodes = list.length(map)
  case total_nodes {
    0 -> #(False, 0.0, 0, 0)
    _ -> {
      let healthy_nodes =
        list.filter(map, fn(pair) {
          let tele = pair.1.value
          tele.health_score >=. 0.7 && tele.is_stable && tele.breaker_state != "open"
        })
      let healthy_count = list.length(healthy_nodes)
      let ratio = int.to_float(healthy_count) /. int.to_float(total_nodes)

      let total_health =
        list.fold(map, 0.0, fn(acc, pair) { acc +. pair.1.value.health_score })
      let avg_health = total_health /. int.to_float(total_nodes)

      let is_met = ratio >=. quorum_threshold_ratio
      #(is_met, avg_health, healthy_count, total_nodes)
    }
  }
}

/// Identifies nodes experiencing Lyapunov divergence or tripped circuit breakers.
pub fn detect_divergent_nodes(map: ClusterHealthMap) -> List(NodeId) {
  list.filter_map(map, fn(pair) {
    let tele = pair.1.value
    case !tele.is_stable || tele.lyapunov_exponent >. 0.0 || tele.breaker_state == "open" {
      True -> Ok(pair.0)
      False -> Error(Nil)
    }
  })
}
