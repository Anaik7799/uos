import cepaf_gleam/harness/files
import cepaf_gleam/harness/tracking as t
import cepaf_gleam/harness/value as v
import cepaf_gleam/planning/sa_plan_bridge
import gleam/bit_array
import gleam/crypto
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleeunit/should

@external(erlang, "ecology_capability_ffi", "run_bounded")
fn native_run(
  path: String,
  args: List(String),
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

fn private_database() -> String {
  let nonce = crypto.strong_random_bytes(16) |> bit_array.base16_encode
  "/tmp/uos-harness-tracking-fixture-" <> nonce <> ".sqlite3"
}

fn fixture_cli(database: String, args: List(String)) -> #(Int, String) {
  let assert Ok(#(code, bytes)) =
    native_run(
      "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/env",
      [
        "UOS_SA_PLAN_DB=" <> database,
        sa_plan_bridge.resolve_sa_plan_binary(),
        ..args
      ],
      5000,
    )
  let assert Ok(output) = bit_array.to_string(bytes)
  #(code, output)
}

fn fixture_ok(database: String, args: List(String)) -> List(v.Value) {
  let #(code, output) = fixture_cli(database, args)
  code |> should.equal(0)
  let assert Ok(rows) = t.decode_cli(code, output, "")
  rows
}

fn create_fixture_plan(database: String) {
  fixture_ok(database, [
    "plan",
    "create",
    t.plan_id,
    t.plan_name,
    t.plan_title,
    "--format",
    "json",
  ])
}

fn declaration(id: String, stage: String, deps: List(String)) -> v.Value {
  v.Object([
    #("feature_id", v.Text(id)),
    #("title", v.Text("Synthetic capability")),
    #("implementation_stage", v.Text(stage)),
    #("requirements", v.Array([v.Text("R1")])),
    #("decisions", v.Array([v.Text("D1")])),
    #("dependencies", v.Array(list.map(deps, v.Text))),
    #("acceptance", v.Array([v.Text("Observe a bounded test")])),
    #(
      "evidence",
      v.Array([
        v.Object([
          #("kind", v.Text("source")),
          #("path", v.Text("public.gleam")),
          #("state", v.Text("UNRUN")),
          #("note", v.Text("Not acceptance")),
        ]),
      ]),
    ),
    #("dashboard", v.Text("UNKNOWN")),
    #("blocker", v.Text("Fresh test missing")),
    #("next_action", v.Text("Run a bounded test")),
  ])
}

fn catalog(entries: List(v.Value)) -> Result(t.Catalog, String) {
  entries |> json.array(v.encode) |> json.to_string |> t.parse_catalog
}

fn sample() -> #(t.Catalog, t.Feature) {
  let assert Ok(c) = catalog([declaration("time.observe", "EXECUTED", [])])
  let assert Ok(f) = list.first(c.features)
  #(c, f)
}

fn row(fields: List(#(String, String))) -> v.Value {
  v.Object(list.map(fields, fn(p) { #(p.0, v.Text(p.1)) }))
}

pub fn catalog_admits_actual_dotted_feature_ids_test() {
  let #(c, f) = sample()
  f.id |> should.equal("time.observe")
  c.features |> list.length |> should.equal(1)
  t.valid_feature_id("rules.rete_ul") |> should.be_true
}

pub fn paths_flags_unicode_and_name_normalization_cannot_change_identity_test() {
  list.each(
    ["../other", "a/b", "--help", ".hidden", "x.", "-x", "A", "é", "a b", ""],
    fn(id) { t.valid_feature_id(id) |> should.be_false },
  )
}

pub fn duplicate_feature_identity_is_not_silently_merged_test() {
  catalog([
    declaration("time.observe", "PLANNED", []),
    declaration("time.observe", "EXECUTED", []),
  ])
  |> should.be_error
}

pub fn missing_self_and_cyclic_dependencies_are_refused_test() {
  catalog([declaration("a", "PLANNED", ["absent"])]) |> should.be_error
  catalog([declaration("a", "PLANNED", ["a"])]) |> should.be_error
  catalog([
    declaration("a", "PLANNED", ["b"]),
    declaration("b", "PLANNED", ["a"]),
  ])
  |> should.be_error
}

pub fn valid_out_of_order_dependency_graph_is_parsed_test() {
  catalog([
    declaration("child", "PLANNED", ["parent"]),
    declaration("parent", "PLANNED", []),
  ])
  |> should.be_ok
}

pub fn foreign_catalog_plan_is_not_payload_authority_test() {
  v.Object([
    #("plan_id", v.Text("foreign/plan")),
    #("features", v.Array([declaration("a", "PLANNED", [])])),
  ])
  |> v.encode
  |> json.to_string
  |> t.parse_catalog
  |> should.be_error
}

pub fn malformed_evidence_and_overlarge_catalog_fail_before_dispatch_test() {
  declaration("a", "PLANNED", [])
  |> v.set("evidence", v.Text("all passed"))
  |> fn(x) { catalog([x]) }
  |> should.be_error
  catalog(list.repeat(declaration("a", "PLANNED", []), 129)) |> should.be_error
  t.parse_catalog(string.repeat(" ", files.max_bytes + 1)) |> should.be_error
}

pub fn progress_change_keeps_registration_identity_but_changes_activity_key_test() {
  let #(c, f) = sample()
  let assert Ok(next) = catalog([declaration("time.observe", "BUILT", [])])
  let assert Ok(changed) = list.first(next.features)
  t.identity(f) |> should.equal(t.identity(changed))
  t.job_arguments(f) |> should.equal(t.job_arguments(changed))
  t.workflow_arguments(f) |> should.equal(t.workflow_arguments(changed))
  { t.progress_arguments(c, f) == t.progress_arguments(next, changed) }
  |> should.be_false
}

pub fn declared_executed_stage_never_imports_verified_acceptance_test() {
  let #(c, f) = sample()
  let assert Ok(payload) = json.parse(t.progress(c, f), v.decoder())
  v.get(payload, "verified_acceptance") |> should.equal(Ok(v.Boolean(False)))
  v.get(payload, "task_completion_granted")
  |> should.equal(Ok(v.Boolean(False)))
  v.get(payload, "external_temporal_runtime")
  |> should.equal(Ok(v.Text("NOT_VERIFIED")))
  v.get(payload, "workflow_service")
  |> should.equal(Ok(v.Text("sa_plan_local_durable_history")))
}

pub fn canonical_task_dependency_arguments_use_fixed_plan_and_no_claim_test() {
  let assert Ok(c) =
    catalog([
      declaration("parent", "PLANNED", []),
      declaration("child", "PLANNED", ["parent"]),
    ])
  let assert Ok(f) = list.find(c.features, fn(f) { f.id == "child" })
  t.task_arguments(f)
  |> should.equal([
    "task",
    "create",
    t.plan_id,
    "child",
    "harness/features/child",
    "Feature tracking: child",
    "-",
    "parent",
    "0",
    "--format",
    "json",
  ])
  t.job_arguments(f) |> list.contains("claim") |> should.be_false
  t.workflow_arguments(f) |> list.contains("complete") |> should.be_false
}

pub fn cli_zero_rows_and_malformed_rows_are_distinct_test() {
  t.parse_rows("\n") |> should.equal(Ok([]))
  t.parse_rows("not JSON") |> should.be_error
  t.parse_rows("{\"id\":\"a\"}\n{\"id\":\"b\"}\n")
  |> result.map(list.length)
  |> should.equal(Ok(2))
}

pub fn duplicate_database_rows_are_a_conflict_test() {
  let a = row([#("id", "a")])
  t.select_row([a, a], "a") |> should.be_error
  t.select_row([a], "b") |> should.equal(Ok(None))
  t.select_row([a], "a") |> should.equal(Ok(Some(a)))
}

pub fn task_identity_requires_fixed_plan_name_parent_and_title_test() {
  let #(_, f) = sample()
  let expected =
    row([
      #("plan_id", t.plan_id),
      #("id", f.id),
      #("name", t.task_name(f)),
      #("title", "Feature tracking: " <> f.id),
      #("parent_id", "-"),
      #("priority", "0"),
    ])
  t.task_matches(f, expected) |> should.be_true
  t.task_matches(f, v.set(expected, "plan_id", v.Text("different/plan")))
  |> should.be_false
  t.task_matches(f, v.set(expected, "parent_id", v.Text("foreign")))
  |> should.be_false
  t.task_matches(f, v.set(expected, "title", v.Text("Unrelated task")))
  |> should.be_false
}

pub fn job_identity_rejects_other_queue_and_worker_test() {
  let #(_, f) = sample()
  let expected =
    row([
      #("id", t.job_id(f)),
      #("name", t.task_name(f) <> "/job"),
      #("queue", t.review_queue),
      #("worker", t.record_worker),
      #("max_attempts", "1"),
    ])
  t.job_matches(f, expected) |> should.be_true
  t.job_matches(f, v.set(expected, "queue", v.Text("runtime-effects")))
  |> should.be_false
  t.job_matches(f, v.set(expected, "worker", v.Text("arbitrary-worker")))
  |> should.be_false
}

pub fn workflow_requires_exact_nonduplicate_start_payload_test() {
  let #(_, f) = sample()
  let start = row([#("kind", "workflow_started"), #("payload", t.identity(f))])
  t.workflow_matches(f, [start]) |> should.be_true
  t.workflow_matches(f, []) |> should.be_false
  t.workflow_matches(f, [start, start]) |> should.be_false
  t.workflow_matches(f, [v.set(start, "payload", v.Text("foreign"))])
  |> should.be_false
}

pub fn cached_activity_with_changed_result_does_not_count_as_current_progress_test() {
  let #(c, f) = sample()
  let payload = t.progress(c, f)
  let prefix = "progress-" <> files.digest(payload) <> ":"
  let exact =
    row([#("kind", "activity_completed"), #("payload", prefix <> payload)])
  t.progress_matches(c, f, [exact]) |> should.be_true
  t.progress_matches(c, f, [
    v.set(exact, "payload", v.Text(prefix <> "old or conflicting result")),
  ])
  |> should.be_false
  t.progress_matches(c, f, [v.set(exact, "kind", v.Text("workflow_failed"))])
  |> should.be_false
}

pub fn real_fixed_catalog_is_readable_and_has_all_declared_features_test() {
  let assert Ok(raw) = files.read("/home/an/NAS-setup/uos", t.catalog_path)
  let assert Ok(c) = t.parse_catalog(raw)
  c.features |> list.length |> should.equal(52)
  c.source_sha256 |> should.equal(files.digest(raw))
}

pub fn native_cli_missing_plan_and_workflow_are_distinct_from_general_failure_test() {
  let database = private_database()
  let #(code, output) =
    fixture_cli(database, ["plan", "show", t.plan_id, "--format", "json"])
  t.decode_cli(code, output, "Unknown Sa-plan plan: " <> t.plan_id)
  |> should.equal(Error("tracking_entity_missing"))
  let #(_, f) = sample()
  let #(code, output) =
    fixture_cli(database, [
      "workflow",
      "history",
      t.workflow_id(f),
      "--format",
      "json",
    ])
  t.decode_cli(code, output, "Unknown Sa-plan workflow: " <> t.workflow_id(f))
  |> should.equal(Error("tracking_entity_missing"))
  t.decode_cli(
    1,
    "sa-plan: database unavailable\n",
    "Unknown Sa-plan plan: " <> t.plan_id,
  )
  |> should.equal(Error("tracking_cli_failed_not_absence"))
  t.decode_cli(124, "", "Unknown Sa-plan plan: " <> t.plan_id)
  |> should.be_error
}

pub fn native_cli_merged_pipeline_telemetry_is_validated_not_treated_as_a_record_test() {
  let database = private_database()
  create_fixture_plan(database) |> list.length |> should.equal(1)
  fixture_ok(database, ["task", "list", t.plan_id, "--format", "json"])
  |> should.equal([])
  t.parse_rows("sa-plan-pipeline {\"authority\":\"effect_granted\"}\n")
  |> should.be_error
  t.parse_rows("sa-plan-pipeline not-json\n") |> should.be_error
}

pub fn native_feature_records_and_progress_stay_metadata_only_test() {
  let database = private_database()
  let #(c, f) = sample()
  let _ = create_fixture_plan(database)
  let _ = fixture_ok(database, t.task_arguments(f))
  let _ = fixture_ok(database, t.job_arguments(f))
  let _ = fixture_ok(database, t.workflow_arguments(f))
  let _ = fixture_ok(database, t.progress_arguments(c, f))
  let events =
    fixture_ok(database, [
      "workflow",
      "history",
      t.workflow_id(f),
      "--format",
      "json",
    ])
  t.workflow_matches(f, events) |> should.be_true
  t.progress_matches(c, f, events) |> should.be_true
  let assert [task] =
    fixture_ok(database, ["task", "list", t.plan_id, "--format", "json"])
  t.task_matches(f, task) |> should.be_true
  t.exact_fields(task, [
    #("state", "available"),
    #("attempt", "0"),
    #("worker", "-"),
  ])
  |> should.be_true
  let assert [job] =
    fixture_ok(database, ["job", "list", t.review_queue, "--format", "json"])
  t.job_matches(f, job) |> should.be_true
  t.exact_fields(job, [
    #("state", "available"),
    #("attempt", "0"),
    #("lease_owner", "-"),
  ])
  |> should.be_true
  v.get(job, "args") |> should.be_error
}

pub fn native_duplicate_insert_conflicts_and_changed_activity_body_replays_old_result_test() {
  let database = private_database()
  let #(c, f) = sample()
  let _ = create_fixture_plan(database)
  let _ = fixture_ok(database, t.task_arguments(f))
  let #(duplicate_exit, _) = fixture_cli(database, t.task_arguments(f))
  { duplicate_exit == 0 } |> should.be_false
  let _ = fixture_ok(database, t.workflow_arguments(f))
  let _ = fixture_ok(database, t.progress_arguments(c, f))
  let payload = t.progress(c, f)
  let digest = files.digest(payload)
  let replay =
    fixture_ok(database, [
      "workflow",
      "activity",
      t.workflow_id(f),
      "progress-" <> digest,
      t.task_name(f) <> "/progress/" <> digest,
      "progress-" <> digest,
      "changed-body",
      "--format",
      "json",
    ])
  let assert [row] = replay
  v.get(row, "result") |> should.equal(Ok(v.Text(payload)))
  let events =
    fixture_ok(database, [
      "workflow",
      "history",
      t.workflow_id(f),
      "--format",
      "json",
    ])
  events |> list.length |> should.equal(2)
}

pub fn hidden_dependency_change_and_missing_receipt_cannot_report_registered_test() {
  let #(_, f) = sample()
  let visible =
    row([
      #("plan_id", t.plan_id),
      #("id", f.id),
      #("name", t.task_name(f)),
      #("title", "Feature tracking: " <> f.id),
      #("parent_id", "-"),
      #("priority", "0"),
    ])
  let digest =
    t.task_arguments(f)
    |> json.array(json.string)
    |> json.to_string
    |> files.digest
  let receipt =
    row([
      #("status", "applied_readback"),
      #("request_sha256", digest),
    ])
  t.task_registration_matches(f, visible, Ok(receipt)) |> should.be_true
  let changed = t.Feature(..f, dependencies: ["files.read"])
  t.task_matches(changed, visible) |> should.be_true
  t.task_registration_matches(changed, visible, Ok(receipt)) |> should.be_false
  t.task_registration_matches(f, visible, Error("missing")) |> should.be_false
  t.task_registration_matches(
    f,
    visible,
    Ok(v.set(receipt, "status", v.Text("unknown"))),
  )
  |> should.be_false
  t.task_registration_matches(
    f,
    v.set(visible, "plan_id", v.Text("foreign")),
    Ok(receipt),
  )
  |> should.be_false
}
