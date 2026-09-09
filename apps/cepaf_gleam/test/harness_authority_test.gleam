import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process
import gleam/json
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile

fn binding() {
  dev.Binding("development", "plan", "task", "worker", 4, "session", 2)
}

pub fn coordinator_wait_must_age_task_authority_test() {
  let b = binding()
  dev.evaluate_task_window(
    b,
    "executing",
    "worker",
    4,
    75_000_000_000,
    0,
    0,
    70_000,
  )
  |> should.be_ok
  dev.evaluate_task_window(
    b,
    "executing",
    "worker",
    4,
    75_000_000_000,
    0,
    30_000_000_000,
    70_000,
  )
  |> should.be_error
  dev.evaluate_task_window(
    b,
    "executing",
    "worker",
    4,
    75_000_000_000,
    0,
    76_000_000_000,
    0,
  )
  |> should.be_error
}

pub fn post_effect_check_does_not_require_another_full_operation_window_test() {
  dev.evaluate_task_window(
    binding(),
    "executing",
    "worker",
    4,
    75_000_000_000,
    0,
    61_000_000_000,
    0,
  )
  |> should.be_ok
  dev.evaluate_task_window(
    binding(),
    "executing",
    "worker",
    4,
    75_000_000_000,
    0,
    75_000_000_000,
    0,
  )
  |> should.be_error
}

pub fn stale_worker_attempt_and_dependency_are_still_refused_test() {
  dev.evaluate_task_window(
    binding(),
    "executing",
    "other",
    4,
    90_000_000_000,
    0,
    0,
    0,
  )
  |> should.be_error
  dev.evaluate_task_window(
    binding(),
    "executing",
    "worker",
    5,
    90_000_000_000,
    0,
    0,
    0,
  )
  |> should.be_error
  dev.evaluate_task_window(
    binding(),
    "executing",
    "worker",
    4,
    90_000_000_000,
    1,
    0,
    0,
  )
  |> should.be_error
  dev.evaluate_task_window(
    binding(),
    "executing",
    "worker",
    4,
    90_000_000_000,
    0,
    0,
    -1,
  )
  |> should.be_error
}

pub fn dispatch_budget_uses_both_clock_domains_and_cleanup_reserve_test() {
  dev.lease_budget_ms(80_000_000_000, 80_000_000, 0, 0, 60_000)
  |> should.equal(Ok(60_000))
  dev.lease_budget_ms(80_000_000_000, 40_000_000, 0, 0, 60_000)
  |> should.equal(Ok(35_000))
  dev.lease_budget_ms(35_000_000_000, 80_000_000, 0, 0, 60_000)
  |> should.equal(Ok(30_000))
  dev.lease_budget_ms(
    80_000_000_000,
    80_000_000,
    30_000_000_000,
    30_000_000,
    60_000,
  )
  |> should.equal(Ok(45_000))
  dev.lease_budget_ms(5_000_000_000, 80_000_000, 0, 0, 60_000)
  |> should.be_error
  dev.lease_budget_ms(80_000_000_000, 5_000_000, 0, 0, 60_000)
  |> should.be_error
  dev.lease_budget_ms(80_000_000_000, 80_000_000, 0, 0, 60_001)
  |> should.be_error
}

pub fn bounded_observation_preserves_success_and_failure_test() {
  dev.bounded_observation(fn() { Ok("observed") }, 100)
  |> should.equal(Ok("observed"))
  dev.bounded_observation(fn() { Error("deliberate refusal") }, 100)
  |> should.equal(Error("deliberate refusal"))
}

pub fn delayed_observation_returns_no_effect_authority_test() {
  dev.bounded_observation(
    fn() {
      process.sleep(100)
      Ok("too late")
    },
    5,
  )
  |> should.equal(Error("coordinator_observation_timeout_no_effect_authority"))
  dev.bounded_observation(fn() { Ok("fresh") }, 100)
  |> should.equal(Ok("fresh"))
  dev.bounded_observation(fn() { Ok("must not run") }, 0) |> should.be_error
}

fn sources() {
  [dev.SourceDigest("public.gleam", files.digest("public fixture"))]
}

fn evidence(
  status: String,
  verification: String,
  manifest: List(dev.SourceDigest),
) {
  let signature =
    files.digest(
      "harness_test\n"
      <> json.to_string(
        json.object([
          #("intent_id", json.string("test-one")),
        ]),
      ),
    )
  json.object([
    #("schema", json.string("uos.harness-effect.v1")),
    #("intent_id", json.string("test-one")),
    #("tool", json.string("harness_test")),
    #("plan", json.string("plan")),
    #("task", json.string("task")),
    #("worker", json.string("worker")),
    #("attempt", json.int(4)),
    #("epoch", json.int(2)),
    #("signature", json.string(signature)),
    #("status", json.string(status)),
    #("verification", json.string(verification)),
    #("loaded_dispatch_module_md5", json.string("loaded-control")),
    #("source_manifest_scope", json.string("finite_harness_reviewed_inputs_v1")),
    #("source_manifest", dev.manifest_json(manifest)),
    #("source_manifest_sha256", json.string(dev.manifest_digest(manifest))),
    #("source_manifest_unchanged", json.bool(True)),
    #("observed_end", json.object([#("utc_us", json.string("123"))])),
  ])
  |> json.to_string
}

pub fn current_successful_evidence_is_accepted_test() {
  dev.validate_bootstrap_receipt(
    evidence("EXECUTED", "passed", sources()),
    binding(),
    "test-one",
    "harness_test",
    sources(),
    "loaded-control",
  )
  |> should.be_ok
}

pub fn failed_stale_or_wrong_identity_evidence_cannot_complete_test() {
  let success = evidence("EXECUTED", "passed", sources())
  dev.validate_bootstrap_receipt(
    evidence("FAILED_OR_UNVERIFIED", "failed", sources()),
    binding(),
    "test-one",
    "harness_test",
    sources(),
    "loaded-control",
  )
  |> should.be_error
  dev.validate_bootstrap_receipt(
    success,
    binding(),
    "test-one",
    "harness_test",
    [dev.SourceDigest("public.gleam", files.digest("changed"))],
    "loaded-control",
  )
  |> should.be_error
  dev.validate_bootstrap_receipt(
    success,
    binding(),
    "test-one",
    "harness_test",
    sources(),
    "old-control",
  )
  |> should.be_error
  dev.validate_bootstrap_receipt(
    success,
    binding(),
    "other",
    "harness_test",
    sources(),
    "loaded-control",
  )
  |> should.be_error
  dev.validate_bootstrap_receipt(
    success,
    binding(),
    "test-one",
    "harness_build",
    sources(),
    "loaded-control",
  )
  |> should.be_error
  dev.validate_bootstrap_receipt(
    success,
    dev.Binding(..binding(), attempt: 5),
    "test-one",
    "harness_test",
    sources(),
    "loaded-control",
  )
  |> should.be_error
  dev.validate_bootstrap_receipt(
    "broken JSON",
    binding(),
    "test-one",
    "harness_test",
    sources(),
    "loaded-control",
  )
  |> should.be_error
}

pub fn old_unbound_receipts_and_empty_manifests_are_not_completion_evidence_test() {
  dev.validate_bootstrap_receipt(
    "{\"status\":\"EXECUTED\"}",
    binding(),
    "test-one",
    "harness_test",
    sources(),
    "loaded-control",
  )
  |> should.be_error
  dev.validate_bootstrap_receipt(
    evidence("EXECUTED", "passed", []),
    binding(),
    "test-one",
    "harness_test",
    [],
    "loaded-control",
  )
  |> should.be_error
}

pub fn manifest_binds_path_bytes_and_order_test() {
  let first = dev.SourceDigest("a.gleam", files.digest("a"))
  let second = dev.SourceDigest("b.gleam", files.digest("b"))
  {
    dev.manifest_digest([first, second]) == dev.manifest_digest([second, first])
  }
  |> should.be_false
  {
    dev.manifest_digest([first])
    == dev.manifest_digest([dev.SourceDigest("other", first.sha256)])
  }
  |> should.be_false
  dev.bootstrap_source_paths()
  |> list.contains("apps/cepaf_gleam/src/cepaf_gleam/harness/peers.gleam")
  |> should.be_true
}

pub fn assessed_closure_inputs_do_not_grant_source_write_authority_test() {
  let readonly_input = "tools/lib/uos-toolchain.sh"
  dev.risk_input_allowed(readonly_input) |> should.be_true
  dev.source_allowed(readonly_input) |> should.be_false
  dev.document_allowed(readonly_input) |> should.be_false
  dev.risk_input_allowed("tools/unreviewed.ml") |> should.be_false
  dev.risk_input_allowed("var/sa-plan/uos.sqlite3") |> should.be_false
  dev.risk_input_allowed(".env") |> should.be_false
  dev.bootstrap_source_paths()
  |> list.contains(
    "governance/capability-inventory/20260909-0412-harness-feature-catalog.json",
  )
  |> should.be_true
}

fn terminal(expected: String) {
  dev.TaskRecord(
    "completed",
    Some("worker"),
    4,
    None,
    0,
    Some(expected),
    Some(123),
  )
}

pub fn lost_completion_reply_can_match_the_canonical_terminal_result_test() {
  let result = dev.completion_task_result("immutable prepared intent")
  dev.terminal_matches(binding(), terminal(result), result) |> should.be_true
  dev.terminal_matches(binding(), terminal("other task result"), result)
  |> should.be_false
  dev.terminal_matches(
    dev.Binding(..binding(), attempt: 5),
    terminal(result),
    result,
  )
  |> should.be_false
  dev.terminal_matches(
    binding(),
    dev.TaskRecord(..terminal(result), state: "executing"),
    result,
  )
  |> should.be_false
  dev.terminal_matches(
    binding(),
    dev.TaskRecord(..terminal(result), lease_until_ns: Some(999)),
    result,
  )
  |> should.be_false
  dev.terminal_matches(
    binding(),
    dev.TaskRecord(..terminal(result), completed_at_ns: None),
    result,
  )
  |> should.be_false
}

pub fn completion_request_requires_both_build_and_test_references_test() {
  dev.validate_arguments(
    "harness_finish",
    value.Object([#("journal_path", value.Text("journal"))]),
  )
  |> should.be_error
  dev.validate_arguments(
    "harness_finish",
    value.Object([
      #("journal_path", value.Text("journal")),
      #("build_intent_id", value.Text("build")),
      #("test_intent_id", value.Text("test")),
    ]),
  )
  |> should.be_ok
}

pub fn matching_visible_bytes_do_not_override_durability_failure_test() {
  dev.accept_existing_artifact("receipt", "receipt", Error("file_sync_failed"))
  |> should.equal(Error("file_sync_failed"))
  dev.accept_existing_artifact(
    "receipt",
    "receipt",
    Error("directory_sync_failed"),
  )
  |> should.equal(Error("directory_sync_failed"))
  dev.accept_existing_artifact("receipt", "receipt", Ok(Nil))
  |> should.equal(Ok(Nil))
  dev.accept_existing_artifact("receipt", "changed", Ok(Nil))
  |> should.equal(Error("artifact_bytes_changed"))
}

pub fn immutable_artifact_retry_resyncs_without_overwriting_bytes_test() {
  let base =
    "/tmp/uos-harness-authority-"
    <> { crypto.strong_random_bytes(12) |> bit_array.base16_encode }
  let assert Ok(_) = simplifile.create_directory(base)
  files.create(base, "receipt", "immutable receipt") |> should.equal(Ok(Nil))
  dev.verify_artifact_durability(base, "receipt", "immutable receipt")
  |> should.equal(Ok(Nil))
  dev.verify_artifact_durability(base, "receipt", "different receipt")
  |> should.equal(Error("artifact_bytes_changed"))
  files.read(base, "receipt") |> should.equal(Ok("immutable receipt"))
  let assert Ok(_) = simplifile.create_symlink("receipt", base <> "/alias")
  dev.verify_artifact_durability(base, "alias", "immutable receipt")
  |> should.equal(Error("regular_single_link_file_bound"))
  // Cleanup is limited to this newly allocated synthetic fixture directory.
  let assert Ok(_) = simplifile.delete(base)
}

pub fn journal_words_alone_are_not_valid_sections_test() {
  let titles = [
    "Scope & Trigger", "Pre-State Assessment", "Execution Detail",
    "Root Cause Analysis", "Fix Taxonomy", "Patterns & Anti-Patterns Discovered",
    "Verification Matrix", "Files Modified", "Architectural Observations",
    "Remaining Gaps", "Metrics Summary", "STAMP & Constitutional Alignment",
    "Conclusion",
  ]
  dev.journal_sections_valid(string.join(titles, " ")) |> should.be_false
  dev.journal_sections_valid("## 1. Scope & Trigger\n## 1. Scope & Trigger")
  |> should.be_false
  let valid = titles
    |> list.index_map(fn(title, index) { "## " <> int.to_string(index + 1) <> ". " <> title })
    |> string.join("\n")
  dev.journal_sections_valid(valid <> "\n## Comprehensive verification checklist")
  |> should.be_true
  dev.journal_sections_valid(valid <> "\n## Arbitrary unreviewed section")
  |> should.be_false
  dev.journal_sections_valid(valid <> "\n## Comprehensive verification checklist\n## Comprehensive verification checklist")
  |> should.be_false
}

pub fn unlisted_prefix_source_is_not_covered_by_manifest_or_write_grant_test() {
  dev.source_allowed("apps/cepaf_gleam/src/cepaf_gleam/harness/unlisted_escape.gleam")
  |> should.be_false
  dev.source_allowed("apps/cepaf_gleam/test/harness_unlisted_escape.gleam")
  |> should.be_false
  dev.source_allowed("apps/cepaf_gleam/src/cepaf_gleam/harness/tracking.gleam")
  |> should.be_true
}
