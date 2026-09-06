import gleam/list
import gleam/string
import gleeunit/should
import uos_tui/ontology

pub fn graph_validates_test() {
  ontology.validate(ontology.graph()) |> should.equal(Ok(Nil))
}

pub fn every_layer_l0_to_l8_populated_test() {
  let g = ontology.graph()
  list.each(
    [
      ontology.L0Constitutional,
      ontology.L1Atomic,
      ontology.L2Component,
      ontology.L3Transaction,
      ontology.L4System,
      ontology.L5Cognitive,
      ontology.L6Ecosystem,
      ontology.L7Federation,
      ontology.L8Evolution,
    ],
    fn(l) { { list.length(ontology.by_layer(g, l)) >= 1 } |> should.be_true },
  )
}

pub fn fidelity_ladder_counts_test() {
  let #(iso, homo, re, deferred) = ontology.fidelity_counts(ontology.graph())
  { iso + homo + re + deferred }
  |> should.equal(list.length(ontology.concepts()))
  { deferred <= 3 } |> should.be_true
}

pub fn markdown_has_one_row_per_concept_test() {
  let md = ontology.to_markdown(ontology.graph())
  md
  |> string.split("\n")
  |> list.length
  |> should.equal(list.length(ontology.concepts()) + 2)
  string.contains(md, "#fractal-l0") |> should.be_true
}

pub fn dangling_edge_detected_test() {
  let g =
    ontology.Graph(ontology.concepts(), [
      ontology.Edge("App", "Nope", ontology.Composes),
    ])
  ontology.validate(g) |> should.equal(Error("dangling edge App -> Nope"))
}
