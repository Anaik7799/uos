// ==============================================================================
// [UOS-OMNI-TEST] Omni-Fractal Matrix & 17-Aspect Generation EUnit Test Suite
// ==============================================================================

import cepaf_gleam/verification/omni_fractal_matrix_engine.{
  L0Constitutional, L9BiosemioticRocha, SdlcAddDesign, SdlcAuditLedger,
  canonical_10_fractal_layers, canonical_10_sdlc_stages,
  canonical_14_superpowers, canonical_5_system_components,
  canonical_fast_ooda_cycle, canonical_mcp_ecosystem, canonical_skill_inventory,
  canonical_symbiosis_topology, evaluate_formal_aspects,
  evaluate_scalability_and_performance, execute_all_17_aspect_processes,
  generate_all_17_aspect_processes, generate_all_agent_specifications,
  generate_all_feature_families, generate_all_formal_aspects,
  generate_all_use_cases, generate_system_scalability_matrix, is_fast_ooda_safe,
  verify_omni_fractal_system_matrix, encode_omni_matrix_json,
  generate_all_15_evolutionary_cycles, execute_evolutionary_cycle,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn canonical_10_fractal_layers_test() {
  let layers = canonical_10_fractal_layers()
  list.length(layers) |> should.equal(10)

  let assert Ok(first) = list.first(layers)
  first |> should.equal(L0Constitutional)

  let assert Ok(last) = list.last(layers)
  last |> should.equal(L9BiosemioticRocha)
}

pub fn fast_ooda_cycle_safety_test() {
  let ooda = canonical_fast_ooda_cycle()
  is_fast_ooda_safe(ooda) |> should.be_true()

  // High latency OODA violation (>100ms)
  let bad_latency =
    omni_fractal_matrix_engine.FastOodaCycle(
      observation_latency_ms: 150,
      sensor_count: ooda.sensor_count,
      orientation_entropy_bits: ooda.orientation_entropy_bits,
      orientation_lyapunov: ooda.orientation_lyapunov,
      decision_consensus_ratio: ooda.decision_consensus_ratio,
      decision_ratified: ooda.decision_ratified,
      action_dispatch_status: ooda.action_dispatch_status,
      action_duration_ms: ooda.action_duration_ms,
    )
  is_fast_ooda_safe(bad_latency) |> should.be_false()

  // Unstable positive Lyapunov drift violation
  let bad_lyapunov =
    omni_fractal_matrix_engine.FastOodaCycle(
      observation_latency_ms: ooda.observation_latency_ms,
      sensor_count: ooda.sensor_count,
      orientation_entropy_bits: ooda.orientation_entropy_bits,
      orientation_lyapunov: 0.45,
      decision_consensus_ratio: ooda.decision_consensus_ratio,
      decision_ratified: ooda.decision_ratified,
      action_dispatch_status: ooda.action_dispatch_status,
      action_duration_ms: ooda.action_duration_ms,
    )
  is_fast_ooda_safe(bad_lyapunov) |> should.be_false()
}

pub fn canonical_10_sdlc_stages_test() {
  let stages = canonical_10_sdlc_stages()
  list.length(stages) |> should.equal(10)

  let assert Ok(first) = list.first(stages)
  first |> should.equal(SdlcAddDesign)

  let assert Ok(last) = list.last(stages)
  last |> should.equal(SdlcAuditLedger)
}

pub fn skill_inventory_test() {
  let skills = canonical_skill_inventory()
  skills.total_skills |> should.equal(170)
  skills.active_skills |> should.equal(170)
  skills.verified_skills |> should.equal(170)
  list.length(skills.governing_authorities) |> should.equal(3)
}

pub fn canonical_14_superpowers_test() {
  let powers = canonical_14_superpowers()
  list.length(powers) |> should.equal(14)

  let all_active = list.all(powers, fn(p) { p.active })
  all_active |> should.be_true()

  let assert Ok(first) = list.first(powers)
  first.id |> should.equal("SP-01")
  first.formal_gate |> should.equal("G-TDD-EUNIT")
}

pub fn mcp_tooling_ecosystem_test() {
  let mcp = canonical_mcp_ecosystem()
  let has_enough = mcp.total_tools >= 35
  has_enough |> should.be_true()

  mcp.moz_transport_active |> should.be_true()
  mcp.zero_trust_interceptor_active |> should.be_true()
}

pub fn agentic_symbiosis_topology_test() {
  let sym = canonical_symbiosis_topology()
  sym.single_instance_singletons |> should.equal(71)
  sym.multi_instance_elastic_workers |> should.equal(195)
  sym.total_actors |> should.equal(266)
  sym.unconstrained_elastic_scaling |> should.be_true()
  sym.tri_sovereignty_ratified |> should.be_true()
}

pub fn all_17_aspect_processes_test() {
  let aspects = generate_all_17_aspect_processes()
  list.length(aspects) |> should.equal(17)

  let all_verified = list.all(aspects, fn(a) { a.verified })
  all_verified |> should.be_true()

  let assert Ok(first) = list.first(aspects)
  first.step_id |> should.equal(1)
  first.pillar |> should.equal("SRE")

  let assert Ok(last) = list.last(aspects)
  last.step_id |> should.equal(17)
  last.pillar |> should.equal("Execution")
}

pub fn all_use_cases_test() {
  let ucs = generate_all_use_cases()
  list.length(ucs) |> should.equal(10)

  let all_operational =
    list.all(ucs, fn(u) { u.status == "Operational" && u.deterministic })
  all_operational |> should.be_true()
}

pub fn scalability_and_performance_test() {
  let eval = evaluate_scalability_and_performance()
  eval.all_math_gates_passed |> should.be_true()
  eval.unconstrained_beam_scaling |> should.be_true()

  let entropy_ok = eval.shannon_entropy_bits >=. 2.5
  entropy_ok |> should.be_true()

  let ccm_ok = eval.cyclomatic_complexity_ratio >=. 0.90
  ccm_ok |> should.be_true()

  let div_ok = eval.expected_vs_actual_divergence <=. 0.10
  div_ok |> should.be_true()

  let itqs_ok = eval.integrated_test_quality_score >=. 0.85
  itqs_ok |> should.be_true()
}

pub fn formal_aspects_test() {
  let formal = evaluate_formal_aspects()
  formal.lean4_conservation_proved |> should.be_true()
  formal.lean4_stm_lease_proved |> should.be_true()
  formal.quint_parity_frontier_proved |> should.be_true()
  formal.gospel_contracts_verified |> should.be_true()
  formal.pure_erlang_graphene_verified |> should.be_true()
  formal.nvme_storage_locked |> should.be_true()
}

pub fn master_matrix_verification_predicate_test() {
  verify_omni_fractal_system_matrix() |> should.be_true()
}

pub fn system_components_test() {
  let comps = canonical_5_system_components()
  list.length(comps) |> should.equal(5)

  let all_zero_muda = list.all(comps, fn(c) { c.zero_muda })
  all_zero_muda |> should.be_true()

  let assert Ok(first) = list.first(comps)
  first.name |> should.equal("uos_sup")
  first.throughput_ops_per_sec |> should.equal(50_000)
}

pub fn agent_specifications_test() {
  let agts = generate_all_agent_specifications()
  list.length(agts) |> should.equal(10)

  let assert Ok(first) = list.first(agts)
  first.id |> should.equal("AGT-L0")
  first.is_singleton |> should.be_true()

  let assert Ok(last) = list.last(agts)
  last.id |> should.equal("AGT-L9")
  last.surface |> should.equal("LustreWeb")
}

pub fn feature_families_test() {
  let families = generate_all_feature_families()
  list.length(families) |> should.equal(18)

  let assert Ok(first) = list.first(families)
  first.family_id |> should.equal("FAM-01")

  let assert Ok(last) = list.last(families)
  last.family_id |> should.equal("FAM-18")
  last.test_count |> should.equal(38)
}

pub fn aspect_processes_execution_receipts_test() {
  let receipts = execute_all_17_aspect_processes()
  list.length(receipts) |> should.equal(17)

  let all_verified = list.all(receipts, fn(r) { r.status == "VERIFIED" })
  all_verified |> should.be_true()

  let assert Ok(first) = list.first(receipts)
  first.step_id |> should.equal(1)
  first.proof_digest |> should.equal("SHA256:DRIVE-NVME-25503L801736-LOCKED")
}

pub fn system_scalability_matrix_test() {
  let profiles = generate_system_scalability_matrix()
  list.length(profiles) |> should.equal(5)

  let all_stable = list.all(profiles, fn(p) { p.lyapunov_stable })
  all_stable |> should.be_true()

  let assert Ok(first) = list.first(profiles)
  first.max_concurrency |> should.equal(100_000)
}

pub fn formal_aspect_proofs_test() {
  let proofs = generate_all_formal_aspects()
  list.length(proofs) |> should.equal(7)

  let all_verified = list.all(proofs, fn(p) { p.verified })
  all_verified |> should.be_true()

  let assert Ok(first) = list.first(proofs)
  first.authority |> should.equal("Lean 4")
}

pub fn encode_omni_matrix_json_test() {
  let json_str = encode_omni_matrix_json()
  string.contains(json_str, "\"status\":\"ok\"") |> should.be_true()
  string.contains(json_str, "\"contract\":\"SC-OMNI-FRACTAL-001\"") |> should.be_true()
  string.contains(json_str, "\"ev_cycle\":\"EV-24..EV-39\"") |> should.be_true()
  string.contains(json_str, "\"cartesian_closure\":true") |> should.be_true()
  string.contains(json_str, "\"components_count\":5") |> should.be_true()
  string.contains(json_str, "\"agents_count\":10") |> should.be_true()
  string.contains(json_str, "\"feature_families_count\":18") |> should.be_true()
  string.contains(json_str, "\"aspect_processes_count\":17") |> should.be_true()
  string.contains(json_str, "\"scalability_profiles_count\":5") |> should.be_true()
  string.contains(json_str, "\"formal_proofs_count\":7") |> should.be_true()
  string.contains(json_str, "\"evolutionary_cycles_count\":15") |> should.be_true()
}

pub fn all_15_evolutionary_cycles_test() {
  let cycles = generate_all_15_evolutionary_cycles()
  list.length(cycles) |> should.equal(15)

  let assert Ok(first) = list.first(cycles)
  first.cycle_id |> should.equal("EV-25")
  first.status |> should.equal("OPERATIONAL")
  first.verified |> should.be_true()

  let assert Ok(last) = list.last(cycles)
  last.cycle_id |> should.equal("EV-39")
  last.status |> should.equal("OPERATIONAL")
  last.verified |> should.be_true()
}

pub fn execute_evolutionary_cycles_test() {
  let cycles = generate_all_15_evolutionary_cycles()
  let all_passed = list.all(cycles, execute_evolutionary_cycle)
  all_passed |> should.be_true()
}
