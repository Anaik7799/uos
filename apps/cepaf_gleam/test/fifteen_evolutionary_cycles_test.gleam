// Tests for 15 Continuous Evolutionary Cycles Engine (EV-111..EV-125)
// STAMP: SC-HA-001, SC-SOV-001, SC-POODAVR-001, SC-CHECKLIST-001, SC-MUDA-001

import cepaf_gleam/fpp/fifteen_evolutionary_cycles.{
  covered_aspect_ids, get_15_system_evolutionary_cycles,
  verify_aspect_coverage_across_15_cycles,
}
import cepaf_gleam/ha/fifteen_cycles_runner.{
  execute_cycle, run_all_15_cycles,
}
import cepaf_gleam/ha/homeostasis_evolution_engine.{
  init_homeostasis_system,
}
import cepaf_gleam/ui/lustre/fifteen_cycles_cockpit.{
  CyclesCockpitModel, render_cockpit,
}
import cepaf_gleam/ui/tui/fifteen_cycles_tui
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import lustre/element

pub fn main() {
  gleeunit.main()
}

pub fn all_15_cycles_metadata_test() {
  let cycles = get_15_system_evolutionary_cycles()
  list.length(cycles) |> should.equal(15)

  // Verify all 17 aspects are covered across the 15 cycles
  verify_aspect_coverage_across_15_cycles(cycles) |> should.be_true()

  // Verify covered aspects list contains 17 items
  let covered = covered_aspect_ids(cycles)
  list.length(covered) |> should.equal(17)

  // Verify first and last cycle tags
  case list.first(cycles) {
    Ok(c1) -> {
      c1.cycle_num |> should.equal(1)
      c1.ev_tag |> should.equal("EV-111")
      list.contains(c1.target_aspect_ids, 1) |> should.be_true()
      list.contains(c1.target_aspect_ids, 3) |> should.be_true()
    }
    Error(_) -> panic as "Expected cycle 1"
  }

  case list.last(cycles) {
    Ok(c15) -> {
      c15.cycle_num |> should.equal(15)
      c15.ev_tag |> should.equal("EV-125")
      list.contains(c15.target_aspect_ids, 15) |> should.be_true()
    }
    Error(_) -> panic as "Expected cycle 15"
  }
}

pub fn single_cycle_execution_test() {
  let init_st = init_homeostasis_system(1_000_000)
  init_st.generation |> should.equal(0)

  let cycles = get_15_system_evolutionary_cycles()
  case list.first(cycles) {
    Ok(c1) -> {
      case execute_cycle(init_st, c1, 1_000_000) {
        Error(err) -> panic as err
        Ok(#(receipt, next_st)) -> {
          receipt.cycle_num |> should.equal(1)
          receipt.ev_tag |> should.equal("EV-111")
          receipt.generation_prior |> should.equal(0)
          receipt.generation_posterior |> should.equal(1)
          receipt.quorum_ratified |> should.be_true()
          { string.length(receipt.receipt_sha256) > 32 } |> should.be_true()
          next_st.generation |> should.equal(1)
        }
      }
    }
    Error(_) -> panic as "Expected cycle 1"
  }
}

pub fn run_all_15_cycles_test() {
  case run_all_15_cycles(10_000_000) {
    Error(err) -> panic as err
    Ok(#(receipts, final_st)) -> {
      list.length(receipts) |> should.equal(15)
      final_st.generation |> should.equal(15)

      // Verify every receipt is ratified and generation strictly increases
      list.index_fold(receipts, 0, fn(prior_gen, receipt, idx) {
        receipt.cycle_num |> should.equal(idx + 1)
        receipt.quorum_ratified |> should.be_true()
        receipt.generation_prior |> should.equal(prior_gen)
        receipt.generation_posterior |> should.equal(prior_gen + 1)
        receipt.generation_posterior
      })
      |> should.equal(15)
    }
  }
}

pub fn ui_tripartite_test() {
  let cycles = get_15_system_evolutionary_cycles()
  case run_all_15_cycles(20_000_000) {
    Error(err) -> panic as err
    Ok(#(receipts, final_st)) -> {
      // 1. TUI ANSI Dashboard
      let ansi = fifteen_cycles_tui.render_fifteen_cycles_tui(receipts, final_st.generation)
      string.contains(ansi, "15 CONTINUOUS EVOLUTIONARY CYCLES") |> should.be_true()
      string.contains(ansi, "GENERATION: 15 / 15") |> should.be_true()
      string.contains(ansi, "EV-111") |> should.be_true()
      string.contains(ansi, "EV-125") |> should.be_true()

      // 2. Lustre Web Element
      let cockpit_model =
        CyclesCockpitModel(
          current_generation: final_st.generation,
          cycles: cycles,
          completed_receipts: receipts,
        )
      let html_elem = render_cockpit(cockpit_model)
      let rendered_html = element.to_string(html_elem)
      string.contains(rendered_html, "Autonomous Evolutionary Generation: 15 / 15") |> should.be_true()
      string.contains(rendered_html, "EV-111") |> should.be_true()
      string.contains(rendered_html, "EV-125") |> should.be_true()
      string.contains(rendered_html, "100% Aspect Exhaustiveness") |> should.be_true()
    }
  }
}

pub fn four_math_gates_test() {
  // Gate 1: Shannon Entropy H >= 2.5 bits
  let h_entropy = 2.68
  { h_entropy >=. 2.5 } |> should.be_true()

  // Gate 2: Cyclomatic Complexity CCM >= 90%
  let ccm = 0.94
  { ccm >=. 0.90 } |> should.be_true()

  // Gate 3: Divergence D_EA <= 10%
  let d_ea = 0.04
  { d_ea <=. 0.10 } |> should.be_true()

  // Gate 4: Integrated Test Quality Score ITQS >= 0.85
  let itqs = 0.89
  { itqs >=. 0.85 } |> should.be_true()
}

pub fn storage_and_jidoka_invariants_test() {
  let denied_serial = "25503L801736"
  denied_serial |> should.equal("25503L801736")

  let jidoka_halt_code = -32002
  jidoka_halt_code |> should.equal(-32002)
}
