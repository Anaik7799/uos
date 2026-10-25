open Core
module Store = Sa_plan.Store
let ok = function Ok x -> x | Error e -> failwith e
let some = function Some x -> x | None -> failwith "expected job"
let check name pass = if pass then Printf.printf "ok %s\n%!" name else failwith name
let jobs store = ok (Store.list_jobs store ~queue:None)
let view store id = List.find_exn (jobs store) ~f:(fun j -> String.equal j.Store.id id)
let enqueue store id queue limit =
  ignore (ok (Store.enqueue_job store ~id ~name:("budget/" ^ id) ~queue
    ~worker:"handler" ~args:"{}" ~max_attempts:limit ~now_ns:0L) : Store.job_view)
let claim store queue now worker =
  ok (Store.claim_job store ~queue ~worker ~now_ns:now ~lease_ns:10L)
let fixture f =
  let path = Stdlib.Filename.temp_file "uos-job-budget-" ".sqlite3" in
  let store = ok (Store.open_db path) in
  Exn.protect ~finally:(fun () -> Store.close store;
    List.iter [path; path ^ "-wal"; path ^ "-shm"] ~f:(fun p ->
      if Stdlib.Sys.file_exists p then Stdlib.Sys.remove p))
    ~f:(fun () -> f path store)
let () =
  fixture (fun _ store ->
    enqueue store "one" "q" 1;
    let first = some (claim store "q" 100L "a") in
    let before = jobs store in
    check "LIVE-FINAL-ATTEMPT-NOT-RECLAIMED"
      (Option.is_none (claim store "q" 109L "b") && Poly.equal before (jobs store));
    check "EXPIRED-FINAL-ATTEMPT-NOT-RECLAIMED"
      (Option.is_none (claim store "q" 110L "b"));
    let retired = view store "one" in
    check "EXPIRED-LIMIT-TERMINAL-UNKNOWN-OUTCOME"
      (Poly.equal retired.state Store.Job_discarded && retired.attempt = 1
       && Option.is_none retired.lease_owner && Option.is_none retired.lease_until_ns
       && Option.value_map retired.result ~default:false
          ~f:(fun s -> String.is_substring s ~substring:"execution_outcome_unknown"));
    let before = jobs store in
    check "RETIRED-REPLAY-AND-LATE-COMPLETION-REFUSED"
      (Option.is_none (claim store "q" 111L "c")
       && Result.is_error (Store.complete_job store ~id_or_name:"one" ~worker:"a"
          ~expected_attempt:first.attempt ~outcome:(`Ok "late") ~now_ns:111L)
       && Poly.equal before (jobs store)));
  fixture (fun _ store ->
    enqueue store "live-success" "q" 1;
    let j = some (claim store "q" 100L "a") in
    let done_ = ok (Store.complete_job store ~id_or_name:j.id ~worker:"a"
      ~expected_attempt:j.attempt ~outcome:(`Ok "known") ~now_ns:109L) in
    check "FINAL-LIVE-ATTEMPT-CAN-COMPLETE" (Poly.equal done_.state Store.Job_completed);
    check "COMPLETED-UNCHANGED" (Option.is_none (claim store "q" 110L "b")
      && String.equal (Option.value_exn (view store j.id).result) "known"));
  List.iter [1; 2; 3; 4] ~f:(fun limit ->
    fixture (fun path store ->
      enqueue store "bounded" "q" limit;
      for i = 1 to limit do
        let job = some (claim store "q" (Int64.of_int (100 + ((i - 1) * 10))) "w") in
        check ("BUDGET-ORACLE-ATTEMPT-" ^ Int.to_string limit ^ "-" ^ Int.to_string i)
          (job.attempt = i && job.attempt <= job.max_attempts)
      done;
      let peer = ok (Store.open_db path) in
      Exn.protect ~finally:(fun () -> Store.close peer) ~f:(fun () ->
        let exhausted_at = Int64.of_int (100 + (limit * 10)) in
        check ("BUDGET-ORACLE-REOPENED-LIMIT-" ^ Int.to_string limit)
          (Option.is_none (claim peer "q" exhausted_at "new")
           && (view peer "bounded").attempt = limit
           && Poly.equal (view peer "bounded").state Store.Job_discarded))));
  fixture (fun _ store ->
    enqueue store "foreign" "foreign" 1; ignore (some (claim store "foreign" 100L "a") : Store.job_view);
    enqueue store "expired" "q" 1; ignore (some (claim store "q" 100L "a") : Store.job_view);
    enqueue store "next" "q" 2;
    let foreign = view store "foreign" in
    let next = some (claim store "q" 110L "b") in
    check "EXHAUSTED-JOB-DOES-NOT-BLOCK-READY-WORK"
      (String.equal next.id "next" && next.attempt = 1);
    check "QUEUE-SCOPE-PRESERVED" (Poly.equal foreign (view store "foreign")));
  fixture (fun _ store ->
    enqueue store "expired" "q" 1; ignore (some (claim store "q" 100L "a") : Store.job_view);
    let before = jobs store in
    check "INVALID-CLAIM-HAS-NO-CLEANUP-EFFECT"
      (Result.is_error (Store.claim_job store ~queue:"q" ~worker:"a" ~now_ns:110L ~lease_ns:0L)
       && Poly.equal before (jobs store)));
  fixture (fun _ store ->
    for i = 1 to 70 do
      let id = Printf.sprintf "old-%03d" i in
      enqueue store id "q" 1;
      ignore (some (claim store "q" 100L "a") : Store.job_view)
    done;
    enqueue store "ready" "q" 1;
    let fresh = some (claim store "q" 110L "b") in
    let discarded () = List.count (jobs store) ~f:(fun j -> Poly.equal j.Store.state Store.Job_discarded) in
    check "BOUNDED-RETIREMENT-DOES-NOT-STARVE-READY-JOB"
      (String.equal fresh.id "ready" && discarded () = 64);
    check "LATER-PULL-RETIRES-REMAINDER-WITHOUT-REPLAY"
      (Option.is_none (claim store "q" 111L "c") && discarded () = 70));
  fixture (fun path store ->
    enqueue store "expired" "q" 1; ignore (some (claim store "q" 100L "a") : Store.job_view);
    enqueue store "ready" "q" 1;
    let peer = ok (Store.open_db path) in
    Exn.protect ~finally:(fun () -> Store.close peer) ~f:(fun () ->
      let remote = Domain.spawn (fun () -> claim peer "q" 110L "b") in
      let local = claim store "q" 110L "c" in
      let other = Domain.join remote in
      check "TWO-CONNECTION-PULL-HAS-ONE-READY-WINNER"
        (Bool.(Option.is_some local <> Option.is_some other)
         && (view store "ready").attempt = 1
         && Poly.equal (view store "expired").state Store.Job_discarded)));
  print_endline "job retry budgets: PASS"
