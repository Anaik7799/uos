// ==============================================================================
// [UOS-SDLC-SA-PLAN-TEST] Test Suite for Sa-Plan Durable Engine
// ==============================================================================

import cepaf_gleam/sdlc/sa_plan_engine.{
  JobCompleted, PlanActive, TaskClaimed, TaskCompleted, WorkflowCompleted,
  claim_job, claim_task, complete_job, complete_task, complete_workflow,
  create_plan, create_task, enqueue_job, new_store, record_workflow_activity,
  start_workflow, validate_sa_plan_durability,
}
import gleam/list
import gleam/option.{None}
import gleeunit/should

pub fn plan_and_task_lifecycle_test() {
  let store0 = new_store()
  let assert Ok(store1) =
    create_plan(
      store0,
      "PLAN-01",
      "uos/sdlc/transmutation",
      "Transmutation Plan",
      1_773_312_000_000,
    )

  // Plan exists and active
  list.length(store1.plans) |> should.equal(1)
  let assert Ok(p) = list.first(store1.plans)
  p.status |> should.equal(PlanActive)

  // Create task
  let assert Ok(store2) =
    create_task(
      store1,
      "PLAN-01",
      "TASK-01",
      "uos/sdlc/transmutation/task-1",
      "Implement Sa-Plan Engine",
      None,
      [],
    )
  list.length(store2.tasks) |> should.equal(1)

  // Claim task
  let assert Ok(store3) =
    claim_task(
      store2,
      "PLAN-01",
      "TASK-01",
      "agent-gleam-worker",
      60_000,
      1_773_312_000_000,
    )
  let assert Ok(t3) = list.first(store3.tasks)
  case t3.status {
    TaskClaimed(worker, lease) -> {
      worker |> should.equal("agent-gleam-worker")
      lease |> should.equal(1_773_312_060_000)
      True
    }
    _ -> False
  }
  |> should.equal(True)

  // Complete task
  let assert Ok(store4) =
    complete_task(
      store3,
      "PLAN-01",
      "TASK-01",
      "agent-gleam-worker",
      "Engine tested and verified green",
    )
  let assert Ok(t4) = list.first(store4.tasks)
  case t4.status {
    TaskCompleted(worker, result) -> {
      worker |> should.equal("agent-gleam-worker")
      result |> should.equal("Engine tested and verified green")
      True
    }
    _ -> False
  }
  |> should.equal(True)

  validate_sa_plan_durability(store4) |> should.equal(True)
}

pub fn job_enqueue_and_claim_test() {
  let store0 = new_store()
  let assert Ok(store1) =
    enqueue_job(
      store0,
      "JOB-01",
      "regenerate_ontology",
      "{\"target\": \"all\"}",
      3,
    )
  list.length(store1.jobs) |> should.equal(1)

  let assert Ok(store2) = claim_job(store1, "JOB-01", "job-worker-1")
  let assert Ok(j2) = list.first(store2.jobs)
  j2.attempts |> should.equal(1)

  let assert Ok(store3) =
    complete_job(store2, "JOB-01", "Ontology graph generated")
  let assert Ok(j3) = list.first(store3.jobs)
  case j3.status {
    JobCompleted(res) -> {
      res |> should.equal("Ontology graph generated")
      True
    }
    _ -> False
  }
  |> should.equal(True)
}

pub fn workflow_activity_test() {
  let store0 = new_store()
  let assert Ok(store1) =
    start_workflow(
      store0,
      "WF-01",
      "monorepo_migration",
      "source_freeze",
      1_773_312_000_000,
    )
  let assert Ok(store2) =
    record_workflow_activity(
      store1,
      "WF-01",
      "jujutsu_init",
      "COMPLETED",
      1_773_312_001_000,
    )
  let assert Ok(store3) =
    complete_workflow(store2, "WF-01", "verification_pass", 1_773_312_002_000)

  let assert Ok(wf) = list.first(store3.workflows)
  wf.status |> should.equal(WorkflowCompleted)
  list.length(wf.activities) |> should.equal(3)
}
