//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Multi-Host CRDT Delta Mesh Engine Verification
//// =============================================================================

import cepaf_gleam/crdt/delta_mesh_engine.{
  OutboundQueueFull, compute_cluster_aggregate_health, drain_pending_outbound,
  generate_gossip_digest, handle_incoming_message, init_engine,
  is_cluster_fully_synchronized, record_local_health, record_worker_active,
  register_peer,
}
import cepaf_gleam/crdt/mesh_sync.{SyncAck, SyncDelta, SyncDigest}
import gleam/list
import gleeunit
import gleeunit/should

pub fn health_observation_advances_causal_clock_test() {
  let engine = init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
  let updated =
    record_local_health(engine, "nas-1", 0.9, -1.0, True, "closed", 2000)
  should.not_equal(
    updated.local_mesh_state.vector_clock,
    engine.local_mesh_state.vector_clock,
  )
  updated.local_mesh_state.epoch_us |> should.equal(2000)
}

pub fn worker_observation_epoch_cannot_regress_test() {
  let engine = init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 2000)
  let updated = record_worker_active(engine, "worker", 1000)
  updated.local_mesh_state.epoch_us |> should.equal(2000)
}

pub fn stale_health_does_not_advance_clock_test() {
  let engine =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> record_local_health("nas-1", 0.9, -1.0, True, "closed", 2000)
  record_local_health(engine, "nas-1", 0.1, 1.0, False, "open", 1500)
  |> should.equal(engine)
}

pub fn gossip_queue_is_bounded_test() {
  let engine =
    list.fold(
      list.repeat(1000, 300),
      init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000),
      fn(engine, epoch) {
        case generate_gossip_digest(engine, epoch) {
          Ok(#(updated, _)) -> updated
          Error(OutboundQueueFull(_)) -> engine
        }
      },
    )
  list.length(engine.pending_outbound) |> should.equal(256)
}

pub fn main() {
  gleeunit.main()
}

pub fn engine_init_test() {
  let engine = init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
  engine.local_node_id |> should.equal("nas-1")
  engine.gossip_round |> should.equal(0)
  is_cluster_fully_synchronized(engine) |> should.be_true()
  compute_cluster_aggregate_health(engine) |> should.equal(1.0)
}

pub fn engine_register_peer_test() {
  let engine =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> register_peer("vm-1", "vm-1.tail55d152.ts.net:8088")

  should.equal(1, list_len(engine.peers))
  is_cluster_fully_synchronized(engine) |> should.be_false()
}

pub fn engine_local_mutation_and_gossip_test() {
  let engine =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> register_peer("vm-1", "vm-1.tail55d152.ts.net:8088")
    |> record_worker_active("worker-1", 1000)

  let assert Ok(#(updated_engine, digest)) =
    generate_gossip_digest(engine, 1000)
  updated_engine.gossip_round |> should.equal(1)

  case digest {
    SyncDigest(from, _, active_count, epoch) -> {
      from |> should.equal("nas-1")
      active_count |> should.equal(1)
      epoch |> should.equal(1000)
    }
    _ -> should.fail()
  }
}

pub fn engine_two_node_reconciliation_test() {
  let engine_nas =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> register_peer("vm-1", "vm-1.tail55d152.ts.net:8088")
    |> record_worker_active("worker-nas-1", 1000)

  let engine_vm =
    init_engine("vm-1", "vm-1.tail55d152.ts.net:8088", 1000)
    |> register_peer("nas-1", "nas-1.tail55d152.ts.net:4100")
    |> record_worker_active("worker-vm-1", 1000)

  // VM sends digest to NAS
  let assert Ok(#(_, vm_digest)) = generate_gossip_digest(engine_vm, 1000)
  let assert Ok(#(nas_after_digest, nas_responses)) =
    handle_incoming_message(engine_nas, vm_digest, 1100)

  // NAS should respond with SyncDelta containing its mutation
  should.be_true(list_len(nas_responses) >= 1)
  is_cluster_fully_synchronized(nas_after_digest) |> should.be_true()

  let delta_msg = case nas_responses {
    [d, ..] -> d
    _ -> panic as "expected delta response"
  }

  // VM handles NAS's delta
  let assert Ok(#(vm_after_delta, vm_responses)) =
    handle_incoming_message(engine_vm, delta_msg, 1200)

  // VM now has NAS's peer marked synchronized and responds with SyncAck
  is_cluster_fully_synchronized(vm_after_delta) |> should.be_true()
  should.be_true(list_len(vm_responses) >= 1)
}

pub fn engine_health_aggregation_test() {
  let engine =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> record_local_health("nas-1", 0.95, -3.2, True, "closed", 1000)
    |> record_local_health("vm-1", 0.85, -2.1, True, "closed", 1000)

  let score = compute_cluster_aggregate_health(engine)
  should.be_true(score >=. 0.89 && score <=. 0.91)
}

fn list_len(l: List(a)) -> Int {
  case l {
    [] -> 0
    [_, ..rest] -> 1 + list_len(rest)
  }
}

fn full_queue() {
  list.fold(
    list.repeat(1000, 256),
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000),
    fn(engine, epoch) {
      let assert Ok(#(updated, _)) = generate_gossip_digest(engine, epoch)
      updated
    },
  )
}

pub fn full_queue_rejects_without_advancing_round_and_can_drain_test() {
  let full = full_queue()
  generate_gossip_digest(full, 2000)
  |> should.equal(Error(OutboundQueueFull(256)))
  full.gossip_round |> should.equal(256)
  let #(drained, messages) = drain_pending_outbound(full)
  messages |> should.equal(full.pending_outbound)
  list.length(messages) |> should.equal(256)
  drained.pending_outbound |> should.equal([])
  let assert Ok(#(retried, _)) = generate_gossip_digest(drained, 2000)
  retried.gossip_round |> should.equal(257)
}

pub fn outbound_drain_retains_fifo_and_is_empty_on_repeat_test() {
  let engine = init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
  let assert Ok(#(one, first)) = generate_gossip_digest(engine, 1100)
  let assert Ok(#(two, second)) = generate_gossip_digest(one, 1200)
  let #(drained, messages) = drain_pending_outbound(two)
  messages |> should.equal([first, second])
  drain_pending_outbound(drained) |> should.equal(#(drained, []))
}

pub fn full_queue_defers_delta_application_until_retry_test() {
  let full = full_queue()
  let remote =
    init_engine("vm-1", "vm-1.tail55d152.ts.net:8088", 1000)
    |> record_worker_active("remote-worker", 2000)
  let msg =
    SyncDelta("vm-1", remote.local_mesh_state, remote.local_health_map, 2000)
  handle_incoming_message(full, msg, 2000)
  |> should.equal(Error(OutboundQueueFull(256)))
  let #(drained, _) = drain_pending_outbound(full)
  let assert Ok(#(applied, replies)) =
    handle_incoming_message(drained, msg, 2000)
  list.length(applied.local_mesh_state.active_workers.elements)
  |> should.equal(1)
  list.length(replies) |> should.equal(1)
  applied.pending_outbound |> should.equal(replies)
}

pub fn full_queue_can_receive_ack_and_peer_time_does_not_regress_test() {
  let full =
    full_queue() |> register_peer("vm-1", "vm-1.tail55d152.ts.net:8088")
  let msg =
    SyncAck("vm-1", full.local_mesh_state.vector_clock, "clock_in_sync", 2000)
  let assert Ok(#(observed, [])) = handle_incoming_message(full, msg, 3000)
  let assert Ok(#(again, [])) = handle_incoming_message(observed, msg, 2000)
  let assert [peer] = again.peers
  peer.last_sync_epoch_us |> should.equal(3000)
  list.length(again.pending_outbound) |> should.equal(256)
}

pub fn health_only_change_generates_delta_against_previous_clock_test() {
  let prior = init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
  let updated =
    record_local_health(prior, "nas-1", 0.8, -1.0, True, "closed", 2000)
  let digest = SyncDigest("vm-1", prior.local_mesh_state.vector_clock, 0, 1000)
  let assert Ok(#(_, replies)) = handle_incoming_message(updated, digest, 2100)
  let assert [SyncDelta(_, _, health, _)] = replies
  health |> should.equal(updated.local_health_map)
}

pub fn full_queue_rejects_both_digest_response_branches_test() {
  let full = full_queue()
  handle_incoming_message(full, SyncDigest("vm-1", [], 0, 2000), 2000)
  |> should.equal(Error(OutboundQueueFull(256)))
  handle_incoming_message(
    full,
    SyncDigest("vm-1", full.local_mesh_state.vector_clock, 0, 2000),
    2000,
  )
  |> should.equal(Error(OutboundQueueFull(256)))
}

pub fn gossip_timestamp_cannot_precede_latest_observation_test() {
  let engine = init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 2000)
  let assert Ok(#(_, SyncDigest(_, _, _, epoch))) =
    generate_gossip_digest(engine, 1000)
  epoch |> should.equal(2000)
}

pub fn repeated_health_sample_is_idempotent_test() {
  let engine =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> record_local_health("nas-1", 0.8, -1.0, True, "closed", 2000)
  record_local_health(engine, "nas-1", 0.8, -1.0, True, "closed", 2000)
  |> should.equal(engine)
}
