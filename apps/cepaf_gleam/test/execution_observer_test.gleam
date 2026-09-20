import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/mcp
import cepaf_gleam/harness/value
import cepaf_gleam/planning/execution_observer as observer
import cepaf_gleam/planning/execution_projection as execution
import cepaf_gleam/planning/sa_plan_bridge
import cepaf_gleam/ui/web/pages/execution_progress
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import lustre/element
import simplifile

@external(erlang, "session_sync_ffi", "unique_id")
fn unique_id() -> String

fn row(plan: String, id: String, dependencies: String) -> json.Json {
  json.object([
    #("plan_id", json.string(plan)),
    #("id", json.string(id)),
    #("title", json.string("<script>alert(1)</script>")),
    #("state", json.string("available")),
    #("worker", json.null()),
    #("attempt", json.int(0)),
    #("lease_until_ns", json.null()),
    #("completed_at_ns", json.null()),
    #("result_present", json.int(0)),
    #("dependencies", json.string(dependencies)),
  ])
}

fn parse(rows: List(json.Json)) {
  rows |> json.array(fn(row) { row }) |> json.to_string |> observer.parse_tasks
}

fn fixture_command(database: String, arguments: List(String)) {
  dev.bounded(
    dev.root <> "/toolchains/nix-profile/bin/env",
    [
      "UOS_SA_PLAN_DB=" <> database,
      sa_plan_bridge.resolve_sa_plan_binary(),
      ..arguments
    ],
    3000,
  )
}

pub fn task_decoder_preserves_edges_and_refuses_foreign_or_malformed_input_test() {
  let assert Ok([task]) = parse([row(execution.plan_id, "task", "[\"dep\"]")])
  task.dependencies |> should.equal(["dep"])
  parse([row("another-plan", "task", "[]")]) |> should.be_error
  parse([row(execution.plan_id, "task", "null")]) |> should.be_error
  observer.parse_tasks("not JSON") |> should.be_error
  parse([]) |> should.be_error
  parse(list.repeat(row(execution.plan_id, "task", "[]"), 257))
  |> should.be_error
}

pub fn unavailable_ui_and_json_never_supply_zero_success_test() {
  let rendered =
    execution_progress.render(Error("database unavailable"))
    |> element.to_string
  rendered |> string.contains("Task progress unavailable") |> should.be_true
  rendered |> string.contains("<progress") |> should.be_false
  rendered |> string.contains("100%") |> should.be_false
  rendered |> string.contains("CHK-01-TIME") |> should.be_true
  rendered |> string.contains("CHK-18-JJ") |> should.be_true
  rendered |> string.contains("<details") |> should.be_true
  observer.response(Error("unavailable"))
  |> json.to_string
  |> string.contains("\"progress\":null")
  |> should.be_true
}

pub fn rendered_titles_and_errors_are_escaped_and_completion_matches_snapshot_test() {
  let assert Ok(tasks) = parse([row(execution.plan_id, "task", "[]")])
  let assert Ok(snapshot) =
    execution.project(
      tasks,
      Error("missing risk"),
      1000,
      "2026-09-21T04:00:00Z",
    )
  let rendered =
    execution_progress.render(
      Ok(observer.Observation(snapshot, "hash", "UNAVAILABLE")),
    )
    |> element.to_string
  rendered
  |> string.contains("0 / 1 canonical tasks completed")
  |> should.be_true
  rendered |> string.contains("<script>") |> should.be_false
  rendered |> string.contains("&lt;script&gt;") |> should.be_true
  rendered
  |> string.contains("Unknown / needs reconciliation")
  |> should.be_true
  rendered
  |> string.contains("http://nas-1.tail55d152.ts.net:4100/api/planning/tasks")
  |> should.be_true
}

pub fn real_private_sa_plan_snapshot_tracks_completion_without_mutation_test() {
  let parent = "/tmp/uos-progress-test-" <> unique_id()
  let assert Ok(_) = simplifile.create_directory(parent)
  let assert Ok(_) = simplifile.set_permissions_octal(parent, 0o700)
  let database = parent <> "/sa-plan.sqlite3"
  fixture_command(database, [
    "plan",
    "create",
    execution.plan_id,
    "fixture/plan",
    "Private progress fixture",
  ])
  |> should.be_ok
  fixture_command(database, [
    "task",
    "create",
    execution.plan_id,
    "parent",
    "fixture/parent",
    "Parent",
    "-",
    "-",
    "100",
  ])
  |> should.be_ok
  fixture_command(database, [
    "task",
    "create",
    execution.plan_id,
    "child",
    "fixture/child",
    "Child",
    "-",
    "parent",
    "90",
  ])
  |> should.be_ok
  let assert Ok(#(before, before_hash)) = observer.read_tasks(database)
  before |> list.length |> should.equal(2)
  let assert Ok(child) = list.find(before, fn(task) { task.id == "child" })
  child.dependencies |> should.equal(["parent"])
  let assert Ok(#(_, unchanged)) = observer.read_tasks(database)
  before_hash |> should.equal(unchanged)
  fixture_command(database, [
    "task",
    "claim",
    "fixture-worker",
    execution.plan_id,
    "60000000000",
    "parent",
  ])
  |> should.be_ok
  fixture_command(database, [
    "task",
    "complete",
    execution.plan_id,
    "parent",
    "fixture-worker",
    "1",
    "private-test receipt",
  ])
  |> should.be_ok
  let assert Ok(#(after, after_hash)) = observer.read_tasks(database)
  { before_hash != after_hash } |> should.be_true
  let assert Ok(parent_task) =
    list.find(after, fn(task) { task.id == "parent" })
  parent_task.state |> should.equal("completed")
  parent_task.result_present |> should.be_true
  parent_task.attempt |> should.equal(1)
  observer.read_tasks(parent <> "/missing.sqlite3") |> should.be_error
  simplifile.is_file(parent <> "/missing.sqlite3") |> should.equal(Ok(False))
}

pub fn mcp_discovery_exposes_strict_tool_and_unbound_calls_fail_closed_test() {
  let binding =
    dev.Binding(
      "development",
      "absent-test-plan",
      "absent-task",
      "fixture",
      1,
      "fixture",
      1,
    )
  let assert #(state, Some(_)) =
    mcp.handle(
      binding,
      mcp.initial,
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}",
    )
  let assert #(_, Some(discovery)) =
    mcp.handle(
      binding,
      state,
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}",
    )
  discovery |> string.contains("harness_execution_progress") |> should.be_true
  let assert #(_, Some(denied)) =
    mcp.handle(
      binding,
      state,
      "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"harness_execution_progress\",\"arguments\":{}}}",
    )
  denied |> string.contains("\"isError\":true") |> should.be_true
  denied |> string.contains("task_snapshot_sha256") |> should.be_false
  let assert #(_, Some(injected)) =
    mcp.handle(
      binding,
      state,
      "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"harness_execution_progress\",\"arguments\":{\"database\":\"other\"}}}",
    )
  injected |> string.contains("unexpected_progress_arguments") |> should.be_true
}

pub fn malformed_and_overlarge_risk_portfolios_are_unknown_test() {
  observer.parse_risks("null") |> should.be_error
  observer.parse_risks(string.repeat(" ", 262_145)) |> should.be_error
  let assert Ok(tasks) = parse([row(execution.plan_id, "task", "[]")])
  let assert Ok(snapshot) =
    execution.project(
      tasks,
      observer.parse_risks("[{}]"),
      1000,
      "2026-09-21T04:00:00Z",
    )
  snapshot.unknown |> should.equal(1)
  snapshot.recommendations |> should.equal([])
}

pub fn functional_query_matches_view_and_denial_dominates_observation_test() {
  let assert Ok(tasks) = parse([row(execution.plan_id, "task", "[]")])
  let assert Ok(snapshot) =
    execution.project(
      tasks,
      Error("missing risk"),
      1000,
      "2026-09-21T04:00:00Z",
    )
  let observation = observer.Observation(snapshot, "fixture", "UNAVAILABLE")
  let assert Ok(response) =
    observer.query(value.Object([]), fn() { Ok(Nil) }, fn() { Ok(observation) })
  response
  |> json.to_string
  |> should.equal(observer.to_json(observation) |> json.to_string)
  observer.query(value.Object([]), fn() { Error("expired_lease") }, fn() {
    Error("observer_must_not_run")
  })
  |> should.equal(Error("expired_lease"))
  observer.query(value.Object([]), fn() { Ok(Nil) }, fn() {
    Error("database_unavailable")
  })
  |> should.equal(Error("database_unavailable"))
}

pub fn legacy_summary_pending_count_matches_list_and_keeps_unknown_separate_test() {
  let assert Ok(tasks) = parse([row(execution.plan_id, "task", "[]")])
  let risk =
    execution.Risk(
      "task",
      "available",
      "P1",
      "ready",
      [],
      [],
      "2026-09-21T03:00:00Z",
      "2026-09-21T05:00:00Z",
      "2026-09-21T03:00:00Z",
      list.repeat(execution.Factor(5, 5, 5), 5),
    )
  list.each([Error("missing risk"), Ok([risk])], fn(risks) {
    let assert Ok(snapshot) =
      execution.project(tasks, risks, 1000, "2026-09-21T04:00:00Z")
    let body =
      observer.to_json(observer.Observation(snapshot, "fixture", "fixture"))
      |> json.to_string
    let decoder = {
      use summary <- decode.field("summary_raw", decode.string)
      use pending <- decode.field("pending_raw", decode.string)
      use tasks <- decode.field("tasks", decode.list(value.decoder()))
      use effect_authority <- decode.field("effect_authority", decode.bool)
      use system_admission <- decode.field("system_admission", decode.bool)
      decode.success(#(
        summary,
        pending,
        tasks,
        effect_authority,
        system_admission,
      ))
    }
    let assert Ok(#(summary, pending, tasks, effect_authority, system_admission)) =
      json.parse(body, decoder)
    let summary_decoder = {
      use count <- decode.field("pending", decode.int)
      decode.success(count)
    }
    let assert Ok(count) = json.parse(summary, summary_decoder)
    let assert Ok(rows) = json.parse(pending, decode.list(value.decoder()))
    count |> should.equal(list.length(rows))
    count |> should.equal(list.length(snapshot.recommendations))
    list.length(tasks) |> should.equal(list.length(snapshot.rows))
    effect_authority |> should.equal(False)
    system_admission |> should.equal(False)
    { count + snapshot.unknown } |> should.equal(1)
  })
}
