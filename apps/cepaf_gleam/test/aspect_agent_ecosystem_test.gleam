//// =============================================================================
//// [C3I-SIL6-ASPECT-AGENTS-TEST] ASPECT AGENT ECOSYSTEM VERIFICATION TEST
//// =============================================================================

import gleeunit/should
import gleam/list
import gleam/string
import cepaf_gleam/sdlc/aspect_agent_ecosystem.{
  get_all_fractal_aspects,
  get_aspect_coverage,
  get_total_aspect_squad_agents,
  verify_full_aspect_coverage,
  encode_aspect_coverage_json,
}

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
