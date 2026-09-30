import cepaf_gleam/crdt/mesh_zenoh_http as http
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/string
import gleeunit/should

type Socket
type SocketOption {
  Binary
  Active(Bool)
  Packet(Int)
  Ip(#(Int, Int, Int, Int))
  Reuseaddr(Bool)
  SendTimeout(Int)
}
@external(erlang, "gen_tcp", "listen")
fn listen(port: Int, options: List(SocketOption)) -> Result(Socket, Dynamic)
@external(erlang, "inet", "port")
fn port(socket: Socket) -> Result(Int, Dynamic)
@external(erlang, "gen_tcp", "accept")
fn accept(socket: Socket, timeout: Int) -> Result(Socket, Dynamic)
@external(erlang, "gen_tcp", "recv")
fn recv(socket: Socket, size: Int, timeout: Int) -> Result(BitArray, Dynamic)
@external(erlang, "gen_tcp", "send")
fn send(socket: Socket, bytes: BitArray) -> Dynamic
@external(erlang, "gen_tcp", "close")
fn close(socket: Socket) -> Dynamic

type Observation {
  Listening(Int)
  Accepted
  Closed(Bool)
}

fn read_headers(socket: Socket, remaining: Int, previous: BitArray) {
  case remaining > 0 {
    False -> panic as "bounded fixture request exceeded header budget"
    True -> {
      let assert Ok(byte) = recv(socket, 1, 1000)
      let next = <<previous:bits, byte:bits>>
      case next {
        <<13, 10, 13, 10>> -> Nil
        _ -> {
          let next = case bit_array.byte_size(next) > 3 {
            True -> {
              let assert Ok(tail) = bit_array.slice(next, 1, 3)
              tail
            }
            False -> next
          }
          read_headers(socket, remaining - 1, next)
        }
      }
    }
  }
}

fn start_fixture(response: BitArray, hang: Bool) {
  let events = process.new_subject()
  let child = process.spawn(fn() {
    let assert Ok(listener) = listen(0, [
      Binary, Active(False), Packet(0), Ip(#(100, 87, 7, 78)),
      Reuseaddr(True), SendTimeout(1000),
    ])
    let assert Ok(p) = port(listener)
    process.send(events, Listening(p))
    let assert Ok(socket) = accept(listener, 1000)
    read_headers(socket, 8192, <<>>)
    process.send(events, Accepted)
    case hang {
      True -> Nil
      False -> {
        let _ = send(socket, response)
        Nil
      }
    }
    let closed = case recv(socket, 1, 2500) {
      Error(reason) ->
        reason == atom.to_dynamic(atom.create("closed"))
        || reason == atom.to_dynamic(atom.create("econnreset"))
      Ok(_) -> False
    }
    process.send(events, Closed(closed))
    let _ = close(socket)
    let _ = close(listener)
    Nil
  })
  let assert Ok(Listening(p)) = process.receive(events, 1000)
  #(child, p, events)
}

const key = "uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/private-independent-http/a/b/1"

fn exchange(response: BitArray, timeout_ms: Int, hang: Bool) {
  let #(server, port, events) = start_fixture(response, hang)
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", port)
  let outcome = http.request(endpoint, http.Get, key, "", timeout_ms)
  let assert Ok(Accepted) = process.receive(events, 1000)
  let assert Ok(Closed(closed)) = process.receive(events, 3000)
  closed |> should.be_true
  process.unlink(server)
  process.kill(server)
  outcome
}

fn length_response(length: String, bytes: BitArray) -> BitArray {
  let head = "HTTP/1.1 200 OK\r\nContent-Length: " <> length <> "\r\n\r\n"
  <<head:utf8, bytes:bits>>
}

pub fn limits() {
  let body = string.repeat("a", http.max_body)
  let assert Ok(response) = exchange(
    length_response(int.to_string(http.max_body), bit_array.from_string(body)),
    1000, False,
  )
  response.body |> should.equal(body)
  exchange(length_response("800001", <<>>), 500, False)
    |> should.equal(Error(http.BodyLimit))
  io.println("PASS independent_http_exact_body_limit_and_socket_close")
}

pub fn framing() {
  exchange(bit_array.from_string(
    "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nTransfer-Encoding: chunked\r\n\r\n",
  ), 500, False) |> should.equal(Error(http.Protocol))
  exchange(length_response("+2", <<91, 93>>), 500, False)
    |> should.equal(Error(http.Protocol))
  exchange(length_response("-0", <<>>), 500, False)
    |> should.equal(Error(http.Protocol))
  exchange(bit_array.from_string(
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n+1\r\n[\r\n0\r\n\r\n",
  ), 500, False) |> should.equal(Error(http.Protocol))
  exchange(length_response("1", <<255>>), 500, False)
    |> should.equal(Error(http.Protocol))
  io.println("PASS independent_http_ambiguous_framing_and_invalid_utf8")
}

pub fn timeout() {
  exchange(<<>>, 30, True) |> should.equal(Error(http.Timeout))
  io.println("PASS independent_http_timeout_observes_socket_eof")
}

pub fn owner_death() {
  let #(server, port, events) = start_fixture(<<>>, True)
  let assert Ok(endpoint) = http.endpoint("nas-1.tail55d152.ts.net", port)
  let owner = process.spawn_unlinked(fn() {
    let _ = http.request(endpoint, http.Get, key, "", 2000)
    Nil
  })
  let assert Ok(Accepted) = process.receive(events, 1000)
  process.kill(owner)
  // This covers owner death after connection/headers, not the spawn window.
  let assert Ok(Closed(closed)) = process.receive(events, 500)
  closed |> should.be_true
  process.unlink(server)
  process.kill(server)
  io.println("PASS independent_http_owner_death_after_connection")
}

pub fn main() {
  limits()
  framing()
  timeout()
  owner_death()
}
