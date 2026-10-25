import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_job as job
import gleam/bit_array
import gleam/int
import gleam/string
import gleeunit/should

@external(erlang, "ecology_capability_ffi", "run_bounded")
fn run_bounded(
  path: String,
  args: List(String),
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

/// Real sa-plan against an isolated throwaway store, never the canonical one.
fn isolated_runner() -> job.Runner {
  let db =
    "/tmp/uos_tg_verify_job_test_"
    <> int.to_string(int.random(1_000_000_000))
    <> ".sqlite3"
  fn(args) {
    case
      run_bounded(
        "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/env",
        [
          "UOS_SA_PLAN_DB=" <> db,
          "/home/an/NAS-setup/uos/tools/sa-plan",
          ..args
        ],
        10_000,
      )
    {
      Ok(#(0, out)) -> {
        let assert Ok(text) = bit_array.to_string(out)
        Ok(string.trim(text))
      }
      Ok(#(code, _)) -> Error("exit " <> int.to_string(code))
      Error(e) -> Error(e)
    }
  }
}

fn binding(request: String) -> v.Binding {
  let assert Ok(p) =
    v.profile(
      "telegram-core",
      string.repeat("a", 40),
      string.repeat("b", 64),
      [v.Gate("build", string.repeat("c", 64), string.repeat("e", 64), 1000)],
      3000,
    )
  let assert Ok(b) = v.binding(p, request, 1)
  b
}

pub fn ensure_enqueues_once_and_replays_test() {
  let run = isolated_runner()
  let b = binding("bot999/inbox8001")
  let assert Ok(job.Enqueued(first)) =
    job.ensure(run, b, "claude-verify-worker")
  first.id |> should.equal(b.job_id)
  first.state |> should.equal("available")
  let assert Ok(job.AlreadyEnqueued(again)) =
    job.ensure(run, b, "claude-verify-worker")
  again.id |> should.equal(b.job_id)
}

pub fn ensure_refuses_same_job_for_another_worker_test() {
  let run = isolated_runner()
  let b = binding("bot999/inbox8002")
  let assert Ok(job.Enqueued(_)) = job.ensure(run, b, "worker-a")
  job.ensure(run, b, "worker-b") |> should.equal(Error("job_conflict"))
}

pub fn distinct_requests_get_distinct_jobs_test() {
  let run = isolated_runner()
  let a = binding("bot999/inbox8003")
  let b = binding("bot999/inbox8004")
  let assert Ok(job.Enqueued(ja)) = job.ensure(run, a, "w")
  let assert Ok(job.Enqueued(jb)) = job.ensure(run, b, "w")
  { ja.id != jb.id } |> should.be_true
}

pub fn unavailable_store_is_an_error_not_a_job_test() {
  let failing = fn(_args) { Error("sa_plan_unreachable") }
  let result = job.ensure(failing, binding("bot999/inbox8005"), "w")
  result
  |> should.equal(Error("job_list_failed:sa_plan_unreachable"))
}

pub fn refused_enqueue_without_a_stored_job_is_an_error_test() {
  // The store refuses the insert yet lists no such job: never report a job.
  let refusing = fn(args) {
    case args {
      ["job", "enqueue", ..] -> Error("exit 1")
      _ -> Ok("")
    }
  }
  job.ensure(refusing, binding("bot999/inbox8006"), "w")
  |> should.equal(Error("job_enqueue_failed:exit 1"))
}
