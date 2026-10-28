import cepaf_gleam/harness/admission as admission
import cepaf_gleam/harness/files
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/operations as operations
import cepaf_gleam/harness/planning_intents as planning
import cepaf_gleam/harness/successor_mcp
import cepaf_gleam/harness/value
import gleam/json
import gleam/erlang/process
import gleam/bit_array
import gleam/erlang/atom
import gleam/list
import gleam/int
import simplifile
import uos_swarm/session_store as store
import uos_swarm/session_sync as sync
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleeunit/should

@external(erlang, "session_sync_ffi", "unique_id")
fn unique_id() -> String

fn parsed(text: String) -> value.Value {
  case json.parse(text, value.decoder()) {
    Ok(value) -> value
    Error(_) -> value.Null
  }
}

fn fixture_rows() -> List(value.Value) {
  [
    parsed("{\"id\":\"A\",\"state\":\"completed\",\"worker\":\"worker-a\",\"attempt\":\"1\"}"),
    parsed("{\"id\":\"B\",\"state\":\"executing\",\"worker\":\"codex-worker\",\"attempt\":\"5\"}"),
  ]
}

fn fixture_assessment() -> List(value.Value) {
  [
    parsed("{\"plan_id\":\"uos/test\",\"task_id\":\"A\",\"task_state\":\"completed\",\"actor\":\"worker-a\"}"),
    parsed("{\"plan_id\":\"uos/test\",\"task_id\":\"B\",\"task_state\":\"executing\",\"actor\":\"codex-worker\"}"),
  ]
}


fn seed_scope_with_reads(reads: List(String)) -> admission.Scope {
  admission.Scope(
    "uos/test/assessment-seed",
    "COMMAND_ACCEPT",
    reads,
    [],
    ["apps/cepaf_gleam/test/harness_pre_attach_assessment_test.gleam"],
    ["harness_pre_attach_assessment_test"],
    "var/harness/20261028-1017-assessment-seed-current-risk.json",
    [],
    [],
  )
}

fn seed_document(plan: String, task: String, path: String, sha256: String) -> value.Value {
  parsed(
    "{\"candidate_binding\":{\"assessment_seed\":{\"plan\":\""
    <> plan
    <> "\",\"task\":\""
    <> task
    <> "\",\"path\":\""
    <> path
    <> "\",\"sha256\":\""
    <> sha256
    <> "\"}}}",
  )
}


pub fn ecology_ffi_control_id_is_required_and_revision_bound_test() {
  admission.control_modules |> list.length |> should.equal(26)
  admission.control_modules
  |> list.contains("ecology_capability_ffi")
  |> should.be_true
  let actual = admission.control_ids()
  let recorded = case json.parse(json.to_string(actual), value.decoder()) {
    Ok(value) -> value
    Error(_) -> value.Null
  }
  admission.control_ids_match(recorded, actual) |> should.be_true
  let missing = case recorded {
    value.Object(fields) ->
      value.Object(list.filter(fields, fn(field) {
        field.0 != "ecology_capability_ffi"
      }))
    _ -> value.Null
  }
  admission.control_ids_match(missing, actual) |> should.be_false
  admission.control_ids_match(
    value.set(recorded, "ecology_capability_ffi", value.Text("changed")),
    actual,
  )
  |> should.be_false
}

pub fn assessment_seed_binding_is_exactly_scoped_and_digest_bound_test() {
  let path = "docs/plans/20261028-1017-assessment-seed.json"
  let sha256 = string.repeat("a", 64)
  let scope = seed_scope_with_reads([path])
  let document = seed_document(scope.plan, scope.task, path, sha256)
  operations.assessment_seed_binding(document, scope)
  |> should.equal(Ok(#(path, sha256)))

  operations.assessment_seed_binding(parsed("{}"), scope)
  |> should.be_error
  operations.assessment_seed_binding(
    seed_document("uos/test/other", scope.task, path, sha256),
    scope,
  )
  |> should.be_error
  operations.assessment_seed_binding(
    seed_document(scope.plan, "OTHER_TASK", path, sha256),
    scope,
  )
  |> should.be_error
  operations.assessment_seed_binding(document, seed_scope_with_reads([]))
  |> should.be_error
  operations.assessment_seed_binding(
    seed_document(scope.plan, scope.task, scope.portfolio, sha256),
    scope,
  )
  |> should.be_error
  operations.assessment_seed_binding(
    seed_document(scope.plan, scope.task, path, "bad"),
    scope,
  )
  |> should.be_error
}

pub fn assessment_seed_digest_rejects_changed_immutable_bytes_test() {
  let bytes = "[]"
  let digest = files.digest(bytes)
  operations.assessment_seed_digest_matches(digest, bytes)
  |> should.be_true
  operations.assessment_seed_digest_matches(
    string.repeat("a", 64),
    bytes,
  )
  |> should.be_false
}

pub fn missing_portfolio_requires_a_verified_seed_test() {
  let path = "docs/plans/20261028-1017-assessment-seed.json"
  let sha256 = string.repeat("b", 64)
  let scope = seed_scope_with_reads([path])
  let bound = operations.assessment_seed_binding(
    seed_document(scope.plan, scope.task, path, sha256),
    scope,
  )
  |> result.map(fn(_) { "verified seed bytes" })
  operations.initial_portfolio_before(bound, None)
  |> should.be_ok
  operations.initial_portfolio_before(
    Error("assessment_seed_binding_missing"),
    None,
  )
  |> should.be_error
  operations.initial_portfolio_before(bound, Some("[]"))
  |> should.be_ok
}


pub fn task_list_parser_ignores_only_pipeline_diagnostic_test() {
  let raw = "{\"id\":\"A\",\"state\":\"completed\",\"worker\":\"worker-a\"}
sa-plan-pipeline {\"request_id\":\"r1\"}"
  operations.initial_plan_rows(raw)
  |> should.be_ok
  operations.initial_plan_rows(raw <> "
unexpected")
  |> should.be_error
}

pub fn canonical_row_match_requires_exact_unique_task_set_test() {
  operations.initial_rows_match(
    fixture_assessment(),
    fixture_rows(),
    fixture_assessment(),
    "uos/test",
  )
  |> should.be_ok
  let duplicated = list.append(fixture_rows(), [parsed("{\"id\":\"B\",\"state\":\"executing\",\"worker\":\"codex-worker\",\"attempt\":\"5\"}")])
  operations.initial_rows_match(
    fixture_assessment(),
    duplicated,
    fixture_assessment(),
    "uos/test",
  )
  |> should.be_error
  operations.initial_rows_match(
    [parsed("{\"plan_id\":\"uos/test\",\"task_id\":\"A\",\"task_state\":\"completed\",\"actor\":\"worker-a\"}")],
    fixture_rows(),
    fixture_assessment(),
    "uos/test",
  )
  |> should.be_error
}

pub fn canonical_state_and_actor_mismatch_refused_test() {
  let bad_state = [
    parsed("{\"plan_id\":\"uos/test\",\"task_id\":\"A\",\"task_state\":\"available\",\"actor\":\"worker-a\"}"),
    ..fixture_assessment(),
  ]
  operations.initial_rows_match(
    bad_state,
    fixture_rows(),
    fixture_assessment(),
    "uos/test",
  )
  |> should.be_error
  let bad_actor = [
    parsed("{\"plan_id\":\"uos/test\",\"task_id\":\"A\",\"task_state\":\"completed\",\"actor\":\"someone-else\"}"),
    parsed("{\"plan_id\":\"uos/test\",\"task_id\":\"B\",\"task_state\":\"executing\",\"actor\":\"codex-worker\"}"),
  ]
  operations.initial_rows_match(
    bad_actor,
    fixture_rows(),
    fixture_assessment(),
    "uos/test",
  )
  |> should.be_error
}

pub fn observational_refresh_preserves_raw_judgments_test() {
  let baseline = "[{\"plan_id\":\"uos/test\",\"task_id\":\"A\",\"actor\":\"old\",\"task_state\":\"available\",\"observed_at\":\"old\",\"score\":12,\"fmea_modes\":[{\"risk\":4}],\"snapshot\":{\"kind\":\"working_tree\",\"opaque\":\"guarded\",\"reference\":\"same\",\"evidence\":[{\"path\":\"AGENTS.md\",\"sha256\":\"old\",\"observed_at\":\"old\"}]}}]"
  let refreshed = "[{\"plan_id\":\"uos/test\",\"task_id\":\"A\",\"actor\":\"new\",\"task_state\":\"available\",\"observed_at\":\"new\",\"score\":12,\"fmea_modes\":[{\"risk\":4}],\"snapshot\":{\"kind\":\"working_tree\",\"opaque\":\"guarded\",\"reference\":\"same\",\"evidence\":[{\"path\":\"AGENTS.md\",\"sha256\":\"new\",\"observed_at\":\"new\"}]}}]"
  operations.judgments_match(baseline, refreshed) |> should.be_ok
  let changed_score = string.replace(refreshed, "\"score\":12", "\"score\":99")
  operations.judgments_match(baseline, changed_score) |> should.be_error
  let changed_path = string.replace(refreshed, "AGENTS.md", "other.md")
  operations.judgments_match(baseline, changed_path) |> should.be_error
  let changed_reference = string.replace(refreshed, "same", "different")
  operations.judgments_match(baseline, changed_reference) |> should.be_error
  let changed_unknown = string.replace(refreshed, "\"opaque\":\"guarded\"", "\"opaque\":\"changed\"")
  operations.judgments_match(baseline, changed_unknown) |> should.be_error
}

pub fn initial_assessment_dispatches_without_execution_context_test() {
  let grant = admission.Grant(
    "fixture",
    "fixture.json",
    "digest",
    "session",
    "codex-worker",
    "host",
    "boot",
    0,
    [],
    "/fixture",
    "review.json",
    "review-digest",
  )
  let state = successor_mcp.initial(grant)
  let initialize = "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\",\"params\":{}}"
  let #(ready, _) = successor_mcp.handle(state, initialize)
  let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"harness_assess\",\"arguments\":{\"intent_id\":\"pre-attach\",\"assessment_json\":\"[]\",\"reason\":\"bounded test reason\"}}}"
  let #(_, reply) = successor_mcp.handle(ready, request)
  case reply {
    Some(text) -> {
      string.contains(text, "pre_attach_assessment_requires_unique_scope")
      |> should.be_true
      string.contains(text, "current_task_required") |> should.be_false
    }
    _ -> should.fail()
  }
}


pub fn pre_attach_assessment_replay_classification_is_fail_closed_test() {
  operations.assessment_replay_state(Some("before"), Some("before"), "after")
  |> should.equal(operations.AssessmentBeforeStillPresent)
  operations.assessment_replay_state(None, None, "after")
  |> should.equal(operations.AssessmentBeforeStillPresent)
  operations.assessment_replay_state(Some("before"), Some("after"), "after")
  |> should.equal(operations.AssessmentPostconditionObserved)
  operations.assessment_replay_state(Some("after"), Some("after"), "after")
  |> should.equal(operations.AssessmentNoChange)
  operations.assessment_replay_state(Some("before"), Some("diverged"), "after")
  |> should.equal(operations.AssessmentDiverged)
}

pub fn pre_attach_assessment_signature_binds_stable_request_test() {
  let base = operations.assessment_request_signature(
    "grant", "worker", "plan", "task", "target",
    "seed.json", "seed-sha", "intent", "body-sha", "reason-sha",
  )
  let replay = operations.assessment_request_signature(
    "grant", "worker", "plan", "task", "target",
    "seed.json", "seed-sha", "intent", "body-sha", "reason-sha",
  )
  let changed_body = operations.assessment_request_signature(
    "grant", "worker", "plan", "task", "target",
    "seed.json", "seed-sha", "intent", "other-body-sha", "reason-sha",
  )
  let changed_seed = operations.assessment_request_signature(
    "grant", "worker", "plan", "task", "target",
    "seed.json", "other-seed-sha", "intent", "body-sha", "reason-sha",
  )
  should.equal(base, replay)
  should.equal(base == changed_body, False)
  should.equal(base == changed_seed, False)
}


pub fn pre_attach_assessment_pending_latch_is_target_scoped_test() {
  let digest = string.repeat("a", 64)
  let prepared = parsed(
    "{\"schema\":\"uos.harness-pre-attach-assessment-ledger.v1\",\"state\":\"PREPARED\",\"request_signature\":\""
    <> digest
    <> "\",\"grant_sha256\":\""
    <> digest
    <> "\",\"plan\":\"plan\",\"task\":\"task\",\"portfolio_path\":\"portfolio.json\",\"intent_id\":\"intent\",\"body_sha256\":\""
    <> digest
    <> "\",\"reason_sha256\":\""
    <> digest
    <> "\",\"seed_sha256\":\""
    <> digest
    <> "\",\"before_state\":\"ABSENT\",\"before_sha256\":\"ABSENT\"}",
  )
  operations.assessment_pending_state(
    prepared, False, "plan", "task", "portfolio.json",
  ) |> should.equal(Ok(True))
  operations.assessment_pending_state(
    prepared, True, "plan", "task", "portfolio.json",
  ) |> should.equal(Ok(False))
  operations.assessment_pending_state(
    prepared, False, "plan", "other-task", "portfolio.json",
  ) |> should.equal(Ok(False))
  operations.assessment_pending_state(
    parsed("{\"schema\":\"unknown\",\"state\":\"PREPARED\"}"),
    False,
    "plan",
    "task",
    "portfolio.json",
  ) |> should.be_error
}

pub fn assessment_ledger_candidate_scan_is_bounded_test() {
  operations.assessment_ledger_candidates([
    "target-old-assessment-ledger.json",
    "other-assessment-ledger.json",
    "unrelated.txt",
  ], "target-")
  |> should.equal(Ok(["target-old-assessment-ledger.json"]))
  operations.assessment_ledger_candidates(
    repeated_ledger_names(129),
    "target-",
  )
  |> should.be_error
}

fn repeated_ledger_names(remaining: Int) -> List(String) {
  case remaining <= 0 {
    True -> []
    False -> [
      "target-candidate-assessment-ledger.json",
      ..repeated_ledger_names(remaining - 1)
    ]
  }
}

pub fn assessment_ledger_candidates_bound_directory_size_before_records_test() {
  operations.assessment_ledger_candidates(
    repeated_unrelated_ledger_names(8193),
    "target-",
  )
  |> should.be_error
}

fn repeated_unrelated_ledger_names(remaining: Int) -> List(String) {
  case remaining <= 0 {
    True -> []
    False -> ["unrelated.txt", ..repeated_unrelated_ledger_names(remaining - 1)]
  }
}

pub fn attached_and_initial_assessment_share_one_portfolio_lock_test() {
  let target = "var/harness/test-current-risk.json"
  admission.assessment_lock_path_for("/canonical", target)
  |> should.equal(operations.assessment_lock_path_for("/canonical", target))
  admission.assessment_lock_path_for("/other-root", target)
  |> should.not_equal(operations.assessment_lock_path_for("/canonical", target))
}

pub fn assessment_target_directory_shares_portfolio_lock_namespace_test() {
  let first = operations.assessment_target_directory_for(
    "/canonical",
    "plan",
    "task",
    "portfolio",
  )
  operations.assessment_target_directory_for(
    "/canonical",
    "plan",
    "task",
    "portfolio",
  )
  |> should.equal(first)
  operations.assessment_target_directory_for(
    "/other-root",
    "plan",
    "task",
    "portfolio",
  )
  |> should.not_equal(first)
  operations.assessment_target_directory_for(
    "/canonical",
    "other-plan",
    "other-task",
    "portfolio",
  )
  |> should.equal(first)
}

pub fn task_effect_index_candidates_are_bounded_and_typed_test() {
  operations.task_effect_index_candidates([
    "grant@intent@intent.index.json",
    "grant@finish@completion-intent.index.json",
    "unrelated.json",
  ])
  |> should.equal(Ok([
    "grant@intent@intent.index.json",
    "grant@finish@completion-intent.index.json",
  ]))
  operations.task_effect_index_candidates(repeated_index_names(257))
  |> should.be_error
}

fn repeated_index_names(remaining: Int) -> List(String) {
  case remaining <= 0 {
    True -> []
    False -> [
      "g@i@intent.index.json",
      ..repeated_index_names(remaining - 1)
    ]
  }
}

pub fn task_effect_index_binding_is_exact_and_receipt_hash_bound_test() {
  let grant_sha = string.repeat("a", 64)
  let prepared_sha = string.repeat("b", 64)
  let pointer = value.Object([
    #("schema", value.Text("uos.harness-task-effect-index.v1")),
    #("plan", value.Text("plan")),
    #("task", value.Text("task")),
    #("grant_id", value.Text("grant")),
    #("grant_sha256", value.Text(grant_sha)),
    #("worker", value.Text("worker")),
    #("attempt", value.Integer(7)),
    #("intent_id", value.Text("intent")),
    #("suffix", value.Text("intent")),
    #("kind", value.Text("effect_intent")),
    #(
      "record_path",
      value.Text(operations.effect_path_for("grant", "intent", "intent")),
    ),
    #("prepared_sha256", value.Text(prepared_sha)),
  ])
  operations.task_effect_index_matches(
    pointer,
    "plan",
    "task",
    "grant",
    grant_sha,
    "worker",
    7,
    "intent",
    "intent",
    "effect_intent",
    prepared_sha,
  )
  |> should.be_true
  operations.task_effect_index_matches(
    pointer,
    "plan",
    "other-task",
    "grant",
    grant_sha,
    "worker",
    7,
    "intent",
    "intent",
    "effect_intent",
    prepared_sha,
  )
  |> should.be_false
  operations.task_effect_index_matches(
    pointer,
    "plan",
    "task",
    "grant",
    grant_sha,
    "worker",
    7,
    "intent",
    "intent",
    "effect_intent",
    string.repeat("c", 64),
  )
  |> should.be_false
}

pub fn task_intent_candidates_are_bounded_and_include_existing_record_kinds_test() {
  operations.task_intent_candidates([
    "grant-a@write-one@intent.json",
    "grant-b@finish-one@completion-intent.json",
    "grant-c@done@result.json",
  ])
  |> should.equal(Ok([
    "grant-a@write-one@intent.json",
    "grant-b@finish-one@completion-intent.json",
  ]))
  operations.task_intent_candidates(repeated_task_intent_names(309))
  |> result.is_ok
  |> should.be_true
  operations.task_intent_candidates(repeated_unrelated_names(4097))
  |> should.be_error
}

fn repeated_task_intent_names(remaining: Int) -> List(String) {
  case remaining <= 0 {
    True -> []
    False -> [
      "grant-a@write-one@intent.json",
      ..repeated_task_intent_names(remaining - 1)
    ]
  }
}

fn repeated_unrelated_names(remaining: Int) -> List(String) {
  case remaining <= 0 {
    True -> []
    False -> ["unrelated.txt", ..repeated_unrelated_names(remaining - 1)]
  }
}

pub fn assessment_lock_is_target_and_request_bound_test() {
  let same = operations.assessment_lock_path_for("/canonical", "var/risk.json")
  let other_target = operations.assessment_lock_path_for("/canonical", "var/other.json")
  let other_root = operations.assessment_lock_path_for("/candidate", "var/risk.json")
  should.equal(same == other_target, False)
  should.equal(same == other_root, False)
  should.equal(
    same,
    operations.assessment_lock_path_for("/canonical", "var/risk.json"),
  )

  let digest = string.repeat("a", 64)
  let signature = string.repeat("b", 64)
  let record = parsed(json.object([
    #("schema", json.string("uos.harness-assessment-path-lock.v1")),
    #("state", json.string("HELD")),
    #("canonical_root", json.string(dev.root)),
    #("portfolio_path", json.string("var/risk.json")),
    #("plan", json.string("uos/test")),
    #("task", json.string("TASK")),
    #("grant_sha256", json.string(digest)),
    #("worker", json.string("codex-test")),
    #("intent_id", json.string("lock-intent")),
    #("request_signature", json.string(signature)),
  ]) |> json.to_string)
  operations.assessment_lock_matches(
    record,
    digest,
    "uos/test",
    "TASK",
    "var/risk.json",
    "codex-test",
    "lock-intent",
    signature,
  )
  |> should.be_true
  operations.assessment_lock_matches(
    record,
    digest,
    "uos/test",
    "TASK",
    "var/risk.json",
    "codex-test",
    "other-intent",
    signature,
  )
  |> should.be_false
}

fn valid_assessment_terminal(signature: String, artifact_sha: String, target_sha: String) -> value.Value {
  let terminal_at = json.object([
    #("utc", json.string("2026-10-28T13:04:00.000000Z")),
    #("utc_us", json.string("1793192640000000")),
    #("boot_us", json.string("2461452640000")),
    #("host_id", json.string("host-id")),
    #("boot_id", json.string("boot-id")),
    #("offset_us", json.int(-100)),
    #("uncertainty_us", json.int(100)),
    #("reference_age_us", json.int(100000)),
    #("receipt_age_us", json.int(1000)),
    #("delivery_us", json.int(100)),
    #("source", json.string("chronyc:-c-tracking:reference-utc")),
    #("reference_max_age_us", json.int(3600000000)),
    #("sample_max_delivery_us", json.int(3000000)),
    #("authority", json.string("OBSERVATION_ONLY")),
  ])
  let receipt = json.object([
    #("status", json.string("PASS")),
    #("assessment_path", json.string("var/harness/G-intent-assessment.json")),
    #("assessment_sha256", json.string(artifact_sha)),
    #("portfolio_path", json.string("portfolio.json")),
    #("portfolio_sha256", json.string(target_sha)),
  ])
  json.object([
    #("schema", json.string("uos.harness-pre-attach-assessment-terminal.v1")),
    #("state", json.string("TERMINAL")),
    #("request_signature", json.string(signature)),
    #("terminal_at", terminal_at),
    #("receipt", receipt),
  ])
  |> json.to_string
  |> parsed
}

pub fn assessment_terminal_requires_exact_typed_binding_test() {
  let signature = string.repeat("b", 64)
  let artifact_sha = string.repeat("a", 64)
  let target_sha = string.repeat("c", 64)
  let valid = valid_assessment_terminal(signature, artifact_sha, target_sha)
  operations.assessment_terminal_valid(valid, signature, "host-id", "boot-id")
  |> should.be_true
  operations.assessment_terminal_valid(valid, string.repeat("d", 64), "host-id", "boot-id")
  |> should.be_false
  operations.assessment_terminal_valid(valid, signature, "other-host", "boot-id")
  |> should.be_false
  operations.assessment_terminal_valid(
    value.set(valid, "terminal_at", parsed("{}")),
    signature,
    "host-id",
    "boot-id",
  )
  |> should.be_false

  operations.assessment_terminal_matches(
    valid,
    signature,
    "var/harness/G-intent-assessment.json",
    artifact_sha,
    "portfolio.json",
    target_sha,
    "host-id",
    "boot-id",
  )
  |> should.be_true
  operations.assessment_terminal_matches(
    valid,
    signature,
    "var/harness/other-assessment.json",
    artifact_sha,
    "portfolio.json",
    target_sha,
    "host-id",
    "boot-id",
  )
  |> should.be_false
  operations.assessment_terminal_matches(
    valid,
    signature,
    "var/harness/G-intent-assessment.json",
    string.repeat("e", 64),
    "portfolio.json",
    target_sha,
    "host-id",
    "boot-id",
  )
  |> should.be_false
  operations.assessment_terminal_matches(
    valid,
    signature,
    "var/harness/G-intent-assessment.json",
    artifact_sha,
    "other-portfolio.json",
    target_sha,
    "host-id",
    "boot-id",
  )
  |> should.be_false
  operations.assessment_terminal_matches(
    valid,
    signature,
    "var/harness/G-intent-assessment.json",
    artifact_sha,
    "portfolio.json",
    string.repeat("f", 64),
    "host-id",
    "boot-id",
  )
  |> should.be_false
}

pub fn attached_mutation_names_require_assessment_stop_line_test() {
  successor_mcp.assessment_guard_required("harness_claim") |> should.be_true
  successor_mcp.assessment_guard_required("harness_attach") |> should.be_true
  successor_mcp.assessment_guard_required("harness_write_file") |> should.be_true
  successor_mcp.assessment_guard_required("harness_build") |> should.be_true
  successor_mcp.assessment_guard_required("harness_test") |> should.be_true
  successor_mcp.assessment_guard_required("harness_finish") |> should.be_true
  successor_mcp.assessment_guard_required("harness_release") |> should.be_true
  successor_mcp.assessment_guard_required("harness_client_mcp_config")
  |> should.be_true
  successor_mcp.assessment_guard_required("harness_read_file")
  |> should.be_false
  successor_mcp.assessment_guard_required("harness_reconcile")
  |> should.be_false
}
pub fn pending_effect_reconcile_requires_exact_unsettled_intent_test() {
  let digest = string.repeat("a", 64)
  let prepared_json =
    "{\"schema\":\"uos.harness-successor-effect.v1\",\"status\":\"PREPARED\",\"kind\":\"effect_intent\",\"intent_id\":\"write-1\",\"signature\":\""
    <> digest
    <> "\",\"execution\":{\"grant_sha256\":\""
    <> digest
    <> "\",\"plan\":\"plan\",\"task\":\"task\",\"worker\":\"worker\",\"attempt\":7}}"
  let prepared = parsed(prepared_json)
  operations.pending_effect_record_matches(
    prepared, digest, "plan", "task", "worker", 7, "write-1",
  ) |> should.be_true
  operations.pending_effect_record_matches(
    prepared, digest, "plan", "task", "worker", 7, "write-2",
  ) |> should.be_false
  operations.pending_effect_record_matches(
    prepared, digest, "plan", "task", "worker", 8, "write-1",
  ) |> should.be_true
  operations.pending_effect_record_matches(
    prepared, digest, "plan", "task", "worker", 6, "write-1",
  ) |> should.be_false
  let settled = string.replace(prepared_json, "\"PREPARED\"", "\"EXECUTED\"")
  operations.pending_effect_record_matches(
    parsed(settled), digest, "plan", "task", "worker", 7, "write-1",
  ) |> should.be_false
}

pub fn known_no_effect_refusal_is_narrowly_classified_test() {
  operations.known_no_effect_refusal(
    "FAILED_OR_UNVERIFIED",
    "harness_write_file",
    "source_digest_conflict",
  )
  |> should.be_true
  operations.known_no_effect_refusal(
    "FAILED_OR_UNVERIFIED",
    "harness_build",
    "source_digest_conflict",
  )
  |> should.be_false
  operations.known_no_effect_refusal(
    "FAILED_OR_UNVERIFIED",
    "harness_write_file",
    "scope_changed_during_effect",
  )
  |> should.be_false
  operations.known_no_effect_refusal(
    "EXECUTED",
    "harness_write_file",
    "source_digest_conflict",
  )
  |> should.be_false
}

pub fn effect_resolution_binds_prepared_and_failed_result_hashes_test() {
  let signature = string.repeat("a", 64)
  let prepared_raw = json.to_string(json.object([
    #("schema", json.string("uos.harness-successor-effect.v1")),
    #("kind", json.string("effect_intent")),
    #("intent_id", json.string("write-1")),
    #("signature", json.string(signature)),
    #("tool", json.string("harness_write_file")),
    #("input_sha256", json.string("input")),
    #("execution", json.object([
      #("plan", json.string("plan")),
      #("task", json.string("task")),
      #("grant_sha256", json.string(signature)),
      #("worker", json.string("worker")),
      #("attempt", json.int(7)),
    ])),
  ]))
  let result_raw = json.to_string(json.object([
    #("schema", json.string("uos.harness-successor-effect.v1")),
    #("kind", json.string("effect_result")),
    #("intent_id", json.string("write-1")),
    #("signature", json.string(signature)),
    #("tool", json.string("harness_write_file")),
    #("input_sha256", json.string("input")),
    #("status", json.string("FAILED_OR_UNVERIFIED")),
    #("failure", json.string("source_digest_conflict")),
    #("execution", json.object([
      #("plan", json.string("plan")),
      #("task", json.string("task")),
      #("grant_sha256", json.string(signature)),
      #("worker", json.string("worker")),
      #("attempt", json.int(7)),
    ])),
  ]))
  let resolution = parsed(json.object([
    #("schema", json.string("uos.harness-effect-resolution.v1")),
    #("state", json.string("KNOWN_NOT_APPLIED")),
    #("intent_id", json.string("write-1")),
    #("plan", json.string("plan")),
    #("task", json.string("task")),
    #("request_signature", json.string(signature)),
    #("prepared_sha256", json.string(files.digest(prepared_raw))),
    #("result_sha256", json.string(files.digest(result_raw))),
    #("reason", json.string("source_digest_conflict")),
    #("attribution", json.string("KNOWN_NOT_APPLIED")),
  ]) |> json.to_string)
  operations.effect_resolution_matches(
    resolution,
    prepared_raw,
    result_raw,
    "plan",
    "task",
    "write-1",
    signature,
  )
  |> should.be_true
  operations.effect_resolution_matches(
    resolution,
    prepared_raw,
    result_raw <> " ",
    "plan",
    "task",
    "write-1",
    signature,
  )
  |> should.be_false
}

pub fn pending_completion_reconcile_requires_exact_task_identity_test() {
  let digest = string.repeat("b", 64)
  let prepared = parsed(
    "{\"schema\":\"uos.harness-successor-completion.v1\",\"kind\":\"completion_intent\",\"intent_id\":\"finish-1\",\"execution\":{\"grant_sha256\":\""
    <> digest
    <> "\",\"plan\":\"plan\",\"task\":\"task\",\"worker\":\"worker\",\"attempt\":7}}",
  )
  operations.pending_completion_record_matches(
    prepared, digest, "plan", "task", "worker", 7, "finish-1",
  ) |> should.be_true
  operations.pending_completion_record_matches(
    prepared, digest, "plan", "other-task", "worker", 7, "finish-1",
  ) |> should.be_false
}

pub fn engine_ml_and_mli_paths_are_explicit_public_sources_test() {
  admission.public_path("engines/hermes/fixtures/sample.ml") |> should.be_true
  admission.public_path("engines/hermes/fixtures/sample.mli") |> should.be_true
  admission.public_path("engines/.hidden/sample.ml") |> should.be_false
  admission.public_path("engines/hermes/credentials.ml") |> should.be_false

  let base = admission.Scope(
    "uos/test/engine-source",
    "COMMAND_ACCEPT",
    [],
    ["engines/hermes/fixtures/sample.ml"],
    ["engines/hermes/fixtures/sample.ml"],
    ["harness_pre_attach_assessment_test"],
    "var/harness/20261028-1017-assessment-seed-current-risk.json",
    [],
    [],
  )
  admission.scope_valid(base) |> should.be_true
  admission.scope_valid(admission.Scope(
    ..base,
    writes: ["engines/hermes/fixtures/sample.mli"],
  )) |> should.be_false
  admission.scope_valid(admission.Scope(
    ..base,
    writes: ["engines/hermes/fixtures/sample.exe"],
    sources: ["engines/hermes/fixtures/sample.exe"],
  )) |> should.be_false
  admission.scope_valid(admission.Scope(
    ..base,
    writes: ["engines/hermes/fixtures/sample.mli"],
    sources: ["engines/hermes/fixtures/sample.ml"],
  )) |> should.be_false
}

pub fn engine_ml_and_mli_private_fixture_cas_write_and_readback_test() {
  let scratch = "/tmp/uos-assessment-engine-source-tests"
  let _ = simplifile.create_directory_all(scratch)
  let id = unique_id()
  let root = scratch <> "/root-" <> id
  let db = scratch <> "/coord-" <> id <> ".sqlite3"
  let assert Ok(Nil) = simplifile.create_directory_all(
    root <> "/engines/hermes/fixtures",
  )
  let assert Ok(opened) = store.open(db)
  let assert Ok(_) = store.append(
    opened,
    sync.Register("engine-source-session", "codex", root, "test-revision", []),
    "register-" <> id,
  )
  let assert Ok(_) = store.append(
    opened,
    sync.Heartbeat("engine-source-session", "test-revision", []),
    "heartbeat-" <> id,
  )
  let assert Ok(#(claim, False)) = store.append(
    opened,
    sync.Claim("engine-source-session", "task:engine-source", 60000000),
    "claim-" <> id,
  )
  let assert Ok(Nil) = store.close(opened)

  let ml = "engines/hermes/fixtures/sample.ml"
  let mli = "engines/hermes/fixtures/sample.mli"
  let ml_body = "let value = 7\n"
  let mli_body = "val value : int\n"
  operations.write_file_with_cas_at(
    db,
    "engine-source-session",
    "task:engine-source",
    claim.epoch,
    "test-grant",
    "write-ml-" <> id,
    root,
    ml,
    ml_body,
    "ABSENT",
  )
  |> should.equal(Ok(files.digest(ml_body)))
  operations.write_file_with_cas_at(
    db,
    "engine-source-session",
    "task:engine-source",
    claim.epoch,
    "test-grant",
    "write-mli-" <> id,
    root,
    mli,
    mli_body,
    "ABSENT",
  )
  |> should.equal(Ok(files.digest(mli_body)))
  files.read(root, ml) |> should.equal(Ok(ml_body))
  files.read(root, mli) |> should.equal(Ok(mli_body))
}


@external(erlang, "os", "getpid")
fn os_pid_codepoints() -> List(Int)

@external(erlang, "erlang", "list_to_binary")
fn charlist_binary(chars: List(Int)) -> BitArray

@external(erlang, "code", "which")
fn module_beam_path(module: atom.Atom) -> List(Int)

fn current_candidate_root() -> String {
  let beam =
    atom.create("harness_pre_attach_assessment_test")
    |> module_beam_path
    |> charlist_binary
    |> bit_array.to_string
    |> result.unwrap("")
  case string.split(beam, "/apps/cepaf_gleam/build/dev/erlang/") {
    [root, ..] -> root
    _ -> ""
  }
}

fn os_pid_text() -> String {
  os_pid_codepoints()
  |> charlist_binary
  |> bit_array.to_string
  |> result.unwrap("pid-unavailable")
}

fn child_erl_args(eval: String) -> List(String) {
  [
    "+S", "2:2", "+A", "2", "-noinput", "-noshell",
    "-eval",
    "C=\"" <> current_candidate_root() <> "\","
    <> "code:set_path(filelib:wildcard(C++\"/apps/cepaf_gleam/build/dev/erlang/*/ebin\")++code:get_path()),"
    <> eval,
  ]
}
fn worker_eval(root: String, database: String, portfolio: String, barrier: String, name: String) -> String {
  "case harness_pre_attach_assessment_test:assessment_lock_os_worker("
  <> "list_to_binary(\"" <> root <> "\"),"
  <> "list_to_binary(\"" <> database <> "\"),"
  <> "list_to_binary(\"" <> portfolio <> "\"),"
  <> "list_to_binary(\"" <> barrier <> "\"),"
  <> "list_to_binary(\"" <> name <> "\")"
  <> ") of {ok,_}->halt(0); {error,_}->halt(2) end."
}
fn run_os_worker(root: String, database: String, barrier: String, name: String) -> Result(String, String) {
  let eval = worker_eval(root, database, "var/assessment.json", barrier, name)
  dev.bounded(
    "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/erl",
    child_erl_args(eval),
    12_000,
  )
}

fn marker_path(barrier: String, name: String) -> String {
  barrier <> "/" <> name <> ".marker"
}

fn wait_for_marker(root: String, path: String, attempts: Int) -> Bool {
  case files.read(root, path) {
    Ok(_) -> True
    Error(_) ->
      case attempts <= 0 {
        True -> False
        False -> {
          process.sleep(10)
          wait_for_marker(root, path, attempts - 1)
        }
      }
  }
}

fn run_worker_actor(root: String, database: String, barrier: String, name: String) -> Nil {
  let outcome = run_os_worker(root, database, barrier, name)
  let encoded = case outcome {
    Ok(output) -> "ok\n" <> output
    Error(error) -> "error\n" <> error
  }
  let _ = files.create(root, marker_path(barrier, name <> "-result"), encoded)
  Nil
}

/// Invoked only by a fixed, bounded Erlang child in the private component test.
pub fn assessment_lock_os_worker(
  root: String,
  database: String,
  portfolio: String,
  barrier: String,
  name: String,
) -> Result(Nil, String) {
  let pid = os_pid_text()
  case name == "b" {
    True -> {
      let _ = files.create(root, marker_path(barrier, "b-ready"), pid)
      Nil
    }
    False -> Nil
  }
  admission.with_assessment_portfolio_lock_at(
    root,
    database,
    portfolio,
    "component-os-lock-" <> name,
    fn() {
      use _ <- result.try(files.create(root, marker_path(barrier, name <> "-enter"), pid))
      case name {
        "a" -> {
          case wait_for_marker(root, marker_path(barrier, "release-a"), 600) {
            False -> Error("owner_release_barrier_timeout")
            True ->
              files.create(root, marker_path(barrier, "a-exit"), pid)
          }
        }
        "b" ->
          case files.read(root, marker_path(barrier, "a-exit")) {
            Ok(_) -> Ok(Nil)
            Error(_) -> Error("lock_entered_before_owner_exit")
          }
        _ -> Error("unknown_worker")
      }
    },
  )
}

fn marker_contents(root: String, path: String) -> String {
  case files.read(root, path) {
    Ok(content) -> content
    Error(_) -> ""
  }
}

pub fn assessment_lock_serializes_two_bounded_os_beams_test() {
  let id = unique_id()
  let root = "/tmp/uos-assessment-os-race-" <> id
  let database = "/tmp/uos-assessment-os-race-" <> id <> ".sqlite3"
  let barrier = "var/race"
  let assert Ok(Nil) = simplifile.create_directory_all(root <> "/var/race")
  let assert Ok(opened) = store.open(database)
  let assert Ok(_) = store.append(
    opened,
    sync.Register("assessment-os-race-" <> id, "codex", root, "fixture", []),
    "register-os-race-" <> id,
  )
  let assert Ok(Nil) = store.close(opened)

  let _a = process.spawn_unlinked(fn() {
    run_worker_actor(root, database, barrier, "a")
  })
  let a_entered = wait_for_marker(root, marker_path(barrier, "a-enter"), 500)

  let _b = process.spawn_unlinked(fn() {
    run_worker_actor(root, database, barrier, "b")
  })
  let b_ready = wait_for_marker(root, marker_path(barrier, "b-ready"), 500)
  let b_entered_before_release =
    files.read(root, marker_path(barrier, "b-enter")) |> result.is_ok

  let _release = files.create(root, marker_path(barrier, "release-a"), "release")
  let a_finished = wait_for_marker(root, marker_path(barrier, "a-result"), 1_500)
  let b_finished = wait_for_marker(root, marker_path(barrier, "b-result"), 1_500)

  a_entered |> should.be_true
  b_ready |> should.be_true
  b_entered_before_release |> should.be_false
  a_finished |> should.be_true
  b_finished |> should.be_true
  string.starts_with(marker_contents(root, marker_path(barrier, "a-result")), "ok\n")
  |> should.be_true
  string.starts_with(marker_contents(root, marker_path(barrier, "b-result")), "ok\n")
  |> should.be_true
  let a_pid = marker_contents(root, marker_path(barrier, "a-enter"))
  let b_pid = marker_contents(root, marker_path(barrier, "b-enter"))
  should.be_false(a_pid == "")
  should.be_false(b_pid == "")
  should.be_false(a_pid == b_pid)
  marker_contents(root, marker_path(barrier, "a-enter"))
  |> should.equal(marker_contents(root, marker_path(barrier, "a-exit")))
}

pub fn legacy_task_budget_is_scoped_and_fail_closed_test() {
  operations.legacy_task_scan_budget(0, 0) |> should.equal(Ok(Nil))
  operations.legacy_task_scan_budget(16_777_216, 256) |> should.equal(Ok(Nil))
  operations.legacy_task_scan_budget(16_777_217, 0) |> should.be_error
  operations.legacy_task_scan_budget(0, 257) |> should.be_error
  operations.legacy_task_scan_budget(-1, 0) |> should.be_error
  operations.legacy_task_scan_budget(0, -1) |> should.be_error
}

pub fn historical_refusal_prefix_is_exact_and_not_a_blanket_settlement_test() {
  operations.known_no_effect_refusal(
    "FAILED_OR_UNVERIFIED", "harness_write_file", "refused: source_digest_conflict",
  ) |> should.be_true
  operations.known_no_effect_refusal(
    "FAILED_OR_UNVERIFIED", "harness_build", "refused: source_digest_conflict",
  ) |> should.be_false
  operations.known_no_effect_refusal(
    "FAILED_OR_UNVERIFIED", "harness_write_file", "refused:source_digest_conflict",
  ) |> should.be_false
  operations.known_no_effect_refusal(
    "FAILED_OR_UNVERIFIED", "harness_write_file", "refused: source_digest_conflict\nextra",
  ) |> should.be_false
}


fn planning_scan_binding() -> dev.Binding {
  dev.Binding("development", "uos/test/planning-scan", "TASK", "worker", 1, "session", 1)
}

fn planning_scan_payload() -> String {
  json.object([
    #("intent", json.string("CreatePlan")),
    #("logical_id", json.string("logical-01")),
    #("target_plan", json.string("uos/test/created")),
    #("task_id", json.string("")),
    #("title", json.string("Fixture")),
    #("evidence_path", json.string("")),
    #("evidence_body_sha256", json.string(files.digest(""))),
  ]) |> json.to_string
}

fn planning_scan_record(outcome: planning.Outcome) -> String {
  let binding = planning_scan_binding()
  let key = planning.logical_key(binding.plan, binding.task, "logical-01")
  planning.ledger_record(key, binding, "CreatePlan", planning_scan_payload(), outcome, "fixture")
  |> json.to_string
}

fn planning_scan_name() -> String {
  "planning@" <> planning.logical_key("uos/test/planning-scan", "TASK", "logical-01") <> "@intent.json"
}

fn planning_scan_resolution(prepared: String, saved: String) -> String {
  json.object([
    #("schema", json.string("uos.harness-planning-resolution.v1")),
    #("kind", json.string("planning_resolution")),
    #("disposition", json.string("RESOLVED_NOT_APPLIED")),
    #("key", json.string(planning.logical_key("uos/test/planning-scan", "TASK", "logical-01"))),
    #("parent_plan", json.string("uos/test/planning-scan")),
    #("parent_task", json.string("TASK")),
    #("logical_id", json.string("logical-01")),
    #("payload_sha256", json.string(files.digest(planning_scan_payload()))),
    #("intent_sha256", json.string(files.digest(prepared))),
    #("result_sha256", json.string(files.digest(saved))),
    #("scope_sha256", json.string(files.digest("fixture-scope"))),
  ]) |> json.to_string
}

pub fn legacy_scan_dispatches_planning_without_execution_field_test() {
  operations.legacy_intent_identity(
    planning_scan_name(), parsed(planning_scan_record(planning.Uncertain("prepared"))),
  ) |> should.equal(Ok(#("uos/test/planning-scan", "TASK", True)))
}

pub fn legacy_scan_rejects_schema_namespace_and_unknown_records_test() {
  let prepared = parsed(planning_scan_record(planning.Uncertain("prepared")))
  operations.legacy_intent_identity("ordinary@intent.json", prepared) |> should.be_error
  operations.legacy_intent_identity(planning_scan_name() <> ".extra", prepared) |> should.be_error
  operations.legacy_intent_identity("ordinary@intent.json", parsed("{\"schema\":\"unknown.v1\"}"))
  |> should.be_error
}

pub fn legacy_scan_recomputes_parent_logical_key_and_payload_digest_test() {
  let raw = planning_scan_record(planning.Uncertain("prepared"))
  operations.legacy_intent_identity(
    planning_scan_name(), parsed(string.replace(raw, "uos/test/planning-scan", "uos/test/other")),
  ) |> should.be_error
  operations.legacy_intent_identity(
    planning_scan_name(), parsed(string.replace(raw, "logical-01", "logical-02")),
  ) |> should.be_error
}

pub fn legacy_scan_accepts_settled_planning_and_holds_missing_result_test() {
  let raw = planning_scan_record(planning.Uncertain("prepared"))
  let prepared = parsed(raw)
  operations.legacy_planning_terminal_valid(planning_scan_name(), raw, prepared, None, None)
  |> should.equal(Ok(False))
  operations.legacy_planning_terminal_valid(
    planning_scan_name(), raw, prepared, Some(planning_scan_record(planning.Applied)), None,
  ) |> should.equal(Ok(True))
}

pub fn legacy_scan_unresolved_per_key_planning_holds_without_current_pointer_test() {
  let raw = planning_scan_record(planning.Uncertain("prepared"))
  let saved = planning_scan_record(planning.Uncertain("unknown"))
  operations.legacy_planning_terminal_valid(planning_scan_name(), raw, parsed(raw), Some(saved), None)
  |> should.equal(Ok(False))
  let resolution = planning_scan_resolution(raw, saved)
  operations.legacy_planning_terminal_valid(
    planning_scan_name(), raw, parsed(raw), Some(saved), Some(resolution),
  ) |> should.equal(Ok(True))
  let wrong_intent = string.replace(resolution, files.digest(raw), files.digest("another-intent"))
  operations.legacy_planning_terminal_valid(
    planning_scan_name(), raw, parsed(raw), Some(saved), Some(wrong_intent),
  ) |> should.be_error
}

pub fn legacy_scan_rejects_cross_parent_and_cross_payload_terminal_test() {
  let raw = planning_scan_record(planning.Uncertain("prepared"))
  let saved = planning_scan_record(planning.Applied)
  operations.legacy_planning_terminal_valid(
    planning_scan_name(), raw, parsed(raw),
    Some(string.replace(saved, "uos/test/planning-scan", "uos/test/other")), None,
  ) |> should.be_error
  operations.legacy_planning_terminal_valid(
    planning_scan_name(), raw, parsed(raw),
    Some(string.replace(saved, "logical-01", "logical-02")), None,
  ) |> should.be_error
}

pub fn legacy_scan_validates_ordinary_schema_even_for_other_task_test() {
  let raw = json.object([
    #("schema", json.string("uos.harness-successor-effect.v1")),
    #("kind", json.string("effect_intent")),
    #("intent_id", json.string("fixture-intent")),
    #("execution", json.object([
      #("plan", json.string("uos/test/other")),
      #("task", json.string("OTHER")),
      #("grant_sha256", json.string(files.digest("grant"))),
      #("worker", json.string("worker")),
      #("attempt", json.int(1)),
    ])),
  ]) |> json.to_string
  operations.legacy_intent_identity("fixture@fixture-intent@intent.json", parsed(raw))
  |> should.equal(Ok(#("uos/test/other", "OTHER", False)))
  operations.legacy_intent_identity("fixture@renamed-intent@intent.json", parsed(raw)) |> should.be_error
  operations.legacy_intent_identity(planning_scan_name(), parsed(raw)) |> should.be_error
  operations.legacy_intent_identity("fixture@fixture-intent@completion-intent.json", parsed(raw)) |> should.be_error
  operations.legacy_intent_identity("fixture@fixture-intent@intent.json", parsed(string.replace(raw, "effect_intent", "unknown_kind")))
  |> should.be_error
}
