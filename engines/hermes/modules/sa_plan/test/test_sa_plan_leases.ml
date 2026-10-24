module Lifetime_unix = Unix
open Core

module Store = Sa_plan.Store

(* Keep raw SQLite fixture handles alive across runtime-releasing C calls. *)
module Raw_sqlite3 = Sqlite3
module Sqlite3 = struct
  include Raw_sqlite3
  let finalize stmt =
    let rc = Raw_sqlite3.finalize stmt in
    Gc.keep_alive stmt; rc
  let db_close db =
    let closed = Raw_sqlite3.db_close db in
    Gc.keep_alive db; closed
end

let require law condition =
  if condition then Printf.printf "ok %s\n%!" law
  else (prerr_endline ("FAILED: " ^ law); exit 1)

let ok = function Ok value -> value | Error error -> failwith error

let mapping_request =
  Store.
    { domain = Sa_plan;
      ooda_slice_id = "cp-05";
      idempotency_key = "cp-05-key";
      source_fingerprint = "source-a";
      dependency_snapshot = "[]";
      prompt_ledger_hash = "prompt-a";
      safety_packet_hash = "safety-a";
      formal_evidence_hash = "formal-a";
      sa_plan_id = Some "cp05-plan";
      sa_task_id = Some "cp05-task";
      lifecycle_state = "preflighted";
      created_at_ns = 1L }

let () =
  let path = (Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "zigvm-sa-plan-lease-test.sqlite3") in
  if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path;
  let store = ok (Store.open_db path) in
  ok
    (Store.create_plan store ~id:"cp05-plan" ~name:"control-plane/bridge"
       ~title:"cp05" ~now_ns:1L);
  ok
    (Store.create_task store ~plan_id:"cp05-plan" ~id:"cp05-task"
       ~name:"control-plane/bridge/05-leases" ~title:"cp05" ~parent_id:None
       ~dependencies:[] ~priority:0 ~now_ns:1L);
  let mapping = ok (Store.ensure_bridge_mapping store mapping_request) in
  let first =
    ok
      (Store.claim_bridge_lease store ~mapping_id:mapping.id ~owner:"worker-a"
         ~lease_id:"lease-a" ~now_ns:100L ~lease_ns:50L)
  in
  require "LAW CP05-FIRST-CLAIM-ASSIGNS-FENCE-ONE"
    (Int64.equal first.fencing_token 1L && String.equal first.owner "worker-a"
     && Int64.equal first.expires_at_ns 150L);
  require "LAW CP05-LIVE-LEASE-REJECTS-SECOND-OWNER"
    (Result.is_error
       (Store.claim_bridge_lease store ~mapping_id:mapping.id ~owner:"worker-b"
          ~lease_id:"lease-b" ~now_ns:149L ~lease_ns:50L));
  let reclaimed =
    ok
      (Store.claim_bridge_lease store ~mapping_id:mapping.id ~owner:"worker-b"
         ~lease_id:"lease-b" ~now_ns:151L ~lease_ns:50L)
  in
  require "LAW CP05-EXPIRED-RECLAIM-ADVANCES-FENCE"
    (Int64.equal reclaimed.fencing_token 2L && String.equal reclaimed.owner "worker-b");
  require "LAW CP05-STALE-FENCE-CANNOT-TRANSITION"
    (Result.is_error
       (Store.complete_bridge_task store ~mapping_id:mapping.id ~owner:"worker-a"
          ~lease_id:"lease-a" ~fencing_token:first.fencing_token ~result:"stale"
          ~now_ns:160L));
  require "LAW CP05-WRONG-FENCE-CANNOT-TRANSITION"
    (Result.is_error
       (Store.complete_bridge_task store ~mapping_id:mapping.id ~owner:"worker-b"
          ~lease_id:"lease-b" ~fencing_token:first.fencing_token ~result:"wrong-fence"
          ~now_ns:160L));
  ok
    (Store.complete_bridge_task store ~mapping_id:mapping.id ~owner:"worker-b"
       ~lease_id:"lease-b" ~fencing_token:reclaimed.fencing_token ~result:"green"
       ~now_ns:160L);
  require "LAW CP05-CURRENT-FENCE-COMPLETES-TASK"
    (match ok (Store.find_task store ~plan_id:"cp05-plan" ~id_or_name:"cp05-task") with
     | Some task -> String.equal task.state "completed"
     | None -> false);
  Store.close store;
  let reopened = ok (Store.open_db path) in
  require "LAW CP05-RESTART-PRESERVES-FENCED-COMPLETION"
    (match ok (Store.find_task reopened ~plan_id:"cp05-plan" ~id_or_name:"cp05-task") with
     | Some task -> String.equal task.state "completed"
     | None -> false);
  require "LAW CP05-COMPLETED-TASK-CANNOT-BE-RECLAIMED"
    (Result.is_error
       (Store.claim_bridge_lease reopened ~mapping_id:mapping.id ~owner:"worker-c"
          ~lease_id:"lease-c" ~now_ns:1000L ~lease_ns:50L));
  Store.close reopened;
  Stdlib.Sys.remove path


(* Independent finite-state oracle. No SQL or Store guard helper is reused.
   Explicit clock inputs include adversarial non-monotone sequences. These
   tests establish store transitions, not trusted time or remote-effect authority. *)
module Oracle = struct
  type phase = Available | Executing of string * int64 | Completed
  type state = { phase : phase; attempt : int }
  type action =
    | Claim of string * int64 * int64
    | Complete of string * int * int64
    | Release of string * int * int64

  let step state action =
    match action with
    | Claim (worker, now, duration) ->
        let ready = match state.phase with
          | Available -> true
          | Executing (_, deadline) -> Int64.(now >= deadline)
          | Completed -> false in
        if not ready || String.is_empty (String.strip worker)
           || Int64.(now < 0L || duration <= 0L || now > max_value - duration)
           || state.attempt = Stdlib.max_int then false, state
        else true, { phase = Executing (worker, Int64.(now + duration));
                     attempt = state.attempt + 1 }
    | Complete (worker, attempt, now) | Release (worker, attempt, now) ->
        let current = match state.phase with
          | Executing (owner, deadline) ->
              String.equal owner worker && attempt = state.attempt
              && attempt > 0 && Int64.(now >= 0L && now < deadline)
          | Available | Completed -> false in
        if not current then false, state
        else true, { state with phase = match action with
          | Complete _ -> Completed | _ -> Available }
end

let tests = ref 0
let check name predicate = Int.incr tests; require ("LAW FENCE-" ^ name) predicate
let some = function Some x -> x | None -> failwith "expected a claim"
let fixture_reader = ref None
let with_fixture run =
  let path = Stdlib.Filename.temp_file "uos-fencing-" ".sqlite3" in
  let store = ok (Store.open_db path) in
  let reader = Sqlite3.db_open ~mode:`READONLY path in
  fixture_reader := Some reader;
  Exn.protect ~f:(fun () -> run path store) ~finally:(fun () ->
    Store.close store;
    fixture_reader := None;
    ignore (Sqlite3.db_close reader : bool);
    List.iter [path; path ^ "-wal"; path ^ "-shm"] ~f:(fun p ->
      if Stdlib.Sys.file_exists p then Stdlib.Sys.remove p))

let create store id =
  ok (Store.create_task store ~plan_id:"fence" ~id ~name:("fence/" ^ id)
        ~title:id ~parent_id:None ~dependencies:[] ~priority:0 ~now_ns:0L)

let setup store =
  ok (Store.create_plan store ~id:"fence" ~name:"fence/tests" ~title:"Fencing laws" ~now_ns:0L)

let view _store id =
  let statement = Sqlite3.prepare (some !fixture_reader)
    "SELECT state,worker,attempt,lease_until_ns,result FROM sa_plan_task WHERE plan_id='fence' AND id=?" in
  Exn.protect ~finally:(fun () -> ignore (Sqlite3.finalize statement : Sqlite3.Rc.t))
    ~f:(fun () ->
      ignore (Sqlite3.bind statement 1 (Sqlite3.Data.TEXT id) : Sqlite3.Rc.t);
      if not (Poly.equal (Sqlite3.step statement) Sqlite3.Rc.ROW) then failwith "missing fixture task";
      Sqlite3.column_text statement 0, Sqlite3.column statement 1,
      Sqlite3.column_int statement 2, Sqlite3.column statement 3, Sqlite3.column statement 4)

let run_action store id = function
  | Oracle.Claim (worker, now_ns, lease_ns) ->
      Result.is_ok (Store.claim_task store ~plan_id:"fence" ~task_id:id ~worker ~now_ns ~lease_ns)
  | Complete (worker, expected_attempt, now_ns) ->
      Result.is_ok (Store.complete_task store ~plan_id:"fence" ~task_id:id ~worker
                      ~expected_attempt ~result:"oracle completion" ~now_ns)
  | Release (worker, expected_attempt, now_ns) ->
      Result.is_ok (Store.release_task store ~plan_id:"fence" ~task_id:id ~worker
                      ~expected_attempt ~now_ns)

let agrees (model : Oracle.state) (state, worker, attempt, expiry, _result) =
  attempt = model.attempt
  && match model.phase with
     | Oracle.Available -> String.equal state "available"
         && Poly.equal worker Sqlite3.Data.NULL && Poly.equal expiry Sqlite3.Data.NULL
     | Oracle.Completed -> String.equal state "completed"
         && Poly.equal expiry Sqlite3.Data.NULL
     | Oracle.Executing (owner, deadline) -> String.equal state "executing"
         && Poly.equal worker (Sqlite3.Data.TEXT owner)
         && Poly.equal expiry (Sqlite3.Data.INT deadline)

let () =
  with_fixture (fun _ store ->
    setup store;
    let alphabet = Oracle.[
      Claim ("same", 110L, 10L); Claim ("other", 110L, 10L);
      Complete ("same", 1, 109L); Complete ("same", 1, 110L);
      Complete ("same", 2, 111L); Complete ("other", 2, 111L);
      Release ("same", 1, 109L); Release ("same", 2, 111L);
      Complete ("same", 0, 105L) ] in
    let sequences = List.concat_map alphabet ~f:(fun a ->
      List.concat_map alphabet ~f:(fun b -> List.map alphabet ~f:(fun c -> [a;b;c]))) in
    List.iteri sequences ~f:(fun seed actions ->
      let id = "oracle-" ^ Int.to_string seed in
      create store id;
      let initial = Oracle.{ phase = Available; attempt = 0 } in
      ignore (List.foldi (Oracle.Claim ("same", 100L, 10L) :: actions)
        ~init:initial ~f:(fun step model action ->
          let expected, next = Oracle.step model action in
          let before = view store id in
          let observed = run_action store id action in
          let after = view store id in
          check (Printf.sprintf "ORACLE-%d-%d" seed step)
            (Bool.equal observed expected && agrees next after
             && (observed || Poly.equal before after));
          next) : Oracle.state));
    check "BOUNDED-ORACLE-729-TRACES" (List.length sequences = 729));

  with_fixture (fun path store ->
    setup store; create store "restart";
    let old = ok (Store.claim_task store ~plan_id:"fence" ~task_id:"restart"
                    ~worker:"same" ~now_ns:100L ~lease_ns:10L) in
    Store.close store;
    let reopened = ok (Store.open_db path) in
    Exn.protect ~finally:(fun () -> Store.close reopened) ~f:(fun () ->
      let current = ok (Store.claim_task reopened ~plan_id:"fence" ~task_id:"restart"
                         ~worker:"same" ~now_ns:110L ~lease_ns:10L) in
      let before = view reopened "restart" in
      check "RESTART-SAME-WORKER-STALE-COMPLETE"
        (Result.is_error (Store.complete_task reopened ~plan_id:"fence" ~task_id:"restart"
           ~worker:"same" ~expected_attempt:old.attempt ~result:"stale" ~now_ns:111L)
         && Poly.equal before (view reopened "restart"));
      check "RESTART-SAME-WORKER-STALE-RELEASE"
        (Result.is_error (Store.release_task reopened ~plan_id:"fence" ~task_id:"restart"
           ~worker:"same" ~expected_attempt:old.attempt ~now_ns:111L)
         && Poly.equal before (view reopened "restart"));
      check "RESTART-CURRENT-COMPLETES"
        (Result.is_ok (Store.complete_task reopened ~plan_id:"fence" ~task_id:"restart"
           ~worker:"same" ~expected_attempt:current.attempt ~result:"fresh" ~now_ns:111L))));

  with_fixture (fun path store ->
    ignore (ok (Store.enqueue_job store ~id:"job" ~name:"fence/job" ~queue:"q"
      ~worker:"fixture" ~args:"{}" ~max_attempts:3 ~now_ns:0L) : Store.job_view);
    let first = some (ok (Store.claim_job store ~queue:"q" ~worker:"same"
                           ~now_ns:100L ~lease_ns:10L)) in
    let before = ok (Store.list_jobs store ~queue:None) in
    List.iter [ `Ok "expired"; `Error "expired" ] ~f:(fun outcome ->
      check "JOB-EXPIRY-EXACT"
        (Result.is_error (Store.complete_job store ~id_or_name:"job" ~worker:"same"
          ~expected_attempt:first.attempt ~outcome ~now_ns:110L)
         && Poly.equal before (ok (Store.list_jobs store ~queue:None))));
    Store.close store;
    let reopened = ok (Store.open_db path) in
    Exn.protect ~finally:(fun () -> Store.close reopened) ~f:(fun () ->
      let current = some (ok (Store.claim_job reopened ~queue:"q" ~worker:"same"
                              ~now_ns:110L ~lease_ns:10L)) in
      let before = ok (Store.list_jobs reopened ~queue:None) in
      List.iter [ `Ok "stale"; `Error "stale" ] ~f:(fun outcome ->
        check "JOB-RESTART-SAME-WORKER-STALE"
          (Result.is_error (Store.complete_job reopened ~id_or_name:"job" ~worker:"same"
             ~expected_attempt:first.attempt ~outcome ~now_ns:111L)
           && Poly.equal before (ok (Store.list_jobs reopened ~queue:None))));
      check "JOB-WRONG-WORKER"
        (Result.is_error (Store.complete_job reopened ~id_or_name:"job" ~worker:"other"
           ~expected_attempt:current.attempt ~outcome:(`Ok "wrong") ~now_ns:111L));
      let retry = ok (Store.complete_job reopened ~id_or_name:"job" ~worker:"same"
        ~expected_attempt:current.attempt ~outcome:(`Error "retry") ~now_ns:111L) in
      check "JOB-CURRENT-RETRY" (Poly.equal retry.state Store.Job_retry);
      let third = some (ok (Store.claim_job reopened ~queue:"q" ~worker:"new"
        ~now_ns:retry.available_at_ns ~lease_ns:10L)) in
      check "JOB-THIRD-ATTEMPT-COMPLETES"
        (Result.is_ok (Store.complete_job reopened ~id_or_name:"job" ~worker:"new"
          ~expected_attempt:third.attempt ~outcome:(`Ok "done")
          ~now_ns:Int64.(retry.available_at_ns + 1L)))));

  with_fixture (fun _ store ->
    setup store; create store "bounds";
    List.iter [(-1L, 1L); (0L, 0L); (0L, -1L); (Int64.max_value, 1L)]
      ~f:(fun (now_ns, lease_ns) ->
        let before = view store "bounds" in
        check "CLAIM-DEADLINE-BOUNDS"
          (Result.is_error (Store.claim_task store ~plan_id:"fence" ~task_id:"bounds"
            ~worker:"same" ~now_ns ~lease_ns)
           && Poly.equal before (view store "bounds")));
    check "CLAIM-NEXT-EMPTY-WORKER"
      (Result.is_error (Store.claim_next store ~plan_id:"fence" ~worker:" "
        ~now_ns:1L ~lease_ns:1L));
    ignore (ok (Store.claim_task store ~plan_id:"fence" ~task_id:"bounds"
      ~worker:"same" ~now_ns:100L ~lease_ns:100L) : Store.claim);
    List.iter [("", 1, 101L); ("same", 0, 101L); ("same", -1, 101L); ("same", 1, -1L)]
      ~f:(fun (worker, expected_attempt, now_ns) ->
        let before = view store "bounds" in
        check "FINALIZER-INVALID-INPUT"
          (Result.is_error (Store.complete_task store ~plan_id:"fence" ~task_id:"bounds"
             ~worker ~expected_attempt ~result:"invalid" ~now_ns)
           && Result.is_error (Store.release_task store ~plan_id:"fence" ~task_id:"bounds"
             ~worker ~expected_attempt ~now_ns)
           && Poly.equal before (view store "bounds")));
    ignore (ok (Store.enqueue_job store ~id:"overflow" ~name:"fence/overflow"
      ~queue:"overflow" ~worker:"same" ~args:"{}" ~max_attempts:3 ~now_ns:0L) : Store.job_view);
    let job = some (ok (Store.claim_job store ~queue:"overflow" ~worker:"same"
      ~now_ns:Int64.(max_value - 10L) ~lease_ns:10L)) in
    let before = ok (Store.list_jobs store ~queue:None) in
    check "RETRY-DEADLINE-OVERFLOW"
      (Result.is_error (Store.complete_job store ~id_or_name:"overflow" ~worker:"same"
        ~expected_attempt:job.attempt ~outcome:(`Error "overflow")
        ~now_ns:Int64.(max_value - 9L))
       && Poly.equal before (ok (Store.list_jobs store ~queue:None))));

  with_fixture (fun path store ->
    setup store; create store "bridge";
    let request = { mapping_request with ooda_slice_id = "cross-path";
      sa_plan_id = Some "fence"; sa_task_id = Some "bridge" } in
    let mapping = ok (Store.ensure_bridge_mapping store request) in
    let first = ok (Store.claim_bridge_lease store ~mapping_id:mapping.id ~owner:"same"
      ~lease_id:"old" ~now_ns:100L ~lease_ns:100L) in
    check "BRIDGE-ORIGINAL-ATTEMPT-BOUND" (Option.equal Int.equal first.task_attempt (Some 1));
    ok (Store.release_task store ~plan_id:"fence" ~task_id:"bridge" ~worker:"same"
      ~expected_attempt:1 ~now_ns:110L);
    let generic = ok (Store.claim_task store ~plan_id:"fence" ~task_id:"bridge"
      ~worker:"same" ~now_ns:111L ~lease_ns:100L) in
    let before = view store "bridge" in
    check "BRIDGE-CANNOT-COMPLETE-REPLACEMENT-GENERIC-ATTEMPT"
      (Result.is_error (Store.complete_bridge_task store ~mapping_id:mapping.id ~owner:"same"
        ~lease_id:"old" ~fencing_token:first.fencing_token ~result:"stale" ~now_ns:112L)
       && Poly.equal before (view store "bridge"));
    ok (Store.release_task store ~plan_id:"fence" ~task_id:"bridge" ~worker:"same"
      ~expected_attempt:generic.attempt ~now_ns:113L);
    let current = ok (Store.claim_bridge_lease store ~mapping_id:mapping.id ~owner:"same"
      ~lease_id:"new" ~now_ns:200L ~lease_ns:100L) in
    check "BRIDGE-RELEASED-TASK-RECLAIM" (Option.equal Int.equal current.task_attempt (Some 3));
    check "BRIDGE-EXACT-EXPIRY-REJECTED"
      (Result.is_error (Store.complete_bridge_task store ~mapping_id:mapping.id ~owner:"same"
        ~lease_id:"new" ~fencing_token:current.fencing_token ~result:"expired" ~now_ns:300L));
    Store.close store;
    let legacy = Sqlite3.db_open path in
    (* Deliberate v6 fixture: no live store or source artifact is modified. *)
    check "LEGACY-FIXTURE"
      (Poly.equal (Sqlite3.exec legacy
        "ALTER TABLE sa_plan_bridge_lease DROP COLUMN task_attempt; UPDATE sa_plan_schema_meta SET version=6")
        Sqlite3.Rc.OK);
    ignore (Sqlite3.db_close legacy : bool);
    let migrated = ok (Store.open_db path) in
    Exn.protect ~finally:(fun () -> Store.close migrated) ~f:(fun () ->
      check "LEGACY-BINDING-UNKNOWN"
        (Option.is_none (some (ok (Store.find_bridge_lease migrated ~mapping_id:mapping.id))).task_attempt);
      check "LEGACY-CANNOT-INFER-COMPLETION-AUTHORITY"
        (Result.is_error (Store.complete_bridge_task migrated ~mapping_id:mapping.id ~owner:"same"
          ~lease_id:"new" ~fencing_token:current.fencing_token ~result:"unsafe upgrade" ~now_ns:250L));
      let fresh = ok (Store.claim_bridge_lease migrated ~mapping_id:mapping.id ~owner:"same"
        ~lease_id:"after-upgrade" ~now_ns:300L ~lease_ns:100L) in
      check "LEGACY-FRESH-CLAIM-BINDS"
        (Option.equal Int.equal fresh.task_attempt (Some 4)
         && Result.is_ok (Store.complete_bridge_task migrated ~mapping_id:mapping.id ~owner:"same"
           ~lease_id:"after-upgrade" ~fencing_token:fresh.fencing_token ~result:"fresh" ~now_ns:301L))));
  with_fixture (fun path store ->
    setup store; create store "blocked-parent";
    ok (Store.create_task store ~plan_id:"fence" ~id:"blocked-child" ~name:"fence/blocked-child"
      ~title:"blocked" ~parent_id:None ~dependencies:["blocked-parent"] ~priority:0 ~now_ns:0L);
    let mapping = ok (Store.ensure_bridge_mapping store
      { mapping_request with ooda_slice_id="blocked"; sa_plan_id=Some "fence";
        sa_task_id=Some "blocked-child" }) in
    check "BRIDGE-DEPENDENCY-GUARD"
      (Result.is_error (Store.claim_bridge_lease store ~mapping_id:mapping.id ~owner:"w"
         ~lease_id:"l" ~now_ns:100L ~lease_ns:10L)
       && Option.is_none (ok (Store.find_bridge_lease store ~mapping_id:mapping.id)));
    let parent = ok (Store.claim_task store ~plan_id:"fence" ~task_id:"blocked-parent"
      ~worker:"w" ~now_ns:100L ~lease_ns:10L) in
    ok (Store.complete_task store ~plan_id:"fence" ~task_id:"blocked-parent" ~worker:"w"
      ~expected_attempt:parent.attempt ~result:"done" ~now_ns:101L);
    let lease = ok (Store.claim_bridge_lease store ~mapping_id:mapping.id ~owner:"w"
      ~lease_id:"l" ~now_ns:102L ~lease_ns:10L) in
    check "BRIDGE-DEPENDENCY-RELEASES-CHILD" (Option.equal Int.equal lease.task_attempt (Some 1));
    let inject sql =
      (* Counter exhaustion fixtures only; the operational store is never opened. *)
      let db = Sqlite3.db_open path in
      Exn.protect ~finally:(fun () -> ignore (Sqlite3.db_close db : bool))
        ~f:(fun () -> check "COUNTER-FIXTURE" (Poly.equal (Sqlite3.exec db sql) Sqlite3.Rc.OK)) in
    inject "UPDATE sa_plan_bridge_lease SET fencing_token=9223372036854775807";
    let before = view store "blocked-child" in
    check "BRIDGE-FENCE-EXHAUSTION"
      (Result.is_error (Store.claim_bridge_lease store ~mapping_id:mapping.id ~owner:"w"
        ~lease_id:"overflow" ~now_ns:112L ~lease_ns:10L)
       && Poly.equal before (view store "blocked-child"));
    create store "max-attempt";
    inject (Printf.sprintf "UPDATE sa_plan_task SET attempt=%d WHERE id='max-attempt'" Stdlib.max_int);
    let before = view store "max-attempt" in
    check "TASK-ATTEMPT-EXHAUSTION"
      (Result.is_error (Store.claim_task store ~plan_id:"fence" ~task_id:"max-attempt"
        ~worker:"w" ~now_ns:100L ~lease_ns:10L)
       && Poly.equal before (view store "max-attempt"));
    ignore (ok (Store.enqueue_job store ~id:"max-job" ~name:"fence/max-job" ~queue:"max"
      ~worker:"w" ~args:"{}" ~max_attempts:3 ~now_ns:0L) : Store.job_view);
    inject (Printf.sprintf "UPDATE sa_plan_job SET attempt=%d WHERE id='max-job'" Stdlib.max_int);
    let before = ok (Store.list_jobs store ~queue:None) in
    check "JOB-ATTEMPT-EXHAUSTION"
      (Result.is_error (Store.claim_job store ~queue:"max" ~worker:"w" ~now_ns:100L ~lease_ns:10L)
       && Poly.equal before (ok (Store.list_jobs store ~queue:None))));

  with_fixture (fun path store ->
    setup store; create store "race";
    let original = ok (Store.claim_task store ~plan_id:"fence" ~task_id:"race"
      ~worker:"old" ~now_ns:100L ~lease_ns:10L) in
    let peer = ok (Store.open_db path) in
    Exn.protect ~finally:(fun () -> Store.close peer) ~f:(fun () ->
      let contender = Domain.spawn (fun () ->
        Store.claim_task peer ~plan_id:"fence" ~task_id:"race" ~worker:"b"
          ~now_ns:110L ~lease_ns:10L) in
      let local = Store.claim_task store ~plan_id:"fence" ~task_id:"race" ~worker:"a"
        ~now_ns:110L ~lease_ns:10L in
      let remote = Domain.join contender in
      check "TWO-CONNECTION-TAKEOVER-ONE-WINNER"
        (Bool.(Result.is_ok local <> Result.is_ok remote));
      let before = view store "race" in
      check "RACE-LOSER-AND-OLD-RECEIPT-CANNOT-COMPLETE"
        (Result.is_error (Store.complete_task store ~plan_id:"fence" ~task_id:"race"
          ~worker:"old" ~expected_attempt:original.attempt ~result:"stale" ~now_ns:111L)
         && Poly.equal before (view store "race"))));
  Printf.printf "fencing: %d passed, 0 failed; 729 bounded oracle traces\n%!" !tests

(* Controlled-action store mechanics. No approvals or process control are granted. *)
module Cancellation = struct
  let hex c = String.make 64 c
  let with_case run =
    let path = Stdlib.Filename.temp_file "uos-cancel-once-" ".sqlite3" in
    let store = ok (Store.open_db path) in
    Exn.protect ~finally:(fun () ->
      Store.close store;
      List.iter [path; path ^ "-wal"; path ^ "-shm"] ~f:(fun p ->
        if Stdlib.Sys.file_exists p then Stdlib.Sys.remove p))
      ~f:(fun () ->
        ok (Store.create_plan store ~id:"cancel-plan" ~name:"cancel-plan/tests"
          ~title:"isolated cancellation fixture" ~now_ns:1L);
        ok (Store.create_task store ~plan_id:"cancel-plan" ~id:"controller"
          ~name:"cancel-plan/controller" ~title:"controller" ~parent_id:None
          ~dependencies:[] ~priority:1 ~now_ns:1L);
        let mapping = ok (Store.ensure_bridge_mapping store
          { mapping_request with ooda_slice_id="cancel-once";
            idempotency_key="cancel-once";sa_plan_id=Some "cancel-plan";
            sa_task_id=Some "controller" }) in
        let lease = ok (Store.claim_bridge_lease store ~mapping_id:mapping.id
          ~owner:"controller" ~lease_id:"control-lease" ~now_ns:100L ~lease_ns:29_900L) in
        ignore (ok (Store.enqueue_job store ~id:"cancel-plan/job1" ~name:"cancel-plan/job1"
          ~queue:"cancel-target" ~worker:"job-worker" ~args:"{}" ~max_attempts:2 ~now_ns:1L)
          : Store.job_view);
        let job = some (ok (Store.claim_job store ~queue:"cancel-target" ~worker:"job-worker"
          ~now_ns:100L ~lease_ns:19_900L)) in
        let request : Store.job_cancellation = {
          mapping_id=mapping.id;effect_id=hex 'e';intent_sha256=hex 'a';
          owner="controller";lease_id="control-lease";fencing_token=lease.fencing_token;
          target_job_id=job.id;target_worker="job-worker";target_attempt=job.attempt;
          target_lease_until_ns=Option.value_exn job.lease_until_ns;
          reason="Operator requested cancellation";expires_at_ns=10_000L } in
        run path store request)
  let exec path sql =
    let db=Sqlite3.db_open path in
    Exn.protect ~finally:(fun () -> ignore (Sqlite3.db_close db : bool))
      ~f:(fun () -> require "CANCEL-FIXTURE-SQL" (Poly.equal (Sqlite3.exec db sql) Sqlite3.Rc.OK))
  let job store =
    List.find_exn (ok (Store.list_jobs store ~queue:None))
      ~f:(fun (j:Store.job_view) -> String.equal j.id "cancel-plan/job1")
  let receipt store request =
    ok (Store.find_bridge_command store ~mapping_id:request.Store.mapping_id
      ~command_id:("cancel-job:" ^ request.Store.effect_id))
  let no_effect store request =
    let current=job store in
    Poly.equal current.state Store.Job_executing
    && Option.is_none (receipt store request)
  let rejected store request =
    Result.is_error (Store.cancel_job_once store request ~now_ns:200L)

  let run () =
    let prior = !tests in
    with_case (fun path store request ->
      let first=ok (Store.cancel_job_once store request ~now_ns:200L) in
      let after=job store in
      check "CANCEL-EXACT-POSTCONDITION" (not first.replayed
        && Poly.equal after.state Store.Job_cancelled
        && String.equal after.worker "job-worker"
        && Option.is_none after.lease_owner && Option.is_none after.lease_until_ns
        && after.attempt=request.target_attempt);
      let payload=Yojson.Safe.from_string first.result in
      let field key=Yojson.Safe.Util.member key payload in
      check "CANCEL-TRUTHFUL-RESULT" (Poly.equal (field "job_lease_cleared") (`Bool true)
        && Poly.equal (field "process_quiesced") (`Bool false)
        && Poly.equal (field "task_cancelled") (`Bool false));
      let task=some (ok (Store.find_task store ~plan_id:"cancel-plan" ~id_or_name:"controller")) in
      check "CANCEL-TASK-UNCHANGED" (String.equal task.state "executing");
      let repeated=ok (Store.cancel_job_once store request ~now_ns:201L) in
      check "CANCEL-REPLAY" (repeated.replayed && String.equal repeated.result first.result
        && String.equal repeated.request_hash first.request_hash
        && Int64.equal repeated.recorded_at_ns 200L);
      check "CANCEL-WORKER-CANNOT-COMPLETE" (Result.is_error
        (Store.complete_job store ~id_or_name:request.target_job_id ~worker:"job-worker"
          ~expected_attempt:request.target_attempt ~outcome:(`Ok "late") ~now_ns:201L));
      Store.close store;
      let reopened=ok (Store.open_db path) in
      Exn.protect ~finally:(fun () -> Store.close reopened) ~f:(fun () ->
        let recovered=ok (Store.cancel_job_once reopened request ~now_ns:202L) in
        check "CANCEL-RESTART-RECONCILIATION" (recovered.replayed
          && String.equal recovered.result first.result)));

    with_case (fun _ store request ->
      let first=ok (Store.cancel_job_once store request ~now_ns:200L) in
      let variants=[
        {request with intent_sha256=hex 'b'};{request with owner="other"};
        {request with lease_id="other"};{request with fencing_token=2L};
        {request with target_job_id="cancel-plan/absent"};
        {request with target_worker="other"};{request with target_attempt=2};
        {request with target_lease_until_ns=20_001L};
        {request with reason="other"};{request with expires_at_ns=10_001L};
      ] in
      List.iter variants ~f:(fun changed ->
        check "CANCEL-CHANGED-REQUEST" (rejected store changed));
      check "CANCEL-RECEIPT-IMMUTABLE" (String.equal
        (Option.value_exn (receipt store request)).request_hash first.request_hash);
      check "CANCEL-DISTINCT-EFFECT-NOT-SUCCESS" (rejected store {request with effect_id=hex 'f'});
      check "CANCEL-EXPIRED-REPLAY" (Result.is_error
        (Store.cancel_job_once store request ~now_ns:10_000L)));

    with_case (fun _ store request ->
      List.iter [
        {request with target_job_id="cancel-plan2/job1"};
        {request with target_job_id="cancel-plan/"};
        {request with target_worker="other"};{request with target_attempt=2};
        {request with target_lease_until_ns=20_001L};
        {request with intent_sha256="invalid"};{request with effect_id="invalid"};
        {request with reason=""};{request with reason="x\000y"};
        {request with reason=String.make 257 'x'};{request with reason="\255"};
        {request with expires_at_ns=200L};{request with expires_at_ns=20_000L};
        {request with fencing_token=0L};{request with target_attempt=0};
      ] ~f:(fun changed ->
        check "CANCEL-INVALID-OR-MISMATCH" (rejected store changed);
        check "CANCEL-REFUSAL-NO-EFFECT" (no_effect store request)));

    with_case (fun _ store request ->
      ignore (ok (Store.cancel_job store ~id_or_name:request.target_job_id ~reason:"legacy" ~now_ns:200L)
        : Store.job_view);
      check "CANCEL-PRE-CANCELLED-NO-RECEIPT" (rejected store request && Option.is_none (receipt store request)));

    with_case (fun path store request ->
      exec path "CREATE TRIGGER reject_cancel_receipt BEFORE INSERT ON sa_plan_bridge_command WHEN NEW.command_id LIKE 'cancel-job:%' BEGIN SELECT RAISE(ABORT,'injected_receipt_failure'); END";
      check "CANCEL-RECEIPT-FAILURE-ROLLBACK" (rejected store request && no_effect store request);
      exec path "DROP TRIGGER reject_cancel_receipt";
      check "CANCEL-RETRY-AFTER-ROLLBACK" (Result.is_ok (Store.cancel_job_once store request ~now_ns:201L)));

    List.iter [
      "UPDATE sa_plan_bridge_lease SET fencing_token=2";
      "UPDATE sa_plan_bridge_lease SET expires_at_ns=199";
      "UPDATE sa_plan_task SET attempt=2";
      "UPDATE sa_plan_task SET worker='other'";
      "UPDATE sa_plan_task SET lease_until_ns=199";
      "UPDATE sa_plan_bridge_lease SET task_attempt=NULL";
    ] ~f:(fun sql -> with_case (fun path store request ->
      exec path sql;
      check "CANCEL-CURRENT-AUTHORITY" (rejected store request && no_effect store request)));

    List.iter [
      "UPDATE sa_plan_job SET state='executing'";
      "UPDATE sa_plan_job SET attempt=2";
      "UPDATE sa_plan_job SET result='different'";
      "UPDATE sa_plan_bridge_command SET result='fabricated'";
    ] ~f:(fun sql -> with_case (fun path store request ->
      ignore (ok (Store.cancel_job_once store request ~now_ns:200L) : Store.bridge_command_receipt);
      exec path sql;
      check "CANCEL-REPLAY-DRIFT" (rejected store request)));

    with_case (fun _ store request ->
      ignore (ok (Store.complete_job store ~id_or_name:request.target_job_id ~worker:"job-worker"
        ~expected_attempt:request.target_attempt ~outcome:(`Ok "finished") ~now_ns:150L) : Store.job_view);
      check "CANCEL-COMPLETED-TARGET-REFUSED" (rejected store request && Option.is_none (receipt store request)));

    with_case (fun path store request ->
      let gate=Atomic.make false in
      let worker () =
        let local=ok (Store.open_db path) in
        Exn.protect ~finally:(fun () -> Store.close local) ~f:(fun () ->
          while not (Atomic.get gate) do Domain.cpu_relax () done;
          Store.cancel_job_once local request ~now_ns:200L) in
      let a=Domain.spawn worker and b=Domain.spawn worker in
      Atomic.set gate true;
      let left=ok (Domain.join a) and right=ok (Domain.join b) in
      check "CANCEL-CONCURRENT-ONCE" (Bool.(left.replayed <> right.replayed)
        && String.equal left.result right.result
        && Poly.equal (job store).state Store.Job_cancelled));
    Printf.printf "cancellation store: %d passed, 0 failed\n%!" (!tests-prior)
end

let () = Cancellation.run ()

(* Regression for native sqlite3 wrapper lifetime across runtime-releasing calls.
   The unguarded baseline crashes under this concurrent-GC workload. *)
let () =
  let active=Atomic.make true in
  let collector=Domain.spawn (fun () ->
    while Atomic.get active do Gc.full_major (); Lifetime_unix.sleepf 0.002 done) in
  let observed=ref 0 in
  Exn.protect ~finally:(fun () -> Atomic.set active false; Domain.join collector)
    ~f:(fun () ->
      for _iteration=1 to 1000 do
        let path=Stdlib.Filename.temp_file "uos-sqlite-lifetime-" ".sqlite3" in
        let store=ok (Store.open_db path) in
        Exn.protect ~finally:(fun () ->
          Store.close store;
          List.iter [path;path^"-wal";path^"-shm"] ~f:(fun p ->
            if Stdlib.Sys.file_exists p then Stdlib.Sys.remove p))
          ~f:(fun () ->
            ok (Store.create_plan store ~id:"lifetime" ~name:"lifetime/probe"
              ~title:"probe" ~now_ns:1L);
            ok (Store.create_task store ~plan_id:"lifetime" ~id:"one" ~name:"lifetime/one"
              ~title:"one" ~parent_id:None ~dependencies:[] ~priority:0 ~now_ns:1L);
            let task=some (ok (Store.find_task store ~plan_id:"lifetime" ~id_or_name:"one")) in
            if String.equal task.id "one" && String.equal task.state "available"
               && task.attempt=0 then Int.incr observed)
      done);
  check "SQLITE-HANDLES-SURVIVE-CONCURRENT-GC" (!observed=1000);
  Printf.printf "lifetime: %d passed, 0 failed\n%!" !observed
