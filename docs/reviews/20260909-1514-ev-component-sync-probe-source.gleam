import cepaf_gleam/crdt/delta_mesh_engine as engine
import cepaf_gleam/crdt/delta_state
import cepaf_gleam/crdt/mesh_sync
import gleam/io
import gleeunit/should

fn observations() {
  let local = engine.init_engine("a", "nas-1.tail55d152.ts.net", 1)
    |> engine.register_peer("b", "vm-1.tail55d152.ts.net")
    |> engine.record_worker_active("a-worker", 2)
  let old_clock = local.local_mesh_state.vector_clock
  let #(new_clock, _) = delta_state.increment_clock(old_clock, "b")
  let assert Ok(#(known, _)) = engine.handle_incoming_message(
    local, mesh_sync.SyncDigest("b", new_clock, 2, 10), 10,
  )
  engine.is_cluster_fully_synchronized(known) |> should.be_false
  #(known, old_clock)
}

pub fn stale_ack() {
  let #(known, old_clock) = observations()
  let assert Ok(#(result, _)) = engine.handle_incoming_message(
    known, mesh_sync.SyncAck("b", old_clock, "old-ack", 2), 11,
  )
  engine.is_cluster_fully_synchronized(result) |> should.be_false
  io.println("PASS independent_stale_ack_after_newer_digest")
}

pub fn stale_delta() {
  let #(known, _) = observations()
  let old_remote = delta_state.MeshDeltaState(
    ..known.local_mesh_state,
    origin_node: "b",
    epoch_us: 2,
  )
  let assert Ok(#(result, _)) = engine.handle_incoming_message(
    known,
    mesh_sync.SyncDelta("b", old_remote, known.local_health_map, 2),
    11,
  )
  engine.is_cluster_fully_synchronized(result) |> should.be_false
  io.println("PASS independent_stale_delta_after_newer_digest")
}

pub fn main() {
  stale_ack()
  stale_delta()
}
