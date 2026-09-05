import gleam/dynamic/decode
import gleam/erlang/charlist.{type Charlist}
import gleam/json
import gleeunit/should
import ocaml_counterparts/native

@external(erlang, "init", "get_plain_arguments")
fn arguments() -> List(Charlist)

// Run with: gleam run -m mutation_probe -- /absolute/path/to/isolated/adapter
// The normal adapter has no mutation flag and the original source is untouched.
pub fn main() {
  let assert [path] = arguments()
  let value =
    native.request_with(
      charlist.to_string(path),
      [],
      "report",
      json.object([
        #("required", json.bool(True)),
        #("verdicts", json.array([], json.string)),
      ]),
      30_000,
    )
    |> should.be_ok
  value
  |> decode.run(decode.field("rolled", decode.string, decode.success))
  |> should.equal(Ok("unmapped"))
}
