import gleam/option
import gleam/string
import gleeunit/should
import uos_swarm
import uos_swarm/board.{Agent, Causality, Draft, Semantics}

fn path(label: String) -> String {
  "/tmp/uos-board-validate-"
  <> label
  <> "-"
  <> string.inspect(board.system_time_us())
  <> ".jsonl"
}

fn draft(note: String) -> board.Draft {
  Draft(
    Agent("validator", "L3", "test"),
    "broadcast",
    board.Report,
    [#("note", note)],
    Semantics(["App"], [14], ["CA-emit_intent"], [], 3),
    Causality(option.None, []),
    option.None,
    option.None,
  )
}

fn sealed(
  note: String,
  ts: Int,
  span: String,
  previous: String,
) -> board.Message {
  board.seal(draft(note), "validation-test", ts, ts, span, previous)
  |> fn(message) { board.sign(message, option.from_result(board.board_key())) }
}

pub fn missing_file_is_an_error_test() {
  let assert Error(error) = uos_swarm.validate_board_file(path("missing"))
  string.contains(error, "enoent") |> should.be_true
}

pub fn explicitly_empty_file_is_labelled_without_health_claim_test() {
  let empty = path("empty")
  board.file_write(empty, "") |> should.be_ok

  let assert Ok(summary) = uos_swarm.validate_board_file(empty)
  summary
  |> should.equal("board EMPTY: 0 messages; no hive health inferred")
}

pub fn malformed_row_is_an_error_test() {
  let malformed = path("malformed")
  board.file_write(malformed, "not-json\n") |> should.be_ok

  let assert Error(error) = uos_swarm.validate_board_file(malformed)
  string.contains(error, "1 malformed row") |> should.be_true
}

pub fn conflicting_duplicate_digests_are_an_error_test() {
  let conflict = path("conflict")
  let first = sealed("first", 1, "0123456789abcdef", board.genesis_digest)
  let second = sealed("second", 1, "0123456789abcdef", board.genesis_digest)
  first.id |> should.equal(second.id)
  first.digest |> should.not_equal(second.digest)
  board.file_write(
    conflict,
    board.to_string(first) <> "\n" <> board.to_string(second) <> "\n",
  )
  |> should.be_ok

  let assert Error(error) = uos_swarm.validate_board_file(conflict)
  string.contains(error, "conflicting duplicate digests") |> should.be_true
}

pub fn broken_chain_is_an_error_test() {
  let invalid = path("chain")
  let message =
    sealed(
      "orphan",
      2,
      "0123456789abcdee",
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
  board.file_write(invalid, board.to_string(message) <> "\n") |> should.be_ok

  let assert Error(error) = uos_swarm.validate_board_file(invalid)
  string.contains(error, "chain broken") |> should.be_true
}

pub fn valid_chain_reports_explicit_gaps_and_forks_test() {
  let valid = path("valid")
  let first = sealed("first", 3, "0123456789abcded", board.genesis_digest)
  let second = sealed("second", 4, "0123456789abcdec", first.digest)
  board.file_write(
    valid,
    board.to_string(first) <> "\n" <> board.to_string(second) <> "\n",
  )
  |> should.be_ok

  let assert Ok(summary) = uos_swarm.validate_board_file(valid)
  summary
  |> should.equal(
    "board valid: 2 messages, chain intact, semantics resolved, causal gaps 0, chain forks 0 (explicit records; lost history is not restored)",
  )
}
