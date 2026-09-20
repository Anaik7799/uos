import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import cepaf_gleam/planning/execution_projection as execution
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const database = "/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3"

pub const risk_path = "governance/planning/20260921-1556-risk-portfolio-refresh.json"

pub type Observation {
  Observation(
    snapshot: execution.Snapshot,
    task_sha256: String,
    risk_sha256: String,
  )
}

fn task_decoder() -> decode.Decoder(#(String, execution.Task, String)) {
  use plan <- decode.field("plan_id", decode.string)
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use state <- decode.field("state", decode.string)
  use worker <- decode.field("worker", decode.optional(decode.string))
  use attempt <- decode.field("attempt", decode.int)
  use lease <- decode.field("lease_until_ns", decode.optional(decode.int))
  use completed <- decode.field("completed_at_ns", decode.optional(decode.int))
  use present <- decode.field("result_present", decode.int)
  use dependencies <- decode.field("dependencies", decode.string)
  decode.success(#(
    plan,
    execution.Task(
      id,
      title,
      state,
      worker,
      attempt,
      lease,
      completed,
      present == 1,
      [],
    ),
    dependencies,
  ))
}

pub fn parse_tasks(raw: String) -> Result(List(execution.Task), String) {
  use _ <- result.try(case string.byte_size(raw) <= 1_048_576 {
    True -> Ok(Nil)
    False -> Error("task_response_bound")
  })
  use rows <- result.try(
    json.parse(raw, decode.list(task_decoder()))
    |> result.replace_error("invalid_task_snapshot_json"),
  )
  use _ <- result.try(case !list.is_empty(rows) && list.length(rows) <= 256 {
    True -> Ok(Nil)
    False -> Error("empty_or_overlarge_task_snapshot")
  })
  list.try_map(rows, fn(row) {
    use _ <- result.try(case row.0 == execution.plan_id {
      True -> Ok(Nil)
      False -> Error("foreign_plan_snapshot")
    })
    use dependencies <- result.try(
      json.parse(row.2, decode.list(decode.string))
      |> result.replace_error("invalid_dependency_snapshot"),
    )
    Ok(execution.Task(..row.1, dependencies: dependencies))
  })
}

fn factor_decoder() -> decode.Decoder(execution.Factor) {
  use value <- decode.field("value", decode.int)
  use low <- decode.field("low", decode.int)
  use high <- decode.field("high", decode.int)
  decode.success(execution.Factor(value, low, high))
}

fn risk_decoder() -> decode.Decoder(#(String, execution.Risk)) {
  use plan <- decode.field("plan_id", decode.string)
  use id <- decode.field("task_id", decode.string)
  use state <- decode.field("task_state", decode.string)
  use class <- decode.field("class", decode.string)
  use readiness <- decode.field("readiness", decode.string)
  use blockers <- decode.field("blockers", decode.list(decode.string))
  use dependencies <- decode.field("dependencies", decode.list(decode.string))
  use observed <- decode.field("observed_at", decode.string)
  use expires <- decode.field("valid_until", decode.string)
  use ready <- decode.field("ready_since", decode.string)
  use criticality <- decode.subfield(
    ["factors", "criticality"],
    factor_decoder(),
  )
  use stpa <- decode.subfield(["factors", "stpa"], factor_decoder())
  use fmea <- decode.subfield(["factors", "fmea"], factor_decoder())
  use dependency <- decode.subfield(["factors", "dependency"], factor_decoder())
  use impact <- decode.subfield(["factors", "impact"], factor_decoder())
  decode.success(#(
    plan,
    execution.Risk(
      id,
      state,
      class,
      readiness,
      blockers,
      dependencies,
      observed,
      expires,
      ready,
      [criticality, stpa, fmea, dependency, impact],
    ),
  ))
}

pub fn parse_risks(raw: String) -> Result(List(execution.Risk), String) {
  use _ <- result.try(case string.byte_size(raw) <= files.max_bytes {
    True -> Ok(Nil)
    False -> Error("risk_response_bound")
  })
  use rows <- result.try(
    json.parse(raw, decode.list(risk_decoder()))
    |> result.replace_error("invalid_risk_snapshot_json"),
  )
  use _ <- result.try(
    case
      list.length(rows) <= 256
      && list.all(rows, fn(row) { row.0 == execution.plan_id })
    {
      True -> Ok(Nil)
      False -> Error("foreign_or_overlarge_risk_snapshot")
    },
  )
  Ok(list.map(rows, fn(row) { row.1 }))
}

pub fn read_tasks(
  path: String,
) -> Result(#(List(execution.Task), String), String) {
  use _ <- result.try(
    case
      string.starts_with(path, "/")
      && string.byte_size(path) <= 4096
      && !string.contains(path, "\u{0}")
    {
      True -> Ok(Nil)
      False -> Error("invalid_database_path")
    },
  )
  let sql =
    "SELECT p.plan_id,p.id,p.title,p.state,p.worker,p.attempt,p.lease_until_ns,p.completed_at_ns,(length(trim(coalesce(p.result,'')))>0) AS result_present, (SELECT json_group_array(dependency_id) FROM (SELECT dependency_id FROM sa_plan_dependency WHERE plan_id=p.plan_id AND task_id=p.id ORDER BY dependency_id LIMIT 257)) AS dependencies FROM sa_plan_task p WHERE p.plan_id='"
    <> execution.plan_id
    <> "' ORDER BY p.id LIMIT 257;"
  use raw <- result.try(dev.bounded(
    "/usr/bin/sqlite3",
    ["-readonly", "-json", path, sql],
    3000,
  ))
  use tasks <- result.try(parse_tasks(raw))
  Ok(#(tasks, files.digest(raw)))
}

pub fn observe() -> Result(Observation, String) {
  use #(tasks, digest) <- result.try(read_tasks(database))
  let risk = files.read(dev.root, risk_path)
  let risks = risk |> result.try(parse_risks)
  use observed <- result.try(clock.observe())
  use snapshot <- result.try(execution.project(
    tasks,
    risks,
    observed.sample.observed.utc_us * 1000,
    clock.canonical_utc(observed),
  ))
  Ok(Observation(
    snapshot,
    digest,
    risk |> result.map(files.digest) |> result.unwrap("UNAVAILABLE"),
  ))
}

pub fn to_json(observation: Observation) -> json.Json {
  let snapshot = observation.snapshot
  json.object([
    #("page", json.string("Planning")),
    #("status", json.string("observed")),
    #(
      "authority",
      json.string("read_only_projection; Sa-plan alone owns execution"),
    ),
    #("task_snapshot_sha256", json.string(observation.task_sha256)),
    #("risk_snapshot_sha256", json.string(observation.risk_sha256)),
    #("risk_path", json.string(risk_path)),
    #("database", json.string(database)),
    #("adapter_scope", dev.adapter_scope()),
    #(
      "summary_raw",
      json.string(
        json.to_string(
          json.object([
            #("pending", json.int(list.length(snapshot.recommendations))),
            #("active", json.int(snapshot.executing)),
            #("completed", json.int(snapshot.completed)),
            #("blocked", json.int(snapshot.blocked)),
            #("unknown", json.int(snapshot.unknown)),
            #("total", json.int(snapshot.total)),
            #("authority", json.string("observation_only")),
          ]),
        ),
      ),
    ),
    #(
      "pending_raw",
      json.string(
        snapshot.rows
        |> list.filter(fn(row) { row.status == execution.ReadyForPreflight })
        |> json.array(execution.row_json)
        |> json.to_string,
      ),
    ),
    #("tasks", json.array(snapshot.rows, execution.row_json)),
    #(
      "snapshot_scope",
      json.string(
        "one SQLite SELECT; risk file is a separate advisory observation",
      ),
    ),
    #("effect_authority", json.bool(False)),
    #("system_admission", json.bool(False)),
    #("progress", execution.to_json(observation.snapshot)),
  ])
}

pub fn response(outcome: Result(Observation, String)) -> json.Json {
  case outcome {
    Ok(observation) -> to_json(observation)
    Error(reason) ->
      json.object([
        #("page", json.string("Planning")),
        #("status", json.string("unavailable")),
        #("plan_id", json.string(execution.plan_id)),
        #("error", json.string(reason)),
        #("progress", json.null()),
        #("summary_raw", json.null()),
        #("pending_raw", json.null()),
        #("effect_authority", json.bool(False)),
      ])
  }
}

pub fn main() {
  observe() |> response |> json.to_string |> io.println
}

pub fn query(
  args: value.Value,
  fence: fn() -> Result(Nil, String),
  read: fn() -> Result(Observation, String),
) -> Result(json.Json, String) {
  use _ <- result.try(case args {
    value.Object([]) -> Ok(Nil)
    _ -> Error("unexpected_progress_arguments")
  })
  use _ <- result.try(fence())
  read() |> result.map(to_json)
}
