import gleam/erlang/charlist.{type Charlist}
import gleam/json
import gleeunit/should
import hermes_harness/parity_algebra_test
import ocaml_counterparts/native

@external(erlang, "init", "get_plain_arguments")
fn arguments() -> List(Charlist)

// Executes the same scale assertions as chaos_test against an isolated adapter.
pub fn main() {
  let assert [path] = arguments()
  parity_algebra_test.chaos_with_report(fn(required, verdicts) {
    native.request_with(
      charlist.to_string(path),
      [],
      "report",
      json.object([
        #("required", json.bool(required)),
        #("verdicts", json.array(verdicts, json.string)),
      ]),
      30_000,
    )
    |> should.be_ok
  })
}
