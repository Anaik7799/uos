import cepaf_gleam/crdt/delta_mesh_engine as engine
import cepaf_gleam/crdt/delta_state
import cepaf_gleam/crdt/mesh_peer as peer
import cepaf_gleam/crdt/mesh_peer_actor as runtime
import cepaf_gleam/crdt/mesh_sync as sync
import cepaf_gleam/crdt/mesh_wire
import cepaf_gleam/ha/deadman_freshness.{HeartbeatTripped}
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

fn configuration(node, others) {
  let assert Ok(c) = peer.config(node, "http://nas-1.tail55d152.ts.net", others, 1000, 2000, 2)
  c
}

fn b() { peer.Peer("b", "http://vm-1.tail55d152.ts.net") }
fn encoded(message) {
  let assert Ok(bytes) = sync.encode_sync_message(message)
  bytes
}

fn fill(state, n) {
  list.fold(list.repeat(Nil, n), state, fn(s, _) {
    let assert Ok(next) = peer.gossip(s, 1000)
    next
  })
}

fn fanout_boundary() {
  let c = configuration("a", [b(), peer.Peer("c", "http://nas-1.tail55d152.ts.net")])
  let assert Ok(initial) = peer.init(c, 0, 1000, 41)
  let state = fill(initial, 127)
  let assert Ok(almost) = peer.receive_wire(state, "b", encoded(sync.SyncDigest("b", [], 0, 1)), 1, 1001)
  list.length(peer.outbound(almost)) |> should.equal(255)
  peer.gossip(almost, 1002) |> should.equal(Error(peer.FrameQuota))
  let assert Ok(first) = list.first(peer.outbound(almost))
  let assert Ok(retired) = peer.report_delivery(almost, first.id, first.destination, peer.TransportAccepted)
  let assert Ok(exact) = peer.gossip(retired, 1002)
  list.length(peer.outbound(exact)) |> should.equal(256)
  let assert Ok(last) = list.last(peer.outbound(exact))
  last.id |> should.equal(peer.FrameId(41, 257))
  peer.report_delivery(exact, peer.FrameId(40, 257), last.destination, peer.TransportAccepted)
  |> should.equal(Error(peer.NotOutstanding))
}

fn populated(node) {
  list.index_fold(list.repeat(Nil, 75), engine.init_engine(node, "http://nas-1.tail55d152.ts.net", 1000), fn(s, _, i) {
    engine.record_worker_active(s, node <> string.repeat("x", 950) <> int.to_string(i), 1000)
  })
}

fn aggregate_merge_refusal() {
  let c = configuration("a", [b()])
  let assert Ok(initial) = peer.init(c, 0, 1000, 1)
  let remote_a = populated("a")
  let remote_b = populated("b")
  let left_bytes = encoded(sync.SyncDelta("b", remote_a.local_mesh_state, [], 1))
  let right_bytes = encoded(sync.SyncDelta("b", remote_b.local_mesh_state, [], 2))
  let assert Ok(left) = peer.receive_wire(initial, "b", left_bytes, 1, 1001)
  peer.receive_wire(left, "b", right_bytes, 2, 1002)
  |> should.equal(Error(peer.WireFailure(mesh_wire.ByteLimit)))
  list.length(peer.engine_snapshot(left).local_mesh_state.active_workers.elements)
  |> should.equal(75)
  list.length(peer.outbound(left)) |> should.equal(1)
}

fn counters_cannot_escape_wire_bound() {
  let c = configuration("a", [b()])
  let assert Ok(initial) = peer.init(c, 0, 1000, 1)
  let remote = delta_state.new_mesh_delta_state("b", 1)
  let remote = delta_state.MeshDeltaState(..remote, vector_clock: [#("a", mesh_wire.max_integer)])
  let assert Ok(full_counter) = peer.receive_wire(initial, "b", encoded(sync.SyncDelta("b", remote, [], 1)), 1, 1001)
  peer.record_worker(full_counter, "overflow", 1002)
  |> should.equal(Error(peer.WireFailure(mesh_wire.IntegerLimit)))
  peer.engine_snapshot(full_counter).local_mesh_state.active_workers.elements
  |> should.equal([])
}

fn stale_activity_with_new_transport_call() {
  let c = configuration("a", [b()])
  let assert Ok(initial) = peer.init(c, 0, 1000, 1)
  let newer = encoded(sync.SyncAck("b", [], "ok", 50))
  let older = encoded(sync.SyncAck("b", [], "ok", 49))
  let assert Ok(observed) = peer.receive_wire(initial, "b", newer, 10, 1010)
  let assert Ok(peer.Tick(tripped, _)) = peer.tick(observed, 4010, -1)
  let assert Ok(replayed) = peer.receive_wire(tripped, "b", older, 4011, 2000)
  let assert [status] = peer.freshness(replayed).actors
  status.status |> should.equal(HeartbeatTripped(4010))
  let assert Ok(repeated) = peer.receive_wire(replayed, "b", newer, 4012, 2001)
  peer.freshness(repeated) |> should.equal(peer.freshness(replayed))
  let assert Ok(recovered) = peer.receive_wire(repeated, "b", encoded(sync.SyncAck("b", [], "ok", 51)), 4013, 2002)
  let assert [fresh] = peer.freshness(recovered).actors
  fresh.last_heartbeat_ms |> should.equal(4013)
}

fn transport(from, sender, target, duplicate) {
  let assert Ok(frames) = runtime.pull(from, 256)
  list.each(frames, fn(frame) {
    runtime.receive_wire(target, sender, frame.wire) |> should.equal(Ok(Nil))
    case duplicate {
      True -> runtime.receive_wire(target, sender, frame.wire) |> should.equal(Ok(Nil))
      False -> Nil
    }
    runtime.report_delivery(from, frame.id, frame.destination, peer.TransportAccepted)
    |> should.equal(Ok(Nil))
  })
}

fn actual_two_way_retry() {
  let assert Ok(a) = runtime.start(configuration("a", [b()]))
  let assert Ok(b) = runtime.start(configuration("b", [peer.Peer("a", "http://nas-1.tail55d152.ts.net")]))
  runtime.record_worker(a.data, "worker-a") |> should.equal(Ok(Nil))
  runtime.record_worker(b.data, "worker-b") |> should.equal(Ok(Nil))
  runtime.gossip(a.data) |> should.equal(Ok(Nil))
  runtime.gossip(b.data) |> should.equal(Ok(Nil))
  let assert Ok([before]) = runtime.pull(a.data, 1)
  runtime.report_delivery(a.data, before.id, before.destination, peer.TransportFailed)
  |> should.equal(Ok(Nil))
  runtime.pull(a.data, 1) |> should.equal(Ok([before]))
  list.each(list.repeat(Nil, 5), fn(_) {
    transport(a.data, "a", b.data, True)
    transport(b.data, "b", a.data, False)
  })
  let assert Ok(av) = runtime.snapshot(a.data)
  let assert Ok(bv) = runtime.snapshot(b.data)
  let left = peer.engine_snapshot(av.peer).local_mesh_state
  let right = peer.engine_snapshot(bv.peer).local_mesh_state
  delta_state.dominates(left.vector_clock, right.vector_clock) |> should.be_true
  delta_state.dominates(right.vector_clock, left.vector_clock) |> should.be_true
  let names = fn(s: delta_state.MeshDeltaState) { s.active_workers.elements |> list.map(fn(p) { p.0 }) |> list.unique |> list.sort(string.compare) }
  names(left) |> should.equal(["worker-a", "worker-b"])
  names(right) |> should.equal(["worker-a", "worker-b"])
  runtime.shutdown(a.data) |> result.is_ok |> should.be_true
  runtime.shutdown(b.data) |> result.is_ok |> should.be_true
}

pub fn main() {
  fanout_boundary()
  io.println("PASS independent_fanout_boundary")
  aggregate_merge_refusal()
  io.println("PASS independent_aggregate_merge_refusal")
  counters_cannot_escape_wire_bound()
  io.println("PASS independent_counter_limit")
  stale_activity_with_new_transport_call()
  io.println("PASS independent_stale_activity")
  actual_two_way_retry()
  io.println("PASS independent_actual_two_way_retry")
}
