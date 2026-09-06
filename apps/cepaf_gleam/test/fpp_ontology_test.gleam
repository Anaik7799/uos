//// =============================================================================
//// [UOS-FPP-ONTOLOGY-TEST] NASA JPL F Prime Living Ontology Test Suite
//// =============================================================================
//// Formally tests the F Prime living ontology derivation & closure laws:
//// 1. Automated ontology derivation from canonical FPP topology
//// 2. Topological closure & referential integrity (zero dangling edges)
//// 3. Biomorphic presence tracking across nodes and edges
//// 4. JSON serialization conforming to UOS ontology schema
//// =============================================================================

import cepaf_gleam/fpp/ontology.{
  OntoComponentDef, OntoInstance, derive_fpp_ontology, ontology_to_json,
  verify_ontology_closure,
}
import cepaf_gleam/fpp/topology.{canonical_harness_model}
import gleam/list
import gleam/string
import gleeunit/should

pub fn fpp_ontology_derivation_test() {
  let model = canonical_harness_model()
  let graph = derive_fpp_ontology(model)

  // Verify graph topology
  graph.topology_name |> should.equal("HermesHarness")
  graph.schema_version |> should.equal("2026.09.06-SIL6")

  // Must have derived component and instance nodes
  let comp_nodes =
    list.filter(graph.nodes, fn(n) { n.category == OntoComponentDef })
  list.length(comp_nodes) |> should.equal(7)

  let inst_nodes =
    list.filter(graph.nodes, fn(n) { n.category == OntoInstance })
  list.length(inst_nodes) |> should.equal(7)

  // Total nodes must be comprehensive (components + details + instances + SM + subtopo + pkts)
  let total_nodes = list.length(graph.nodes)
  { total_nodes >= 30 } |> should.be_true

  // Edges must be derived
  let total_edges = list.length(graph.edges)
  { total_edges >= 20 } |> should.be_true
}

pub fn fpp_ontology_topological_closure_test() {
  let model = canonical_harness_model()
  let graph = derive_fpp_ontology(model)

  // Law of Topological Closure: every edge endpoint must resolve to a valid node in the graph
  let closure_res = verify_ontology_closure(graph)
  closure_res |> should.be_ok

  let assert Ok(valid_nodes) = closure_res
  valid_nodes |> should.equal(list.length(graph.nodes))
}

pub fn fpp_ontology_json_serialization_test() {
  let model = canonical_harness_model()
  let graph = derive_fpp_ontology(model)
  let json_str = ontology_to_json(graph)

  json_str |> string.contains("\"schema_version\":\"2026.09.06-SIL6\"") |> should.be_true
  json_str |> string.contains("\"topology_name\":\"HermesHarness\"") |> should.be_true
  json_str |> string.contains("\"node_count\":") |> should.be_true
  json_str |> string.contains("\"edge_count\":") |> should.be_true
  json_str |> string.contains("comp:evidence_store") |> should.be_true
  json_str |> string.contains("inst:evidence_store") |> should.be_true
}
