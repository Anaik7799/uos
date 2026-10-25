//// Scoped read-only task detail through the existing pinned Sa-plan observer.
//// Caller text selects a task identifier, never a database, plan or authority.
import cepaf_gleam/harness/observer_policy as observer
import cepaf_gleam/harness/telegram_knowledge_report as knowledge
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

type TaskRow {
  TaskRow(id: String, state: String, attempt: Int, result_present: Bool, dependencies: List(String))
}

type Snapshot {
  Snapshot(source: String, authority: String, admission: String, plan: String,
    total: Int, selected: Int, digest: String, tasks: List(TaskRow))
}

pub fn parse_task_id(args: String) -> Result(String, String) {
  let allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/. \t\n"
  let task = string.trim(args)
  case string.byte_size(args) <= 2048
    && list.all(string.to_graphemes(args), fn(c) { string.contains(allowed, c) })
    && observer.valid_id(task) {
    True -> Ok(task)
    False -> Error("invalid_task_identifier")
  }
}

fn task_decoder() -> decode.Decoder(TaskRow) {
  use id <- decode.field("task_id", decode.string)
  use state <- decode.field("state", decode.string)
  use attempt <- decode.field("attempt", decode.int)
  use present <- decode.field("result_present", decode.bool)
  use dependencies <- decode.field("dependencies", decode.list(decode.string))
  decode.success(TaskRow(id, state, attempt, present, dependencies))
}

fn snapshot_decoder() -> decode.Decoder(Snapshot) {
  use source <- decode.field("observer", decode.string)
  use authority <- decode.field("authority", decode.string)
  use admission <- decode.field("runtime_admission", decode.string)
  use plan <- decode.field("plan_id", decode.string)
  use total <- decode.field("observed_tasks_total", decode.int)
  use selected <- decode.field("selected_count", decode.int)
  use digest <- decode.field("full_observation_sha256", decode.string)
  use tasks <- decode.field("tasks", decode.list(task_decoder()))
  decode.success(Snapshot(source, authority, admission, plan, total, selected, digest, tasks))
}

/// Validate identity and shape before projecting only public task metadata.
/// Recorded state is a snapshot, not proof that an executing lease is current.
pub fn project(raw: String, expected_plan: String, expected_task: String) -> Result(String, String) {
  use _ <- result.try(case string.byte_size(raw) <= 262_144
    && observer.valid_id(expected_plan) && observer.valid_id(expected_task) {
    True -> Ok(Nil)
    False -> Error("invalid_observation_bounds")
  })
  use snapshot <- result.try(json.parse(raw, snapshot_decoder())
    |> result.replace_error("invalid_task_observation"))
  use _ <- result.try(case snapshot.source == "uos.sa_plan.observer.v1"
    && snapshot.authority == "NONE" && snapshot.admission == "NOT_GRANTED"
    && snapshot.plan == expected_plan && snapshot.total >= 1 && snapshot.total <= 1000
    && snapshot.selected == list.length(snapshot.tasks)
    && snapshot.selected <= snapshot.total && observer.valid_digest(snapshot.digest) {
    True -> Ok(Nil)
    False -> Error("task_observation_identity_mismatch")
  })
  case snapshot.tasks {
    [] -> Error("task_not_found")
    [task] -> {
      use _ <- result.try(case task.id == expected_task
        && list.contains(["available", "executing", "completed", "failed", "blocked"], task.state)
        && task.attempt >= 0 && task.attempt <= 1_000_000
        && list.length(task.dependencies) <= 1000
        && list.all(task.dependencies, observer.valid_id)
        && list.length(list.unique(task.dependencies)) == list.length(task.dependencies) {
        True -> Ok(Nil)
        False -> Error("invalid_task_row")
      })
      Ok(json.object([
        #("status", json.string("observed")),
        #("source", json.string("canonical_sa_plan_snapshot")),
        #("authority", json.string("NONE")),
        #("runtime_admission", json.string("NOT_GRANTED")),
        #("plan_id", json.string(expected_plan)),
        #("task_id", json.string(task.id)),
        #("state", json.string(task.state)),
        #("state_note", json.string("Recorded task state; lease freshness is not inferred.")),
        #("attempt", json.int(task.attempt)),
        #("dependencies", json.array(task.dependencies, json.string)),
        #("result_present", json.bool(task.result_present)),
        #("full_observation_sha256", json.string(snapshot.digest)),
      ]) |> json.to_string)
    }
    _ -> Error("unexpected_task_cardinality")
  }
}

pub fn observe_task(req: observer.ObserveRequest, task_id: String) -> Result(String, String) {
  use task <- result.try(parse_task_id(task_id))
  let request = observer.ObserveRequest(..req, task_id: observer.Task(task))
  use observed <- result.try(observer.observe(request)
    |> result.replace_error("task_observer_failed"))
  use raw <- result.try(bit_array.to_string(observed.payload)
    |> result.replace_error("invalid_task_observation_encoding"))
  project(raw, req.plan_id, task)
}

fn parse_query(raw: String) -> Result(String, String) {
  knowledge.validate_query(raw)
}

fn valid_task_row(task: TaskRow) -> Bool {
  observer.valid_id(task.id)
  && list.contains(["available", "executing", "completed", "failed", "blocked"], task.state)
  && task.attempt >= 0 && task.attempt <= 1_000_000
  && list.length(task.dependencies) <= 1000
  && list.all(task.dependencies, observer.valid_id)
  && list.length(list.unique(task.dependencies)) == list.length(task.dependencies)
}


fn encode_search_task(task: TaskRow) -> json.Json {
  json.object([
    #("task_id", json.string(task.id)),
    #("state", json.string(task.state)),
    #("attempt", json.int(task.attempt)),
    #("result_present", json.bool(task.result_present)),
  ])
}

pub fn search_project(raw: String, expected_plan: String, query: String) -> Result(String, String) {
  use trimmed_query <- result.try(parse_query(query))
  use _ <- result.try(case string.byte_size(raw) <= 262_144 && observer.valid_id(expected_plan) {
    True -> Ok(Nil)
    False -> Error("invalid_observation_bounds")
  })
  use snapshot <- result.try(json.parse(raw, snapshot_decoder())
    |> result.replace_error("invalid_task_observation"))
  use _ <- result.try(case snapshot.source == "uos.sa_plan.observer.v1"
    && snapshot.authority == "NONE" && snapshot.admission == "NOT_GRANTED"
    && snapshot.plan == expected_plan && snapshot.total >= 0 && snapshot.total <= 1000
    && snapshot.selected == snapshot.total && snapshot.total == list.length(snapshot.tasks)
    && observer.valid_digest(snapshot.digest) {
    True -> Ok(Nil)
    False -> Error("task_observation_identity_mismatch")
  })
  let ids = list.map(snapshot.tasks, fn(t) { t.id })
  use _ <- result.try(case list.length(list.unique(ids)) == list.length(ids)
    && list.all(snapshot.tasks, valid_task_row) {
    True -> Ok(Nil)
    False -> Error("invalid_task_row")
  })
  let needle = string.lowercase(trimmed_query)
  let matches =
    list.filter(snapshot.tasks, fn(t) {
      string.contains(string.lowercase(t.id), needle)
      || string.contains(string.lowercase(t.state), needle)
    })
    |> list.sort(fn(a, b) { string.compare(a.id, b.id) })
  let matched_total = list.length(matches)
  let visible = list.take(matches, 20)
  let shown = list.length(visible)
  let out =
    json.object([
      #("schema", json.string("uos.telegram.task_search.v1")),
      #("status", json.string("observed")),
      #("source", json.string("canonical_sa_plan_snapshot")),
      #("authority", json.string("NONE")),
      #("runtime_admission", json.string("NOT_GRANTED")),
      #("plan_id", json.string(expected_plan)),
      #("scope", json.string("configured_plan_task_ids_and_states")),
      #("observed_tasks_total", json.int(snapshot.total)),
      #("matched_total", json.int(matched_total)),
      #("shown", json.int(shown)),
      #("truncated", json.bool(matched_total > shown)),
      #("full_observation_sha256", json.string(snapshot.digest)),
      #("state_note", json.string("Recorded task state is a snapshot and does not prove lease freshness.")),
      #("tasks", json.array(visible, encode_search_task)),
    ])
    |> json.to_string
  case string.byte_size(out) <= 16_384 {
    True -> Ok(out)
    False -> Error("task_search_output_too_large")
  }
}

pub fn search_tasks(req: observer.ObserveRequest, query: String) -> Result(String, String) {
  use trimmed_query <- result.try(parse_query(query))
  use _ <- result.try(case observer.valid_id(req.plan_id) {
    True -> Ok(Nil)
    False -> Error("invalid_observation_bounds")
  })
  let request = observer.ObserveRequest(..req, task_id: observer.NoTask)
  use observed <- result.try(observer.observe(request)
    |> result.replace_error("task_observer_failed"))
  use _ <- result.try(case observed.guardian_result == "child_exited"
    && observed.cleanup == "confirmed" && observed.child_exit == 0
    && bit_array.byte_size(observed.payload) <= 262_144 {
    True -> Ok(Nil)
    False -> Error("task_observer_failed")
  })
  use raw <- result.try(bit_array.to_string(observed.payload)
    |> result.replace_error("invalid_task_observation_encoding"))
  search_project(raw, req.plan_id, trimmed_query)
}
