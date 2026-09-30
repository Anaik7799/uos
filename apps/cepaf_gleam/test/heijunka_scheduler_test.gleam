//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Heijunka Adaptive Scheduler Verification
//// =============================================================================

import cepaf_gleam/ha/heijunka_scheduler.{
  HeijunkaQueue, QueuedTask, TaskLease, complete_task, enqueue_task, init_queue,
  pull_batch, reclaim_expired,
}
import cepaf_gleam/ha/lyapunov_controller.{init_controller, update_controller}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn enqueue_priority_ordering_test() {
  let q0 = init_queue(10)
  let t1 = QueuedTask("t1", "p1", 2, "{}")
  let t2 = QueuedTask("t2", "p1", 0, "{}")
  let t3 = QueuedTask("t3", "p1", 1, "{}")

  let assert Ok(q1) = enqueue_task(q0, t1)
  let assert Ok(q2) = enqueue_task(q1, t2)
  let assert Ok(q3) = enqueue_task(q2, t3)

  let ids = list.map(q3.pending_tasks, fn(t) { t.task_id })
  ids |> should.equal(["t2", "t3", "t1"])
}

pub fn pull_batch_nominal_controller_test() {
  let q0 = init_queue(10)
  let t1 = QueuedTask("t1", "p1", 0, "{}")
  let t2 = QueuedTask("t2", "p1", 0, "{}")
  let t3 = QueuedTask("t3", "p1", 0, "{}")

  let assert Ok(q1) = enqueue_task(q0, t1)
  let assert Ok(q2) = enqueue_task(q1, t2)
  let assert Ok(q3) = enqueue_task(q2, t3)

  let ctrl = init_controller(1, 10)
  let #(q4, pulled) = pull_batch(q3, ctrl, "worker-1", 1, 5_000_000, 1_000_000)

  // ctrl concurrency = 10 -> batch size = max(1, 10 / 2) = 5 -> takes all 3
  list.length(pulled) |> should.equal(3)
  list.length(q4.pending_tasks) |> should.equal(0)
  list.length(q4.active_leases) |> should.equal(3)
}

pub fn pull_batch_throttled_controller_test() {
  let q0 = init_queue(10)
  let t1 = QueuedTask("t1", "p1", 0, "{}")
  let t2 = QueuedTask("t2", "p1", 0, "{}")

  let assert Ok(q1) = enqueue_task(q0, t1)
  let assert Ok(q2) = enqueue_task(q1, t2)

  let ctrl = init_controller(1, 10)
  let throttled_ctrl = update_controller(ctrl, -0.5)
  // Marginal -> batch size 1
  let #(q3, pulled) =
    pull_batch(q2, throttled_ctrl, "worker-1", 1, 5_000_000, 1_000_000)

  list.length(pulled) |> should.equal(1)
  list.length(q3.pending_tasks) |> should.equal(1)
  list.length(q3.active_leases) |> should.equal(1)
}

pub fn pull_batch_respects_remaining_concurrency_after_prior_leases_test() {
  let q0 = init_queue(10)
  let task = QueuedTask("t", "plan", 0, "payload")
  let assert Ok(q1) = enqueue_task(q0, task)
  let assert Ok(q2) = enqueue_task(q1, QueuedTask("t2", "plan", 0, "payload"))
  let assert Ok(q3) = enqueue_task(q2, QueuedTask("t3", "plan", 0, "payload"))
  let assert Ok(q4) = enqueue_task(q3, QueuedTask("t4", "plan", 0, "payload"))
  let assert Ok(q5) = enqueue_task(q4, QueuedTask("t5", "plan", 0, "payload"))
  let assert Ok(q6) = enqueue_task(q5, QueuedTask("t6", "plan", 0, "payload"))

  let ctrl = init_controller(1, 4)
  let #(q7, _) = pull_batch(q6, ctrl, "worker-1", 1, 5000, 1000)
  let #(q8, _) = pull_batch(q7, ctrl, "worker-1", 1, 5000, 1001)
  let #(q9, third_pull) = pull_batch(q8, ctrl, "worker-1", 1, 5000, 1002)

  // A third pull must not exceed the controller's four concurrent leases.
  third_pull |> should.equal([])
  list.length(q9.active_leases) |> should.equal(4)
  list.length(q9.pending_tasks) |> should.equal(2)
}

pub fn pull_batch_halted_controller_test() {
  let q0 = init_queue(10)
  let t1 = QueuedTask("t1", "p1", 0, "{}")
  let assert Ok(q1) = enqueue_task(q0, t1)

  let ctrl = init_controller(1, 10)
  let halted_ctrl = update_controller(ctrl, 0.8)
  // Emergency halt -> batch size 0
  let #(q2, pulled) =
    pull_batch(q1, halted_ctrl, "worker-1", 1, 5_000_000, 1_000_000)

  list.length(pulled) |> should.equal(0)
  list.length(q2.pending_tasks) |> should.equal(1)
  list.length(q2.active_leases) |> should.equal(0)
}

pub fn task_completion_and_reclaim_test() {
  let q0 = init_queue(10)
  let t1 = QueuedTask("t1", "p1", 0, "{}")
  let t2 = QueuedTask("t2", "p1", 0, "{}")
  let assert Ok(q1) = enqueue_task(q0, t1)
  let assert Ok(q2) = enqueue_task(q1, t2)

  let ctrl = init_controller(1, 10)
  let #(q3, _pulled) = pull_batch(q2, ctrl, "worker-1", 1, 1000, 1000)

  // Complete t1
  let q4 = complete_task(q3, "t1", "p1", "worker-1", 1)
  list.length(q4.active_leases) |> should.equal(1)

  // At time 3000, t2 lease (expires at 2000) is expired -> reclaim
  let q5 = reclaim_expired(q4, 3000)
  list.length(q5.active_leases) |> should.equal(0)
  list.length(q5.pending_tasks) |> should.equal(1)
}

pub fn reclaim_expired_preserves_original_task_identity_test() {
  let q0 = init_queue(10)
  let task =
    QueuedTask("task-42", "plan-origin", 17, "{\"intent\":\"preserve\"}")
  let assert Ok(q1) = enqueue_task(q0, task)
  let ctrl = init_controller(1, 4)
  let #(q2, _) = pull_batch(q1, ctrl, "worker-1", 1, 1000, 1000)

  let reclaimed = reclaim_expired(q2, 2001)

  // Reclaim returns the original task, including its plan, priority, and payload.
  reclaimed.pending_tasks |> should.equal([task])
}

pub fn reclaim_expired_keeps_pending_depth_bounded_test() {
  let q0 = init_queue(1)
  let expired_task = QueuedTask("expired", "plan", 0, "payload")
  let waiting_task = QueuedTask("waiting", "plan", 0, "payload")
  let assert Ok(q1) = enqueue_task(q0, expired_task)
  let ctrl = init_controller(1, 1)
  let #(q2, _) = pull_batch(q1, ctrl, "worker-1", 1, 1000, 1000)
  let assert Ok(q3) = enqueue_task(q2, waiting_task)

  let reclaimed = reclaim_expired(q3, 2001)

  // An expired lease cannot make the visible pending queue exceed its capacity.
  list.length(reclaimed.pending_tasks) |> should.equal(1)
  list.length(reclaimed.deferred_tasks) |> should.equal(1)

  // Deferred retained work applies backpressure to further intake.
  enqueue_task(reclaimed, QueuedTask("new-work", "plan", 0, "payload"))
  |> should.equal(Error("Heijunka queue depth exceeded: max 1"))
}

pub fn complete_task_does_not_release_another_workers_lease_test() {
  let task = QueuedTask("same-task", "plan", 0, "payload")
  let queue =
    HeijunkaQueue(
      pending_tasks: [],
      deferred_tasks: [],
      active_leases: [
        TaskLease(task, "worker-a", 1, 1000, 2000),
        TaskLease(task, "worker-a", 2, 1000, 2000),
        TaskLease(task, "worker-b", 1, 1000, 2000),
      ],
      max_queue_depth: 2,
    )

  let completed = complete_task(queue, "same-task", "plan", "worker-a", 1)

  // Completion must match the lease's worker and attempt, not just the task ID.
  list.length(completed.active_leases) |> should.equal(2)
}

pub fn complete_task_does_not_release_another_plans_lease_test() {
  let plan_a = QueuedTask("same-task", "plan-a", 0, "payload")
  let plan_b = QueuedTask("same-task", "plan-b", 0, "payload")
  let queue =
    HeijunkaQueue(
      pending_tasks: [],
      deferred_tasks: [],
      active_leases: [
        TaskLease(plan_a, "worker-a", 1, 1000, 2000),
        TaskLease(plan_b, "worker-a", 1, 1000, 2000),
      ],
      max_queue_depth: 2,
    )

  let completed = complete_task(queue, "same-task", "plan-a", "worker-a", 1)

  // A completion key must include plan identity as well as task, worker, and attempt.
  list.length(completed.active_leases) |> should.equal(1)
}

pub fn pull_batch_drains_deferred_reclaims_test() {
  let q0 = init_queue(1)
  let expired_task = QueuedTask("expired", "plan", 0, "payload")
  let waiting_task = QueuedTask("waiting", "plan", 0, "payload")
  let assert Ok(q1) = enqueue_task(q0, expired_task)
  let ctrl = init_controller(1, 1)
  let #(q2, _) = pull_batch(q1, ctrl, "worker-1", 1, 1000, 1000)
  let assert Ok(q3) = enqueue_task(q2, waiting_task)
  let reclaimed = reclaim_expired(q3, 2001)

  let #(drained, pulled) =
    pull_batch(reclaimed, ctrl, "worker-2", 1, 1000, 2002)

  list.length(pulled) |> should.equal(1)
  list.length(drained.pending_tasks) |> should.equal(1)
  list.length(drained.deferred_tasks) |> should.equal(0)
}
