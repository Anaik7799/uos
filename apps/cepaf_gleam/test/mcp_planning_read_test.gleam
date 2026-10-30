import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/types.{Complete, NonRetryable, Refused}
import gleam/dict
import gleam/string
import gleeunit/should

pub fn legacy_and_sa_plan_reads_return_same_canonical_rows_test() {
  let store =
    planning_read.sample_canonical_store(
      plan_id: "20261029-1913-mcp-server-completion",
      rows: [
        planning_read.CanonicalTaskRow(
          plan_id: "20261029-1913-mcp-server-completion",
          task_id: "T01",
          title: "Route Census",
          state: "completed",
          worker: "pi-session-20261030-0754",
          attempt: 1,
        ),
        planning_read.CanonicalTaskRow(
          plan_id: "20261029-1913-mcp-server-completion",
          task_id: "T05",
          title: "Planning Read Family",
          state: "executing",
          worker: "agy-worker-20261030",
          attempt: 1,
        ),
        planning_read.CanonicalTaskRow(
          plan_id: "20261029-1913-mcp-server-completion",
          task_id: "T06",
          title: "Planning Write Family",
          state: "available",
          worker: "",
          attempt: 0,
        ),
      ],
    )

  let legacy_list =
    planning_read.execute(
      store,
      "plan_list",
      dict.from_list([#("plan_id", "20261029-1913-mcp-server-completion")]),
    )
  let sa_list =
    planning_read.execute(
      store,
      "sa_plan_list",
      dict.from_list([#("plan_id", "20261029-1913-mcp-server-completion")]),
    )

  case legacy_list, sa_list {
    Complete(legacy_json, _), Complete(sa_json, _) -> {
      planning_read.canonical_row_digest(legacy_json)
      |> should.equal(planning_read.canonical_row_digest(sa_json))
      string.contains(legacy_json, "\"T05\"") |> should.be_true()
      string.contains(sa_json, "\"T05\"") |> should.be_true()
    }
    _, _ -> should.fail()
  }

  // Also verify feature_tracker_status separates the 5 distinct epistemic totals
  case planning_read.execute(store, "feature_tracker_status", dict.new()) {
    Complete(tracker_json, _) -> {
      string.contains(tracker_json, "\"declared_total\":") |> should.be_true()
      string.contains(tracker_json, "\"implemented_total\":") |> should.be_true()
      string.contains(tracker_json, "\"observed_executed_total\":")
      |> should.be_true()
      string.contains(tracker_json, "\"formally_verified_total\":")
      |> should.be_true()
      string.contains(tracker_json, "\"admitted_total\":") |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn unknown_plan_is_not_global_completion_test() {
  let store =
    planning_read.sample_canonical_store(
      plan_id: "20261029-1913-mcp-server-completion",
      rows: [],
    )

  let res =
    planning_read.execute(
      store,
      "sa_plan_status_for",
      dict.from_list([#("plan_id", "non-existent-plan-999")]),
    )

  case res {
    Refused(err) -> {
      err.code |> should.equal("UNKNOWN_PLAN_ID")
      err.retryability |> should.equal(NonRetryable)
    }
    _ -> should.fail()
  }
}

pub fn unavailable_store_is_tool_error_test() {
  let broken_store = planning_read.unavailable_store("sqlite_open_failed: /missing/db")

  case planning_read.execute(broken_store, "sa_plan_status", dict.new()) {
    Refused(err) -> {
      err.code |> should.equal("SA_PLAN_STORE_UNAVAILABLE")
    }
    _ -> should.fail()
  }
}
