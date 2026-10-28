import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/operations as ops
import cepaf_gleam/harness/planning_intents as planning
import cepaf_gleam/harness/successor_mcp as mcp
import cepaf_gleam/harness/value
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile
import uos_swarm/session_sync

fn scope() {
  a.Scope(
    "uos/test/20260909",
    "clock",
    ["AGENTS.md"],
    ["apps/cepaf_gleam/test/harness_successor_test.gleam"],
    ["AGENTS.md", "apps/cepaf_gleam/test/harness_successor_test.gleam"],
    ["harness_successor_test"],
    "var/harness/20260909-1751-current-risk.json",
    [],
    [],
  )
}

fn grant() {
  a.Grant(
    "20260909-1751-test",
    "var/harness/20260909-1751-test-grant.json",
    string.repeat("a", 64),
    "test-session",
    "test-worker",
    string.repeat("b", 64),
    "test-boot",
    1000,
    [scope()],
    "",
    "docs/reviews/20260909-1751-test.json",
    string.repeat("c", 64),
  )
}

pub fn short_backend_diagnostics_are_preserved_test() {
  dev.backend_diagnostic("failed: expected diagnostic")
  |> should.equal("failed: expected diagnostic")
  dev.backend_diagnostic("Gleam λ 日本語") |> should.equal("Gleam λ 日本語")
  dev.backend_diagnostic("") |> should.equal("")
}

pub fn diagnostic_tail_is_bounded_and_preserves_terminal_cause_test() {
  let suffix = "terminal cause"
  let full = string.repeat("x", 9000) <> suffix
  let bounded = dev.backend_diagnostic(full)
  bounded |> string.length |> should.equal(8192)
  bounded |> string.ends_with(suffix) |> should.be_true
  dev.backend_diagnostic(string.repeat("界", 8192))
  |> should.equal("diagnostic_exceeded_byte_bound")
}

pub fn real_nonzero_adapter_keeps_its_diagnostic_test() {
  let outcome =
    dev.bounded(
      dev.root <> "/toolchains/nix-profile/bin/env",
      ["/uos-deliberately-absent-successor-fixture"],
      3000,
    )
  let assert Error(reason) = outcome
  reason |> string.contains("backend_exit:127") |> should.be_true
  reason
  |> string.contains("uos-deliberately-absent-successor-fixture")
  |> should.be_true
}

pub fn task_scope_excludes_old_bootstrap_and_secrets_test() {
  a.scope_valid(scope()) |> should.be_true
  a.scope_valid(a.Scope(..scope(), task: "HARNESSBOOT")) |> should.be_false
  a.scope_valid(a.Scope(..scope(), plan: "foreign/plan")) |> should.be_false
  a.scope_valid(a.Scope(..scope(), reads: [".env"])) |> should.be_false
  a.scope_valid(a.Scope(..scope(), reads: ["var/sa-plan/uos.sqlite3"]))
  |> should.be_false
  a.scope_valid(
    a.Scope(..scope(), reads: ["/home/an/dev/ver/zigvm/config.json"]),
  )
  |> should.be_false
  a.scope_valid(a.Scope(..scope(), writes: ["tools/unreviewed.ml"]))
  |> should.be_false
  a.scope_valid(a.Scope(..scope(), sources: ["AGENTS.md"]))
  |> should.be_false
}

pub fn path_components_and_empty_evidence_fail_closed_test() {
  a.component("../escape") |> should.be_false
  a.component("..") |> should.be_false
  a.component("abc\u{0}") |> should.be_false
  a.component("20260909-1751-test") |> should.be_true
  a.scope_valid(a.Scope(..scope(), sources: [])) |> should.be_false
  a.scope_valid(a.Scope(..scope(), tests: [])) |> should.be_false
  a.scope_valid(a.Scope(..scope(), tests: ["bad();halt(0)"])) |> should.be_false
}

pub fn task_selector_cannot_expand_manifest_test() {
  a.lookup(grant(), scope().plan, scope().task) |> should.equal(Ok(scope()))
  a.lookup(grant(), scope().plan, "another") |> should.be_error
  a.lookup(grant(), "uos/other", scope().task) |> should.be_error
}

pub fn payload_identity_and_backend_are_refused_test() {
  ops.validate_args(
    "harness_build",
    value.Object([
      #("intent_id", value.Text("one")),
      #("worker", value.Text("forged")),
    ]),
  )
  |> should.be_error
  ops.validate_args(
    "harness_test",
    value.Object([
      #("intent_id", value.Text("one")),
      #("backend", value.Text("shell")),
    ]),
  )
  |> should.be_error
  ops.validate_args(
    "harness_claim",
    value.Object([
      #("plan", value.Text(scope().plan)),
      #("task", value.Text("clock")),
      #("intent_id", value.Text("one")),
      #("attempt", value.Integer(9)),
    ]),
  )
  |> should.be_error
  ops.validate_args("arbitrary_shell", value.Object([])) |> should.be_error
}

pub fn client_mcp_config_accepts_only_typed_client_and_action_test() {
  let valid =
    value.Object([
      #("intent_id", value.Text("config")),
      #("client", value.Text("codex")),
      #("action", value.Text("prepare")),
    ])
  ops.validate_args("harness_client_mcp_config", valid) |> should.be_ok
  ops.validate_args(
    "harness_client_mcp_config",
    value.Object([
      #("intent_id", value.Text("config")),
      #("client", value.Text("shell")),
      #("action", value.Text("prepare")),
    ]),
  )
  |> should.be_error
  ops.validate_args(
    "harness_client_mcp_config",
    value.Object([
      #("intent_id", value.Text("config")),
      #("client", value.Text("codex")),
      #("action", value.Text("write_file")),
    ]),
  )
  |> should.be_error
}

pub fn reviewed_workspace_root_changes_only_source_root_test() {
  a.source_root(grant()) |> should.equal(Ok(dev.root))
  a.source_root(a.Grant(..grant(), workspace_root: "apps/cepaf_gleam"))
  |> should.be_error
}

pub fn workspace_root_requires_registered_canonical_jj_identity_test() {
  let root = "/repo/.uos-workspaces/candidate"
  let listing = "candidate: .uos-workspaces/candidate abc123 (empty)\n"
  a.workspace_identity_matches(
    ".uos-workspaces/candidate",
    root,
    listing,
    root <> "\n",
  )
  |> should.be_true
  a.workspace_identity_matches(
    ".uos-workspaces/candidate",
    root,
    "candidate: .uos-workspaces/elsewhere abc123\n",
    root,
  )
  |> should.be_false
  a.workspace_identity_matches(
    ".uos-workspaces/candidate",
    root,
    listing,
    "/repo/apps/cepaf_gleam\n",
  )
  |> should.be_false
  a.workspace_identity_matches(
    ".uos-workspaces/candidate/nested",
    root,
    listing,
    root,
  )
  |> should.be_false
}

// C4: tools/ecology_process.ml bounds every effect's time, output and process
// group, and was bound by nothing -- no path list, no control module. It could
// change while the review, the task row, the candidate manifest and all nine
// control ids stayed matched. Every arm here fails closed.
pub fn control_dependencies_are_bound_and_fail_closed_test() {
  let assert Ok(actual) =
    simplifile.read("/home/an/NAS-setup/uos/tools/ecology_process.ml")
  let digest = files.digest(actual)
  let declared = fn(v) { value.Object([#("tools/ecology_process.ml", v)]) }

  a.control_dependencies_match(declared(value.Text(digest))) |> should.be_ok
  // a changed guardian is refused
  a.control_dependencies_match(declared(value.Text(string.repeat("a", 64))))
  |> should.be_error
  // a malformed digest is refused, not coerced
  a.control_dependencies_match(declared(value.Text("short"))) |> should.be_error
  a.control_dependencies_match(declared(value.Integer(1))) |> should.be_error
  // an undeclared dependency set is refused
  a.control_dependencies_match(value.Object([])) |> should.be_error
  a.control_dependencies_match(
    value.Object([#("tools/other.ml", value.Text(digest))]),
  )
  |> should.be_error
  // an extra declaration cannot pad the set
  a.control_dependencies_match(
    value.Object([
      #("tools/ecology_process.ml", value.Text(digest)),
      #("tools/other.ml", value.Text(digest)),
    ]),
  )
  |> should.be_error
  a.control_dependencies_match(value.Text("not an object")) |> should.be_error
}

pub fn success_replay_requires_exact_binding_and_terminal_success_test() {
  let good =
    json.object([
      #("schema", json.string("uos.harness-successor-effect.v1")),
      #("kind", json.string("effect_result")),
      #("signature", json.string("expected")),
      #("status", json.string("EXECUTED")),
    ])
    |> json.to_string
  ops.replay(good, "expected") |> should.be_ok
  ops.replay(good, "other") |> should.be_error
  ops.replay("not json", "expected") |> should.be_error
  ops.replay(
    "{\"signature\":\"expected\",\"status\":\"FAILED_OR_UNVERIFIED\"}",
    "expected",
  )
  |> should.be_error
}

// C2: an untyped record is no longer replayable, because its meaning used to be
// carried entirely by the filename it was found under -- and two different kinds
// of record could land on the same filename.
pub fn replay_refuses_a_record_that_does_not_declare_its_own_kind_test() {
  let untyped =
    json.object([
      #("signature", json.string("expected")),
      #("status", json.string("EXECUTED")),
    ])
    |> json.to_string
  ops.replay(untyped, "expected") |> should.be_error
  let wrong_kind =
    json.object([
      #("schema", json.string("uos.harness-successor-effect.v1")),
      #("kind", json.string("quarantine_record")),
      #("signature", json.string("expected")),
      #("status", json.string("EXECUTED")),
    ])
    |> json.to_string
  ops.replay(wrong_kind, "expected") |> should.be_error
  let wrong_schema =
    json.object([
      #("schema", json.string("uos.harness-successor-completion.v1")),
      #("kind", json.string("effect_result")),
      #("signature", json.string("expected")),
      #("status", json.string("EXECUTED")),
    ])
    |> json.to_string
  ops.replay(wrong_schema, "expected") |> should.be_error
}

// C2 by construction: "@" is outside the admission.component charset, so an
// intent id can no longer contain the delimiter and impersonate a suffix.
// Before this, intent "x-completion" with suffix "intent" and intent "x" with
// suffix "completion-intent" produced the SAME path.
pub fn effect_paths_cannot_collide_across_record_kinds_test() {
  let a = ops.effect_path_for("G", "x-completion", "intent")
  let b = ops.effect_path_for("G", "x", "completion-intent")
  a |> should.not_equal(b)
  ops.effect_path_for("G", "x", "intent")
  |> should.not_equal(ops.effect_path_for("G", "x", "result"))
  ops.effect_path_for("G", "x", "intent")
  |> should.not_equal(ops.effect_path_for("H", "x", "intent"))
}

// C3: a write to an authorized path OUTSIDE scope.sources used to be invisible
// to every guard. The guard manifest now covers sources and writes together,
// while candidate identity stays narrow so a journal written after the build
// does not invalidate the completion it belongs to.
pub fn guard_manifest_covers_authorized_writes_while_identity_stays_narrow_test() {
  let scope =
    a.Scope(
      "uos/p",
      "T",
      [],
      ["docs/journal/absent-j.md"],
      ["tools/absent-a.gleam"],
      ["m"],
      "var/harness/x-current-risk.json",
      [],
      [],
    )
  let assert Ok(identity) = ops.capture(scope)
  let assert Ok(guard) = ops.guard_capture(scope)
  identity |> string.contains("docs/journal/absent-j.md") |> should.be_false
  guard |> string.contains("docs/journal/absent-j.md") |> should.be_true
  guard |> string.contains("tools/absent-a.gleam") |> should.be_true
}

// The write guard replaces `name == "harness_write_file" || before == after`,
// which permitted ANY other file to move underneath a write.
pub fn write_guard_pins_the_target_digest_and_refuses_other_movement_test() {
  let entry = fn(p, h) {
    json.object([#("path", json.string(p)), #("sha256", json.string(h))])
  }
  let manifest = fn(target_hash, other_hash) {
    json.array(
      [entry("t.gleam", target_hash), entry("o.gleam", other_hash)],
      fn(x) { x },
    )
    |> json.to_string
  }
  let before = manifest("aa", "bb")
  ops.write_manifest_clean(before, manifest("cc", "bb"), "t.gleam", "cc")
  |> should.be_ok
  // the target did not become what the effect claims it wrote
  ops.write_manifest_clean(before, manifest("dd", "bb"), "t.gleam", "cc")
  |> should.be_error
  // something else moved underneath the write
  ops.write_manifest_clean(before, manifest("cc", "zz"), "t.gleam", "cc")
  |> should.be_error
}

pub fn mcp_initialization_notifications_and_closed_sessions_test() {
  let state = mcp.initial(grant())
  let assert #(_, Some(before)) =
    mcp.handle(
      state,
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}",
    )
  before |> string.contains("initialize_required") |> should.be_true
  let assert #(ready, Some(init)) =
    mcp.handle(
      state,
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"initialize\"}",
    )
  init |> string.contains("uos-gleam-successor-harness") |> should.be_true
  mcp.handle(
    ready,
    "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"harness_claim\",\"arguments\":{}}}",
  )
  |> should.equal(#(ready, None))
  let assert #(same, Some(reinit)) =
    mcp.handle(
      ready,
      "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"initialize\"}",
    )
  same |> should.equal(ready)
  reinit |> string.contains("already_initialized") |> should.be_true
  let #(closed, _) =
    mcp.handle(ready, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\"}")
  let assert #(_, Some(after)) =
    mcp.handle(
      closed,
      "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"initialize\"}",
    )
  after |> string.contains("session_closed") |> should.be_true
}

pub fn literal_sa_plan_argument_construction_does_not_admit_arbitrary_shell_test() {
  let args = ops.build_args(["build"])
  args
  |> should.equal([
    "--chdir=" <> dev.root <> "/apps/cepaf_gleam",
    "PATH="
      <> dev.root
      <> "/toolchains/nix-profile/bin:"
      <> dev.root
      <> "/toolchains/gleam-1.16.0/bin:"
      <> dev.root
      <> "/toolchains/opam-ocaml/bin",
    "ERL_FLAGS=+S 2:2 +A 2",
    "ERL_CRASH_DUMP_SECONDS=0",
    dev.root <> "/toolchains/gleam-1.16.0/bin/gleam",
    "build",
  ])
}

pub fn task_namespace_conforms_to_the_real_coordinator_and_separates_plans_test() {
  let first =
    dev.Binding(
      "development",
      "uos/first/plan",
      "same-task",
      "worker",
      1,
      "session",
      1,
    )
  let second = dev.Binding(..first, plan: "uos/second/plan")
  let a = dev.task_resource(first)
  let b = dev.task_resource(second)
  session_sync.valid_resource(a) |> should.be_true
  session_sync.valid_resource(b) |> should.be_true
  { a != b } |> should.be_true
  dev.task_resource(
    dev.Binding(..first, plan: "uos/ecology/20260909-0146", task: "HARNESSBOOT"),
  )
  |> should.equal("task:HARNESSBOOT")
}

pub fn coordinator_operation_ids_leave_room_for_composed_suffixes_test() {
  a.intent_valid(string.repeat("x", 48)) |> should.be_true
  a.intent_valid(string.repeat("x", 49)) |> should.be_false
}

fn reviewed_documents() {
  let proposal =
    value.Object([
      #("grant_id", value.Text("test-grant")),
      #("session", value.Text("root-session")),
      #("worker", value.Text("root-worker")),
      #("tasks", value.Array([])),
      #("review_sha256", value.Text("PENDING")),
    ])
  let path = "var/harness/20260909-1751-proposal.json"
  let hash = string.repeat("a", 64)
  let document =
    proposal
    |> value.set("review_sha256", value.Text(string.repeat("b", 64)))
    |> value.set("proposal_path", value.Text(path))
    |> value.set("proposal_sha256", value.Text(hash))
  let review =
    value.Object([
      #("schema", value.Text("uos.harness-successor-grant-review.v1")),
      #("verdict", value.Text("APPROVE_DEV_TEST_SCOPE")),
      #("reviewer", value.Object([#("session_id", value.Text("peer-session"))])),
      #(
        "grant_proposal",
        value.Object([
          #("path", value.Text(path)),
          #("sha256", value.Text(hash)),
          #("grant_id", value.Text("test-grant")),
          #("target_session", value.Text("root-session")),
          #("target_worker", value.Text("root-worker")),
        ]),
      ),
    ])
  #(document, review, proposal)
}

pub fn review_verdict_and_independent_identity_are_mandatory_test() {
  let #(document, review, proposal) = reviewed_documents()
  a.validate_review(document, review, proposal) |> should.be_ok
  a.validate_review(
    document,
    value.set(review, "verdict", value.Text("REVISE")),
    proposal,
  )
  |> should.equal(Error("review_verdict"))
  a.validate_review(
    document,
    value.set(review, "verdict", value.Text("PENDING")),
    proposal,
  )
  |> should.be_error
  a.validate_review(
    document,
    value.set(review, "schema", value.Text("arbitrary")),
    proposal,
  )
  |> should.be_error
  a.validate_review(
    document,
    value.set(
      review,
      "reviewer",
      value.Object([#("session_id", value.Text("root-session"))]),
    ),
    proposal,
  )
  |> should.be_error
}

pub fn approved_review_cannot_authorize_a_different_proposal_or_scope_test() {
  let #(document, review, proposal) = reviewed_documents()
  a.validate_review(
    value.set(document, "proposal_sha256", value.Text(string.repeat("c", 64))),
    review,
    proposal,
  )
  |> should.be_error
  a.validate_review(
    value.set(document, "proposal_path", value.Text("var/harness/other.json")),
    review,
    proposal,
  )
  |> should.be_error
  a.validate_review(
    value.set(document, "worker", value.Text("another-worker")),
    review,
    proposal,
  )
  |> should.be_error
  a.validate_review(
    value.set(document, "tasks", value.Array([value.Text("unreviewed")])),
    review,
    proposal,
  )
  |> should.be_error
  a.validate_review(
    value.set(document, "extra_authority", value.Text("production")),
    review,
    proposal,
  )
  |> should.be_error
  let assert value.Object(fields) = document
  a.validate_review(
    value.Object([#("session", value.Text("root-session")), ..fields]),
    review,
    proposal,
  )
  |> should.be_error
}

pub fn refused_task_selection_preserves_a_usable_mcp_session_test() {
  let ready = mcp.State(..mcp.initial(grant()), initialized: True)
  let args =
    value.Object([
      #("plan", value.Text("uos/does-not-exist")),
      #("task", value.Text("clock")),
      #("intent_id", value.Text("typo")),
    ])
  let #(after, outcome) = mcp.call(ready, "harness_claim", args)
  outcome |> should.equal(Error("task_not_in_reviewed_grant"))
  after |> should.equal(ready)
  a.outcome_unknown("task_not_in_reviewed_grant") |> should.be_false
  a.outcome_unknown("intent_id") |> should.be_false
  a.outcome_unknown("claim_outcome_unknown:backend_timeout") |> should.be_true
  a.outcome_unknown("release_outcome_unknown:readback") |> should.be_true
  a.outcome_unknown("unknown_effect_outcome_requires_reconciliation")
  |> should.be_true
}

pub fn grant_lease_covers_the_full_operation_horizon_test() {
  let now = 1_000_000_000
  a.grant_budget_valid(now + 2_000_000, now, 65_000) |> should.be_false
  a.grant_budget_valid(now + 65_000_000, now, 65_000) |> should.be_false
  a.grant_budget_valid(now + 65_000_001, now, 65_000) |> should.be_true
  a.grant_budget_valid(now, now, 0) |> should.be_false
  a.grant_budget_valid(now + 1, now, 0) |> should.be_true
  a.grant_budget_valid(now + 86_400_000_001, now, 0) |> should.be_false
  a.grant_budget_valid(now + 70_000_001, now, 70_001) |> should.be_false
  a.grant_budget_valid(now + 1, now, -1) |> should.be_false
}

pub fn completed_review_requires_the_exact_canonical_artifact_result_test() {
  let b =
    dev.Binding(
      "development",
      "uos/review/plan",
      "review",
      "peer",
      2,
      "peer-session",
      1,
    )
  let hash = string.repeat("a", 64)
  let row =
    dev.TaskRecord(
      "completed",
      Some("peer"),
      2,
      None,
      0,
      Some("uos.harness-peer-review.v1:" <> hash),
      Some(123),
    )
  a.review_task_matches(b, row, hash) |> should.be_true
  a.review_task_matches(b, row, string.repeat("b", 64)) |> should.be_false
  a.review_task_matches(b, dev.TaskRecord(..row, state: "executing"), hash)
  |> should.be_false
  a.review_task_matches(
    b,
    dev.TaskRecord(..row, result: Some("old review done")),
    hash,
  )
  |> should.be_false
  a.review_task_matches(b, dev.TaskRecord(..row, worker: Some("root")), hash)
  |> should.be_false
  a.review_task_matches(dev.Binding(..b, attempt: 3), row, hash)
  |> should.be_false
}

pub fn nested_grant_objects_have_order_independent_unique_key_semantics_test() {
  let left =
    value.Object([
      #(
        "tasks",
        value.Array([
          value.Object([
            #("plan", value.Text("uos/test")),
            #("task", value.Text("one")),
          ]),
        ]),
      ),
    ])
  let right =
    value.Object([
      #(
        "tasks",
        value.Array([
          value.Object([
            #("task", value.Text("one")),
            #("plan", value.Text("uos/test")),
          ]),
        ]),
      ),
    ])
  a.same_value(left, right) |> should.be_true
  a.same_value(left, value.Object([#("tasks", value.Array([]))]))
  |> should.be_false
  a.same_value(
    value.Object([#("key", value.Text("x")), #("key", value.Text("x"))]),
    value.Object([#("key", value.Text("x")), #("key", value.Text("x"))]),
  )
  |> should.be_false
  a.same_value(
    value.Array([value.Integer(1), value.Integer(2)]),
    value.Array([value.Integer(2), value.Integer(1)]),
  )
  |> should.be_false
}

pub fn task_completion_cannot_bypass_an_unresolved_effect_test() {
  let b =
    dev.Binding(
      "development",
      scope().plan,
      scope().task,
      grant().worker,
      1,
      grant().session,
      1,
    )
  let e = a.Execution(grant(), scope(), b, scope().portfolio)
  let state = mcp.State(grant(), True, False, Some(e), True)
  let args =
    value.Object([
      #("intent_id", value.Text("finish")),
      #("journal_path", value.Text("journal")),
      #("build_intent_id", value.Text("build")),
      #("test_intent_id", value.Text("test")),
      #("verification_path", value.Text("verification")),
    ])
  mcp.call(state, "harness_finish", args)
  |> should.equal(#(state, Error("unresolved_operation_stop_line")))
}

// --- Retained diagnostic integrity (RECEIPT_FIX) ---------------------------
//
// Observed defect, 2026-10-27, receipt of a real harness_test effect under
// grant 20261027-0538-hive-receipt-dedicated: the EXECUTED record retained
// 8192 bytes of the tail, whose digest is
//   e019941e9c2ba9ac4388890fbef184ffc5461d90b254f2a0d452673097231c1e
// while the record's only digest, output_sha256, claimed
//   5055476adedd97820354aad00baa1469b3a8b9b06043c7ce061e3262192fe3ea
// (the digest of the FULL output). A verifier holding the receipt therefore
// could not check the bytes in front of it, and nothing in the record
// disclosed that truncation had occurred or how many bytes were dropped.
//
// Assertions below reuse the production pure constructor
// ops.effect_output_fields and the production bound dev.backend_diagnostic;
// there is no test-local reimplementation of either.

fn receipt_field(output: String, key: String) -> Result(json.Json, Nil) {
  list.key_find(ops.effect_output_fields(output), key)
}

fn assert_retained_bytes_are_verifiable(output: String, retention: String) {
  let retained = dev.backend_diagnostic(output)
  // the retained text is exactly what the production bound produced
  receipt_field(output, "output")
  |> should.equal(Ok(json.string(retained)))
  // and the receipt carries a digest OF THOSE RETAINED BYTES
  receipt_field(output, "output_retained_sha256")
  |> should.equal(Ok(json.string(files.digest(retained))))
  // byte counts are explicit on both sides of the bound
  receipt_field(output, "output_retained_bytes")
  |> should.equal(Ok(json.int(string.byte_size(retained))))
  receipt_field(output, "output_bytes")
  |> should.equal(Ok(json.int(string.byte_size(output))))
  // the full-output digest is preserved, under its documented meaning
  receipt_field(output, "output_sha256")
  |> should.equal(Ok(json.string(files.digest(output))))
  // and the relationship between the two is stated, never implied
  receipt_field(output, "output_retention")
  |> should.equal(Ok(json.string(retention)))
}

pub fn executed_receipt_digest_covers_the_bytes_it_retains_test() {
  // short output: nothing is dropped
  assert_retained_bytes_are_verifiable("ok\n", "full")
  // empty output: a measured zero, not an absence
  assert_retained_bytes_are_verifiable("", "full")
  // long ASCII: the grapheme tail bound drops a prefix
  assert_retained_bytes_are_verifiable(
    string.repeat("x", 20_000),
    "tail_truncated",
  )
  // Unicode: 8192 three-byte graphemes exceed the 16384-byte bound, so the
  // production fallback retains a sentinel that is NOT output bytes at all
  assert_retained_bytes_are_verifiable(
    string.repeat("\u{d55c}", 9000),
    "unavailable",
  )
}

// --- Typed planning intents (PLANNING_MCP) --------------------------------
//
// Source-bound unit laws over the pure planning surface. These assertions use
// the production module, never a test-local reimplementation, and they do NOT
// mutate the canonical Sa-plan store: no CLI dispatch happens in a unit test.
// Real canonical sandbox create/read/publish is a later activation gate.

fn planning_binding() {
  dev.Binding(
    "development",
    "uos/hive-development/20261027-0532",
    "PLANNING_MCP",
    "claude-hive-planning-2585",
    1,
    "2585c3a9-4685-457d-84af-74238f66aa7c",
    1,
  )
}

pub fn planning_intent_set_is_closed_test() {
  planning.parse_intent("CreatePlan") |> should.equal(Ok(planning.CreatePlan))
  planning.parse_intent("CreateTask") |> should.equal(Ok(planning.CreateTask))
  planning.parse_intent("PublishEvidence")
  |> should.equal(Ok(planning.PublishEvidence))
  // Anything outside the closed set, including a generic runner or an
  // identity/backend/SQL/shell carrier, is refused by name.
  planning.parse_intent("RunSql") |> should.equal(Error("unknown_intent"))
  planning.parse_intent("") |> should.equal(Error("unknown_intent"))
  planning.parse_intent("createplan") |> should.equal(Error("unknown_intent"))
}

pub fn planning_outcomes_are_four_and_labelled_test() {
  planning.outcome_label(planning.Applied) |> should.equal("Applied")
  planning.outcome_label(planning.Replayed) |> should.equal("Replayed")
  planning.outcome_label(planning.Refused("x")) |> should.equal("Refused")
  planning.outcome_label(planning.Uncertain("x")) |> should.equal("Uncertain")
}

pub fn planning_logical_key_is_unambiguous_and_grant_attempt_free_test() {
  let b = planning_binding()
  let key = planning.logical_key(b.plan, b.task, "L-001")
  // Stable across attempt: the key is computed from the tuple only.
  let other_attempt = dev.Binding(..b, attempt: 7)
  planning.logical_key(other_attempt.plan, other_attempt.task, "L-001")
  |> should.equal(key)
  // A different logical id is a different key.
  planning.logical_key(b.plan, b.task, "L-002") |> should.not_equal(key)
  // Unambiguous encoding: these two tuples must NOT collide, which a slash or
  // newline concatenation would allow.
  planning.logical_key("a/b", "c", "d")
  |> should.not_equal(planning.logical_key("a", "b/c", "d"))
  planning.logical_key("a", "b", "c\nd")
  |> should.not_equal(planning.logical_key("a", "b\nc", "d"))
}

pub fn planning_ledger_path_excludes_grant_and_attempt_test() {
  let b = planning_binding()
  let key = planning.logical_key(b.plan, b.task, "L-003")
  let intent_path = planning.ledger_path(key, "intent")
  let result_path = planning.ledger_path(key, "result")
  // One exclusive pair inside the EXISTING effects directory.
  intent_path
  |> string.starts_with("var/harness/effects/planning@")
  |> should.be_true
  intent_path |> should.not_equal(result_path)
  // The path must not carry the grant id or the attempt.
  intent_path
  |> string.contains("20261027-1013-planning-implementation")
  |> should.be_false
  intent_path |> string.contains("-a1") |> should.be_false
}

pub fn planning_transport_receipt_id_comes_from_trusted_attempt_test() {
  let b = planning_binding()
  let key = planning.logical_key(b.plan, b.task, "L-004")
  // The transport id is derived from the trusted attempt, so a caller cannot
  // supply a second identity to bypass the ledger.
  planning.transport_receipt_id(b, key) |> should.equal(key <> "-a1")
  planning.transport_receipt_id(dev.Binding(..b, attempt: 2), key)
  |> should.equal(key <> "-a2")
  // The ledger key itself is unchanged by attempt.
  planning.transport_receipt_id(dev.Binding(..b, attempt: 2), key)
  |> should.not_equal(planning.transport_receipt_id(b, key))
}

pub fn planning_payload_keys_are_closed_test() {
  // Identity, role, backend, SQL and shell carriers are absent from the
  // allowed set, so they are refused as unknown keys.
  planning.allowed_keys |> list.contains("logical_id") |> should.be_true
  planning.allowed_keys |> list.contains("target_plan") |> should.be_true
  planning.allowed_keys |> list.contains("worker") |> should.be_false
  planning.allowed_keys |> list.contains("role") |> should.be_false
  planning.allowed_keys |> list.contains("session") |> should.be_false
  planning.allowed_keys |> list.contains("attempt") |> should.be_false
  planning.allowed_keys |> list.contains("sql") |> should.be_false
  planning.allowed_keys |> list.contains("backend") |> should.be_false
  planning.allowed_keys |> list.contains("command") |> should.be_false
}

pub fn planning_target_must_be_allowlisted_test() {
  let approved = "uos/development/planning-proof/20261027-1013"
  planning.target_allowed(approved, [approved]) |> should.equal(Ok(Nil))
  // An arbitrary canonical target is refused even though it is a real plan.
  planning.target_allowed("uos/hive-development/20261027-0532", [approved])
  |> should.equal(Error("planning_target_refused"))
  planning.target_allowed("", [approved])
  |> should.equal(Error("planning_target_refused"))
  // An empty allowlist authorizes nothing.
  planning.target_allowed(approved, [])
  |> should.equal(Error("planning_target_refused"))
}

pub fn planning_evidence_path_allows_md_and_json_only_test() {
  planning.evidence_path_allowed("docs/journal/20261027-1013-x.md")
  |> should.equal(Ok(Nil))
  planning.evidence_path_allowed("governance/planning/20261027-1013-x.json")
  |> should.equal(Ok(Nil))
  // Never code or configuration.
  planning.evidence_path_allowed("apps/cepaf_gleam/src/x.gleam")
  |> should.equal(Error("evidence_path_refused"))
  planning.evidence_path_allowed("flake.nix")
  |> should.equal(Error("evidence_path_refused"))
  planning.evidence_path_allowed("tools/preflight")
  |> should.equal(Error("evidence_path_refused"))
  planning.evidence_path_allowed("../../etc/passwd")
  |> should.equal(Error("evidence_path_refused"))
}

pub fn planning_payload_byte_bound_is_exact_at_the_edge_test() {
  let limit = planning.max_payload_bytes
  // 64 KiB encoded intent, large enough for a real 13-section journal plus the
  // canonical checklist, and bounded so the ledger record and the MCP frame
  // both stay inside their own limits once escaped.
  limit |> should.equal(65_536)
  planning.payload_within_bound(string.repeat("a", limit))
  |> should.equal(Ok(Nil))
  planning.payload_within_bound(string.repeat("a", limit - 1))
  |> should.equal(Ok(Nil))
  planning.payload_within_bound(string.repeat("a", limit + 1))
  |> should.equal(Error("payload_bound_exceeded"))
  // Unicode is measured in BYTES, not graphemes: one 3-byte grapheme at the
  // boundary must not be counted as one byte.
  planning.payload_within_bound(string.repeat("界", limit / 3))
  |> should.equal(Ok(Nil))
  planning.payload_within_bound(string.repeat("界", limit / 3 + 1))
  |> should.equal(Error("payload_bound_exceeded"))
}

pub fn planning_nonzero_exit_is_never_a_pre_effect_refusal_test() {
  // Only proven pre-dispatch validation refuses. A nonzero exit, a timeout or
  // a readback disagreement is uncertain, because the effect may have landed.
  planning.classify_backend(Error("backend_exit:1\nboom"))
  |> planning.outcome_label
  |> should.equal("Uncertain")
  planning.classify_backend(Error("timeout"))
  |> planning.outcome_label
  |> should.equal("Uncertain")
  planning.classify_backend(Error("readback_mismatch"))
  |> planning.outcome_label
  |> should.equal("Uncertain")
}

pub fn planning_readback_must_match_the_requested_identity_test() {
  // Captured actual CLI output, plan show --format json: one JSON record
  // line followed by the sa-plan-pipeline diagnostic line.
  let plan_raw =
    "{\"id\":\"uos/development/planning-proof/20261027-1013\",\"name\":\"proof\",\"title\":\"T\"}\nsa-plan-pipeline {\"request_id\":\"sa-plan-1\",\"command\":\"--plan-show\"}"
  planning.readback_matches(
    "uos/development/planning-proof/20261027-1013",
    "",
    "proof",
    "T",
    plan_raw,
  )
  |> should.equal(Ok(Nil))
  // An alias that resolves to a different id is refused.
  planning.readback_matches(
    "uos/development/planning-proof/20261027-1013",
    "",
    "proof",
    "T",
    "{\"id\":\"uos/other/alias\",\"name\":\"proof\",\"title\":\"T\"}",
  )
  |> should.equal(Error("readback_identity_mismatch"))
  // Captured actual CLI output, task show --format json: parent binding
  // must match as well as the identity.
  let task_raw =
    "{\"plan_id\":\"uos/development/planning-proof/20261027-1013\",\"id\":\"T01\",\"name\":\"T01\",\"title\":\"T\",\"parent_id\":\"-\",\"state\":\"available\"}\nsa-plan-pipeline {\"command\":\"--task-show\"}"
  planning.readback_matches(
    "T01",
    "uos/development/planning-proof/20261027-1013",
    "T01",
    "T",
    task_raw,
  )
  |> should.equal(Ok(Nil))
  planning.readback_matches("T01", "uos/wrong/parent", "T01", "T", task_raw)
  |> should.equal(Error("readback_parent_mismatch"))
  // Title carries spaces, and the JSON record keeps them intact.
  planning.readback_matches(
    "T01",
    "uos/development/planning-proof/20261027-1013",
    "T01",
    "wrong title",
    task_raw,
  )
  |> should.equal(Error("readback_title_mismatch"))
  // Stdout as a whole is not JSON, and extra records are ambiguous.
  planning.record_line("not json\nsa-plan-pipeline {}")
  |> should.equal(Error("readback_unexpected_output"))
  planning.record_line("{\"id\":\"a\"}\n{\"id\":\"b\"}")
  |> should.equal(Error("readback_ambiguous"))
  planning.record_line("sa-plan-pipeline {}")
  |> should.equal(Error("readback_absent"))
}

pub fn planning_submit_refuses_unknown_and_pending_before_dispatch_test() {
  let execution =
    a.Execution(
      grant(),
      scope(),
      planning_binding(),
      "var/harness/20261027-1013-planning-current-risk.json",
    )
  // An unknown intent is refused by prevalidation, with no dispatch at all.
  ops.submit_planning_outcome(
    execution,
    value.Object([#("intent", value.Text("RunSql"))]),
  )
  |> should.equal(Error("unknown_intent"))
  // A missing logical id is refused before dispatch.
  ops.submit_planning_outcome(
    execution,
    value.Object([#("intent", value.Text("CreatePlan"))]),
  )
  |> should.equal(Error("logical_id_required"))
  // An unknown payload key is refused before dispatch.
  ops.submit_planning_outcome(
    execution,
    value.Object([
      #("intent", value.Text("CreatePlan")),
      #("logical_id", value.Text("L-100")),
      #("worker", value.Text("impostor")),
    ]),
  )
  |> should.equal(Error("unknown_payload_key:worker"))
}

// --- Interpreter transition laws, driven through the real shared path -------
//
// These exercise planning.submit_with, the same decision path the dispatch arm
// uses, with a bounded in-memory backend. No canonical Sa-plan row is created
// and no CLI runs: the backend is injected.

fn planning_execution() {
  a.Execution(
    grant(),
    scope(),
    dev.Binding(
      "development",
      "uos/test/planning",
      "PLANNING_LAWS",
      "worker",
      1,
      "session",
      1,
    ),
    "var/harness/20261027-1013-planning-current-risk.json",
  )
}

fn ok_plan_readback(id: String, title: String) -> String {
  "{\"id\":\""
  <> id
  <> "\",\"name\":\""
  <> id
  <> "\",\"title\":\""
  <> title
  <> "\"}\nsa-plan-pipeline {\"command\":\"--plan-show\"}"
}

fn stub_backend(
  dispatch: Result(String, String),
  readback: Result(String, String),
) {
  planning.Backend(
    dispatch: fn(_argv) { dispatch },
    readback: fn(_argv) { readback },
    write_evidence: fn(_path, _body) { Ok(Nil) },
  )
}

pub fn planning_prevalidation_refuses_before_any_dispatch_test() {
  let execution = planning_execution()
  // A dispatch that would panic if reached proves these refusals are pre-effect.
  let backend =
    planning.Backend(
      dispatch: fn(_argv) { Error("DISPATCH_MUST_NOT_RUN") },
      readback: fn(_argv) { Error("READBACK_MUST_NOT_RUN") },
      write_evidence: fn(_path, _body) { Error("WRITE_MUST_NOT_RUN") },
    )
  planning.submit_with(
    execution,
    value.Object([#("intent", value.Text("RunSql"))]),
    backend,
  )
  |> should.equal(Error("unknown_intent"))
  planning.submit_with(
    execution,
    value.Object([#("intent", value.Text("CreatePlan"))]),
    backend,
  )
  |> should.equal(Error("logical_id_required"))
  planning.submit_with(
    execution,
    value.Object([
      #("intent", value.Text("CreatePlan")),
      #("logical_id", value.Text("L-1")),
      #("worker", value.Text("impostor")),
    ]),
    backend,
  )
  |> should.equal(Error("unknown_payload_key:worker"))
  planning.submit_with(
    execution,
    value.Object([
      #("intent", value.Text("CreatePlan")),
      #("logical_id", value.Text("L-1")),
      #("logical_id", value.Text("L-2")),
    ]),
    backend,
  )
  |> should.equal(Error("duplicate_payload_key:logical_id"))
}

pub fn planning_saved_record_is_validated_whole_test() {
  let binding = planning_execution().binding
  let key = planning.logical_key(binding.plan, binding.task, "L-9")
  let payload =
    planning.canonical_payload("CreatePlan", "L-9", "t", "T", "ti", "", "")
  let good =
    planning.ledger_record(
      key,
      binding,
      "CreatePlan",
      payload,
      planning.Applied,
      "d",
    )
    |> json.to_string
  planning.validate_saved(good, key, binding, payload)
  |> should.equal(Ok(Nil))
  // A record for another key, parent or payload is never usable as a replay.
  planning.validate_saved(good, "other-key", binding, payload)
  |> should.equal(Error("ledger_key_mismatch"))
  planning.validate_saved(
    good,
    key,
    dev.Binding(..binding, task: "OTHER_TASK"),
    payload,
  )
  |> should.equal(Error("ledger_parent_mismatch"))
  planning.validate_saved(good, key, binding, "different payload")
  |> should.equal(Error("payload_conflict"))
  planning.validate_saved("{\"schema\":\"wrong\"}", key, binding, payload)
  |> should.equal(Error("ledger_schema_mismatch"))
}

pub fn planning_uncertain_outcome_is_never_a_refusal_test() {
  // Every post-reservation failure class classifies as Uncertain, because the
  // canonical effect may already have landed.
  planning.classify_backend(Error("backend_exit:1"))
  |> planning.outcome_label
  |> should.equal("Uncertain")
  planning.classify_backend(Error("timeout"))
  |> planning.outcome_label
  |> should.equal("Uncertain")
  planning.classify_backend(Ok("anything"))
  |> planning.outcome_label
  |> should.equal("Applied")
}

pub fn planning_readback_failure_yields_uncertain_not_applied_test() {
  // A dispatch that succeeds with a readback that disagrees must not be
  // reported as success. The identity check is what makes it evidence.
  planning.readback_matches(
    "uos/development/planning-proof/20261027-1013",
    "",
    "uos/development/planning-proof/20261027-1013",
    "T",
    ok_plan_readback("uos/other/alias", "T"),
  )
  |> should.equal(Error("readback_identity_mismatch"))
  planning.readback_matches(
    "uos/development/planning-proof/20261027-1013",
    "",
    "uos/development/planning-proof/20261027-1013",
    "T",
    ok_plan_readback("uos/development/planning-proof/20261027-1013", "T"),
  )
  |> should.equal(Ok(Nil))
}

fn publication_execution() {
  let e = planning_execution()
  let publish_path = "governance/planning/command-publish-probe.json"
  a.Execution(..e, scope: a.Scope(..e.scope, writes: [publish_path]))
}

fn uncertain_publish_records(
  execution: a.Execution,
  logical_id: String,
  detail: String,
) {
  let target = "uos/test/proof/command-publish"
  let path = "governance/planning/command-publish-probe.json"
  let body = "{\"probe\":\"bounded\"}"
  let key =
    planning.logical_key(
      execution.binding.plan,
      execution.binding.task,
      logical_id,
    )
  let payload =
    planning.canonical_payload(
      "PublishEvidence",
      logical_id,
      target,
      "",
      "bounded publish probe",
      path,
      body,
    )
  let intent =
    planning.ledger_record(
      key,
      execution.binding,
      "PublishEvidence",
      payload,
      planning.Uncertain("reserved"),
      "intent reserved before dispatch",
    )
    |> json.to_string
  let result =
    planning.ledger_record(
      key,
      execution.binding,
      "PublishEvidence",
      payload,
      planning.Uncertain(detail),
      detail,
    )
    |> json.to_string
  #(
    key,
    payload,
    intent,
    result,
    planning.pointer_record(execution.binding.plan, execution.binding.task, key),
  )
}

pub fn planning_publish_missing_target_refuses_before_writer_test() {
  let prepared =
    planning.Prepared(
      planning.PublishEvidence,
      "PublishEvidence",
      "missing-target-probe",
      "uos/test/proof/missing-target",
      "",
      "planning/evidence",
      "missing target precondition",
      "governance/planning/command-publish-probe.json",
      "{\"probe\":\"bounded\"}",
      "payload",
    )
  let backend =
    planning.Backend(
      dispatch: fn(_) { Error("DISPATCH_MUST_NOT_RUN") },
      readback: fn(_) { Error("sa-plan exited 1") },
      write_evidence: fn(_, _) { Error("WRITE_MUST_NOT_RUN") },
    )
  planning.preflight_target(backend, prepared)
  |> should.equal(Error("refused:planning_target_precondition"))
}

pub fn planning_resolution_classifies_only_known_read_phase_failure_test() {
  let execution = publication_execution()
  let #(key, payload, intent, result, pointer) =
    uncertain_publish_records(
      execution,
      "known-read-failure",
      "sa-plan exited 1",
    )
  planning.classify_resolution(
    execution,
    "known-read-failure",
    pointer,
    intent,
    result,
    None,
    Error("not-required-for-read-phase-failure"),
    ["uos/test/proof/command-publish"],
  )
  |> should.equal(
    Ok(planning.Resolution(
      "RESOLVED_NOT_APPLIED",
      key,
      "known-read-failure",
      files.digest(payload),
      "governance/planning/command-publish-probe.json",
      None,
      None,
      "read-only plan-show failed before the evidence writer",
    )),
  )
  let #(key2, _, intent2, result2, pointer2) =
    uncertain_publish_records(execution, "unknown-outcome", "backend timeout")
  planning.classify_resolution(
    execution,
    "unknown-outcome",
    pointer2,
    intent2,
    result2,
    None,
    Error("no-postcondition"),
    ["uos/test/proof/command-publish"],
  )
  |> should.equal(Error("planning_resolution_inconclusive:" <> key2))
  planning.classify_resolution(
    execution,
    "different-logical-id",
    pointer,
    intent,
    result,
    None,
    Error("no-postcondition"),
    ["uos/test/proof/command-publish"],
  )
  |> should.equal(Error("planning_resolution_not_current"))
  planning.classify_resolution(
    execution,
    "known-read-failure",
    pointer,
    intent,
    result,
    None,
    Error("no-postcondition"),
    [],
  )
  |> should.equal(Error("planning_target_refused"))
}

pub fn planning_resolution_refuses_mutated_uncertain_payload_test() {
  let execution = publication_execution()
  let logical_id = "payload-bindings"
  let #(key, _payload, intent, result, pointer) =
    uncertain_publish_records(execution, logical_id, "sa-plan exited 1")
  let parsed = result |> json.parse(value.decoder()) |> should.be_ok
  let tampered =
    value.set(parsed, "canonical_payload", value.Text("different payload"))
    |> value.encode
    |> json.to_string
  planning.classify_resolution(
    execution,
    logical_id,
    pointer,
    intent,
    tampered,
    None,
    Error("not-required"),
    ["uos/test/proof/command-publish"],
  )
  |> should.equal(Error("planning_resolution_payload_conflict"))
  // Ensure the hostile result could not redirect the immutable ledger key.
  planning.ledger_path(key, "result")
  |> string.starts_with("var/harness/effects/planning@")
  |> should.be_true
}

pub fn planning_resolution_sidecar_binds_uncertain_record_and_andon_test() {
  let execution = publication_execution()
  let logical_id = "sidecar-bindings"
  let #(key, _payload, intent, result, pointer) =
    uncertain_publish_records(execution, logical_id, "sa-plan exited 1")
  let resolution =
    planning.classify_resolution(
      execution,
      logical_id,
      pointer,
      intent,
      result,
      None,
      Error("not-required-for-read-phase-failure"),
      ["uos/test/proof/command-publish"],
    )
    |> should.be_ok
  let sidecar =
    planning.resolution_record(
      execution,
      resolution,
      intent,
      result,
      json.object([
        #("utc_us", json.string("1793160000000000")),
        #("boot_us", json.string("2425560000000")),
        #("host_id", json.string("fixture-host")),
        #("boot_id", json.string("fixture-boot")),
      ]),
    )
  planning.validate_resolution(sidecar, execution, resolution, intent, result)
  |> should.equal(Ok(Nil))
  let parsed_sidecar = sidecar |> json.parse(value.decoder()) |> should.be_ok
  let malformed_clock =
    value.set(parsed_sidecar, "observed_at", value.Text("untrusted clock"))
    |> value.encode
    |> json.to_string
  planning.validate_resolution(
    malformed_clock,
    execution,
    resolution,
    intent,
    result,
  )
  |> should.equal(Error("planning_resolution_clock"))
  let changed_scope =
    a.Execution(..execution, scope: a.Scope(..execution.scope, writes: []))
  planning.validate_resolution(
    sidecar,
    changed_scope,
    resolution,
    intent,
    result,
  )
  |> should.equal(Error("planning_resolution_scope"))
  planning.validate_resolution(
    sidecar,
    execution,
    resolution,
    intent,
    result <> " ",
  )
  |> should.be_error
  planning.validate_resolution(sidecar, execution, resolution, intent, result)
  |> should.equal(Ok(Nil))
  planning.decide_andon_with_resolution(
    Some(pointer),
    Some(result),
    Some(sidecar),
    execution.binding.plan,
    execution.binding.task,
  )
  |> should.equal(Ok(Nil))
  // The resolution is a sidecar; the original uncertainty remains byte-stable.
  result |> json.parse(value.decoder()) |> should.be_ok
  planning.resolution_path(key)
  |> string.ends_with("@resolution.json")
  |> should.be_true
}

pub fn planning_resolution_receipt_keeps_task_context_test() {
  mcp.planning_resolution_receipt(
    json.object([
      #("kind", json.string("planning_resolution")),
      #("disposition", json.string("RESOLVED_NOT_APPLIED")),
    ]),
  )
  |> should.be_true
  mcp.planning_resolution_receipt(
    json.object([
      #("state", json.string("completed")),
    ]),
  )
  |> should.be_false
}

pub fn planning_resolution_applied_requires_exact_scoped_postcondition_test() {
  let execution = publication_execution()
  let logical_id = "exact-evidence-observation"
  let #(key, payload, intent, result, pointer) =
    uncertain_publish_records(
      execution,
      logical_id,
      "evidence_readback_failed:closed",
    )
  let body = "{\"probe\":\"bounded\"}"
  planning.classify_resolution(
    execution,
    logical_id,
    pointer,
    intent,
    result,
    Some(body),
    Error("not-required"),
    ["uos/test/proof/command-publish"],
  )
  |> should.equal(
    Ok(planning.Resolution(
      "RESOLVED_APPLIED",
      key,
      logical_id,
      files.digest(payload),
      "governance/planning/command-publish-probe.json",
      Some(files.digest(body)),
      None,
      "exact evidence bytes observed at the scoped publish path",
    )),
  )
  planning.classify_resolution(
    execution,
    logical_id,
    pointer,
    intent,
    result,
    Some("different bytes"),
    Error("not-required"),
    ["uos/test/proof/command-publish"],
  )
  |> should.equal(Error("planning_resolution_evidence_mismatch"))
}

pub fn active_assessment_actor_uses_canonical_claim_worker_test() {
  let record =
    value.Object([
      #("plan_id", value.Text("uos/test/20261028")),
      #("task_id", value.Text("COMMAND_ACCEPT")),
      #("actor", value.Text("codex-risk-observer")),
      #("task_state", value.Text("available")),
    ])
  let active =
    a.assessment_record_state(
      record,
      "uos/test/20261028",
      "COMMAND_ACCEPT",
      "executing",
      "codex-command-01a1802b",
    )
  value.get(active, "actor")
  |> should.equal(Ok(value.Text("codex-command-01a1802b")))
  value.get(active, "task_state")
  |> should.equal(Ok(value.Text("executing")))
  a.assessment_record_state(
    record,
    "uos/test/20261028",
    "OTHER_TASK",
    "executing",
    "codex-command-01a1802b",
  )
  |> should.equal(record)
}

pub fn planning_payload_bounds_hold_at_the_byte_edge_test() {
  planning.payload_within_bound(string.repeat("a", planning.max_payload_bytes))
  |> should.equal(Ok(Nil))
  planning.payload_within_bound(string.repeat(
    "a",
    planning.max_payload_bytes + 1,
  ))
  |> should.equal(Error("payload_bound_exceeded"))
  planning.payload_within_bound(string.repeat(
    "界",
    planning.max_payload_bytes / 3 + 1,
  ))
  |> should.equal(Error("payload_bound_exceeded"))
  planning.evidence_path_allowed("docs/journal/x.md") |> should.equal(Ok(Nil))
  planning.evidence_path_allowed("apps/x.gleam")
  |> should.equal(Error("evidence_path_refused"))
}

fn laws_binding() {
  dev.Binding(
    "development",
    "uos/test/planning",
    "PLANNING_LAWS",
    "worker",
    1,
    "session",
    1,
  )
}

fn applied_result(binding, key, payload) {
  planning.ledger_record(
    key,
    binding,
    "CreatePlan",
    payload,
    planning.Applied,
    "d",
  )
  |> json.to_string
}

fn uncertain_result(binding, key, payload) {
  planning.ledger_record(
    key,
    binding,
    "CreatePlan",
    payload,
    planning.Uncertain("backend_exit:1"),
    "d",
  )
  |> json.to_string
}

pub fn planning_prepare_reaches_target_name_and_size_guards_test() {
  let approved = "uos/development/planning-proof/20261027-1013"
  let base = fn(extra) {
    value.Object(list.append(
      [
        #("intent", value.Text("CreateTask")),
        #("logical_id", value.Text("L-1")),
        #("target_plan", value.Text(approved)),
        #("task_id", value.Text("t01")),
        #("title", value.Text("a title")),
      ],
      extra,
    ))
  }
  // POSITIVE: the guards are reached and pass, and the native name is derived
  // rather than overloading the caller's task id.
  let prepared = planning.prepare(base([]), [approved], [])
  case prepared {
    Ok(p) -> {
      p.native_name |> should.equal("planning/t01")
      p.target |> should.equal(approved)
      p.payload |> string.contains("CreateTask") |> should.be_true
    }
    Error(reason) -> should.equal(reason, "PREPARE_MUST_SUCCEED")
  }
  // A plan name is derived from the allowlisted target, already hierarchical.
  planning.plan_name(approved) |> should.equal(Ok(approved))
  // Native contract: at least two lowercase segments, so a bare id is invalid.
  planning.normalize_name("T01") |> should.equal(Error("native_name_invalid"))
  planning.task_name("T01") |> should.equal(Ok("planning/t01"))
  planning.normalize_name("a/B") |> should.equal(Ok("a/b"))
  planning.normalize_name("a/-bad")
  |> should.equal(Error("native_name_invalid"))
  // Target guard reached, with the same payload otherwise valid.
  planning.prepare(base([]), ["uos/other/allowed"], [])
  |> should.equal(Error("planning_target_refused"))
  // Title guard reached.
  planning.prepare(
    value.Object([
      #("intent", value.Text("CreateTask")),
      #("logical_id", value.Text("L-1")),
      #("target_plan", value.Text(approved)),
      #("task_id", value.Text("t01")),
      #("title", value.Text("")),
    ]),
    [approved],
    [],
  )
  |> should.equal(Error("title_required"))
  // Unknown and duplicate field guards reached.
  planning.prepare(base([#("worker", value.Text("x"))]), [approved], [])
  |> should.equal(Error("unknown_payload_key:worker"))
  planning.prepare(base([#("task_id", value.Text("t02"))]), [approved], [])
  |> should.equal(Error("duplicate_payload_key:task_id"))
  // Size guard reached through prepare, at the byte edge.
  planning.prepare(
    value.Object([
      #("intent", value.Text("PublishEvidence")),
      #("logical_id", value.Text("L-2")),
      #("target_plan", value.Text(approved)),
      #("title", value.Text("t")),
      #("evidence_path", value.Text("docs/journal/x.md")),
      #("evidence_body", value.Text(string.repeat("a", 70_000))),
    ]),
    [approved],
    ["docs/journal/x.md"],
  )
  |> should.equal(Error("payload_bound_exceeded"))
  // Evidence write scope guard reached.
  planning.prepare(
    value.Object([
      #("intent", value.Text("PublishEvidence")),
      #("logical_id", value.Text("L-3")),
      #("target_plan", value.Text(approved)),
      #("title", value.Text("t")),
      #("evidence_path", value.Text("docs/journal/x.md")),
      #("evidence_body", value.Text("body")),
    ]),
    [approved],
    [],
  )
  |> should.equal(Error("evidence_write_scope_refused"))
}

pub fn planning_ledger_trace_applied_replay_next_and_conflict_test() {
  let b = laws_binding()
  let k1 = planning.logical_key(b.plan, b.task, "L-1")
  let k2 = planning.logical_key(b.plan, b.task, "L-2")
  let p1 =
    planning.canonical_payload("CreatePlan", "L-1", "t", "t01", "ti", "", "")
  let p2 =
    planning.canonical_payload("CreatePlan", "L-2", "t", "t02", "ti", "", "")
  let rp = planning.ledger_path(k1, "result")
  let ip = planning.ledger_path(k1, "intent")
  // 1. First intent, nothing recorded: dispatch.
  planning.decide_ledger(None, None, k1, b, p1, rp, ip)
  |> should.equal(Ok(planning.Dispatch))
  // 2. Same id after success: Replayed, returning the SAVED record.
  let saved = applied_result(b, k1, p1)
  planning.decide_ledger(Some(saved), None, k1, b, p1, rp, ip)
  |> should.equal(Ok(planning.ReplaySaved(saved)))
  // 3. A different logical id is unaffected by the first one's record.
  planning.decide_ledger(None, None, k2, b, p2, rp, ip)
  |> should.equal(Ok(planning.Dispatch))
  // 4. Same id, changed payload: conflict, never a silent replay.
  planning.decide_ledger(Some(saved), None, k1, b, p2, rp, ip)
  |> should.equal(Error("payload_conflict"))
  // 5. A recorded uncertainty is re-surfaced, not replayed as success.
  planning.decide_ledger(
    Some(uncertain_result(b, k1, p1)),
    None,
    k1,
    b,
    p1,
    rp,
    ip,
  )
  |> should.equal(Error("uncertain:recorded_Uncertain;ledger:" <> rp))
  // 6. A pending reservation with the same payload is never redispatched.
  let pending =
    planning.ledger_record(
      k1,
      b,
      "CreatePlan",
      p1,
      planning.Uncertain("reserved"),
      "r",
    )
    |> json.to_string
  planning.decide_ledger(None, Some(pending), k1, b, p1, rp, ip)
  |> should.equal(Error("uncertain:pending_not_redispatched;ledger:" <> ip))
  // 7. Cross-attempt and cross-grant: the key is identical, so the same
  // pending record blocks a redispatch from any attempt.
  let other_attempt = dev.Binding(..b, attempt: 9)
  planning.logical_key(other_attempt.plan, other_attempt.task, "L-1")
  |> should.equal(k1)
  planning.decide_ledger(None, Some(pending), k1, other_attempt, p1, rp, ip)
  |> should.equal(Error("uncertain:pending_not_redispatched;ledger:" <> ip))
}

pub fn planning_andon_trace_applied_applied_uncertain_blocks_next_test() {
  let b = laws_binding()
  let k1 = planning.logical_key(b.plan, b.task, "L-1")
  let k2 = planning.logical_key(b.plan, b.task, "L-2")
  let p1 =
    planning.canonical_payload("CreatePlan", "L-1", "t", "t01", "ti", "", "")
  let p2 =
    planning.canonical_payload("CreatePlan", "L-2", "t", "t02", "ti", "", "")
  // No pointer yet: open.
  planning.decide_andon(None, None, b.plan, b.task)
  |> should.equal(Ok(Nil))
  // First Applied: pointer at k1 with a settled Applied result: still open, so
  // a success never latches the line shut.
  let ptr1 = planning.pointer_record(b.plan, b.task, k1)
  planning.decide_andon(
    Some(ptr1),
    Some(applied_result(b, k1, p1)),
    b.plan,
    b.task,
  )
  |> should.equal(Ok(Nil))
  // Second Applied at a different key: still open.
  let ptr2 = planning.pointer_record(b.plan, b.task, k2)
  planning.decide_andon(
    Some(ptr2),
    Some(applied_result(b, k2, p2)),
    b.plan,
    b.task,
  )
  |> should.equal(Ok(Nil))
  // Third is Uncertain: the line holds for the WHOLE parent task.
  planning.decide_andon(
    Some(ptr2),
    Some(uncertain_result(b, k2, p2)),
    b.plan,
    b.task,
  )
  |> should.equal(Error("planning_andon_held;Uncertain:" <> k2))
  // Fourth, a different logical id, is blocked by that same hold.
  planning.decide_andon(
    Some(ptr2),
    Some(uncertain_result(b, k2, p2)),
    b.plan,
    b.task,
  )
  |> should.equal(Error("planning_andon_held;Uncertain:" <> k2))
  // A reservation with no settled result holds, covering a crash after
  // reservation.
  planning.decide_andon(Some(ptr2), None, b.plan, b.task)
  |> should.equal(Error("planning_andon_held;unsettled:" <> k2))
  // A corrupt pointer or a result for another parent holds.
  planning.decide_andon(Some("{\"schema\":\"wrong\"}"), None, b.plan, b.task)
  |> should.equal(Error("planning_andon_held;pointer_corrupt"))
  planning.decide_andon(
    Some(ptr2),
    Some(applied_result(dev.Binding(..b, task: "OTHER"), k2, p2)),
    b.plan,
    b.task,
  )
  |> should.equal(Error("planning_andon_held;result_corrupt:" <> k2))
  // The pointer path excludes grant and attempt, so the hold spans both.
  planning.andon_path(b.plan, b.task)
  |> string.contains("20261027-1013-planning-implementation")
  |> should.be_false
  planning.andon_path(b.plan, b.task)
  |> should.not_equal(planning.andon_path(b.plan, "OTHER_TASK"))
}
