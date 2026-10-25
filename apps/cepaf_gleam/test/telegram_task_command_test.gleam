import cepaf_gleam/harness/telegram_task_command as task
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

fn row(id: String, state: String) {
  json.object([
    #("task_id", json.string(id)), #("state", json.string(state)),
    #("attempt", json.int(1)), #("result_present", json.bool(False)),
    #("dependencies", json.array(["PRIOR"], json.string)),
    #("worker", json.string("PRIVATE_WORKER_SECRET")),
    #("result", json.string("PRIVATE_RESULT_SECRET")),
  ])
}

fn snapshot(rows: List(json.Json), count: Int) {
  json.object([
    #("observer", json.string("uos.sa_plan.observer.v1")),
    #("authority", json.string("NONE")),
    #("runtime_admission", json.string("NOT_GRANTED")),
    #("plan_id", json.string("plan-a")),
    #("observed_tasks_total", json.int(3)),
    #("selected_count", json.int(count)),
    #("full_observation_sha256", json.string(string.repeat("a", 64))),
    #("tasks", json.array(rows, fn(x) { x })),
  ]) |> json.to_string
}

fn good() { snapshot([row("TASK", "available")], 1) }

pub fn task_identifier_bounds_and_grammar_test() {
  task.parse_task_id(" \tTASK-01/sub.id\n") |> should.equal(Ok("TASK-01/sub.id"))
  task.parse_task_id(string.repeat("a", 200)) |> should.equal(Ok(string.repeat("a", 200)))
  list.each(["", " ", "A B", "A;DROP", "plan:task", "A\r", "A\u{0}", "é", "../x?y", string.repeat("a", 201), string.repeat(" ", 2049)], fn(input) {
    task.parse_task_id(input) |> should.equal(Error("invalid_task_identifier"))
  })
  // Slash/dot are identifier data passed as --task, never a filesystem path.
  task.parse_task_id("../x") |> should.equal(Ok("../x"))
}

pub fn task_state_changes_are_observed_without_authority_grant_test() {
  list.each(["available", "executing", "completed", "failed", "blocked"], fn(state) {
    let assert Ok(reply) = task.project(snapshot([row("TASK", state)], 1), "plan-a", "TASK")
    string.contains(reply, "\"state\":\"" <> state <> "\"") |> should.equal(True)
    string.contains(reply, "\"authority\":\"NONE\"") |> should.equal(True)
    string.contains(reply, "lease freshness is not inferred") |> should.equal(True)
  })
}

pub fn task_projection_does_not_disclose_private_fields_test() {
  let assert Ok(reply) = task.project(good(), "plan-a", "TASK")
  string.contains(reply, "PRIVATE_") |> should.equal(False)
  string.contains(reply, "worker") |> should.equal(False)
  string.contains(reply, "\"dependencies\":[\"PRIOR\"]") |> should.equal(True)
}

pub fn task_snapshot_identity_and_digest_refused_test() {
  list.each([
    string.replace(good(), "uos.sa_plan.observer.v1", "forged"),
    string.replace(good(), "NONE", "GRANTED"),
    string.replace(good(), "NOT_GRANTED", "ADMITTED"),
    string.replace(good(), "plan-a", "plan-b"),
    string.replace(good(), string.repeat("a", 64), string.repeat("A", 64)),
  ], fn(raw) {
    task.project(raw, "plan-a", "TASK") |> should.equal(Error("task_observation_identity_mismatch"))
  })
  task.project(good(), "plan-a", "OTHER") |> should.equal(Error("invalid_task_row"))
}

pub fn task_missing_and_cardinality_refused_test() {
  task.project(snapshot([], 0), "plan-a", "TASK") |> should.equal(Error("task_not_found"))
  task.project(snapshot([row("TASK", "available")], 0), "plan-a", "TASK")
    |> should.equal(Error("task_observation_identity_mismatch"))
  task.project(snapshot([row("TASK", "available"), row("OTHER", "available")], 2), "plan-a", "TASK")
    |> should.equal(Error("unexpected_task_cardinality"))
}

pub fn task_invalid_metadata_refused_test() {
  list.each([
    snapshot([row("TASK", "magic-pass")], 1),
    string.replace(good(), "\"attempt\":1", "\"attempt\":-1"),
    string.replace(good(), "\"attempt\":1", "\"attempt\":1000001"),
    string.replace(good(), "[\"PRIOR\"]", "[\"bad id\"]"),
    string.replace(good(), "[\"PRIOR\"]", "[\"PRIOR\",\"PRIOR\"]"),
  ], fn(raw) {
    task.project(raw, "plan-a", "TASK") |> should.equal(Error("invalid_task_row"))
  })
}

pub fn task_payload_and_expected_identity_bounds_test() {
  task.project(string.repeat("x", 262145), "plan-a", "TASK") |> should.equal(Error("invalid_observation_bounds"))
  task.project(good(), "bad plan", "TASK") |> should.equal(Error("invalid_observation_bounds"))
  task.project(good(), "plan-a", "") |> should.equal(Error("invalid_observation_bounds"))
  list.each(["{}", "{", string.replace(good(), "\"attempt\":1", "\"attempt\":\"1\"")], fn(raw) {
    task.project(raw, "plan-a", "TASK") |> should.equal(Error("invalid_task_observation"))
  })
}

pub fn task_native_total_bounds_refused_test() {
  list.each(["0", "1001", "-1"], fn(total) {
    task.project(string.replace(good(), "\"observed_tasks_total\":3", "\"observed_tasks_total\":" <> total), "plan-a", "TASK")
      |> should.equal(Error("task_observation_identity_mismatch"))
  })
}
