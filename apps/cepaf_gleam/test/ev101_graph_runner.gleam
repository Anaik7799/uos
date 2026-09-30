import gleam/erlang/atom.{type Atom}
import gleam/io
import gleeunit/should

@external(erlang, "eunit", "test")
fn test_modules(modules: List(Atom), options: List(Atom)) -> Atom

pub fn main() {
  test_modules(
    [
      atom.create("sheaf_engine_test"),
      atom.create("ev101_graph_integrity_test"),
    ],
    [atom.create("verbose")],
  )
  |> atom.to_string
  |> should.equal("ok")
  io.println("PASS EV101 bounded graph component; admission NOT_GRANTED")
}
