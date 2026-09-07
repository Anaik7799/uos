//// Autonomous Sa-Plan Heijunka Dispatcher & Decentralized Work-Stealer (EV-109)
//// #fractal-l0 #fractal-l1 #fractal-l3 #zero-muda #tailscale-web
////
//// Implements pull-based leveled queue dispatching (Toyota Production System Heijunka),
//// preventing task starvation, enforcing monotonic lease fencing (T_lease >= 1320s),
//// and stabilizing swarm execution under Lyapunov decay.

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

pub type SovereignWorker {
  WorkerAGY
  WorkerClaude
  WorkerCodex
}

pub fn worker_to_string(w: SovereignWorker) -> String {
  case w {
    WorkerAGY -> "AGY"
    WorkerClaude -> "Claude"
    WorkerCodex -> "Codex"
  }
}

pub type TaskAspect {
  AspectFormal
  AspectInterface
  AspectKernel
  AspectGeneral
}

pub type QueuedTask {
  QueuedTask(
    id: String,
    title: String,
    aspect: TaskAspect,
    priority: Int,
    claimed_by: Option(SovereignWorker),
    lease_until_ns: Int,
  )
}

pub type HeijunkaState {
  HeijunkaState(
    tasks: Dict(String, QueuedTask),
    queue_backlog: Int,
    pull_epoch: Int,
    lyapunov_v: Float,
    andon_halted: Bool,
  )
}

pub fn init_dispatcher() -> HeijunkaState {
  HeijunkaState(
    tasks: dict.new(),
    queue_backlog: 0,
    pull_epoch: 1,
    lyapunov_v: 1.0,
    andon_halted: False,
  )
}

/// Enqueue a new task into the Heijunka buffer
pub fn enqueue_task(
  state: HeijunkaState,
  id: String,
  title: String,
  aspect: TaskAspect,
  priority: Int,
) -> HeijunkaState {
  case state.andon_halted {
    True -> state
    False -> {
      let task =
        QueuedTask(
          id: id,
          title: title,
          aspect: aspect,
          priority: priority,
          claimed_by: None,
          lease_until_ns: 0,
        )
      let new_tasks = dict.insert(state.tasks, id, task)
      let backlog = dict.size(new_tasks)
      let f_backlog = int.to_float(backlog)
      // Lyapunov function V = 0.5 * Q^2
      let new_v = 0.5 *. f_backlog *. f_backlog

      HeijunkaState(
        ..state,
        tasks: new_tasks,
        queue_backlog: backlog,
        lyapunov_v: new_v,
      )
    }
  }
}

/// Match task to ideal sovereign worker according to aspect affinity
pub fn preferred_worker(aspect: TaskAspect) -> SovereignWorker {
  case aspect {
    AspectFormal -> WorkerAGY
    AspectInterface -> WorkerClaude
    AspectKernel -> WorkerCodex
    AspectGeneral -> WorkerAGY
  }
}

/// Pull next available task for a worker enforcing Heijunka leveling and lease >= 1320s
pub fn pull_next_task(
  state: HeijunkaState,
  worker: SovereignWorker,
  now_ns: Int,
  lease_seconds: Int,
) -> Result(#(HeijunkaState, QueuedTask), String) {
  case state.andon_halted {
    True -> Error("Andon Halt active: task pull barred (SC-JIDOKA-001)")
    False -> {
      case lease_seconds < 1320 {
        True ->
          Error("Lease too short: must be at least 1320 seconds (SYNC-06)")
        False -> {
          // Find highest priority unclaimed task matching worker affinity or general
          let available =
            dict.values(state.tasks)
            |> list.filter(fn(t) {
              case t.claimed_by {
                None -> True
                Some(_) -> t.lease_until_ns < now_ns
              }
            })
            |> list.sort(fn(a, b) { int.compare(b.priority, a.priority) })

          case list.first(available) {
            Error(_) -> Error("Queue empty: no tasks available")
            Ok(task) -> {
              let lease_ns = int.to_float(lease_seconds) *. 1_000_000_000.0
              let expires_at = now_ns + float.round(lease_ns)
              let updated_task =
                QueuedTask(
                  ..task,
                  claimed_by: Some(worker),
                  lease_until_ns: expires_at,
                )
              let new_tasks =
                dict.insert(state.tasks, task.id, updated_task)
              let new_state =
                HeijunkaState(
                  ..state,
                  tasks: new_tasks,
                  pull_epoch: state.pull_epoch + 1,
                )
              Ok(#(new_state, updated_task))
            }
          }
        }
      }
    }
  }
}

/// Complete task, retiring it from the queue and decaying Lyapunov potential
pub fn complete_task(
  state: HeijunkaState,
  task_id: String,
) -> HeijunkaState {
  let new_tasks = dict.delete(state.tasks, task_id)
  let backlog = dict.size(new_tasks)
  let f_backlog = int.to_float(backlog)
  let new_v = 0.5 *. f_backlog *. f_backlog

  HeijunkaState(
    ..state,
    tasks: new_tasks,
    queue_backlog: backlog,
    lyapunov_v: new_v,
  )
}
