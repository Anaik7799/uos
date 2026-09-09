//// Fixed test manifest invoked by the Gleam development harness.

import gleam/erlang/atom
import gleam/io
import gleam/list

type Option {
  Verbose
}

@external(erlang, "eunit", "test")
fn eunit(modules: List(atom.Atom), options: List(Option)) -> atom.Atom

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

pub fn main() {
  let modules = [
    "harness_development_test",
    "harness_authority_test",
    "harness_tracking_test",
    "harness_sa_plan_boundary_test",
    "mcp_runtime_truth_test",
  ]
  let result =
    eunit(list.map(modules, atom.create), [Verbose]) |> atom.to_string
  io.println("harness verification: " <> result)
  case result {
    "ok" -> Nil
    _ -> halt(1)
  }
}
