import gleam/erlang/atom.{type Atom}
import gleam/io
import gleeunit/should

@external(erlang, "eunit", "test")
fn test_module(module: Atom, options: List(Atom)) -> Atom

pub fn main() {
  test_module(atom.create("mesh_zenoh_test"), [atom.create("verbose")])
  |> atom.to_string
  |> should.equal("ok")
  io.println("PASS production_transport_test_discovery")
}
