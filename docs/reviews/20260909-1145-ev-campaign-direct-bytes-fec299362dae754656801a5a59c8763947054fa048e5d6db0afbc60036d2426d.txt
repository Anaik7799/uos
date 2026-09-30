//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/crdt/delta_mesh_engine</module>
////     <fsharp-lineage>N/A — Pure Gleam Multi-Host CRDT Delta Mesh Engine</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <layer>L7_FEDERATION</layer>
////     <cross-layer-dependencies>
////       <dep layer="L6_ECOSYSTEM">cepaf_gleam/crdt/delta_state</dep>
////       <dep layer="L2_COMPONENT">cepaf_gleam/crdt/health_bridge</dep>
////       <dep layer="L6_ECOSYSTEM">cepaf_gleam/crdt/mesh_sync</dep>
////     </cross-layer-dependencies>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-SYNC-001, SC-CRDT-001, SC-TAILSCALE-WEB-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="anti-entropy-convergence">Gossip rounds monotonically reduce version divergence to zero</property>
////     <property name="deterministic-merge">Concurrent updates resolve deterministically across all peers</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/crdt/delta_state.{
  type MeshDeltaState, type NodeId, increment_clock, new_mesh_delta_state,
  orset_add, pncounter_increment,
}
import cepaf_gleam/crdt/health_bridge.{
  type ClusterHealthMap, empty_health_map, evaluate_quorum, record_health_from,
}
import cepaf_gleam/crdt/mesh_sync.{
  type MeshSyncMessage, type PeerSyncEndpoint, PeerSyncEndpoint, Reconciling,
  SyncAck, SyncDelta, SyncDigest, Synchronized, generate_sync_digest,
  reconcile_remote_delta, requires_delta_sync,
}
import gleam/int
import gleam/list
import gleam/result

/// Maximum accepted outbound messages retained by this pure state machine.
pub const max_pending_outbound = 256

/// The caller retains its original state and must drain/retry on rejection.
pub type OutboundError {
  OutboundQueueFull(capacity: Int)
}

/// The Delta Mesh Engine state.
pub type DeltaMeshEngine {
  DeltaMeshEngine(
    local_node_id: NodeId,
    local_fqdn: String,
    local_mesh_state: MeshDeltaState,
    local_health_map: ClusterHealthMap,
    peers: List(PeerSyncEndpoint),
    gossip_round: Int,
    pending_outbound: List(MeshSyncMessage),
  )
}

/// Initialize the Delta Mesh Engine for a local node.
pub fn init_engine(
  node_id: NodeId,
  fqdn: String,
  now_us: Int,
) -> DeltaMeshEngine {
  DeltaMeshEngine(
    local_node_id: node_id,
    local_fqdn: fqdn,
    local_mesh_state: new_mesh_delta_state(node_id, now_us),
    local_health_map: empty_health_map(),
    peers: [],
    gossip_round: 0,
    pending_outbound: [],
  )
}

/// Register a remote cluster peer into the engine.
pub fn register_peer(
  engine: DeltaMeshEngine,
  peer_node_id: NodeId,
  peer_fqdn: String,
) -> DeltaMeshEngine {
  let existing_filtered =
    list.filter(engine.peers, fn(p) { p.node_id != peer_node_id })
  let new_peer =
    PeerSyncEndpoint(
      node_id: peer_node_id,
      tailscale_fqdn: peer_fqdn,
      last_sync_epoch_us: 0,
      status: Reconciling,
    )
  DeltaMeshEngine(..engine, peers: [new_peer, ..existing_filtered])
}

/// Record a local worker activation.
pub fn record_worker_active(
  engine: DeltaMeshEngine,
  worker_id: String,
  now_us: Int,
) -> DeltaMeshEngine {
  let #(new_clock, dot) =
    increment_clock(engine.local_mesh_state.vector_clock, engine.local_node_id)
  let new_workers =
    orset_add(engine.local_mesh_state.active_workers, worker_id, dot)
  let new_tasks =
    pncounter_increment(
      engine.local_mesh_state.task_counters,
      engine.local_node_id,
      1,
    )

  let old_state = engine.local_mesh_state
  let new_mesh =
    delta_state.MeshDeltaState(
      origin_node: old_state.origin_node,
      epoch_us: int.max(old_state.epoch_us, now_us),
      vector_clock: new_clock,
      active_workers: new_workers,
      task_counters: new_tasks,
      leader_lease: old_state.leader_lease,
    )
  DeltaMeshEngine(..engine, local_mesh_state: new_mesh)
}

/// Record a local health metric observation.
pub fn record_local_health(
  engine: DeltaMeshEngine,
  target_node: String,
  health_score: Float,
  lyapunov_exp: Float,
  is_stable: Bool,
  breaker_state: String,
  epoch_us: Int,
) -> DeltaMeshEngine {
  let new_health =
    record_health_from(
      engine.local_health_map,
      engine.local_node_id,
      target_node,
      health_score,
      lyapunov_exp,
      is_stable,
      breaker_state,
      epoch_us,
    )
  case new_health == engine.local_health_map {
    True -> engine
    False -> {
      let #(clock, _) =
        increment_clock(
          engine.local_mesh_state.vector_clock,
          engine.local_node_id,
        )
      let mesh =
        delta_state.MeshDeltaState(
          ..engine.local_mesh_state,
          vector_clock: clock,
          epoch_us: int.max(engine.local_mesh_state.epoch_us, epoch_us),
        )
      DeltaMeshEngine(
        ..engine,
        local_health_map: new_health,
        local_mesh_state: mesh,
      )
    }
  }
}

fn enqueue_outbound(
  engine: DeltaMeshEngine,
  message: MeshSyncMessage,
) -> Result(DeltaMeshEngine, OutboundError) {
  case list.length(engine.pending_outbound) >= max_pending_outbound {
    True -> Error(OutboundQueueFull(max_pending_outbound))
    False ->
      Ok(
        DeltaMeshEngine(
          ..engine,
          pending_outbound: list.append(engine.pending_outbound, [message]),
        ),
      )
  }
}

/// Transfer all accepted messages to the caller in FIFO order.
/// This is an in-memory handoff, not a network delivery acknowledgement.
pub fn drain_pending_outbound(
  engine: DeltaMeshEngine,
) -> #(DeltaMeshEngine, List(MeshSyncMessage)) {
  #(DeltaMeshEngine(..engine, pending_outbound: []), engine.pending_outbound)
}

/// Generate and queue a digest, or explicitly reject without advancing state.
pub fn generate_gossip_digest(
  engine: DeltaMeshEngine,
  epoch_us: Int,
) -> Result(#(DeltaMeshEngine, MeshSyncMessage), OutboundError) {
  let epoch_us = int.max(engine.local_mesh_state.epoch_us, epoch_us)
  let digest =
    generate_sync_digest(
      engine.local_node_id,
      engine.local_mesh_state,
      epoch_us,
    )
  use queued <- result.try(enqueue_outbound(engine, digest))
  let updated_engine =
    DeltaMeshEngine(
      ..queued,
      gossip_round: engine.gossip_round + 1,
      local_mesh_state: delta_state.MeshDeltaState(
        ..engine.local_mesh_state,
        epoch_us: epoch_us,
      ),
    )
  Ok(#(updated_engine, digest))
}

/// Handle an incoming sync protocol message from a peer.
pub fn handle_incoming_message(
  engine: DeltaMeshEngine,
  msg: MeshSyncMessage,
  current_epoch_us: Int,
) -> Result(#(DeltaMeshEngine, List(MeshSyncMessage)), OutboundError) {
  let current_epoch_us =
    int.max(current_epoch_us, engine.local_mesh_state.epoch_us)
  // This local value is returned only after any required enqueue succeeds.
  // Refusal therefore exposes no updated observation watermark to the caller.
  let engine =
    DeltaMeshEngine(
      ..engine,
      local_mesh_state: delta_state.MeshDeltaState(
        ..engine.local_mesh_state,
        epoch_us: current_epoch_us,
      ),
    )
  case msg {
    SyncDigest(from_node, remote_clock, _count, _epoch) -> {
      case requires_delta_sync(engine.local_mesh_state, remote_clock) {
        True -> {
          let delta_msg =
            SyncDelta(
              from_node: engine.local_node_id,
              delta_state: engine.local_mesh_state,
              health_map: engine.local_health_map,
              epoch_us: current_epoch_us,
            )
          use queued <- result.try(enqueue_outbound(engine, delta_msg))
          let updated_peers =
            mark_peer_status(
              engine.peers,
              from_node,
              Synchronized,
              current_epoch_us,
            )
          let updated_engine = DeltaMeshEngine(..queued, peers: updated_peers)
          Ok(#(updated_engine, [delta_msg]))
        }
        False -> {
          let ack_msg =
            SyncAck(
              from_node: engine.local_node_id,
              applied_clock: engine.local_mesh_state.vector_clock,
              status: "clock_in_sync",
              epoch_us: current_epoch_us,
            )
          use queued <- result.try(enqueue_outbound(engine, ack_msg))
          let updated_peers =
            mark_peer_status(
              engine.peers,
              from_node,
              Synchronized,
              current_epoch_us,
            )
          let updated_engine = DeltaMeshEngine(..queued, peers: updated_peers)
          Ok(#(updated_engine, [ack_msg]))
        }
      }
    }
    SyncDelta(from_node, _, _, _) -> {
      let #(merged_mesh, merged_health, ack) =
        reconcile_remote_delta(
          engine.local_node_id,
          engine.local_mesh_state,
          engine.local_health_map,
          msg,
          current_epoch_us,
        )
      use queued <- result.try(enqueue_outbound(engine, ack))
      let updated_peers =
        mark_peer_status(
          engine.peers,
          from_node,
          Synchronized,
          current_epoch_us,
        )
      let updated_engine =
        DeltaMeshEngine(
          ..queued,
          local_mesh_state: merged_mesh,
          local_health_map: merged_health,
          peers: updated_peers,
        )
      Ok(#(updated_engine, [ack]))
    }
    SyncAck(from_node, _, _, _) -> {
      let updated_peers =
        mark_peer_status(
          engine.peers,
          from_node,
          Synchronized,
          current_epoch_us,
        )
      let updated_engine = DeltaMeshEngine(..engine, peers: updated_peers)
      Ok(#(updated_engine, []))
    }
  }
}

fn mark_peer_status(
  peers: List(PeerSyncEndpoint),
  node: NodeId,
  status: mesh_sync.SyncStatus,
  now_us: Int,
) -> List(PeerSyncEndpoint) {
  list.map(peers, fn(p) {
    case p.node_id == node {
      True ->
        PeerSyncEndpoint(
          node_id: p.node_id,
          tailscale_fqdn: p.tailscale_fqdn,
          last_sync_epoch_us: int.max(p.last_sync_epoch_us, now_us),
          status: status,
        )
      False -> p
    }
  })
}

/// Check if all registered cluster peers are synchronized.
pub fn is_cluster_fully_synchronized(engine: DeltaMeshEngine) -> Bool {
  case engine.peers {
    [] -> True
    peers ->
      list.all(peers, fn(p) {
        case p.status {
          Synchronized -> True
          _ -> False
        }
      })
  }
}

/// Compute aggregate cluster health score [0.0, 1.0].
pub fn compute_cluster_aggregate_health(engine: DeltaMeshEngine) -> Float {
  let #(_is_met, avg_health, _healthy_cnt, total_nodes) =
    evaluate_quorum(engine.local_health_map, 0.5)
  case total_nodes {
    0 -> 1.0
    _ -> avg_health
  }
}
