import cepaf_gleam/planning/execution_projection as execution
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

const now = "2026-09-21T04:00:00Z"

fn task(id: String, dependencies: List(String)) -> execution.Task {
  execution.Task(id, id, "available", None, 0, None, None, False, dependencies)
}

fn risk(id: String) -> execution.Risk {
  execution.Risk(
    id,
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
}

fn snapshot(tasks: List(execution.Task), risks: List(execution.Risk)) {
  execution.project(tasks, Ok(risks), 1000, now)
}

pub fn completion_is_canonical_not_catalog_stage_test() {
  let completed =
    execution.Task(
      ..task("done", []),
      state: "completed",
      result_present: True,
      completed_at_ns: Some(900),
    )
  let assert Ok(view) =
    snapshot([completed, task("open", [])], [risk("done"), risk("open")])
  view.completed |> should.equal(1)
  view.total |> should.equal(2)
  view.recommendations |> should.equal(["open"])
}

pub fn completed_dependencies_do_not_receive_inherited_priority_test() {
  let completed_parent =
    execution.Task(
      ..task("done", []),
      state: "completed",
      result_present: True,
      completed_at_ns: Some(900),
    )
  let blocked_child =
    execution.Task(..task("child", ["done"]), state: "available")
  let assert Ok(view) =
    snapshot(
      [completed_parent, blocked_child],
      [risk("done"), execution.Risk(..risk("child"), dependencies: ["done"])],
    )
  dict.get(view.priorities, "done") |> should.be_error()
  view.recommendations |> should.equal(["child"])
}

pub fn missing_result_and_future_completion_are_refused_test() {
  snapshot([execution.Task(..task("bad", []), state: "completed")], [])
  |> should.be_error
  snapshot(
    [
      execution.Task(
        ..task("bad", []),
        state: "completed",
        result_present: True,
        completed_at_ns: Some(1001),
      ),
    ],
    [],
  )
  |> should.be_error
}

pub fn missing_empty_duplicate_and_cyclic_graphs_fail_closed_test() {
  snapshot([], []) |> should.be_error
  snapshot([task("a", []), task("a", [])], []) |> should.be_error
  snapshot([task("a", ["missing"])], []) |> should.be_error
  snapshot([task("a", ["b"]), task("b", ["a"])], []) |> should.be_error
  snapshot([task("a", ["a"])], []) |> should.be_error
  snapshot([execution.Task(..task("a", []), state: "passed")], [])
  |> should.be_error
}

pub fn dependency_and_safety_gates_precede_score_test() {
  let blocked_risk = execution.Risk(..risk("blocked"), dependencies: ["a"])
  let assert Ok(view) =
    snapshot([task("a", []), task("blocked", ["a"])], [risk("a"), blocked_risk])
  view.recommendations |> should.equal(["a"])
  let assert Ok(blocked) =
    list.find(view.rows, fn(row) { row.task.id == "blocked" })
  blocked.status |> should.equal(execution.Blocked)
  snapshot([task("unsafe", [])], [
    execution.Risk(..risk("unsafe"), readiness: "blocked", blockers: [
      "No release authority",
    ]),
  ])
  |> should.be_ok
  let assert Ok(held) =
    snapshot([task("unsafe", [])], [
      execution.Risk(..risk("unsafe"), readiness: "blocked"),
    ])
  held.recommendations |> should.equal([])
}

pub fn missing_stale_future_or_state_mismatched_risk_never_recommends_test() {
  list.each(
    [
      [],
      [execution.Risk(..risk("a"), valid_until: now)],
      [execution.Risk(..risk("a"), observed_at: "2026-09-22T00:00:00Z")],
      [execution.Risk(..risk("a"), task_state: "completed")],
      [execution.Risk(..risk("a"), dependencies: ["phantom"])],
      [execution.Risk(..risk("a"), factors: [execution.Factor(5, 1, 5)])],
    ],
    fn(risks) {
      let assert Ok(view) = snapshot([task("a", [])], risks)
      view.recommendations |> should.equal([])
    },
  )
}

pub fn executing_or_expired_lease_is_not_available_work_test() {
  list.each([Some(999), Some(1001), None], fn(lease) {
    let busy =
      execution.Task(
        ..task("busy", []),
        state: "executing",
        worker: Some("worker"),
        attempt: 1,
        lease_until_ns: lease,
      )
    let assert Ok(view) = snapshot([busy], [risk("busy")])
    view.recommendations |> should.equal([])
  })
}

pub fn safety_class_then_score_then_age_then_id_order_test() {
  let tasks = [
    task("high-score", []),
    task("safety", []),
    task("old", []),
    task("new", []),
  ]
  let risks = [
    risk("high-score"),
    execution.Risk(
      ..risk("safety"),
      class: "P0",
      factors: list.repeat(execution.Factor(1, 1, 1), 5),
    ),
    execution.Risk(..risk("old"), ready_since: "2026-09-21T02:00:00Z"),
    risk("new"),
  ]
  let assert Ok(view) = snapshot(tasks, risks)
  view.recommendations |> should.equal(["safety", "old", "high-score", "new"])
  let assert Ok(reversed) = snapshot(list.reverse(tasks), list.reverse(risks))
  view |> should.equal(reversed)
}

pub fn factor_uncertainty_and_invalid_dates_fail_closed_test() {
  let uncertain =
    execution.Risk(
      ..risk("a"),
      factors: list.repeat(execution.Factor(5, 4, 5), 5),
    )
  let assert Ok(view) = snapshot([task("a", [])], [uncertain])
  view.recommendations |> should.equal([])
  list.each(
    [
      "",
      "2026-02-30T00:00:00Z",
      "2026-09-21T25:00:00Z",
      "2026-09-21T04:00:00+00:00",
    ],
    fn(timestamp) {
      execution.project([task("a", [])], Ok([risk("a")]), 1000, timestamp)
      |> should.be_error
    },
  )
}

pub fn unknown_risk_does_not_erase_real_completion_test() {
  let complete =
    execution.Task(
      ..task("done", []),
      state: "completed",
      result_present: True,
      completed_at_ns: Some(999),
    )
  let assert Ok(view) =
    execution.project(
      [complete, task("a", [])],
      Error("unavailable"),
      1000,
      now,
    )
  view.completed |> should.equal(1)
  view.recommendations |> should.equal([])
}

pub fn task_and_edge_resource_bounds_fail_closed_test() {
  snapshot(list.repeat(task("a", []), 257), []) |> should.be_error
  snapshot([task("a", list.repeat("b", 257)), task("b", [])], [])
  |> should.be_error
}

pub fn blocked_consumer_urgency_propagates_without_making_consumer_eligible_test() {
  let parent =
    execution.Risk(
      ..risk("parent"),
      class: "P3",
      factors: list.repeat(execution.Factor(1, 1, 1), 5),
    )
  let child =
    execution.Risk(
      ..risk("child"),
      class: "P0",
      dependencies: ["parent"],
      readiness: "blocked",
    )
  let assert Ok(view) =
    snapshot(
      [task("parent", []), task("child", ["parent"]), task("other", [])],
      [parent, child, risk("other")],
    )
  view.recommendations |> should.equal(["parent", "other"])
  let assert Ok(priority) = dict.get(view.priorities, "parent")
  priority.task_id |> should.equal("child")
}

pub fn propagated_priority_agrees_with_small_reference_interpretation_test() {
  list.each(["P0", "P1", "P2"], fn(parent_class) {
    list.each(["P0", "P1", "P2"], fn(child_class) {
      list.each(["P0", "P1", "P2"], fn(other_class) {
        let tasks = [
          task("parent", []),
          task("child", ["parent"]),
          task("other", []),
        ]
        let risks = [
          execution.Risk(..risk("parent"), class: parent_class),
          execution.Risk(..risk("child"), class: child_class, dependencies: [
            "parent",
          ]),
          execution.Risk(..risk("other"), class: other_class),
        ]
        let assert Ok(view) = snapshot(tasks, risks)
        let levels = ["P0", "P1", "P2"]
        let assert Ok(effective_parent) =
          list.find(levels, fn(level) {
            level == parent_class || level == child_class
          })
        let assert Ok(first_class) =
          list.find(levels, fn(level) {
            level == effective_parent || level == other_class
          })
        let expected = case first_class == other_class {
          True -> ["other", "parent"]
          False -> ["parent", "other"]
        }
        view.recommendations |> should.equal(expected)
        let assert Ok(reversed) =
          snapshot(list.reverse(tasks), list.reverse(risks))
        reversed |> should.equal(view)
        {
          view.completed
          + view.executing
          + view.blocked
          + view.unknown
          + list.length(view.recommendations)
        }
        |> should.equal(view.total)
      })
    })
  })
}

pub fn incomplete_duplicate_or_foreign_risk_sets_do_not_enable_dispatch_test() {
  list.each(
    [
      [risk("a")],
      [risk("a"), risk("a")],
      [risk("a"), risk("b"), risk("foreign")],
    ],
    fn(risks) {
      let assert Ok(view) = snapshot([task("a", []), task("b", [])], risks)
      view.recommendations |> should.equal([])
      view.unknown |> should.equal(2)
    },
  )
}

pub fn completed_dependent_with_unfinished_parent_is_not_counted_test() {
  let completed =
    execution.Task(
      ..task("child", ["parent"]),
      state: "completed",
      result_present: True,
      completed_at_ns: Some(999),
    )
  snapshot([completed, task("parent", [])], []) |> should.be_error
}
