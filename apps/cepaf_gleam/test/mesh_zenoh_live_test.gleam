//// Explicit opt-in owned-namespace integration runner; never part of unit main.

import cepaf_gleam/crdt/mesh_peer as peer
import cepaf_gleam/crdt/mesh_peer_actor as peers
import cepaf_gleam/crdt/mesh_zenoh_http as http
import cepaf_gleam/crdt/mesh_zenoh_transport as transport
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleeunit/should

type Unit {
  Microsecond
}

type Unique {
  Positive
  Monotonic
}

@external(erlang, "erlang", "system_time")
fn utc(unit: Unit) -> Int

@external(erlang, "erlang", "unique_integer")
fn unique(options: List(Unique)) -> Int

fn start(node: String, other: String) {
  let assert Ok(config) =
    peer.config(
      node,
      "nas-1.tail55d152.ts.net",
      [peer.Peer(other, "nas-1.tail55d152.ts.net")],
      60_000,
      60_000,
      2,
    )
  let assert Ok(started) = peers.start(config)
  started.data
}

fn applied(b: peers.Handle, attempts: Int) {
  let assert Ok(view) = peers.snapshot(b)
  let state = peer.engine_snapshot(view.peer)
  let present =
    list.any(state.local_mesh_state.active_workers.elements, fn(x) {
      x.0 == "worker-owned-live"
    })
  case present, list.key_find(state.local_health_map, "a") {
    True, Ok(health) if health.value.health_score == 0.91 -> True
    _, _ ->
      case attempts > 0 {
        True -> {
          process.sleep(50)
          applied(b, attempts - 1)
        }
        False -> False
      }
  }
}

fn readbacks(
  endpoint: http.Endpoint,
  run: String,
  sender: String,
  destination: String,
  count: Int,
) {
  int.range(1, count + 1, Nil, fn(_, seq) {
    let key =
      "uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/"
      <> run
      <> "/"
      <> sender
      <> "/"
      <> destination
      <> "/"
      <> int.to_string(seq)
    let assert Ok(response) = http.request(endpoint, http.Get, key, "", 1000)
    io.println(
      json.object([
        #("kind", json.string("broker_readback")),
        #("key", json.string(key)),
        #("body", json.string(response.body)),
      ])
      |> json.to_string,
    )
  })
}

pub fn main() {
  let run =
    "r"
    <> int.to_string(utc(Microsecond))
    <> "-"
    <> int.to_string(unique([Positive, Monotonic]))
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", 8080)
  io.println(
    json.object([
      #("kind", json.string("owned_run")),
      #("run", json.string(run)),
      #("authority", json.string("NONE")),
    ])
    |> json.to_string,
  )
  let a = start("a", "b")
  let b = start("b", "a")
  peers.record_worker(a, "worker-owned-live") |> should.be_ok
  peers.record_health(a, 0.91, -0.2, True, "closed") |> should.be_ok
  peers.gossip(a) |> should.be_ok
  peers.gossip(b) |> should.be_ok
  let assert Ok(before) = peers.pull(a, 1)
  list.each(before, fn(frame) {
    io.println(
      json.object([
        #("kind", json.string("producer_wire")),
        #("wire", json.string(frame.wire)),
      ])
      |> json.to_string,
    )
  })
  let assert Ok(ca) = transport.config(endpoint, run, "a", ["b"])
  let assert Ok(cb) = transport.config(endpoint, run, "b", ["a"])
  let assert Ok(wa) = transport.start(ca, a)
  let assert Ok(wb) = transport.start(cb, b)
  let succeeded = applied(b, 100)
  process.sleep(200)
  let assert Ok(sa) = transport.shutdown(wa.data)
  let assert Ok(sb) = transport.shutdown(wb.data)
  io.println(
    json.object([
      #("kind", json.string("transport_stats")),
      #("a_published", json.int(sa.published)),
      #("b_published", json.int(sb.published)),
      #("a_applied", json.int(sa.applied)),
      #("b_applied", json.int(sb.applied)),
      #("a_failures", json.int(sa.failures)),
      #("b_failures", json.int(sb.failures)),
      #("a_error", json.string(error_name(sa.last_error))),
      #("b_error", json.string(error_name(sb.last_error))),
    ])
    |> json.to_string,
  )
  case succeeded {
    True -> Nil
    False -> {
      let key =
        "uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/"
        <> run
        <> "/a/b/1"
      case http.request(endpoint, http.Get, key, "", 2000) {
        Ok(response) -> io.println(response.body)
        Error(_) -> io.println("diagnostic read refused")
      }
    }
  }
  succeeded |> should.be_true
  { sa.published > 0 && sb.applied > 0 } |> should.be_true
  readbacks(
    endpoint,
    run,
    "a",
    "b",
    sa.published
      + case sa.custody_pending {
      True -> 1
      False -> 0
    },
  )
  readbacks(
    endpoint,
    run,
    "b",
    "a",
    sb.published
      + case sb.custody_pending {
      True -> 1
      False -> 0
    },
  )
  let assert option.Some(produced) = sa.last_stored_wire
  let assert option.Some(consumed) = sb.last_applied_wire
  produced |> should.equal(consumed)
  io.println(
    json.object([
      #("kind", json.string("producer_consumer_equal_bytes")),
      #("producer_wire", json.string(produced)),
      #("consumer_wire", json.string(consumed)),
    ])
    |> json.to_string,
  )
  let assert Ok(view) = peers.snapshot(b)
  let state = peer.engine_snapshot(view.peer)
  let assert Ok(health) = list.key_find(state.local_health_map, "a")
  io.println(
    json.object([
      #("kind", json.string("peer_applied")),
      #("worker", json.string("worker-owned-live")),
      #("health", json.float(health.value.health_score)),
      #("a_broker_custody_reports", json.int(sa.published)),
      #("b_applied_frames", json.int(sb.applied)),
      #("run", json.string(run)),
    ])
    |> json.to_string,
  )
  let assert Ok(_) = peers.shutdown(a)
  let assert Ok(_) = peers.shutdown(b)
  io.println("PASS owned_zenoh_two_actor_roundtrip")
}

fn error_name(error: option.Option(transport.Error)) -> String {
  case error {
    option.None -> "none"
    option.Some(transport.Http(http.Status(n))) ->
      "http_status_" <> int.to_string(n)
    option.Some(transport.Http(http.Protocol)) -> "http_protocol"
    option.Some(transport.Http(http.Timeout)) -> "http_timeout"
    option.Some(transport.Http(_)) -> "http_other"
    option.Some(transport.InvalidSample) -> "invalid_sample"
    option.Some(transport.NamespaceConflict) -> "namespace_conflict"
    option.Some(transport.Peer(_)) -> "peer_refusal"
    option.Some(_) -> "other"
  }
}
