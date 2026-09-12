// =============================================================================
// maut_pull_queue_test.gleam — Multi-Attribute Utility Theory Scheduler Tests
// STAMP: SC-SIL6-001, SC-JIDOKA-001, SC-SA-PLAN-001
// =============================================================================

import cepaf_gleam/ha/maut_pull_queue.{
  CandidateTask, compute_utility, default_weights, pull_highest_utility_task,
  score_candidate_queue,
}
import gleeunit/should

pub fn compute_utility_nominal_test() {
  let weights = default_weights()
  let task =
    CandidateTask(
      task_id: "task-alpha",
      plan_id: "plan-1",
      priority: 8.0,
      dependency_readiness: 10.0,
      fmea_risk: 2.0,
      resource_cost: 1.0,
      required_affinity: "L0-fable",
    )
  // positive = (8.0 * 0.40) + (10.0 * 0.30) = 3.2 + 3.0 = 6.2
  // penalty = (2.0 * 0.20) + (1.0 * 0.10) = 0.4 + 0.1 = 0.5
  // utility = 6.2 - 0.5 = 5.7
  let u = compute_utility(task, weights)
  should.be_true(u >. 5.6 && u <. 5.8)
}

pub fn blocked_dependency_utility_zero_test() {
  let weights = default_weights()
  let task =
    CandidateTask(
      task_id: "task-blocked",
      plan_id: "plan-1",
      priority: 10.0,
      dependency_readiness: 0.0,
      fmea_risk: 1.0,
      resource_cost: 1.0,
      required_affinity: "any",
    )
  let u = compute_utility(task, weights)
  u |> should.equal(0.0)
}

pub fn pareto_frontier_tagging_test() {
  let weights = default_weights()
  let dominant =
    CandidateTask(
      task_id: "dominant",
      plan_id: "plan-1",
      priority: 9.0,
      dependency_readiness: 10.0,
      fmea_risk: 1.0,
      resource_cost: 1.0,
      required_affinity: "any",
    )
  let dominated =
    CandidateTask(
      task_id: "dominated",
      plan_id: "plan-1",
      priority: 4.0,
      dependency_readiness: 5.0,
      fmea_risk: 8.0,
      resource_cost: 5.0,
      required_affinity: "any",
    )
  let queue = [dominant, dominated]
  let scored = score_candidate_queue(queue, weights)
  case scored {
    [first, second] -> {
      first.is_pareto_optimal |> should.be_true
      second.is_pareto_optimal |> should.be_false
    }
    _ -> should.fail()
  }
}

pub fn pull_highest_utility_matching_affinity_test() {
  let weights = default_weights()
  let task1 =
    CandidateTask(
      task_id: "task-claude-high",
      plan_id: "plan-1",
      priority: 9.0,
      dependency_readiness: 10.0,
      fmea_risk: 2.0,
      resource_cost: 1.0,
      required_affinity: "L0-fable",
    )
  let task2 =
    CandidateTask(
      task_id: "task-codex-mid",
      plan_id: "plan-1",
      priority: 6.0,
      dependency_readiness: 8.0,
      fmea_risk: 3.0,
      resource_cost: 2.0,
      required_affinity: "L0-codex-gpt-6-astra",
    )
  let queue = [task1, task2]

  // Pull for L0-fable gets task1
  let assert Ok(best_fable) = pull_highest_utility_task(queue, "L0-fable", weights)
  best_fable.task.task_id |> should.equal("task-claude-high")

  // Pull for L0-codex gets task2
  let assert Ok(best_codex) = pull_highest_utility_task(queue, "L0-codex-gpt-6-astra", weights)
  best_codex.task.task_id |> should.equal("task-codex-mid")
}
