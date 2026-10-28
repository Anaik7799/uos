//// Inert proposal for a real MCP stdio pipe regression.
//// This module is not in the application test tree and was not compiled/run.

import cepaf_gleam/harness/mcp
import cepaf_gleam/harness/value
import gleam/bit_array
import gleam/json
import gleam/option.{Some}
import gleeunit/should

@external(erlang, "ecology_capability_ffi", "uos_root")
fn uos_root() -> String

// This declaration records the proposed bounded raw-stdin ABI. It is not
// exported in the frozen candidate yet; the inert manifest specifies the
// narrow wrapper needed before this test can run. Existing length-prefixed
// framed input remains unchanged for its service child protocols.
@external(erlang, "ecology_capability_ffi", "run_bounded_raw_input")
fn run_raw_input(
  executable: String,
  args: List(String),
  input: BitArray,
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

const marker = "λ 日本語 🧪"

fn fixture_response() -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(7)),
    #("result", json.object([#("text", json.string(marker))])),
  ])
  |> json.to_string
}

/// Child entrypoint: the trusted handler only supplies a fixed response and
/// closes after one frame. It does not authorize or fake a task operation.
pub fn mcp_pipe_fixture_main() {
  mcp.serve(Nil, fn(state, _line) {
    #(state, Some(fixture_response()), True)
  })
}

pub fn real_serve_loop_emits_unicode_as_utf8_json_over_pipe_test() {
  let root = uos_root()
  let app = root <> "/apps/cepaf_gleam/build"
  let code_paths =
    "filelib:wildcard(\"" <> app <> "/dev/erlang/*/ebin\") ++ " <>
    "filelib:wildcard(\"" <> app <> "/test/erlang/*/ebin\") ++ code:get_path()"
  let eval =
    "code:add_paths(" <> code_paths <> "), " <>
    "harness_stdio_pipe_test:mcp_pipe_fixture_main(), halt(0)."
  let input =
    bit_array.from_string(
      "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"test\"}\n",
    )
  let assert Ok(#(0, output)) = run_raw_input(
    root <> "/toolchains/nix-profile/bin/erl",
    ["+S", "2:2", "+A", "2", "-noinput", "-noshell", "-eval", eval],
    input,
    10_000,
  )
  let assert Ok(raw) = bit_array.to_string(output)
  let assert Ok(_) = json.parse(raw, value.decoder())
  raw |> should.equal(fixture_response() <> "\n")
}
