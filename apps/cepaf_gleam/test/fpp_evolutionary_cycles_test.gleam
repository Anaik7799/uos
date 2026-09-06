//// =============================================================================
//// [UOS-TEST-FPP-EVOLUTIONARY-CYCLES] 15 Cycles Test Suite
//// =============================================================================

import cepaf_gleam/fpp/evolutionary_cycles.{
  ClaudeFable, CodexAstra, TriSovereignConsensus,
  encode_cycles_json, get_15_evolutionary_cycles,
  verify_all_15_cycles, verify_cycle,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn get_15_cycles_count_test() {
  let cycles = get_15_evolutionary_cycles()
  list.length(cycles)
  |> should.equal(15)
}

pub fn cycle_alternation_test() {
  let cycles = get_15_evolutionary_cycles()
  
  // Verify odd cycles (1, 3, 5, 7, 9, 11, 13) are CodexAstra
  let codex_cycles = list.filter(cycles, fn(c) {
    c.cycle_num % 2 == 1 && c.cycle_num < 15
  })
  list.length(codex_cycles)
  |> should.equal(7)
  list.all(codex_cycles, fn(c) { c.sovereign == CodexAstra })
  |> should.be_true()

  // Verify even cycles (2, 4, 6, 8, 10, 12, 14) are ClaudeFable
  let claude_cycles = list.filter(cycles, fn(c) {
    c.cycle_num % 2 == 0
  })
  list.length(claude_cycles)
  |> should.equal(7)
  list.all(claude_cycles, fn(c) { c.sovereign == ClaudeFable })
  |> should.be_true()

  // Verify cycle 15 is TriSovereignConsensus
  let cycle_15 = list.find(cycles, fn(c) { c.cycle_num == 15 })
  case cycle_15 {
    Ok(c) -> c.sovereign |> should.equal(TriSovereignConsensus)
    Error(_) -> should.fail()
  }
}

pub fn aspect_coverage_test() {
  let cycles = get_15_evolutionary_cycles()
  let aspects = list.map(cycles, fn(c) { c.aspect })
  // Verify all 5 aspects are present
  list.contains(aspects, evolutionary_cycles.FunctionalityAspect) |> should.be_true()
  list.contains(aspects, evolutionary_cycles.CodeAspect) |> should.be_true()
  list.contains(aspects, evolutionary_cycles.SopAspect) |> should.be_true()
  list.contains(aspects, evolutionary_cycles.SkillsAspect) |> should.be_true()
  list.contains(aspects, evolutionary_cycles.SuperpowersAspect) |> should.be_true()
}

pub fn individual_cycle_execution_test() {
  let nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
  list.each(nums, fn(n) {
    case verify_cycle(n) {
      Ok(record) -> {
        record.cycle_num |> should.equal(n)
        record.status |> should.equal(evolutionary_cycles.CycleRatified)
      }
      Error(_) -> should.fail()
    }
  })
}

pub fn verify_all_15_cycles_metrics_test() {
  let #(cycles, all_passed, metrics) = verify_all_15_cycles()
  list.length(cycles) |> should.equal(15)
  all_passed |> should.be_true()
  
  // Verify 4 Math Gates
  { metrics.shannon_entropy >=. 2.5 } |> should.be_true()
  { metrics.cyclomatic_complexity >=. 0.90 } |> should.be_true()
  { metrics.divergence_d_ea <=. 0.10 } |> should.be_true()
  { metrics.itqs >=. 0.85 } |> should.be_true()
  metrics.all_gates_pass |> should.be_true()
}

pub fn json_serialization_test() {
  let #(cycles, _, metrics) = verify_all_15_cycles()
  let json_str = encode_cycles_json(cycles, metrics)
  
  string.contains(json_str, "\"cycles_count\":15") |> should.be_true()
  string.contains(json_str, "\"all_passed\":true") |> should.be_true()
  string.contains(json_str, "Codex Astra") |> should.be_true()
  string.contains(json_str, "Claude Fable 5.1") |> should.be_true()
  string.contains(json_str, "Tri-Sovereign Consensus") |> should.be_true()
  string.contains(json_str, "25503L801736") |> should.be_true()
}
