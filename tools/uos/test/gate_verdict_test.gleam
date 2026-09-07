import gleeunit/should
import main.{
  Checklist, Selfcheck15Cycles, SelfcheckInference, SelfcheckMirage,
  SelfcheckMirageMigration, SelfcheckMirageProd, SelfcheckMirageTenders,
  SelfcheckSaPlan, SelfcheckVfs, SelfcheckWave3Cycles, SelfcheckWave4Cycles,
  count_ok_lines, count_pass_lines, count_passed, exit_for, execute,
  inference_selfcheck_ok, last_line, sa_plan_suites, suite_ok, suite_pass_ok,
  summary_line, vfs_laws, wave3_records, wave4_records,
}

// --- pure verdict helpers -------------------------------------------------

pub fn exit_for_all_true_is_zero_test() {
  exit_for([True, True, True])
  |> should.equal(0)
}

pub fn exit_for_any_false_is_one_test() {
  exit_for([True, False, True])
  |> should.equal(1)
}

pub fn exit_for_empty_is_unrun_and_fails_closed_test() {
  exit_for([])
  |> should.equal(1)
}

pub fn count_passed_counts_only_true_test() {
  count_passed([True, False, True, False, False])
  |> should.equal(2)
}

pub fn summary_line_reports_ratio_and_verdict_test() {
  summary_line("Checks Passed", [True, True, False])
  |> should.equal("Summary: 2/3 Checks Passed (FAIL)")
  summary_line("Checks Passed", [True, True])
  |> should.equal("Summary: 2/2 Checks Passed (PASS)")
}

// --- inference selfcheck predicate ---------------------------------------

const green_fixture = "
[PASS] health           status=ok
[PASS] metrics          status=ok
[PASS] modalities       status=ok
[PASS] infer_text       status=ok
[PASS] infer_audio      status=ok
[PASS] infer_image      status=ok
[PASS] infer_video      status=ok
[PASS] embed            status=ok
[PASS] ast_anomaly      status=ok
[PASS] zk_transclude    status=ok
[PASS] lyapunov_trend   status=ok
[PASS] stpa_hazard      status=ok
[PASS] rete_conflict    status=ok
[PASS] ruliad_branch    status=ok
[PASS] shruti_harmonics status=ok
ALL 15 MODULAR MAX / MOJO INFERENCE METHODS VERIFIED 100% GREEN
"

pub fn inference_selfcheck_green_fixture_is_ok_test() {
  inference_selfcheck_ok(0, green_fixture)
  |> should.be_true
}

pub fn inference_selfcheck_nonzero_exit_is_not_ok_test() {
  inference_selfcheck_ok(1, green_fixture)
  |> should.be_false
}

pub fn inference_selfcheck_empty_output_is_not_ok_test() {
  inference_selfcheck_ok(0, "")
  |> should.be_false
}

pub fn inference_selfcheck_missing_final_line_is_not_ok_test() {
  inference_selfcheck_ok(0, "[PASS] a\n[PASS] b\n")
  |> should.be_false
}

// --- gates against the current repository state --------------------------

pub fn checklist_gate_returns_zero_on_current_tree_test() {
  execute(Checklist)
  |> should.equal(0)
}

pub fn fifteen_cycles_inventory_returns_zero_when_records_present_test() {
  execute(Selfcheck15Cycles)
  |> should.equal(0)
}

pub fn vfs_gate_fails_closed_while_law_08_is_unimplemented_test() {
  let laws = vfs_laws()
  laws
  |> list_length
  |> should.equal(8)
  // LAW-VFS-05 now has an observed predicate (owned bounded copies and
  // positional reads). LAW-VFS-08 (path jail) is not implemented in ZigVM, so
  // exactly seven laws observe true and the gate must fail closed.
  laws
  |> list_map_third
  |> count_passed
  |> should.equal(7)
  // The oracle suite adds a ninth, executed row; the gate still fails closed
  // on LAW-VFS-08 until ZigVM implements the jail.
  execute(SelfcheckVfs)
  |> should.equal(1)
}

fn list_map_third(items: List(#(String, String, Bool))) -> List(Bool) {
  case items {
    [] -> []
    [#(_, _, b), ..rest] -> [b, ..list_map_third(rest)]
  }
}

pub fn inference_gate_executes_worker_and_returns_zero_test() {
  execute(SelfcheckInference)
  |> should.equal(0)
}

fn list_length(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}


// --- sa-plan suite execution ---------------------------------------------------

pub fn count_ok_lines_counts_only_ok_prefixed_lines_test() {
  count_ok_lines("ok LAW A\nnot ok B\nok LAW C\n  ok indented\n")
  |> should.equal(2)
}

pub fn suite_ok_requires_zero_exit_and_law_floor_test() {
  suite_ok(0, "ok A\nok B\n", 2, "")
  |> should.be_true
  suite_ok(0, "ok A\n", 2, "")
  |> should.be_false
  suite_ok(1, "ok A\nok B\n", 2, "")
  |> should.be_false
}

pub fn suite_ok_prose_suite_requires_phrase_test() {
  suite_ok(0, "Workflow Durable Execution Completed Successfully.", 0, "Completed Successfully")
  |> should.be_true
  suite_ok(0, "", 0, "Completed Successfully")
  |> should.be_false
}

pub fn sa_plan_gate_executes_thirteen_suites_and_returns_zero_test() {
  sa_plan_suites()
  |> list_length
  |> should.equal(13)
  execute(SelfcheckSaPlan)
  |> should.equal(0)
}


// --- wave inventories -----------------------------------------------------------

pub fn wave_records_cover_ev_55_to_84_test() {
  wave3_records() |> list_length |> should.equal(15)
  wave4_records() |> list_length |> should.equal(15)
  // Every row names a distinct EV and a record path.
  wave3_records()
  |> list_all_third_nonempty
  |> should.be_true
  wave4_records()
  |> list_all_third_nonempty
  |> should.be_true
}

pub fn wave_gates_return_zero_when_every_record_present_test() {
  execute(SelfcheckWave3Cycles)
  |> should.equal(0)
  execute(SelfcheckWave4Cycles)
  |> should.equal(0)
}

// --- mirage suite predicates ------------------------------------------------------

pub fn count_pass_lines_counts_pass_markers_test() {
  count_pass_lines("  [PASS] a\nnoise\n  [PASS] b\n[FAIL] c\n")
  |> should.equal(2)
}

pub fn last_line_returns_terminal_verdict_test() {
  last_line("first\n=== deployment NOT_VERIFIED ===\n\n")
  |> should.equal("=== deployment NOT_VERIFIED ===")
  last_line("")
  |> should.equal("(no output)")
}

pub fn suite_pass_ok_requires_exit_count_and_phrase_test() {
  let out = "[PASS] a\n[PASS] b\nHost library checks passed\n"
  suite_pass_ok(0, out, 2, "Host library checks passed")
  |> should.be_true
  // wrong exit
  suite_pass_ok(1, out, 2, "Host library checks passed")
  |> should.be_false
  // too few PASS lines
  suite_pass_ok(0, out, 3, "Host library checks passed")
  |> should.be_false
  // terminal phrase absent
  suite_pass_ok(0, out, 2, "ALL CHECKS PASSED")
  |> should.be_false
}

pub fn mirage_gates_execute_their_suites_and_return_zero_test() {
  execute(SelfcheckMirage)
  |> should.equal(0)
  execute(SelfcheckMirageMigration)
  |> should.equal(0)
  execute(SelfcheckMirageProd)
  |> should.equal(0)
  execute(SelfcheckMirageTenders)
  |> should.equal(0)
}

fn list_all_third_nonempty(items: List(#(String, String, String))) -> Bool {
  case items {
    [] -> True
    [#(a, b, c), ..rest] ->
      a != "" && b != "" && c != "" && list_all_third_nonempty(rest)
  }
}
