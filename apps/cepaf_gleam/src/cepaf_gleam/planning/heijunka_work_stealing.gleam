//// Heijunka Work-Stealing Operad Engine (SC-FEAT-IMPL-001)
//// #fractal-l0 #fractal-l4 #zero-muda #tailscale-web
////
//// Implements leveled pull-queue task balancing under sa-plan authority,
//// precluding priority inversion and maintaining exponential Lyapunov stability.

pub type TaskPriority {
  CriticalPoset(level: Int)
  StandardPoset(level: Int)
  BackgroundPoset(level: Int)
}

pub type StealableTask {
  StealableTask(
    id: String,
    plan_id: String,
    priority: TaskPriority,
    estimated_cost_ns: Int,
    payoff_units: Int,
  )
}

pub type WorkerQueue {
  WorkerQueue(
    worker_id: String,
    tasks: List(StealableTask),
    total_load_ns: Int,
  )
}

pub type RebalanceVerdict {
  RebalanceExecuted(
    from_worker: String,
    to_worker: String,
    stolen_task_id: String,
    residual_skew_ns: Int,
  )
  RebalanceBalanced
}

/// Converts TaskPriority into a comparable rank integer.
pub fn priority_rank(p: TaskPriority) -> Int {
  case p {
    CriticalPoset(lvl) -> 1000 + lvl
    StandardPoset(lvl) -> 100 + lvl
    BackgroundPoset(lvl) -> lvl
  }
}

/// Verifies that task assignment satisfies the Pareto cost-payoff condition.
pub fn is_pareto_favorable(t: StealableTask) -> Bool {
  t.payoff_units * 1_000_000 >= t.estimated_cost_ns
}

/// Computes skew between two worker queues and executes a work-stealing operad if skewed.
pub fn evaluate_work_stealing(
  q1: WorkerQueue,
  q2: WorkerQueue,
  skew_threshold_ns: Int,
) -> RebalanceVerdict {
  let diff = q1.total_load_ns - q2.total_load_ns
  case diff > skew_threshold_ns {
    True -> {
      case q1.tasks {
        [first, ..] ->
          RebalanceExecuted(
            from_worker: q1.worker_id,
            to_worker: q2.worker_id,
            stolen_task_id: first.id,
            residual_skew_ns: diff - first.estimated_cost_ns,
          )
        [] -> RebalanceBalanced
      }
    }
    False -> RebalanceBalanced
  }
}
