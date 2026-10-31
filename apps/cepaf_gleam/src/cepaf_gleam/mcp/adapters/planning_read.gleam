//// Planning Read Family Adapter (9 tools):
//// plan_status, plan_list_pending, plan_list, plan_get, plan_search,
//// sa_plan_status, sa_plan_status_for, sa_plan_list, feature_tracker_status.
//// Projects legacy plan_* fields from canonical sa-plan rows and separates
//// feature_tracker_status into the 5 distinct epistemic totals.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/evidence
import cepaf_gleam/mcp/types.{
  type Outcome, NonRetryable, Refused, Retryable, ToolError,
}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type CanonicalTaskRow {
  CanonicalTaskRow(
    plan_id: String,
    task_id: String,
    title: String,
    state: String,
    worker: String,
    attempt: Int,
  )
}

pub type PlanningReadStore {
  AvailableStore(default_plan_id: String, rows: List(CanonicalTaskRow))
  MultiPlanStore(
    default_plan_id: String,
    known_plans: List(String),
    rows: List(CanonicalTaskRow),
    plan_totals: Dict(String, #(Int, Int, Int, Int)),
    oban_jobs: Option(Int),
    temporal_workflows: Option(Int),
    truncated: Bool,
  )
  UnknownPlanStore(plan_id: String)
  UnavailableStore(reason: String)
}

pub type PlanTaskCounts {
  PlanTaskCounts(
    plan_id: String,
    total: Int,
    completed: Int,
    executing: Int,
    available: Int,
  )
}

pub fn multi_plan_available_store(
  default_plan_id: String,
  known_plans: List(String),
  rows: List(CanonicalTaskRow),
  oban_job_count: Int,
  temporal_workflow_count: Int,
) -> PlanningReadStore {
  multi_plan_snapshot_store(
    default_plan_id,
    known_plans,
    rows,
    oban_job_count,
    temporal_workflow_count,
    list.map(known_plans, fn(plan) {
      counts_from_rows(plan, list.filter(rows, fn(r) { r.plan_id == plan }))
    }),
  )
}

pub fn multi_plan_snapshot_store(
  default_plan_id: String,
  known_plans: List(String),
  rows: List(CanonicalTaskRow),
  oban_job_count: Int,
  temporal_workflow_count: Int,
  counts: List(PlanTaskCounts),
) -> PlanningReadStore {
  MultiPlanStore(
    default_plan_id,
    known_plans,
    rows,
    dict.from_list(
      list.map(counts, fn(c) {
        #(c.plan_id, #(c.total, c.completed, c.executing, c.available))
      }),
    ),
    Some(oban_job_count),
    Some(temporal_workflow_count),
    list.fold(counts, 0, fn(total, c) { total + c.total }) > list.length(rows),
  )
}

pub fn plan_task_counts_decoder() -> decode.Decoder(PlanTaskCounts) {
  use plan <- decode.field("plan_id", decode.string)
  use total <- decode.field("total", decode.int)
  use completed <- decode.field("completed", decode.int)
  use executing <- decode.field("executing", decode.int)
  use available <- decode.field("available", decode.int)
  decode.success(PlanTaskCounts(plan, total, completed, executing, available))
}

fn counts_from_rows(
  plan: String,
  rows: List(CanonicalTaskRow),
) -> PlanTaskCounts {
  PlanTaskCounts(
    plan,
    list.length(rows),
    list.count(rows, fn(r) { r.state == "completed" }),
    list.count(rows, fn(r) { r.state == "executing" }),
    list.count(rows, fn(r) { r.state == "available" }),
  )
}

fn select_counts(plan: String, counts: List(PlanTaskCounts)) -> PlanTaskCounts {
  let selected = case plan {
    "all" -> counts
    _ -> list.filter(counts, fn(c) { c.plan_id == plan })
  }
  list.fold(selected, PlanTaskCounts(plan, 0, 0, 0, 0), fn(sum, c) {
    PlanTaskCounts(
      plan,
      sum.total + c.total,
      sum.completed + c.completed,
      sum.executing + c.executing,
      sum.available + c.available,
    )
  })
}

pub fn sample_canonical_store(
  plan_id plan_id: String,
  rows rows: List(CanonicalTaskRow),
) -> PlanningReadStore {
  AvailableStore(default_plan_id: plan_id, rows: rows)
}

pub fn unavailable_store(reason: String) -> PlanningReadStore {
  UnavailableStore(reason: reason)
}

pub fn canonical_row_digest(payload_json: String) -> String {
  files.digest(payload_json)
}

pub fn execute(
  store: PlanningReadStore,
  tool_name: String,
  args: Dict(String, String),
) -> Outcome {
  case store {
    UnknownPlanStore(plan) ->
      Refused(ToolError(
        "UNKNOWN_PLAN_ID",
        "Unknown canonical plan: " <> plan,
        NonRetryable,
      ))
    UnavailableStore(reason) ->
      Refused(ToolError(
        code: "SA_PLAN_STORE_UNAVAILABLE",
        reason: reason,
        retryability: Retryable,
      ))
    AvailableStore(default_plan_id, rows) ->
      execute_legacy(default_plan_id, rows, tool_name, args)
    MultiPlanStore(default, plans, rows, totals, jobs, workflows, truncated) ->
      execute_snapshot(
        default,
        plans,
        rows,
        totals,
        jobs,
        workflows,
        truncated,
        tool_name,
        args,
      )
  }
}

fn execute_legacy(
  default_plan_id: String,
  rows: List(CanonicalTaskRow),
  tool_name: String,
  args: Dict(String, String),
) -> Outcome {
  let requested_plan = case dict.get(args, "plan_id") {
    Ok(id) if id != "" -> id
    _ ->
      case dict.get(args, "plan") {
        Ok(id) if id != "" -> id
        _ -> default_plan_id
      }
  }
  case requested_plan == default_plan_id {
    False ->
      Refused(ToolError(
        code: "UNKNOWN_PLAN_ID",
        reason: "Plan ID not found in canonical Sa-plan store: "
          <> requested_plan,
        retryability: NonRetryable,
      ))
    True ->
      render_tool(
        tool_name,
        requested_plan,
        rows,
        args,
        1,
        None,
        None,
        counts_from_rows(requested_plan, rows),
        False,
      )
  }
}

fn execute_snapshot(
  default_plan_id: String,
  plans: List(String),
  rows: List(CanonicalTaskRow),
  totals: Dict(String, #(Int, Int, Int, Int)),
  jobs: Option(Int),
  workflows: Option(Int),
  truncated: Bool,
  tool_name: String,
  args: Dict(String, String),
) -> Outcome {
  let counts =
    list.map(dict.to_list(totals), fn(entry) {
      let #(plan, #(total, completed, executing, available)) = entry
      PlanTaskCounts(plan, total, completed, executing, available)
    })
  let requested = case dict.get(args, "plan_id") {
    Ok(id) if id != "" -> id
    _ ->
      case dict.get(args, "plan") {
        Ok(id) if id != "" -> id
        _ -> default_plan_id
      }
  }
  let task_id =
    dict.get(args, "task_id")
    |> result.unwrap(dict.get(args, "id") |> result.unwrap(""))
  let explicit_plan =
    list.any(["plan_id", "plan"], fn(key) {
      dict.get(args, key) |> result.unwrap("") != ""
    })
  let ambiguous =
    tool_name == "plan_get"
    && !explicit_plan
    && rows
    |> list.filter(fn(row) { row.task_id == task_id })
    |> list.map(fn(row) { row.plan_id })
    |> list.unique
    |> list.length
    > 1
  case ambiguous {
    True ->
      Refused(ToolError(
        "AMBIGUOUS_TASK_ID",
        "Task ID occurs in more than one plan; supply plan_id",
        NonRetryable,
      ))
    False ->
      case requested == "" || requested == "all" {
        True ->
          render_tool(
            tool_name,
            "all",
            rows,
            args,
            list.length(plans),
            jobs,
            workflows,
            select_counts("all", counts),
            truncated,
          )
        False ->
          case list.contains(plans, requested) {
            False ->
              Refused(ToolError(
                "UNKNOWN_PLAN_ID",
                "Unknown canonical plan: " <> requested,
                NonRetryable,
              ))
            True ->
              render_tool(
                tool_name,
                requested,
                list.filter(rows, fn(row) { row.plan_id == requested }),
                args,
                list.length(plans),
                jobs,
                workflows,
                select_counts(requested, counts),
                truncated,
              )
          }
      }
  }
}

fn optional_int(value: Option(Int)) -> json.Json {
  case value {
    Some(n) -> json.int(n)
    None -> json.null()
  }
}

fn render_tool(
  tool_name: String,
  plan_id: String,
  rows: List(CanonicalTaskRow),
  args: Dict(String, String),
  total_plans: Int,
  oban_jobs: Option(Int),
  temporal_workflows: Option(Int),
  counts: PlanTaskCounts,
  truncated: Bool,
) -> Outcome {
  case tool_name {
    "plan_list" | "sa_plan_list" -> {
      let rows = case dict.get(args, "status") {
        Ok("pending") ->
          list.filter(rows, fn(row) {
            list.contains(["available", "ready", "pending"], row.state)
          })
        Ok("in_progress") ->
          list.filter(rows, fn(row) {
            list.contains(["claimed", "executing", "in_progress"], row.state)
          })
        Ok("completed") ->
          list.filter(rows, fn(row) { row.state == "completed" })
        Ok("blocked") ->
          list.filter(rows, fn(row) {
            row.state == "blocked" || row.state == "hold"
          })
        _ -> rows
      }
      let payload = encode_rows(plan_id, rows, truncated)
      evidence.classify_backend_payload(
        "public",
        tool_name,
        payload,
        candidate_id.current(),
      )
    }
    "plan_list_pending" -> {
      let pending = list.filter(rows, fn(r) { r.state != "completed" })
      let payload = encode_rows(plan_id, pending, truncated)
      evidence.classify_backend_payload(
        "public",
        tool_name,
        payload,
        candidate_id.current(),
      )
    }
    "plan_status" | "sa_plan_status" | "sa_plan_status_for" -> {
      let payload =
        json.object([
          #("plan_id", json.string(plan_id)),
          #("total_tasks", json.int(counts.total)),
          #("completed_tasks", json.int(counts.completed)),
          #("executing_tasks", json.int(counts.executing)),
          #("available_tasks", json.int(counts.available)),
          #("canonical_authority", json.string("sa_plan")),
          #("total_plans", json.int(total_plans)),
          #("truncated", json.bool(truncated)),
          #("background_counts_scope", json.string("store")),
          #("oban_jobs", optional_int(oban_jobs)),
          #("temporal_workflows", optional_int(temporal_workflows)),
        ])
        |> json.to_string
      evidence.classify_backend_payload(
        "public",
        tool_name,
        payload,
        candidate_id.current(),
      )
    }
    "plan_get" -> {
      let target_id = case dict.get(args, "task_id") {
        Ok(id) if id != "" -> id
        _ ->
          case dict.get(args, "id") {
            Ok(id) -> id
            Error(_) -> ""
          }
      }
      case list.find(rows, fn(r) { r.task_id == target_id }) {
        Ok(row) -> {
          let payload = encode_row(row) |> json.to_string
          evidence.classify_backend_payload(
            "public",
            tool_name,
            payload,
            candidate_id.current(),
          )
        }
        Error(_) if truncated ->
          Refused(ToolError(
            code: "SA_PLAN_SNAPSHOT_TRUNCATED",
            reason: "Task absence cannot be established from a truncated snapshot",
            retryability: NonRetryable,
          ))
        Error(_) ->
          Refused(ToolError(
            code: "UNKNOWN_TASK_ID",
            reason: "Task not found: " <> target_id,
            retryability: NonRetryable,
          ))
      }
    }
    "plan_search" -> {
      let query = case dict.get(args, "query") {
        Ok(q) -> string.lowercase(q)
        Error(_) -> ""
      }
      let matched =
        list.filter(rows, fn(r) {
          string.contains(string.lowercase(r.title), query)
          || string.contains(string.lowercase(r.task_id), query)
        })
      let payload = encode_rows(plan_id, matched, truncated)
      evidence.classify_backend_payload(
        "public",
        tool_name,
        payload,
        candidate_id.current(),
      )
    }
    "feature_tracker_status" -> {
      let declared_total = counts.total
      let implemented_total = counts.executing + counts.completed
      let observed_executed_total = 0
      let formally_verified_total = 0
      let admitted_total = 0
      let admitted_ev_ceiling = 93
      let basis = "canonical_plan_rows_only"
      let payload =
        json.object([
          #("declared_total", json.int(declared_total)),
          #("implemented_total", json.int(implemented_total)),
          #("observed_executed_total", json.int(observed_executed_total)),
          #("formally_verified_total", json.int(formally_verified_total)),
          #("admitted_total", json.int(admitted_total)),
          #("admitted_ev_ceiling", json.int(admitted_ev_ceiling)),
          #("basis", json.string(basis)),
          #("completed_is_not_observed", json.bool(True)),
          #("truncated", json.bool(truncated)),
        ])
        |> json.to_string
      evidence.classify_backend_payload(
        "public",
        tool_name,
        payload,
        candidate_id.current(),
      )
    }
    _ ->
      Refused(ToolError(
        code: "UNSUPPORTED_PLANNING_READ_TOOL",
        reason: "Unsupported tool in planning_read adapter: " <> tool_name,
        retryability: NonRetryable,
      ))
  }
}

fn encode_rows(
  plan_id: String,
  rows: List(CanonicalTaskRow),
  truncated: Bool,
) -> String {
  json.object([
    #("plan_id", json.string(plan_id)),
    #("rows", json.array(rows, encode_row)),
    #("truncated", json.bool(truncated)),
  ])
  |> json.to_string
}

fn encode_row(row: CanonicalTaskRow) -> json.Json {
  json.object([
    #("plan_id", json.string(row.plan_id)),
    #("task_id", json.string(row.task_id)),
    #("title", json.string(row.title)),
    #("state", json.string(row.state)),
    #("worker", json.string(row.worker)),
    #("attempt", json.int(row.attempt)),
  ])
}
