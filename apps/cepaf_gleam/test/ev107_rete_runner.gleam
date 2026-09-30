import gleam/erlang/atom.{type Atom}
import gleam/io
import gleeunit/should

@external(erlang, "eunit", "test")
fn test_modules(modules: List(Atom), options: List(Atom)) -> Atom

pub fn main() {
  test_modules(
    [
      atom.create("rete_ul_verifier_test"),
      atom.create("ev107_rete_closure_test"),
    ],
    [atom.create("verbose")],
  )
  |> atom.to_string
  |> should.equal("ok")
  io.println("PASS EV107 bounded forward chaining; admission NOT_GRANTED")
}
