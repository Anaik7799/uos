//// =============================================================================
//// [C3I-SIL6-ASPECT-AGENTS-TEST] ASPECT AGENT ECOSYSTEM VERIFICATION TEST
//// =============================================================================

import cepaf_gleam/sdlc/aspect_agent_ecosystem.{
  agent_limit_enforced, count_multi_instance_agents,
  count_single_instance_agents, encode_agent_instances_json,
  encode_aspect_coverage_json, encode_aspect_features_json,
  get_all_agent_descriptors, get_all_aspect_feature_details, get_all_features,
  get_all_fractal_aspects, get_aspect_coverage, get_aspect_features,
  get_aspect_squad_agents, get_multi_instance_agents,
  get_single_instance_agents, get_total_aspect_squad_agents,
  is_elastic_swarm_unbounded, lookup_aspect_by_agent, lookup_aspect_by_feature,
  verify_all_features_covered, verify_full_aspect_coverage,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn all_17_aspects_mapped_test() {
  let aspects = get_all_fractal_aspects()
  list.length(aspects) |> should.equal(17)

  list.each(aspects, fn(a) {
    let cov = get_aspect_coverage(a)
    cov.name |> should.not_equal("")
    cov.pillar |> should.not_equal("")
    cov.primary_agent_kind |> should.not_equal("")
    { cov.squad_size > 0 } |> should.be_true
    cov.governing_contract |> should.not_equal("")
    cov.formal_verification_method |> should.not_equal("")
  })
}

pub fn unconstrained_elastic_swarm_test() {
  // 256 agent limit is explicitly removed from system
  agent_limit_enforced() |> should.be_false
  is_elastic_swarm_unbounded() |> should.be_true
  { get_total_aspect_squad_agents() >= 17 } |> should.be_true
}

pub fn single_vs_multi_instance_classification_test() {
  let singletons = get_single_instance_agents()
  let multi = get_multi_instance_agents()
  let all_descriptors = get_all_agent_descriptors()

  list.length(all_descriptors) |> should.equal(get_total_aspect_squad_agents())
  { list.length(singletons) + list.length(multi) }
  |> should.equal(list.length(all_descriptors))

  // Verify single-instance count
  let single_count = count_single_instance_agents()
  let multi_count = count_multi_instance_agents()
  single_count |> should.equal(list.length(singletons))
  multi_count |> should.equal(list.length(multi))

  { single_count > 0 } |> should.be_true
  { multi_count > 0 } |> should.be_true

  // Verify that all singletons have is_singleton == True
  list.each(singletons, fn(d) { d.is_singleton |> should.be_true })

  // Verify that all multi-instance have is_singleton == False
  list.each(multi, fn(d) { d.is_singleton |> should.be_false })
}

pub fn full_coverage_verification_test() {
  verify_full_aspect_coverage()
  |> should.be_true
}

pub fn pillar_representation_test() {
  let aspects = get_all_fractal_aspects()
  let pillars =
    list.map(aspects, fn(a) { get_aspect_coverage(a).pillar })
    |> list.unique

  list.contains(pillars, "C3I-SDLC") |> should.be_true
  list.contains(pillars, "C3I-SRE") |> should.be_true
  list.contains(pillars, "C3I-VERIFICATION") |> should.be_true
  list.contains(pillars, "C3I-INTELLIGENCE") |> should.be_true
  list.length(pillars) |> should.equal(4)
}

pub fn aspect_json_encoding_test() {
  let aspects = list.map(get_all_fractal_aspects(), get_aspect_coverage)
  let json_str = encode_aspect_coverage_json(aspects)

  string.contains(json_str, "\"status\":\"ok\"") |> should.be_true
  string.contains(json_str, "\"total_aspects\":17") |> should.be_true
  string.contains(json_str, "\"baseline_agents\":256") |> should.be_true
  string.contains(json_str, "\"agent_limit_enforced\":false") |> should.be_true
  string.contains(json_str, "\"full_coverage_verified\":true") |> should.be_true
}

pub fn all_120_features_mapped_test() {
  let features = get_all_features()
  list.length(features) |> should.equal(120)

  let aspects = get_all_fractal_aspects()
  list.each(aspects, fn(a) {
    let f = get_aspect_features(a)
    { f != [] } |> should.be_true
    let squad = get_aspect_squad_agents(a)
    let cov = get_aspect_coverage(a)
    list.length(squad) |> should.equal(cov.squad_size)
  })
}

pub fn all_features_covered_verification_test() {
  verify_all_features_covered()
  |> should.be_true
}

pub fn lookup_by_feature_and_agent_test() {
  let res1 = lookup_aspect_by_feature("F01_COMPONENT_SPEC")
  case res1 {
    Ok(d) -> d.aspect_name |> should.equal("11-Field Reusable Component Packet")
    Error(_) -> should.fail()
  }

  let res2 = lookup_aspect_by_agent("VerifCc4StorageSafetyAuditor")
  case res2 {
    Ok(d) ->
      d.aspect_name
      |> should.equal("Six Fractal Completeness Criteria (CC1-CC6)")
    Error(_) -> should.fail()
  }

  let res3 = lookup_aspect_by_feature("F105_DOC_MANDATORY_TIMESTAMP")
  case res3 {
    Ok(d) ->
      d.aspect_name
      |> should.equal(
        "Documentation Lattice, Wiki AST & Living ZK Knowledge Base",
      )
    Error(_) -> should.fail()
  }

  let res4 = lookup_aspect_by_feature("F111_ZENOH_NIF_BINDING")
  case res4 {
    Ok(d) ->
      d.aspect_name
      |> should.equal(
        "Zenoh Native NIF Distributed Pub/Sub Mesh & ZMOF Backplane",
      )
    Error(_) -> should.fail()
  }

  let res5 = lookup_aspect_by_feature("F116_RETE_UL_NIF_ENGINE")
  case res5 {
    Ok(d) ->
      d.aspect_name
      |> should.equal(
        "RETE-UL Cognitive Rule Engine & Forward-Chaining Inference",
      )
    Error(_) -> should.fail()
  }

  let res6 = lookup_aspect_by_agent("IntelReteUlSupervisor")
  case res6 {
    Ok(d) ->
      d.aspect_name
      |> should.equal(
        "RETE-UL Cognitive Rule Engine & Forward-Chaining Inference",
      )
    Error(_) -> should.fail()
  }
}

pub fn aspect_features_json_encoding_test() {
  let details = get_all_aspect_feature_details()
  let json_str = encode_aspect_features_json(details)

  string.contains(json_str, "\"status\":\"ok\"") |> should.be_true
  string.contains(json_str, "\"total_aspects\":17") |> should.be_true
  string.contains(json_str, "\"total_features\":120") |> should.be_true
  string.contains(json_str, "\"baseline_agents\":256") |> should.be_true
  string.contains(json_str, "\"agent_limit_enforced\":false") |> should.be_true
  string.contains(json_str, "\"all_features_covered\":true") |> should.be_true
}

pub fn agent_instances_json_encoding_test() {
  let json_str = encode_agent_instances_json()

  string.contains(json_str, "\"status\":\"ok\"") |> should.be_true
  string.contains(json_str, "\"agent_limit_enforced\":false") |> should.be_true
  string.contains(json_str, "\"swarm_model\":\"UNCONSTRAINED_ELASTIC_BEAM_SWARM\"")
  |> should.be_true
  string.contains(json_str, "\"total_single_instance_agents\"")
  |> should.be_true
  string.contains(json_str, "\"total_multi_instance_agents\"") |> should.be_true
  string.contains(json_str, "\"single_instance_agents\"") |> should.be_true
  string.contains(json_str, "\"multi_instance_agents\"") |> should.be_true
}
