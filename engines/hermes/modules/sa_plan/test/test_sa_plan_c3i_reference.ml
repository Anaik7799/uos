open Core

module Reference = Sa_plan.C3i_reference
module Store = Sa_plan.Store

let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let or_fail = function Ok value -> value | Error message -> failwith message

let with_store f =
  let path = (Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "zigvm-sa-plan-c3i-reference.sqlite3") in
  Exn.protect
    ~f:(fun () ->
      let store = or_fail (Store.open_db path) in
      Exn.protect ~f:(fun () -> f store) ~finally:(fun () -> Store.close store))
    ~finally:(fun () ->
      List.iter [ path; path ^ "-wal"; path ^ "-shm" ] ~f:(fun candidate ->
        if Stdlib.Sys.file_exists candidate then Stdlib.Sys.remove candidate))

let () =
  require "LAW C3I-REFERENCE-TERMINAL-TOTALITY"
    (Reference.corpus
     |> List.for_all ~f:(fun row ->
       match row.Reference.verdict with
       | Verified | Rejected_by_policy | Unavailable_observed -> true));
  require "LAW C3I-TASK-STATE-NORMALIZATION"
    (String.equal (Reference.normalize_task_state ~dependencies_ready:true "available")
       "pending"
     && String.equal
          (Reference.normalize_task_state ~dependencies_ready:false "available")
          "blocked"
     && String.equal
          (Reference.normalize_task_state ~dependencies_ready:true "executing")
          "in_progress");
  require "LAW C3I-JOB-STATE-NORMALIZATION"
    (String.equal (Reference.normalize_job_state Store.Job_retry) "retryable"
     && String.equal (Reference.normalize_job_state Store.Job_discarded) "discarded");
  require "LAW C3I-RETRY-TIMING-CLASS"
    (List.equal Int64.equal
       (List.init 9 ~f:(fun index -> Reference.retry_delay_ns ~attempt:(index + 1)))
       [ 30_000_000_000L; 60_000_000_000L; 120_000_000_000L;
         240_000_000_000L; 480_000_000_000L; 960_000_000_000L;
         1_920_000_000_000L; 3_600_000_000_000L; 3_600_000_000_000L ]);
  with_store (fun store ->
    let report = or_fail (Reference.evaluate_store store ~now_ns:10_000L) in
    require "LAW C3I-PLAN-JOB-WORKFLOW-VALUE-PARITY"
      (Option.equal Reference.equal_verdict
         (Reference.find_verdict report "plan-state") (Some Verified)
       && Option.equal Reference.equal_verdict
            (Reference.find_verdict report "job-state") (Some Verified)
       && Option.equal Reference.equal_verdict
            (Reference.find_verdict report "workflow-trace") (Some Verified));
    require "LAW C3I-ACTIVITY-IDEMPOTENCY-PARITY"
      (Option.equal Reference.equal_verdict
         (Reference.find_verdict report "activity-idempotency") (Some Verified));
    require "LAW C3I-TERMINAL-OUTCOME-PARITY"
      (Option.equal Reference.equal_verdict
         (Reference.find_verdict report "job-terminal-outcomes") (Some Verified));
    require "LAW C3I-UNAVAILABLE-NONFABRICATION"
      (Option.equal Reference.equal_verdict
         (Reference.find_verdict report "rust-runtime-execution")
         (Some Unavailable_observed)
       && Option.equal Reference.equal_verdict
            (Reference.find_verdict report "workflow-cancellation")
            (Some Unavailable_observed)));
  require "MUT-C3I-RETRY-FIXED-DELAY"
    (not (Int64.equal (Reference.retry_delay_ns ~attempt:1)
            (Reference.retry_delay_ns ~attempt:2)));
  require "MUT-C3I-UNAVAILABLE-AS-VERIFIED"
    (Reference.corpus
     |> List.exists ~f:(fun row ->
       String.equal row.Reference.id "rust-runtime-execution"
       && Poly.equal row.verdict Unavailable_observed))
