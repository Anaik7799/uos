//// =============================================================================
//// [C3I-SIL6-ASPECT-AGENTS-TEST] ASPECT AGENT ECOSYSTEM VERIFICATION TEST
//// =============================================================================

import cepaf_gleam/sdlc/aspect_agent_ecosystem.{
  encode_aspect_coverage_json, encode_aspect_features_json,
  get_all_aspect_feature_details, get_all_features, get_all_fractal_aspects,
  get_aspect_coverage, get_aspect_features, get_aspect_squad_agents,
  get_total_aspect_squad_agents, lookup_aspect_by_agent,
  lookup_aspect_by_feature, verify_all_features_covered,
  verify_full_aspect_coverage,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn all_14_aspects_mapped_test() {
  let aspects = get_all_fractal_aspects()
  list.length(aspects) |> should.equal(14)

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

pub fn exact_256_agents_deployed_test() {
  get_total_aspect_squad_agents()
  |> should.equal(256)
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
  string.contains(json_str, "\"total_aspects\":14") |> should.be_true
  string.contains(json_str, "\"total_agents_deployed\":256") |> should.be_true
  string.contains(json_str, "\"full_coverage_verified\":true") |> should.be_true
}

pub fn all_104_features_mapped_test() {
  let features = get_all_features()
  list.length(features) |> should.equal(104)

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
}

pub fn aspect_features_json_encoding_test() {
  let details = get_all_aspect_feature_details()
  let json_str = encode_aspect_features_json(details)

  string.contains(json_str, "\"status\":\"ok\"") |> should.be_true
  string.contains(json_str, "\"total_aspects\":14") |> should.be_true
  string.contains(json_str, "\"total_features\":104") |> should.be_true
  string.contains(json_str, "\"total_agents_deployed\":256") |> should.be_true
  string.contains(json_str, "\"all_features_covered\":true") |> should.be_true
}
