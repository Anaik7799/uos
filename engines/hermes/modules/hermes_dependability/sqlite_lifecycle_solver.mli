(** Argv-only Z3 oracle for the generated relational SQLite lifecycle model.

    Solver absence, timeout, signal, malformed output, temporary-file failure,
    open failure, or spawn failure is unavailable.  Every admitted child is
    terminated if needed and reaped before return. *)

val run_z3 : script:string -> Sqlite_lifecycle_model.verdict

type batch_receipt = {
  receipt_batch_id : string;
  receipt_batch_digest : string;
  receipt_elapsed_ns : int64;
  receipt_answers : int;
  receipt_prefix_answers : int;
  receipt_first_unanswered : string option;
  receipt_stdout_bytes : int;
  receipt_stdout_digest : string;
  receipt_stderr_bytes : int;
  receipt_stderr_digest : string;
  receipt_reaped : bool;
  receipt_verdict : Sqlite_lifecycle_model.verdict;
}

type batch_run = {
  run_verdict : Sqlite_lifecycle_model.verdict;
  run_receipts : batch_receipt list;
  run_elapsed_ns : int64;
}

val run_batch :
  deadline_ns:int64 ->
  Sqlite_lifecycle_model.smt_batch ->
  batch_receipt

val run_z3_batches : Sqlite_lifecycle_model.smt_batch list -> batch_run

module For_test : sig
  type failure_case =
    | Timeout
    | Signal
    | Stopped
    | Nonzero_exit
    | Spawn_failure
    | Output_open_failure

  type observation = {
    verdict : Sqlite_lifecycle_model.verdict;
    pid : int option;
    reaped : bool;
    stopped_observed : bool;
  }

  val exercise_failure : failure_case -> observation
  val pid_is_reaped : int -> bool
  val reap_retries_eintr : unit -> bool
  val kill_retries_eintr : unit -> bool
end
