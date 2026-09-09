import gleam/erlang/atom.{type Atom}
import gleam/io
import gleeunit/should

@external(erlang, "eunit", "test")
fn test_modules(tests: #(Atom, List(Atom)), options: List(Atom)) -> Atom

pub fn main() {
  test_modules(
    #(
      atom.create("inparallel"),
      [
        atom.create("sheaf_engine_test"),
        atom.create("ev101_graph_integrity_test"),
        atom.create("rete_ul_verifier_test"),
        atom.create("ev107_rete_closure_test"),
        atom.create("ooda_shruti_copilot_test"),
      ],
    ),
    [atom.create("verbose")],
  )
  |> atom.to_string
  |> should.equal("ok")
  io.println("PASS composed graph, Rete and remediation suites; admission NOT_GRANTED")
}
