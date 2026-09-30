//// Narrow HTTP/1.1 client for owned Zenoh REST keys. No redirects, proxy,
//// credentials, TLS downgrade, wildcard selectors or caller request headers.

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub const max_body = 800_000

pub const max_header = 8192

pub type Error {
  InvalidConfig
  Timeout
  Network
  CleanupUnconfirmed
  HeaderLimit
  BodyLimit
  Protocol
  Status(Int)
}

pub type Method {
  Get
  Put
}

pub opaque type Endpoint {
  Endpoint(host: String, port: Int)
}

pub type Response {
  Response(status: Int, body: String)
}

type Socket

type Option {
  Binary
  Active(Bool)
  Packet(Int)
  Recbuf(Int)
  Buffer(Int)
  SendTimeout(Int)
  SendTimeoutClose(Bool)
}

type Unit {
  Millisecond
}

@external(erlang, "erlang", "monotonic_time")
fn now(unit: Unit) -> Int

@external(erlang, "erlang", "binary_to_list")
fn chars(s: String) -> List(Int)

@external(erlang, "gen_tcp", "connect")
fn connect(
  host: List(Int),
  port: Int,
  options: List(Option),
  timeout: Int,
) -> Result(Socket, Dynamic)

@external(erlang, "gen_tcp", "send")
fn send(socket: Socket, bytes: String) -> Dynamic

@external(erlang, "gen_tcp", "recv")
fn recv(socket: Socket, length: Int, timeout: Int) -> Result(BitArray, Dynamic)

@external(erlang, "gen_tcp", "close")
fn close(socket: Socket) -> Dynamic

pub fn endpoint(host: String, port: Int) -> Result(Endpoint, Error) {
  case
    string.byte_size(host) <= 253
    && string.ends_with(host, ".tail55d152.ts.net")
    && valid_host(chars(host))
    && port > 0
    && port <= 65_535
  {
    True -> Ok(Endpoint(host, port))
    False -> Error(InvalidConfig)
  }
}

fn valid_host(xs: List(Int)) -> Bool {
  case xs {
    [] -> True
    [c, ..rest] ->
      { c >= 97 && c <= 122 || c >= 48 && c <= 57 || c == 45 || c == 46 }
      && valid_host(rest)
  }
}

pub fn segment(s: String) -> Bool {
  let n = string.byte_size(s)
  n >= 1 && n <= 80 && valid_segment(chars(s))
}

fn valid_segment(xs: List(Int)) -> Bool {
  case xs {
    [] -> True
    [c, ..rest] ->
      {
        c >= 97
        && c <= 122
        || c >= 65
        && c <= 90
        || c >= 48
        && c <= 57
        || c == 45
        || c == 95
      }
      && valid_segment(rest)
  }
}

fn digits(xs: List(Int), hex: Bool) -> Bool {
  case xs {
    [] -> True
    [c, ..rest] ->
      {
        c >= 48
        && c <= 57
        || hex
        && { c >= 65 && c <= 70 || c >= 97 && c <= 102 }
      }
      && digits(rest, hex)
  }
}

fn numeral(s: String, hex: Bool) -> Bool {
  string.byte_size(s) >= 1 && string.byte_size(s) <= 6 && digits(chars(s), hex)
}

fn valid_key(key: String) -> Bool {
  string.byte_size(key) <= 512
  && string.starts_with(
    key,
    "uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/",
  )
  && list.all(string.split(key, "/"), segment)
}

type Event {
  Returned(Result(Response, Error))
  Exited
}

type Watch {
  ChildDown
  OwnerDown
}

fn watchdog(owner: process.Pid, child: process.Pid, timeout: Int) {
  let parent_monitor = process.monitor(owner)
  let child_monitor = process.monitor(child)
  let selector =
    process.new_selector()
    |> process.select_specific_monitor(parent_monitor, fn(_) { OwnerDown })
    |> process.select_specific_monitor(child_monitor, fn(_) { ChildDown })
  case process.selector_receive(selector, timeout + 100) {
    Ok(ChildDown) -> Nil
    _ -> {
      process.kill(child)
      let _ =
        process.new_selector()
        |> process.select_specific_monitor(child_monitor, fn(_) { Nil })
        |> process.selector_receive(100)
      Nil
    }
  }
  process.demonitor_process(parent_monitor)
  process.demonitor_process(child_monitor)
}

/// Disposable socket owner plus owner-death watchdog; no link can crash the
/// caller. Confirmed DOWN permits flushing the sole response without a late
/// response. CleanupUnconfirmed does not make that guarantee and must halt I/O.
/// Cleanup observation adds at most 300ms. The bounded watchdog is installed
/// after spawn; immediate atomic owner-death cleanup is not claimed.
pub fn request(
  endpoint: Endpoint,
  method: Method,
  key: String,
  body: String,
  timeout_ms: Int,
) -> Result(Response, Error) {
  case
    valid_key(key)
    && string.byte_size(body) <= max_body
    && timeout_ms >= 10
    && timeout_ms <= 2000
  {
    False -> Error(InvalidConfig)
    True -> {
      let reply = process.new_subject()
      let owner = process.self()
      let child =
        process.spawn_unlinked(fn() {
          process.send(reply, perform(endpoint, method, key, body, timeout_ms))
        })
      let monitor = process.monitor(child)
      let watcher =
        process.spawn_unlinked(fn() { watchdog(owner, child, timeout_ms) })
      let watch_monitor = process.monitor(watcher)
      let selected =
        process.new_selector()
        |> process.select_map(reply, Returned)
        |> process.select_specific_monitor(monitor, fn(_) { Exited })
        |> process.selector_receive(timeout_ms)
      let outcome = case selected {
        Ok(Returned(value)) -> value
        Ok(Exited) -> Error(Network)
        Error(_) -> Error(Timeout)
      }
      process.kill(child)
      let dead = case selected {
        Ok(Exited) -> True
        _ ->
          process.new_selector()
          |> process.select_specific_monitor(monitor, fn(_) { Nil })
          |> process.selector_receive(100)
          |> result.is_ok
      }
      let watched =
        process.new_selector()
        |> process.select_specific_monitor(watch_monitor, fn(_) { Nil })
        |> process.selector_receive(100)
        |> result.is_ok
      let watched = case watched {
        True -> True
        False -> {
          process.kill(watcher)
          process.new_selector()
          |> process.select_specific_monitor(watch_monitor, fn(_) { Nil })
          |> process.selector_receive(100)
          |> result.is_ok
        }
      }
      let _ = process.receive(reply, 0)
      process.demonitor_process(monitor)
      process.demonitor_process(watch_monitor)
      case dead && watched {
        True -> outcome
        False -> Error(CleanupUnconfirmed)
      }
    }
  }
}

fn perform(
  endpoint: Endpoint,
  method: Method,
  key: String,
  body: String,
  timeout_ms: Int,
) -> Result(Response, Error) {
  let deadline = now(Millisecond) + timeout_ms
  use sock <- result.try(
    connect(
      chars(endpoint.host),
      endpoint.port,
      [
        Binary,
        Active(False),
        Packet(0),
        Recbuf(4096),
        Buffer(4096),
        SendTimeout(timeout_ms),
        SendTimeoutClose(True),
      ],
      timeout_ms,
    )
    |> result.map_error(fn(_) { Network }),
  )
  let method_text = case method {
    Get -> "GET"
    Put -> "PUT"
  }
  let payload = case method {
    Get -> ""
    Put -> body
  }
  let request =
    method_text
    <> " /"
    <> key
    <> " HTTP/1.1\r\nHost: "
    <> endpoint.host
    <> ":"
    <> int.to_string(endpoint.port)
    <> "\r\nConnection: close\r\nAccept: application/json\r\nContent-Type: application/json\r\nContent-Length: "
    <> int.to_string(string.byte_size(payload))
    <> "\r\n\r\n"
    <> payload
  let outcome = case send(sock, request) == atom.to_dynamic(atom.create("ok")) {
    False -> Error(Network)
    True -> response(sock, deadline)
  }
  let _ = close(sock)
  outcome
}

fn read(sock: Socket, size: Int, deadline: Int) -> Result(BitArray, Error) {
  let left = deadline - now(Millisecond)
  case left > 0 {
    False -> Error(Timeout)
    True -> recv(sock, size, left) |> result.map_error(fn(_) { Network })
  }
}

fn line(
  sock: Socket,
  deadline: Int,
  left: Int,
  acc: BitArray,
) -> Result(String, Error) {
  case left <= 0 {
    True -> Error(HeaderLimit)
    False -> {
      use byte <- result.try(read(sock, 1, deadline))
      let next = <<acc:bits, byte:bits>>
      case byte == <<10>> {
        True -> {
          use text <- result.try(
            bit_array.to_string(next) |> result.map_error(fn(_) { Protocol }),
          )
          case string.ends_with(text, "\r\n") {
            True -> {
              use raw <- result.try(
                bit_array.slice(next, 0, bit_array.byte_size(next) - 2)
                |> result.map_error(fn(_) { Protocol }),
              )
              bit_array.to_string(raw) |> result.map_error(fn(_) { Protocol })
            }
            False -> Error(Protocol)
          }
        }
        False -> line(sock, deadline, left - 1, next)
      }
    }
  }
}

fn response(sock: Socket, deadline: Int) -> Result(Response, Error) {
  use first <- result.try(line(sock, deadline, 128, <<>>))
  use status <- result.try(case string.split(first, " ") {
    ["HTTP/1.1", code, ..] | ["HTTP/1.0", code, ..] ->
      case string.byte_size(code) == 3 && numeral(code, False) {
        True -> int.parse(code) |> result.map_error(fn(_) { Protocol })
        False -> Error(Protocol)
      }
    _ -> Error(Protocol)
  })
  case status >= 200 && status < 300 {
    False -> Error(Status(status))
    True -> {
      use headers <- result.try(
        headers(sock, deadline, max_header - string.byte_size(first), []),
      )
      use body <- result.try(
        case
          list.key_find(headers, "transfer-encoding"),
          list.key_find(headers, "content-length")
        {
          Ok("chunked"), Error(_) -> chunks(sock, deadline, max_body, [])
          Error(_), Ok(length) -> {
            use _ <- result.try(case numeral(length, False) {
              True -> Ok(Nil)
              False -> Error(Protocol)
            })
            use size <- result.try(
              int.parse(length) |> result.map_error(fn(_) { Protocol }),
            )
            case size >= 0 && size <= max_body {
              True -> read_body(sock, deadline, size, [])
              False -> Error(BodyLimit)
            }
          }
          Error(_), Error(_) if status == 204 -> Ok("")
          _, _ -> Error(Protocol)
        },
      )
      Ok(Response(status, body))
    }
  }
}

fn headers(
  sock: Socket,
  deadline: Int,
  remaining: Int,
  acc: List(#(String, String)),
) -> Result(List(#(String, String)), Error) {
  use text <- result.try(line(sock, deadline, int.min(1024, remaining), <<>>))
  case text {
    "" -> Ok(acc)
    _ -> {
      use pair <- result.try(
        string.split_once(text, ":") |> result.map_error(fn(_) { Protocol }),
      )
      let #(name, value) = pair
      let name = string.lowercase(name)
      case name == "" || list.key_find(acc, name) |> result.is_ok {
        True -> Error(Protocol)
        False ->
          headers(sock, deadline, remaining - string.byte_size(text) - 2, [
            #(name, string.trim(value)),
            ..acc
          ])
      }
    }
  }
}

fn read_bytes(
  sock: Socket,
  deadline: Int,
  remaining: Int,
  acc: List(BitArray),
) -> Result(BitArray, Error) {
  case remaining {
    0 -> Ok(bit_array.concat(list.reverse(acc)))
    _ -> {
      let n = int.min(4096, remaining)
      use bytes <- result.try(read(sock, n, deadline))
      case bit_array.byte_size(bytes) == n {
        True -> read_bytes(sock, deadline, remaining - n, [bytes, ..acc])
        False -> Error(Protocol)
      }
    }
  }
}

fn read_body(
  sock: Socket,
  deadline: Int,
  remaining: Int,
  acc: List(BitArray),
) -> Result(String, Error) {
  read_bytes(sock, deadline, remaining, acc)
  |> result.try(fn(b) {
    bit_array.to_string(b) |> result.map_error(fn(_) { Protocol })
  })
}

fn chunks(
  sock: Socket,
  deadline: Int,
  remaining: Int,
  acc: List(BitArray),
) -> Result(String, Error) {
  chunk_loop(sock, deadline, remaining, acc, 4096)
}

fn chunk_loop(
  sock: Socket,
  deadline: Int,
  remaining: Int,
  acc: List(BitArray),
  chunks_left: Int,
) -> Result(String, Error) {
  use text <- result.try(line(sock, deadline, 16, <<>>))
  use _ <- result.try(case numeral(text, True) {
    True -> Ok(Nil)
    False -> Error(Protocol)
  })
  use size <- result.try(
    int.base_parse(text, 16) |> result.map_error(fn(_) { Protocol }),
  )
  case size {
    0 -> {
      use end <- result.try(line(sock, deadline, 2, <<>>))
      case end {
        "" ->
          bit_array.concat(list.reverse(acc))
          |> bit_array.to_string
          |> result.map_error(fn(_) { Protocol })
        _ -> Error(Protocol)
      }
    }
    n if n > 0 && n <= remaining && chunks_left > 0 -> {
      use part <- result.try(read_bytes(sock, deadline, n, []))
      use end <- result.try(read(sock, 2, deadline))
      case end == <<13, 10>> {
        True ->
          chunk_loop(
            sock,
            deadline,
            remaining - n,
            [part, ..acc],
            chunks_left - 1,
          )
        False -> Error(Protocol)
      }
    }
    _ -> Error(BodyLimit)
  }
}
