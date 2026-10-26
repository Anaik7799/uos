//// Canonical Sa-plan job for one reserved /verify request. The job id is the
//// binding's job_id, a digest over the inbox request and the profile digest,
//// so a request can map to at most one job. Enqueue is idempotent: when the id
//// already exists, the existing row is accepted only if its queue and worker
//// match; anything else is a conflict. Creating a job grants no execution: a
//// worker must still claim it through Sa-plan and recheck the loaded profile.

import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_reservation as reservation
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const queue = "telegram-verify"

pub type Job {
  Job(id: String, worker: String, state: String, attempt: String)
}

pub type Ensured {
  /// This call enqueued the job.
  Enqueued(Job)
  /// The job already existed with the same identity (idempotent replay).
  AlreadyEnqueued(Job)
}

/// Runs one literal sa-plan argv and returns its trimmed stdout.
pub type Runner =
  fn(List(String)) -> Result(String, String)

fn job_decoder() {
  use id <- decode.field("id", decode.string)
  use q <- decode.field("queue", decode.string)
  use worker <- decode.field("worker", decode.string)
  use state <- decode.field("state", decode.string)
  use attempt <- decode.field("attempt", decode.string)
  decode.success(#(q, Job(id, worker, state, attempt)))
}

fn parse_list(output: String) -> Result(List(#(String, Job)), String) {
  output
  |> string.split("\n")
  |> list.filter(fn(line) { string.starts_with(line, "{") })
  |> list.try_map(fn(line) {
    json.parse(line, job_decoder())
    |> result.replace_error("job_list_malformed")
  })
}

pub fn lookup(run: Runner, job_id: String) -> Result(Job, String) {
  use output <- result.try(
    run(["--format", "json", "job", "list", queue])
    |> result.map_error(fn(e) { "job_list_failed:" <> e }),
  )
  use rows <- result.try(parse_list(output))
  case list.filter(rows, fn(row) { { row.1 }.id == job_id }) {
    [#(q, job)] if q == queue -> Ok(job)
    [] -> Error("job_absent")
    _ -> Error("job_identity_ambiguous")
  }
}

/// Enqueues the job for a reserved binding exactly once.
pub fn ensure(
  run: Runner,
  b: v.Binding,
  worker: String,
) -> Result(Ensured, String) {
  let args = reservation.encode(b)
  case run(["job", "enqueue", b.job_id, b.job_id, queue, worker, args, "1"]) {
    Ok(_) -> lookup(run, b.job_id) |> result.map(Enqueued)
    Error(enqueue_error) ->
      case lookup(run, b.job_id) {
        Ok(job) if job.worker == worker -> Ok(AlreadyEnqueued(job))
        Ok(_) -> Error("job_conflict")
        Error("job_absent") -> Error("job_enqueue_failed:" <> enqueue_error)
        Error(e) -> Error(e)
      }
  }
}
