//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/heijunka_scheduler</module>
////     <fsharp-lineage>N/A — Pure Gleam Autonomous Heijunka Task Pull-Queue Scheduler</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <layer>L5_COGNITIVE</layer>
////     <cross-layer-dependencies>
////       <dep layer="L0_CONSTITUTIONAL">cepaf_gleam/ha/lyapunov_controller</dep>
////     </cross-layer-dependencies>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-MATH-001, SC-CTRL-001, SC-JIDOKA-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="heijunka-leveling">Task pulling dynamically adapts to Lyapunov stability exponent</property>
////     <property name="lease-finiteness">Every pulled task receives a strictly monotonic expiration epoch</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/ha/lyapunov_controller.{
  type LyapunovController, compute_batch_size,
}
import gleam/int
import gleam/list

/// Queued task item with priority and metadata.
pub type QueuedTask {
  QueuedTask(
    task_id: String,
    plan_id: String,
    priority: Int,
    payload_json: String,
  )
}

/// Active task execution lease.
pub type TaskLease {
  TaskLease(
    task: QueuedTask,
    worker_id: String,
    attempt: Int,
    claimed_at_us: Int,
    lease_until_us: Int,
  )
}

/// Structured Heijunka leveled pull queue state.
pub type HeijunkaQueue {
  HeijunkaQueue(
    pending_tasks: List(QueuedTask),
    deferred_tasks: List(QueuedTask),
    active_leases: List(TaskLease),
    max_queue_depth: Int,
  )
}

/// Initialize an empty Heijunka leveled pull queue.
pub fn init_queue(max_depth: Int) -> HeijunkaQueue {
  HeijunkaQueue(
    pending_tasks: [],
    deferred_tasks: [],
    active_leases: [],
    max_queue_depth: max_depth,
  )
}

/// Enqueue a task into the pending pull queue respecting priority ordering (0 = highest).
pub fn enqueue_task(
  queue: HeijunkaQueue,
  task: QueuedTask,
) -> Result(HeijunkaQueue, String) {
  case queue_load(queue) >= queue.max_queue_depth {
    True ->
      Error(
        "Heijunka queue depth exceeded: max "
        <> int.to_string(queue.max_queue_depth),
      )
    False -> {
      let sorted_tasks =
        [task, ..queue.pending_tasks]
        |> list.sort(fn(a, b) { int.compare(a.priority, b.priority) })
      Ok(HeijunkaQueue(..queue, pending_tasks: sorted_tasks))
    }
  }
}

/// Pull a leveled batch of tasks dynamically bounded by the Lyapunov Controller.
pub fn pull_batch(
  queue: HeijunkaQueue,
  ctrl: LyapunovController,
  worker_id: String,
  attempt: Int,
  lease_duration_us: Int,
  now_us: Int,
) -> #(HeijunkaQueue, List(QueuedTask)) {
  let remaining_concurrency =
    int.max(0, ctrl.concurrency_limit - list.length(queue.active_leases))
  let allowed_batch = int.min(compute_batch_size(ctrl), remaining_concurrency)
  case allowed_batch <= 0 {
    True -> #(queue, [])
    False -> {
      let available_tasks =
        list.append(queue.pending_tasks, queue.deferred_tasks)
      let taken = list.take(available_tasks, allowed_batch)
      let remaining = list.drop(available_tasks, allowed_batch)
      let #(pending_tasks, deferred_tasks) =
        list.split(remaining, queue.max_queue_depth)
      let new_leases =
        list.map(taken, fn(t) {
          TaskLease(
            task: t,
            worker_id: worker_id,
            attempt: attempt,
            claimed_at_us: now_us,
            lease_until_us: now_us + lease_duration_us,
          )
        })

      let updated_queue =
        HeijunkaQueue(
          ..queue,
          pending_tasks: pending_tasks,
          deferred_tasks: deferred_tasks,
          active_leases: list.append(queue.active_leases, new_leases),
        )
      #(updated_queue, taken)
    }
  }
}

/// Release or complete a task lease.
pub fn complete_task(
  queue: HeijunkaQueue,
  task_id: String,
  plan_id: String,
  worker_id: String,
  attempt: Int,
) -> HeijunkaQueue {
  let remaining_leases =
    list.filter(queue.active_leases, fn(l) {
      l.task.task_id != task_id
      || l.task.plan_id != plan_id
      || l.worker_id != worker_id
      || l.attempt != attempt
    })
  HeijunkaQueue(..queue, active_leases: remaining_leases)
}

/// Reclaim expired leases back into the pending task list.
pub fn reclaim_expired(queue: HeijunkaQueue, now_us: Int) -> HeijunkaQueue {
  let #(expired, active) =
    list.partition(queue.active_leases, fn(l) { now_us > l.lease_until_us })

  let reclaimed_tasks = list.map(expired, fn(l) { l.task })
  let retained_tasks =
    list.append(
      reclaimed_tasks,
      list.append(queue.pending_tasks, queue.deferred_tasks),
    )
  let #(pending_tasks, deferred_tasks) =
    list.split(retained_tasks, queue.max_queue_depth)

  HeijunkaQueue(
    pending_tasks: pending_tasks,
    deferred_tasks: deferred_tasks,
    active_leases: active,
    max_queue_depth: queue.max_queue_depth,
  )
}

fn queue_load(queue: HeijunkaQueue) -> Int {
  list.length(queue.pending_tasks) + list.length(queue.deferred_tasks)
}
