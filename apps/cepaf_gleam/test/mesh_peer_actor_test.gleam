import cepaf_gleam/crdt/mesh_peer.{FrameQuota, Peer, TransportAccepted}
import cepaf_gleam/crdt/mesh_peer_actor as peer_actor
import cepaf_gleam/crdt/mesh_sync
import cepaf_gleam/ha/deadman_freshness.{HeartbeatNominal, HeartbeatTripped}
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleeunit/should

fn config(node, other, tick, heartbeat) {
  let assert Ok(c) =
    mesh_peer.config(
      node,
      "http://nas-1.tail55d152.ts.net",
      [Peer(other, "http://vm-1.tail55d152.ts.net")],
      tick,
      heartbeat,
      2,
    )
  c
}

fn transfer(from, sender, target) {
  let assert Ok(frames) = peer_actor.pull(from, 256)
  list.each(frames, fn(frame) {
    peer_actor.receive_wire(target, sender, frame.wire) |> should.equal(Ok(Nil))
    peer_actor.report_delivery(
      from,
      frame.id,
      frame.destination,
      TransportAccepted,
    )
    |> should.equal(Ok(Nil))
  })
}

pub fn two_actor_exchange_test() {
  let assert Ok(a) = peer_actor.start(config("a", "b", 1000, 2000))
  let assert Ok(b) = peer_actor.start(config("b", "a", 1000, 2000))
  peer_actor.pull(a.data, 0) |> should.equal(Error(mesh_peer.InvalidConfig))
  peer_actor.receive_wire(b.data, "unknown", "[]")
  |> should.equal(Error(mesh_peer.UnknownPeer))
  peer_actor.record_worker(a.data, "worker") |> should.equal(Ok(Nil))
  peer_actor.record_health(a.data, 0.91, -0.2, True, "closed")
  |> should.equal(Ok(Nil))
  peer_actor.gossip(a.data) |> should.equal(Ok(Nil))
  peer_actor.gossip(b.data) |> should.equal(Ok(Nil))
  transfer(a.data, "a", b.data)
  transfer(b.data, "b", a.data)
  transfer(a.data, "a", b.data)
  transfer(b.data, "b", a.data)
  let assert Ok(view) = peer_actor.snapshot(b.data)
  mesh_peer.engine_snapshot(view.peer).local_mesh_state.active_workers.elements
  |> list.any(fn(p) { p.0 == "worker" })
  |> should.be_true
  let assert Ok(health) =
    list.key_find(mesh_peer.engine_snapshot(view.peer).local_health_map, "a")
  health.value.health_score |> should.equal(0.91)
  health.value.lyapunov_exponent |> should.equal(-0.2)
  let assert Ok(_) = peer_actor.shutdown(a.data)
  let assert Ok(_) = peer_actor.shutdown(b.data)
  Nil
}

fn fill(handle, left) {
  case left {
    0 -> panic as "queue failed to fill"
    _ ->
      case peer_actor.gossip(handle) {
        Ok(Nil) -> fill(handle, left - 1)
        Error(FrameQuota) -> Nil
        Error(_) -> panic as "unexpected queue refusal"
      }
  }
}

pub fn timer_full_queue_and_replay_test() {
  let assert Ok(started) = peer_actor.start(config("a", "b", 10, 20))
  let handle = started.data
  let assert Ok(bytes) =
    mesh_sync.encode_sync_message(mesh_sync.SyncAck("b", [], "ok", 1))
  peer_actor.receive_wire(handle, "b", bytes) |> should.equal(Ok(Nil))
  fill(handle, 300)
  process.sleep(100)
  let assert Ok(view) = peer_actor.snapshot(handle)
  list.length(mesh_peer.outbound(view.peer)) |> should.equal(256)
  view.last_tick_gossip |> should.equal(Error(FrameQuota))
  let assert [entry] = mesh_peer.freshness(view.peer).actors
  case entry.status {
    HeartbeatTripped(_) -> Nil
    _ -> panic as "timer did not trip full queue"
  }
  peer_actor.receive_wire(handle, "b", bytes) |> should.equal(Error(FrameQuota))
  let assert Ok(covering_ack) =
    mesh_sync.encode_sync_message(mesh_sync.SyncAck(
      "b",
      mesh_peer.engine_snapshot(view.peer).local_mesh_state.vector_clock,
      "clock_in_sync",
      1,
    ))
  peer_actor.receive_wire(handle, "b", covering_ack) |> should.equal(Ok(Nil))
  let assert Ok(replayed) = peer_actor.snapshot(handle)
  let assert [after] = mesh_peer.freshness(replayed.peer).actors
  after.status |> should.equal(entry.status)
  let assert Ok(shutdown) = peer_actor.shutdown(handle)
  list.length(mesh_peer.outbound(shutdown.peer)) |> should.equal(256)
  process.sleep(5)
  peer_actor.snapshot(handle) |> should.equal(Error(mesh_peer.ActorUnavailable))
}

pub fn supervised_child_shutdown_test() {
  let replies = process.new_subject()
  let specification = peer_actor.supervised(config("a", "b", 1000, 2000))
  let child =
    supervision.ChildSpecification(..specification, start: fn() {
      case specification.start() {
        Ok(started) -> {
          process.send(replies, started)
          Ok(started)
        }
        Error(e) -> Error(e)
      }
    })
  let assert Ok(supervised) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child)
    |> static_supervisor.start
  let assert Ok(first) = process.receive(replies, 1000)
  let handle = first.data
  let assert Ok(view) = peer_actor.snapshot(handle)
  let assert [entry] = mesh_peer.freshness(view.peer).actors
  entry.status |> should.equal(HeartbeatNominal)
  peer_actor.gossip(handle) |> should.equal(Ok(Nil))
  let assert Ok([old_frame]) = peer_actor.pull(handle, 256)
  process.kill(first.pid)
  let assert Ok(restarted) = process.receive(replies, 1000)
  peer_actor.gossip(restarted.data) |> should.equal(Ok(Nil))
  let assert Ok([new_frame]) = peer_actor.pull(restarted.data, 256)
  { new_frame.id.instance != old_frame.id.instance } |> should.be_true
  peer_actor.report_delivery(
    restarted.data,
    old_frame.id,
    old_frame.destination,
    TransportAccepted,
  )
  |> should.equal(Error(mesh_peer.NotOutstanding))
  let assert Ok(_) = peer_actor.shutdown(restarted.data)
  process.receive(replies, 30) |> should.equal(Error(Nil))
  process.unlink(supervised.pid)
  process.kill(supervised.pid)
}

pub fn main() {
  two_actor_exchange_test()
  io.println("PASS two_actor_exchange")
  supervised_child_shutdown_test()
  io.println("PASS supervised_child_shutdown")
  timer_full_queue_and_replay_test()
  io.println("PASS timer_full_queue_and_replay")
}
