import cepaf_gleam/crdt/delta_state
import cepaf_gleam/crdt/mesh_peer.{
  ByteQuota, FrameId, FrameQuota, InvalidClock, NotOutstanding, Peer,
  SenderMismatch, Tick, TransportAccepted, TransportFailed, UnknownPeer,
}
import cepaf_gleam/crdt/mesh_sync.{SyncAck, SyncDelta, SyncDigest}
import cepaf_gleam/ha/deadman_freshness.{HeartbeatTripped}
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

pub fn valid_configuration_test() {
  mesh_peer.config(
    "a",
    "http://nas-1.tail55d152.ts.net",
    [Peer("b", "http://vm-1.tail55d152.ts.net")],
    10,
    50,
    3,
  )
  |> result.is_ok
  |> should.be_true
}

fn configured(peers) {
  let assert Ok(config) =
    mesh_peer.config("a", "http://nas-1.tail55d152.ts.net", peers, 10, 50, 2)
  let assert Ok(state) = mesh_peer.init(config, 0, 1000, 1)
  state
}

fn initial() {
  configured([Peer("b", "http://vm-1.tail55d152.ts.net")])
}

fn encode(message) {
  let assert Ok(bytes) = mesh_sync.encode_sync_message(message)
  bytes
}

fn gossip_n(state, n) {
  case n {
    0 -> state
    _ -> {
      let assert Ok(next) = mesh_peer.gossip(state, 1000 + n)
      gossip_n(next, n - 1)
    }
  }
}

pub fn configuration_bounds_test() {
  mesh_peer.config("a", "fqdn", [Peer("a", "other")], 1, 50, 2)
  |> result.is_error
  |> should.be_true
  mesh_peer.config("a", "fqdn", list.repeat(Peer("b", "other"), 2), 1, 50, 2)
  |> result.is_error
  |> should.be_true
  mesh_peer.config("a", "fqdn", [], 0, 50, 2)
  |> result.is_error
  |> should.be_true
  let peers =
    list.index_map(list.repeat(Nil, 17), fn(_, i) {
      Peer(int.to_string(i), "fqdn")
    })
  mesh_peer.config("a", "fqdn", peers, 1, 50, 2)
  |> result.is_error
  |> should.be_true
}

pub fn routes_and_delivery_test() {
  let state = configured([Peer("b", "b.fqdn"), Peer("c", "c.fqdn")])
  let assert Ok(queued) = mesh_peer.gossip(state, 1001)
  let assert [first, second] = mesh_peer.outbound(queued)
  first.destination |> should.equal("b")
  second.destination |> should.equal("c")
  mesh_peer.report_delivery(queued, first.id, "c", TransportAccepted)
  |> should.equal(Error(NotOutstanding))
  mesh_peer.report_delivery(queued, first.id, "b", TransportFailed)
  |> should.equal(Ok(queued))
  let assert Ok(retired) =
    mesh_peer.report_delivery(queued, first.id, "b", TransportAccepted)
  mesh_peer.outbound(retired) |> should.equal([second])
  mesh_peer.report_delivery(retired, first.id, "b", TransportAccepted)
  |> should.equal(Error(NotOutstanding))
  mesh_peer.report_delivery(retired, FrameId(99, 1), "c", TransportAccepted)
  |> should.equal(Error(NotOutstanding))
}

pub fn incoming_routing_test() {
  let state = initial()
  let bytes = encode(SyncDigest("b", [], 0, 1))
  mesh_peer.receive_wire(state, "x", bytes, 1, 1001)
  |> should.equal(Error(UnknownPeer))
  mesh_peer.receive_wire(state, "b", encode(SyncAck("c", [], "ok", 1)), 1, 1001)
  |> should.equal(Error(SenderMismatch))
  mesh_peer.receive_wire(state, "b", "[]", 1, 1001)
  |> result.is_error
  |> should.be_true
  let assert Ok(next) = mesh_peer.receive_wire(state, "b", bytes, 1, 1001)
  list.map(mesh_peer.outbound(next), fn(f) { f.destination })
  |> should.equal(["b"])
}

pub fn replay_does_not_rearm_test() {
  let state = initial()
  let bytes = encode(SyncAck("b", [], "ok", 1))
  let assert Ok(observed) = mesh_peer.receive_wire(state, "b", bytes, 1, 1001)
  let assert Ok(Tick(tripped, _)) = mesh_peer.tick(observed, 101, 1101)
  let assert [entry] = mesh_peer.freshness(tripped).actors
  entry.status |> should.equal(HeartbeatTripped(101))
  let assert Ok(replayed) =
    mesh_peer.receive_wire(tripped, "b", bytes, 102, 1102)
  mesh_peer.freshness(replayed) |> should.equal(mesh_peer.freshness(tripped))
  let assert Ok(recovered) =
    mesh_peer.receive_wire(
      replayed,
      "b",
      encode(SyncAck("b", [], "ok", 2)),
      103,
      1103,
    )
  let assert [fresh] = mesh_peer.freshness(recovered).actors
  fresh.last_heartbeat_ms |> should.equal(103)
}

pub fn full_queue_tick_and_atomic_refusal_test() {
  let full = gossip_n(initial(), 256)
  mesh_peer.gossip(full, 5000) |> should.equal(Error(FrameQuota))
  let assert Ok(Tick(ticked, Error(FrameQuota))) =
    mesh_peer.tick(full, 101, 5000)
  mesh_peer.outbound(ticked) |> should.equal(mesh_peer.outbound(full))
  let #(cleared, actions, _) = mesh_peer.take_advisories(ticked)
  list.length(actions) |> should.equal(1)
  let assert Ok(Tick(again, _)) = mesh_peer.tick(cleared, 102, 5001)
  let #(_, repeated, _) = mesh_peer.take_advisories(again)
  repeated |> should.equal([])
  let delta = SyncDelta("b", delta_state.new_mesh_delta_state("b", 1), [], 1)
  mesh_peer.receive_wire(full, "b", encode(delta), 1, 1001)
  |> should.equal(Error(FrameQuota))
}

pub fn byte_quota_and_encode_refusal_test() {
  let peers =
    list.index_map(list.repeat(Nil, 16), fn(_, i) {
      Peer("b" <> int.to_string(i), "fqdn")
    })
  let state = configured(peers)
  let clock =
    list.index_map(list.repeat(Nil, 128), fn(_, i) {
      #(string.repeat("k", 500) <> int.to_string(i), 1)
    })
  let remote =
    delta_state.MeshDeltaState(
      ..delta_state.new_mesh_delta_state("b0", 1),
      vector_clock: clock,
    )
  let assert Ok(merged) =
    mesh_peer.receive_wire(
      state,
      "b0",
      encode(SyncDelta("b0", remote, [], 1)),
      1,
      1001,
    )
  mesh_peer.gossip(merged, 1002) |> should.equal(Error(ByteQuota))
  mesh_peer.record_worker(state, string.repeat("x", 1025), 1002)
  |> result.is_error
  |> should.be_true
  mesh_peer.outbound(state) |> should.equal([])
}

pub fn clock_and_worker_roundtrip_test() {
  let state = initial()
  let assert Ok(worker) = mesh_peer.record_worker(state, "worker", 1001)
  let assert Ok(gossiped) = mesh_peer.gossip(worker, 1000)
  mesh_peer.engine_snapshot(gossiped).local_mesh_state.epoch_us
  |> should.equal(1001)
  mesh_peer.tick(gossiped, -1, 1000) |> should.equal(Error(InvalidClock))
  let assert Ok(Tick(advanced, _)) = mesh_peer.tick(gossiped, 10, 1002)
  mesh_peer.receive_wire(
    advanced,
    "b",
    encode(SyncAck("b", [], "ok", 1)),
    9,
    1003,
  )
  |> should.equal(Error(InvalidClock))
}

pub fn utc_refusal_cannot_suppress_freshness_test() {
  let assert Ok(Tick(ticked, Error(InvalidClock))) =
    mesh_peer.tick(initial(), 100, -1)
  let assert [entry] = mesh_peer.freshness(ticked).actors
  entry.status |> should.equal(HeartbeatTripped(100))
  mesh_peer.outbound(ticked) |> should.equal([])
}

pub fn advisory_overflow_is_explicit_test() {
  let peers =
    list.index_map(list.repeat(Nil, 16), fn(_, i) {
      Peer("b" <> int.to_string(i), "fqdn")
    })
  let assert Ok(c) = mesh_peer.config("a", "fqdn", peers, 1, 1, 100)
  let assert Ok(initial) = mesh_peer.init(c, 0, 0, 1)
  let state =
    list.fold([1, 2, 3, 4, 5], initial, fn(s, time) {
      let assert Ok(Tick(next, _)) = mesh_peer.tick(s, time, time)
      next
    })
  let #(drained, actions, overflow) = mesh_peer.take_advisories(state)
  list.length(actions) |> should.equal(64)
  overflow |> should.equal(16)
  mesh_peer.advisory_overflow(drained) |> should.equal(0)
  list.length(mesh_peer.freshness(drained).actors) |> should.equal(16)
}

pub fn main() {
  valid_configuration_test()
  io.println("PASS valid_configuration")
  configuration_bounds_test()
  io.println("PASS configuration_bounds")
  routes_and_delivery_test()
  io.println("PASS routes_and_delivery")
  incoming_routing_test()
  io.println("PASS incoming_routing")
  replay_does_not_rearm_test()
  io.println("PASS replay_does_not_rearm")
  full_queue_tick_and_atomic_refusal_test()
  io.println("PASS full_queue_tick_and_atomic_refusal")
  byte_quota_and_encode_refusal_test()
  io.println("PASS byte_quota_and_encode_refusal")
  clock_and_worker_roundtrip_test()
  io.println("PASS clock_and_worker_roundtrip")
  advisory_overflow_is_explicit_test()
  io.println("PASS advisory_overflow_is_explicit")
  utc_refusal_cannot_suppress_freshness_test()
  io.println("PASS utc_refusal_cannot_suppress_freshness")
}
