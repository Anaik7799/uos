import cepaf_gleam/core/ids
import cepaf_gleam/core/types
import cepaf_gleam/planning/parser
import cepaf_gleam/zenoh/safety.{
  ChannelA, ChannelB, ChannelC, Disagreement, Majority, Unanimous,
}
import gleam/dict
import gleam/list
import gleeunit/should

// =============================================================================
// L0 CONSTITUTIONAL TESTS - Type Safety Invariants
// =============================================================================

pub fn non_empty_string_rejects_empty_test() {
  types.new_non_empty_string("")
  |> should.be_error()
}

pub fn non_empty_string_rejects_whitespace_test() {
  types.new_non_empty_string("   ")
  |> should.be_error()
}

pub fn non_empty_string_accepts_valid_test() {
  types.new_non_empty_string("hello")
  |> should.be_ok()
}

pub fn positive_int_rejects_zero_test() {
  types.new_positive_int(0)
  |> should.be_error()
}

pub fn positive_int_rejects_negative_test() {
  types.new_positive_int(-5)
  |> should.be_error()
}

pub fn positive_int_accepts_positive_test() {
  types.new_positive_int(42)
  |> should.be_ok()
}

pub fn unit_interval_rejects_over_test() {
  types.new_unit_interval(1.5)
  |> should.be_error()
}

pub fn unit_interval_rejects_negative_test() {
  types.new_unit_interval(-0.1)
  |> should.be_error()
}

pub fn unit_interval_accepts_bounds_test() {
  types.new_unit_interval(0.0)
  |> should.be_ok()
  types.new_unit_interval(1.0)
  |> should.be_ok()
}

pub fn priority_roundtrip_test() {
  types.priority_from_string("P0")
  |> types.priority_to_string()
  |> should.equal("P0")
}

pub fn task_status_roundtrip_test() {
  types.task_status_from_string("completed")
  |> types.task_status_to_string()
  |> should.equal("completed")
}

// =============================================================================
// L0 CONSTITUTIONAL TESTS - ID Generation
// =============================================================================

pub fn task_id_uniqueness_test() {
  let id1 = ids.new_task_id()
  let id2 = ids.new_task_id()
  let s1 = ids.task_id_to_string(id1)
  let s2 = ids.task_id_to_string(id2)
  should.not_equal(s1, s2)
}

pub fn task_id_from_string_roundtrip_test() {
  let original = "test-id-123"
  let id = ids.task_id_from_string(original)
  ids.task_id_to_string(id)
  |> should.equal(original)
}

// =============================================================================
// L2 COMPONENT TESTS - Parser
// =============================================================================

pub fn parser_parses_completed_tasks_test() {
  let content =
    "# PROJECT TODOLIST\n\n## 1.1.1 - Test task (P0) [COMPLETED]\n## 1.1.2 - Another task (P1) [PENDING]\n"
  let tasks = parser.parse_todolist(content)
  list.length(tasks)
  |> should.equal(2)
}

pub fn parser_handles_empty_content_test() {
  let tasks = parser.parse_todolist("")
  list.length(tasks)
  |> should.equal(0)
}

pub fn parser_skips_header_lines_test() {
  let content = "# Header\n\nSome random text\n"
  let tasks = parser.parse_todolist(content)
  list.length(tasks)
  |> should.equal(0)
}

// =============================================================================
// L6 ECOSYSTEM TESTS - TMR Voting (2oo3 Consensus)
// =============================================================================

pub fn tmr_unanimous_test() {
  let results =
    dict.from_list([
      #(ChannelA, 42),
      #(ChannelB, 42),
      #(ChannelC, 42),
    ])
  case safety.vote(results) {
    Unanimous(value) -> should.equal(value, 42)
    _ -> should.fail()
  }
}

pub fn tmr_majority_test() {
  let results =
    dict.from_list([
      #(ChannelA, 42),
      #(ChannelB, 42),
      #(ChannelC, 99),
    ])
  case safety.vote(results) {
    Majority(value, _dissenter) -> should.equal(value, 42)
    _ -> should.fail()
  }
}

pub fn tmr_disagreement_test() {
  let results =
    dict.from_list([
      #(ChannelA, 1),
      #(ChannelB, 2),
      #(ChannelC, 3),
    ])
  case safety.vote(results) {
    Disagreement(_) -> should.be_true(True)
    _ -> should.fail()
  }
}
