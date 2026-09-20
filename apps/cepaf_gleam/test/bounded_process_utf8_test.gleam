import gleam/bit_array
import gleam/list
import gleeunit/should

@external(erlang, "ecology_capability_ffi", "run_bounded")
fn run(
  path: String,
  args: List(String),
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

@external(erlang, "ecology_capability_ffi", "run_bounded")
fn run_bytes(
  path: BitArray,
  args: List(BitArray),
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

const printf = "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/printf"

pub fn bounded_argv_preserves_unicode_without_normalization_test() {
  list.each(
    ["plain ASCII", "operator — policy", "漢字 € 😀", "é", "e\u{301}"],
    fn(input) {
      let assert Ok(#(0, output)) = run(printf, ["%s", input], 3000)
      output |> should.equal(bit_array.from_string(input))
    },
  )
}

pub fn argv_boundaries_quotes_newlines_and_shell_text_are_literal_test() {
  let first = "— \"quote\"\n$(printf SHOULD_NOT_RUN)"
  let second = "漢字; | &"
  let assert Ok(#(0, output)) = run(printf, ["[%s][%s]", first, second], 3000)
  output
  |> should.equal(bit_array.from_string("[" <> first <> "][" <> second <> "]"))
}

pub fn malformed_utf8_is_refused_before_starting_child_test() {
  list.each([<<255>>, <<226, 128>>], fn(invalid) {
    run_bytes(
      bit_array.from_string(printf),
      [bit_array.from_string("%s"), invalid],
      3000,
    )
    |> should.equal(Error("backend_spawn_failed"))
    run_bytes(invalid, [], 3000) |> should.equal(Error("backend_spawn_failed"))
  })
}

pub fn embedded_nul_and_invalid_deadline_stay_refused_test() {
  run(printf, ["%s", "before\u{0}after"], 3000) |> should.be_error
  run(printf, ["%s", "—"], 0) |> should.equal(Error("invalid_resource_bound"))
  run(printf, ["%s", "—"], 60_001)
  |> should.equal(Error("invalid_resource_bound"))
}
