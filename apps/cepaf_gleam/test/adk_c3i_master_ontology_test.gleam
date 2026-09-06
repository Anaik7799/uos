// ==============================================================================
// Unified Operational System (UOS) - Master Ontology Engine Test Suite
//
// Verifies semantic graph connectivity, domain filtering, JSON & GraphML export.
// ==============================================================================

import cepaf_gleam/ontology/adk_c3i_master_ontology.{
  DomainAdkFramework, DomainC3iEcology, DomainFormalInvariants,
  DomainZigvmLifecycle, build_canonical_master_ontology,
  encode_master_ontology_json, export_ontology_graphml, filter_entities_by_domain,
  find_entity_by_id, total_edges_count, total_entities_count,
  verify_master_ontology_integrity,
}
import gleam/list
import gleam/string

pub fn master_ontology_completeness_test() {
  let graph = build_canonical_master_ontology()

  let total_e = total_entities_count(graph)
  let total_edges = total_edges_count(graph)

  let assert True = total_e >= 22
  let assert True = total_edges >= 20
  let assert True = verify_master_ontology_integrity(graph)
}

pub fn master_ontology_domain_distribution_test() {
  let graph = build_canonical_master_ontology()

  let adk_entities = filter_entities_by_domain(graph, DomainAdkFramework)
  let c3i_entities = filter_entities_by_domain(graph, DomainC3iEcology)
  let zigvm_entities = filter_entities_by_domain(graph, DomainZigvmLifecycle)
  let invariant_entities = filter_entities_by_domain(graph, DomainFormalInvariants)

  let assert True = list.length(adk_entities) >= 9
  let assert True = list.length(c3i_entities) == 3
  let assert True = list.length(zigvm_entities) == 6
  let assert True = list.length(invariant_entities) == 4
}

pub fn master_ontology_lookup_test() {
  let graph = build_canonical_master_ontology()

  let assert Ok(hw_lock) = find_entity_by_id(graph, "inv-hardware-storage-lock")
  let assert True = hw_lock.fractal_layer == 0
  let assert True = string.contains(hw_lock.description, "25503L801736")

  let assert Ok(adk_graph) = find_entity_by_id(graph, "adk-workflow-graph")
  let assert True = adk_graph.domain == DomainAdkFramework

  let assert Ok(stg1) = find_entity_by_id(graph, "zigvm-stg1-ontology")
  let assert True = stg1.domain == DomainZigvmLifecycle
}

pub fn master_ontology_serialization_test() {
  let graph = build_canonical_master_ontology()

  let json_str = encode_master_ontology_json(graph)
  let assert True = string.contains(json_str, "2.0.0-UOS-ADK-C3I-CANONICAL")
  let assert True = string.contains(json_str, "Google-ADK-Framework")
  let assert True = string.contains(json_str, "adk-workflow-graph")

  let graphml_str = export_ontology_graphml(graph)
  let assert True = string.contains(graphml_str, "<graphml")
  let assert True = string.contains(graphml_str, "UOS_Master_Ontology")
  let assert True = string.contains(graphml_str, "</graphml>")
}
