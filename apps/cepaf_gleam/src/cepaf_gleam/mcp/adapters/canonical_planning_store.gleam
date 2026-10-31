//// Bounded SQLite seam. Gleam owns validation, transactions and result policy;
//// the existing supervised native guardian owns subprocess lifetime/output bounds.
//// Never manufacture an empty successful store from unavailable evidence.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/adapters/feature_receipt_ledger as ledger
import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/admission.{type ValidatedCall}
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/types.{type ToolError, NonRetryable, Retryable, ToolError}
import filepath
import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

pub type WriteBackend {
  InMemoryWriteBackend
  CanonicalSqliteWriteBackend(
    root: String,
    db_path: String,
    sqlite_bin: Option(String),
  )
}

@external(erlang, "mcp_stdio_ffi", "run_workspace_bounded_cd")
fn run_bounded_cd(
  path: String,
  args: List(String),
  cwd: String,
  timeout_ms: Int,
) -> Result(#(Int, String), String)

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

type ReadMode {
  Read
}

@external(erlang, "file", "open")
fn open_read(path: String, modes: List(ReadMode)) -> Result(Dynamic, Dynamic)

@external(erlang, "file", "close")
fn close_file(fd: Dynamic) -> Dynamic

pub fn resolve_sqlite_binary(root: String) -> Option(String) {
  [
    root <> "/toolchains/nix-profile/bin/sqlite3",
    "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/sqlite3",
  ]
  |> list.find(fn(path) { simplifile.is_file(path) == Ok(True) })
  |> option.from_result
}

fn safe_parents(path: String) -> Bool {
  !ledger.has_unsafe_ancestor(filepath.directory_name(path))
}

fn database_readable(path: String) -> Bool {
  case
    !safe_parents(path)
    || list.any(["-wal", "-shm", "-journal"], fn(suffix) {
      sidecar_unsafe(path <> suffix)
    })
  {
    True -> False
    False -> database_file_readable(path)
  }
}

fn sidecar_unsafe(sidecar_path: String) -> Bool {
  case simplifile.is_symlink(sidecar_path) {
    Ok(False) | Error(simplifile.Enoent) -> False
    Ok(True) | Error(_) -> True
  }
}

fn database_file_readable(path: String) -> Bool {
  case simplifile.is_symlink(path), simplifile.is_file(path) {
    Ok(False), Ok(True) ->
      case open_read(path, [Read]) {
        Ok(fd) -> {
          let _ = close_file(fd)
          True
        }
        Error(_) -> False
      }
    _, _ -> False
  }
}

// URI mode=rw/ro prevents accidental creation if a database disappears after
// the precheck; -nofollow also rejects a final-component symlink at open time.
fn db_uri(path: String, read_only: Bool) -> String {
  let encoded =
    path
    |> string.replace("%", "%25")
    |> string.replace("?", "%3F")
    |> string.replace("#", "%23")
  "file:"
  <> encoded
  <> case read_only {
    True -> "?mode=ro"
    False -> "?mode=rw"
  }
}

fn query(
  root: String,
  db: String,
  bin: String,
  read_only: Bool,
  sql: String,
) -> Result(String, String) {
  case
    run_bounded_cd(
      bin,
      [
        "-init",
        "/dev/null",
        "-batch",
        "-bail",
        "-nofollow",
        "-noheader",
        db_uri(db, read_only),
        "PRAGMA busy_timeout=2500; " <> sql,
      ],
      root,
      case read_only {
        True -> 3000
        False -> 5000
      },
    )
  {
    Ok(#(0, output)) ->
      case bit_array.byte_size(bit_array.from_string(output)) <= 524_288 {
        False -> Error("output_limit")
        True ->
          case string.split_once(string.trim(output), "\n") {
            Ok(#("2500", payload)) -> Ok(string.trim(payload))
            _ -> Error("invalid_busy_timeout_receipt")
          }
      }
    Ok(#(_, output)) -> Error(output)
    Error(reason) -> Error(reason)
  }
}

pub fn load_read_store(
  root: String,
  requested_plan: String,
) -> planning_read.PlanningReadStore {
  load_read_store_with_bin(
    root,
    root <> "/var/sa-plan/uos.sqlite3",
    requested_plan,
    resolve_sqlite_binary(root),
  )
}

/// Observe only the canonical task fence, using the same bounded read-only
/// SQLite path as planning projections. A missing row is unavailable evidence.
pub fn load_task_fence_row(
  root: String,
  plan_id: String,
  task_id: String,
) -> Result(#(String, String, Int, Int), String) {
  use _ <- result.try(
    case
      plan_id != ""
      && task_id != ""
      && list.all([plan_id, task_id], fn(value) {
        bounded(value, 256) && valid_text(value)
      })
    {
      True -> Ok(Nil)
      False -> Error("invalid_task_fence_identifier")
    },
  )
  let db = root <> "/var/sa-plan/uos.sqlite3"
  use bin <- result.try(
    resolve_sqlite_binary(root)
    |> option.to_result("canonical_sqlite_binary_unavailable"),
  )
  use _ <- result.try(case database_readable(db) {
    True -> Ok(Nil)
    False -> Error("canonical_task_fence_database_unavailable")
  })
  use payload <- result.try(query(
    root,
    db,
    bin,
    True,
    "SELECT json_object('state',state,'worker',coalesce(worker,''),'attempt',coalesce(attempt,0),'lease_until_ns',coalesce(lease_until_ns,0)) FROM sa_plan_task WHERE plan_id="
      <> literal(plan_id)
      <> " AND id="
      <> literal(task_id)
      <> " LIMIT 1;",
  ))
  let decoder = {
    use state <- decode.field("state", decode.string)
    use worker <- decode.field("worker", decode.string)
    use attempt <- decode.field("attempt", decode.int)
    use lease <- decode.field("lease_until_ns", decode.int)
    decode.success(#(state, worker, attempt, lease))
  }
  json.parse(payload, decoder)
  |> result.map_error(fn(_) { "canonical_task_fence_missing_or_invalid" })
}

pub fn load_read_store_with_bin(
  root: String,
  db_path: String,
  requested_plan: String,
  sqlite_bin: Option(String),
) -> planning_read.PlanningReadStore {
  case bounded(requested_plan, 256) && valid_text(requested_plan) {
    False ->
      planning_read.unavailable_store("Invalid canonical plan identifier")
    True -> load_read_store_validated(root, db_path, requested_plan, sqlite_bin)
  }
}

fn load_read_store_validated(
  root: String,
  db_path: String,
  requested_plan: String,
  sqlite_bin: Option(String),
) -> planning_read.PlanningReadStore {
  case sqlite_bin {
    None ->
      planning_read.unavailable_store("Canonical sqlite3 binary unavailable")
    Some(bin) ->
      case database_readable(db_path) {
        False ->
          planning_read.unavailable_store(
            "Canonical Sa-plan database missing, symlinked, or unreadable",
          )
        True ->
          case read_snapshot(root, db_path, bin, requested_plan) {
            Ok(store) -> store
            Error(_) ->
              planning_read.unavailable_store(
                "Canonical Sa-plan store corrupt or query failed",
              )
          }
      }
  }
}

fn table_names(
  root: String,
  db: String,
  bin: String,
) -> Result(#(List(String), Int, List(String)), String) {
  use payload <- result.try(query(
    root,
    db,
    bin,
    True,
    "SELECT json_object('tables',json_group_array(name),'schema_version',(SELECT schema_version FROM pragma_schema_version),'dependency_columns',(SELECT json_group_array(name) FROM pragma_table_info('sa_plan_task_dep'))) FROM sqlite_master WHERE type='table';",
  ))
  let decoder = {
    use tables <- decode.field("tables", decode.list(decode.string))
    use version <- decode.field("schema_version", decode.int)
    use columns <- decode.field(
      "dependency_columns",
      decode.list(decode.string),
    )
    decode.success(#(tables, version, columns))
  }
  json.parse(payload, decoder)
  |> result.map_error(fn(_) { "invalid_table_json" })
}

fn optional_count(
  tables: List(String),
  canonical: String,
  compatibility: String,
) -> String {
  case list.contains(tables, canonical), list.contains(tables, compatibility) {
    True, _ -> "(SELECT count(*) FROM " <> canonical <> ")"
    False, True -> "(SELECT count(*) FROM " <> compatibility <> ")"
    False, False -> "0"
  }
}

fn read_snapshot(
  root: String,
  db: String,
  bin: String,
  requested: String,
) -> Result(planning_read.PlanningReadStore, String) {
  use schema <- result.try(table_names(root, db, bin))
  let #(tables, observed_version, _) = schema
  let snapshot = snapshot_sql(tables, "sa_plan_task", requested)
  let payload = case query(root, db, bin, True, snapshot) {
    // Legacy fallback is permitted ONLY for this precise missing-table error.
    Error(reason) ->
      case string.contains(reason, "no such table: sa_plan_task") {
        True ->
          query(root, db, bin, True, snapshot_sql(tables, "tasks", requested))
        False -> Error(reason)
      }
    ok -> ok
  }
  use payload <- result.try(payload)
  let decoder = {
    use plans <- decode.field("plans", decode.list(decode.string))
    use rows <- decode.field("rows", decode.list(row_decoder()))
    use jobs <- decode.field("jobs", decode.int)
    use workflows <- decode.field("workflows", decode.int)
    use counts <- decode.field(
      "counts",
      decode.list(planning_read.plan_task_counts_decoder()),
    )
    use matching <- decode.field("matching", decode.int)
    use version <- decode.field("schema_version", decode.int)
    decode.success(#(plans, rows, jobs, workflows, counts, version, matching))
  }
  use decoded <- result.try(
    json.parse(payload, decoder)
    |> result.map_error(fn(_) { "invalid_snapshot_json" }),
  )
  let #(plans, rows, jobs, workflows, counts, version, matching) = decoded
  // Schema discovery and row reads use separate bounded processes. Refuse a
  // topology change rather than silently report zero for a newly created table.
  use _ <- result.try(case version == observed_version {
    True -> Ok(Nil)
    False -> Error("schema_changed_during_snapshot")
  })
  case
    requested == "" || requested == "all" || list.contains(plans, requested)
  {
    False -> Ok(planning_read.UnknownPlanStore(requested))
    True ->
      Ok(planning_read.MultiPlanStore(
        case requested {
          "" -> "all"
          _ -> requested
        },
        plans,
        rows,
        dict.from_list(
          list.map(counts, fn(c) {
            #(c.plan_id, #(c.total, c.completed, c.executing, c.available))
          }),
        ),
        Some(jobs),
        Some(workflows),
        matching > list.length(rows),
      ))
  }
}

fn snapshot_sql(
  tables: List(String),
  tasks: String,
  requested: String,
) -> String {
  let plans = case list.contains(tables, "sa_plan_plan") {
    True ->
      "SELECT id AS plan_id FROM sa_plan_plan UNION SELECT plan_id FROM "
      <> tasks
    False -> "SELECT DISTINCT plan_id FROM " <> tasks
  }
  let filter = case requested == "" || requested == "all" {
    True -> ""
    False -> " WHERE t.plan_id=" <> literal(requested)
  }
  let state = case list.contains(tables, "sa_plan_mcp_hold") {
    True ->
      "CASE WHEN t.state='executing' AND EXISTS(SELECT 1 FROM sa_plan_mcp_hold h WHERE h.plan_id=t.plan_id AND h.id=t.id AND h.worker=coalesce(t.worker,'') AND h.attempt=coalesce(t.attempt,0) AND coalesce(t.lease_until_ns,0)>"
      <> int.to_string(system_time_nanos())
      <> ") THEN 'blocked' ELSE coalesce(t.state,'') END"
    False -> "coalesce(t.state,'')"
  }
  // The cumulative byte budget also covers multibyte titles and JSON escapes.
  "BEGIN; WITH candidates AS (SELECT json_object('plan_id',t.plan_id,'task_id',t.id,'title',substr(coalesce(t.title,''),1,512),'state',"
  <> state
  <> ",'worker',coalesce(t.worker,''),'attempt',coalesce(t.attempt,0)) AS payload FROM "
  <> tasks
  <> " t"
  <> filter
  <> " ORDER BY t.plan_id,t.id LIMIT 500), bounded AS (SELECT payload,sum(length(CAST(payload AS BLOB))+1) OVER (ROWS UNBOUNDED PRECEDING) AS bytes FROM candidates) SELECT json_object('plans',(SELECT json_group_array(plan_id) FROM ("
  <> plans
  <> " ORDER BY plan_id)), 'rows',(SELECT json_group_array(json(payload)) FROM bounded WHERE bytes<=350000), 'matching',(SELECT count(*) FROM "
  <> tasks
  <> " t"
  <> filter
  <> "), 'counts',(SELECT json_group_array(json_object('plan_id',plan_id,'total',total,'completed',completed,'executing',executing,'available',available)) FROM (SELECT plan_id,count(*) AS total,sum(state='completed') AS completed,sum(state='executing') AS executing,sum(state='available') AS available FROM (SELECT t.plan_id,"
  <> state
  <> " AS state FROM "
  <> tasks
  <> " t) GROUP BY plan_id)), 'jobs',"
  <> optional_count(tables, "sa_plan_job", "sa_oban_job")
  <> ", 'workflows',"
  <> optional_count(tables, "sa_plan_workflow", "sa_temporal_workflow")
  <> ", 'schema_version',(SELECT schema_version FROM pragma_schema_version)); COMMIT;"
}

fn row_decoder() -> decode.Decoder(planning_read.CanonicalTaskRow) {
  use plan <- decode.field("plan_id", decode.string)
  use id <- decode.field("task_id", decode.string)
  use title <- decode.field("title", decode.string)
  use state <- decode.field("state", decode.string)
  use worker <- decode.field("worker", decode.string)
  use attempt <- decode.field("attempt", decode.int)
  decode.success(planning_read.CanonicalTaskRow(
    plan,
    id,
    title,
    state,
    worker,
    attempt,
  ))
}

fn literal(value: String) -> String {
  "'" <> string.replace(value, "'", "''") <> "'"
}

fn plan_name(plan: String) -> String {
  case string.split(plan, "/") |> list.filter(fn(s) { s != "" }) {
    [_, _, ..] -> plan
    _ -> "mcp/" <> string.slice(files.digest(plan), 0, 24)
  }
}

fn bounded(value: String, max_bytes: Int) -> Bool {
  bit_array.byte_size(bit_array.from_string(value)) <= max_bytes
}

pub fn arguments_bounded(call: ValidatedCall) -> Bool {
  list.all(dict.to_list(call.arguments), fn(pair) {
    let limit = case pair.0 {
      "plan_id"
      | "plan"
      | "task_id"
      | "id"
      | "job_id"
      | "workflow_id"
      | "bridge_key"
      | "task"
      | "worker"
      | "name"
      | "queue"
      | "kind" -> 256
      "title" -> 2048
      _ -> 8192
    }
    bounded(pair.0, 256) && bounded(pair.1, limit)
  })
}

fn valid_text(value: String) -> Bool {
  bit_array.byte_size(bit_array.from_string(value)) <= 65_536
  && !list.any(string.to_utf_codepoints(value), fn(cp) {
    let n = string.utf_codepoint_to_int(cp)
    n < 32 || n >= 127 && n <= 159
  })
}

fn error(code: String) -> ToolError {
  ToolError(code, "Canonical Sa-plan transaction refused", case code {
    "SA_PLAN_STORE_UNAVAILABLE" -> Retryable
    _ -> NonRetryable
  })
}

fn arg(call: ValidatedCall, key: String) -> String {
  dict.get(call.arguments, key) |> result.unwrap("")
}

fn alias(call: ValidatedCall, first: String, second: String) -> String {
  case arg(call, first) {
    "" -> arg(call, second)
    value -> value
  }
}

pub fn execute(
  backend: WriteBackend,
  call: ValidatedCall,
  plan_id: String,
  task_id: String,
) -> Result(String, ToolError) {
  let actor = principal.actor_id(call.principal)
  case actor == "" {
    True -> Error(error("MISSING_AUTHENTICATED_WORKER"))
    False ->
      case
        arguments_bounded(call)
        && list.all([actor, plan_id, task_id], fn(v) { bounded(v, 256) })
      {
        False -> Error(error("INVALID_ARGUMENT"))
        True -> execute_validated(backend, call, plan_id, task_id, actor)
      }
  }
}

fn execute_validated(
  backend: WriteBackend,
  call: ValidatedCall,
  plan_id: String,
  task_id: String,
  actor: String,
) -> Result(String, ToolError) {
  case
    list.all([actor, plan_id, task_id], valid_text)
    && list.all(dict.to_list(call.arguments), fn(pair) {
      valid_text(pair.0) && valid_text(pair.1)
    })
  {
    False -> Error(error("INVALID_PLANNING_ARGUMENT"))
    True ->
      case backend {
        InMemoryWriteBackend -> Error(error("SA_PLAN_STORE_UNAVAILABLE"))
        CanonicalSqliteWriteBackend(_, _, None) ->
          Error(error("SA_PLAN_STORE_UNAVAILABLE"))
        CanonicalSqliteWriteBackend(root, db, Some(bin)) ->
          case database_readable(db) {
            False -> Error(error("SA_PLAN_STORE_UNAVAILABLE"))
            True -> {
              use schema <- result.try(
                table_names(root, db, bin)
                |> result.map_error(fn(reason) { store_error(reason) }),
              )
              let #(tables, _, columns) = schema
              use _ <- result.try(case list.contains(tables, "sa_plan_task") {
                True -> Ok(Nil)
                False -> Error(error("SA_PLAN_SCHEMA_MISSING"))
              })
              use dependencies <- result.try(
                dependency_predicate(tables, columns, plan_id, task_id)
                |> result.map_error(fn(reason) { store_error(reason) }),
              )
              use body <- result.try(write_body(
                call,
                plan_id,
                task_id,
                actor,
                dependencies,
              ))
              // RAISE(ROLLBACK) on a refusal also undoes any auxiliary DDL.
              // Emit the decision before that deliberate nonzero SQLite exit.
              let sql =
                "PRAGMA foreign_keys=ON; BEGIN IMMEDIATE; CREATE TEMP TABLE mcp_result(code TEXT NOT NULL,value TEXT NOT NULL); "
                <> body
                <> " CREATE TEMP TABLE mcp_commit_guard(n INTEGER); CREATE TEMP TRIGGER mcp_refusal BEFORE INSERT ON mcp_commit_guard WHEN (SELECT code FROM mcp_result)<>'OK' BEGIN SELECT RAISE(ROLLBACK,'MCP_WRITE_REFUSED'); END; SELECT json_object('code',code,'value',value) FROM mcp_result; INSERT INTO mcp_commit_guard VALUES(1); COMMIT;"
              case query(root, db, bin, False, sql) {
                Error(reason) ->
                  case
                    list.any(
                      [
                        "timeout",
                        "output_limit",
                        "backend_output_or_process_failure",
                        "invalid_busy_timeout_receipt",
                      ],
                      fn(marker) { string.contains(reason, marker) },
                    )
                  {
                    True -> Error(uncertain_write())
                    False ->
                      // SQLite versions differ in which final rollback error
                      // they print. A typed refusal emitted by this script is
                      // authoritative; an OK line on nonzero exit never is.
                      case
                        list.find_map(string.split(reason, "\n"), fn(line) {
                          decode_write_result(string.trim(line))
                        })
                      {
                        Ok(#(code, _)) if code != "OK" -> Error(error(code))
                        Ok(_) -> Error(uncertain_write())
                        Error(_) -> Error(store_error(reason))
                      }
                  }
                Ok(payload) ->
                  case decode_write_result(payload) {
                    Ok(#("OK", value)) -> Ok(value)
                    // A refusal must have rolled back, never committed DDL.
                    _ -> Error(uncertain_write())
                  }
              }
            }
          }
      }
  }
}

fn decode_write_result(payload: String) -> Result(#(String, String), Nil) {
  let decoder = {
    use code <- decode.field("code", decode.string)
    use value <- decode.field("value", decode.string)
    decode.success(#(code, value))
  }
  json.parse(payload, decoder) |> result.map_error(fn(_) { Nil })
}

fn uncertain_write() -> ToolError {
  ToolError(
    "SA_PLAN_WRITE_UNCERTAIN",
    "Canonical SQLite write timed out; reconcile before retry",
    types.ReconcileFirst,
  )
}

fn store_error(reason: String) -> ToolError {
  case
    list.any(["not a database", "malformed", "corrupt"], fn(marker) {
      string.contains(string.lowercase(reason), marker)
    })
  {
    True -> error("SA_PLAN_STORE_CORRUPT")
    False -> error("SA_PLAN_STORE_UNAVAILABLE")
  }
}

fn dependency_predicate(
  tables: List(String),
  columns: List(String),
  plan: String,
  task: String,
) -> Result(String, String) {
  let canonical = case list.contains(tables, "sa_plan_dependency") {
    True -> dependency_unmet("sa_plan_dependency", "dependency_id", plan, task)
    False -> "0"
  }
  case list.contains(tables, "sa_plan_task_dep") {
    False -> Ok(canonical)
    True -> {
      use column <- result.try(
        list.find(["dep_id", "depends_on"], fn(c) { list.contains(columns, c) })
        |> result.map_error(fn(_) { "invalid_dependency_schema" }),
      )
      Ok(
        "("
        <> canonical
        <> " OR "
        <> dependency_unmet("sa_plan_task_dep", column, plan, task)
        <> ")",
      )
    }
  }
}

fn dependency_unmet(
  table: String,
  column: String,
  plan: String,
  task: String,
) -> String {
  "EXISTS(SELECT 1 FROM "
  <> table
  <> " d LEFT JOIN sa_plan_task p ON p.plan_id=d.plan_id AND p.id=d."
  <> column
  <> " WHERE d.plan_id="
  <> literal(plan)
  <> " AND d.task_id="
  <> literal(task)
  <> " AND coalesce(p.state,'')<>'completed')"
}

// This is the observed canonical schema, including required names/timestamps.
// Never create competing sa_oban_job/sa_temporal_workflow authorities.
const jobs_schema = "CREATE TABLE IF NOT EXISTS sa_plan_job(id TEXT PRIMARY KEY,name TEXT NOT NULL UNIQUE,queue TEXT NOT NULL,worker TEXT NOT NULL,args TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN ('available','executing','retry','completed','discarded','cancelled')),attempt INTEGER NOT NULL DEFAULT 0,max_attempts INTEGER NOT NULL,available_at_ns INTEGER NOT NULL,lease_owner TEXT,lease_until_ns INTEGER,result TEXT,inserted_at_ns INTEGER NOT NULL); "

const workflows_schema = "CREATE TABLE IF NOT EXISTS sa_plan_workflow(id TEXT PRIMARY KEY,name TEXT NOT NULL UNIQUE,kind TEXT NOT NULL DEFAULT 'workflow',input TEXT NOT NULL DEFAULT '',state TEXT NOT NULL CHECK(state IN ('running','completed','failed')),result TEXT,created_at_ns INTEGER NOT NULL,completed_at_ns INTEGER); "

const holds_schema = "CREATE TABLE IF NOT EXISTS sa_plan_mcp_hold(plan_id TEXT NOT NULL,id TEXT NOT NULL,worker TEXT NOT NULL DEFAULT '',attempt INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(plan_id,id)); "

const bridge_schema = "CREATE TABLE IF NOT EXISTS sa_plan_mcp_bridge(bridge_key TEXT PRIMARY KEY,job_id TEXT NOT NULL UNIQUE,FOREIGN KEY(job_id) REFERENCES sa_plan_job(id)); "

const ok_guard = "(SELECT code FROM mcp_result)='OK'"

fn set_result(code: String, value: String) -> String {
  "INSERT INTO mcp_result SELECT " <> code <> "," <> value <> "; "
}

fn write_body(
  call: ValidatedCall,
  plan: String,
  task: String,
  actor: String,
  dependencies: String,
) -> Result(String, ToolError) {
  let key = "plan_id=" <> literal(plan) <> " AND id=" <> literal(task)
  let exists = "EXISTS(SELECT 1 FROM sa_plan_task WHERE " <> key <> ")"
  let now =
    "max("
    <> int.to_string(system_time_nanos())
    <> ",CAST((julianday('now')-2440587.5)*86400000000000 AS INTEGER))"
  case call.spec.name {
    "plan_add" ->
      case plan == "" || task == "" {
        True -> Error(error("MISSING_TASK_ID"))
        False ->
          Ok(
            set_result(
              "CASE WHEN "
                <> exists
                <> " THEN 'TASK_ALREADY_EXISTS' ELSE 'OK' END",
              "'available'",
            )
            <> "INSERT INTO sa_plan_plan(id,name,title,graph_fingerprint,created_at_ns) SELECT "
            <> literal(plan)
            <> ","
            <> literal(plan_name(plan))
            <> ","
            <> literal(plan)
            <> ","
            <> literal("mcp-plan-v1:" <> plan)
            <> ","
            <> now
            <> " WHERE "
            <> ok_guard
            <> " AND NOT EXISTS(SELECT 1 FROM sa_plan_plan WHERE id="
            <> literal(plan)
            <> "); "
            <> "INSERT INTO sa_plan_task(plan_id,id,name,ordinal,task_type,title,priority,state,attempt) SELECT "
            <> literal(plan)
            <> ","
            <> literal(task)
            <> ",NULL,coalesce((SELECT max(ordinal)+1 FROM sa_plan_task WHERE plan_id="
            <> literal(plan)
            <> "),0),'task',"
            <> literal(arg(call, "title"))
            <> ","
            <> int.to_string(
              int.parse(arg(call, "priority")) |> result.unwrap(0),
            )
            <> ",'available',0 WHERE "
            <> ok_guard
            <> "; ",
          )
      }
    "sa_task_claim" | "sa_task_complete" | "plan_update" ->
      task_transition(call, key, exists, actor, now, dependencies)
    "sa_job_enqueue" -> {
      let id = alias(call, "job_id", "id")
      let name = case arg(call, "name") {
        "" -> id
        v -> v
      }
      case id == "" {
        True -> Error(error("MISSING_JOB_ID"))
        False ->
          Ok(
            jobs_schema
            <> set_result(
              "CASE WHEN EXISTS(SELECT 1 FROM sa_plan_job WHERE id="
                <> literal(id)
                <> " OR name="
                <> literal(name)
                <> ") THEN 'JOB_ALREADY_EXISTS' ELSE 'OK' END",
              literal(id),
            )
            <> insert_job(call, id, name, actor, now, ok_guard),
          )
      }
    }
    "sa_workflow_start" -> {
      let id = alias(call, "workflow_id", "id")
      let name = case arg(call, "name") {
        "" -> id
        v -> v
      }
      case id == "" {
        True -> Error(error("MISSING_WORKFLOW_ID"))
        False ->
          Ok(
            workflows_schema
            <> set_result(
              "CASE WHEN EXISTS(SELECT 1 FROM sa_plan_workflow WHERE id="
                <> literal(id)
                <> " OR name="
                <> literal(name)
                <> ") THEN 'WORKFLOW_ALREADY_EXISTS' ELSE 'OK' END",
              literal(id),
            )
            <> "INSERT INTO sa_plan_workflow(id,name,kind,input,state,created_at_ns) SELECT "
            <> literal(id)
            <> ","
            <> literal(name)
            <> ","
            <> literal(case arg(call, "kind") {
              "" -> "workflow"
              v -> v
            })
            <> ","
            <> literal(arg(call, "input"))
            <> ",'running',"
            <> now
            <> " WHERE "
            <> ok_guard
            <> "; ",
          )
      }
    }
    "sa_bridge_submit" -> {
      let key = alias(call, "bridge_key", "task")
      let id = "bridge:" <> key
      let mapped =
        "EXISTS(SELECT 1 FROM sa_plan_mcp_bridge WHERE bridge_key="
        <> literal(key)
        <> ")"
      case key == "" {
        True -> Error(error("MISSING_BRIDGE_KEY"))
        False ->
          Ok(
            jobs_schema
            <> bridge_schema
            <> set_result(
              "CASE WHEN "
                <> mapped
                <> " THEN 'OK' WHEN EXISTS(SELECT 1 FROM sa_plan_job WHERE id="
                <> literal(id)
                <> " OR name="
                <> literal(id)
                <> ") THEN 'JOB_ALREADY_EXISTS' ELSE 'OK' END",
              "coalesce((SELECT job_id FROM sa_plan_mcp_bridge WHERE bridge_key="
                <> literal(key)
                <> "),"
                <> literal(id)
                <> ")",
            )
            <> insert_job(
              call,
              id,
              id,
              actor,
              now,
              ok_guard <> " AND NOT " <> mapped,
            )
            <> "INSERT INTO sa_plan_mcp_bridge(bridge_key,job_id) SELECT "
            <> literal(key)
            <> ","
            <> literal(id)
            <> " WHERE "
            <> ok_guard
            <> " AND NOT "
            <> mapped
            <> "; ",
          )
      }
    }
    _ -> Error(error("UNSUPPORTED_PLANNING_WRITE_TOOL"))
  }
}

fn insert_job(
  call: ValidatedCall,
  id: String,
  name: String,
  actor: String,
  now: String,
  condition: String,
) -> String {
  let queue = case arg(call, "queue") {
    "" -> "default"
    v -> v
  }
  let max_attempts =
    int.parse(arg(call, "max_attempts")) |> result.unwrap(3) |> int.max(1)
  let scheduled =
    int.parse(alias(call, "scheduled_at_ns", "available_at_ns"))
    |> result.map(int.to_string)
    |> result.unwrap(now)
  "INSERT INTO sa_plan_job(id,name,queue,worker,args,state,attempt,max_attempts,available_at_ns,inserted_at_ns) SELECT "
  <> literal(id)
  <> ","
  <> literal(name)
  <> ","
  <> literal(queue)
  <> ","
  <> literal(case arg(call, "worker") {
    "" -> actor
    v -> v
  })
  <> ","
  <> literal(arg(call, "args"))
  <> ",'available',0,"
  <> int.to_string(max_attempts)
  <> ","
  <> scheduled
  <> ","
  <> now
  <> " WHERE "
  <> condition
  <> "; "
}

fn task_transition(
  call: ValidatedCall,
  key: String,
  exists: String,
  actor: String,
  now: String,
  dependencies: String,
) -> Result(String, ToolError) {
  let target = case call.spec.name {
    "sa_task_claim" -> "executing"
    "sa_task_complete" -> "completed"
    _ ->
      case alias(call, "state", "status") {
        "in_progress" -> "executing"
        "pending" -> "available"
        s -> s
      }
  }
  let row = " FROM sa_plan_task WHERE " <> key
  let worker = "coalesce((SELECT worker" <> row <> "),'')"
  let state = "coalesce((SELECT state" <> row <> "),'')"
  let lease = "coalesce((SELECT lease_until_ns" <> row <> "),0)"
  let held =
    "EXISTS(SELECT 1 FROM sa_plan_mcp_hold h WHERE "
    <> key
    <> " AND h.worker="
    <> worker
    <> " AND h.attempt=coalesce((SELECT attempt"
    <> row
    <> "),0) AND "
    <> lease
    <> ">"
    <> now
    <> ")"
  let requested_attempt = int.parse(arg(call, "attempt")) |> result.unwrap(-1)
  let fence_bad = case call.attempt {
    Some(fence) -> fence != requested_attempt
    None -> False
  }
  let stale = case fence_bad || requested_attempt < 0 {
    True -> "1"
    False ->
      "coalesce((SELECT attempt"
      <> row
      <> "),-1)<>"
      <> int.to_string(requested_attempt)
  }
  let owned =
    " WHEN "
    <> state
    <> "<>'executing' THEN 'TASK_NOT_EXECUTING' WHEN "
    <> worker
    <> "<>"
    <> literal(actor)
    <> " THEN 'PRINCIPAL_WORKER_MISMATCH' WHEN "
    <> stale
    <> " THEN 'STALE_ATTEMPT_FENCE' WHEN "
    <> lease
    <> "<="
    <> now
    <> " THEN 'TASK_LEASE_EXPIRED'"
  let claimable =
    "("
    <> state
    <> "='available' OR ("
    <> state
    <> "='executing' AND "
    <> lease
    <> ">0 AND "
    <> lease
    <> "<="
    <> now
    <> "))"
  let decision =
    "CASE WHEN NOT "
    <> exists
    <> " THEN 'UNKNOWN_TASK_ID'"
    <> " WHEN "
    <> state
    <> "='completed' THEN 'COMPLETED_TASK_IMMUTABLE'"
    <> case target {
      "executing" ->
        case call.spec.name == "plan_update" {
          True ->
            " WHEN "
            <> held
            <> " THEN CASE"
            <> owned
            <> " ELSE 'OK' END"
            <> " WHEN NOT "
            <> claimable
            <> " THEN 'TASK_ALREADY_CLAIMED' WHEN "
            <> dependencies
            <> " THEN 'TASK_DEPENDENCIES_UNMET'"
          False ->
            " WHEN "
            <> held
            <> " THEN 'TASK_BLOCKED' WHEN NOT "
            <> claimable
            <> " THEN 'TASK_ALREADY_CLAIMED' WHEN "
            <> dependencies
            <> " THEN 'TASK_DEPENDENCIES_UNMET'"
        }
      "completed" ->
        " WHEN "
        <> held
        <> " THEN 'TASK_BLOCKED' WHEN "
        <> state
        <> "<>'executing' THEN 'INVALID_STATE_TRANSITION'"
        <> owned
      "blocked" -> owned
      "available" ->
        " WHEN NOT " <> held <> " THEN 'TASK_NOT_EXECUTING'" <> owned
      _ -> " WHEN 1 THEN 'INVALID_STATE_TRANSITION'"
    }
    <> " ELSE 'OK' END"
  let update = case target {
    "executing" ->
      "UPDATE sa_plan_task SET state='executing',worker="
      <> literal(actor)
      <> ",attempt=coalesce(attempt,0)+1,lease_until_ns="
      <> now
      <> "+3600000000000 WHERE "
      <> key
      <> " AND "
      <> ok_guard
      <> " AND NOT "
      <> held
      <> "; DELETE FROM sa_plan_mcp_hold WHERE "
      <> key
      <> " AND "
      <> ok_guard
      <> "; "
    "completed" ->
      "UPDATE sa_plan_task SET state='completed',completed_at_ns="
      <> now
      <> ",result="
      <> literal(arg(call, "result"))
      <> ",lease_until_ns=NULL WHERE "
      <> key
      <> " AND "
      <> ok_guard
      <> "; "
    "blocked" ->
      "INSERT OR REPLACE INTO sa_plan_mcp_hold(plan_id,id,worker,attempt) SELECT plan_id,id,coalesce(worker,''),coalesce(attempt,0) FROM sa_plan_task WHERE "
      <> key
      <> " AND "
      <> ok_guard
      <> "; "
    "available" ->
      "UPDATE sa_plan_task SET state='available',worker=NULL,lease_until_ns=NULL WHERE "
      <> key
      <> " AND "
      <> ok_guard
      <> "; DELETE FROM sa_plan_mcp_hold WHERE "
      <> key
      <> " AND "
      <> ok_guard
      <> "; "
    _ -> ""
  }
  Ok(holds_schema <> set_result(decision, literal(target)) <> update)
}
