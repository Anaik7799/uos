import envoy
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleeunit
import gleeunit/should
import ocaml_counterparts/native
import ocaml_gleam_orchestration as plan
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn registers_all_tasks_and_jobs_test() {
  let assert Ok(root) = envoy.get("UOS_PLAN_TEST_ROOT")
  let assert Ok(observed) =
    plan.request("register", root <> "/registration/sa_plan.sqlite3")
  let assert Ok(task_count) =
    decode.run(observed, decode.at(["task_count"], decode.int))
  let assert Ok(job_count) =
    decode.run(observed, decode.at(["job_count"], decode.int))
  task_count |> should.equal(75)
  job_count |> should.equal(74)
  text_field(observed, "queue") |> should.equal("uos-ocaml-gleam-v1-reserved")
  text_field(observed, "workflow_state") |> should.equal("running")
  text_field(observed, "backend")
  |> should.equal("Sa_plan.Store/sqlite/local-temporal-style-history")
  let assert Ok(connected) =
    decode.run(observed, decode.at(["temporal_service_connected"], decode.bool))
  connected |> should.be_false
  let assert Ok(tasks) =
    decode.run(observed, decode.at(["tasks"], decode.list(decode.dynamic)))
  let assert Ok(pilot) =
    list.find(tasks, fn(t) { text_field(t, "id") == "OGL.04" })
  let assert Ok(deps) =
    decode.run(pilot, decode.at(["dependencies"], decode.list(decode.string)))
  deps |> should.equal(["OGL.02", "OGL.03"])
}

fn text_field(observed: Dynamic, field: String) -> String {
  let assert Ok(value) = decode.run(observed, decode.at([field], decode.string))
  value
}

fn database(name: String) -> String {
  let assert Ok(root) = envoy.get("UOS_PLAN_TEST_ROOT")
  root <> "/" <> name <> "/sa_plan.sqlite3"
}

fn integer(observed: Dynamic, field: String) -> Int {
  let assert Ok(value) = decode.run(observed, decode.at([field], decode.int))
  value
}

pub fn replay_and_new_process_readback_are_identical_test() {
  let path = database("replay")
  let assert Ok(first) = plan.request("register", path)
  let assert Ok(second) = plan.request("register", path)
  let assert Ok(reopened) = plan.request("status", path)
  second |> should.equal(first)
  reopened |> should.equal(first)
  integer(first, "completed") |> should.equal(0)
  integer(first, "executing") |> should.equal(0)
  integer(first, "ready") |> should.equal(1)
  let assert Ok(dispatch) =
    decode.run(first, decode.at(["dispatch_enabled"], decode.bool))
  dispatch |> should.be_false
  let assert Ok(events) =
    decode.run(first, decode.at(["events"], decode.list(decode.dynamic)))
  list.length(events) |> should.equal(1)
}

pub fn missing_status_never_creates_database_test() {
  let path = database("missing")
  plan.request("status", path) |> should.be_error
  simplifile.is_file(path) |> should.equal(Ok(False))
}

pub fn undeclared_paths_are_rejected_before_creation_test() {
  plan.request("register", "/tmp/not-a-uos-plan/sa_plan.sqlite3")
  |> should.be_error
  plan.request("register", database("../escape")) |> should.be_error
}

pub fn symlink_state_path_is_rejected_test() {
  let assert Ok(root) = envoy.get("UOS_PLAN_TEST_ROOT")
  let target = root <> "/symlink-target"
  let link = root <> "/symlink-alias"
  let assert Ok(_) = simplifile.create_directory(target)
  let assert Ok(_) = simplifile.create_symlink(target, link)
  plan.request("register", link <> "/sa_plan.sqlite3") |> should.be_error
  simplifile.is_file(target <> "/sa_plan.sqlite3") |> should.equal(Ok(False))
  let assert Ok(_) = simplifile.delete_file(link)
  let assert Ok(_) = simplifile.delete(target)
}

fn fixture(mode: String) -> Dynamic {
  let assert Ok(executable) = envoy.get("UOS_PLAN_FIXTURE")
  let assert Ok(response) =
    native.request_with(
      executable,
      [database(mode)],
      mode,
      json.object([]),
      30_000,
    )
  response
}

pub fn transaction_rollback_removes_partial_plan_jobs_workflow_test() {
  let observed = fixture("rollback")
  integer(observed, "plan_count") |> should.equal(0)
  integer(observed, "job_count") |> should.equal(0)
  integer(observed, "workflow_count") |> should.equal(0)
  let assert Ok(rejected) =
    decode.run(observed, decode.at(["rejected"], decode.bool))
  rejected |> should.be_true
}

pub fn conflicting_workflow_is_not_overwritten_test() {
  let observed = fixture("workflow-conflict")
  integer(observed, "plan_count") |> should.equal(0)
  integer(observed, "job_count") |> should.equal(0)
  integer(observed, "workflow_count") |> should.equal(1)
  let assert Ok(rejected) =
    decode.run(observed, decode.at(["rejected"], decode.bool))
  rejected |> should.be_true
  text_field(observed, "workflow_kind") |> should.equal("conflicting-kind")
  text_field(observed, "workflow_input") |> should.equal("unchanged-sentinel")
  let assert Ok(history) =
    decode.run(observed, decode.at(["workflow_history"], decode.dynamic))
  let assert Ok(expected) =
    json.parse(
      "[{\"sequence\":0,\"kind\":\"workflow_started\",\"payload\":\"unchanged-sentinel\",\"occurred_at_ns\":\"1000000000\"}]",
      decode.dynamic,
    )
  history |> should.equal(expected)
}

pub fn conflicting_job_rolls_back_new_plan_and_workflow_test() {
  let observed = fixture("job-conflict")
  integer(observed, "plan_count") |> should.equal(0)
  integer(observed, "job_count") |> should.equal(1)
  integer(observed, "workflow_count") |> should.equal(0)
  let assert Ok(rejected) =
    decode.run(observed, decode.at(["rejected"], decode.bool))
  rejected |> should.be_true
  text_field(observed, "job_name") |> should.equal("tests/conflicting-job")
  text_field(observed, "job_worker") |> should.equal("UnchangedSentinel")
  text_field(observed, "job_args") |> should.equal("unchanged-sentinel")
  integer(observed, "job_max_attempts") |> should.equal(1)
}

pub fn task_claims_enforce_dependencies_and_no_work_is_auto_claimed_test() {
  let observed = fixture("dependency-claims")
  let assert Ok(blocked) =
    decode.run(observed, decode.at(["dependent_refused"], decode.bool))
  let assert Ok(ready) =
    decode.run(observed, decode.at(["root_claimed"], decode.bool))
  blocked |> should.be_true
  ready |> should.be_true
  integer(observed, "job_attempts") |> should.equal(0)
}
