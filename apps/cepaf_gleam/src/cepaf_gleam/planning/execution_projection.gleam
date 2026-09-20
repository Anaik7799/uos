import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string

pub const plan_id = "uos/system-mcp-features/20260919-1642"

pub type Task {
  Task(
    id: String,
    title: String,
    state: String,
    worker: Option(String),
    attempt: Int,
    lease_until_ns: Option(Int),
    completed_at_ns: Option(Int),
    result_present: Bool,
    dependencies: List(String),
  )
}

pub type Factor {
  Factor(value: Int, low: Int, high: Int)
}

pub type Risk {
  Risk(
    task_id: String,
    task_state: String,
    class: String,
    readiness: String,
    blockers: List(String),
    dependencies: List(String),
    observed_at: String,
    valid_until: String,
    ready_since: String,
    factors: List(Factor),
  )
}

pub type Status {
  Completed
  InProgress
  Blocked
  Unknown
  ReadyForPreflight
}

pub type Row {
  Row(task: Task, status: Status, reasons: List(String), risk: Option(Risk))
}

pub type Snapshot {
  Snapshot(
    observed_at: String,
    total: Int,
    completed: Int,
    executing: Int,
    blocked: Int,
    unknown: Int,
    rows: List(Row),
    recommendations: List(String),
    priorities: Dict(String, Risk),
  )
}

fn require(condition: Bool, message: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(message)
  }
}

pub fn valid_utc(timestamp: String) -> Bool {
  let year = string.slice(timestamp, 0, 4) |> int.parse |> result.unwrap(0)
  let month = string.slice(timestamp, 5, 2) |> int.parse |> result.unwrap(0)
  let day = string.slice(timestamp, 8, 2) |> int.parse |> result.unwrap(0)
  let hour = string.slice(timestamp, 11, 2) |> int.parse |> result.unwrap(-1)
  let minute = string.slice(timestamp, 14, 2) |> int.parse |> result.unwrap(-1)
  let second = string.slice(timestamp, 17, 2) |> int.parse |> result.unwrap(-1)
  let leap = year % 400 == 0 || { year % 4 == 0 && year % 100 != 0 }
  let days = case month {
    2 ->
      case leap {
        True -> 29
        False -> 28
      }
    4 | 6 | 9 | 11 -> 30
    _ -> 31
  }
  string.byte_size(timestamp) == 20
  && string.slice(timestamp, 4, 1) == "-"
  && string.slice(timestamp, 7, 1) == "-"
  && string.slice(timestamp, 10, 1) == "T"
  && string.slice(timestamp, 13, 1) == ":"
  && string.slice(timestamp, 16, 1) == ":"
  && string.slice(timestamp, 19, 1) == "Z"
  && list.all(
    [#(0, 4), #(5, 2), #(8, 2), #(11, 2), #(14, 2), #(17, 2)],
    fn(part) {
      string.slice(timestamp, part.0, part.1)
      |> string.to_graphemes
      |> list.all(fn(char) { string.contains("0123456789", char) })
    },
  )
  && year >= 1970
  && month >= 1
  && month <= 12
  && day >= 1
  && day <= days
  && hour >= 0
  && hour < 24
  && minute >= 0
  && minute < 60
  && second >= 0
  && second < 60
}

fn ordered(values: List(String)) -> List(String) {
  list.sort(values, string.compare)
}

fn topological(
  remaining: List(Task),
  done: List(Task),
) -> Result(List(Task), Nil) {
  case remaining {
    [] -> Ok(done)
    _ -> {
      let complete = list.map(done, fn(task) { task.id })
      let ready =
        list.filter(remaining, fn(task) {
          list.all(task.dependencies, fn(dependency) {
            list.contains(complete, dependency)
          })
        })
      case ready {
        [] -> Error(Nil)
        _ -> {
          let ids = list.map(ready, fn(task) { task.id })
          topological(
            list.filter(remaining, fn(task) { !list.contains(ids, task.id) }),
            list.append(done, ready),
          )
        }
      }
    }
  }
}

fn valid_tasks(tasks: List(Task), now_ns: Int) -> Result(Nil, String) {
  use _ <- result.try(require(
    !list.is_empty(tasks) && list.length(tasks) <= 256,
    "empty_or_overlarge_task_snapshot",
  ))
  let ids = list.map(tasks, fn(task) { task.id })
  use _ <- result.try(require(
    list.length(list.unique(ids)) == list.length(ids),
    "duplicate_task_identity",
  ))
  use _ <- result.try(
    list.try_each(tasks, fn(task) {
      use _ <- result.try(require(
        task.id != ""
          && string.byte_size(task.id) <= 256
          && string.byte_size(task.title) <= 4096
          && task.attempt >= 0,
        "invalid_task_fields",
      ))
      use _ <- result.try(require(
        list.contains(["available", "executing", "completed"], task.state),
        "unknown_task_state",
      ))
      use _ <- result.try(require(
        list.length(task.dependencies) <= 256
          && list.length(list.unique(task.dependencies))
          == list.length(task.dependencies),
        "invalid_dependency_set",
      ))
      case task.state {
        "completed" ->
          require(
            task.result_present
              && case task.completed_at_ns {
              Some(stamp) -> stamp > 0 && stamp <= now_ns
              None -> False
            }
              && list.all(task.dependencies, fn(dependency) {
              list.any(tasks, fn(other) {
                other.id == dependency && other.state == "completed"
              })
            }),
            "completion_missing_future_or_dependency_receipt",
          )
        _ -> Ok(Nil)
      }
    }),
  )
  use _ <- result.try(require(
    list.fold(tasks, 0, fn(total, task) {
      total + list.length(task.dependencies)
    })
      <= 4096,
    "dependency_graph_bound",
  ))
  topological(tasks, [])
  |> result.map(fn(_) { Nil })
  |> result.replace_error("missing_or_cyclic_dependency")
}

fn risk_current(risk: Risk, task: Task, now: String) -> Bool {
  list.all([risk.observed_at, risk.valid_until, risk.ready_since], valid_utc)
  && string.compare(risk.observed_at, now) != Gt
  && string.compare(risk.ready_since, now) != Gt
  && string.compare(now, risk.valid_until) == Lt
  && risk.task_state == task.state
  && ordered(risk.dependencies) == ordered(task.dependencies)
  && list.contains(["P0", "P1", "P2", "P3"], risk.class)
  && list.length(risk.factors) == 5
  && list.all(risk.factors, fn(factor) {
    factor.low >= 1
    && factor.high <= 5
    && factor.low <= factor.value
    && factor.value <= factor.high
  })
}

fn row(
  task: Task,
  tasks: List(Task),
  risks: List(Risk),
  now_ns: Int,
  now: String,
) -> Row {
  let risk =
    list.find(risks, fn(risk) { risk.task_id == task.id }) |> option.from_result
  let unfinished =
    list.filter(task.dependencies, fn(dependency) {
      !list.any(tasks, fn(other) {
        other.id == dependency && other.state == "completed"
      })
    })
  case task.state {
    "completed" ->
      Row(
        task,
        Completed,
        ["Sa-plan completion receipt present; not runtime admission"],
        risk,
      )
    "executing" ->
      case task.lease_until_ns, task.worker {
        Some(deadline), Some(worker) if deadline > now_ns && worker != "" ->
          Row(task, InProgress, ["Occupied by canonical worker/attempt"], risk)
        _, _ ->
          Row(
            task,
            Unknown,
            ["Expired or missing worker lease; reconciliation required"],
            risk,
          )
      }
    _ ->
      case unfinished, risk {
        [_, ..], _ ->
          Row(
            task,
            Blocked,
            list.map(unfinished, fn(id) { "Dependency incomplete: " <> id }),
            risk,
          )
        [], None -> Row(task, Unknown, ["Risk assessment unavailable"], risk)
        [], Some(assessment) ->
          case risk_current(assessment, task, now) {
            False ->
              Row(
                task,
                Unknown,
                [
                  "Risk assessment stale, invalid or inconsistent with canonical task",
                ],
                risk,
              )
            True ->
              case
                assessment.readiness == "ready"
                && list.is_empty(assessment.blockers)
              {
                False ->
                  Row(
                    task,
                    Blocked,
                    ["Risk/authority gate not ready", ..assessment.blockers],
                    risk,
                  )
                True ->
                  case
                    list.all(assessment.factors, fn(factor) {
                      factor.low == factor.high
                    })
                  {
                    False ->
                      Row(
                        task,
                        Unknown,
                        [
                          "Provisional factor interval; gather discriminating evidence",
                        ],
                        risk,
                      )
                    True ->
                      Row(
                        task,
                        ReadyForPreflight,
                        [
                          "Advisory only; source-bound preflight and effect-time authority still required",
                        ],
                        risk,
                      )
                  }
              }
          }
      }
  }
}

pub fn score(risk: Risk) -> Int {
  list.fold(risk.factors, 1, fn(product, factor) { product * factor.value })
}

fn compare_risks(first: Risk, second: Risk) -> order.Order {
  case string.compare(first.class, second.class) {
    Eq -> int.compare(score(second), score(first))
    other -> other
  }
}

fn priorities(rows: List(Row), now: String) -> Dict(String, Risk) {
  let tasks = list.map(rows, fn(row) { row.task })
  let initial =
    rows
    |> list.filter_map(fn(other) {
      case other.risk {
        Some(risk) ->
          case
            other.task.state != "completed"
            && risk_current(risk, other.task, now)
            && list.all(risk.factors, fn(factor) { factor.low == factor.high })
          {
            True -> Ok(#(other.task.id, risk))
            False -> Error(Nil)
          }
        None -> Error(Nil)
      }
    })
    |> dict.from_list
  let ordered_tasks =
    topological(tasks, []) |> result.unwrap([]) |> list.reverse
  list.fold(ordered_tasks, initial, fn(ranks, task) {
    case dict.get(ranks, task.id) {
      Error(_) -> ranks
      Ok(urgency) ->
        list.fold(task.dependencies, ranks, fn(ranks, dependency) {
          let dependency_completed =
            list.any(tasks, fn(candidate) {
              candidate.id == dependency && candidate.state == "completed"
            })
          case dependency_completed {
            True -> ranks
            False -> {
              let selected = case dict.get(ranks, dependency) {
                Error(_) -> urgency
                Ok(existing) ->
                  case compare_risks(urgency, existing) {
                    Lt -> urgency
                    Gt -> existing
                    Eq ->
                      case string.compare(urgency.task_id, existing.task_id) {
                        Lt -> urgency
                        _ -> existing
                      }
                  }
              }
              dict.insert(ranks, dependency, selected)
            }
          }
        })
    }
  })
}

fn compare(left: Row, right: Row, ranks: Dict(String, Risk)) -> order.Order {
  case dict.get(ranks, left.task.id), dict.get(ranks, right.task.id) {
    Ok(first), Ok(second) ->
      case string.compare(first.class, second.class) {
        Eq ->
          case int.compare(score(second), score(first)) {
            Eq ->
              case left.risk, right.risk {
                Some(left_risk), Some(right_risk) ->
                  case
                    string.compare(
                      left_risk.ready_since,
                      right_risk.ready_since,
                    )
                  {
                    Eq -> string.compare(left.task.id, right.task.id)
                    other -> other
                  }
                _, _ -> string.compare(left.task.id, right.task.id)
              }
            other -> other
          }
        other -> other
      }
    _, _ -> string.compare(left.task.id, right.task.id)
  }
}

pub fn project(
  tasks: List(Task),
  risks: Result(List(Risk), String),
  now_ns: Int,
  now: String,
) -> Result(Snapshot, String) {
  use _ <- result.try(require(
    now_ns > 0 && valid_utc(now),
    "invalid_observation_clock",
  ))
  use _ <- result.try(valid_tasks(tasks, now_ns))
  let tasks =
    list.sort(tasks, fn(left, right) { string.compare(left.id, right.id) })
  let risks = case risks {
    Ok(entries) ->
      case
        list.length(entries) <= 256
        && ordered(list.map(entries, fn(risk) { risk.task_id }))
        == ordered(list.map(tasks, fn(task) { task.id }))
      {
        True -> entries
        False -> []
      }
    Error(_) -> []
  }
  let rows = list.map(tasks, fn(task) { row(task, tasks, risks, now_ns, now) })
  let count = fn(status) {
    rows |> list.filter(fn(row) { row.status == status }) |> list.length
  }
  let ranks = priorities(rows, now)
  let recommendations =
    rows
    |> list.filter(fn(row) { row.status == ReadyForPreflight })
    |> list.sort(fn(left, right) { compare(left, right, ranks) })
    |> list.map(fn(row) { row.task.id })
  Ok(Snapshot(
    now,
    list.length(tasks),
    count(Completed),
    count(InProgress),
    count(Blocked),
    count(Unknown),
    rows,
    recommendations,
    ranks,
  ))
}

pub fn status_label(status: Status) -> String {
  case status {
    Completed -> "completed"
    InProgress -> "executing"
    Blocked -> "blocked"
    Unknown -> "unknown"
    ReadyForPreflight -> "ready_for_preflight"
  }
}

pub fn row_json(row: Row) -> json.Json {
  json.object([
    #("id", json.string(row.task.id)),
    #("title", json.string(row.task.title)),
    #("canonical_state", json.string(row.task.state)),
    #("status", json.string(status_label(row.status))),
    #("worker", case row.task.worker {
      None -> json.null()
      Some(worker) -> json.string(worker)
    }),
    #("attempt", json.int(row.task.attempt)),
    #("result_present", json.bool(row.task.result_present)),
    #("dependencies", json.array(row.task.dependencies, json.string)),
    #("reasons", json.array(row.reasons, json.string)),
    #("risk_class", case row.risk {
      None -> json.null()
      Some(risk) -> json.string(risk.class)
    }),
    #("risk_score", case row.risk {
      None -> json.null()
      Some(risk) -> json.int(score(risk))
    }),
  ])
}

pub fn to_json(snapshot: Snapshot) -> json.Json {
  json.object([
    #("page", json.string("Planning")),
    #("schema", json.string("uos.execution-progress.v1")),
    #("status", json.string("observed")),
    #("plan_id", json.string(plan_id)),
    #("observed_at", json.string(snapshot.observed_at)),
    #("total", json.int(snapshot.total)),
    #("completed", json.int(snapshot.completed)),
    #("executing", json.int(snapshot.executing)),
    #("blocked", json.int(snapshot.blocked)),
    #("unknown", json.int(snapshot.unknown)),
    #("tasks", json.array(snapshot.rows, row_json)),
    #("recommendations", json.array(snapshot.recommendations, json.string)),
    #(
      "effective_priorities",
      json.array(snapshot.rows, fn(row) {
        json.object([
          #("task_id", json.string(row.task.id)),
          #("priority", case dict.get(snapshot.priorities, row.task.id) {
            Error(_) -> json.null()
            Ok(risk) ->
              json.object([
                #("class", json.string(risk.class)),
                #("score", json.int(score(risk))),
                #("origin", json.string(risk.task_id)),
              ])
          }),
        ])
      }),
    ),
    #("effect_authority", json.bool(False)),
    #("system_admission", json.bool(False)),
    #(
      "optimization",
      json.string(
        "Authority/dependency readiness, safety class, C*T*F*Dep*I, oldest ready, stable ID; cost tie unavailable; local advisory, not a global optimum",
      ),
    ),
    #(
      "risk_source_binding",
      json.string(
        "NOT_VERIFIED_BY_DASHBOARD; canonical risk preflight required before claim",
      ),
    ),
  ])
}
