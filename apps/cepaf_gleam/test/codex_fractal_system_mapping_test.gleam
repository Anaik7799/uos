//// =============================================================================
//// [C3I-SIL6-CODEX-MAP-TEST] CODEX FRACTAL SYSTEM MAPPING VERIFICATION TEST
//// =============================================================================

import cepaf_gleam/verification/codex_fractal_system_mapping.{
  CompletenessCriteria, ComponentPacket, OodavrState, PhaseAct, PhaseDecide,
  PhaseObserve, PhaseOrient, PhaseRecord, PhaseVerify, ProductionReadiness,
  ResolvedInPureBeam, StateAbsent, StateEq, StateEquiv, StateUntested, StratumA,
  StratumB, StratumC, TierL0MetaOrchestrator, WikiPipelineRecursion,
  advance_oodavr_phase, capability_state_leq, capability_state_meet,
  count_all_subsystems, evaluate_production_readiness,
  evaluate_system_completeness, get_all_code_surface_mappings,
  get_design_lattice_mapping, get_faculty_mapping, get_plane_mapping,
  get_sa_plan_residual_audit, get_stratum_mapping, get_subsystem_mapping,
  get_system_path_flow, get_vertical_mapping, is_oodavr_cycle_closed,
  list_all_design_stages, list_all_faculties, list_all_system_paths,
  list_all_system_planes, list_all_vertical_layers, validate_component_packet,
  verify_stratum_isolation, verify_wiki_pipeline_recursion,
}
import gleam/int
import gleam/list
import gleeunit/should

pub fn component_packet_validation_test() {
  let valid_packet =
    ComponentPacket(
      name: "HermesZeroTrustHook",
      signature: "fn(payload: String) -> Result(DispatchVerdict, SecurityFault)",
      semantic_domain: "Zero-Trust MCP Interception Domain",
      oracle: "Cryptokit SHA-256 Digest Reference",
      final_encoding: "engines/hermes/modules/system_engg/agent_dispatch_hook.ml",
      homomorphism: "denote(Final(payload)) == denote(Oracle(payload))",
      generator: "arbitrary_mcp_tool_calls_with_entropy_seed",
      mutants: ["inject_embedded_nul_byte", "inject_raw_sql_quote"],
      judge: "trap_nul_code_minus_2_and_sql_code_minus_3",
      governor: "fail_closed_policy_authorizer",
      documentation: "contracts/mcp/agent_dispatch_spec.md",
      durable_evidence: "data/sqlite/uos_verification_tracking.sqlite3",
    )
  validate_component_packet(valid_packet)
  |> should.be_true

  let invalid_packet_empty_judge = ComponentPacket(..valid_packet, judge: "")
  validate_component_packet(invalid_packet_empty_judge)
  |> should.be_false

  let invalid_packet_single_mutant =
    ComponentPacket(..valid_packet, mutants: ["only_one_mutant"])
  validate_component_packet(invalid_packet_single_mutant)
  |> should.be_false
}

pub fn vertical_layer_ladder_test() {
  let layers = list_all_vertical_layers()
  list.length(layers)
  |> should.equal(11)

  list.each(layers, fn(layer) {
    let mapping = get_vertical_mapping(layer)
    mapping.layer_name |> should.not_equal("")
    mapping.uos_carrier |> should.not_equal("")
    mapping.closure_evidence |> should.not_equal("")
  })
}

pub fn system_planes_mapping_test() {
  let planes = list_all_system_planes()
  list.length(planes)
  |> should.equal(9)

  list.each(planes, fn(plane) {
    let mapping = get_plane_mapping(plane)
    mapping.plane_name |> should.not_equal("")
    mapping.primary_flow |> should.not_equal("")
    list.is_empty(mapping.uos_subsystems)
    |> should.be_false
  })
}

fn range(start: Int, stop: Int) -> List(Int) {
  case start <= stop {
    True -> [start, ..range(start + 1, stop)]
    False -> []
  }
}

pub fn semantic_strata_isolation_test() {
  let stratum_a = get_stratum_mapping(StratumA)
  let stratum_b = get_stratum_mapping(StratumB)
  let stratum_c = get_stratum_mapping(StratumC)

  stratum_a.stratum_name |> should.not_equal("")
  stratum_b.stratum_name |> should.not_equal("")
  stratum_c.stratum_name |> should.not_equal("")

  // Stratum A laws must never depend on Stratum C behavior
  verify_stratum_isolation(True, True)
  |> should.be_false

  verify_stratum_isolation(True, False)
  |> should.be_true

  verify_stratum_isolation(False, True)
  |> should.be_true
}

pub fn horizontal_subsystems_s1_s33_test() {
  count_all_subsystems()
  |> should.equal(33)

  range(1, 33)
  |> list.each(fn(i) {
    let id = "S" <> int.to_string(i)
    case get_subsystem_mapping(id) {
      Ok(sub) -> {
        sub.id |> should.equal(id)
        sub.name |> should.not_equal("")
        sub.uos_carrier |> should.not_equal("")
      }
      Error(_) -> should.fail()
    }
  })

  get_subsystem_mapping("S34")
  |> should.be_error
}

pub fn code_surface_mappings_test() {
  let surfaces = get_all_code_surface_mappings()
  list.length(surfaces)
  |> should.equal(12)

  list.each(surfaces, fn(s) {
    s.surface_id |> should.not_equal("")
    s.uos_carrier |> should.not_equal("")
    s.verification_proof |> should.not_equal("")
  })
}

pub fn production_readiness_conjunction_test() {
  let all_green =
    ProductionReadiness(
      functional_parity_f: True,
      capability_completeness_c: True,
      operational_honesty_o: True,
      performance_p: True,
      scalability_s: True,
      realtime_behavior_r: True,
    )
  evaluate_production_readiness(all_green)
  |> should.be_true

  // Any single failure fails the conjunction
  evaluate_production_readiness(
    ProductionReadiness(..all_green, functional_parity_f: False),
  )
  |> should.be_false

  evaluate_production_readiness(
    ProductionReadiness(..all_green, capability_completeness_c: False),
  )
  |> should.be_false

  evaluate_production_readiness(
    ProductionReadiness(..all_green, operational_honesty_o: False),
  )
  |> should.be_false

  evaluate_production_readiness(
    ProductionReadiness(..all_green, performance_p: False),
  )
  |> should.be_false

  evaluate_production_readiness(
    ProductionReadiness(..all_green, scalability_s: False),
  )
  |> should.be_false

  evaluate_production_readiness(
    ProductionReadiness(..all_green, realtime_behavior_r: False),
  )
  |> should.be_false
}

pub fn capability_state_poset_test() {
  // ABSENT < UNTESTED < EQUIV < EQ
  capability_state_leq(StateAbsent, StateUntested) |> should.be_true
  capability_state_leq(StateUntested, StateEquiv) |> should.be_true
  capability_state_leq(StateEquiv, StateEq) |> should.be_true

  capability_state_leq(StateEq, StateEquiv) |> should.be_false
  capability_state_leq(StateEquiv, StateUntested) |> should.be_false
  capability_state_leq(StateUntested, StateAbsent) |> should.be_false

  // Meet operator takes the lower state
  capability_state_meet(StateEq, StateUntested)
  |> should.equal(StateUntested)

  capability_state_meet(StateAbsent, StateEquiv)
  |> should.equal(StateAbsent)

  capability_state_meet(StateEquiv, StateEq)
  |> should.equal(StateEquiv)
}

pub fn oodavr_phase_transitions_test() {
  advance_oodavr_phase(PhaseObserve) |> should.equal(PhaseOrient)
  advance_oodavr_phase(PhaseOrient) |> should.equal(PhaseDecide)
  advance_oodavr_phase(PhaseDecide) |> should.equal(PhaseAct)
  advance_oodavr_phase(PhaseAct) |> should.equal(PhaseVerify)
  advance_oodavr_phase(PhaseVerify) |> should.equal(PhaseRecord)
  advance_oodavr_phase(PhaseRecord) |> should.equal(PhaseObserve)

  let closed_state =
    OodavrState(
      cycle_id: "OODAVR-001",
      current_phase: PhaseRecord,
      active_tier: TierL0MetaOrchestrator,
      sa_plan_bound: True,
      gate_passed: True,
      rete_recorded: True,
    )
  is_oodavr_cycle_closed(closed_state)
  |> should.be_true

  let incomplete_state = OodavrState(..closed_state, gate_passed: False)
  is_oodavr_cycle_closed(incomplete_state)
  |> should.be_false
}

pub fn sa_plan_residual_resolution_test() {
  let audit = get_sa_plan_residual_audit()
  audit.status |> should.equal(ResolvedInPureBeam)
  audit.engine_module
  |> should.equal("apps/cepaf_gleam/src/cepaf_gleam/sdlc/sa_plan_engine.gleam")
  audit.test_module
  |> should.equal("apps/cepaf_gleam/test/sa_plan_engine_test.gleam")
}

pub fn system_paths_flow_test() {
  let paths = list_all_system_paths()
  list.length(paths) |> should.equal(7)
  list.each(paths, fn(p) {
    let flow = get_system_path_flow(p)
    flow.name |> should.not_equal("")
    flow.source |> should.not_equal("")
    flow.interface |> should.not_equal("")
    flow.transformation |> should.not_equal("")
    flow.observer |> should.not_equal("")
    flow.governor |> should.not_equal("")
  })
}

pub fn design_lattice_stages_test() {
  let stages = list_all_design_stages()
  list.length(stages) |> should.equal(10)
  list.each(stages, fn(s) {
    let mapping = get_design_lattice_mapping(s)
    mapping.code |> should.not_equal("")
    mapping.name |> should.not_equal("")
    mapping.primary_activity |> should.not_equal("")
  })
}

pub fn ontology_faculties_test() {
  let faculties = list_all_faculties()
  list.length(faculties) |> should.equal(10)
  list.each(faculties, fn(f) {
    let mapping = get_faculty_mapping(f)
    mapping.name |> should.not_equal("")
    mapping.uos_carrier |> should.not_equal("")
  })
}

pub fn system_completeness_criteria_test() {
  let complete =
    CompletenessCriteria(
      cc1_ladder_and_planes_total: True,
      cc2_component_placement: True,
      cc3_live_artifact_attached: True,
      cc4_interaction_endpoints_declared: True,
      cc5_critical_paths_closed: True,
      cc6_component_packet_on_change: True,
    )
  evaluate_system_completeness(complete)
  |> should.be_true

  evaluate_system_completeness(
    CompletenessCriteria(..complete, cc5_critical_paths_closed: False),
  )
  |> should.be_false
}

pub fn wiki_pipeline_recursion_test() {
  let valid_pipeline =
    WikiPipelineRecursion(
      corpus_prefix_size: 512,
      worker_count: 4,
      backlink_inversion_active: True,
      aho_corasick_mention_active: True,
      immutable_render_context: True,
      lossless_projection_verified: True,
    )
  verify_wiki_pipeline_recursion(valid_pipeline)
  |> should.be_true

  verify_wiki_pipeline_recursion(
    WikiPipelineRecursion(..valid_pipeline, worker_count: 0),
  )
  |> should.be_false
}
