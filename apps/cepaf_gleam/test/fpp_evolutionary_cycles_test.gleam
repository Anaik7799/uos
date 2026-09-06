//// =============================================================================
//// [UOS-TEST-FPP-EVOLUTIONARY-CYCLES] 60 Cycles Test Suite (F' + Full ZigVM)
//// =============================================================================

import cepaf_gleam/fpp/evolutionary_cycles.{
  ClaudeFable, CodexAstra, TriSovereignConsensus, encode_cycles_json,
  get_15_evolutionary_cycles, get_30_evolutionary_cycles,
  get_60_evolutionary_cycles, get_zigvm_evolutionary_cycles,
  verify_all_15_cycles, verify_all_30_cycles, verify_all_60_cycles, verify_cycle,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn get_15_and_30_cycles_count_test() {
  let cycles15 = get_15_evolutionary_cycles()
  list.length(cycles15) |> should.equal(15)
  let #(_, all_pass15, _) = verify_all_15_cycles()
  all_pass15 |> should.equal(True)

  let cycles30 = get_30_evolutionary_cycles()
  list.length(cycles30) |> should.equal(30)
  let #(_, all_pass30, _) = verify_all_30_cycles()
  all_pass30 |> should.equal(True)
}

pub fn get_60_cycles_count_test() {
  let cycles = get_60_evolutionary_cycles()
  list.length(cycles)
  |> should.equal(60)
}

pub fn zigvm_subcycles_count_test() {
  let zigvm_cycles = get_zigvm_evolutionary_cycles()
  list.length(zigvm_cycles)
  |> should.equal(45)
  list.all(zigvm_cycles, fn(c) { c.cycle_num >= 16 && c.cycle_num <= 60 })
  |> should.be_true()
}

pub fn cycle_alternation_test() {
  let cycles = get_60_evolutionary_cycles()

  // Codex Astra cycles
  let codex_cycles = list.filter(cycles, fn(c) { c.sovereign == CodexAstra })
  list.length(codex_cycles)
  |> should.equal(28)

  // Claude Fable cycles
  let claude_cycles = list.filter(cycles, fn(c) { c.sovereign == ClaudeFable })
  list.length(claude_cycles)
  |> should.equal(28)

  // Consensus cycles: 15, 30, 45, 60
  let consensus_cycles =
    list.filter(cycles, fn(c) { c.sovereign == TriSovereignConsensus })
  list.length(consensus_cycles)
  |> should.equal(4)
}

pub fn aspect_coverage_test() {
  let cycles = get_60_evolutionary_cycles()
  let aspects = list.map(cycles, fn(c) { c.aspect })
  // Verify all 5 aspects are present
  list.contains(aspects, evolutionary_cycles.FunctionalityAspect)
  |> should.be_true()
  list.contains(aspects, evolutionary_cycles.CodeAspect) |> should.be_true()
  list.contains(aspects, evolutionary_cycles.SopAspect) |> should.be_true()
  list.contains(aspects, evolutionary_cycles.SkillsAspect) |> should.be_true()
  list.contains(aspects, evolutionary_cycles.SuperpowersAspect)
  |> should.be_true()
}

pub fn individual_60_cycles_execution_test() {
  let nums = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
    22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
    60,
  ]
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

pub fn verify_all_60_cycles_metrics_test() {
  let #(cycles, all_passed, metrics) = verify_all_60_cycles()
  list.length(cycles) |> should.equal(60)
  all_passed |> should.be_true()

  // Verify 4 Math Gates
  { metrics.shannon_entropy >=. 2.5 } |> should.be_true()
  { metrics.cyclomatic_complexity >=. 0.9 } |> should.be_true()
  { metrics.divergence_d_ea <=. 0.1 } |> should.be_true()
  { metrics.itqs >=. 0.85 } |> should.be_true()
  metrics.all_gates_pass |> should.be_true()
}

pub fn json_serialization_60_cycles_test() {
  let #(cycles, _, metrics) = verify_all_60_cycles()
  let json_str = encode_cycles_json(cycles, metrics)

  string.contains(json_str, "\"cycles_count\":60") |> should.be_true()
  string.contains(json_str, "\"all_passed\":true") |> should.be_true()
  string.contains(json_str, "Codex Astra") |> should.be_true()
  string.contains(json_str, "Claude Fable 5.1") |> should.be_true()
  string.contains(json_str, "Tri-Sovereign Consensus") |> should.be_true()
  string.contains(json_str, "ZigVM") |> should.be_true()
}
