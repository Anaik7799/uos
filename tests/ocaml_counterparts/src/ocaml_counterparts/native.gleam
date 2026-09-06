import exception
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/port.{type Port}
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/result

const limit = 8_388_608

const adapter = "../../engines/hermes/_build/default/test_ports/parity/parity_port.exe"

pub fn fixture_path() -> String {
  "../../engines/hermes/_build/default/test_ports/parity/fault_port.exe"
}

type Executable {
  SpawnExecutable(String)
}

type Option {
  Binary
  Args(List(String))
  StderrToStdout
}

type ExitOption {
  ExitStatus
}

type OsPid {
  OsPid
}

type Unit {
  Millisecond
}

type Event {
  Data(BitArray)
  Exited(Int)
}

type SendOption {
  Nosuspend
}

@external(erlang, "erlang", "open_port")
fn open_port(executable: Executable, options: List(Dynamic)) -> Port

@external(erlang, "erlang", "port_command")
fn command(port: Port, bytes: BitArray, options: List(SendOption)) -> Bool

@external(erlang, "erlang", "port_close")
fn close(port: Port) -> Bool

@external(erlang, "erlang", "port_info")
fn port_pid(port: Port, item: OsPid) -> #(OsPid, Int)

@external(erlang, "erlang", "element")
fn element(index: Int, message: Dynamic) -> Dynamic

@external(erlang, "erlang", "monotonic_time")
fn clock(unit: Unit) -> Int

@external(erlang, "gleam_stdlib", "identity")
fn dynamic(value: a) -> Dynamic

fn options(argv: List(String)) -> List(Dynamic) {
  [dynamic(Binary), dynamic(ExitStatus), dynamic(Args(argv))]
}

fn event(message: Dynamic) -> Event {
  let payload = element(2, message)
  let tag = element(1, payload)
  let value = element(2, payload)
  case tag == dynamic(ExitStatus) {
    True -> {
      let assert Ok(code) = decode.run(value, decode.int)
      Exited(code)
    }
    False -> {
      let assert Ok(bytes) = decode.run(value, decode.bit_array)
      Data(bytes)
    }
  }
}

fn terminate(port: Port, pid: Int) {
  // Direct executable invocation, never a shell; this pure adapter has no children.
  let _ =
    exception.rescue(fn() {
      let killer =
        open_port(SpawnExecutable("/usr/bin/kill"), [
          dynamic(StderrToStdout),
          ..options(["-KILL", int.to_string(pid)])
        ])
      let selector =
        process.new_selector() |> process.select_record(killer, 1, event)
      let _ = process.selector_receive(selector, 1000)
      let _ = exception.rescue(fn() { close(killer) })
      Nil
    })
  let _ = exception.rescue(fn() { close(port) })
  Nil
}

pub fn request(
  operation: String,
  arguments: json.Json,
) -> Result(Dynamic, String) {
  request_with(adapter, [], operation, arguments, 30_000)
}

pub fn request_with(
  path: String,
  argv: List(String),
  operation: String,
  arguments: json.Json,
  timeout: Int,
) -> Result(Dynamic, String) {
  let id = "parity-1"
  let payload =
    json.object([
      #("version", json.int(1)),
      #("id", json.string(id)),
      #("operation", json.string(operation)),
      #("arguments", arguments),
    ])
    |> json.to_string
    |> bit_array.from_string
  let size = bit_array.byte_size(payload)
  case size > limit || timeout < 1 || timeout > 30_000 {
    True -> Error("request_bounds")
    False -> {
      use p <- result.try(
        exception.rescue(fn() {
          open_port(SpawnExecutable(path), options(argv))
        })
        |> result.map_error(fn(_) { "spawn_failed" }),
      )
      let #(_, pid) = port_pid(p, OsPid)
      let outcome =
        exception.rescue(fn() {
          let deadline = clock(Millisecond) + timeout
          let selector =
            process.new_selector() |> process.select_record(p, 1, event)
          case command(p, <<size:32-big, payload:bits>>, [Nosuspend]) {
            True -> receive(selector, <<>>, deadline)
            False -> Error("port_busy")
          }
        })
        |> result.unwrap(Error("port_error"))
      case outcome {
        Error("nonzero_exit") -> Nil
        Error(_) -> terminate(p, pid)
        Ok(_) -> Nil
      }
      use raw <- result.try(outcome)
      use bytes <- result.try(frame(raw))
      decode_reply(bytes, id, operation)
    }
  }
}

fn receive(
  selector: process.Selector(Event),
  bytes: BitArray,
  deadline: Int,
) -> Result(BitArray, String) {
  let remaining = deadline - clock(Millisecond)
  case remaining <= 0 {
    True -> Error("timeout")
    False -> {
      case process.selector_receive(selector, remaining) {
        Error(_) -> Error("timeout")
        Ok(Exited(code)) ->
          case code {
            0 -> Ok(bytes)
            _ -> Error("nonzero_exit")
          }
        Ok(Data(chunk)) -> {
          let joined = <<bytes:bits, chunk:bits>>
          case bit_array.byte_size(joined) > limit + 4 {
            True -> Error("oversized_frame")
            False ->
              case joined {
                <<size:32-big, _:bytes>> if size > limit ->
                  Error("oversized_frame")
                _ -> receive(selector, joined, deadline)
              }
          }
        }
      }
    }
  }
}

fn frame(bytes: BitArray) -> Result(BitArray, String) {
  case bytes {
    <<size:32-big, payload:bytes>> ->
      case bit_array.byte_size(payload) {
        actual if actual < size -> Error("truncated_frame")
        actual if actual > size -> Error("malformed_frame")
        _ -> Ok(payload)
      }
    _ -> Error("malformed_frame")
  }
}

pub fn decode_reply(
  bytes: BitArray,
  id: String,
  operation: String,
) -> Result(Dynamic, String) {
  use _ <- result.try(check_depth(bytes, 0, False, False))
  use text <- result.try(
    bit_array.to_string(bytes) |> result.map_error(fn(_) { "malformed_json" }),
  )
  use value <- result.try(
    json.parse(text, decode.dynamic)
    |> result.map_error(fn(_) { "malformed_json" }),
  )
  let identity = {
    use version <- decode.field("version", decode.int)
    use response_id <- decode.field("id", decode.string)
    use response_op <- decode.field("operation", decode.string)
    decode.success(#(version, response_id, response_op))
  }
  case decode.run(value, identity) {
    Ok(#(1, response_id, response_op))
      if response_id == id && response_op == operation
    -> {
      let error =
        decode.run(value, decode.field("error", decode.dynamic, decode.success))
      let payload =
        decode.run(
          value,
          decode.field("result", decode.dynamic, decode.success),
        )
      case error, payload {
        Ok(error), Error(_) -> {
          let structured_error = {
            use code <- decode.field("code", decode.string)
            use message <- decode.field("message", decode.string)
            decode.success(#(code, message))
          }
          case decode.run(error, structured_error) {
            Ok(_) -> Error("native_error")
            Error(_) -> Error("malformed_json")
          }
        }
        Error(_), Ok(payload) -> Ok(payload)
        _, _ -> Error("malformed_json")
      }
    }
    _ -> Error("identity_mismatch")
  }
}

fn check_depth(
  bytes: BitArray,
  depth: Int,
  quoted: Bool,
  escaped: Bool,
) -> Result(Nil, String) {
  case bytes {
    <<>> -> Ok(Nil)
    <<byte, rest:bytes>> ->
      case quoted {
        True ->
          case escaped {
            True -> check_depth(rest, depth, True, False)
            False ->
              case byte {
                92 -> check_depth(rest, depth, True, True)
                34 -> check_depth(rest, depth, False, False)
                _ -> check_depth(rest, depth, True, False)
              }
          }
        False ->
          case byte {
            34 -> check_depth(rest, depth, True, False)
            91 | 123 ->
              case depth >= 64 {
                True -> Error("json_depth")
                False -> check_depth(rest, depth + 1, False, False)
              }
            93 | 125 -> check_depth(rest, depth - 1, False, False)
            _ -> check_depth(rest, depth, False, False)
          }
      }
    _ -> Error("malformed_json")
  }
}
