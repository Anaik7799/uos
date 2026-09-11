//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Multi-Host CRDT Delta Mesh Engine Verification
//// =============================================================================

import cepaf_gleam/crdt/delta_mesh_engine.{
  compute_cluster_aggregate_health, generate_gossip_digest,
  handle_incoming_message, init_engine, is_cluster_fully_synchronized,
  record_local_health, record_worker_active, register_peer,
}
import cepaf_gleam/crdt/mesh_sync.{
  SyncDigest,
}
import gleeunit
import gleeunit/should

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

  let #(updated_engine, digest) = generate_gossip_digest(engine, 1000)
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
  let #(_, vm_digest) = generate_gossip_digest(engine_vm, 1000)
  let #(nas_after_digest, nas_responses) =
    handle_incoming_message(engine_nas, vm_digest, 1100)

  // NAS should respond with SyncDelta containing its mutation
  should.be_true(list_len(nas_responses) >= 1)
  is_cluster_fully_synchronized(nas_after_digest) |> should.be_true()

  let delta_msg = case nas_responses {
    [d, ..] -> d
    _ -> panic as "expected delta response"
  }
  
  // VM handles NAS's delta
  let #(vm_after_delta, vm_responses) =
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

pub fn init_nas_vm_cluster_test() {
  let engine = delta_mesh_engine.init_nas_vm_cluster(2000)
  engine.local_node_id |> should.equal("nas-1")
  should.equal(1, list_len(engine.peers))
  case engine.peers {
    [peer] -> {
      peer.node_id |> should.equal("vm-1")
      peer.tailscale_fqdn |> should.equal("http://vm-1.tail55d152.ts.net:4100")
    }
    _ -> should.fail()
  }
}

fn list_len(l: List(a)) -> Int {
  case l {
    [] -> 0
    [_, ..rest] -> 1 + list_len(rest)
  }
}
