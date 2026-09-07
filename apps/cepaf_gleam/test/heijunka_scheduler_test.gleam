//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Heijunka Adaptive Scheduler Verification
//// =============================================================================

import cepaf_gleam/ha/heijunka_scheduler.{
  QueuedTask, complete_task, enqueue_task, init_queue, pull_batch, reclaim_expired,
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
  let #(q4, pulled) = pull_batch(q3, ctrl, "worker-1", 5000000, 1000000)

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
  let throttled_ctrl = update_controller(ctrl, -0.5) // Marginal -> batch size 1
  let #(q3, pulled) = pull_batch(q2, throttled_ctrl, "worker-1", 5000000, 1000000)

  list.length(pulled) |> should.equal(1)
  list.length(q3.pending_tasks) |> should.equal(1)
  list.length(q3.active_leases) |> should.equal(1)
}

pub fn pull_batch_halted_controller_test() {
  let q0 = init_queue(10)
  let t1 = QueuedTask("t1", "p1", 0, "{}")
  let assert Ok(q1) = enqueue_task(q0, t1)

  let ctrl = init_controller(1, 10)
  let halted_ctrl = update_controller(ctrl, 0.8) // Emergency halt -> batch size 0
  let #(q2, pulled) = pull_batch(q1, halted_ctrl, "worker-1", 5000000, 1000000)

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
  let #(q3, _pulled) = pull_batch(q2, ctrl, "worker-1", 1000, 1000)

  // Complete t1
  let q4 = complete_task(q3, "t1")
  list.length(q4.active_leases) |> should.equal(1)

  // At time 3000, t2 lease (expires at 2000) is expired -> reclaim
  let q5 = reclaim_expired(q4, 3000)
  list.length(q5.active_leases) |> should.equal(0)
  list.length(q5.pending_tasks) |> should.equal(1)
}
