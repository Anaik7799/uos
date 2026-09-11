//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/crdt/mesh_sync</module>
////     <fsharp-lineage>N/A — Pure Gleam Multi-Host CRDT Mesh Sync & Anti-Entropy</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <layer>L7_FEDERATION</layer>
////     <cross-layer-dependencies>
////       <dep layer="L6_ECOSYSTEM">cepaf_gleam/crdt/delta_state</dep>
////       <dep layer="L2_COMPONENT">cepaf_gleam/crdt/health_bridge</dep>
////     </cross-layer-dependencies>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-SYNC-001, SC-CRDT-001, SC-TAILSCALE-WEB-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="anti-entropy">Periodic delta-digest exchange guarantees bounded convergence lag delta <= T_sync</property>
////     <property name="partition-safety">Network partition heals monotonically without lost updates upon reconnection</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/crdt/delta_state.{
  type MeshDeltaState, type NodeId, type VectorClock, dominates,
  merge_mesh_states,
}
import cepaf_gleam/crdt/health_bridge.{
  type ClusterHealthMap, merge_health_maps,
}
import gleam/json
import gleam/list

/// Peer sync connection status.
pub type SyncStatus {
  Synchronized
  Lagging(lag_versions: Int)
  Partitioned
  Reconciling
}

/// Description of a cluster peer endpoint.
pub type PeerSyncEndpoint {
  PeerSyncEndpoint(
    node_id: NodeId,
    tailscale_fqdn: String,
    last_sync_epoch_us: Int,
    status: SyncStatus,
  )
}

/// Anti-entropy synchronization protocol messages.
pub type MeshSyncMessage {
  SyncDigest(
    from_node: NodeId,
    vector_clock: VectorClock,
    active_worker_count: Int,
    epoch_us: Int,
  )
  SyncDelta(
    from_node: NodeId,
    delta_state: MeshDeltaState,
    health_map: ClusterHealthMap,
    epoch_us: Int,
  )
  SyncAck(
    from_node: NodeId,
    applied_clock: VectorClock,
    status: String,
    epoch_us: Int,
  )
}

/// Generates a concise synchronization digest for anti-entropy comparison.
pub fn generate_sync_digest(
  local_node: NodeId,
  local_state: MeshDeltaState,
  now_us: Int,
) -> MeshSyncMessage {
  let count = list.length(local_state.active_workers.elements)
  SyncDigest(
    from_node: local_node,
    vector_clock: local_state.vector_clock,
    active_worker_count: count,
    epoch_us: now_us,
  )
}

/// Evaluates if a peer requires delta transmission by comparing vector clocks.
/// Returns True if local state has updates not dominated by remote clock.
pub fn requires_delta_sync(
  local_state: MeshDeltaState,
  remote_clock: VectorClock,
) -> Bool {
  !dominates(remote_clock, local_state.vector_clock)
}

/// Reconciles an incoming remote SyncDelta message into the local store and health map.
/// Returns #(updated_mesh_state, updated_health, ack_message).
pub fn reconcile_remote_delta(
  local_node: NodeId,
  local_state: MeshDeltaState,
  local_health: ClusterHealthMap,
  msg: MeshSyncMessage,
  now_us: Int,
) -> #(MeshDeltaState, ClusterHealthMap, MeshSyncMessage) {
  case msg {
    SyncDelta(_from_node, remote_state, remote_health, _epoch) -> {
      let merged_state = merge_mesh_states(local_state, remote_state)
      let merged_health = merge_health_maps(local_health, remote_health)
      let ack =
        SyncAck(
          from_node: local_node,
          applied_clock: merged_state.vector_clock,
          status: "reconciled_ok",
          epoch_us: now_us,
        )
      #(merged_state, merged_health, ack)
    }
    _ -> {
      let ack =
        SyncAck(
          from_node: local_node,
          applied_clock: local_state.vector_clock,
          status: "ignored_not_a_delta",
          epoch_us: now_us,
        )
      #(local_state, local_health, ack)
    }
  }
}

/// Default multi-host peer topology between nas-1 and vm-1.
pub fn default_cluster_topology(now_us: Int) -> List(PeerSyncEndpoint) {
  [
    PeerSyncEndpoint(
      node_id: "nas-1",
      tailscale_fqdn: "http://nas-1.tail55d152.ts.net:4100",
      last_sync_epoch_us: now_us,
      status: Synchronized,
    ),
    PeerSyncEndpoint(
      node_id: "vm-1",
      tailscale_fqdn: "http://vm-1.tail55d152.ts.net:8088",
      last_sync_epoch_us: now_us,
      status: Synchronized,
    ),
  ]
}

/// Live multi-host peer topology between nas-1 and vm-1 on active C3I port 4100.
pub fn live_cluster_topology(now_us: Int) -> List(PeerSyncEndpoint) {
  [
    PeerSyncEndpoint(
      node_id: "nas-1",
      tailscale_fqdn: "http://nas-1.tail55d152.ts.net:4100",
      last_sync_epoch_us: now_us,
      status: Synchronized,
    ),
    PeerSyncEndpoint(
      node_id: "vm-1",
      tailscale_fqdn: "http://vm-1.tail55d152.ts.net:4100",
      last_sync_epoch_us: now_us,
      status: Synchronized,
    ),
  ]
}

/// Encodes a MeshSyncMessage to typed JSON string.
pub fn sync_message_to_json(msg: MeshSyncMessage) -> String {
  case msg {
    SyncDigest(node, clock, count, epoch) -> {
      let clock_fields =
        list.map(clock, fn(p: #(String, Int)) { #(p.0, json.int(p.1)) })
      json.object([
        #("type", json.string("sync_digest")),
        #("from_node", json.string(node)),
        #("active_worker_count", json.int(count)),
        #("epoch_us", json.int(epoch)),
        #("vector_clock", json.object(clock_fields)),
      ])
      |> json.to_string
    }
    SyncDelta(node, _, _, epoch) -> {
      json.object([
        #("type", json.string("sync_delta")),
        #("from_node", json.string(node)),
        #("epoch_us", json.int(epoch)),
      ])
      |> json.to_string
    }
    SyncAck(node, clock, status, epoch) -> {
      let clock_fields =
        list.map(clock, fn(p: #(String, Int)) { #(p.0, json.int(p.1)) })
      json.object([
        #("type", json.string("sync_ack")),
        #("from_node", json.string(node)),
        #("status", json.string(status)),
        #("epoch_us", json.int(epoch)),
        #("applied_clock", json.object(clock_fields)),
      ])
      |> json.to_string
    }
  }
}
