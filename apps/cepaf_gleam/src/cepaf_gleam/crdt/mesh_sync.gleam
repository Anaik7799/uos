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
  type MeshDeltaState, type NodeId, type VectorClock, Dot, LWWRegister,
  MeshDeltaState, ORSet, PNCounter, dominates, merge_mesh_states,
}
import cepaf_gleam/crdt/health_bridge.{
  type ClusterHealthMap, NodeHealthTelemetry, merge_health_maps,
}
import cepaf_gleam/crdt/mesh_wire.{
  type Value, type WireError, Array, Boolean, CollectionLimit, DuplicateDot,
  DuplicateKey, Integer, InvalidIdentity, InvalidShape, NodeMismatch, Real, Text,
}
import gleam/json
import gleam/list
import gleam/result
import gleam/string

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

/// Compatibility diagnostic JSON. This is not a validated transport envelope;
/// use encode_sync_message and decode_sync_message at a wire boundary.
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
    SyncDelta(node, state, health, epoch) -> {
      json.object([
        #("type", json.string("sync_delta")),
        #("from_node", json.string(node)),
        #("epoch_us", json.int(epoch)),
        #("delta_state", mesh_wire.diagnostic_json(state_value(state))),
        #("health_map", mesh_wire.diagnostic_json(health_value(health))),
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

// Version 1 wire grammar: [1, tag, sender, ...payload..., epoch]. Every nested
// record is a fixed-length array; every association list preserves entry order.
// Origin need not equal sender: peers legitimately forward merged state.
fn clock_value(clock: VectorClock) -> Value {
  Array(list.map(clock, fn(p) { Array([Text(p.0), Integer(p.1)]) }))
}

fn dot_value(dot: delta_state.Dot) -> Value {
  Array([Text(dot.node), Integer(dot.counter)])
}

fn state_value(state: MeshDeltaState) -> Value {
  Array([
    Text(state.origin_node),
    Integer(state.epoch_us),
    clock_value(state.vector_clock),
    Array([
      Array(
        list.map(state.active_workers.elements, fn(p) {
          Array([Text(p.0), dot_value(p.1)])
        }),
      ),
      Array(list.map(state.active_workers.tombstones, dot_value)),
    ]),
    Array([
      clock_value(state.task_counters.positive),
      clock_value(state.task_counters.negative),
    ]),
    Array([
      Text(state.leader_lease.value),
      Integer(state.leader_lease.timestamp_us),
      Text(state.leader_lease.writer),
    ]),
  ])
}

fn health_value(health: ClusterHealthMap) -> Value {
  Array(
    list.map(health, fn(p) {
      let reg = p.1
      let h = reg.value
      Array([
        Text(p.0),
        Array([
          Array([
            Text(h.node),
            Real(h.health_score),
            Real(h.lyapunov_exponent),
            Boolean(h.is_stable),
            Text(h.breaker_state),
            Integer(h.sample_epoch_us),
          ]),
          Integer(reg.timestamp_us),
          Text(reg.writer),
        ]),
      ])
    }),
  )
}

fn message_value(message: MeshSyncMessage) -> Value {
  case message {
    SyncDigest(node, clock, count, epoch) ->
      Array([
        Integer(1),
        Text("sync_digest"),
        Text(node),
        clock_value(clock),
        Integer(count),
        Integer(epoch),
      ])
    SyncDelta(node, state, health, epoch) ->
      Array([
        Integer(1),
        Text("sync_delta"),
        Text(node),
        state_value(state),
        health_value(health),
        Integer(epoch),
      ])
    SyncAck(node, clock, status, epoch) ->
      Array([
        Integer(1),
        Text("sync_ack"),
        Text(node),
        clock_value(clock),
        Text(status),
        Integer(epoch),
      ])
  }
}

fn bounded_message(message: MeshSyncMessage) -> Bool {
  case message {
    SyncDigest(_, clock, _, _) | SyncAck(_, clock, _, _) ->
      mesh_wire.bounded_list(clock)
    SyncDelta(_, state, health, _) ->
      mesh_wire.bounded_list(state.vector_clock)
      && mesh_wire.bounded_list(state.active_workers.elements)
      && mesh_wire.bounded_list(state.active_workers.tombstones)
      && mesh_wire.bounded_list(state.task_counters.positive)
      && mesh_wire.bounded_list(state.task_counters.negative)
      && mesh_wire.bounded_list(health)
  }
}

/// Validates shape, identities and bounds before emitting any wire bytes.
/// Float metrics must be finite; epochs/counters/versions use nonnegative safe
/// JSON integers. Validation does not authenticate the supplied identities.
pub fn encode_sync_message(
  message: MeshSyncMessage,
) -> Result(String, WireError) {
  use _ <- result.try(case bounded_message(message) {
    True -> Ok(Nil)
    False -> Error(CollectionLimit)
  })
  let value = message_value(message)
  use _ <- result.try(mesh_wire.validate(value))
  use _ <- result.try(read_message(value))
  mesh_wire.encode(value)
}

pub fn decode_sync_message(
  bytes: String,
) -> Result(MeshSyncMessage, WireError) {
  use value <- result.try(mesh_wire.parse(bytes))
  read_message(value)
}

/// The decoded message reaches the existing merge only after full validation.
/// Rejection returns no proposed state change; the caller retains its originals.
pub fn reconcile_remote_wire(
  local_node: NodeId,
  local_state: MeshDeltaState,
  local_health: ClusterHealthMap,
  bytes: String,
  now_us: Int,
) -> Result(#(MeshDeltaState, ClusterHealthMap, MeshSyncMessage), WireError) {
  use message <- result.try(decode_sync_message(bytes))
  Ok(reconcile_remote_delta(
    local_node,
    local_state,
    local_health,
    message,
    now_us,
  ))
}

fn identity(node: String) -> Result(String, WireError) {
  case string.trim(node) != "" {
    True -> Ok(node)
    False -> Error(InvalidIdentity)
  }
}

fn unique_keys(
  entries: List(#(String, a)),
) -> Result(List(#(String, a)), WireError) {
  let keys = list.map(entries, fn(p) { p.0 })
  case list.length(list.unique(keys)) == list.length(keys) {
    True -> Ok(entries)
    False -> Error(DuplicateKey)
  }
}

fn read_clock(value: Value) -> Result(VectorClock, WireError) {
  case value {
    Array(entries) -> {
      use clock <- result.try(
        list.try_map(entries, fn(entry) {
          case entry {
            Array([Text(node), Integer(counter)]) -> {
              use node <- result.try(identity(node))
              Ok(#(node, counter))
            }
            _ -> Error(InvalidShape)
          }
        }),
      )
      unique_keys(clock)
    }
    _ -> Error(InvalidShape)
  }
}

fn read_dot(value: Value) -> Result(delta_state.Dot, WireError) {
  case value {
    Array([Text(node), Integer(counter)]) -> {
      use node <- result.try(identity(node))
      Ok(Dot(node, counter))
    }
    _ -> Error(InvalidShape)
  }
}

fn read_workers(value: Value) -> Result(delta_state.ORSet(String), WireError) {
  case value {
    Array([Array(elements), Array(tombstones)]) -> {
      use elements <- result.try(
        list.try_map(elements, fn(entry) {
          case entry {
            Array([Text(worker), dot]) -> {
              use dot <- result.try(read_dot(dot))
              Ok(#(worker, dot))
            }
            _ -> Error(InvalidShape)
          }
        }),
      )
      use tombstones <- result.try(list.try_map(tombstones, read_dot))
      let dots = list.append(list.map(elements, fn(p) { p.1 }), tombstones)
      case list.length(list.unique(dots)) == list.length(dots) {
        True -> Ok(ORSet(elements, tombstones))
        False -> Error(DuplicateDot)
      }
    }
    _ -> Error(InvalidShape)
  }
}

fn read_state(value: Value) -> Result(MeshDeltaState, WireError) {
  case value {
    Array([
      Text(origin),
      Integer(epoch),
      clock,
      workers,
      Array([positive, negative]),
      Array([Text(leader), Integer(version), Text(writer)]),
    ]) -> {
      use origin <- result.try(identity(origin))
      use writer <- result.try(identity(writer))
      use clock <- result.try(read_clock(clock))
      use workers <- result.try(read_workers(workers))
      use positive <- result.try(read_clock(positive))
      use negative <- result.try(read_clock(negative))
      Ok(MeshDeltaState(
        origin,
        epoch,
        clock,
        workers,
        PNCounter(positive, negative),
        LWWRegister(leader, version, writer),
      ))
    }
    _ -> Error(InvalidShape)
  }
}

fn read_health(value: Value) -> Result(ClusterHealthMap, WireError) {
  case value {
    Array(entries) -> {
      use health <- result.try(
        list.try_map(entries, fn(entry) {
          case entry {
            Array([
              Text(key),
              Array([
                Array([
                  Text(node),
                  Real(score),
                  Real(exponent),
                  Boolean(stable),
                  Text(breaker),
                  Integer(sample),
                ]),
                Integer(version),
                Text(writer),
              ]),
            ]) -> {
              use node <- result.try(identity(node))
              use writer <- result.try(identity(writer))
              case key == node {
                True ->
                  Ok(#(
                    key,
                    LWWRegister(
                      NodeHealthTelemetry(
                        node,
                        score,
                        exponent,
                        stable,
                        breaker,
                        sample,
                      ),
                      version,
                      writer,
                    ),
                  ))
                False -> Error(NodeMismatch)
              }
            }
            _ -> Error(InvalidShape)
          }
        }),
      )
      unique_keys(health)
    }
    _ -> Error(InvalidShape)
  }
}

fn read_message(value: Value) -> Result(MeshSyncMessage, WireError) {
  case value {
    Array([
      Integer(1),
      Text("sync_digest"),
      Text(node),
      clock,
      Integer(count),
      Integer(epoch),
    ]) -> {
      use node <- result.try(identity(node))
      use clock <- result.try(read_clock(clock))
      Ok(SyncDigest(node, clock, count, epoch))
    }
    Array([
      Integer(1),
      Text("sync_delta"),
      Text(node),
      state,
      health,
      Integer(epoch),
    ]) -> {
      use node <- result.try(identity(node))
      use state <- result.try(read_state(state))
      use health <- result.try(read_health(health))
      Ok(SyncDelta(node, state, health, epoch))
    }
    Array([
      Integer(1),
      Text("sync_ack"),
      Text(node),
      clock,
      Text(status),
      Integer(epoch),
    ]) -> {
      use node <- result.try(identity(node))
      use clock <- result.try(read_clock(clock))
      Ok(SyncAck(node, clock, status, epoch))
    }
    _ -> Error(InvalidShape)
  }
}
