import cepaf_gleam/verification/web_quality_contract as q
import gleam/int
import gleam/io
import gleam/list
import gleeunit/should

pub fn layer_bounds_test() {
  q.layer(-1) |> should.be_error
  q.layer(0) |> should.be_ok
  q.layer(9) |> should.be_ok
  q.layer(10) |> should.be_error
}

pub fn evidence_fail_closed_test() {
  q.admit(q.Passed, q.Unrun) |> should.be_false
  q.admit(q.Unrun, q.Passed) |> should.be_false
  q.admit(q.Failed, q.Passed) |> should.be_false
  q.admit(q.Passed, q.Passed) |> should.be_true
}

pub fn rollup_semilattice_test() {
  let states = [q.Passed, q.Unrun, q.Failed]
  list.each(states, fn(a) {
    q.join(a, a) |> should.equal(a)
    q.join(a, q.Passed) |> should.equal(a)
    list.each(states, fn(b) {
      q.join(a, b) |> should.equal(q.join(b, a))
      list.each(states, fn(c) {
        q.join(q.join(a, b), c) |> should.equal(q.join(a, q.join(b, c)))
      })
    })
  })
  q.rollup([]) |> should.equal(q.Unrun)
  q.rollup([q.Passed, q.Failed]) |> should.equal(q.Failed)
}

pub fn route_boundary_fuzz_test() {
  list.each(
    [
      "",
      "//evil.invalid",
      "/../key",
      "/%2e%2e/x",
      "/x?exec=1",
      "/x#y",
      "https://evil.invalid",
    ],
    fn(path) { q.route(path) |> should.be_error },
  )
  // Reproducible generated valid paths plus two distinct hostile mutations.
  int.range(from: 0, to: 1000, with: Nil, run: fn(_, seed) {
    let path = "/docs/note-" <> int.to_string(seed)
    let assert Ok(route) = q.route(path)
    q.route_path(route) |> should.equal(path)
    q.route("/../" <> path) |> should.be_error
    q.route(path <> "?redirect=//evil.invalid") |> should.be_error
  })
}

pub fn four_cycle_evidence_test() {
  q.complete_cycles([1, 2, 3, 4]) |> should.be_true
  q.complete_cycles([1, 1, 2, 3]) |> should.be_false
  q.complete_cycles([1, 2, 4]) |> should.be_false
  q.complete_cycles([]) |> should.be_false
}

pub fn graph_return_paths_test() {
  q.strongly_connected(3, [#(0, 1), #(1, 2), #(2, 0)]) |> should.be_true
  q.strongly_connected(3, [#(0, 1), #(1, 2)]) |> should.be_false
  q.strongly_connected(0, []) |> should.be_false
  q.strongly_connected(3, [#(0, 3)]) |> should.be_false
}

pub fn denotation_composition_test() {
  let a = [q.Open(1), q.Open(2)]
  let b = [q.Back, q.Open(3)]
  let start = q.Navigation(current: 0, history: [])
  q.denote(list.append(a, b), start)
  |> should.equal(q.denote(b, q.denote(a, start)))
  q.denote([], start) |> should.equal(start)
  // Distinct mutants: dropping history and reversing composition must differ.
  q.denote([q.Open(1), q.Back], start) |> should.equal(start)
  q.denote(list.append(b, a), start)
  |> should.not_equal(q.denote(list.append(a, b), start))
}

pub fn given_wiki_link_when_opened_then_back_returns_test() {
  let start = q.Navigation(2, [0])
  q.denote([q.Open(8), q.Back], start) |> should.equal(start)
}

pub fn all_thirteen_coordinates_conserved_test() {
  let assert Ok(layer) = q.layer(4)
  let before =
    q.Trace(
      layer,
      "page",
      "wiki",
      "origin",
      "target",
      7,
      "operator",
      "mapped",
      "digest",
      0,
      0,
      8,
      "unrun",
    )
  q.conserves(before, before) |> should.be_true
  let mutants = [
    q.Trace(..before, fractal: "component"),
    q.Trace(..before, domain: "km"),
    q.Trace(..before, origin: "different"),
    q.Trace(..before, target: "different"),
    q.Trace(..before, epoch: 8),
    q.Trace(..before, authority: "other"),
    q.Trace(..before, status: "passed"),
    q.Trace(..before, digest: "altered"),
    q.Trace(..before, trust: 1),
    q.Trace(..before, drift_us: 1),
    q.Trace(..before, entropy_millibits: 9),
    q.Trace(..before, parity: "passed"),
  ]
  list.each(mutants, fn(after) { q.conserves(before, after) |> should.be_false })
  let assert Ok(other_layer) = q.layer(5)
  q.conserves(before, q.Trace(..before, layer: other_layer)) |> should.be_false
}

pub fn main() {
  layer_bounds_test()
  evidence_fail_closed_test()
  rollup_semilattice_test()
  route_boundary_fuzz_test()
  four_cycle_evidence_test()
  graph_return_paths_test()
  denotation_composition_test()
  given_wiki_link_when_opened_then_back_returns_test()
  all_thirteen_coordinates_conserved_test()
  io.println(
    "web_quality_contract: 9 test functions passed; 1000 generated route seeds",
  )
}
