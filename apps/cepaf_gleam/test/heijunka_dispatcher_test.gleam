import cepaf_gleam/ha/heijunka_dispatcher.{
  AspectFormal, AspectInterface, AspectKernel, HeijunkaState,
  WorkerAGY, WorkerClaude, WorkerCodex, complete_task, enqueue_task,
  init_dispatcher, preferred_worker, pull_next_task, worker_to_string,
}
import gleam/option.{Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn worker_string_and_affinity_test() {
  worker_to_string(WorkerAGY) |> should.equal("AGY")
  worker_to_string(WorkerClaude) |> should.equal("Claude")
  worker_to_string(WorkerCodex) |> should.equal("Codex")

  preferred_worker(AspectFormal) |> should.equal(WorkerAGY)
  preferred_worker(AspectInterface) |> should.equal(WorkerClaude)
  preferred_worker(AspectKernel) |> should.equal(WorkerCodex)
}

pub fn enqueue_and_pull_lease_test() {
  let s0 = init_dispatcher()
  let s1 = enqueue_task(s0, "task-1", "Formal verification", AspectFormal, 10)
  s1.queue_backlog |> should.equal(1)
  { s1.lyapunov_v >. 0.0 } |> should.be_true

  // Reject lease < 1320s
  let res_short = pull_next_task(s1, WorkerAGY, 1_000_000, 500)
  res_short |> should.be_error

  // Accept lease >= 1320s
  let res_ok = pull_next_task(s1, WorkerAGY, 1_000_000, 1320)
  case res_ok {
    Ok(#(s2, task)) -> {
      task.id |> should.equal("task-1")
      task.claimed_by |> should.equal(Some(WorkerAGY))
      s2.pull_epoch |> should.equal(2)

      // Complete task
      let s3 = complete_task(s2, "task-1")
      s3.queue_backlog |> should.equal(0)
      s3.lyapunov_v |> should.equal(0.0)
    }
    Error(_) -> should.fail()
  }
}

pub fn andon_halt_blocks_pull_test() {
  let s0 = init_dispatcher()
  let s_halt = HeijunkaState(..s0, andon_halted: True)
  let s1 = enqueue_task(s_halt, "t-halt", "Blocked", AspectFormal, 5)
  let pull_res = pull_next_task(s1, WorkerAGY, 1000, 1320)
  pull_res |> should.be_error
}
