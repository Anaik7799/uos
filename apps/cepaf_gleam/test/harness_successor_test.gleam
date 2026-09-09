import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/operations as ops
import cepaf_gleam/harness/successor_mcp as mcp
import cepaf_gleam/harness/value
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import uos_swarm/session_sync

fn scope() {
  a.Scope("uos/test/20260909", "clock",
    ["AGENTS.md"], ["apps/cepaf_gleam/test/harness_successor_test.gleam"],
    ["AGENTS.md"], ["harness_successor_test"], "var/harness/20260909-1751-current-risk.json")
}
fn grant() {
  a.Grant("20260909-1751-test", "var/harness/20260909-1751-test-grant.json",
    string.repeat("a", 64), "test-session", "test-worker", string.repeat("b", 64),
    "test-boot", 1000, [scope()], "docs/reviews/20260909-1751-test.json", string.repeat("c", 64))
}
pub fn short_backend_diagnostics_are_preserved_test() {
  dev.backend_diagnostic("failed: expected diagnostic") |> should.equal("failed: expected diagnostic")
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
  let outcome = dev.bounded(dev.root <> "/toolchains/nix-profile/bin/env",
    ["/uos-deliberately-absent-successor-fixture"], 3000)
  let assert Error(reason) = outcome
  reason |> string.contains("backend_exit:127") |> should.be_true
  reason |> string.contains("uos-deliberately-absent-successor-fixture") |> should.be_true
}
pub fn task_scope_excludes_old_bootstrap_and_secrets_test() {
  a.scope_valid(scope()) |> should.be_true
  a.scope_valid(a.Scope(..scope(), task: "HARNESSBOOT")) |> should.be_false
  a.scope_valid(a.Scope(..scope(), plan: "foreign/plan")) |> should.be_false
  a.scope_valid(a.Scope(..scope(), reads: [".env"])) |> should.be_false
  a.scope_valid(a.Scope(..scope(), reads: ["var/sa-plan/uos.sqlite3"])) |> should.be_false
  a.scope_valid(a.Scope(..scope(), reads: ["/home/an/dev/ver/zigvm/config.json"])) |> should.be_false
  a.scope_valid(a.Scope(..scope(), writes: ["tools/unreviewed.ml"])) |> should.be_false
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
  ops.validate_args("harness_build", value.Object([
    #("intent_id", value.Text("one")), #("worker", value.Text("forged"))])) |> should.be_error
  ops.validate_args("harness_test", value.Object([
    #("intent_id", value.Text("one")), #("backend", value.Text("shell"))])) |> should.be_error
  ops.validate_args("harness_claim", value.Object([
    #("plan", value.Text(scope().plan)), #("task", value.Text("clock")),
    #("intent_id", value.Text("one")), #("attempt", value.Integer(9))])) |> should.be_error
  ops.validate_args("arbitrary_shell", value.Object([])) |> should.be_error
}
pub fn success_replay_requires_exact_binding_and_terminal_success_test() {
  let good = json.object([#("signature", json.string("expected")), #("status", json.string("EXECUTED"))])
    |> json.to_string
  ops.replay(good, "expected") |> should.be_ok
  ops.replay(good, "other") |> should.be_error
  ops.replay("not json", "expected") |> should.be_error
  ops.replay("{\"signature\":\"expected\",\"status\":\"FAILED_OR_UNVERIFIED\"}", "expected") |> should.be_error
}
pub fn mcp_initialization_notifications_and_closed_sessions_test() {
  let state = mcp.initial(grant())
  let assert #(_, Some(before)) = mcp.handle(state, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}")
  before |> string.contains("initialize_required") |> should.be_true
  let assert #(ready, Some(init)) = mcp.handle(state, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"initialize\"}")
  init |> string.contains("uos-gleam-successor-harness") |> should.be_true
  mcp.handle(ready, "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"harness_claim\",\"arguments\":{}}}")
    |> should.equal(#(ready, None))
  let assert #(same, Some(reinit)) = mcp.handle(ready, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"initialize\"}")
  same |> should.equal(ready)
  reinit |> string.contains("already_initialized") |> should.be_true
  let #(closed, _) = mcp.handle(ready, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\"}")
  let assert #(_, Some(after)) = mcp.handle(closed, "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"initialize\"}")
  after |> string.contains("session_closed") |> should.be_true
}
pub fn literal_sa_plan_argument_construction_does_not_admit_arbitrary_shell_test() {
  let args = ops.build_args(["build"])
  args |> should.equal([
    "--chdir=" <> dev.root <> "/apps/cepaf_gleam",
    "PATH=" <> dev.root <> "/toolchains/nix-profile/bin:" <> dev.root <> "/toolchains/gleam-1.16.0/bin:" <> dev.root <> "/toolchains/opam-ocaml/bin",
    "ERL_FLAGS=+S 2:2 +A 2", "ERL_CRASH_DUMP_SECONDS=0",
    dev.root <> "/toolchains/gleam-1.16.0/bin/gleam", "build"])
}

pub fn task_namespace_conforms_to_the_real_coordinator_and_separates_plans_test() {
  let first = dev.Binding("development", "uos/first/plan", "same-task", "worker", 1, "session", 1)
  let second = dev.Binding(..first, plan: "uos/second/plan")
  let a = dev.task_resource(first)
  let b = dev.task_resource(second)
  session_sync.valid_resource(a) |> should.be_true
  session_sync.valid_resource(b) |> should.be_true
  { a != b } |> should.be_true
  dev.task_resource(dev.Binding(..first, plan: "uos/ecology/20260909-0146", task: "HARNESSBOOT"))
    |> should.equal("task:HARNESSBOOT")
}

pub fn coordinator_operation_ids_leave_room_for_composed_suffixes_test() {
  a.intent_valid(string.repeat("x", 48)) |> should.be_true
  a.intent_valid(string.repeat("x", 49)) |> should.be_false
}

fn reviewed_documents() {
  let proposal = value.Object([
    #("grant_id", value.Text("test-grant")),
    #("session", value.Text("root-session")),
    #("worker", value.Text("root-worker")),
    #("tasks", value.Array([])),
    #("review_sha256", value.Text("PENDING")),
  ])
  let path = "var/harness/20260909-1751-proposal.json"
  let hash = string.repeat("a", 64)
  let document = proposal
    |> value.set("review_sha256", value.Text(string.repeat("b", 64)))
    |> value.set("proposal_path", value.Text(path))
    |> value.set("proposal_sha256", value.Text(hash))
  let review = value.Object([
    #("schema", value.Text("uos.harness-successor-grant-review.v1")),
    #("verdict", value.Text("APPROVE_DEV_TEST_SCOPE")),
    #("reviewer", value.Object([#("session_id", value.Text("peer-session"))])),
    #("grant_proposal", value.Object([
      #("path", value.Text(path)), #("sha256", value.Text(hash)),
      #("grant_id", value.Text("test-grant")),
      #("target_session", value.Text("root-session")),
      #("target_worker", value.Text("root-worker")),
    ])),
  ])
  #(document, review, proposal)
}
pub fn review_verdict_and_independent_identity_are_mandatory_test() {
  let #(document, review, proposal) = reviewed_documents()
  a.validate_review(document, review, proposal) |> should.be_ok
  a.validate_review(document, value.set(review, "verdict", value.Text("REVISE")), proposal)
    |> should.equal(Error("review_verdict"))
  a.validate_review(document, value.set(review, "verdict", value.Text("PENDING")), proposal)
    |> should.be_error
  a.validate_review(document, value.set(review, "schema", value.Text("arbitrary")), proposal)
    |> should.be_error
  a.validate_review(document, value.set(review, "reviewer",
    value.Object([#("session_id", value.Text("root-session"))])), proposal) |> should.be_error
}
pub fn approved_review_cannot_authorize_a_different_proposal_or_scope_test() {
  let #(document, review, proposal) = reviewed_documents()
  a.validate_review(value.set(document, "proposal_sha256", value.Text(string.repeat("c", 64))),
    review, proposal) |> should.be_error
  a.validate_review(value.set(document, "proposal_path", value.Text("var/harness/other.json")),
    review, proposal) |> should.be_error
  a.validate_review(value.set(document, "worker", value.Text("another-worker")),
    review, proposal) |> should.be_error
  a.validate_review(value.set(document, "tasks", value.Array([value.Text("unreviewed")])),
    review, proposal) |> should.be_error
  a.validate_review(value.set(document, "extra_authority", value.Text("production")),
    review, proposal) |> should.be_error
  let assert value.Object(fields) = document
  a.validate_review(value.Object([#("session", value.Text("root-session")), ..fields]),
    review, proposal) |> should.be_error
}

pub fn refused_task_selection_preserves_a_usable_mcp_session_test() {
  let ready = mcp.State(..mcp.initial(grant()), initialized: True)
  let args = value.Object([
    #("plan", value.Text("uos/does-not-exist")), #("task", value.Text("clock")),
    #("intent_id", value.Text("typo")),
  ])
  let #(after, outcome) = mcp.call(ready, "harness_claim", args)
  outcome |> should.equal(Error("task_not_in_reviewed_grant"))
  after |> should.equal(ready)
  a.outcome_unknown("task_not_in_reviewed_grant") |> should.be_false
  a.outcome_unknown("intent_id") |> should.be_false
  a.outcome_unknown("claim_outcome_unknown:backend_timeout") |> should.be_true
  a.outcome_unknown("release_outcome_unknown:readback") |> should.be_true
  a.outcome_unknown("unknown_effect_outcome_requires_reconciliation") |> should.be_true
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
  let b = dev.Binding("development", "uos/review/plan", "review", "peer", 2, "peer-session", 1)
  let hash = string.repeat("a", 64)
  let row = dev.TaskRecord("completed", Some("peer"), 2, None, 0,
    Some("uos.harness-peer-review.v1:" <> hash), Some(123))
  a.review_task_matches(b, row, hash) |> should.be_true
  a.review_task_matches(b, row, string.repeat("b", 64)) |> should.be_false
  a.review_task_matches(b, dev.TaskRecord(..row, state: "executing"), hash) |> should.be_false
  a.review_task_matches(b, dev.TaskRecord(..row, result: Some("old review done")), hash) |> should.be_false
  a.review_task_matches(b, dev.TaskRecord(..row, worker: Some("root")), hash) |> should.be_false
  a.review_task_matches(dev.Binding(..b, attempt: 3), row, hash) |> should.be_false
}
pub fn nested_grant_objects_have_order_independent_unique_key_semantics_test() {
  let left = value.Object([#("tasks", value.Array([value.Object([
    #("plan", value.Text("uos/test")), #("task", value.Text("one")),
  ])]))])
  let right = value.Object([#("tasks", value.Array([value.Object([
    #("task", value.Text("one")), #("plan", value.Text("uos/test")),
  ])]))])
  a.same_value(left, right) |> should.be_true
  a.same_value(left, value.Object([#("tasks", value.Array([]))])) |> should.be_false
  a.same_value(value.Object([#("key", value.Text("x")), #("key", value.Text("x"))]),
    value.Object([#("key", value.Text("x")), #("key", value.Text("x"))])) |> should.be_false
  a.same_value(value.Array([value.Integer(1), value.Integer(2)]),
    value.Array([value.Integer(2), value.Integer(1)])) |> should.be_false
}
pub fn task_completion_cannot_bypass_an_unresolved_effect_test() {
  let b = dev.Binding("development", scope().plan, scope().task, grant().worker, 1, grant().session, 1)
  let e = a.Execution(grant(), scope(), b, scope().portfolio)
  let state = mcp.State(grant(), True, False, Some(e), True)
  let args = value.Object([
    #("intent_id", value.Text("finish")), #("journal_path", value.Text("journal")),
    #("build_intent_id", value.Text("build")), #("test_intent_id", value.Text("test")),
    #("verification_path", value.Text("verification")),
  ])
  mcp.call(state, "harness_finish", args) |> should.equal(#(state, Error("unresolved_operation_stop_line")))
}
