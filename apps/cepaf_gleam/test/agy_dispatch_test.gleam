import cepaf_gleam/harness/agy_dispatch as agy
import cepaf_gleam/harness/development as dev
import gleam/json
import gleam/list
import gleam/result
import gleeunit/should

fn request() -> agy.Request {
  agy.Request(
    dev.Binding(
      "development",
      "uos/agy-operations/test",
      "RUNNER",
      "root",
      1,
      "session",
      1,
    ),
    "uos/agy-operations/test/review",
    "agy",
    1,
    "owned-test",
    1,
    "review",
    120,
    "Bounded source review",
  )
}

fn job_args() -> String {
  json.to_string(
    json.object([
      #("plan", json.string("uos/agy-operations/test")),
      #("task", json.string("RUNNER")),
      #("parent_worker", json.string("root")),
      #("parent_attempt", json.int(1)),
      #("workspace", json.string("owned-test")),
      #("mode", json.string("review")),
    ]),
  )
}

pub fn request_refuses_path_escape_sql_and_scope_confusion_test() {
  let good = request()
  agy.validate(good) |> should.equal(Ok(Nil))
  [
    agy.Request(..good, workspace: "../var"),
    agy.Request(..good, workspace: "/canonical"),
    agy.Request(..good, job: "x'; DELETE"),
    agy.Request(..good, job: "unrelated-plan/job"),
    agy.Request(..good, job_attempt: 0),
    agy.Request(..good, workspace_epoch: 0),
    agy.Request(..good, mode: "full-host"),
    agy.Request(..good, seconds: 901),
    agy.Request(..good, seconds: 29),
    agy.Request(..good, prompt: ""),
  ]
  |> list.each(fn(r) { agy.validate(r) |> result.is_error |> should.be_true })
}

pub fn canonical_job_must_bind_parent_task_attempt_workspace_and_mode_test() {
  let r = request()
  agy.job_binding_matches(job_args(), r) |> should.be_true
  agy.job_binding_matches("{}", r) |> should.be_false
  [
    agy.Request(..r, binding: dev.Binding(..r.binding, attempt: 2)),
    agy.Request(..r, binding: dev.Binding(..r.binding, task: "OTHER")),
    agy.Request(..r, binding: dev.Binding(..r.binding, worker: "foreign")),
    agy.Request(..r, workspace: "foreign"),
    agy.Request(..r, mode: "code"),
  ]
  |> list.each(fn(other) {
    agy.job_binding_matches(job_args(), other) |> should.be_false
  })
}

pub fn review_has_no_writable_workspace_and_hides_global_mcp_configuration_test() {
  let r = request()
  let args = agy.sandbox_args(r, "uos-agy-test")
  list.filter(args, fn(x) { x == "--bind" }) |> list.length |> should.equal(2)
  list.contains(args, "/home/an/.gemini") |> should.be_true
  list.contains(args, "--dangerously-skip-permissions") |> should.be_true
  list.contains(args, dev.root <> "/.uos-workspaces/owned-test")
  |> should.be_false
  let code = agy.sandbox_args(agy.Request(..r, mode: "code"), "uos-agy-test")
  list.filter(code, fn(x) { x == "--bind" }) |> list.length |> should.equal(3)
  list.contains(code, dev.root <> "/.uos-workspaces/owned-test")
  |> should.be_true
}

pub fn operation_identity_binds_exact_request_bytes_test() {
  agy.unit_id("same") |> should.equal(agy.unit_id("same"))
  { agy.unit_id("changed") != agy.unit_id("same") } |> should.be_true
}

pub fn longer_jobs_require_both_clock_domain_leases_test() {
  let utc = 1_790_000_000_000_000
  let boot = 500_000_000
  let needed = 270_000_000
  agy.long_job_window(
    { utc + needed + 1 } * 1000,
    boot + needed + 1,
    utc,
    boot,
    240,
  )
  |> should.be_true
  agy.long_job_window(
    { utc + needed } * 1000,
    boot + needed + 1,
    utc,
    boot,
    240,
  )
  |> should.be_false
  agy.long_job_window(
    { utc + needed + 1 } * 1000,
    boot + needed,
    utc,
    boot,
    240,
  )
  |> should.be_false
}
