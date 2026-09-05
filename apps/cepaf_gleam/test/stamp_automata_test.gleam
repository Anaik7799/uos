/// RETE5 — STAMP Constraint Automata Tests — 14-test suite
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-SIL4-001, SC-FUNC-001, SC-SAFETY-001, SC-GLM-UI-001, SC-MUDA-001
/// Ultrathink: Focus #5 (Continuous Formal Verification), #8 (Apoptosis)
///
/// अहिंसा परमो धर्मः — Non-violation is the highest duty (Mahabharata)
import cepaf_gleam/ha/stamp_automata.{
  AtRisk, Compliant, StampCell, Violated, at_risk_count, compliance_ratio,
  evaluate_step, init_grid, status_to_string, summary, to_json, violation_count,
}
import gleam/list
import gleam/string
import gleeunit/should

// ===========================================================================
// init_grid — construction
// ===========================================================================

pub fn init_grid_length_test() {
  let ids = ["SC-SIL4-001", "SC-FUNC-001", "SC-SAFETY-001"]
  let cells = init_grid(ids)
  cells |> list.length |> should.equal(3)
}

pub fn init_grid_all_compliant_test() {
  let ids = ["SC-A", "SC-B", "SC-C", "SC-D"]
  let cells = init_grid(ids)
  cells
  |> list.all(fn(c) { c.status == Compliant })
  |> should.be_true
}

pub fn init_grid_generation_zero_test() {
  let cells = init_grid(["SC-X"])
  cells
  |> list.all(fn(c) { c.generation == 0 })
  |> should.be_true
}

pub fn init_grid_preserves_ids_test() {
  let ids = ["SC-SIL4-001", "SC-FUNC-001"]
  let cells = init_grid(ids)
  let got_ids = list.map(cells, fn(c) { c.constraint_id })
  got_ids |> should.equal(ids)
}

// ===========================================================================
// evaluate_step — transition rules
// ===========================================================================

pub fn evaluate_step_all_compliant_stays_compliant_test() {
  let cells = init_grid(["SC-A", "SC-B", "SC-C"])
  let cells2 = evaluate_step(cells)
  cells2
  |> list.all(fn(c) { c.status == Compliant })
  |> should.be_true
}

pub fn evaluate_step_violated_stays_violated_test() {
  // Violated cells must NOT self-heal (safety invariant)
  let cells = [
    StampCell(constraint_id: "SC-A", status: Violated, generation: 0),
    StampCell(constraint_id: "SC-B", status: Compliant, generation: 0),
  ]
  let cells2 = evaluate_step(cells)
  let first =
    cells2
    |> list.first
  case first {
    Ok(c) -> c.status |> should.equal(Violated)
    Error(_) -> should.fail()
  }
}

pub fn evaluate_step_violated_makes_neighbour_at_risk_test() {
  // Middle cell Violated → both neighbours become AtRisk
  let cells = [
    StampCell(constraint_id: "SC-A", status: Compliant, generation: 0),
    StampCell(constraint_id: "SC-B", status: Violated, generation: 0),
    StampCell(constraint_id: "SC-C", status: Compliant, generation: 0),
  ]
  let cells2 = evaluate_step(cells)
  let first_status =
    cells2
    |> list.first
    |> fn(r) {
      case r {
        Ok(c) -> c.status
        Error(_) -> Compliant
      }
    }
  first_status |> should.equal(AtRisk)
}

pub fn evaluate_step_at_risk_recovers_with_no_violated_neighbour_test() {
  let cells = [
    StampCell(constraint_id: "SC-A", status: Compliant, generation: 0),
    StampCell(constraint_id: "SC-B", status: AtRisk, generation: 0),
    StampCell(constraint_id: "SC-C", status: Compliant, generation: 0),
  ]
  let cells2 = evaluate_step(cells)
  // Middle cell should recover to Compliant
  let mid =
    cells2
    |> list.drop(1)
    |> list.first
    |> fn(r) {
      case r {
        Ok(c) -> c.status
        Error(_) -> Violated
      }
    }
  mid |> should.equal(Compliant)
}

pub fn evaluate_step_preserves_length_test() {
  let cells = init_grid(["SC-A", "SC-B", "SC-C", "SC-D"])
  let cells2 = evaluate_step(cells)
  list.length(cells2) |> should.equal(4)
}

// ===========================================================================
// Metrics
// ===========================================================================

pub fn violation_count_zero_when_all_compliant_test() {
  let cells = init_grid(["SC-A", "SC-B", "SC-C"])
  violation_count(cells) |> should.equal(0)
}

pub fn violation_count_counts_correctly_test() {
  let cells = [
    StampCell(constraint_id: "SC-A", status: Violated, generation: 0),
    StampCell(constraint_id: "SC-B", status: Compliant, generation: 0),
    StampCell(constraint_id: "SC-C", status: Violated, generation: 0),
  ]
  violation_count(cells) |> should.equal(2)
}

pub fn at_risk_count_test() {
  let cells = [
    StampCell(constraint_id: "SC-A", status: AtRisk, generation: 0),
    StampCell(constraint_id: "SC-B", status: Compliant, generation: 0),
    StampCell(constraint_id: "SC-C", status: AtRisk, generation: 0),
  ]
  at_risk_count(cells) |> should.equal(2)
}

pub fn compliance_ratio_all_compliant_is_one_test() {
  let cells = init_grid(["SC-A", "SC-B"])
  compliance_ratio(cells) |> should.equal(1.0)
}

pub fn compliance_ratio_empty_grid_is_one_test() {
  compliance_ratio([]) |> should.equal(1.0)
}

pub fn compliance_ratio_partial_test() {
  let cells = [
    StampCell(constraint_id: "SC-A", status: Compliant, generation: 0),
    StampCell(constraint_id: "SC-B", status: Violated, generation: 0),
  ]
  // 1 out of 2 compliant = 0.5
  compliance_ratio(cells) |> should.equal(0.5)
}

// ===========================================================================
// Serialisation
// ===========================================================================

pub fn to_json_is_array_test() {
  let cells = init_grid(["SC-A"])
  let j = to_json(cells)
  string.contains(j, "[{") |> should.be_true
}

pub fn to_json_contains_constraint_id_test() {
  let cells = init_grid(["SC-SIL4-001"])
  let j = to_json(cells)
  string.contains(j, "SC-SIL4-001") |> should.be_true
}

pub fn summary_contains_constraints_label_test() {
  let cells = init_grid(["SC-A", "SC-B"])
  let s = summary(cells)
  string.contains(s, "constraints") |> should.be_true
}

pub fn status_to_string_all_variants_test() {
  status_to_string(Compliant) |> should.equal("compliant")
  status_to_string(AtRisk) |> should.equal("at_risk")
  status_to_string(Violated) |> should.equal("violated")
}
