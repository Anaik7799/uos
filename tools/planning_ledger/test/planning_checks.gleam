import gleam/dynamic.{type Dynamic}
import gleam/io
import prompt_test

// Explicit hermetic selection: never discover the corpus-reading tests.
// The binding is the existing pinned gleeunit helper, not authored Erlang.
type TestModule {
  DatabaseTest
  SafetyTest
  WriterLockTest
  PlanningGuardTest
  IntakeGuardTest
}

type TestOption {
  Verbose
}

@external(erlang, "gleeunit_ffi", "run_eunit")
fn run_selected(
  tests: List(a),
  options: List(TestOption),
) -> Result(Nil, Dynamic)

pub fn main() {
  let assert Ok(Nil) =
    run_selected(
      [
        DatabaseTest,
        SafetyTest,
        WriterLockTest,
        PlanningGuardTest,
        IntakeGuardTest,
      ],
      [Verbose],
    )
  let assert Ok(Nil) =
    run_selected(
      [
        prompt_test.extracts_labelled_and_latest_prompt_blocks_test,
        prompt_test.ignores_non_text_fences_and_marks_partial_records_test,
        prompt_test.preserves_internal_newlines_but_trims_record_edges_test,
        prompt_test.accepts_crlf_and_trailing_fence_whitespace_without_normalizing_body_test,
        prompt_test.requires_unindented_fences_and_standalone_partial_suffix_test,
        prompt_test.sha256_is_lowercase_hex_over_exact_bytes_test,
      ],
      [Verbose],
    )
  io.println(
    "SELECTED_HERMETIC_CHECKS_ONLY: corpus materialization and historical prompt tests were not selected; no runtime admission.",
  )
}
