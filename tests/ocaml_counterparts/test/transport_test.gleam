import gleam/bit_array
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import ocaml_counterparts/native
import simplifile

pub fn faults_test() {
  list.each(
    [
      #("malformed_frame", "malformed_frame"),
      #("truncated", "truncated_frame"),
      #("oversized", "oversized_frame"),
      #("malformed_json", "malformed_json"),
      #("wrong_id", "identity_mismatch"),
      #("wrong_version", "identity_mismatch"),
      #("wrong_operation", "identity_mismatch"),
      #("native_error", "native_error"),
      #("nonzero", "nonzero_exit"),
      #("timeout", "timeout"),
    ],
    fn(pair) {
      let #(mode, expected) = pair
      native.request_with(
        native.fixture_path(),
        [mode],
        "observe",
        json.object([]),
        200,
      )
      |> should.equal(Error(expected))
    },
  )
}

pub fn missing_executable_test() {
  native.request_with(
    "/nonexistent/uos-parity-adapter",
    [],
    "observe",
    json.object([]),
    200,
  )
  |> should.equal(Error("spawn_failed"))
}

pub fn native_request_errors_test() {
  native.request("unknown", json.object([]))
  |> should.equal(Error("native_error"))
  native.request("report", json.object([#("required", json.string("yes"))]))
  |> should.equal(Error("native_error"))
}

pub fn bounded_json_test() {
  let deep = string.repeat("[", 65) <> "0" <> string.repeat("]", 65)
  native.decode_reply(bit_array.from_string(deep), "parity-1", "observe")
  |> should.equal(Error("json_depth"))
}

@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

pub fn timeout_reaps_direct_child_test() {
  let path =
    "/tmp/uos-parity-timeout-" <> int.to_string(unique_integer()) <> ".pid"
  native.request_with(
    native.fixture_path(),
    ["timeout", path],
    "observe",
    json.object([]),
    200,
  )
  |> should.equal(Error("timeout"))
  let pid = simplifile.read(path) |> should.be_ok |> string.trim
  process.sleep(20)
  simplifile.is_directory("/proc/" <> pid) |> should.equal(Ok(False))
  simplifile.delete_file(path) |> should.be_ok
}

pub fn oversized_request_test() {
  native.request_with(
    native.fixture_path(),
    [],
    "observe",
    json.string(string.repeat("x", 8_388_609)),
    200,
  )
  |> should.equal(Error("request_bounds"))
}

pub fn strict_envelope_test() {
  list.each(
    [
      "\"error\":false",
      "\"error\":{\"code\":7,\"message\":null}",
      "\"error\":{\"code\":\"bad\",\"message\":\"bad\"},\"result\":null",
      "\"other\":null",
    ],
    fn(payload) {
      let body =
        "{\"version\":1,\"id\":\"parity-1\",\"operation\":\"observe\","
        <> payload
        <> "}"
      native.decode_reply(bit_array.from_string(body), "parity-1", "observe")
      |> should.equal(Error("malformed_json"))
    },
  )
}
