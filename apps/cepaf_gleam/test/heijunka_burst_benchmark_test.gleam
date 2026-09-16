//// =============================================================================
//// [UOS-HEIJUNKA-BURST] High-Burst Benchmark & Work-Stealing Operad Verification
//// =============================================================================

import cepaf_gleam/planning/heijunka_work_stealing.{
  type StealableTask, BackgroundPoset, BatchRebalanceExecuted, CriticalPoset,
  StandardPoset, StealableTask, WorkerQueue, compute_cluster_skew,
  evaluate_burst_work_stealing, is_pareto_favorable, run_burst_benchmark,
}
import gleam/int
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn int_range(start: Int, stop: Int) -> List(Int) {
  case start > stop {
    True -> []
    False -> [start, ..int_range(start + 1, stop)]
  }
}

fn make_task(id_num: Int, prio_mod: Int, cost_ns: Int) -> StealableTask {
  let prio = case prio_mod % 3 {
    0 -> CriticalPoset(level: prio_mod)
    1 -> StandardPoset(level: prio_mod)
    _ -> BackgroundPoset(level: prio_mod)
  }
  let id = "task-" <> int.to_string(id_num)
  let payoff = cost_ns / 500_000 + 1
  StealableTask(
    id: id,
    plan_id: "plan-burst",
    priority: prio,
    estimated_cost_ns: cost_ns,
    payoff_units: payoff,
  )
}

fn generate_tasks(count: Int, base_cost: Int) -> List(StealableTask) {
  int_range(1, count)
  |> list.map(fn(i) { make_task(i, i, base_cost + { i % 10 } * 1000) })
}

pub fn burst_batch_stealing_direct_test() {
  let tasks = generate_tasks(20, 100_000)
  let q1 =
    WorkerQueue(
      worker_id: "worker-overloaded",
      tasks: tasks,
      total_load_ns: 20 * 100_000,
    )
  let q2 = WorkerQueue(worker_id: "worker-idle", tasks: [], total_load_ns: 0)

  let verdict = evaluate_burst_work_stealing(q1, q2, 200_000, 8)
  case verdict {
    BatchRebalanceExecuted(
      from,
      to,
      stolen,
      stolen_count,
      transferred_load,
      residual_skew,
    ) -> {
      from |> should.equal("worker-overloaded")
      to |> should.equal("worker-idle")
      stolen_count |> should.equal(8)
      list.length(stolen) |> should.equal(8)
      { transferred_load > 0 } |> should.be_true
      { residual_skew > 0 } |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn burst_100_tasks_test() {
  let tasks = generate_tasks(100, 50_000)
  let total_load =
    list.fold(tasks, 0, fn(acc, t) { acc + t.estimated_cost_ns })
  let q1 =
    WorkerQueue(
      worker_id: "worker-1",
      tasks: tasks,
      total_load_ns: total_load,
    )
  let q2 = WorkerQueue(worker_id: "worker-2", tasks: [], total_load_ns: 0)
  let q3 = WorkerQueue(worker_id: "worker-3", tasks: [], total_load_ns: 0)
  let q4 = WorkerQueue(worker_id: "worker-4", tasks: [], total_load_ns: 0)

  let queues = [q1, q2, q3, q4]
  let initial_skew = compute_cluster_skew(queues)
  initial_skew |> should.equal(total_load)

  let report = run_burst_benchmark(queues, 50_000, 15, 20)

  report.total_tasks |> should.equal(100)
  { report.total_thefts > 0 } |> should.be_true
  { report.final_skew_ns > 0 } |> should.be_true
  { report.final_skew_ns < report.initial_skew_ns } |> should.be_true
  // Skew contraction should exceed 40%
  { report.contraction_ratio >. 0.40 } |> should.be_true
}

pub fn burst_500_tasks_test() {
  let tasks = generate_tasks(500, 20_000)
  let total_load =
    list.fold(tasks, 0, fn(acc, t) { acc + t.estimated_cost_ns })

  // 1 overloaded worker, 7 idle workers
  let q1 =
    WorkerQueue(
      worker_id: "worker-1",
      tasks: tasks,
      total_load_ns: total_load,
    )
  let idle_workers =
    int_range(2, 8)
    |> list.map(fn(i) {
      WorkerQueue(
        worker_id: "worker-" <> int.to_string(i),
        tasks: [],
        total_load_ns: 0,
      )
    })

  let queues = [q1, ..idle_workers]
  let report = run_burst_benchmark(queues, 50_000, 30, 40)

  report.total_tasks |> should.equal(500)
  { report.total_thefts > 0 } |> should.be_true
  { report.final_skew_ns < report.initial_skew_ns } |> should.be_true
  // Skew contraction under high burst should exceed 50%
  { report.contraction_ratio >. 0.50 } |> should.be_true
}

pub fn burst_1000_tasks_test() {
  let tasks = generate_tasks(1000, 10_000)
  let total_load =
    list.fold(tasks, 0, fn(acc, t) { acc + t.estimated_cost_ns })

  // 1 heavily overloaded worker, 15 idle workers (total 16 workers)
  let q1 =
    WorkerQueue(
      worker_id: "worker-1",
      tasks: tasks,
      total_load_ns: total_load,
    )
  let idle_workers =
    int_range(2, 16)
    |> list.map(fn(i) {
      WorkerQueue(
        worker_id: "worker-" <> int.to_string(i),
        tasks: [],
        total_load_ns: 0,
      )
    })

  let queues = [q1, ..idle_workers]
  let report = run_burst_benchmark(queues, 40_000, 40, 60)

  report.total_tasks |> should.equal(1000)
  { report.total_thefts > 0 } |> should.be_true
  { report.final_skew_ns < report.initial_skew_ns } |> should.be_true
  // Skew contraction under massive burst should exceed 60%
  { report.contraction_ratio >. 0.60 } |> should.be_true
}

pub fn pareto_condition_invariance_test() {
  let tasks = generate_tasks(50, 100_000)
  list.each(tasks, fn(t) {
    is_pareto_favorable(t) |> should.be_true
  })
}
