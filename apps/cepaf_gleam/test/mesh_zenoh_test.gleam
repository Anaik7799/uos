import cepaf_gleam/crdt/mesh_peer as peer
import cepaf_gleam/crdt/mesh_peer_actor as peers
import cepaf_gleam/crdt/mesh_sync
import cepaf_gleam/crdt/mesh_zenoh_http as http
import cepaf_gleam/crdt/mesh_zenoh_transport as transport
import cepaf_gleam/ha/deadman_freshness
import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import gleam/string
import gleeunit/should

type Socket

type Option {
  Binary
  Active(Bool)
  Packet(Int)
  Reuseaddr(Bool)
  Ip(#(Int, Int, Int, Int))
}

@external(erlang, "gen_tcp", "listen")
fn listen(port: Int, options: List(Option)) -> Result(Socket, Dynamic)

@external(erlang, "inet", "port")
fn port(sock: Socket) -> Result(Int, Dynamic)

@external(erlang, "gen_tcp", "accept")
fn accept(sock: Socket, timeout: Int) -> Result(Socket, Dynamic)

@external(erlang, "gen_tcp", "recv")
fn recv(sock: Socket, n: Int, timeout: Int) -> Result(BitArray, Dynamic)

@external(erlang, "gen_tcp", "send")
fn send(sock: Socket, data: String) -> Dynamic

@external(erlang, "gen_tcp", "close")
fn close(sock: Socket) -> Dynamic

type Mode {
  Store
  FailPut
  Slow
  Huge
  Duplicate
  Chunked
  Redirect
  DeepJson
  Ambiguous
  BadChunk
  ChunkHuge
  Cleanup(process.Subject(Bool))
  RetryReadback(process.Subject(String))
  DuplicateJson
  SignedLength
  ExactBody
  ChunkAggregate
}

fn read_header(sock: Socket, acc: String, left: Int) -> String {
  case left > 0 {
    False -> panic as "test request header quota"
    True -> {
      let assert Ok(b) = recv(sock, 1, 1000)
      let assert Ok(s) = bit_array.to_string(b)
      let text = acc <> s
      case string.ends_with(text, "\r\n\r\n") {
        True -> text
        False -> read_header(sock, text, left - 1)
      }
    }
  }
}

fn reply(body: String) -> String {
  "HTTP/1.1 200 OK\r\nContent-Length: "
  <> int.to_string(string.byte_size(body))
  <> "\r\n\r\n"
  <> body
}

fn serve(
  socket: Socket,
  mode: Mode,
  store: dict.Dict(String, String),
  left: Int,
) {
  case left > 0 {
    False -> Nil
    True -> {
      case accept(socket, 2000) {
        Error(_) -> Nil
        Ok(client) -> {
          let header = read_header(client, "", 8192)
          let lines = string.split(header, "\r\n")
          let assert Ok(first) = list.first(lines)
          let assert [method, path, ..] = string.split(first, " ")
          let length =
            lines
            |> list.find_map(fn(line) {
              case string.split_once(line, ": ") {
                Ok(#("Content-Length", n)) -> int.parse(n)
                _ -> Error(Nil)
              }
            })
            |> result.unwrap(0)
          let body = case length {
            0 -> ""
            _ -> {
              let assert Ok(b) = recv(client, length, 1000)
              let assert Ok(text) = bit_array.to_string(b)
              text
            }
          }
          let #(output, next) = case mode {
            Slow -> {
              process.sleep(150)
              #(reply("[]"), store)
            }
            Huge -> #(
              "HTTP/1.1 200 OK\r\nContent-Length: 800001\r\n\r\n",
              store,
            )
            Duplicate -> #(
              "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n[]",
              store,
            )
            Chunked -> #(
              "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\n[\r\n1\r\n]\r\n0\r\n\r\n",
              store,
            )
            Redirect -> #(
              "HTTP/1.1 302 Found\r\nLocation: http://example.com/\r\nContent-Length: 0\r\n\r\n",
              store,
            )
            DeepJson -> #(
              reply(string.repeat("[", 30) <> string.repeat("]", 30)),
              store,
            )
            Ambiguous -> #(
              "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nTransfer-Encoding: chunked\r\n\r\n[]",
              store,
            )
            SignedLength -> #(
              "HTTP/1.1 200 OK\r\nContent-Length: +2\r\n\r\n[]",
              store,
            )
            BadChunk -> #(
              "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n[]XX0\r\n\r\n",
              store,
            )
            ChunkHuge -> #(
              "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nc3501\r\n",
              store,
            )
            ExactBody -> #(reply(string.repeat("x", http.max_body)), store)
            ChunkAggregate -> #(
              "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n61a81\r\n"
                <> string.repeat("x", 400_001)
                <> "\r\n61a80\r\n",
              store,
            )
            Cleanup(observer) -> {
              let outcome = recv(client, 1, 1000)
              let closed = case outcome {
                Error(reason) ->
                  reason == atom.to_dynamic(atom.create("closed"))
                _ -> False
              }
              process.send(observer, closed)
              #("", store)
            }
            DuplicateJson -> #(
              reply(
                "[{\"key\":\"wrong\",\"key\":\"wrong2\",\"encoding\":\"application/json\",\"value\":[]}]",
              ),
              store,
            )
            FailPut if method == "PUT" -> #(
              "HTTP/1.1 503 unavailable\r\nContent-Length: 0\r\n\r\n",
              store,
            )
            _ ->
              case method {
                "PUT" -> {
                  case mode {
                    RetryReadback(observer) -> process.send(observer, "PUT")
                    _ -> Nil
                  }
                  #(reply(""), dict.insert(store, path, body))
                }
                _ -> {
                  let sample = case dict.get(store, path) {
                    Error(_) -> "[]"
                    Ok(value) ->
                      "[{\"key\":"
                      <> json.to_string(json.string(string.drop_start(path, 1)))
                      <> ",\"encoding\":\"application/json\",\"timestamp\":\"synthetic-clock-not-authority\",\"value\":"
                      <> value
                      <> "}]"
                  }
                  case mode, dict.get(store, "__held") {
                    RetryReadback(observer), Error(_) if sample != "[]" -> {
                      process.send(observer, "READBACK_LOST")
                      #(reply("[]"), dict.insert(store, "__held", "true"))
                    }
                    _, _ -> #(reply(sample), store)
                  }
                }
              }
          }
          let _ = send(client, output)
          let _ = close(client)
          serve(socket, mode, next, left - 1)
        }
      }
    }
  }
}

fn server(mode: Mode) -> #(process.Pid, Int) {
  let reply = process.new_subject()
  let pid =
    process.spawn(fn() {
      let assert Ok(sock) =
        listen(0, [
          Binary,
          Active(False),
          Packet(0),
          Reuseaddr(True),
          Ip(#(100, 87, 7, 78)),
        ])
      let assert Ok(port) = port(sock)
      process.send(reply, port)
      serve(sock, mode, dict.new(), 200)
      let _ = close(sock)
    })
  let assert Ok(port) = process.receive(reply, 1000)
  #(pid, port)
}

fn stop(pid: process.Pid) {
  process.unlink(pid)
  process.kill(pid)
}

const key = "uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/synthetic-test/a/b/1"

fn http_test(mode: Mode, timeout: Int) -> Result(http.Response, http.Error) {
  let #(pid, port) = server(mode)
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", port)
  let result = http.request(endpoint, http.Get, key, "", timeout)
  stop(pid)
  result
}

fn start_peer(node: String, other: String) -> peers.Handle {
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

fn worker_test(mode: Mode) {
  let #(server, port) = server(mode)
  let a = start_peer("a", "b")
  let b = start_peer("b", "a")
  let assert Ok(_) = peers.record_worker(a, "worker-a")
  let assert Ok(_) = peers.gossip(a)
  let assert Ok(_) = peers.gossip(b)
  let assert Ok(before) = peers.pull(a, 1)
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", port)
  let assert Ok(ca) = transport.config(endpoint, "synthetic-worker", "a", ["b"])
  let assert Ok(cb) = transport.config(endpoint, "synthetic-worker", "b", ["a"])
  let assert Ok(wa) = transport.start(ca, a)
  transport.start(ca, a) |> should.be_error
  let assert Ok(wb) = transport.start(cb, b)
  process.sleep(450)
  let assert Ok(sa) = transport.shutdown(wa.data)
  let assert Ok(sb) = transport.shutdown(wb.data)
  case mode {
    FailPut -> {
      sa.published |> should.equal(0)
      let assert Ok(after) = peers.pull(a, 1)
      after |> should.equal(before)
      { sa.failures > 0 } |> should.be_true
    }
    DeepJson | DuplicateJson -> {
      sa.published |> should.equal(0)
      { sa.failures > 0 } |> should.be_true
    }
    _ -> {
      { sa.published > 0 && sb.applied > 0 } |> should.be_true
      let assert Ok(view) = peers.snapshot(b)
      peer.engine_snapshot(view.peer).local_mesh_state.active_workers.elements
      |> list.any(fn(p) { p.0 == "worker-a" })
      |> should.be_true
    }
  }
  let assert Ok(_) = peers.shutdown(a)
  let assert Ok(_) = peers.shutdown(b)
  stop(server)
}

fn replay_test() {
  let #(server, port) = server(Store)
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", port)
  let assert Ok(config) =
    peer.config(
      "b",
      "nas-1.tail55d152.ts.net",
      [peer.Peer("a", "nas-1.tail55d152.ts.net")],
      20,
      40,
      2,
    )
  let assert Ok(b) = peers.start(config)
  let assert Ok(wire) =
    mesh_sync.encode_sync_message(mesh_sync.SyncAck("a", [], "ok", 1))
  let body =
    json.array(
      [
        json.string("uos.ev98.transport.v1"),
        json.string("a"),
        json.string("b"),
        json.int(10),
        json.int(1),
        json.string(wire),
      ],
      fn(x) { x },
    )
    |> json.to_string
  let first =
    "uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/replay/a/b/1"
  let second =
    "uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/replay/a/b/2"
  http.request(endpoint, http.Put, first, body, 500) |> should.be_ok
  let assert Ok(config) = transport.config(endpoint, "replay", "b", ["a"])
  let assert Ok(worker) = transport.start(config, b.data)
  process.sleep(200)
  let assert Ok(before) = peers.snapshot(b.data)
  let assert [old] = peer.freshness(before.peer).actors
  let assert deadman_freshness.HeartbeatTripped(_) = old.status
  http.request(endpoint, http.Put, second, body, 500) |> should.be_ok
  process.sleep(100)
  let assert Ok(stats) = transport.shutdown(worker.data)
  stats.applied |> should.equal(2)
  let assert Ok(after) = peers.snapshot(b.data)
  let assert [fresh] = peer.freshness(after.peer).actors
  fresh.last_heartbeat_ms |> should.equal(old.last_heartbeat_ms)
  let assert deadman_freshness.HeartbeatTripped(_) = fresh.status
  let assert Ok(_) = peers.shutdown(b.data)
  stop(server)
}

fn timeout_cleanup_test() {
  let observer = process.new_subject()
  // Observe owner-exit socket closure before ending the server.
  let #(server, port) = server(Cleanup(observer))
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", port)
  http.request(endpoint, http.Get, key, "", 30)
  |> should.equal(Error(http.Timeout))
  process.receive(observer, 500) |> should.equal(Ok(True))
  stop(server)
}

fn retry_cursor_test() {
  let observer = process.new_subject()
  let #(server, port) = server(RetryReadback(observer))
  let a = start_peer("a", "b")
  let assert Ok(_) = peers.gossip(a)
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", port)
  let assert Ok(config) = transport.config(endpoint, "retry", "a", ["b"])
  let assert Ok(worker) = transport.start(config, a)
  process.sleep(250)
  let assert Ok(stats) = transport.shutdown(worker.data)
  stats.published |> should.equal(1)
  { stats.failures > 0 } |> should.be_true
  process.receive(observer, 100) |> should.equal(Ok("PUT"))
  process.receive(observer, 100) |> should.equal(Ok("READBACK_LOST"))
  process.receive(observer, 30) |> should.be_error
  let assert Ok(after) = peers.pull(a, 1)
  after |> should.equal([])
  let assert Ok(_) = peers.shutdown(a)
  stop(server)
}

// Used only with a private fault-injected peer module whose first successful
// delivery report reply is delayed beyond the public peer RPC timeout.
pub fn run_delayed_report_fault() {
  let observer = process.new_subject()
  let #(server, port) = server(RetryReadback(observer))
  let a = start_peer("a", "b")
  let assert Ok(_) = peers.gossip(a)
  let assert Ok(_) = peers.gossip(a)
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", port)
  let assert Ok(config) =
    transport.config(endpoint, "delayed-report", "a", ["b"])
  let assert Ok(worker) = transport.start(config, a)
  process.sleep(3000)
  let assert Ok(stats) = transport.shutdown(worker.data)
  stats.published |> should.equal(2)
  let assert Ok(after) = peers.pull(a, 256)
  after |> should.equal([])
  let assert Ok(_) = peers.shutdown(a)
  stop(server)
  io.println("PASS delayed_report_retirement_preserves_route_cursor")
}

pub fn run_cleanup_halt_fault() {
  let a = start_peer("a", "b")
  let assert Ok(_) = peers.gossip(a)
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", 8080)
  let assert Ok(config) =
    transport.config(endpoint, "synthetic-cleanup-halt", "a", ["b"])
  let assert Ok(worker) = transport.start(config, a)
  process.sleep(200)
  let assert Ok(stats) = transport.shutdown(worker.data)
  stats.failures |> should.equal(1)
  stats.published |> should.equal(0)
  let assert Ok(frames) = peers.pull(a, 256)
  list.length(frames) |> should.equal(1)
  let assert Ok(_) = peers.shutdown(a)
  io.println("PASS unknown_cleanup_latches_io_halt")
}

pub fn run_receive_retry_fault() {
  let #(server, port) = server(Store)
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", port)
  let b = start_peer("b", "a")
  let assert Ok(wire) =
    mesh_sync.encode_sync_message(mesh_sync.SyncAck("a", [], "ok", 1))
  let body =
    json.array(
      [
        json.string("uos.ev98.transport.v1"),
        json.string("a"),
        json.string("b"),
        json.int(10),
        json.int(1),
        json.string(wire),
      ],
      fn(x) { x },
    )
    |> json.to_string
  let route =
    "uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/receive-retry/a/b/1"
  http.request(endpoint, http.Put, route, body, 500) |> should.be_ok
  let assert Ok(config) =
    transport.config(endpoint, "receive-retry", "b", ["a"])
  let assert Ok(worker) = transport.start(config, b)
  process.sleep(250)
  let assert Ok(stats) = transport.shutdown(worker.data)
  stats.applied |> should.equal(1)
  stats.failures |> should.equal(1)
  let assert Ok(_) = peers.shutdown(b)
  stop(server)
  io.println("PASS unavailable_receive_retries_same_route_cursor")
}

fn supervised_worker_test() {
  let #(server, port) = server(Store)
  let a = start_peer("a", "b")
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", port)
  let assert Ok(config) = transport.config(endpoint, "supervised", "a", ["b"])
  let replies = process.new_subject()
  let specification = transport.supervised(config, a)
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
  let assert Ok(supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(child)
    |> static_supervisor.start
  let assert Ok(first) = process.receive(replies, 1000)
  process.kill(first.pid)
  let assert Ok(second) = process.receive(replies, 1500)
  let assert Ok(_) = transport.shutdown(second.data)
  process.receive(replies, 100) |> should.be_error
  process.unlink(supervisor.pid)
  process.kill(supervisor.pid)
  let assert Ok(_) = peers.shutdown(a)
  stop(server)
}

// Ordinary EUnit discovery executes the production transport checks. Synthetic
// fault entry points above are called explicitly by the mutated private builds.
pub fn production_transport_test() {
  main()
}

pub fn main() {
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", 8080)
  transport.config(endpoint, "synthetic-red", "a", ["b"]) |> should.be_ok
  io.println("PASS valid_transport_configuration")
  http.endpoint("localhost", 8080) |> should.be_error
  transport.config(endpoint, "../escape", "a", ["b"]) |> should.be_error
  transport.config(endpoint, "safe", "a", ["a"]) |> should.be_error
  io.println("PASS configuration_refusals")
  http_test(Store, 500) |> should.equal(Ok(http.Response(200, "[]")))
  io.println("PASS bounded_http_content_length")
  http_test(Chunked, 500) |> should.equal(Ok(http.Response(200, "[]")))
  io.println("PASS bounded_http_chunked")
  http_test(Huge, 500) |> should.equal(Error(http.BodyLimit))
  http_test(Duplicate, 500) |> should.equal(Error(http.Protocol))
  http_test(Slow, 30) |> should.equal(Error(http.Timeout))
  http_test(Redirect, 500) |> should.equal(Error(http.Status(302)))
  http_test(Ambiguous, 500) |> should.equal(Error(http.Protocol))
  http_test(SignedLength, 500) |> should.equal(Error(http.Protocol))
  http_test(BadChunk, 500) |> should.equal(Error(http.Protocol))
  http_test(ChunkHuge, 500) |> should.equal(Error(http.BodyLimit))
  http_test(ChunkAggregate, 500) |> should.equal(Error(http.BodyLimit))
  let assert Ok(boundary) = http_test(ExactBody, 500)
  string.byte_size(boundary.body) |> should.equal(http.max_body)
  io.println("PASS oversize_duplicate_timeout")
  worker_test(FailPut)
  io.println("PASS failed_publish_retains_exact_frame")
  worker_test(Store)
  io.println("PASS two_actor_fake_broker_exchange")
  worker_test(DeepJson)
  worker_test(DuplicateJson)
  io.println("PASS deep_sample_refusal")
  replay_test()
  io.println("PASS replay_does_not_rearm_deadman")
  timeout_cleanup_test()
  io.println("PASS deadline_cancels_socket_owner")
  retry_cursor_test()
  io.println("PASS lost_readback_retries_without_overwrite")
  supervised_worker_test()
  io.println("PASS worker_supervision_and_controlled_shutdown")
}

pub fn run_quota_boundary_fault() {
  let #(server, port) = server(Store)
  let a = start_peer("a", "b")
  let assert Ok(_) = peers.gossip(a)
  let assert Ok(_) = peers.gossip(a)
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", port)
  let assert Ok(config) =
    transport.config(endpoint, "quota-boundary", "a", ["b"])
  let assert Ok(worker) = transport.start(config, a)
  process.sleep(250)
  let assert Ok(stats) = transport.shutdown(worker.data)
  stats.published |> should.equal(256)
  { stats.failures > 0 } |> should.be_true
  let assert Ok(frames) = peers.pull(a, 256)
  list.length(frames) |> should.equal(1)
  let assert Ok(_) = peers.shutdown(a)
  stop(server)
  io.println("PASS publication_quota_boundary_retains_next_frame")
}

pub fn broker_probe() {
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", 8080)
  let assert Ok(response) =
    http.request(
      endpoint,
      http.Get,
      "uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/readonly-probe-1419/a/b/1",
      "",
      2000,
    )
  io.println(response.body)
  Nil
}
