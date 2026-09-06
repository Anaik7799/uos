//// =============================================================================
//// [C3I-SIL6-ASPECT-PROCESSING-TEST] FRACTAL ASPECT PROCESSING AGENTS TEST
//// =============================================================================

import gleeunit/should
import gleam/list
import gleam/string
import cepaf_gleam/sdlc/aspect_agent_ecosystem.{AspectComponentPacket, AspectVerticalLadder}
import cepaf_gleam/sdlc/aspect_processing_agent.{
  init_all_14_processing_agents,
  execute_fractal_processing_cycle,
  execute_all_aspects_processing_cycle,
  verify_all_aspects_fractally_aligned,
  lookup_processing_agent_by_layer,
  lookup_processing_agent_by_aspect,
  encode_processing_agents_json,
  CycleSuccess,
}

pub fn init_all_14_processing_agents_test() {
  let agents = init_all_14_processing_agents()
  list.length(agents) |> should.equal(14)

  list.each(agents, fn(a) {
    a.aspect_name |> should.not_equal("")
    a.processor_agent_name |> should.not_equal("")
    { a.features_count > 0 } |> should.be_true
    { a.squad_agent_count > 0 } |> should.be_true
    { a.primary_layer >= 0 && a.primary_layer <= 10 } |> should.be_true
    { a.secondary_layers != [] } |> should.be_true
  })
}

pub fn lyapunov_stability_and_entropy_test() {
  let agents = init_all_14_processing_agents()

  list.each(agents, fn(a) {
    // Negative Lyapunov exponent guarantees asymptotic orbital stability
    { a.lyapunov_exponent <. 0.0 } |> should.be_true
    // Shannon entropy >= 2.5 bits ensures high-dimensional information preservation
    { a.shannon_entropy >=. 2.5 } |> should.be_true
  })
}

pub fn execute_single_cycle_test() {
  let agents = init_all_14_processing_agents()
  case list.first(agents) {
    Ok(agent) -> {
      let #(updated, result) = execute_fractal_processing_cycle(agent)
      updated.current_cycle |> should.equal(agent.current_cycle + 1)
      updated.status |> should.equal("CYCLE_COMPLETED_HEALTHY")
      case result {
        CycleSuccess(name, layer, feats, squad, lyap, ent, duration) -> {
          name |> should.equal(agent.aspect_name)
          layer |> should.equal(agent.primary_layer)
          feats |> should.equal(agent.features_count)
          squad |> should.equal(agent.squad_agent_count)
          { lyap <. 0.0 } |> should.be_true
          { ent >=. 2.5 } |> should.be_true
          { duration > 0 } |> should.be_true
        }
        _ -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn execute_all_aspects_processing_cycle_test() {
  let #(states, results) = execute_all_aspects_processing_cycle()
  list.length(states) |> should.equal(14)
  list.length(results) |> should.equal(14)

  list.each(results, fn(r) {
    case r {
      CycleSuccess(_, _, _, _, _, _, _) -> should.be_true(True)
      _ -> should.fail()
    }
  })
}

pub fn verify_fractal_alignment_test() {
  let agents = init_all_14_processing_agents()
  verify_all_aspects_fractally_aligned(agents)
  |> should.be_true
}

pub fn lookup_agent_by_layer_and_aspect_test() {
  let agents = init_all_14_processing_agents()

  // Layer 0 has SemanticStrata, CompletenessCriteria, ProductionConjunction
  let l0_agents = lookup_processing_agent_by_layer(0, agents)
  { list.length(l0_agents) >= 3 } |> should.be_true

  // Layer 4 has VerticalLadder, OrthogonalPlanes, HorizontalSubsystems
  let l4_agents = lookup_processing_agent_by_layer(4, agents)
  { list.length(l4_agents) >= 3 } |> should.be_true

  let cp_res = lookup_processing_agent_by_aspect(AspectComponentPacket, agents)
  case cp_res {
    Ok(a) -> a.processor_agent_name |> should.equal("ComponentPacketProcessingAgent")
    Error(_) -> should.fail()
  }

  let vl_res = lookup_processing_agent_by_aspect(AspectVerticalLadder, agents)
  case vl_res {
    Ok(a) -> a.processor_agent_name |> should.equal("VerticalLadderProcessingAgent")
    Error(_) -> should.fail()
  }
}

pub fn processing_agents_json_encoding_test() {
  let agents = init_all_14_processing_agents()
  let json_str = encode_processing_agents_json(agents)

  string.contains(json_str, "\"status\":\"ok\"") |> should.be_true
  string.contains(json_str, "\"total_aspect_processors\":14") |> should.be_true
  string.contains(json_str, "\"total_features_governed\":104") |> should.be_true
  string.contains(json_str, "\"total_squad_agents_active\":256") |> should.be_true
  string.contains(json_str, "\"all_fractally_aligned\":true") |> should.be_true
}
