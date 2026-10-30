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
import gleam/json
import gleam/list
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
  UnavailableStore(reason: String)
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
    UnavailableStore(reason) ->
      Refused(ToolError(
        code: "SA_PLAN_STORE_UNAVAILABLE",
        reason: reason,
        retryability: Retryable,
      ))
    AvailableStore(default_plan_id, rows) -> {
      let requested_plan = case dict.get(args, "plan_id") {
        Ok(id) if id != "" -> id
        _ -> default_plan_id
      }
      case requested_plan == default_plan_id {
        False ->
          Refused(ToolError(
            code: "UNKNOWN_PLAN_ID",
            reason: "Plan ID not found in canonical Sa-plan store: "
              <> requested_plan,
            retryability: NonRetryable,
          ))
        True -> render_tool(tool_name, requested_plan, rows, args)
      }
    }
  }
}

fn render_tool(
  tool_name: String,
  plan_id: String,
  rows: List(CanonicalTaskRow),
  args: Dict(String, String),
) -> Outcome {
  case tool_name {
    "plan_list" | "sa_plan_list" -> {
      let payload = encode_rows(plan_id, rows)
      evidence.classify_backend_payload(
        "public",
        tool_name,
        payload,
        candidate_id.current(),
      )
    }
    "plan_list_pending" -> {
      let pending = list.filter(rows, fn(r) { r.state != "completed" })
      let payload = encode_rows(plan_id, pending)
      evidence.classify_backend_payload(
        "public",
        tool_name,
        payload,
        candidate_id.current(),
      )
    }
    "plan_status" | "sa_plan_status" | "sa_plan_status_for" -> {
      let completed = list.count(rows, fn(r) { r.state == "completed" })
      let executing = list.count(rows, fn(r) { r.state == "executing" })
      let available = list.count(rows, fn(r) { r.state == "available" })
      let payload =
        json.object([
          #("plan_id", json.string(plan_id)),
          #("total_tasks", json.int(list.length(rows))),
          #("completed_tasks", json.int(completed)),
          #("executing_tasks", json.int(executing)),
          #("available_tasks", json.int(available)),
          #("canonical_authority", json.string("sa_plan")),
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
        Ok(id) -> id
        Error(_) -> ""
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
      let payload = encode_rows(plan_id, matched)
      evidence.classify_backend_payload(
        "public",
        tool_name,
        payload,
        candidate_id.current(),
      )
    }
    "feature_tracker_status" -> {
      let declared_total = list.length(rows)
      let implemented_total =
        list.count(rows, fn(r) {
          r.state == "executing" || r.state == "completed"
        })
      let observed_executed_total =
        list.count(rows, fn(r) { r.state == "completed" })
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

fn encode_rows(plan_id: String, rows: List(CanonicalTaskRow)) -> String {
  json.object([
    #("plan_id", json.string(plan_id)),
    #("rows", json.array(rows, encode_row)),
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
