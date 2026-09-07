import cepaf_gleam/planning/sa_plan_bridge
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

pub fn all_17_aspects_coverage_test() {
  sa_plan_bridge.verify_17_aspects_coverage()
  |> should.be_true()

  let aspects = sa_plan_bridge.all_17_aspects()
  list.length(aspects)
  |> should.equal(17)

  // Verify each aspect has a unique ID from 1 to 17
  let ids = list.map(aspects, fn(a) { a.id })
  ids
  |> should.equal([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17])
}

pub fn actor_ecosystem_catalog_test() {
  sa_plan_bridge.verify_actor_ecosystem_completeness()
  |> should.be_true()

  let catalog = sa_plan_bridge.actor_ecosystem_catalog()
  let has_min_catalog = list.length(catalog) >= 20
  has_min_catalog |> should.be_true()

  let singles = sa_plan_bridge.single_instance_actors()
  let has_min_singles = list.length(singles) >= 12
  has_min_singles |> should.be_true()

  let multis = sa_plan_bridge.multi_instance_actors()
  let has_min_multis = list.length(multis) >= 7
  has_min_multis |> should.be_true()

  // Verify single instance actors have concurrency of 1
  let all_singles_valid =
    list.all(singles, fn(a: sa_plan_bridge.ActorDescriptor) {
      a.mode == sa_plan_bridge.SingleInstance && a.max_concurrency == 1
    })
  all_singles_valid |> should.be_true()

  // Verify multi instance actors have concurrency > 1
  let all_multis_valid =
    list.all(multis, fn(a: sa_plan_bridge.ActorDescriptor) {
      a.mode == sa_plan_bridge.MultiInstance && a.max_concurrency > 1
    })
  all_multis_valid |> should.be_true()
}

pub fn planning_task_claim_and_completion_test() {
  let plan = sa_plan_bridge.create_plan("plan-01", "uos/plan", "UOS Sa-Plan Execution")
  plan.id |> should.equal("plan-01")
  plan.name |> should.equal("uos/plan")

  let task = sa_plan_bridge.create_task("plan-01", "task-01", "uos/task", "Execute Task", [])
  task.state |> should.equal(sa_plan_bridge.Available)
  task.attempt |> should.equal(0)

  // Claim task
  let claim_res = sa_plan_bridge.claim_task(task, "worker-alpha", 60_000_000_000, 1_000_000_000)
  claim_res |> should.be_ok()
  let claimed_task = case claim_res {
    Ok(t) -> t
    Error(_) -> panic as "claim failed"
  }
  claimed_task.state |> should.equal(sa_plan_bridge.Executing)
  claimed_task.worker |> should.equal(Some("worker-alpha"))
  claimed_task.attempt |> should.equal(1)

  // Complete task
  let comp_res = sa_plan_bridge.complete_task(claimed_task, "worker-alpha", "success: green", 1_005_000_000)
  comp_res |> should.be_ok()
  let completed_task = case comp_res {
    Ok(t) -> t
    Error(_) -> panic as "complete failed"
  }
  completed_task.state |> should.equal(sa_plan_bridge.Completed)
  completed_task.result |> should.equal(Some("success: green"))
}

pub fn oban_job_queue_and_lock_test() {
  let job = sa_plan_bridge.enqueue_oban_job(101, "epoch_8", "PlanningWorker", "task_payload_101")
  job.id |> should.equal(101)
  job.state |> should.equal(sa_plan_bridge.JobAvailable)
  job.attempt |> should.equal(0)

  let lock_res = sa_plan_bridge.lock_oban_job(job)
  lock_res |> should.be_ok()
  let locked_job = case lock_res {
    Ok(j) -> j
    Error(_) -> panic as "lock failed"
  }
  locked_job.state |> should.equal(sa_plan_bridge.JobExecuting)
  locked_job.attempt |> should.equal(1)
}

pub fn temporal_durable_execution_and_replay_test() {
  let wf = sa_plan_bridge.start_temporal_workflow("wf-001", "SaPlanWorkflow")
  wf.id |> should.equal("wf-001")
  wf.state |> should.equal(sa_plan_bridge.WfRunning)
  list.length(wf.history) |> should.equal(0)

  // Activity 1: DB setup
  let #(wf_step1, res1) =
    sa_plan_bridge.execute_temporal_activity(wf, "act_db_init", fn() { "DB_INITIALIZED" }, 1_000_000)
  res1 |> should.equal("DB_INITIALIZED")
  list.length(wf_step1.history) |> should.equal(1)

  // Activity 1 Re-run (Simulating agent restart / replay): should return cached result
  let #(wf_step2, res1_cached) =
    sa_plan_bridge.execute_temporal_activity(
      wf_step1,
      "act_db_init",
      fn() { panic as "Violates exactly-once replay guarantee" },
      1_005_000,
    )
  res1_cached |> should.equal("DB_INITIALIZED")
  list.length(wf_step2.history) |> should.equal(1)

  // Complete workflow
  let final_wf = sa_plan_bridge.complete_temporal_workflow(wf_step2, "SUCCESS_COMPLETED")
  final_wf.state |> should.equal(sa_plan_bridge.WfCompleted)
  final_wf.result |> should.equal(Some("SUCCESS_COMPLETED"))
}

pub fn tcm_13d_vector_integrity_test() {
  let vec = sa_plan_bridge.create_default_13d_vector(3, "ExecutionPlane")
  vec.layer |> should.equal(3)
  vec.domain |> should.equal("ExecutionPlane")
  vec.trust |> should.equal(1)
  vec.safety_level |> should.equal("SIL-6")
  vec.governance_gate |> should.equal("G-CHECKLIST-PASS")
}

pub fn json_serialization_test() {
  let json_str = sa_plan_bridge.serialize_aspects_json()
  should.not_equal(json_str, "")
}

pub fn fractal_jidoka_enforcement_test() {
  // Authorized sa-plan execution succeeds
  sa_plan_bridge.enforce_fractal_jidoka("AgentAlpha", "task_execution", True)
  |> should.equal(Ok(Nil))

  // Unauthorized non-sa-plan execution triggers Jidoka Andon Halt
  let halt_res =
    sa_plan_bridge.enforce_fractal_jidoka("RogueAgent", "unledgered_task", False)

  case halt_res {
    Ok(_) -> panic as "Should have triggered Jidoka Andon Halt"
    Error(msg) -> {
      should.be_true(string.contains(msg, "Fractal Jidoka Andon Halt"))
      should.be_true(string.contains(msg, "SC-JIDOKA-001"))
    }
  }
}

pub fn tps_poka_yoke_validation_test() {
  // Valid task passes Poka-Yoke
  sa_plan_bridge.poka_yoke_validate_task(
    "plan-uos",
    "task-01",
    "compile",
    "Compile codebase",
  )
  |> should.equal(Ok(Nil))

  // Invalid task (empty plan) fails Poka-Yoke
  sa_plan_bridge.poka_yoke_validate_task(
    "",
    "task-01",
    "compile",
    "Compile codebase",
  )
  |> should.be_error

  // Valid Oban job passes Poka-Yoke
  sa_plan_bridge.poka_yoke_validate_job(
    "default",
    "DurableWorker",
    "{\"action\": \"run\"}",
  )
  |> should.equal(Ok(Nil))

  // Invalid Oban job (empty worker) fails Poka-Yoke
  sa_plan_bridge.poka_yoke_validate_job(
    "default",
    "",
    "{\"action\": \"run\"}",
  )
  |> should.be_error

  // Valid Temporal workflow passes Poka-Yoke
  sa_plan_bridge.poka_yoke_validate_workflow("wf-101", "OrderOrchestration")
  |> should.equal(Ok(Nil))

  // Invalid Temporal workflow (empty workflow type) fails Poka-Yoke
  sa_plan_bridge.poka_yoke_validate_workflow("wf-101", "")
  |> should.be_error
}

pub fn sa_plan_cli_status_query_test() {
  case sa_plan_bridge.query_sa_plan_status() {
    Ok(status) -> {
      should.be_true(string.contains(status, "sa-plan-pipeline"))
    }
    Error(err) -> {
      // In CI environments where binary might not be present at relative path, verify error is typed
      should.be_true(string.contains(err, "sa-plan"))
    }
  }
}

pub fn zenoh_jidoka_and_topic_test() {
  let topic = sa_plan_bridge.jidoka_andon_topic()
  topic |> should.equal("indrajaal/l0/const/jidoka/andon")

  let task_topic = sa_plan_bridge.sa_plan_task_topic("TASK-001", "claim")
  task_topic |> should.equal("indrajaal/planning/task/TASK-001/claim")

  let event =
    sa_plan_bridge.format_jidoka_andon_event(
      "agent-test",
      "shadow_task",
      "Unledgered execution detected",
      "2026-09-07T15:30:00.000000Z",
    )
  should.be_true(string.contains(event, "FRACTAL_JIDOKA_ANDON_HALT"))
  should.be_true(string.contains(event, "-32002"))
  should.be_true(string.contains(event, "SC-JIDOKA-001"))
}


