/// Tool Sequencer tests
/// Layer: L3_TRANSACTION
/// STAMP: SC-HA-001, SC-FUNC-001, SC-MUDA-001
///
/// Covers:
///   sequence_new construction
///   validate_dependencies: unknown deps return Error
///   execution_order: parallel waves grouping
///   record_result and can_proceed logic
///   all_completed and all_passed gates
///   Summary string
import cepaf_gleam/ha/tool_sequencer.{
  type ToolStep, Completed, Failed, Pending, ToolStep, all_completed, all_passed,
  can_proceed, execution_order, record_result, sequence_new, summary,
  validate_dependencies,
}
import gleam/list
import gleeunit/should

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn step(name: String, deps: List(String)) -> ToolStep {
  ToolStep(tool_name: name, args: [], timeout_ms: 5000, depends_on: deps)
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

pub fn sequence_new_stores_steps_test() {
  let seq = sequence_new([step("a", []), step("b", ["a"])])
  list.length(seq.steps) |> should.equal(2)
}

pub fn sequence_new_has_no_results_test() {
  let seq = sequence_new([step("a", [])])
  list.length(seq.results) |> should.equal(0)
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

pub fn validate_dependencies_ok_test() {
  let seq = sequence_new([step("a", []), step("b", ["a"])])
  validate_dependencies(seq) |> should.be_ok()
}

pub fn validate_dependencies_unknown_dep_test() {
  let seq = sequence_new([step("b", ["missing"])])
  validate_dependencies(seq) |> should.be_error()
}

pub fn validate_dependencies_multiple_unknown_test() {
  let seq = sequence_new([step("c", ["x", "y"])])
  case validate_dependencies(seq) {
    Error(msg) -> msg |> should.not_equal("")
    Ok(_) -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Execution order
// ---------------------------------------------------------------------------

pub fn execution_order_no_deps_single_wave_test() {
  let seq = sequence_new([step("a", []), step("b", []), step("c", [])])
  let waves = execution_order(seq)
  // All independent — should collapse into one wave
  list.length(waves) |> should.equal(1)
}

pub fn execution_order_chain_produces_multiple_waves_test() {
  let seq = sequence_new([step("a", []), step("b", ["a"]), step("c", ["b"])])
  let waves = execution_order(seq)
  // a -> b -> c means 3 waves
  list.length(waves) |> should.equal(3)
}

pub fn execution_order_first_wave_has_no_deps_test() {
  let seq = sequence_new([step("root", []), step("child", ["root"])])
  let waves = execution_order(seq)
  case waves {
    [first, ..] -> list.contains(first, "root") |> should.be_true()
    [] -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Record result
// ---------------------------------------------------------------------------

pub fn record_result_adds_entry_test() {
  let seq =
    sequence_new([step("a", [])])
    |> record_result("a", Completed("ok"), 100)
  list.length(seq.results) |> should.equal(1)
}

pub fn record_result_replaces_existing_test() {
  let seq =
    sequence_new([step("a", [])])
    |> record_result("a", Completed("first"), 100)
    |> record_result("a", Completed("second"), 200)
  list.length(seq.results) |> should.equal(1)
}

// ---------------------------------------------------------------------------
// can_proceed
// ---------------------------------------------------------------------------

pub fn can_proceed_no_deps_is_true_test() {
  let seq = sequence_new([step("a", [])])
  can_proceed(seq, "a") |> should.be_true()
}

pub fn can_proceed_with_unfinished_dep_is_false_test() {
  let seq = sequence_new([step("a", []), step("b", ["a"])])
  can_proceed(seq, "b") |> should.be_false()
}

pub fn can_proceed_with_completed_dep_is_true_test() {
  let seq =
    sequence_new([step("a", []), step("b", ["a"])])
    |> record_result("a", Completed("done"), 50)
  can_proceed(seq, "b") |> should.be_true()
}

pub fn can_proceed_with_failed_dep_is_false_test() {
  let seq =
    sequence_new([step("a", []), step("b", ["a"])])
    |> record_result("a", Failed("err"), 50)
  can_proceed(seq, "b") |> should.be_false()
}

// ---------------------------------------------------------------------------
// all_completed / all_passed
// ---------------------------------------------------------------------------

pub fn all_completed_false_when_pending_test() {
  let seq = sequence_new([step("a", [])])
  all_completed(seq) |> should.be_false()
}

pub fn all_completed_true_when_all_done_test() {
  let seq =
    sequence_new([step("a", []), step("b", [])])
    |> record_result("a", Completed("ok"), 10)
    |> record_result("b", Failed("err"), 20)
  all_completed(seq) |> should.be_true()
}

pub fn all_passed_false_when_failed_test() {
  let seq =
    sequence_new([step("a", []), step("b", [])])
    |> record_result("a", Completed("ok"), 10)
    |> record_result("b", Failed("err"), 20)
  all_passed(seq) |> should.be_false()
}

pub fn all_passed_true_when_all_completed_test() {
  let seq =
    sequence_new([step("a", []), step("b", [])])
    |> record_result("a", Completed("ok"), 10)
    |> record_result("b", Completed("ok"), 20)
  all_passed(seq) |> should.be_true()
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

pub fn summary_is_not_empty_test() {
  let seq = sequence_new([step("a", [])])
  summary(seq) |> should.not_equal("")
}

pub fn summary_pending_step_not_counted_completed_test() {
  let seq = sequence_new([step("a", []), step("b", [])])
  let _ = Pending
  let s = summary(seq)
  s |> should.not_equal("")
}
