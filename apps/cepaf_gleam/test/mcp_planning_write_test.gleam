import cepaf_gleam/mcp/adapters/planning_write as planning
import cepaf_gleam/mcp/admission.{TaskCompleted, TaskExecuting, type ValidatedCall, ValidatedCall}
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/types.{
  type Outcome, ClientProfile, Complete, NonRetryable, Refused, ToolError,
}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleeunit/should

fn call(
  tool: String,
  actor: String,
  extra: List(#(String, String)),
) -> ValidatedCall {
  let assert Ok(spec) = registry.lookup("public", tool)
  ValidatedCall(
    spec,
    principal.from_launcher_env(
      actor: actor,
      client: ClientProfile("test"),
      workspace_root: "tenant-a",
      session_id: "test",
    ),
    dict.from_list(list.append([#("plan_id", "p"), #("task_id", "t")], extra)),
    None,
    None,
    None,
    None,
  )
}

fn seeded() -> planning.PlanningWriteStore {
  let #(outcome, store) =
    planning.execute(planning.new_store(), call("plan_add", "owner", []))
  let assert Complete(_, _) = outcome
  store
}

fn code(outcome: Outcome, expected: String) {
  let assert Refused(ToolError(actual, _, NonRetryable)) = outcome
  actual |> should.equal(expected)
}

pub fn legacy_update_cannot_skip_transition_test() {
  let before = seeded()
  let #(outcome, after) =
    planning.execute(
      before,
      call("plan_update", "owner", [#("state", "completed")]),
    )
  code(outcome, "INVALID_STATE_TRANSITION")
  after |> should.equal(before)
}

pub fn bridge_duplicate_does_not_double_submit_test() {
  let request = call("sa_bridge_submit", "owner", [#("bridge_key", "b")])
  let #(first, store) = planning.execute(seeded(), request)
  let #(second, after) = planning.execute(store, request)
  first |> should.equal(second)
  after |> should.equal(store)
  dict.size(after.jobs) |> should.equal(1)
  dict.size(after.bridge_submissions) |> should.equal(1)
}

pub fn sixteen_claimants_have_one_owner_test() {
  let #(store, successes, refusals) =
    list.fold(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
      #(seeded(), 0, 0),
      fn(acc, index) {
        let #(store, successes, refusals) = acc
        let #(outcome, next) =
          planning.execute(
            store,
            call("sa_task_claim", "worker-" <> int.to_string(index), [
              #("worker", "forged"),
            ]),
          )
        case outcome {
          Complete(_, _) -> #(next, successes + 1, refusals)
          _ -> {
            code(outcome, "TASK_ALREADY_CLAIMED")
            next |> should.equal(store)
            #(next, successes, refusals + 1)
          }
        }
      },
    )
  successes |> should.equal(1)
  refusals |> should.equal(15)
  let assert Ok(task) = dict.get(store.tasks, #("p", "t"))
  task.worker |> should.equal("worker-1")
  task.attempt |> should.equal(1)
  task.state |> should.equal(TaskExecuting)
}

pub fn stale_attempt_cannot_complete_test() {
  let #(_, claimed) =
    planning.execute(seeded(), call("sa_task_claim", "owner", []))
  let #(outcome, after) =
    planning.execute(
      claimed,
      call("sa_task_complete", "owner", [#("attempt", "0")]),
    )
  code(outcome, "STALE_ATTEMPT_FENCE")
  after |> should.equal(claimed)
}

pub fn payload_worker_cannot_impersonate_owner_test() {
  let #(_, claimed) =
    planning.execute(seeded(), call("sa_task_claim", "owner", []))
  let #(outcome, after) =
    planning.execute(
      claimed,
      call("sa_task_complete", "intruder", [
        #("attempt", "1"),
        #("worker", "owner"),
      ]),
    )
  code(outcome, "PRINCIPAL_WORKER_MISMATCH")
  after |> should.equal(claimed)
  let #(completed, final) =
    planning.execute(
      after,
      call("sa_task_complete", "owner", [#("attempt", "1")]),
    )
  let assert Complete(_, _) = completed
  let assert Ok(task) = dict.get(final.tasks, #("p", "t"))
  task.state |> should.equal(TaskCompleted)
}

pub fn job_and_workflow_transactions_test() {
  let #(job, store) =
    planning.execute(
      seeded(),
      call("sa_job_enqueue", "owner", [#("job_id", "j")]),
    )
  let assert Complete(_, _) = job
  let #(workflow, store) =
    planning.execute(
      store,
      call("sa_workflow_start", "owner", [#("workflow_id", "w")]),
    )
  let assert Complete(_, _) = workflow
  dict.get(store.jobs, "j") |> should.equal(Ok("owner"))
  dict.get(store.workflows, "w") |> should.equal(Ok("owner"))
}
