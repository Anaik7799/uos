open Core

(** Oban-style robust job processing queue backed by SQLite.
    Provides at-least-once execution guarantees, retries, and scheduled execution. *)

type job_state =
  | Available
  | Executing
  | Retry
  | Completed
  | Discarded
  [@@deriving sexp, compare]

type job = {
  id: int;
  queue: string;
  worker: string;
  args: string; (* JSON payload *)
  attempt: int;
  max_attempts: int;
  state: job_state;
  scheduled_at: float;
  inserted_at: float;
} [@@deriving sexp]

let job_state_to_string = function
  | Available -> "available"
  | Executing -> "executing"
  | Retry -> "retry"
  | Completed -> "completed"
  | Discarded -> "discarded"

(** Simulates Oban.insert/1 - enqueues a job transactionally *)
let insert ~queue ~worker ~args ~max_attempts =
  let now = Time_ns.now () |> Time_ns.to_span_since_epoch |> Time_ns.Span.to_sec in
  {
    id = Random.int 1_000_000;
    queue;
    worker;
    args;
    attempt = 0;
    max_attempts;
    state = Available;
    scheduled_at = now;
    inserted_at = now;
  }

(** Simulates Oban's poll/dispatch cycle.
    In a real implementation, this runs a SQLite 'UPDATE ... RETURNING' 
    to atomically lock a job. *)
let fetch_and_lock_next_job (jobs : job list) ~queue =
  let now = Time_ns.now () |> Time_ns.to_span_since_epoch |> Time_ns.Span.to_sec in
  List.find jobs ~f:(fun j -> 
    String.equal j.queue queue 
    && Float.(j.scheduled_at <= now)
    && (match j.state with Available | Retry -> true | _ -> false)
  )
  |> Option.map ~f:(fun j -> { j with state = Executing; attempt = j.attempt + 1 })

(** Marks job completed or calculates backoff for Retry/Discard *)
let complete_job job (result: (unit, string) Result.t) =
  if not (match job.state with Executing -> true | _ -> false) then
    invalid_arg "STPA Safety Guard: Cannot complete a job that is not in the Executing state.";
  match result with
  | Ok () -> { job with state = Completed }
  | Error _err ->
      if job.attempt >= job.max_attempts then
        { job with state = Discarded }
      else
        (* Exponential backoff for retries *)
        let backoff = (Float.of_int job.attempt) ** 2.0 *. 10.0 in
        { job with 
          state = Retry; 
          scheduled_at = (Time_ns.now () |> Time_ns.to_span_since_epoch |> Time_ns.Span.to_sec) +. backoff 
        }
