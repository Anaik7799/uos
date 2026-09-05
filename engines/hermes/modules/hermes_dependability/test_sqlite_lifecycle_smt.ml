open Sqlite_lifecycle_model

let passed = ref 0
let failed = ref 0
let check name condition =
  if condition then incr passed
  else begin incr failed; Printf.printf "FAILED: %s\n" name end

let contains_substring text needle =
  let text_length = String.length text in
  let needle_length = String.length needle in
  let rec search index =
    index + needle_length <= text_length
    && (String.sub text index needle_length = needle || search (index + 1))
  in
  needle_length = 0 || search 0

let expected_batch_output (batch : smt_batch) =
  batch.batch_obligations
  |> List.concat_map (fun (obligation : obligation) ->
         [ obligation.id;
           (match obligation.expected with Sat -> "sat" | Unsat -> "unsat") ])
  |> String.concat "\n"
  |> fun text -> text ^ "\n"

let () =
  let explore_started_ns = Mtime_clock.elapsed_ns () in
  let obligation_ids =
    obligations |> List.map (fun (obligation : obligation) -> obligation.id)
  in
  let report = explore () in
  let explore_elapsed_ns =
    Int64.sub (Mtime_clock.elapsed_ns ()) explore_started_ns
  in
  let campaign_started_ns = Mtime_clock.elapsed_ns () in
  let batches, metrics = smt_batches_with_metrics report in
  let campaign_elapsed_ns =
    Int64.sub (Mtime_clock.elapsed_ns ()) campaign_started_ns
  in
  let script =
    String.concat ""
      (List.map (fun (batch : smt_batch) -> batch.batch_script) batches)
  in
  Printf.printf
    "sqlite_lifecycle_stage: stage=explore elapsed_ns=%Ld states=%d/%d/%d laws=%d mutants=%d\n"
    explore_elapsed_ns report.statement_states report.close_v2_states
    report.actor_states (List.length report.laws) (List.length report.mutants);
  Printf.printf
    "sqlite_lifecycle_stage: stage=campaign elapsed_ns=%Ld bytes=%d relations=%d obligations=%d\n"
    campaign_elapsed_ns metrics.script_bytes (List.length metrics.relations)
    metrics.obligation_count;
  List.iter
    (fun (batch : smt_batch) ->
      Printf.printf
        "sqlite_lifecycle_batch_plan: id=%s digest=%s bytes=%d obligations=%d\n"
        batch.batch_id batch.batch_digest (String.length batch.batch_script)
        (List.length batch.batch_obligations))
    batches;
  flush stdout;
  check "S1 SMT obligations have unique stable identities"
    (List.length obligation_ids = List.length (List.sort_uniq compare obligation_ids)
     && List.length obligation_ids = 72
     && List.length
          (List.filter
             (fun (obligation : obligation) ->
               obligation.kind = Premise_control)
             obligations)
        = 25);
  check "S1b 22 relation batches are an exact ordered 72-label partition"
    (let missing = List.tl batches in
     let duplicate =
       match batches with [] -> [] | first :: _ -> first :: batches
     in
     let one_byte_payload_mutant =
       match batches with
       | [] -> []
       | (first : smt_batch) :: rest ->
           { first with batch_script = first.batch_script ^ " " } :: rest
     in
     let rejected_without_spawn candidate =
       let run = Sqlite_lifecycle_solver.run_z3_batches candidate in
       run.run_receipts = []
       && match run.run_verdict with
          | Unavailable detail -> String.trim detail <> ""
          | Proved | Refuted _ -> false
     in
     let cached_batches, cached_metrics = smt_batches_with_metrics report in
     List.length batches = 22
     && batches == cached_batches
     && metrics == cached_metrics
     && batch_manifest_complete batches
     && not (batch_manifest_complete missing)
     && not (batch_manifest_complete duplicate)
     && not (batch_manifest_complete one_byte_payload_mutant)
     && rejected_without_spawn missing
     && rejected_without_spawn duplicate
     && rejected_without_spawn one_byte_payload_mutant
     && List.concat_map
          (fun (batch : smt_batch) ->
            List.map
              (fun (obligation : obligation) -> obligation.id)
              batch.batch_obligations)
          batches
        = obligation_ids);
  check "S2 exact labelled Unsat/Sat output validates"
    (validate_solver_output (expected_solver_output ()) = Proved
     && List.for_all
          (fun (batch : smt_batch) ->
            validate_batch_output batch (expected_batch_output batch) = Proved)
          batches);
  check "S3 a satisfiable theorem negation is a refutation"
    (match mutate_expected_output ~id:"SQL.STMT.NO_DOUBLE_FINALIZE" ~actual:Sat with
     | Error _ -> false
     | Ok output ->
         begin match validate_solver_output output with
         | Refuted detail -> String.length detail > 0
         | Proved | Unavailable _ -> false
         end);
  check "S4 a dead satisfiability control is rejected as vacuous"
    (match mutate_expected_output ~id:"CONTROL.HEALTHY_CLOSE" ~actual:Unsat with
     | Error _ -> false
     | Ok output ->
         begin match validate_solver_output output with
         | Refuted detail -> String.length detail > 0
         | Proved | Unavailable _ -> false
         end);
  check "S5 malformed, truncated, duplicate, or unknown output is unavailable"
    (let first_batch = List.hd batches in
     let first_output = expected_batch_output first_batch in
     List.for_all
       (fun output ->
         match validate_solver_output output with
         | Unavailable detail -> String.length detail > 0
         | Proved | Refuted _ -> false)
       [ ""; "SQL.STMT.NO_DOUBLE_FINALIZE\nunsat\n";
         expected_solver_output () ^ "CONTROL.HEALTHY_CLOSE\nsat\n";
         "SQL.STMT.NO_DOUBLE_FINALIZE\nunknown\n" ]
     && List.for_all
          (fun output ->
            match validate_batch_output first_batch output with
            | Unavailable detail -> String.length detail > 0
            | Proved | Refuted _ -> false)
          [ "";
            first_output ^
            (List.hd first_batch.batch_obligations).id ^ "\nunsat\n";
            (List.hd first_batch.batch_obligations).id ^ "\nunknown\n" ]);
  check "S6 generated SMT is bound to relational real and mutant path tables"
    (String.length script > 1_000
     && metrics.script_bytes = String.length script
     && metrics.script_bytes <= 16 * 1024 * 1024
     && metrics.obligation_count = 72
     && List.length metrics.relations = 22
     && metrics.path_assertions > 0
     && bfs_certificates_valid ()
     && bfs_certificate_mutants_rejected ()
     && bfs_certificate_mutant_results ()
        = [ ("CERT.BROKEN_PARENT", true); ("CERT.MISSING_EDGE", true);
            ("CERT.MISSING_STATE", true); ("CERT.FALSE_DEPTH", true) ]
     && progress_certificate_valid ()
     && progress_certificate_mutants_rejected ()
     && progress_certificate_mutant_results ()
        = [ ("PROGRESS_CERT.BROKEN_RANK", true);
            ("PROGRESS_CERT.MISSING_EDGE", true);
            ("PROGRESS_CERT.CYCLE", true) ]
     && raw_cleanup_encodings_valid ()
     && raw_cleanup_encoding_mutants_rejected ()
     && raw_cleanup_encoding_mutant_results ()
        = [ ("RAW_CLEANUP.OMITTED_NONZERO", true);
            ("RAW_CLEANUP.WRONG_DEFAULT", true);
            ("RAW_CLEANUP.WRONG_NONZERO", true) ]
     && List.for_all
          (fun metric ->
            metric.relation_states > 0
            && metric.relation_path_bound >= 0
            && metric.relation_path_bound < metric.relation_states)
          metrics.relations
     && mutant_prefixes_closed report
     && String.length (transition_table_digest ()) = 64
     && contains_substring script (transition_table_digest ())
     && contains_substring script "mut_trace_id"
     && contains_substring script "real_statement_initial"
     && contains_substring script "real_statement_edge"
     && contains_substring script "real_statement_next"
     && contains_substring script "real_statement_bfs_depth"
     && contains_substring script "real_statement_bfs_parent"
     && contains_substring script "real_statement_bfs_parent_event"
     && contains_substring script "real_statement_certified_reachable"
     && contains_substring script "real_close_v2_initial"
     && contains_substring script "real_close_v2_edge"
     && contains_substring script "real_close_v2_next"
     && contains_substring script "real_close_v2_bfs_depth"
     && contains_substring script "real_close_v2_bfs_parent"
     && contains_substring script "real_close_v2_bfs_parent_event"
     && contains_substring script "real_close_v2_certified_reachable"
     && contains_substring script "real_actor_initial"
     && contains_substring script "real_actor_edge"
     && contains_substring script "real_actor_next"
     && contains_substring script "real_actor_bfs_depth"
     && contains_substring script "real_actor_bfs_parent"
     && contains_substring script "real_actor_bfs_parent_event"
     && contains_substring script "real_actor_certified_reachable"
     && contains_substring script "real_actor_progress_edge"
     && contains_substring script "real_actor_progress_rank"
     && contains_substring script "real_actor_progress_certified"
     && contains_substring script "actor_cleanup_origin"
     && contains_substring script "actor_cleanup_owner_kind"
     && contains_substring script "actor_cleanup_owner_generation"
     && contains_substring script "actor_ack_failure_name_length"
     && not (contains_substring script "actor_progress_total")
     && not (contains_substring script "actor_cleanup_honest")
     && not (contains_substring script "declare-const MUT_STMT_DROP_KEEPALIVE Bool")
     && contains_substring script "(declare-const s Int)"
     && contains_substring script "(declare-const a Int)"
     && List.for_all
          (fun id ->
            let n = String.length script and k = String.length id in
            let rec contains at =
              at + k <= n
              && (String.sub script at k = id || contains (at + 1))
            in
            contains 0)
          obligation_ids
     && List.for_all
          (fun id ->
            List.exists
              (fun (obligation : obligation) ->
                obligation.id = id && obligation.kind = Premise_control
                && obligation.expected = Sat)
              obligations)
          [ "CONTROL.PREMISE.SQL.ACTOR.BOUNDED_TERMINAL";
            "CONTROL.PREMISE.SQL.ACTOR.PROGRESS_TOTAL" ]
     && List.for_all (fun (mutant : mutant_result) ->
               let prefix =
                 String.map
                   (function '.' | '-' -> '_' | character -> character)
                   mutant.id
               in
               contains_substring script (prefix ^ "_initial")
               && contains_substring script (prefix ^ "_edge")
               && contains_substring script (prefix ^ "_next")
               && contains_substring script (prefix ^ "_bfs_depth")
               && contains_substring script (prefix ^ "_bfs_parent")
               && contains_substring script (prefix ^ "_bfs_parent_event")
               && contains_substring script (prefix ^ "_certified_reachable"))
          report.mutants);
  check "S7 timeout, signal, stop, nonzero, spawn, and open failures are unavailable and reaped"
    (Sqlite_lifecycle_solver.For_test.reap_retries_eintr ()
     && Sqlite_lifecycle_solver.For_test.kill_retries_eintr ()
     && List.for_all
       (fun failure_case ->
         let observation =
           Sqlite_lifecycle_solver.For_test.exercise_failure failure_case
         in
         observation.reaped
         && (match failure_case with
             | Sqlite_lifecycle_solver.For_test.Stopped ->
                 observation.stopped_observed
             | _ -> not observation.stopped_observed)
         && (match observation.pid with
             | None -> true
             | Some pid -> Sqlite_lifecycle_solver.For_test.pid_is_reaped pid)
         && (match failure_case, observation.pid with
             | (Sqlite_lifecycle_solver.For_test.Timeout
               | Sqlite_lifecycle_solver.For_test.Signal
               | Sqlite_lifecycle_solver.For_test.Stopped
               | Sqlite_lifecycle_solver.For_test.Nonzero_exit), Some _ -> true
             | (Sqlite_lifecycle_solver.For_test.Spawn_failure
               | Sqlite_lifecycle_solver.For_test.Output_open_failure), None -> true
             | _ -> false)
         && (match observation.verdict with
             | Unavailable detail -> String.trim detail <> ""
             | Proved | Refuted _ -> false))
       [ Sqlite_lifecycle_solver.For_test.Timeout;
         Sqlite_lifecycle_solver.For_test.Signal;
         Sqlite_lifecycle_solver.For_test.Stopped;
         Sqlite_lifecycle_solver.For_test.Nonzero_exit;
         Sqlite_lifecycle_solver.For_test.Spawn_failure;
         Sqlite_lifecycle_solver.For_test.Output_open_failure ]);
  let solve_started_ns = Mtime_clock.elapsed_ns () in
  let campaign_deadline_ns =
    Int64.add explore_started_ns 44_000_000_000L
  in
  let finish_run verdict receipts : Sqlite_lifecycle_solver.batch_run =
    { run_verdict = verdict; run_receipts = List.rev receipts;
      run_elapsed_ns = Int64.sub (Mtime_clock.elapsed_ns ()) solve_started_ns }
  in
  let rec run_campaign receipts = function
    | [] ->
        let answers =
          List.fold_left
            (fun total
              (receipt : Sqlite_lifecycle_solver.batch_receipt) ->
              total + receipt.receipt_answers)
            0 receipts
        in
        finish_run
          (if answers = List.length obligations then Proved
           else Unavailable "batch answer union is incomplete")
          receipts
    | (batch : smt_batch) :: rest ->
        let remaining_ns =
          let remaining =
            Int64.sub campaign_deadline_ns (Mtime_clock.elapsed_ns ())
          in
          if Int64.compare remaining 0L < 0 then 0L else remaining
        in
        Printf.printf
          "BATCH_START id=%s digest=%s bytes=%d obligations=%d remaining_ns=%Ld\n"
          batch.batch_id batch.batch_digest (String.length batch.batch_script)
          (List.length batch.batch_obligations) remaining_ns;
        flush stdout;
        let receipt =
          Sqlite_lifecycle_solver.run_batch ~deadline_ns:campaign_deadline_ns
            batch
        in
        Printf.printf
          "BATCH_END id=%s verdict=%s answers=%d elapsed_ns=%Ld reaped=%b prefix_answers=%d first_unanswered=%s stdout_bytes=%d stdout_sha256=%s stderr_bytes=%d stderr_sha256=%s\n"
          receipt.receipt_batch_id
          (match receipt.receipt_verdict with
           | Proved -> "proved"
           | Refuted _ -> "refuted"
           | Unavailable _ -> "unavailable")
          receipt.receipt_answers receipt.receipt_elapsed_ns
          receipt.receipt_reaped receipt.receipt_prefix_answers
          (Option.value ~default:"none" receipt.receipt_first_unanswered)
          receipt.receipt_stdout_bytes receipt.receipt_stdout_digest
          receipt.receipt_stderr_bytes receipt.receipt_stderr_digest;
        flush stdout;
        begin match receipt.receipt_verdict with
        | Proved -> run_campaign (receipt :: receipts) rest
        | Refuted detail ->
            finish_run (Refuted (batch.batch_id ^ ": " ^ detail))
              (receipt :: receipts)
        | Unavailable detail ->
            finish_run (Unavailable (batch.batch_id ^ ": " ^ detail))
              (receipt :: receipts)
        end
  in
  let live_run =
    if batch_manifest_complete batches then run_campaign [] batches
    else
      finish_run
        (Unavailable "batch manifest is missing, duplicated, or reordered") []
  in
  check "S8 live Z3 discharges relational theorem paths, mutant paths, and controls"
    (match live_run.run_verdict with
     | Proved ->
         List.length live_run.run_receipts = List.length batches
         && List.for_all2
              (fun
                (receipt : Sqlite_lifecycle_solver.batch_receipt)
                (batch : smt_batch) ->
                String.equal receipt.receipt_batch_id batch.batch_id
                && String.equal receipt.receipt_batch_digest batch.batch_digest
                && receipt.receipt_answers = List.length batch.batch_obligations
                && receipt.receipt_prefix_answers
                   = List.length batch.batch_obligations
                && receipt.receipt_first_unanswered = None
                && String.length receipt.receipt_stdout_digest = 64
                && String.length receipt.receipt_stderr_digest = 64
                && receipt.receipt_reaped
                && receipt.receipt_verdict = Proved)
              live_run.run_receipts batches
         && List.fold_left
              (fun total
                (receipt : Sqlite_lifecycle_solver.batch_receipt) ->
                total + receipt.receipt_answers)
              0 live_run.run_receipts
            = 72
         && Int64.compare live_run.run_elapsed_ns 45_000_000_000L <= 0
     | Refuted detail -> Printf.printf "  live refutation: %s\n" detail; false
     | Unavailable detail -> Printf.printf "  unavailable: %s\n" detail; false);
  Printf.printf "sqlite_lifecycle_smt: %d passed, %d failed\n" !passed !failed;
  Printf.printf
    "sqlite_lifecycle_smt_metrics: bytes=%d path_assertions=%d relations=%d obligations=%d\n"
    metrics.script_bytes metrics.path_assertions (List.length metrics.relations)
    metrics.obligation_count;
  List.iter
    (fun metric ->
      Printf.printf
        "sqlite_lifecycle_relation: id=%s states=%d edges=%d diameter=%d\n"
        metric.relation_id metric.relation_states metric.relation_edges
        metric.relation_path_bound)
    metrics.relations;
  List.iter2
    (fun
      (receipt : Sqlite_lifecycle_solver.batch_receipt)
      (batch : smt_batch) ->
      Printf.printf
        "sqlite_lifecycle_batch: id=%s digest=%s bytes=%d answers=%d prefix_answers=%d first_unanswered=%s elapsed_ns=%Ld reaped=%b stdout_bytes=%d stdout_sha256=%s stderr_bytes=%d stderr_sha256=%s\n"
        receipt.receipt_batch_id receipt.receipt_batch_digest
        (String.length batch.batch_script) receipt.receipt_answers
        receipt.receipt_prefix_answers
        (Option.value ~default:"none" receipt.receipt_first_unanswered)
        receipt.receipt_elapsed_ns receipt.receipt_reaped
        receipt.receipt_stdout_bytes receipt.receipt_stdout_digest
        receipt.receipt_stderr_bytes receipt.receipt_stderr_digest)
    live_run.run_receipts
    (let receipt_count = List.length live_run.run_receipts in
     List.filteri (fun index _ -> index < receipt_count) batches);
  Printf.printf "sqlite_lifecycle_solver: elapsed_ns=%Ld receipts=%d\n"
    live_run.run_elapsed_ns (List.length live_run.run_receipts);
  let self = Suite_telemetry.observe ~suite:"test_sqlite_lifecycle_smt" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_dependability_core; Stanza.hermes_dependability_sqlite; Stanza.hermes_dependability_solver; Stanza.hermes_dependability_process; Stanza.hermes_dependability_topology ]);
  exit (Suite_telemetry.exit_code self)
