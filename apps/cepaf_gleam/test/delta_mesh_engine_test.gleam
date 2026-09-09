//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Multi-Host CRDT Delta Mesh Engine Verification
//// =============================================================================

import cepaf_gleam/crdt/delta_mesh_engine.{
  OutboundQueueFull, compute_cluster_aggregate_health, drain_pending_outbound,
  generate_gossip_digest, handle_incoming_message, init_engine,
  is_cluster_fully_synchronized, record_local_health, record_worker_active,
  register_peer,
}
import cepaf_gleam/crdt/mesh_sync.{Reconciling, SyncAck, SyncDelta, SyncDigest}
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
  full_two_way_exchange_converges_only_after_remote_delta_test()
}

pub fn digest_only_exchange_does_not_claim_remote_state_test() {
  let nas =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> register_peer("vm-1", "vm-1.tail55d152.ts.net:8088")
    |> record_worker_active("nas-worker", 1000)
  let vm =
    init_engine("vm-1", "vm-1.tail55d152.ts.net:8088", 1000)
    |> register_peer("nas-1", "nas-1.tail55d152.ts.net:4100")
    |> record_worker_active("vm-worker", 1000)
  let assert Ok(#(_, digest)) = generate_gossip_digest(vm, 1000)
  let assert Ok(#(nas_after_digest, [_])) =
    handle_incoming_message(nas, digest, 1100)

  peer_status(nas_after_digest, "vm-1") |> should.equal(Reconciling)
  is_cluster_fully_synchronized(nas_after_digest) |> should.be_false()
}

pub fn local_mutation_invalidates_prior_peer_coverage_test() {
  let engine =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> register_peer("vm-1", "vm-1.tail55d152.ts.net:8088")
  let ack = SyncAck("vm-1", engine.local_mesh_state.vector_clock, "clock_in_sync", 1100)
  let assert Ok(#(covered, [])) = handle_incoming_message(engine, ack, 1100)
  is_cluster_fully_synchronized(covered) |> should.be_true()

  let mutated = record_worker_active(covered, "nas-worker", 1200)
  peer_status(mutated, "vm-1") |> should.equal(Reconciling)
  is_cluster_fully_synchronized(mutated) |> should.be_false()
}

pub fn stale_ack_cannot_restore_peer_coverage_after_local_change_test() {
  let engine =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> register_peer("vm-1", "vm-1.tail55d152.ts.net:8088")
  let old_ack = SyncAck("vm-1", engine.local_mesh_state.vector_clock, "clock_in_sync", 1100)
  let assert Ok(#(covered, [])) = handle_incoming_message(engine, old_ack, 1100)
  let mutated = record_worker_active(covered, "nas-worker", 1200)
  let assert Ok(#(observed, _)) = handle_incoming_message(mutated, old_ack, 1300)

  peer_status(observed, "vm-1") |> should.equal(Reconciling)
  is_cluster_fully_synchronized(observed) |> should.be_false()
}

pub fn remote_ahead_ack_requests_the_missing_delta_test() {
  let nas =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> register_peer("vm-1", "vm-1.tail55d152.ts.net:8088")
  let ack =
    SyncAck(
      "vm-1",
      [#("nas-1", 1), #("vm-1", 1)],
      "reconciled_ok",
      1200,
    )
  let assert Ok(#(nas_after_ack, [SyncDigest("nas-1", _, _, _)])) =
    handle_incoming_message(nas, ack, 1200)

  peer_status(nas_after_ack, "vm-1") |> should.equal(Reconciling)
}

pub fn full_two_way_exchange_converges_only_after_remote_delta_test() {
  let nas =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> register_peer("vm-1", "vm-1.tail55d152.ts.net:8088")
    |> record_worker_active("nas-worker", 1000)
  let vm =
    init_engine("vm-1", "vm-1.tail55d152.ts.net:8088", 1000)
    |> register_peer("nas-1", "nas-1.tail55d152.ts.net:8088")
    |> record_worker_active("vm-worker", 1000)
  let assert Ok(#(_, vm_digest)) = generate_gossip_digest(vm, 1000)
  let assert Ok(#(nas_after_digest, [nas_delta])) =
    handle_incoming_message(nas, vm_digest, 1100)
  peer_status(nas_after_digest, "vm-1") |> should.equal(Reconciling)
  let assert Ok(#(vm_after_delta, [vm_ack])) =
    handle_incoming_message(vm, nas_delta, 1200)
  peer_status(vm_after_delta, "nas-1") |> should.equal(Reconciling)
  let assert Ok(#(nas_after_ack, [nas_digest])) =
    handle_incoming_message(nas_after_digest, vm_ack, 1300)
  let assert Ok(#(vm_after_digest, [vm_delta])) =
    handle_incoming_message(vm_after_delta, nas_digest, 1400)
  let assert Ok(#(nas_converged, [nas_ack])) =
    handle_incoming_message(nas_after_ack, vm_delta, 1500)
  is_cluster_fully_synchronized(nas_converged) |> should.be_true()
  let assert Ok(#(vm_converged, [])) =
    handle_incoming_message(vm_after_digest, nas_ack, 1600)
  is_cluster_fully_synchronized(vm_converged) |> should.be_true()
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

fn peer_status(engine: delta_mesh_engine.DeltaMeshEngine, node: String) {
  let assert [peer] = list.filter(engine.peers, fn(peer) { peer.node_id == node })
  peer.status
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

pub fn stale_ack_recovery_refuses_when_outbound_queue_is_full_test() {
  let full =
    full_queue() |> register_peer("vm-1", "vm-1.tail55d152.ts.net:8088")
  let stale_ack =
    SyncAck("vm-1", full.local_mesh_state.vector_clock, "clock_in_sync", 2000)
  let updated = record_worker_active(full, "nas-worker", 2100)

  handle_incoming_message(updated, stale_ack, 2200)
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

fn health_delta(engine: delta_mesh_engine.DeltaMeshEngine) {
  SyncDelta(
    engine.local_node_id,
    engine.local_mesh_state,
    engine.local_health_map,
    engine.local_mesh_state.epoch_us,
  )
}

fn accept_delta(engine, remote) {
  let assert Ok(#(updated, _)) =
    handle_incoming_message(engine, health_delta(remote), 3000)
  updated
}

pub fn reversed_same_tick_health_deltas_preserve_latest_sample_test() {
  let initial = init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
  let healthy =
    record_local_health(initial, "nas-1", 0.9, -1.0, True, "closed", 2000)
  let unhealthy =
    record_local_health(healthy, "nas-1", 0.1, 1.0, False, "open", 2000)
  let receiver = init_engine("vm-1", "vm-1.tail55d152.ts.net:8088", 1000)
  let forward = receiver |> accept_delta(healthy) |> accept_delta(unhealthy)
  let reverse = receiver |> accept_delta(unhealthy) |> accept_delta(healthy)
  reverse.local_health_map |> should.equal(unhealthy.local_health_map)
  reverse.local_health_map |> should.equal(forward.local_health_map)
  let assert Ok(#(_, [SyncAck(_, _, _, _)])) =
    handle_incoming_message(
      unhealthy,
      SyncDigest("vm-1", reverse.local_mesh_state.vector_clock, 0, 3000),
      3000,
    )
  let assert [#(_, entry)] = reverse.local_health_map
  entry.value.health_score |> should.equal(0.1)
  entry.value.sample_epoch_us |> should.equal(2000)
}

pub fn concurrent_same_target_health_converges_in_both_orders_test() {
  let a =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> record_local_health("target", 0.9, -1.0, True, "closed", 2000)
  let b =
    init_engine("vm-1", "vm-1.tail55d152.ts.net:8088", 1000)
    |> record_local_health("target", 0.1, 1.0, False, "open", 2000)
  let ab = accept_delta(a, b)
  let ba = accept_delta(b, a)
  ab.local_health_map |> should.equal(ba.local_health_map)
  accept_delta(ab, a).local_health_map |> should.equal(ab.local_health_map)
  accept_delta(ba, b).local_health_map |> should.equal(ba.local_health_map)
}

pub fn local_health_after_merge_supersedes_same_tick_remote_sample_test() {
  let a = init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
  let b =
    init_engine("vm-1", "vm-1.tail55d152.ts.net:8088", 1000)
    |> record_local_health("target", 0.9, -1.0, True, "closed", 2000)
  let merged = accept_delta(a, b)
  let updated =
    record_local_health(merged, "target", 0.1, 1.0, False, "open", 2000)
  let receiver = accept_delta(b, updated)
  receiver.local_health_map |> should.equal(updated.local_health_map)
  let assert [#(_, entry)] = receiver.local_health_map
  entry.value.health_score |> should.equal(0.1)
}

pub fn successive_gossip_retains_accepted_epoch_test() {
  let engine = init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
  let assert Ok(#(first, SyncDigest(_, _, _, first_epoch))) =
    generate_gossip_digest(engine, 3000)
  let assert Ok(#(second, SyncDigest(_, _, _, second_epoch))) =
    generate_gossip_digest(first, 2000)
  first_epoch |> should.equal(3000)
  second_epoch |> should.equal(first_epoch)
  second.local_mesh_state.epoch_us |> should.equal(3000)
}

pub fn incoming_ack_and_digest_observations_advance_outgoing_epoch_test() {
  let engine = init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
  let assert Ok(#(observed, [])) =
    handle_incoming_message(engine, SyncAck("vm-1", [], "ok", 3000), 3000)
  let assert Ok(#(replied, [SyncDelta(_, _, _, response_epoch)])) =
    handle_incoming_message(observed, SyncDigest("vm-1", [], 0, 2000), 2000)
  response_epoch |> should.equal(3000)
  let assert Ok(#(_, SyncDigest(_, _, _, gossip_epoch))) =
    generate_gossip_digest(replied, 1500)
  gossip_epoch |> should.equal(3000)
}

pub fn newer_sample_time_wins_over_an_older_logical_counter_test() {
  let a =
    init_engine("nas-1", "nas-1.tail55d152.ts.net:4100", 1000)
    |> record_local_health("target", 0.9, -1.0, True, "closed", 2000)
    |> record_local_health("target", 0.1, 1.0, False, "open", 2000)
    |> record_local_health("target", 0.2, 1.0, False, "open", 2000)
  let b =
    init_engine("vm-1", "vm-1.tail55d152.ts.net:8088", 1000)
    |> record_local_health("target", 0.95, -1.0, True, "closed", 2001)
  accept_delta(a, b).local_health_map |> should.equal(b.local_health_map)
  accept_delta(b, a).local_health_map |> should.equal(b.local_health_map)
}
