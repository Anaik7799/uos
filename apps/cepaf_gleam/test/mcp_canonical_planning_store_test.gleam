//// C01: real SQLite fault injection, snapshot truth, transaction fences and restart persistence.
//// Fixtures clone the observed canonical schema; no test mutates the live database.

import cepaf_gleam/mcp/adapters/canonical_planning_store as canonical
import cepaf_gleam/mcp/adapters/planning_read as reads
import cepaf_gleam/mcp/adapters/planning_write as writes
import cepaf_gleam/mcp/admission.{type ValidatedCall, ValidatedCall}
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/types.{
  type Outcome, ClientProfile, Complete, Refused, ToolError,
}
import envoy
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import mcp_canonical_gateway_wiring_test as wiring
import mcp_resilience_bdd_test as fixtures
import simplifile

const root = "/home/an/NAS-setup/uos"

@external(erlang, "mcp_stdio_ffi", "run_workspace_bounded_cd")
fn run(
  path: String,
  args: List(String),
  cwd: String,
  timeout: Int,
) -> Result(#(Int, String), String)

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn now() -> Int

fn sql(db: String, query: String) -> String {
  let bin = fixtures.fixture_sqlite_binary()
  let assert Ok(#(0, out)) =
    run(
      bin,
      ["-init", "/dev/null", "-batch", "-bail", db, query],
      fixtures.sqlite_fixture_root,
      3000,
    )
  string.trim(out)
}

fn fixture() -> String {
  fixture_schema(False)
}

fn fixture_schema(nullable: Bool) -> String {
  let db = "/tmp/uos-c01-" <> int.to_string(now()) <> ".sqlite3"
  let _ = fixtures.fixture_sqlite_binary()
  // Copy the authority read-only into the isolated SQLite fixture before inspection.
  let assert Ok(_) =
    simplifile.copy_file(root <> "/var/sa-plan/uos.sqlite3", db)
  let observed =
    sql(
      db,
      "SELECT group_concat(sql, ';') FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%';",
    )
  let assert Ok(_) = simplifile.delete_file(db)
  let schema = case nullable {
    False -> observed
    True ->
      observed
      |> string.replace("attempt INTEGER NOT NULL", "attempt INTEGER")
      |> string.replace("title TEXT NOT NULL", "title TEXT")
      |> string.replace("state TEXT NOT NULL", "state TEXT")
  }
  let _ = sql(db, schema <> ";")
  db
}

fn cleanup(db: String) {
  list.each([db, db <> "-wal", db <> "-shm", db <> "-journal"], fn(path) {
    let _ = simplifile.delete_file(path)
    Nil
  })
}

fn call(
  tool: String,
  actor: String,
  args: List(#(String, String)),
  fence: Option(Int),
) -> ValidatedCall {
  let assert Ok(spec) = registry.lookup("public", tool)
  ValidatedCall(
    spec,
    principal.from_launcher_env(
      actor,
      ClientProfile("c01-test"),
      root,
      "c01-test",
    ),
    dict.from_list(list.append([#("plan_id", "p"), #("task_id", "t")], args)),
    None,
    None,
    fence,
    None,
  )
}

fn write(db: String, call: ValidatedCall) -> Outcome {
  let #(outcome, _) =
    writes.execute(
      writes.new_canonical_store_with_db(
        fixtures.sqlite_fixture_root,
        db,
        Some(fixtures.fixture_sqlite_binary()),
      ),
      call,
    )
  outcome
}

fn success(outcome: Outcome) -> String {
  let assert Complete(payload, _) = outcome
  payload
}

fn refused(outcome: Outcome, expected: String) {
  let assert Refused(ToolError(code, _, _)) = outcome
  code |> should.equal(expected)
}

fn load(db: String, plan: String) -> reads.PlanningReadStore {
  canonical.load_read_store_with_bin(
    fixtures.sqlite_fixture_root,
    db,
    plan,
    Some(fixtures.fixture_sqlite_binary()),
  )
}

fn status(db: String, plan: String) -> String {
  reads.execute(
    load(db, "all"),
    "plan_status",
    dict.from_list([#("plan_id", plan)]),
  )
  |> success
}

fn count(payload: String, field: String, expected: Int) {
  json.parse(payload, decode.field(field, decode.int, decode.success))
  |> should.equal(Ok(expected))
}

pub fn status_includes_truthful_plan_count_test() {
  reads.execute(
    reads.sample_canonical_store("p", []),
    "plan_status",
    dict.new(),
  )
  |> success
  |> count("total_plans", 1)
}

pub fn missing_binary_is_unavailable_never_empty_available_test() {
  canonical.load_read_store_with_bin(
    root,
    root <> "/var/sa-plan/uos.sqlite3",
    "all",
    None,
  )
  |> should.equal(reads.UnavailableStore("Canonical sqlite3 binary unavailable"))
  let store =
    writes.new_canonical_store_with_db(
      root,
      root <> "/var/sa-plan/uos.sqlite3",
      None,
    )
  let #(out, after) = writes.execute(store, call("plan_add", "owner", [], None))
  refused(out, "SA_PLAN_STORE_UNAVAILABLE")
  after |> should.equal(store)
  dict.has_key(after.tasks, #("p", "t")) |> should.be_false
}

pub fn missing_symlink_and_unreadable_database_fail_closed_test() {
  let absent = "/tmp/uos-c01-absent-" <> int.to_string(now())
  load(absent, "all")
  |> should.equal(reads.UnavailableStore(
    "Canonical Sa-plan database missing, symlinked, or unreadable",
  ))
  write(absent, call("plan_add", "owner", [], None))
  |> refused("SA_PLAN_STORE_UNAVAILABLE")
  simplifile.is_file(absent) |> should.equal(Ok(False))
  let db = fixture()
  let link = db <> ".link"
  let assert Ok(_) = simplifile.create_symlink(db, link)
  load(link, "all")
  |> should.equal(reads.UnavailableStore(
    "Canonical Sa-plan database missing, symlinked, or unreadable",
  ))
  write(link, call("plan_add", "owner", [], None))
  |> refused("SA_PLAN_STORE_UNAVAILABLE")
  let assert Ok(_) = simplifile.delete_file(link)
  let assert Ok(_) = simplifile.set_permissions_octal(db, 0)
  case simplifile.read(db) {
    Error(_) -> {
      load(db, "all")
      |> should.equal(reads.UnavailableStore(
        "Canonical Sa-plan database missing, symlinked, or unreadable",
      ))
      write(db, call("plan_add", "owner", [], None))
      |> refused("SA_PLAN_STORE_UNAVAILABLE")
    }
    Ok(_) -> Nil
  }
  let assert Ok(_) = simplifile.set_permissions_octal(db, 0o600)
  cleanup(db)
}

pub fn wal_database_without_rollback_journal_sidecar_is_readable_test() {
  let db = fixture()
  sql(db, "PRAGMA journal_mode=WAL;") |> should.equal("wal")
  let assert Ok(#(0, _)) =
    run(
      fixtures.fixture_sqlite_binary(),
      [
        "-init", "/dev/null", "-batch", "-bail", db, ".filectrl persist_wal 1",
        "INSERT INTO sa_plan_plan(id,title,graph_fingerprint) VALUES('p','wal','');",
      ],
      fixtures.sqlite_fixture_root,
      3000,
    )
  simplifile.is_file(db <> "-wal") |> should.equal(Ok(True))
  simplifile.is_file(db <> "-shm") |> should.equal(Ok(True))
  should.be_true(simplifile.is_file(db <> "-journal") != Ok(True))
  list.each(["plan_status", "sa_plan_status_for"], fn(tool) {
    reads.execute(load(db, "all"), tool, dict.from_list([#("plan_id", "p")]))
    |> success
    |> json.parse(decode.at(["canonical_authority"], decode.string))
    |> should.equal(Ok("sa_plan"))
  })
  let assert Ok(_) = simplifile.create_symlink(db, db <> "-journal")
  load(db, "all")
  |> should.equal(reads.UnavailableStore(
    "Canonical Sa-plan database missing, symlinked, or unreadable",
  ))
  cleanup(db)
}

pub fn corrupt_header_never_crashes_or_mutates_test() {
  let db = "/tmp/uos-c01-corrupt-" <> int.to_string(now())
  let assert Ok(_) = simplifile.write(db, "CORRUPT_HEADER_NOT_SQLITE3")
  load(db, "all")
  |> should.equal(reads.UnavailableStore(
    "Canonical Sa-plan store corrupt or query failed",
  ))
  write(db, call("plan_add", "owner", [], None))
  |> refused("SA_PLAN_STORE_CORRUPT")
  simplifile.read(db) |> should.equal(Ok("CORRUPT_HEADER_NOT_SQLITE3"))
  cleanup(db)
}

pub fn multi_plan_counts_and_all_nine_read_tools_are_truthful_test() {
  let db = fixture()
  write(db, call("plan_add", "owner", [#("title", "first")], None)) |> success
  write(
    db,
    call(
      "plan_add",
      "owner",
      [#("plan_id", "q"), #("task_id", "u"), #("title", "second")],
      None,
    ),
  )
  |> success
  write(db, call("sa_task_claim", "owner", [], None)) |> success
  write(db, call("sa_task_complete", "owner", [#("attempt", "1")], Some(1)))
  |> success
  write(db, call("plan_add", "owner", [#("task_id", "v")], None)) |> success
  write(db, call("sa_task_claim", "owner", [#("task_id", "v")], None))
  |> success
  write(
    db,
    call(
      "sa_job_enqueue",
      "owner",
      [#("job_id", "j"), #("queue", "default")],
      None,
    ),
  )
  |> success
  write(db, call("sa_workflow_start", "owner", [#("workflow_id", "w")], None))
  |> success
  let all = status(db, "all")
  count(all, "total_plans", 2)
  count(all, "total_tasks", 3)
  count(all, "completed_tasks", 1)
  count(all, "executing_tasks", 1)
  count(all, "available_tasks", 1)
  count(all, "oban_jobs", 1)
  count(all, "temporal_workflows", 1)
  count(status(db, "p"), "total_tasks", 2)
  count(status(db, "q"), "total_tasks", 1)
  load(db, "absent") |> should.equal(reads.UnknownPlanStore("absent"))
  reads.execute(
    load(db, "all"),
    "plan_status",
    dict.from_list([#("plan_id", "absent")]),
  )
  |> refused("UNKNOWN_PLAN_ID")
  let snapshot = load(db, "")
  list.each(
    [
      "plan_list",
      "sa_plan_list",
      "plan_list_pending",
      "plan_status",
      "sa_plan_status",
      "sa_plan_status_for",
      "plan_get",
      "plan_search",
      "feature_tracker_status",
    ],
    fn(tool) {
      reads.execute(
        snapshot,
        tool,
        dict.from_list([
          #("plan_id", "q"),
          #("task_id", "u"),
          #("query", "second"),
        ]),
      )
      |> success
      Nil
    },
  )
  let payload =
    reads.execute(
      load(db, "all"),
      "plan_list",
      dict.from_list([#("status", "completed")]),
    )
    |> success
  json.parse(
    payload,
    decode.field("rows", decode.list(decode.dynamic), decode.success),
  )
  |> should.be_ok
  string.contains(payload, "\"task_id\":\"t\"") |> should.be_true
  string.contains(payload, "\"task_id\":\"u\"") |> should.be_false
  let _ =
    sql(
      db,
      "INSERT INTO sa_plan_plan(id,title,graph_fingerprint) VALUES('empty','empty','');",
    )
  count(status(db, "empty"), "total_tasks", 0)
  count(status(db, "all"), "total_plans", 3)
  cleanup(db)
}

pub fn transactional_write_fences_and_restart_persistence_test() {
  let db = fixture()
  write(
    db,
    call(
      "plan_add",
      "owner",
      [#("title", "O'Brien; DROP TABLE sa_plan_task; --")],
      None,
    ),
  )
  |> success
  write(db, call("plan_add", "owner", [], None))
  |> refused("TASK_ALREADY_EXISTS")
  write(db, call("sa_task_claim", "owner", [], None)) |> success
  write(db, call("sa_task_claim", "other", [], None))
  |> refused("TASK_ALREADY_CLAIMED")
  write(db, call("sa_task_complete", "other", [#("attempt", "1")], Some(1)))
  |> refused("PRINCIPAL_WORKER_MISMATCH")
  write(db, call("sa_task_complete", "owner", [#("attempt", "2")], Some(2)))
  |> refused("STALE_ATTEMPT_FENCE")
  write(db, call("sa_task_complete", "owner", [#("attempt", "1")], Some(2)))
  |> refused("STALE_ATTEMPT_FENCE")
  write(
    db,
    call(
      "sa_task_complete",
      "owner",
      [#("attempt", "1"), #("result", "durable ' receipt")],
      Some(1),
    ),
  )
  |> success
  write(
    db,
    call(
      "sa_job_enqueue",
      "owner",
      [#("job_id", "j"), #("args", "{\"literal\":\"O'Brien\"}")],
      None,
    ),
  )
  |> success
  write(db, call("sa_job_enqueue", "owner", [#("job_id", "j")], None))
  |> refused("JOB_ALREADY_EXISTS")
  write(
    db,
    call(
      "sa_workflow_start",
      "owner",
      [#("workflow_id", "w"), #("input", "O'Brien")],
      None,
    ),
  )
  |> success
  write(db, call("sa_workflow_start", "owner", [#("workflow_id", "w")], None))
  |> refused("WORKFLOW_ALREADY_EXISTS")
  let bridge = call("sa_bridge_submit", "owner", [#("bridge_key", "b")], None)
  write(db, bridge) |> success |> should.equal(write(db, bridge) |> success)
  sql(db, "SELECT count(*) FROM sa_plan_job;") |> should.equal("2")
  sql(db, "SELECT result FROM sa_plan_task;")
  |> should.equal("durable ' receipt")
  sql(db, "SELECT state || ':' || worker || ':' || attempt FROM sa_plan_task;")
  |> should.equal("completed:owner:1")
  count(status(db, "all"), "completed_tasks", 1)
  count(status(db, "all"), "oban_jobs", 2)
  count(status(db, "all"), "temporal_workflows", 1)
  write(db, call("sa_task_claim", "owner", [#("task_id", "absent")], None))
  |> refused("UNKNOWN_TASK_ID")
  cleanup(db)
}

pub fn blocked_transition_survives_restarts_without_widening_canonical_schema_test() {
  let db = fixture()
  write(db, call("plan_add", "owner", [], None)) |> success
  write(db, call("plan_update", "other", [#("state", "blocked")], None))
  |> refused("TASK_NOT_EXECUTING")
  write(db, call("sa_task_claim", "owner", [], None)) |> success
  let hold =
    call(
      "plan_update",
      "owner",
      [#("state", "blocked"), #("attempt", "1")],
      Some(1),
    )
  write(db, hold) |> success
  write(db, call("sa_task_claim", "owner", [], None)) |> refused("TASK_BLOCKED")
  let blocked =
    reads.execute(load(db, "all"), "plan_list", dict.new()) |> success
  string.contains(blocked, "\"state\":\"blocked\"") |> should.be_true
  list.each(["available", "executing"], fn(target) {
    write(
      db,
      call(
        "plan_update",
        "other",
        [#("state", target), #("attempt", "1")],
        Some(1),
      ),
    )
    |> refused("PRINCIPAL_WORKER_MISMATCH")
    write(
      db,
      call(
        "plan_update",
        "owner",
        [#("state", target), #("attempt", "2")],
        Some(2),
      ),
    )
    |> refused("STALE_ATTEMPT_FENCE")
  })
  let lease = sql(db, "SELECT lease_until_ns FROM sa_plan_task;")
  write(
    db,
    call(
      "plan_update",
      "owner",
      [#("state", "executing"), #("attempt", "1")],
      Some(1),
    ),
  )
  |> success
  sql(db, "SELECT count(*) FROM sa_plan_mcp_hold;") |> should.equal("0")
  sql(db, "SELECT attempt FROM sa_plan_task;") |> should.equal("1")
  sql(db, "SELECT lease_until_ns FROM sa_plan_task;") |> should.equal(lease)
  write(db, hold) |> success
  write(
    db,
    call(
      "plan_update",
      "owner",
      [#("state", "available"), #("attempt", "1")],
      Some(1),
    ),
  )
  |> success
  sql(db, "SELECT count(*) FROM sa_plan_mcp_hold;") |> should.equal("0")
  write(db, call("sa_task_claim", "owner", [], None)) |> success
  write(
    db,
    call(
      "plan_update",
      "other",
      [#("state", "blocked"), #("attempt", "2")],
      Some(2),
    ),
  )
  |> refused("PRINCIPAL_WORKER_MISMATCH")
  write(
    db,
    call(
      "plan_update",
      "owner",
      [#("state", "blocked"), #("attempt", "1")],
      Some(1),
    ),
  )
  |> refused("STALE_ATTEMPT_FENCE")
  write(
    db,
    call(
      "plan_update",
      "owner",
      [#("state", "completed"), #("attempt", "2")],
      Some(2),
    ),
  )
  |> success
  let version = sql(db, "PRAGMA schema_version;")
  write(
    db,
    call(
      "plan_update",
      "owner",
      [#("state", "blocked"), #("attempt", "2")],
      Some(2),
    ),
  )
  |> refused("COMPLETED_TASK_IMMUTABLE")
  write(
    db,
    call(
      "plan_update",
      "owner",
      [#("state", "available"), #("attempt", "2")],
      Some(2),
    ),
  )
  |> refused("COMPLETED_TASK_IMMUTABLE")
  sql(db, "SELECT state FROM sa_plan_task;") |> should.equal("completed")
  sql(db, "PRAGMA schema_version;") |> should.equal(version)
  cleanup(db)
}

pub fn control_characters_are_rejected_before_any_sql_effect_test() {
  let db = fixture()
  list.each(["nul\u{0}", "line\n", "tab\t", "del\u{7f}", "c1\u{85}"], fn(value) {
    write(db, call("plan_add", "owner", [#("title", value)], None))
    |> refused("INVALID_PLANNING_ARGUMENT")
  })
  sql(db, "SELECT count(*) FROM sa_plan_plan;") |> should.equal("0")
  cleanup(db)
}

pub fn optional_absent_tables_are_zero_but_required_missing_tables_fail_closed_test() {
  let db = fixture()
  let _ = sql(db, "DROP TABLE sa_plan_job; DROP TABLE sa_plan_workflow;")
  count(status(db, "all"), "oban_jobs", 0)
  count(status(db, "all"), "temporal_workflows", 0)
  write(db, call("sa_job_enqueue", "owner", [#("job_id", "new")], None))
  |> success
  write(db, call("sa_workflow_start", "owner", [#("workflow_id", "new")], None))
  |> success
  count(status(db, "all"), "oban_jobs", 1)
  count(status(db, "all"), "temporal_workflows", 1)
  let _ = sql(db, "DROP TABLE sa_plan_task;")
  load(db, "all")
  |> should.equal(reads.UnavailableStore(
    "Canonical Sa-plan store corrupt or query failed",
  ))
  cleanup(db)
}

pub fn snapshot_row_and_output_bounds_are_explicit_test() {
  let db = fixture()
  let _ =
    sql(
      db,
      "INSERT INTO sa_plan_plan(id,title,graph_fingerprint) VALUES('p','p',''),('z','last',''); WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<504) INSERT INTO sa_plan_task(plan_id,id,ordinal,task_type,title,state) SELECT 'p',printf('%03d',i),i,'task',hex(zeroblob(1024)),'available' FROM n; INSERT INTO sa_plan_task(plan_id,id,ordinal,task_type,title,state) VALUES('z','505',505,'task','last task','available');",
    )
  count(status(db, "all"), "total_tasks", 505)
  let snapshot = load(db, "all")
  reads.execute(snapshot, "plan_get", dict.from_list([#("task_id", "505")]))
  |> refused("SA_PLAN_SNAPSHOT_TRUNCATED")
  let payload = reads.execute(snapshot, "plan_list", dict.new()) |> success
  json.parse(payload, decode.at(["truncated"], decode.bool))
  |> should.equal(Ok(True))
  list.each(
    ["plan_search", "plan_list_pending", "sa_plan_list", "plan_status"],
    fn(tool) {
      let body = reads.execute(snapshot, tool, dict.new()) |> success
      json.parse(body, decode.at(["truncated"], decode.bool))
      |> should.equal(Ok(True))
    },
  )
  let body =
    reads.execute(
      load(db, "z"),
      "plan_get",
      dict.from_list([#("task_id", "505")]),
    )
    |> success
  string.contains(body, "last task") |> should.be_true
  let last = reads.execute(load(db, "z"), "plan_list", dict.new()) |> success
  json.parse(last, decode.at(["truncated"], decode.bool))
  |> should.equal(Ok(False))
  // Legacy oversize titles cannot make the entire read model unavailable.
  let _ =
    sql(
      db,
      "UPDATE sa_plan_task SET title=hex(zeroblob(270000)) WHERE id='001';",
    )
  count(status(db, "all"), "total_tasks", 505)
  // A 2 KiB UTF-8 title still fits the transport by using a cumulative byte budget.
  let _ =
    sql(
      db,
      "UPDATE sa_plan_task SET title=replace(hex(zeroblob(256)),'0','界');",
    )
  count(status(db, "all"), "total_tasks", 505)
  cleanup(db)
}

pub fn concurrent_claims_have_exactly_one_committed_owner_test() {
  let db = fixture()
  write(db, call("plan_add", "owner", [], None)) |> success
  let replies = process.new_subject()
  list.each([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16], fn(n) {
    let _ =
      process.spawn(fn() {
        process.send(
          replies,
          write(
            db,
            call("sa_task_claim", "worker-" <> int.to_string(n), [], None),
          ),
        )
      })
    Nil
  })
  let results =
    list.map([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16], fn(_) {
      let assert Ok(out) = process.receive(replies, 8000)
      out
    })
  list.count(results, fn(out) {
    case out {
      Complete(_, _) -> True
      _ -> False
    }
  })
  |> should.equal(1)
  list.each(results, fn(out) {
    case out {
      Complete(_, _) -> Nil
      _ -> refused(out, "TASK_ALREADY_CLAIMED")
    }
  })
  sql(db, "SELECT state || ':' || attempt FROM sa_plan_task;")
  |> should.equal("executing:1")
  cleanup(db)
}

pub fn legacy_task_table_fallback_and_optional_compatibility_counts_test() {
  let db = fixture()
  let _ =
    sql(
      db,
      "ALTER TABLE sa_plan_task RENAME TO tasks; DROP TABLE sa_plan_job; DROP TABLE sa_plan_workflow; CREATE TABLE sa_oban_job(id TEXT); CREATE TABLE sa_temporal_workflow(id TEXT); INSERT INTO sa_plan_plan(id,title,graph_fingerprint) VALUES('p','p',''); INSERT INTO tasks(plan_id,id,ordinal,task_type,title,state) VALUES('p','t',0,'task','legacy','available'); INSERT INTO sa_oban_job VALUES('j'); INSERT INTO sa_temporal_workflow VALUES('w');",
    )
  let snapshot = status(db, "all")
  count(snapshot, "total_tasks", 1)
  count(snapshot, "oban_jobs", 1)
  count(snapshot, "temporal_workflows", 1)
  cleanup(db)
}

pub fn invalid_json_and_nonzero_sqlite_override_are_unavailable_test() {
  let db = fixture()
  list.each(["/usr/bin/true", "/usr/bin/false"], fn(bin) {
    canonical.load_read_store_with_bin(root, db, "all", Some(bin))
    |> should.equal(reads.UnavailableStore(
      "Canonical Sa-plan store corrupt or query failed",
    ))
    let store = writes.new_canonical_store_with_db(root, db, Some(bin))
    let #(out, after) =
      writes.execute(store, call("plan_add", "owner", [], None))
    refused(out, "SA_PLAN_STORE_UNAVAILABLE")
    after |> should.equal(store)
  })
  sql(db, "SELECT count(*) FROM sa_plan_task;") |> should.equal("0")
  cleanup(db)
}

pub fn ownerless_executing_row_cannot_be_completed_test() {
  let db = fixture()
  write(db, call("plan_add", "owner", [], None)) |> success
  let _ =
    sql(db, "UPDATE sa_plan_task SET state='executing',worker=NULL,attempt=1;")
  write(db, call("sa_task_complete", "owner", [#("attempt", "1")], Some(1)))
  |> refused("PRINCIPAL_WORKER_MISMATCH")
  sql(db, "SELECT state FROM sa_plan_task;") |> should.equal("executing")
  cleanup(db)
}

pub fn expired_leases_refuse_completion_and_allow_fenced_reclaim_test() {
  let db = fixture()
  write(db, call("plan_add", "owner", [], None)) |> success
  write(db, call("sa_task_claim", "owner", [], None)) |> success
  let _ = sql(db, "UPDATE sa_plan_task SET lease_until_ns=1;")
  list.each(["sa_task_complete", "plan_update"], fn(tool) {
    let out =
      write(
        db,
        call(
          tool,
          "owner",
          [#("state", "completed"), #("attempt", "1")],
          Some(1),
        ),
      )
    let assert Refused(ToolError("TASK_LEASE_EXPIRED", _, types.NonRetryable)) =
      out
  })
  write(
    db,
    call(
      "plan_update",
      "owner",
      [#("state", "blocked"), #("attempt", "1")],
      Some(1),
    ),
  )
  |> refused("TASK_LEASE_EXPIRED")
  write(db, call("sa_task_claim", "new-owner", [], None)) |> success
  sql(db, "SELECT worker || ':' || attempt FROM sa_plan_task;")
  |> should.equal("new-owner:2")
  sql(db, "SELECT lease_until_ns>1 FROM sa_plan_task;") |> should.equal("1")
  write(db, call("sa_task_complete", "owner", [#("attempt", "1")], Some(1)))
  |> refused("PRINCIPAL_WORKER_MISMATCH")
  write(db, call("sa_task_complete", "new-owner", [#("attempt", "1")], Some(1)))
  |> refused("STALE_ATTEMPT_FENCE")
  cleanup(db)
}

pub fn nullable_attempt_and_title_do_not_bypass_fences_or_break_reads_test() {
  let db = fixture_schema(True)
  write(db, call("plan_add", "owner", [], None)) |> success
  write(db, call("sa_task_claim", "owner", [], None)) |> success
  let _ = sql(db, "UPDATE sa_plan_task SET attempt=NULL,title=NULL;")
  list.each(["sa_task_complete", "plan_update"], fn(tool) {
    write(
      db,
      call(tool, "owner", [#("state", "completed"), #("attempt", "1")], Some(1)),
    )
    |> refused("STALE_ATTEMPT_FENCE")
  })
  write(db, call("sa_task_complete", "owner", [#("attempt", "-1")], None))
  |> refused("STALE_ATTEMPT_FENCE")
  count(status(db, "all"), "total_tasks", 1)
  let body =
    reads.execute(
      load(db, "p"),
      "plan_get",
      dict.from_list([#("task_id", "t")]),
    )
    |> success
  count(body, "attempt", 0)
  let _ = sql(db, "UPDATE sa_plan_task SET lease_until_ns=1;")
  write(db, call("sa_task_claim", "new", [], None)) |> success
  sql(db, "SELECT attempt FROM sa_plan_task;") |> should.equal("1")
  cleanup(db)
}

pub fn byte_size_limits_refuse_before_any_database_effect_test() {
  let db = fixture()
  let version = sql(db, "PRAGMA schema_version;")
  list.each(
    [
      #("title", string.repeat("x", 2049)),
      #("title", string.repeat("界", 683)),
      #("plan_id", string.repeat("p", 257)),
      #("task_id", string.repeat("t", 257)),
      #("result", string.repeat("r", 8193)),
    ],
    fn(pair) {
      write(db, call("plan_add", "owner", [pair], None))
      |> refused("INVALID_ARGUMENT")
    },
  )
  list.each(
    [
      #("sa_job_enqueue", "job_id"),
      #("sa_workflow_start", "workflow_id"),
      #("sa_bridge_submit", "bridge_key"),
    ],
    fn(pair) {
      write(
        db,
        call(pair.0, "owner", [#(pair.1, string.repeat("i", 257))], None),
      )
      |> refused("INVALID_ARGUMENT")
    },
  )
  sql(db, "PRAGMA schema_version;") |> should.equal(version)
  sql(db, "SELECT count(*) FROM sa_plan_task;") |> should.equal("0")
  write(
    db,
    call("plan_add", "owner", [#("title", string.repeat("x", 2048))], None),
  )
  |> success
  count(status(db, "all"), "total_tasks", 1)
  cleanup(db)
}

pub fn noncanonical_database_refuses_all_writes_without_ddl_test() {
  let db = "/tmp/uos-c01-empty-" <> int.to_string(now()) <> ".sqlite3"
  let assert Ok(_) = simplifile.write(db, "")
  list.each(
    [
      "plan_add",
      "sa_task_claim",
      "sa_task_complete",
      "plan_update",
      "sa_job_enqueue",
      "sa_workflow_start",
      "sa_bridge_submit",
    ],
    fn(tool) {
      write(
        db,
        call(
          tool,
          "owner",
          [#("job_id", "j"), #("workflow_id", "w"), #("bridge_key", "b")],
          None,
        ),
      )
      |> refused("SA_PLAN_SCHEMA_MISSING")
      sql(db, "SELECT count(*) FROM sqlite_master WHERE type='table';")
      |> should.equal("0")
      simplifile.read(db) |> should.equal(Ok(""))
    },
  )
  let _ = sql(db, "CREATE TABLE unrelated(id TEXT);")
  write(db, call("sa_job_enqueue", "owner", [#("job_id", "j")], None))
  |> refused("SA_PLAN_SCHEMA_MISSING")
  sql(db, "SELECT count(*) FROM sqlite_master WHERE type='table';")
  |> should.equal("1")
  cleanup(db)
  cleanup(db)
}

pub fn refused_write_rolls_back_auxiliary_ddl_and_schema_version_test() {
  let db = fixture()
  let _ =
    sql(
      db,
      "DROP TABLE IF EXISTS sa_plan_mcp_hold; DROP TABLE IF EXISTS sa_plan_mcp_bridge;",
    )
  let version = sql(db, "PRAGMA schema_version;")
  write(db, call("sa_task_claim", "owner", [], None))
  |> refused("UNKNOWN_TASK_ID")
  sql(db, "PRAGMA schema_version;") |> should.equal(version)
  sql(db, "SELECT count(*) FROM sqlite_master WHERE name='sa_plan_mcp_hold';")
  |> should.equal("0")
  write(
    db,
    call(
      "sa_job_enqueue",
      "owner",
      [#("job_id", "bridge:b"), #("name", "bridge:b")],
      None,
    ),
  )
  |> success
  let version = sql(db, "PRAGMA schema_version;")
  write(db, call("sa_bridge_submit", "owner", [#("bridge_key", "b")], None))
  |> refused("JOB_ALREADY_EXISTS")
  sql(db, "PRAGMA schema_version;") |> should.equal(version)
  sql(db, "SELECT count(*) FROM sqlite_master WHERE name='sa_plan_mcp_bridge';")
  |> should.equal("0")
  cleanup(db)
}

pub fn dependency_readiness_is_required_on_claim_and_reclaim_test() {
  let db = fixture()
  write(db, call("plan_add", "owner", [], None)) |> success
  write(db, call("plan_add", "owner", [#("task_id", "prerequisite")], None))
  |> success
  let _ =
    sql(db, "INSERT INTO sa_plan_dependency VALUES('p','t','prerequisite');")
  write(db, call("sa_task_claim", "owner", [], None))
  |> refused("TASK_DEPENDENCIES_UNMET")
  let _ =
    sql(
      db,
      "UPDATE sa_plan_task SET state='executing',worker='old',attempt=3,lease_until_ns=1 WHERE id='t';",
    )
  write(db, call("sa_task_claim", "owner", [], None))
  |> refused("TASK_DEPENDENCIES_UNMET")
  let _ =
    sql(
      db,
      "UPDATE sa_plan_task SET state='completed' WHERE id='prerequisite';",
    )
  write(db, call("sa_task_claim", "owner", [], None)) |> success
  sql(db, "SELECT attempt FROM sa_plan_task WHERE id='t';") |> should.equal("4")
  cleanup(db)
}

pub fn compatibility_dependency_columns_are_checked_test() {
  list.each(["dep_id", "depends_on"], fn(column) {
    let db = fixture()
    write(db, call("plan_add", "owner", [], None)) |> success
    let _ =
      sql(
        db,
        "CREATE TABLE sa_plan_task_dep(plan_id TEXT,task_id TEXT,"
          <> column
          <> " TEXT); INSERT INTO sa_plan_task_dep VALUES('p','t','missing');",
      )
    write(db, call("sa_task_claim", "owner", [], None))
    |> refused("TASK_DEPENDENCIES_UNMET")
    let _ = sql(db, "DELETE FROM sa_plan_task_dep;")
    write(db, call("sa_task_claim", "owner", [], None)) |> success
    cleanup(db)
  })
}

pub fn available_store_is_pure_and_unknown_counts_are_null_test() {
  let store = reads.sample_canonical_store("plain-plan", [])
  let assert reads.AvailableStore(default, _) = store
  default |> should.equal("plain-plan")
  let body = reads.execute(store, "plan_status", dict.new()) |> success
  string.contains(body, "\"oban_jobs\":null") |> should.be_true
  string.contains(body, "\"temporal_workflows\":null") |> should.be_true
  let body =
    reads.execute(
      reads.sample_canonical_store("p", [
        reads.CanonicalTaskRow("p", "t", "done", "completed", "owner", 1),
      ]),
      "feature_tracker_status",
      dict.new(),
    )
    |> success
  count(body, "observed_executed_total", 0)
  json.parse(body, decode.at(["completed_is_not_observed"], decode.bool))
  |> should.equal(Ok(True))
}

pub fn symlinked_parents_and_sidecars_are_refused_test() {
  let db = fixture()
  list.each(["-wal", "-shm"], fn(suffix) {
    let assert Ok(_) = simplifile.create_symlink(db, db <> suffix)
    load(db, "all")
    |> should.equal(reads.UnavailableStore(
      "Canonical Sa-plan database missing, symlinked, or unreadable",
    ))
    write(db, call("plan_add", "owner", [], None))
    |> refused("SA_PLAN_STORE_UNAVAILABLE")
    let _ = simplifile.delete_file(db <> suffix)
    Nil
  })
  let parent = db <> "-parent"
  let assert Ok(_) = simplifile.create_symlink("/tmp", parent)
  let name = list.last(string.split(db, "/")) |> should.be_ok
  load(parent <> "/" <> name, "all")
  |> should.equal(reads.UnavailableStore(
    "Canonical Sa-plan database missing, symlinked, or unreadable",
  ))
  let _ = simplifile.delete_file(parent)
  cleanup(db)
}

pub fn holds_require_live_leases_and_cannot_hide_completed_rows_test() {
  let db = fixture()
  write(db, call("plan_add", "owner", [], None)) |> success
  write(db, call("sa_task_claim", "owner", [], None)) |> success
  write(
    db,
    call(
      "plan_update",
      "owner",
      [#("state", "blocked"), #("attempt", "1")],
      Some(1),
    ),
  )
  |> success
  let _ = sql(db, "UPDATE sa_plan_task SET lease_until_ns=1;")
  // Expired holds confer no unhold authority. Reclaim creates a new attempt.
  write(
    db,
    call(
      "plan_update",
      "owner",
      [#("state", "available"), #("attempt", "1")],
      Some(1),
    ),
  )
  |> refused("TASK_NOT_EXECUTING")
  write(
    db,
    call(
      "plan_update",
      "owner",
      [#("state", "executing"), #("attempt", "1")],
      Some(1),
    ),
  )
  |> success
  sql(db, "SELECT attempt FROM sa_plan_task;") |> should.equal("2")
  let _ = sql(db, "UPDATE sa_plan_task SET state='completed';")
  count(status(db, "all"), "completed_tasks", 1)
  write(
    db,
    call(
      "plan_update",
      "owner",
      [#("state", "available"), #("attempt", "1")],
      Some(1),
    ),
  )
  |> refused("COMPLETED_TASK_IMMUTABLE")
  cleanup(db)
}

pub type TimedTest {
  Timeout(Int, fn() -> Nil)
}

pub fn write_timeout_requires_reconciliation_test_() -> TimedTest {
  Timeout(15, write_timeout_requires_reconciliation)
}

fn write_timeout_requires_reconciliation() {
  let db = fixture()
  let _ =
    sql(
      db,
      "CREATE TRIGGER c01_slow_insert BEFORE INSERT ON sa_plan_task BEGIN SELECT sum(x) FROM (WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1000000000) SELECT x FROM n); END;",
    )
  let out = write(db, call("plan_add", "owner", [], None))
  let assert Refused(ToolError(code, reason, types.ReconcileFirst)) = out
  code |> should.equal("SA_PLAN_WRITE_UNCERTAIN")
  reason
  |> should.equal("Canonical SQLite write timed out; reconcile before retry")
  sql(db, "SELECT count(*) FROM sa_plan_task;") |> should.equal("0")
  cleanup(db)
}

pub fn sqlite_resolution_never_falls_back_to_system_binary_test() {
  canonical.resolve_sqlite_binary(root)
  |> should.equal(
    case simplifile.is_file(root <> "/toolchains/nix-profile/bin/sqlite3") {
      Ok(True) -> Some(root <> "/toolchains/nix-profile/bin/sqlite3")
      _ -> None
    },
  )
}

pub fn ambiguous_task_id_requires_explicit_plan_test() {
  let snapshot =
    reads.multi_plan_snapshot_store(
      "all",
      ["p", "q"],
      [
        reads.CanonicalTaskRow("p", "shared", "first", "available", "", 0),
        reads.CanonicalTaskRow("q", "shared", "second", "available", "", 0),
      ],
      0,
      0,
      [
        reads.PlanTaskCounts("p", 1, 0, 0, 1),
        reads.PlanTaskCounts("q", 1, 0, 0, 1),
      ],
    )
  reads.execute(snapshot, "plan_get", dict.from_list([#("task_id", "shared")]))
  |> refused("AMBIGUOUS_TASK_ID")
  reads.execute(
    snapshot,
    "plan_get",
    dict.from_list([#("task_id", "shared"), #("plan_id", "q")]),
  )
  |> success
  |> string.contains("second")
  |> should.be_true
}

pub fn canonical_store_cannot_fall_back_after_task_dict_is_cleared_test() {
  let configured =
    writes.new_canonical_store_with_db(
      root,
      "/tmp/nonexistent-v01.sqlite3",
      None,
    )
  let cleared = writes.PlanningWriteStore(..configured, tasks: dict.new())
  let #(out, after) =
    writes.execute(cleared, call("plan_add", "owner", [], None))
  out |> refused("SA_PLAN_STORE_UNAVAILABLE")
  dict.size(after.tasks) |> should.equal(0)
}

pub fn expired_held_task_is_reclaimed_and_completed_cleanly_test() {
  let db = fixture()
  write(db, call("plan_add", "old", [], None)) |> success
  write(db, call("sa_task_claim", "old", [], None)) |> success
  write(
    db,
    call(
      "plan_update",
      "old",
      [#("state", "blocked"), #("attempt", "1")],
      Some(1),
    ),
  )
  |> success
  let _ = sql(db, "UPDATE sa_plan_task SET lease_until_ns=1;")
  let page = reads.execute(load(db, "all"), "plan_list", dict.new()) |> success
  page |> string.contains("\"state\":\"blocked\"") |> should.be_false
  write(db, call("sa_task_claim", "new", [], None)) |> success
  write(db, call("sa_task_complete", "new", [#("attempt", "2")], Some(2)))
  |> success
  sql(db, "SELECT state || ':' || worker || ':' || attempt FROM sa_plan_task;")
  |> should.equal("completed:new:2")
  cleanup(db)
}

pub fn stale_hold_does_not_block_another_channel_attempt_test() {
  let db = fixture()
  write(db, call("plan_add", "old", [], None)) |> success
  write(db, call("sa_task_claim", "old", [], None)) |> success
  write(
    db,
    call(
      "plan_update",
      "old",
      [#("state", "blocked"), #("attempt", "1")],
      Some(1),
    ),
  )
  |> success
  let _ = sql(db, "UPDATE sa_plan_task SET worker='new',attempt=2;")
  let page = reads.execute(load(db, "all"), "plan_list", dict.new()) |> success
  page |> string.contains("\"state\":\"blocked\"") |> should.be_false
  write(db, call("sa_task_complete", "new", [#("attempt", "2")], Some(2)))
  |> success
  // MCP auxiliary rows must never stop canonical plan/task deletion.
  sql(
    db,
    "PRAGMA foreign_keys=ON; DELETE FROM sa_plan_task; DELETE FROM sa_plan_plan;",
  )
  |> should.equal("")
  cleanup(db)
}

pub fn writes_use_only_one_schema_discovery_subprocess_test() {
  let db = fixture()
  write(db, call("plan_add", "owner", [], None)) |> success
  let _ =
    sql(
      db,
      "CREATE TABLE sa_plan_task_dep(plan_id TEXT,task_id TEXT,dep_id TEXT);",
    )
  let calls =
    wiring.count_subprocesses(fn() {
      write(db, call("sa_task_claim", "owner", [], None)) |> success
      Nil
    })
  cleanup(db)
  { calls <= 2 } |> should.be_true
}

pub fn default_job_schedule_is_numeric_current_time_test() {
  let db = fixture()
  let start = now()
  write(
    db,
    call("sa_job_enqueue", "owner", [#("job_id", "schedule-v01")], None),
  )
  |> success
  let raw = sql(db, "SELECT available_at_ns FROM sa_plan_job;")
  let assert Ok(scheduled) = int.parse(raw)
  cleanup(db)
  { scheduled >= start } |> should.be_true
}

pub fn sqlite_journal_symlink_is_refused_test() {
  let db = fixture()
  let target = db <> ".target"
  let assert Ok(_) = simplifile.write(target, "must stay unchanged")
  let assert Ok(_) = simplifile.create_symlink(target, db <> "-journal")
  let calls =
    wiring.count_subprocesses(fn() {
      write(db, call("plan_add", "owner", [], None))
      |> refused("SA_PLAN_STORE_UNAVAILABLE")
      Nil
    })
  { calls == 0 } |> should.be_true
  simplifile.read(target) |> should.equal(Ok("must stay unchanged"))
  cleanup(db)
  let _ = simplifile.delete_file(target)
}

pub fn canonical_cli_status_has_exact_mcp_created_plan_counts_test() {
  let db = "/tmp/uos-v01-parity-" <> int.to_string(now()) <> ".sqlite3"
  // The operator-authorized copy is isolated before MCP writes.
  let assert Ok(_) =
    simplifile.copy_file(root <> "/var/sa-plan/uos.sqlite3", db)
  let plan = "mcp/v01/" <> int.to_string(now())
  let base = [#("plan_id", plan), #("task_id", "parity-task")]
  write(db, call("plan_add", "v01", base, None)) |> success
  write(db, call("sa_task_claim", "v01", base, None)) |> success
  write(
    db,
    call(
      "plan_update",
      "v01",
      list.append(base, [#("state", "blocked"), #("attempt", "1")]),
      Some(1),
    ),
  )
  |> success
  write(
    db,
    call(
      "plan_update",
      "v01",
      list.append(base, [#("state", "available"), #("attempt", "1")]),
      Some(1),
    ),
  )
  |> success
  write(db, call("sa_task_claim", "v01", base, None)) |> success
  write(
    db,
    call(
      "sa_task_complete",
      "v01",
      list.append(base, [#("attempt", "2"), #("result", "parity")]),
      Some(2),
    ),
  )
  |> success
  write(db, call("sa_job_enqueue", "v01", [#("job_id", plan <> "/job")], None))
  |> success
  write(
    db,
    call(
      "sa_workflow_start",
      "v01",
      [#("workflow_id", plan <> "/workflow")],
      None,
    ),
  )
  |> success
  let before = envoy.get("UOS_SA_PLAN_DB")
  let _ = envoy.set("UOS_SA_PLAN_DB", db)
  let result =
    run(
      root <> "/tools/sa-plan",
      ["--format", "json", "status", plan],
      fixtures.sqlite_fixture_root,
      5000,
    )
  case before {
    Ok(old) -> {
      let _ = envoy.set("UOS_SA_PLAN_DB", old)
      Nil
    }
    Error(_) -> {
      let _ = envoy.unset("UOS_SA_PLAN_DB")
      Nil
    }
  }
  let name = sql(db, "SELECT name FROM sa_plan_plan WHERE id='" <> plan <> "';")
  let fingerprint =
    sql(
      db,
      "SELECT graph_fingerprint FROM sa_plan_plan WHERE id='" <> plan <> "';",
    )
  cleanup(db)
  name |> should.equal(plan)
  fingerprint |> should.equal("mcp-plan-v1:" <> plan)
  let assert Ok(#(0, raw)) = result
  // The guardian merges the CLI's report-only pipeline telemetry with stdout.
  let assert Ok(payload) = list.first(string.split(string.trim(raw), "\n"))
  json.parse(payload, decode.field("total", decode.string, decode.success))
  |> should.equal(Ok("1"))
  json.parse(payload, decode.field("completed", decode.string, decode.success))
  |> should.equal(Ok("1"))
}

pub fn null_task_state_cannot_bypass_transition_guard_test() {
  let db = fixture_schema(True)
  write(db, call("plan_add", "owner", [], None)) |> success
  write(db, call("sa_task_claim", "owner", [], None)) |> success
  let _ = sql(db, "UPDATE sa_plan_task SET state=NULL;")
  let out =
    write(
      db,
      call(
        "plan_update",
        "owner",
        [#("state", "blocked"), #("attempt", "1")],
        Some(1),
      ),
    )
  cleanup(db)
  out |> refused("TASK_NOT_EXECUTING")
}

pub fn single_segment_plan_gets_a_valid_hierarchical_slug_test() {
  let db = fixture()
  write(db, call("plan_add", "owner", [#("plan_id", "single plan")], None))
  |> success
  let name = sql(db, "SELECT name FROM sa_plan_plan;")
  cleanup(db)
  string.starts_with(name, "mcp/") |> should.be_true
  string.contains(name, " ") |> should.be_false
}
