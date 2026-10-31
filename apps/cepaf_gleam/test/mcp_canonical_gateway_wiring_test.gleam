//// C02: gateway wiring with unique real SQLite and metadata fixtures.
//// Canonical Sa-plan is opened read-only only to clone its schema. No live
//// authority, runtime state, protected sources, or secret values are changed.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/adapters/features
import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/server as server_backends
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/wire
import gleam/dict
import gleam/dynamic as gleam_dynamic
import gleam/dynamic/decode
import gleam/erlang/atom as gleam_erlang_atom
import gleam/erlang/charlist
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import mcp_resilience_bdd_test as fixtures
import simplifile

const canonical_root = "/home/an/NAS-setup/uos"

const write_tools = [
  "plan_add", "sa_task_claim", "sa_task_complete", "sa_job_enqueue",
  "sa_workflow_start",
]

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn now_ns() -> Int

@external(erlang, "mcp_stdio_ffi", "run_workspace_bounded_cd")
fn run(
  path: String,
  args: List(String),
  cwd: String,
  timeout: Int,
) -> Result(#(Int, String), String)

fn write(root: String, relative: String, raw: String) -> String {
  let path = root <> "/" <> relative
  let parts =
    string.split(path, "/") |> list.reverse |> list.drop(1) |> list.reverse
  let assert Ok(_) = simplifile.create_directory_all(string.join(parts, "/"))
  let assert Ok(_) = simplifile.write(path, raw)
  // Every ordinary grant fixture explicitly pins the exact file bytes.
  case string.ends_with(relative, "grant.json") {
    True -> {
      let _ = put_env("UOS_MCP_PUBLIC_GRANT_SHA256", files.digest(raw))
      Nil
    }
    False -> Nil
  }
  path
}

fn fixture_root() -> String {
  let root = "/tmp/uos-c02-" <> int.to_string(now_ns())
  let assert Ok(_) = simplifile.create_directory_all(root)
  // Six exact source files let the fixture use the real candidate calculation.
  list.each(
    [
      "registry",
      "admission",
      "receipts",
      "dispatch",
      "route_convergence",
      "server",
    ],
    fn(name) {
      let relative = "src/cepaf_gleam/mcp/" <> name <> ".gleam"
      let assert Ok(raw) = simplifile.read(relative)
      let _ = write(root, relative, raw)
      Nil
    },
  )
  root
}

fn cleanup(root: String) {
  let _ = simplifile.delete_all([root])
  Nil
}

fn sql(root: String, query: String) -> String {
  let bin = fixtures.fixture_sqlite_binary()
  let assert Ok(#(0, out)) =
    run(
      bin,
      [
        "-init",
        "/dev/null",
        "-batch",
        "-bail",
        root <> "/var/sa-plan/uos.sqlite3",
        query,
      ],
      root,
      3000,
    )
  string.trim(out)
}

fn database(root: String) {
  let assert Ok(_) = simplifile.create_directory_all(root <> "/var/sa-plan")
  let _ = fixtures.install_sqlite_fixture_toolchain(root)
  let clone = root <> "/var/sa-plan/uos.sqlite3"
  let assert Ok(_) =
    simplifile.copy_file(canonical_root <> "/var/sa-plan/uos.sqlite3", clone)
  let schema =
    sql(
      root,
      "SELECT group_concat(sql,';') FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%';",
    )
  let assert Ok(_) = simplifile.delete_file(clone)
  let _ = sql(root, schema <> ";")
  let _ =
    sql(
      root,
      "INSERT INTO sa_plan_plan(id,title,graph_fingerprint) VALUES('p','primary',''),('q','secondary',''); INSERT INTO sa_plan_task(plan_id,id,name,ordinal,task_type,title,state,worker,attempt,lease_until_ns) VALUES('p','authority','authority',0,'task','fence','executing','owner',1,"
        <> int.to_string(now_ns() + 3_600_000_000_000)
        <> "),('p','done','done',1,'task','completed task','completed','owner',1,NULL),('q','pending','pending',0,'task','other plan task','available',NULL,0,NULL);",
    )
  Nil
}

fn state(root: String) -> gateway.GatewayState {
  let cand = candidate_id.from_root(root)
  let assert Ok(pool) = supervisor.start_worker_pool_for_candidate(1, cand)
  let assert Ok(supervised) = supervisor.start_supervised_gateway()
  gateway.new_state(root, cand, pool, supervised)
}

fn actor(root: String) -> process.Subject(gateway.Message) {
  let assert Ok(started) = gateway.start_state_owner(state(root))
  started.data
}

fn identity(root: String, worker: String) -> principal.Principal {
  principal.from_launcher_env(
    worker,
    types.ClientProfile("c02"),
    root,
    "c02-session",
  )
}

fn request(
  method: String,
  params: json.Json,
) -> #(String, wire.NormalizedMessage) {
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(1)),
      #("method", json.string(method)),
      #("params", params),
    ])
    |> json.to_string
  let assert Ok(msg) = wire.decode_request(types.Modern20260728, raw)
  #(raw, msg)
}

fn params(tool: String, args: List(#(String, String))) -> json.Json {
  json.object([
    #("name", json.string(tool)),
    #(
      "arguments",
      json.object(list.map(args, fn(pair) { #(pair.0, json.string(pair.1)) })),
    ),
  ])
}

fn invoke(
  subject: process.Subject(gateway.Message),
  root: String,
  tool: String,
  args: List(#(String, String)),
) -> types.Outcome {
  let #(raw, msg) = request("tools/call", params(tool, args))
  gateway.dispatch_public_actor(
    subject,
    identity(root, "owner"),
    types.Modern20260728,
    "public",
    raw,
    msg,
    now_ns() / 1_000_000,
  )
}

fn direct(
  root: String,
  tool: String,
  args: List(#(String, String)),
) -> types.Outcome {
  let #(raw, msg) = request("tools/call", params(tool, args))
  let #(out, _) =
    gateway.dispatch_normalized(
      state(root),
      identity(root, "owner"),
      types.Modern20260728,
      "public",
      raw,
      msg,
      now_ns() / 1_000_000,
    )
  out
}

fn success(out: types.Outcome) -> String {
  let assert types.Complete(raw, _) = out
  raw
}

fn refusal(out: types.Outcome, code: String) {
  let assert types.Refused(error) = out
  error.code |> should.equal(code)
}

fn count(raw: String, key: String, expected: Int) {
  json.parse(raw, decode.field(key, decode.int, decode.success))
  |> should.equal(Ok(expected))
}

fn grant_json(root: String, worker: String, scope: String) -> String {
  json.object([
    #("grant_id", json.string("c02-host-grant")),
    #("worker_id", json.string(worker)),
    #("workspace_root", json.string(root)),
    #("allowed_route", json.string("public")),
    #("allowed_tools", json.array(write_tools, json.string)),
    #("scope", json.string(scope)),
    #("revoked", json.bool(False)),
    #("expires_at_ms", json.int(now_ns() / 1_000_000 + 3_600_000)),
    #("plan_id", json.string("p")),
    #("task_id", json.string("authority")),
  ])
  |> json.to_string
}

fn grant(root: String) -> String {
  write(
    root,
    "var/harness/mcp_public_mutation_grant.json",
    grant_json(root, "owner", "task_scoped_mutation"),
  )
}

pub fn absent_receipt_ledger_never_fabricates_completed_tasks_test() {
  let root = fixture_root()
  let before = state(root)
  before.backends.features.completed_task_ids |> should.equal([])
  features.compute_progress(before.backends.features).completed_total
  |> should.equal(0)
  cleanup(root)
}

pub fn cold_metadata_requests_succeed_without_boot_database_test() {
  let root = fixture_root()
  let subject = actor(root)
  list.each(
    [
      #(
        "initialize",
        json.object([#("protocolVersion", json.string("2026-07-28"))]),
      ),
      #("ping", json.object([])),
      #("tools/list", json.object([])),
    ],
    fn(pair) {
      let #(raw, msg) = request(pair.0, pair.1)
      gateway.dispatch_public_actor(
        subject,
        identity(root, "owner"),
        types.Modern20260728,
        "public",
        raw,
        msg,
        now_ns() / 1_000_000,
      )
      |> success
      |> string.is_empty
      |> should.be_false
    },
  )
  invoke(subject, root, "plan_status", [])
  |> refusal("SA_PLAN_STORE_UNAVAILABLE")
  simplifile.is_file(root <> "/var/sa-plan/uos.sqlite3")
  |> should.equal(Ok(False))
  cleanup(root)
}

pub fn canonical_multiplan_reads_preserve_all_rows_and_per_plan_totals_test() {
  let root = fixture_root()
  database(root)
  let before = state(root)
  let assert planning_read.MultiPlanStore(_, plans, rows, _, _, _, _) =
    before.backends.planning_read
  list.length(plans) |> should.equal(2)
  list.length(rows) |> should.equal(3)
  let subject = actor(root)
  list.each(["plan_status", "sa_plan_status"], fn(tool) {
    let raw = invoke(subject, root, tool, []) |> success
    count(raw, "total_plans", 2)
    count(raw, "total_tasks", 3)
    count(raw, "completed_tasks", 1)
  })
  let raw = invoke(subject, root, "sa_plan_list", []) |> success
  raw |> string.contains("authority") |> should.be_true
  raw |> string.contains("pending") |> should.be_true
  let raw = invoke(subject, root, "plan_list", []) |> success
  raw |> string.contains("authority") |> should.be_true
  raw |> string.contains("pending") |> should.be_true
  let raw = invoke(subject, root, "feature_tracker_status", []) |> success
  count(raw, "declared_total", 3)
  raw |> string.contains("\"completed_is_not_observed\":true") |> should.be_true
  count(raw, "observed_executed_total", 0)
  let raw = invoke(subject, root, "plan_status", [#("plan_id", "q")]) |> success
  count(raw, "total_tasks", 1)
  let raw = invoke(subject, root, "plan_list", [#("plan", "q")]) |> success
  raw |> string.contains("pending") |> should.be_true
  raw |> string.contains("authority") |> should.be_false
  cleanup(root)
}

pub fn gateway_missing_symlinked_and_corrupt_databases_fail_closed_test() {
  let root = fixture_root()
  let assert planning_read.UnavailableStore(_) =
    state(root).backends.planning_read
  let path = write(root, "var/sa-plan/real.sqlite3", "corrupt")
  let db = root <> "/var/sa-plan/uos.sqlite3"
  let assert Ok(_) = simplifile.create_symlink(to: path, from: db)
  let assert planning_read.UnavailableStore(_) =
    state(root).backends.planning_read
  let assert Ok(_) = simplifile.delete_file(db)
  let _ = write(root, "var/sa-plan/uos.sqlite3", "corrupt")
  let assert planning_read.UnavailableStore(_) =
    state(root).backends.planning_read
  cleanup(root)
}

pub fn no_host_grant_and_forged_argument_grants_never_mutate_sqlite_test() {
  let root = fixture_root()
  database(root)
  list.each([[], [#("grant_id", "forged"), #("worker", "owner")]], fn(extra) {
    direct(
      root,
      "plan_add",
      list.append(
        [#("plan_id", "p"), #("task_id", "new"), #("title", "new task")],
        extra,
      ),
    )
    |> refusal("ROUTE_GRANT_REQUIRED")
    sql(root, "SELECT count(*) FROM sa_plan_task;") |> should.equal("3")
  })
  cleanup(root)
}

pub fn duplicate_key_grant_is_refused_before_execution_test() {
  let root = fixture_root()
  database(root)
  let raw =
    grant_json(root, "owner", "task_scoped_mutation")
    |> string.replace(
      "\"grant_id\":",
      "\"grant_id\":\"duplicate\",\"grant_id\":",
    )
  let _ = write(root, "var/harness/mcp_public_mutation_grant.json", raw)
  direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "new")])
  |> refusal("PUBLIC_GRANT_INVALID")
  sql(root, "SELECT count(*) FROM sa_plan_task;") |> should.equal("3")
  cleanup(root)
}

pub fn symlink_grant_is_refused_before_execution_test() {
  let root = fixture_root()
  database(root)
  let path =
    write(
      root,
      "real-grant.json",
      grant_json(root, "owner", "task_scoped_mutation"),
    )
  let assert Ok(_) = simplifile.create_directory_all(root <> "/var/harness")
  let assert Ok(_) =
    simplifile.create_symlink(
      to: path,
      from: root <> "/var/harness/mcp_public_mutation_grant.json",
    )
  direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "new")])
  |> refusal("PUBLIC_GRANT_INVALID")
  sql(root, "SELECT count(*) FROM sa_plan_task;") |> should.equal("3")
  cleanup(root)
}

pub fn release_authority_and_unknown_or_missing_grant_fields_are_refused_test() {
  let root = fixture_root()
  database(root)
  list.each(
    [
      grant_json(root, "owner", "release_authority"),
      grant_json(root, "owner", "task_scoped_mutation")
        |> string.replace("\"grant_id\":", "\"unknown\":true,\"grant_id\":"),
      "{}",
      "",
      string.repeat("x", 65_537),
    ],
    fn(raw) {
      let _ = write(root, "var/harness/mcp_public_mutation_grant.json", raw)
      direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "new")])
      |> refusal("PUBLIC_GRANT_INVALID")
    },
  )
  sql(root, "SELECT count(*) FROM sa_plan_task;") |> should.equal("3")
  cleanup(root)
}

pub fn expired_live_fence_refuses_even_with_valid_host_grant_test() {
  let root = fixture_root()
  database(root)
  let _ = grant(root)
  let _ =
    sql(root, "UPDATE sa_plan_task SET lease_until_ns=1 WHERE id='authority';")
  direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "new")])
  |> refusal("TASK_LEASE_EXPIRED")
  cleanup(root)
}

pub fn completed_live_fence_refuses_reuse_test() {
  let root = fixture_root()
  database(root)
  let _ = grant(root)
  let _ =
    sql(root, "UPDATE sa_plan_task SET state='completed' WHERE id='authority';")
  direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "new")])
  |> refusal("COMPLETED_TASK_NOT_REUSABLE")
  cleanup(root)
}

pub fn live_fence_worker_and_grant_worker_must_match_principal_test() {
  let root = fixture_root()
  database(root)
  let _ =
    write(
      root,
      "var/harness/mcp_public_mutation_grant.json",
      grant_json(root, "other", "task_scoped_mutation"),
    )
  direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "new")])
  |> refusal("PRINCIPAL_WORKER_MISMATCH")
  let _ = grant(root)
  let _ =
    sql(root, "UPDATE sa_plan_task SET worker='other' WHERE id='authority';")
  direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "new")])
  |> refusal("PRINCIPAL_WORKER_MISMATCH")
  cleanup(root)
}

pub fn grant_without_live_database_or_fence_row_is_unavailable_test() {
  let root = fixture_root()
  let _ = grant(root)
  direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "new")])
  |> refusal("SA_PLAN_FENCE_UNAVAILABLE")
  database(root)
  let _ =
    sql(root, "UPDATE sa_plan_task SET id='different' WHERE id='authority';")
  direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "new")])
  |> refusal("SA_PLAN_FENCE_UNAVAILABLE")
  cleanup(root)
}

pub fn valid_host_grant_mutates_real_sqlite_and_reads_refresh_immediately_test() {
  let root = fixture_root()
  database(root)
  let _ = grant(root)
  let subject = actor(root)
  invoke(subject, root, "plan_add", [
    #("plan_id", "p"),
    #("task_id", "new"),
    #("title", "new durable task"),
  ])
  |> success
  |> string.contains("available")
  |> should.be_true
  invoke(subject, root, "sa_task_claim", [
    #("plan_id", "p"),
    #("task_id", "new"),
  ])
  |> success
  |> string.contains("executing")
  |> should.be_true
  invoke(subject, root, "sa_task_complete", [
    #("plan_id", "p"),
    #("task_id", "new"),
    #("attempt", "1"),
    #("result", "durable receipt"),
  ])
  |> success
  |> string.contains("completed")
  |> should.be_true
  invoke(subject, root, "sa_job_enqueue", [
    #("job_id", "job-c02"),
    #("name", "test"),
    #("args", "{}"),
  ])
  |> success
  |> string.contains("job-c02")
  |> should.be_true
  invoke(subject, root, "sa_workflow_start", [
    #("workflow_id", "workflow-c02"),
    #("name", "test"),
    #("input", "{}"),
  ])
  |> success
  |> string.contains("workflow-c02")
  |> should.be_true
  sql(
    root,
    "SELECT state || ':' || worker || ':' || result FROM sa_plan_task WHERE id='new';",
  )
  |> should.equal("completed:owner:durable receipt")
  let raw = invoke(subject, root, "sa_plan_status", []) |> success
  count(raw, "total_tasks", 4)
  count(raw, "completed_tasks", 2)
  count(raw, "oban_jobs", 1)
  count(raw, "temporal_workflows", 1)
  cleanup(root)
}

fn vault_json(root: String, observed_ms: Int) -> String {
  json.object([
    #("tenant_id", json.string(root)),
    #("sealed", json.bool(False)),
    #("healthy", json.bool(True)),
    #("observed_at_ms", json.int(observed_ms)),
    #(
      "secret_names",
      json.array(["hvs.canary-value", "safe-name"], json.string),
    ),
    #("policies", json.object([#("default", json.string("safe-policy"))])),
    #(
      "audit_lines",
      json.array(["ghp_secret-canary", "safe audit"], json.string),
    ),
  ])
  |> json.to_string
}

pub fn live_vault_refresh_observes_valid_then_stale_corrupt_and_symlink_test() {
  let root = fixture_root()
  let subject = actor(root)
  invoke(subject, root, "vault_status", []) |> refusal("VAULT_BACKEND_UNWIRED")
  let path =
    write(
      root,
      "var/vault/metadata.json",
      vault_json(root, now_ns() / 1_000_000),
    )
  list.each(
    [
      "vault_status",
      "vault_health",
      "vault_list_secrets",
      "vault_audit_tail",
      "vault_policy_get",
    ],
    fn(tool) {
      let raw = invoke(subject, root, tool, []) |> success
      raw |> string.contains("hvs.canary-value") |> should.be_false
      raw |> string.contains("ghp_secret-canary") |> should.be_false
    },
  )
  let _ = write(root, "var/vault/metadata.json", vault_json(root, 1))
  invoke(subject, root, "vault_status", []) |> refusal("VAULT_BACKEND_UNWIRED")
  let _ = write(root, "var/vault/metadata.json", "corrupt")
  invoke(subject, root, "vault_status", []) |> refusal("VAULT_BACKEND_UNWIRED")
  let assert Ok(_) = simplifile.delete_file(path)
  let real =
    write(root, "vault-real.json", vault_json(root, now_ns() / 1_000_000))
  let assert Ok(_) = simplifile.create_symlink(to: real, from: path)
  invoke(subject, root, "vault_status", []) |> refusal("VAULT_BACKEND_UNWIRED")
  cleanup(root)
}

fn ledger_json(root: String) -> String {
  json.object([
    #("admitted_ev_ceiling", json.int(93)),
    #("completed_task_ids", json.array(["T01"], json.string)),
    #(
      "receipts",
      json.array(
        [
          json.object([
            #("task_id", json.string("T01")),
            #("candidate_commit", json.string(candidate_id.from_root(root))),
            #("exit_code", json.int(0)),
            #("raw_review_verdict", json.string("APPROVED")),
            #("wrapper_verdict", json.string("NONE")),
            #("output_sha256", json.string("c02-observed-test-output")),
            #(
              "observed_tools",
              json.array(["harness_execution_progress"], json.string),
            ),
          ]),
        ],
        fn(x) { x },
      ),
    ),
    #("intents", json.object([#("disk-intent", json.string("disk intent"))])),
  ])
  |> json.to_string
}

pub fn live_feature_refresh_has_no_fake_tasks_and_loads_verified_receipt_test() {
  let root = fixture_root()
  let subject = actor(root)
  let raw = invoke(subject, root, "harness_execution_progress", []) |> success
  count(raw, "completed_total", 0)
  count(raw, "verified_complete_count", 0)
  let _ =
    write(
      root,
      "var/harness/mcp_feature_receipt_ledger.json",
      ledger_json(root),
    )
  let raw = invoke(subject, root, "harness_execution_progress", []) |> success
  count(raw, "completed_total", 1)
  count(raw, "verified_complete_count", 1)
  let raw =
    invoke(subject, root, "harness_system_feature_observations", [
      #("task_id", "T01"),
    ])
    |> success
  raw
  |> string.contains("\"verified_for_active_candidate\":true")
  |> should.be_true
  cleanup(root)
}

pub fn live_feature_quarantine_wins_after_previously_verified_receipt_test() {
  let root = fixture_root()
  let subject = actor(root)
  let valid = ledger_json(root)
  let _ = write(root, "var/harness/mcp_feature_receipt_ledger.json", valid)
  invoke(subject, root, "harness_system_feature_observations", [
    #("task_id", "T01"),
  ])
  |> success
  |> string.contains("observed")
  |> should.be_true
  list.each(
    [
      valid
        |> string.replace(
          "\"admitted_ev_ceiling\":93",
          "\"admitted_ev_ceiling\":93,\"admitted_ev_ceiling\":93",
        ),
      valid
        |> string.replace("harness_execution_progress", "unknown_observed_tool"),
    ],
    fn(raw) {
      let _ = write(root, "var/harness/mcp_feature_receipt_ledger.json", raw)
      list.each(
        [
          "mcp_capability_inventory",
          "harness_system_feature_catalog",
          "harness_system_feature_observations",
          "harness_system_feature_intent",
          "harness_execution_progress",
        ],
        fn(tool) {
          invoke(subject, root, tool, []) |> refusal("FEATURE_LEDGER_CORRUPT")
        },
      )
    },
  )
  let path = root <> "/var/harness/mcp_feature_receipt_ledger.json"
  let assert Ok(_) = simplifile.delete_file(path)
  let real = write(root, "real-ledger.json", valid)
  let assert Ok(_) = simplifile.create_symlink(to: real, from: path)
  invoke(subject, root, "harness_execution_progress", [])
  |> refusal("FEATURE_LEDGER_SYMLINK_FORBIDDEN")
  cleanup(root)
}

// A dedicated OTP29 trace session counts bounded subprocess invocations in
// just this fixture worker and its descendants, without touching other traces.
@external(erlang, "trace", "session_create")
fn trace_session(
  name: gleam_erlang_atom.Atom,
  tracer: process.Pid,
  options: List(Nil),
) -> gleam_dynamic.Dynamic

@external(erlang, "trace", "function")
fn trace_function(
  session: gleam_dynamic.Dynamic,
  mfa: #(gleam_erlang_atom.Atom, gleam_erlang_atom.Atom, Int),
  enabled: Bool,
  options: List(Nil),
) -> Int

@external(erlang, "trace", "process")
fn trace_process(
  session: gleam_dynamic.Dynamic,
  pid: process.Pid,
  enabled: Bool,
  flags: List(gleam_erlang_atom.Atom),
) -> Int

@external(erlang, "trace", "delivered")
fn trace_delivered(
  session: gleam_dynamic.Dynamic,
  target: gleam_erlang_atom.Atom,
) -> gleam_dynamic.Dynamic

@external(erlang, "trace", "session_destroy")
fn trace_destroy(session: gleam_dynamic.Dynamic) -> gleam_dynamic.Dynamic

type TraceEvent {
  Subprocess
  TraceBarrier
}

fn trace_count(total: Int) -> Int {
  let selector =
    process.new_selector()
    |> process.select_record(gleam_erlang_atom.create("trace"), 3, fn(_) {
      Subprocess
    })
    |> process.select_record(
      gleam_erlang_atom.create("trace_delivered"),
      2,
      fn(_) { TraceBarrier },
    )
  let assert Ok(event) = process.selector_receive(selector, 1000)
  case event {
    Subprocess -> trace_count(total + 1)
    TraceBarrier -> total
  }
}

pub fn count_subprocesses(work: fn() -> Nil) -> Int {
  let ready = process.new_subject()
  let done = process.new_subject()
  let pid =
    process.spawn(fn() {
      let start = process.new_subject()
      process.send(ready, start)
      let assert Ok(Nil) = process.receive(start, 1000)
      work()
      process.send(done, Nil)
    })
  let assert Ok(start) = process.receive(ready, 1000)
  let session =
    trace_session(
      gleam_erlang_atom.create("c02_bounded_calls"),
      process.self(),
      [],
    )
  let _ =
    trace_function(
      session,
      #(
        gleam_erlang_atom.create("mcp_stdio_ffi"),
        gleam_erlang_atom.create("run_workspace_bounded_cd"),
        4,
      ),
      True,
      [],
    )
  let _ =
    trace_process(session, pid, True, [
      gleam_erlang_atom.create("call"),
      gleam_erlang_atom.create("set_on_spawn"),
    ])
  process.send(start, Nil)
  let completed = process.receive(done, 5000)
  let _ = trace_delivered(session, gleam_erlang_atom.create("all"))
  let count = trace_count(0)
  let _ = trace_destroy(session)
  completed |> should.equal(Ok(Nil))
  count
}

pub fn cold_metadata_and_readonly_authority_spawn_zero_subprocesses_test() {
  let root = fixture_root()
  let _ =
    write(
      root,
      "var/harness/mcp_public_mutation_grant.json",
      "{invalid host grant}",
    )
  let calls =
    count_subprocesses(fn() {
      let subject = actor(root)
      list.each(["initialize", "ping", "tools/list"], fn(method) {
        let #(raw, msg) = request(method, json.object([]))
        gateway.dispatch_public_actor(
          subject,
          identity(root, "owner"),
          types.Modern20260728,
          "public",
          raw,
          msg,
          now_ns() / 1_000_000,
        )
        |> success
        |> string.is_empty
        |> should.be_false
      })
      invoke(subject, root, "mcp_capability_inventory", [])
      |> success
      |> string.is_empty
      |> should.be_false
      Nil
    })
  calls |> should.equal(0)
  cleanup(root)
}

pub fn symlinked_grant_ancestor_is_rejected_even_for_absent_final_file_test() {
  let root = fixture_root()
  database(root)
  let assert Ok(_) = simplifile.create_directory_all(root <> "/grant-target")
  let assert Ok(_) =
    simplifile.create_symlink(
      to: root <> "/grant-target",
      from: root <> "/var/harness",
    )
  direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "new")])
  |> refusal("PUBLIC_GRANT_INVALID")
  cleanup(root)
}

pub fn symlinked_sqlite_sidecars_refuse_live_grant_fence_test() {
  let root = fixture_root()
  database(root)
  let _ = grant(root)
  let target = write(root, "sidecar-target", "do not follow")
  let db = root <> "/var/sa-plan/uos.sqlite3"
  list.each(["-wal", "-shm", "-journal"], fn(suffix) {
    let assert Ok(_) = simplifile.create_symlink(to: target, from: db <> suffix)
    direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "new")])
    |> refusal("SA_PLAN_FENCE_UNAVAILABLE")
    let assert Ok(_) = simplifile.delete_file(db <> suffix)
    Nil
  })
  cleanup(root)
}

pub fn live_feature_projection_preserves_memory_intents_and_receipts_test() {
  let root = fixture_root()
  let initial = state(root)
  let memory =
    features.FeatureEvidenceStore(
      ..initial.backends.features,
      intents: dict.from_list([#("memory-intent", "keep pending intent")]),
      receipts: dict.from_list([
        #(
          "memory-task",
          features.ExecutionReceipt(
            "memory-task",
            candidate_id.from_root(root),
            0,
            Some("APPROVED"),
            None,
            "memory-output",
          ),
        ),
      ]),
    )
  let seeded =
    gateway.GatewayState(
      ..initial,
      backends: server_backends.ServerBackends(
        ..initial.backends,
        features: memory,
      ),
    )
  let assert Ok(started) = gateway.start_state_owner(seeded)
  let _ =
    write(
      root,
      "var/harness/mcp_feature_receipt_ledger.json",
      ledger_json(root),
    )
  invoke(started.data, root, "harness_system_feature_intent", [
    #("intent_id", "memory-intent"),
  ])
  |> success
  |> string.contains("keep pending intent")
  |> should.be_true
  // Only actor intents survive: disk receipts are authoritative.
  invoke(started.data, root, "harness_system_feature_observations", [
    #("task_id", "memory-task"),
  ])
  |> refusal("UNKNOWN_FEATURE_OR_TASK")
  let _ =
    write(root, "var/harness/mcp_feature_receipt_ledger.json", "{corrupt}")
  invoke(started.data, root, "harness_system_feature_intent", [
    #("intent_id", "memory-intent"),
  ])
  |> refusal("FEATURE_LEDGER_CORRUPT")
  cleanup(root)
}

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)

@external(erlang, "os", "putenv")
fn put_env_native(name: charlist.Charlist, value: charlist.Charlist) -> Bool

@external(erlang, "os", "unsetenv")
fn unset_env_native(name: charlist.Charlist) -> Bool

fn put_env(name: String, value: String) -> Bool {
  put_env_native(charlist.from_string(name), charlist.from_string(value))
}

fn unset_env(name: String) -> Bool {
  unset_env_native(charlist.from_string(name))
}

fn restore_env(name: String, previous: Result(String, Nil)) {
  case previous {
    Ok(raw) -> {
      let _ = put_env(name, raw)
      Nil
    }
    Error(_) -> {
      let _ = unset_env(name)
      Nil
    }
  }
}

pub fn public_grant_digest_requires_lowercase_and_matching_bytes_test() {
  let root = fixture_root()
  database(root)
  let path = grant(root)
  let assert Ok(raw) = simplifile.read(path)
  let previous = get_env("UOS_MCP_PUBLIC_GRANT_SHA256")
  let _ =
    put_env(
      "UOS_MCP_PUBLIC_GRANT_SHA256",
      files.digest(raw) |> string.uppercase,
    )
  let uppercase =
    direct(root, "plan_add", [
      #("plan_id", "p"),
      #("task_id", "uppercase-denied"),
    ])
  let _ = put_env("UOS_MCP_PUBLIC_GRANT_SHA256", files.digest(raw))
  let accepted =
    direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "digest-ok")])
  let _ = put_env("UOS_MCP_PUBLIC_GRANT_SHA256", string.repeat("0", 64))
  let denied =
    direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "digest-denied")])
  restore_env("UOS_MCP_PUBLIC_GRANT_SHA256", previous)
  uppercase |> refusal("PUBLIC_GRANT_DIGEST_MISMATCH")
  accepted |> success |> string.contains("available") |> should.be_true
  denied |> refusal("PUBLIC_GRANT_DIGEST_MISMATCH")
  sql(root, "SELECT count(*) FROM sa_plan_task WHERE id='digest-denied';")
  |> should.equal("0")
  cleanup(root)
}

pub fn explicit_external_grant_path_checks_every_symlink_ancestor_test() {
  let root = fixture_root()
  database(root)
  let external_root = fixture_root()
  let target =
    write(
      external_root,
      "actual/grant.json",
      grant_json(root, "owner", "task_scoped_mutation"),
    )
  let assert Ok(_) =
    simplifile.create_symlink(
      to: external_root <> "/actual",
      from: external_root <> "/alias",
    )
  let previous = get_env("UOS_MCP_PUBLIC_GRANT_PATH")
  let _ = put_env("UOS_MCP_PUBLIC_GRANT_PATH", target)
  let accepted =
    direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "external-ok")])
  let _ =
    put_env("UOS_MCP_PUBLIC_GRANT_PATH", external_root <> "/alias/grant.json")
  let denied =
    direct(root, "plan_add", [
      #("plan_id", "p"),
      #("task_id", "external-denied"),
    ])
  restore_env("UOS_MCP_PUBLIC_GRANT_PATH", previous)
  accepted |> success |> string.contains("available") |> should.be_true
  denied |> refusal("PUBLIC_GRANT_INVALID")
  sql(root, "SELECT count(*) FROM sa_plan_task WHERE id='external-denied';")
  |> should.equal("0")
  cleanup(external_root)
  cleanup(root)
}

pub fn modern_task_create_finds_executing_row_in_multiplan_store_test() {
  let root = fixture_root()
  database(root)
  let p = identity(root, "owner")
  let #(raw, msg) =
    request(
      "initialize",
      json.object([
        #("protocolVersion", json.string("2026-07-28")),
        #("capabilities", json.object([#("tasks", json.object([]))])),
      ]),
    )
  let #(initialized, ready) =
    gateway.dispatch_normalized(
      state(root),
      p,
      types.Modern20260728,
      "public",
      raw,
      msg,
      now_ns() / 1_000_000,
    )
  initialized |> success |> string.is_empty |> should.be_false
  let #(raw, msg) =
    request(
      "tasks/create",
      json.object([
        #("planId", json.string("p")),
        #("taskId", json.string("authority")),
      ]),
    )
  let #(out, _) =
    gateway.dispatch_normalized(
      ready,
      p,
      types.Modern20260728,
      "public",
      raw,
      msg,
      now_ns() / 1_000_000,
    )
  out |> success |> string.contains("authority") |> should.be_true
  cleanup(root)
}

pub fn live_vault_seal_updates_override_success_with_same_intent_id_test() {
  let root = fixture_root()
  let subject = actor(root)
  let initial = vault_json(root, now_ns() / 1_000_000)
  let args = [#("intent_id", "same-vault-seal-intent")]
  let _ = write(root, "var/vault/metadata.json", initial)
  let raw = invoke(subject, root, "vault_status", args) |> success
  json.parse(raw, decode.field("sealed", decode.bool, decode.success))
  |> should.equal(Ok(False))
  let _ =
    write(
      root,
      "var/vault/metadata.json",
      string.replace(initial, "\"sealed\":false", "\"sealed\":true"),
    )
  let raw = invoke(subject, root, "vault_status", args) |> success
  json.parse(raw, decode.field("sealed", decode.bool, decode.success))
  |> should.equal(Ok(True))
  cleanup(root)
}

pub fn live_vault_unavailability_overrides_success_with_same_intent_id_test() {
  let root = fixture_root()
  let subject = actor(root)
  let args = [#("intent_id", "same-vault-unavailable-intent")]
  let _ =
    write(
      root,
      "var/vault/metadata.json",
      vault_json(root, now_ns() / 1_000_000),
    )
  invoke(subject, root, "vault_status", args)
  |> success
  |> string.contains("sealed")
  |> should.be_true
  list.each([vault_json(root, 1), "{corrupt}"], fn(raw) {
    let _ = write(root, "var/vault/metadata.json", raw)
    invoke(subject, root, "vault_status", args)
    |> refusal("VAULT_BACKEND_UNWIRED")
  })
  cleanup(root)
}

pub fn live_feature_new_receipts_override_progress_with_same_intent_id_test() {
  let root = fixture_root()
  let subject = actor(root)
  let args = [#("intent_id", "same-feature-progress-intent")]
  let first = ledger_json(root)
  let _ = write(root, "var/harness/mcp_feature_receipt_ledger.json", first)
  let raw = invoke(subject, root, "harness_execution_progress", args) |> success
  count(raw, "completed_total", 1)
  count(raw, "verified_complete_count", 1)
  let second_receipt =
    json.object([
      #("task_id", json.string("T02")),
      #("candidate_commit", json.string(candidate_id.from_root(root))),
      #("exit_code", json.int(0)),
      #("raw_review_verdict", json.string("APPROVED")),
      #("wrapper_verdict", json.string("NONE")),
      #("output_sha256", json.string("c02-second-observed-output")),
      #(
        "observed_tools",
        json.array(["harness_execution_progress"], json.string),
      ),
    ])
    |> json.to_string
  let second =
    first
    |> string.replace(
      "\"completed_task_ids\":[\"T01\"]",
      "\"completed_task_ids\":[\"T01\",\"T02\"]",
    )
    |> string.replace(
      "\"receipts\":[",
      "\"receipts\":[" <> second_receipt <> ",",
    )
  let _ = write(root, "var/harness/mcp_feature_receipt_ledger.json", second)
  let raw = invoke(subject, root, "harness_execution_progress", args) |> success
  count(raw, "completed_total", 2)
  count(raw, "verified_complete_count", 2)
  cleanup(root)
}

pub fn live_receipt_downgrade_is_immediately_authoritative_test() {
  let root = fixture_root()
  let subject = actor(root)
  let raw = ledger_json(root)
  let _ = write(root, "var/harness/mcp_feature_receipt_ledger.json", raw)
  let args = [#("task_id", "T01"), #("intent_id", "same-observation")]
  invoke(subject, root, "harness_system_feature_observations", args)
  |> success
  |> string.contains("\"exit_code\":0")
  |> should.be_true
  let _ =
    write(
      root,
      "var/harness/mcp_feature_receipt_ledger.json",
      string.replace(raw, "\"exit_code\":0", "\"exit_code\":1"),
    )
  invoke(subject, root, "harness_system_feature_observations", args)
  |> refusal("FAILED_EXECUTION_RECEIPT")
  let observed =
    invoke(subject, root, "harness_system_feature_observations", [
      #("offset", "0"),
    ])
    |> success
  observed |> string.contains("\"exit_code\":1") |> should.be_true
  observed
  |> string.contains("\"verified_for_active_candidate\":false")
  |> should.be_true
  let inventory =
    invoke(subject, root, "mcp_capability_inventory", []) |> success
  count(inventory, "observed_count", 0)
  cleanup(root)
}

pub fn live_receipt_and_ledger_deletion_drop_stale_observations_test() {
  let root = fixture_root()
  let subject = actor(root)
  let relative = "var/harness/mcp_feature_receipt_ledger.json"
  list.each([False, True], fn(delete_file) {
    let path = write(root, relative, ledger_json(root))
    let args = [#("offset", "0"), #("intent_id", "same-page")]
    let before =
      invoke(subject, root, "harness_system_feature_observations", args)
      |> success
    count(before, "total_observations", 1)
    case delete_file {
      True -> {
        let assert Ok(_) = simplifile.delete_file(path)
        Nil
      }
      False -> {
        let _ =
          write(root, relative, "{\"admitted_ev_ceiling\":93,\"receipts\":[]}")
        Nil
      }
    }
    let after =
      invoke(subject, root, "harness_system_feature_observations", args)
      |> success
    count(after, "total_observations", 0)
    let inventory =
      invoke(subject, root, "mcp_capability_inventory", []) |> success
    count(inventory, "observed_count", 0)
  })
  cleanup(root)
}

pub fn live_planning_counts_refresh_after_mutation_with_same_intent_id_test() {
  let root = fixture_root()
  database(root)
  let _ = grant(root)
  let subject = actor(root)
  let args = [#("intent_id", "same-planning-status-intent")]
  let before = invoke(subject, root, "plan_status", args) |> success
  count(before, "total_tasks", 3)
  invoke(subject, root, "plan_add", [
    #("plan_id", "p"),
    #("task_id", "immediate-visibility"),
    #("title", "read after committed write"),
  ])
  |> success
  |> string.contains("available")
  |> should.be_true
  sql(root, "SELECT count(*) FROM sa_plan_task;") |> should.equal("4")
  let after = invoke(subject, root, "plan_status", args) |> success
  count(after, "total_tasks", 4)
  cleanup(root)
}

pub fn unpinned_public_grant_is_refused_test() {
  let root = fixture_root()
  let _ = grant(root)
  let previous = get_env("UOS_MCP_PUBLIC_GRANT_SHA256")
  let _ = unset_env("UOS_MCP_PUBLIC_GRANT_SHA256")
  let absent =
    direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "unpin")])
  let _ = put_env("UOS_MCP_PUBLIC_GRANT_SHA256", "")
  let empty =
    direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "empty-pin")])
  restore_env("UOS_MCP_PUBLIC_GRANT_SHA256", previous)
  absent |> refusal("PUBLIC_GRANT_UNPINNED")
  empty |> refusal("PUBLIC_GRANT_UNPINNED")
  cleanup(root)
}

pub fn revoked_grant_blocks_subsequent_mutation_test() {
  let root = fixture_root()
  database(root)
  let path = grant(root)
  let subject = actor(root)
  invoke(subject, root, "plan_add", [
    #("plan_id", "p"),
    #("task_id", "before-revoke"),
  ])
  |> success
  let assert Ok(raw) = simplifile.read(path)
  // Refresh the pin too: revocation must be refused even with authentic bytes.
  let _ =
    write(
      root,
      "var/harness/mcp_public_mutation_grant.json",
      string.replace(raw, "\"revoked\":false", "\"revoked\":true"),
    )
  invoke(subject, root, "plan_add", [
    #("plan_id", "p"),
    #("task_id", "after-revoke"),
  ])
  |> refusal("ROUTE_GRANT_REVOKED")
  sql(root, "SELECT count(*) FROM sa_plan_task WHERE id='after-revoke';")
  |> should.equal("0")
  cleanup(root)
}

pub fn relative_and_unnormalized_public_grant_overrides_are_refused_test() {
  let root = fixture_root()
  let _ = grant(root)
  let previous = get_env("UOS_MCP_PUBLIC_GRANT_PATH")
  let outcomes =
    list.map(
      [
        "grant.json",
        root <> "/var/../var/harness/mcp_public_mutation_grant.json",
        root <> "/var//harness/mcp_public_mutation_grant.json",
        root <> "/./var/harness/mcp_public_mutation_grant.json",
      ],
      fn(path) {
        let _ = put_env("UOS_MCP_PUBLIC_GRANT_PATH", path)
        direct(root, "plan_add", [
          #("plan_id", "p"),
          #("task_id", "relative-denied"),
        ])
      },
    )
  restore_env("UOS_MCP_PUBLIC_GRANT_PATH", previous)
  list.each(outcomes, fn(out) { refusal(out, "PUBLIC_GRANT_INVALID") })
  cleanup(root)
}

pub fn invalid_public_grant_pin_is_refused_without_sqlite_test() {
  let root = fixture_root()
  let path = grant(root)
  let assert Ok(raw) = simplifile.read(path)
  let before = get_env("UOS_MCP_PUBLIC_GRANT_SHA256")
  let outcomes =
    list.map(
      [files.digest(raw) |> string.uppercase, "BAD", string.repeat("0", 64)],
      fn(pin) {
        let _ = put_env("UOS_MCP_PUBLIC_GRANT_SHA256", pin)
        direct(root, "plan_add", [#("plan_id", "p"), #("task_id", "pin-denied")])
      },
    )
  restore_env("UOS_MCP_PUBLIC_GRANT_SHA256", before)
  cleanup(root)
  list.each(outcomes, fn(out) { refusal(out, "PUBLIC_GRANT_DIGEST_MISMATCH") })
}
