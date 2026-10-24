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


(* A running controller binds its bridge without a second task claim. *)
let () =
  let count = ref 0 in
  let check name passed = incr count; require ("BRIDGE-BIND-" ^ name) passed in
  let fixture run = with_fixture (fun path store ->
    setup store; create store "controller";
    let mapping = ok (Store.ensure_bridge_mapping store
      { mapping_request with ooda_slice_id="bound-controller";
        idempotency_key="bound-controller";sa_plan_id=Some "fence";
        sa_task_id=Some "controller" }) in
    run path store mapping) in
  let bind store (mapping : Store.bridge_mapping) owner attempt lease now duration =
    Store.bind_bridge_to_claimed_task store ~mapping_id:mapping.Store.id ~owner
      ~expected_attempt:attempt ~lease_id:lease ~now_ns:now ~lease_ns:duration in
  fixture (fun _path store mapping ->
    let before = view store "controller" in
    check "AVAILABLE-NOT-CLAIMED"
      (Result.is_error (bind store mapping "owner" 1 "bridge" 100L 100L)
       && Poly.equal before (view store "controller")
       && Option.is_none (ok (Store.find_bridge_lease store ~mapping_id:mapping.id)));
    let claim = ok (Store.claim_task store ~plan_id:"fence" ~task_id:"controller"
      ~worker:"owner" ~now_ns:100L ~lease_ns:1000L) in
    let before = view store "controller" in
    List.iter [
      "WRONG-OWNER","other",claim.attempt,"bridge",101L,99L;
      "STALE-ATTEMPT","owner",claim.attempt + 1,"bridge",101L,99L;
      "ZERO-ATTEMPT","owner",0,"bridge",101L,99L;
      "EMPTY-OWNER"," ",claim.attempt,"bridge",101L,99L;
      "EMPTY-LEASE","owner",claim.attempt," ",101L,99L;
      "NEGATIVE-TIME","owner",claim.attempt,"bridge",(-1L),99L;
      "ZERO-DURATION","owner",claim.attempt,"bridge",101L,0L;
      "NEGATIVE-DURATION","owner",claim.attempt,"bridge",101L,(-1L);
      "OVERFLOW","owner",claim.attempt,"bridge",Int64.max_value,1L;
      "OUTLIVES-TASK","owner",claim.attempt,"bridge",101L,1000L;
      "AT-TASK-EXPIRY","owner",claim.attempt,"bridge",1100L,1L
    ] ~f:(fun (name,owner,attempt,lease,now,duration) ->
      check name (Result.is_error (bind store mapping owner attempt lease now duration)
        && Poly.equal before (view store "controller")
        && Option.is_none (ok (Store.find_bridge_lease store ~mapping_id:mapping.id))));
    check "MISSING-MAPPING"
      (Result.is_error (Store.bind_bridge_to_claimed_task store ~mapping_id:"absent"
        ~owner:"owner" ~expected_attempt:claim.attempt ~lease_id:"b"
        ~now_ns:101L ~lease_ns:99L));
    let lease = ok (bind store mapping "owner" claim.attempt "bridge" 101L 99L) in
    check "FIRST-BIND-DOES-NOT-MUTATE-TASK"
      (Poly.equal before (view store "controller")
       && Poly.equal lease.task_attempt (Some claim.attempt) && Int64.equal lease.fencing_token 1L
       && Int64.equal lease.expires_at_ns 200L);
    check "LIVE-BRIDGE-REFUSED-EVEN-SAME-OWNER"
      (Result.is_error (bind store mapping "owner" claim.attempt "bridge" 102L 98L)
       && Poly.equal (Some lease) (ok (Store.find_bridge_lease store ~mapping_id:mapping.id))
       && Poly.equal before (view store "controller"));
    let next = ok (bind store mapping "owner" claim.attempt "bridge2" 200L 900L) in
    check "EXPIRED-BRIDGE-ADVANCES-FENCE-NOT-TASK"
      (Int64.equal next.fencing_token 2L && Int64.equal next.expires_at_ns 1100L
       && Poly.equal before (view store "controller"));
    ok (Store.release_task store ~plan_id:"fence" ~task_id:"controller"
      ~worker:"owner" ~expected_attempt:claim.attempt ~now_ns:201L);
    let _replacement = ok (Store.claim_task store ~plan_id:"fence" ~task_id:"controller"
      ~worker:"owner" ~now_ns:202L ~lease_ns:2000L) in
    let replacement_before = view store "controller" in
    check "OLD-ATTEMPT-REFUSED-AFTER-RECLAIM"
      (Result.is_error (bind store mapping "owner" claim.attempt "old" 1100L 1L)
       && Poly.equal replacement_before (view store "controller")
       && Poly.equal (Some next) (ok (Store.find_bridge_lease store ~mapping_id:mapping.id))));
  fixture (fun _path store mapping ->
    let claim = ok (Store.claim_task store ~plan_id:"fence" ~task_id:"controller"
      ~worker:"owner" ~now_ns:100L ~lease_ns:1000L) in
    let wrong = ok (Store.ensure_bridge_mapping store
      { mapping_request with domain=Documentation;ooda_slice_id="wrong-domain";
        idempotency_key="wrong-domain";sa_plan_id=Some "fence";sa_task_id=Some "controller" }) in
    check "WRONG-DOMAIN" (Result.is_error (bind store wrong "owner" claim.attempt "b" 101L 99L));
    ok (Store.complete_task store ~plan_id:"fence" ~task_id:"controller"
      ~worker:"owner" ~expected_attempt:claim.attempt ~result:"done" ~now_ns:101L);
    check "COMPLETED-TASK" (Result.is_error (bind store mapping "owner" claim.attempt "b" 102L 98L)));
  fixture (fun path store mapping ->
    let claim = ok (Store.claim_task store ~plan_id:"fence" ~task_id:"controller"
      ~worker:"owner" ~now_ns:100L ~lease_ns:1000L) in
    let before = view store "controller" in
    let peer = ok (Store.open_db path) in
    Exn.protect ~finally:(fun () -> Store.close peer) ~f:(fun () ->
      let other = Domain.spawn (fun () -> bind peer mapping "owner" claim.attempt "b" 101L 99L) in
      let local = bind store mapping "owner" claim.attempt "a" 101L 99L in
      let remote = Domain.join other in
      check "TWO-CONNECTIONS-EXACTLY-ONE-WINNER"
        (Bool.(Result.is_ok local <> Result.is_ok remote)
         && Poly.equal before (view store "controller"))));
  fixture (fun path store mapping ->
    let claim = ok (Store.claim_task store ~plan_id:"fence" ~task_id:"controller"
      ~worker:"owner" ~now_ns:100L ~lease_ns:1000L) in
    ignore (ok (bind store mapping "owner" claim.attempt "bridge" 101L 99L) : Store.bridge_lease);
    let inject sql =
      let db = Sqlite3.db_open path in
      Exn.protect ~finally:(fun () -> ignore (Sqlite3.db_close db : bool))
        ~f:(fun () -> if not (Poly.equal (Sqlite3.exec db sql) Sqlite3.Rc.OK)
          then failwith ("bridge bind test SQL failed: " ^ Sqlite3.errmsg db)) in
    List.iter [0L; Int64.max_value] ~f:(fun fence ->
      (* Corrupt only this disposable fixture; production CHECK stays enforced. *)
      inject ("PRAGMA ignore_check_constraints=ON; UPDATE sa_plan_bridge_lease SET fencing_token=" ^ Int64.to_string fence);
      let before_task = view store "controller" in
      let before_bridge = ok (Store.find_bridge_lease store ~mapping_id:mapping.id) in
      check "INVALID-OR-EXHAUSTED-FENCE"
        (Result.is_error (bind store mapping "owner" claim.attempt "next" 200L 100L)
         && Poly.equal before_task (view store "controller")
         && Poly.equal before_bridge (ok (Store.find_bridge_lease store ~mapping_id:mapping.id))));
    inject "UPDATE sa_plan_bridge_lease SET fencing_token=1";
    let before_task = view store "controller" in
    let before_bridge = ok (Store.find_bridge_lease store ~mapping_id:mapping.id) in
    inject "CREATE TRIGGER reject_bridge_bind BEFORE INSERT ON sa_plan_bridge_lease BEGIN SELECT RAISE(ABORT,'fixture_bridge_failure'); END";
    check "WRITE-FAILURE-PRESERVES-TASK-AND-PRIOR"
      (Result.is_error (bind store mapping "owner" claim.attempt "next" 200L 100L)
       && Poly.equal before_task (view store "controller")
       && Poly.equal before_bridge (ok (Store.find_bridge_lease store ~mapping_id:mapping.id))));
  Printf.printf "bridge bind: %d checks passed\n%!" !count


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
        let claim = ok (Store.claim_task store ~plan_id:"cancel-plan" ~task_id:"controller"
          ~worker:"controller" ~now_ns:100L ~lease_ns:29_900L) in
        let lease = ok (Store.bind_bridge_to_claimed_task store ~mapping_id:mapping.id
          ~owner:"controller" ~expected_attempt:claim.attempt ~lease_id:"control-lease"
          ~now_ns:100L ~lease_ns:29_900L) in
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

module Cancel_protocol = Sa_plan.Cancel_protocol

let cancellation_json (r : Store.job_cancellation) =
  let i n = `Intlit (Int64.to_string n) in
  `Assoc [
    "schema", `String "uos.sa-plan.cancel-job-request.v1";
    "mapping_id", `String r.mapping_id; "effect_id", `String r.effect_id;
    "intent_sha256", `String r.intent_sha256; "owner", `String r.owner;
    "lease_id", `String r.lease_id; "fencing_token", i r.fencing_token;
    "target_job_id", `String r.target_job_id; "target_worker", `String r.target_worker;
    "target_attempt", `Int r.target_attempt;
    "target_lease_until_ns", i r.target_lease_until_ns;
    "reason", `String r.reason; "expires_at_ns", i r.expires_at_ns
  ]

let () =
  Cancellation.with_case (fun path store request ->
    let query () = Store.lookup_job_cancellation store request ~now_ns:40_000L in
    check "CANCEL-LOOKUP-MISSING-NO-EFFECT"
      (Option.is_none (ok (query ())) && Cancellation.no_effect store request);
    let first=ok (Store.cancel_job_once store request ~now_ns:200L) in
    Cancellation.exec path "UPDATE sa_plan_task SET attempt=99,worker='replacement',lease_until_ns=0";
    Cancellation.exec path "UPDATE sa_plan_bridge_lease SET fencing_token=99,expires_at_ns=0";
    Cancellation.exec path "CREATE TRIGGER no_lookup_job_write BEFORE UPDATE ON sa_plan_job BEGIN SELECT RAISE(ABORT,'lookup cannot update job'); END";
    Cancellation.exec path "CREATE TRIGGER no_lookup_receipt_write BEFORE INSERT ON sa_plan_bridge_command BEGIN SELECT RAISE(ABORT,'lookup cannot insert receipt'); END";
    let historical=some (ok (query ())) in
    check "CANCEL-LOOKUP-EXPIRED-AUTHORITY-HISTORICAL-ONLY"
      (String.equal first.result historical.result
       && Int64.equal first.recorded_at_ns historical.recorded_at_ns
       && historical.replayed
       && Result.is_error (Store.cancel_job_once store request ~now_ns:40_000L));
    check "CANCEL-LOOKUP-CHANGED-INTENT-REFUSED"
      (Result.is_error (Store.lookup_job_cancellation store
        { request with intent_sha256=Cancellation.hex 'b' } ~now_ns:40_000L));
    check "CANCEL-LOOKUP-CHANGED-ORIGINAL-FENCE-REFUSED"
      (Result.is_error (Store.lookup_job_cancellation store
        { request with fencing_token=2L } ~now_ns:40_000L));
    check "CANCEL-LOOKUP-FUTURE-RECEIPT-REFUSED"
      (Result.is_error (Store.lookup_job_cancellation store request ~now_ns:199L));
    check "CANCEL-LOOKUP-NEGATIVE-CLOCK-REFUSED"
      (Result.is_error (Store.lookup_job_cancellation store request ~now_ns:(-1L))));
  Cancellation.with_case (fun path store request ->
    ignore (ok (Store.cancel_job_once store request ~now_ns:200L) : Store.bridge_command_receipt);
    Cancellation.exec path "UPDATE sa_plan_bridge_command SET result='fabricated'";
    check "CANCEL-LOOKUP-CORRUPT-RECEIPT-REFUSED"
      (Result.is_error (Store.lookup_job_cancellation store request ~now_ns:40_000L)));
  Cancellation.with_case (fun _ store request ->
    let raw=Yojson.Safe.to_string (cancellation_json request) in
    let query=ok (Cancel_protocol.decode Lookup raw) in
    let missing=ok (Cancel_protocol.execute store query ~now_ns:200L) in
    check "CANCEL-PROTOCOL-MISSING-IS-NOT-SUCCESS"
      (Poly.equal (Yojson.Safe.Util.member "found" missing) (`Bool false)
       && Cancellation.no_effect store request);
    let command=ok (Cancel_protocol.decode Cancel raw) in
    let first=ok (Cancel_protocol.execute store command ~now_ns:200L) in
    check "CANCEL-PROTOCOL-EXECUTE-TRUTHFUL"
      (Poly.equal (Yojson.Safe.Util.member "found" first) (`Bool true)
       && Poly.equal (Yojson.Safe.Util.member "historical" first) (`Bool false)
       && Poly.equal (Cancellation.job store).state Store.Job_cancelled);
    let past=ok (Cancel_protocol.execute store query ~now_ns:40_000L) in
    check "CANCEL-PROTOCOL-LOOKUP-HISTORICAL"
      (Poly.equal (Yojson.Safe.Util.member "historical" past) (`Bool true)
       && Poly.equal (Yojson.Safe.Util.member "process_quiesced"
          (Yojson.Safe.Util.member "result" (Yojson.Safe.Util.member "receipt" past))) (`Bool false)));
  Cancellation.with_case (fun _ _ request ->
    let fields=match cancellation_json request with `Assoc fields -> fields | _ -> assert false in
    let reject json = Result.is_error (Cancel_protocol.decode Cancel (Yojson.Safe.to_string json)) in
    List.iter fields ~f:(fun (name, _) ->
      check "CANCEL-PROTOCOL-MISSING-FIELD"
        (reject (`Assoc (List.filter fields ~f:(fun (k,_) -> not (String.equal k name)))));
      check "CANCEL-PROTOCOL-WRONG-TYPE"
        (reject (`Assoc (List.map fields ~f:(fun (k,v) -> k,(if String.equal k name then `Bool true else v)))));
      check "CANCEL-PROTOCOL-DUPLICATE-FIELD"
        (reject (`Assoc ((name, `Null)::fields))));
    List.iter [
      "now_ns", `Int 200; "db_path", `String "/tmp/other";
      "approved", `Bool true; "unused", `Null
    ] ~f:(fun extra -> check "CANCEL-PROTOCOL-UNKNOWN-FIELD" (reject (`Assoc (extra::fields))));
    List.iter [
      "fencing_token", `String "1";
      "target_attempt", `Float 1.0;
      "target_attempt", `Intlit "2147483648";
      "target_lease_until_ns", `Intlit "9223372036854775808";
      "schema", `String "wrong";
      "reason", `String "bad\ncontrol";
      "effect_id", `String (String.make 64 'G');
      "mapping_id", `String "../mapping"
    ] ~f:(fun (name,value) ->
      check "CANCEL-PROTOCOL-INVALID-VALUE"
        (reject (`Assoc (List.map fields ~f:(fun (k,v) -> k,(if String.equal k name then value else v))))));
    List.iter ["[]"; "null"; "{}junk"; String.make 8193 ' '; "\255"] ~f:(fun raw ->
      check "CANCEL-PROTOCOL-MALFORMED-BOUNDED"
        (Result.is_error (Cancel_protocol.decode Cancel raw))));
  Printf.printf "cancellation protocol checks included: %d total passed\n%!" !tests

(* Execute the actual CLI with isolated files, explicit DB, and a finite timeout.
   Neither fixture setup nor child execution touches the canonical live store. *)
let run_cancellation_child ~program ~arguments ~database ~input =
  let stdin_path=Stdlib.Filename.temp_file "uos-cancel-input-" ".json" in
  let stdout_path=Stdlib.Filename.temp_file "uos-cancel-output-" ".json" in
  let stderr_path=Stdlib.Filename.temp_file "uos-cancel-errors-" ".txt" in
  let all=[stdin_path;stdout_path;stderr_path] in
  Exn.protect ~finally:(fun () -> List.iter all ~f:(fun p ->
    if Stdlib.Sys.file_exists p then Stdlib.Sys.remove p)) ~f:(fun () ->
    Out_channel.write_all stdin_path ~data:input;
    let fd_in=Lifetime_unix.openfile stdin_path [O_RDONLY] 0 in
    let fd_out=Lifetime_unix.openfile stdout_path [O_WRONLY;O_TRUNC] 0 in
    let fd_err=Lifetime_unix.openfile stderr_path [O_WRONLY;O_TRUNC] 0 in
    let exe=if Filename.is_relative program then Filename.concat (Filename.dirname Stdlib.Sys.executable_name) program else program in
    let env=Lifetime_unix.environment () |> Array.to_list
      |> List.filter ~f:(fun s -> not (String.is_prefix s ~prefix:"UOS_SA_PLAN_DB="))
      |> fun xs -> Array.of_list (("UOS_SA_PLAN_DB="^database)::xs) in
    let pid=Exn.protect ~finally:(fun () ->
      List.iter [fd_in;fd_out;fd_err] ~f:Lifetime_unix.close)
      ~f:(fun () -> Lifetime_unix.create_process_env exe
        (Array.of_list (exe :: arguments)) env fd_in fd_out fd_err) in
    let deadline=Lifetime_unix.gettimeofday () +. 6.5 in
    let rec wait () =
      match Lifetime_unix.waitpid [WNOHANG] pid with
      | 0,_ ->
          if Float.(Lifetime_unix.gettimeofday () >= deadline) then begin
            Lifetime_unix.kill pid Stdlib.Sys.sigkill;
            ignore (Lifetime_unix.waitpid [] pid : int * Lifetime_unix.process_status);
            failwith "cancellation CLI fixture timed out"
          end else (Lifetime_unix.sleepf 0.01; wait ())
      | _,status -> status in
    let status=wait () in
    let output=In_channel.read_all stdout_path in
    let errors=In_channel.read_all stderr_path in
    if String.length output > 8192 || String.length errors > 32768 then
      failwith "cancellation CLI fixture output exceeded bounds";
    status,output,errors)

let run_cancellation_cli ~database ~verb ~input =
  run_cancellation_child ~program:"sa_plan_main.exe" ~arguments:["job";verb] ~database ~input

let () =
  Cancellation.with_case (fun path store request ->
    let now=Int64.of_float (Lifetime_unix.gettimeofday () *. 1_000_000_000.) in
    let expires=Int64.(now + 60_000_000_000L) in
    let target_lease=Int64.(now + 120_000_000_000L) in
    let control_lease=Int64.(now + 180_000_000_000L) in
    Cancellation.exec path (Printf.sprintf
      "UPDATE sa_plan_task SET lease_until_ns=%Ld; UPDATE sa_plan_bridge_lease SET expires_at_ns=%Ld; UPDATE sa_plan_job SET lease_until_ns=%Ld"
      control_lease control_lease target_lease);
    let request={ request with target_lease_until_ns=target_lease;expires_at_ns=expires } in
    let input=Yojson.Safe.to_string (cancellation_json request) in
    let status,output,_=run_cancellation_cli ~database:path ~verb:"cancel-once" ~input in
    check "CANCEL-REAL-CLI-SUCCEEDED" (Poly.equal status (Lifetime_unix.WEXITED 0));
    let json=Yojson.Safe.from_string output in
    check "CANCEL-REAL-CLI-OBSERVED-EFFECT"
      (Poly.equal (Cancellation.job store).state Store.Job_cancelled
       && Poly.equal (Yojson.Safe.Util.member "found" json) (`Bool true));
    let status,output,_=run_cancellation_cli ~database:path ~verb:"cancel-once" ~input in
    let replay=Yojson.Safe.from_string output in
    check "CANCEL-REAL-CLI-REPLAY"
      (Poly.equal status (Lifetime_unix.WEXITED 0)
       && Poly.equal (Yojson.Safe.Util.member "replayed"
           (Yojson.Safe.Util.member "receipt" replay)) (`Bool true));
    let status,output,_=run_cancellation_cli ~database:path ~verb:"cancellation-result" ~input in
    check "CANCEL-REAL-CLI-HISTORICAL-QUERY"
      (Poly.equal status (Lifetime_unix.WEXITED 0)
       && Poly.equal (Yojson.Safe.Util.member "historical" (Yojson.Safe.from_string output)) (`Bool true));
    let invalid=String.drop_suffix input 1 ^ ",\"now_ns\":200}" in
    let status,output,errors=run_cancellation_cli ~database:path ~verb:"cancel-once" ~input:invalid in
    check "CANCEL-REAL-CLI-CALLER-CLOCK-REFUSED"
      (not (Poly.equal status (Lifetime_unix.WEXITED 0))
       && String.is_empty output && not (String.is_substring errors ~substring:request.reason)));
  let path=Stdlib.Filename.temp_file "uos-cancel-missing-store-" ".sqlite3" in
  Stdlib.Sys.remove path;
  let status,_,_=run_cancellation_cli ~database:path ~verb:"cancel-once" ~input:"{}" in
  check "CANCEL-REAL-CLI-MALFORMED-DOES-NOT-CREATE-STORE"
    (not (Poly.equal status (Lifetime_unix.WEXITED 0)) && not (Stdlib.Sys.file_exists path))

let () = Cancellation.with_case (fun _ _ request ->
  let path=Stdlib.Filename.temp_file "uos-cancel-valid-missing-" ".sqlite3" in
  Stdlib.Sys.remove path;
  let input=Yojson.Safe.to_string (cancellation_json request) in
  let status,_,_=run_cancellation_cli ~database:path ~verb:"cancellation-result" ~input in
  check "CANCEL-REAL-CLI-VALID-INPUT-REQUIRES-EXISTING-STORE"
    (not (Poly.equal status (Lifetime_unix.WEXITED 0)) && not (Stdlib.Sys.file_exists path)))

let () = Cancellation.with_case (fun path store request ->
  let peer=ok (Store.open_db path) in
  let lock=Sqlite3.db_open path in
  Exn.protect ~finally:(fun () ->
    ignore (Sqlite3.exec lock "ROLLBACK" : Sqlite3.Rc.t);
    ignore (Sqlite3.db_close lock : bool); Store.close peer)
    ~f:(fun () ->
      require "CANCEL-CONTENTION-LOCK" (Poly.equal (Sqlite3.exec lock "BEGIN IMMEDIATE") Sqlite3.Rc.OK);
      let command=ok (Cancel_protocol.decode Cancel (Yojson.Safe.to_string (cancellation_json request))) in
      let now=Atomic.make 200L and started=Atomic.make false and observed=Atomic.make false in
      let worker=Domain.spawn (fun () ->
        Atomic.set started true;
        Cancel_protocol.execute_observed peer command ~observe_now:(fun () ->
          Atomic.set observed true; Atomic.get now)) in
      while not (Atomic.get started) do Lifetime_unix.sleepf 0.001 done;
      Lifetime_unix.sleepf 0.05;
      let premature=Atomic.get observed in
      Atomic.set now 40_000L;
      require "CANCEL-CONTENTION-UNLOCK" (Poly.equal (Sqlite3.exec lock "COMMIT") Sqlite3.Rc.OK);
      let outcome=Domain.join worker in
      check "CANCEL-CLOCK-OBSERVED-AFTER-LOCK" (not premature && Atomic.get observed);
      check "CANCEL-EXPIRY-DURING-LOCK-WAIT-REFUSED"
        (Result.is_error outcome && Cancellation.no_effect store request)))

let () = Cancellation.with_case (fun _ store request ->
  let command=ok (Cancel_protocol.decode Cancel (Yojson.Safe.to_string (cancellation_json request))) in
  check "CANCEL-CLOCK-OBSERVER-FAILURE-ROLLS-BACK"
    (Result.is_error (Cancel_protocol.execute_observed store command
       ~observe_now:(fun () -> failwith "test clock unavailable"))
     && Cancellation.no_effect store request);
  ignore (ok (Cancel_protocol.execute_observed store command ~observe_now:(fun () -> 200L))
    : Yojson.Safe.t);
  check "CANCEL-CLOCK-OBSERVER-RECOVERY" (Poly.equal (Cancellation.job store).state Store.Job_cancelled))

(* Existing-store opener: missing or obsolete stores never initialize/migrate. *)
let () =
  let path=Stdlib.Filename.temp_file "uos-existing-only-" ".sqlite3" in
  Exn.protect ~finally:(fun () -> if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path)
    ~f:(fun () ->
      check "CANCEL-EXISTING-EMPTY-REFUSED" (Result.is_error (Store.open_existing path));
      check "CANCEL-EXISTING-EMPTY-NO-DDL" (Int64.equal (Lifetime_unix.LargeFile.stat path).st_size 0L);
      Stdlib.Sys.remove path;
      check "CANCEL-EXISTING-MISSING-REFUSED" (Result.is_error (Store.open_existing path));
      check "CANCEL-EXISTING-NO-CREATE" (not (Stdlib.Sys.file_exists path)));
  Cancellation.with_case (fun path _ _ ->
    let reopened=ok (Store.open_existing path) in
    check "CANCEL-EXISTING-V7-OPEN" (Store.schema_version reopened=7);
    Store.close reopened;
    List.iter [6;8] ~f:(fun version ->
      Cancellation.exec path (Printf.sprintf "UPDATE sa_plan_schema_meta SET version=%d" version);
      check "CANCEL-EXISTING-NO-MIGRATION" (Result.is_error (Store.open_existing path)));
    Cancellation.exec path "UPDATE sa_plan_schema_meta SET version=7")

module Cancel_frame = Sa_plan.Cancel_frame

let with_frame_input raw run =
  let path=Stdlib.Filename.temp_file "uos-cancel-frame-" ".bin" in
  Exn.protect ~finally:(fun () -> if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path)
    ~f:(fun () ->
      Out_channel.write_all path ~data:raw;
      let ch=Stdlib.open_in_bin path in
      Exn.protect ~finally:(fun () -> Stdlib.close_in_noerr ch) ~f:(fun () -> run ch))

let framed_string raw =
  let n=String.length raw in
  let header=Stdlib.String.init 4 (fun i -> Stdlib.Char.chr ((n lsr ((3-i)*8)) land 255)) in
  header ^ raw

let cancel_envelope operation request =
  Yojson.Safe.to_string (`Assoc [
    "schema",`String "uos.telegram.cancel-transport.v1";
    "operation",`String operation;
    "request",cancellation_json request])

let frame_read raw = with_frame_input raw Cancel_frame.read_frame
let frame_json raw = Yojson.Safe.from_string (ok (frame_read raw))

let () =
  check "CANCEL-FRAME-EXACT" (Poly.equal (frame_read (framed_string "body")) (Ok "body"));
  List.iter ["";"x";"xxx";"\000\000\000\000";"\255\255\255\255";
      framed_string "body" ^ "trailer";
      framed_string "body" ^ framed_string "two";
      "\000\000\000\004abc";
      framed_string (String.make 16385 'x')] ~f:(fun bad ->
    check "CANCEL-FRAME-BAD-LENGTH-OR-TRAILING" (Result.is_error (frame_read bad)));
  Cancellation.with_case (fun _ store request ->
    let raw=cancel_envelope "cancel-once" request in
    check "CANCEL-FRAME-VALID-ENVELOPE" (Result.is_ok (Cancel_frame.decode raw));
    let fields=match Yojson.Safe.from_string raw with `Assoc xs->xs|_->assert false in
    let bad_fields=[
      ("extra",`Bool true)::fields;
      ("operation",`String "cancel-once")::fields;
      List.filter fields ~f:(fun (k,_)->not (String.equal k "operation"));
      List.Assoc.add fields ~equal:String.equal "operation" (`String "eval");
      List.Assoc.add fields ~equal:String.equal "request" (`String "{}");
      List.Assoc.add fields ~equal:String.equal "schema" (`String "future");
      List.Assoc.add fields ~equal:String.equal "request" (`Assoc (
        ("reason",`String "duplicate") :: (match cancellation_json request with `Assoc xs->xs|_->[])))] in
    List.iter bad_fields ~f:(fun xs ->
      check "CANCEL-FRAME-CLOSED-ENVELOPE" (Result.is_error (Cancel_frame.decode (Yojson.Safe.to_string (`Assoc xs)))));
    List.iter [String.make 16385 'x';"[]";"{";"\255";""] ~f:(fun bad ->
      check "CANCEL-FRAME-INVALID-BODY" (Result.is_error (Cancel_frame.decode bad)));
    check "CANCEL-FRAME-DECODE-NO-EFFECT" (Cancellation.no_effect store request));
  let rejection=Cancel_frame.response (Error "private secret/path must not leak") |> Yojson.Safe.to_string in
  check "CANCEL-FRAME-REDACTED" (not (String.is_substring rejection ~substring:"private")
    && Poly.equal (Yojson.Safe.Util.member "status" (Yojson.Safe.from_string rejection)) (`String "rejected"))

let live_cancel_request path request =
  let now=Int64.of_float (Lifetime_unix.gettimeofday () *. 1_000_000_000.) in
  let expires=Int64.(now+60_000_000_000L) in
  let target_lease=Int64.(now+120_000_000_000L) in
  let control=Int64.(now+180_000_000_000L) in
  Cancellation.exec path (Printf.sprintf
    "UPDATE sa_plan_task SET lease_until_ns=%Ld; UPDATE sa_plan_bridge_lease SET expires_at_ns=%Ld; UPDATE sa_plan_job SET lease_until_ns=%Ld"
    control control target_lease);
  {request with Store.target_lease_until_ns=target_lease;expires_at_ns=expires}

let run_cancel_worker path input =
  run_cancellation_child ~program:"sa_plan_cancel_worker.exe" ~arguments:[path] ~database:path ~input

let () =
  Cancellation.with_case (fun path store request ->
    let request=live_cancel_request path request in
    let call operation request =
      let status,output,errors=run_cancel_worker path (framed_string (cancel_envelope operation request)) in
      check "CANCEL-WORKER-FRAME-EXIT" (Poly.equal status (Lifetime_unix.WEXITED 0) && String.is_empty errors);
      frame_json output in
    let first=call "cancel-once" request in
    check "CANCEL-WORKER-ACTUAL-EFFECT" (Poly.equal (Cancellation.job store).state Store.Job_cancelled
      && Poly.equal (Yojson.Safe.Util.member "status" first) (`String "ok"));
    let recovered=call "cancellation-result" request in
    check "CANCEL-WORKER-EXACT-RECOVERY"
      (Poly.equal (Yojson.Safe.Util.member "historical" (Yojson.Safe.Util.member "result" recovered)) (`Bool true));
    let rejected=call "cancel-once" {request with reason="different request"} in
    check "CANCEL-WORKER-DOMAIN-REFUSAL-IS-TRANSPORT-SUCCESS"
      (Poly.equal (Yojson.Safe.Util.member "status" rejected) (`String "rejected")
       && Poly.equal (Cancellation.job store).state Store.Job_cancelled));
  Cancellation.with_case (fun path store request ->
    let before=Cancellation.job store in
    let status,out,_=run_cancel_worker path (framed_string (cancel_envelope "cancel-once" request)^"extra") in
    check "CANCEL-WORKER-TRAILER-BEFORE-EFFECT"
      (not (Poly.equal status (Lifetime_unix.WEXITED 0)) && String.is_empty out
       && Poly.equal before (Cancellation.job store));
    let status,out,_=run_cancel_worker path (framed_string "{}") in
    check "CANCEL-WORKER-BAD-ENVELOPE"
      (Poly.equal status (Lifetime_unix.WEXITED 0)
       && Poly.equal (Yojson.Safe.Util.member "status" (frame_json out)) (`String "rejected")
       && Cancellation.no_effect store request));
  Cancellation.with_case (fun _ _ request ->
    let missing=Stdlib.Filename.temp_file "uos-cancel-worker-missing-" ".sqlite3" in
    Stdlib.Sys.remove missing;
    let status,out,_=run_cancel_worker missing (framed_string (cancel_envelope "cancellation-result" request)) in
    check "CANCEL-WORKER-MISSING-STORE-NOT-CREATED"
      (Poly.equal status (Lifetime_unix.WEXITED 0) && not (Stdlib.Sys.file_exists missing)
       && Poly.equal (Yojson.Safe.Util.member "status" (frame_json out)) (`String "rejected")));
  Printf.printf "framed cancellation checks included: %d total passed\n%!" !tests

(* Real BEAM transport over a protected isolated fixture. The verification
   harness supplies the candidate transport directory; absence fails closed. *)
let () =
  let dir=match Stdlib.Sys.getenv_opt "UOS_CANCEL_TRANSPORT_TEST_DIR" with
    | Some path -> path | None -> failwith "cancel transport fixture is required" in
  let gleam_root=match Stdlib.Sys.getenv_opt "UOS_CANCEL_GLEAM_TEST_ROOT" with
    | Some path -> path | None -> failwith "Gleam transport fixture is required" in
  let bin s = "<<" ^ String.concat ~sep:"," (List.map (String.to_list s)
      ~f:(fun c -> Int.to_string (Char.to_int c))) ^ ">>" in
  let sha path = Digestif.SHA256.(to_hex (digest_string (In_channel.read_all path))) in
  let guardian=Filename.concat dir "guardian.exe" in
  let worker=Filename.concat dir "worker.exe" in
  let guardian_sha=sha guardian and worker_sha=sha worker in
  let call path body hash =
    let code=Printf.sprintf
      "code:add_paths(filelib:wildcard(%S)),code:add_patha(%S),code:add_patha(%S), C='cepaf_gleam@harness@telegram_store_transport':reviewed_local_configuration(%s,%s,%s,%s,%s),R='cepaf_gleam@harness@telegram_store_transport':exchange(C,%s), case R of {ok,B}->io:put_chars(B),halt(0); _->io:put_chars(<<\"transport_not_confirmed\">>),halt(3) end."
      (Filename.concat gleam_root "lib/*/ebin") (Filename.concat gleam_root "build/ebin") dir (bin guardian) (bin guardian_sha) (bin worker) (bin hash) (bin path) (bin body) in
    run_cancellation_child
      ~program:"/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl"
      ~arguments:["+S";"2:2";"+A";"2";"-noshell";"-eval";code]
      ~database:path ~input:"" in
  Cancellation.with_case (fun path store request ->
    let request=live_cancel_request path request in
    let body=cancel_envelope "cancel-once" request in
    let status,_,_=call path body (String.make 64 '0') in
    check "CANCEL-BEAM-PIN-REFUSES-BEFORE-EFFECT"
      (not (Poly.equal status (Lifetime_unix.WEXITED 0)) && Cancellation.no_effect store request);
    let status,out,_=call path body worker_sha in
    check "CANCEL-BEAM-GUARDIAN-WORKER-REAL-EFFECT"
      (Poly.equal status (Lifetime_unix.WEXITED 0)
       && Poly.equal (Yojson.Safe.Util.member "status" (Yojson.Safe.from_string out)) (`String "ok")
       && Poly.equal (Cancellation.job store).state Store.Job_cancelled);
    let status,out,_=call path (cancel_envelope "cancellation-result" request) worker_sha in
    check "CANCEL-BEAM-READONLY-RECOVERY"
      (Poly.equal status (Lifetime_unix.WEXITED 0)
       && Poly.equal (Yojson.Safe.Util.member "historical" (Yojson.Safe.Util.member "result" (Yojson.Safe.from_string out))) (`Bool true));
    let status,out,_=call path (cancel_envelope "cancel-once" {request with reason="altered"}) worker_sha in
    check "CANCEL-BEAM-DOMAIN-REJECT-PRESERVED"
      (Poly.equal status (Lifetime_unix.WEXITED 0)
       && Poly.equal (Yojson.Safe.Util.member "status" (Yojson.Safe.from_string out)) (`String "rejected")));
  Printf.printf "native plus actual BEAM transport: %d checks passed\n%!" !tests

(* End-to-end signed fixture: real Ed25519 verification, exact capped request,
   strict response validation, pinned guardian/worker and isolated Sa-plan DB.
   Fixture keys and clocks are test inputs; no live signer or Telegram claim. *)
let () =
  let dir=match Stdlib.Sys.getenv_opt "UOS_CANCEL_TRANSPORT_TEST_DIR" with
    | Some p -> p | None -> failwith "cancel transport fixture is required" in
  let gleam_root=match Stdlib.Sys.getenv_opt "UOS_CANCEL_GLEAM_TEST_ROOT" with
    | Some p -> p | None -> failwith "signed Gleam fixture is required" in
  let bin s = "<<" ^ String.concat ~sep:"," (List.map (String.to_list s)
    ~f:(fun c -> Int.to_string (Char.to_int c))) ^ ">>" in
  let sha p=Digestif.SHA256.(to_hex (digest_string (In_channel.read_all p))) in
  let guardian=Filename.concat dir "guardian.exe" in
  let worker=Filename.concat dir "worker.exe" in
  Cancellation.with_case (fun path store request ->
    let request=live_cancel_request path request in
    let code=Printf.sprintf
      "code:add_paths(filelib:wildcard(%S)),code:add_patha(%S), C='cepaf_gleam@harness@telegram_store_transport':reviewed_local_configuration(%s,%s,%s,%s,%s), R=telegram_cancellation_test:run_native(C,%s,%Ld,%Ld,%s),io:put_chars(R),halt(0)."
      (Filename.concat gleam_root "lib/*/ebin") (Filename.concat gleam_root "build/ebin")
      (bin guardian) (bin (sha guardian)) (bin worker) (bin (sha worker)) (bin path)
      (bin request.mapping_id) request.fencing_token request.target_lease_until_ns (bin (sha worker)) in
    let status,out,errors=run_cancellation_child
      ~program:"/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl"
      ~arguments:["+S";"2:2";"+A";"2";"-noshell";"-eval";code]
      ~database:path ~input:"" in
    check "CANCEL-SIGNED-GLEAM-NATIVE-EXIT"
      (Poly.equal status (Lifetime_unix.WEXITED 0) && String.is_empty errors);
    let result=Yojson.Safe.from_string out in
    let raw=Yojson.Safe.Util.member "request_json" result |> Yojson.Safe.Util.to_string in
    let query=ok (Cancel_protocol.decode Lookup raw) in
    let persisted=ok (Cancel_protocol.execute store query ~now_ns:Int64.max_value) in
    let native_receipt=Yojson.Safe.Util.member "receipt" persisted in
    check "CANCEL-SIGNED-GLEAM-NATIVE-EXACT-HASH"
      (Poly.equal (Yojson.Safe.Util.member "request_hash" result)
        (Yojson.Safe.Util.member "request_hash" native_receipt));
    check "CANCEL-SIGNED-GLEAM-NATIVE-HISTORICAL-EFFECT"
      (Poly.equal (Cancellation.job store).state Store.Job_cancelled
       && Yojson.Safe.Util.to_bool (Yojson.Safe.Util.member "historical" persisted)
       && String.equal (Yojson.Safe.Util.to_string (Yojson.Safe.Util.member "status" result)) "passed"));
  Printf.printf "signed approval through native worker: %d checks passed\n%!" !tests

(* A separate BEAM incarnation recovers an effect after the first incarnation
   deliberately halts before writing any Telegram result/outbox row. *)
let () =
  let required name=match Stdlib.Sys.getenv_opt name with
    | Some p -> p | None -> failwith ("missing fixture " ^ name) in
  let dir=required "UOS_CANCEL_TRANSPORT_TEST_DIR" in
  let gleam_root=required "UOS_CANCEL_GLEAM_TEST_ROOT" in
  let bin s="<<" ^ String.concat ~sep:"," (List.map (String.to_list s)
    ~f:(fun c -> Int.to_string (Char.to_int c))) ^ ">>" in
  let sha p=Digestif.SHA256.(to_hex (digest_string (In_channel.read_all p))) in
  let guardian=Filename.concat dir "guardian.exe" and worker=Filename.concat dir "worker.exe" in
  Cancellation.with_case (fun path store request ->
    let request=live_cancel_request path request in
    let tg_dir=path ^ ".telegram-dir" in
    Lifetime_unix.mkdir tg_dir 0o700;
    let tg_path=Filename.concat tg_dir "telegram.sqlite3" in
    Exn.protect ~finally:(fun () ->
      List.iter [tg_path;tg_path ^ "-wal";tg_path ^ "-shm";tg_path ^ ".process_lock"] ~f:(fun p ->
        if Stdlib.Sys.file_exists p then Stdlib.Sys.remove p);
      Lifetime_unix.rmdir tg_dir) ~f:(fun () ->
      let prefix=Printf.sprintf
        "code:add_paths(filelib:wildcard(%S)),code:add_patha(%S),C='cepaf_gleam@harness@telegram_store_transport':reviewed_local_configuration(%s,%s,%s,%s,%s),"
        (Filename.concat gleam_root "lib/*/ebin") (Filename.concat gleam_root "build/ebin")
        (bin guardian) (bin (sha guardian)) (bin worker) (bin (sha worker)) (bin path) in
      let run suffix=run_cancellation_child
        ~program:"/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl"
        ~arguments:["+S";"2:2";"+A";"2";"-noshell";"-eval";prefix ^ suffix]
        ~database:path ~input:"" in
      let first=Printf.sprintf
        "R=telegram_cancellation_record_test:execute_without_reply(C,%s,%s,%Ld,%Ld,%s),io:put_chars(R),erlang:halt(77)."
        (bin tg_path) (bin request.mapping_id) request.fencing_token
        request.target_lease_until_ns (bin (sha worker)) in
      let status,out,errors=run first in
      if not (Poly.equal status (Lifetime_unix.WEXITED 77)) then
        Printf.eprintf "signed durable first child stdout=%s stderr=%s\n%!" out errors;
      check "CANCEL-DURABLE-EFFECT-BEFORE-ABNORMAL-BEAM-EXIT"
        (Poly.equal status (Lifetime_unix.WEXITED 77)
         && String.equal out "effect_committed_reply_absent"
         && Poly.equal (Cancellation.job store).state Store.Job_cancelled);
      Cancellation.exec path "UPDATE sa_plan_bridge_lease SET expires_at_ns=0,fencing_token=99";
      let second=Printf.sprintf
        "R=telegram_cancellation_record_test:recover_and_reply(C,%s),io:put_chars(R),halt(0)." (bin tg_path) in
      let status,out,_=run second in
      check "CANCEL-DURABLE-FRESH-BEAM-HISTORICAL-LOOKUP-AND-OUTBOX"
        (Poly.equal status (Lifetime_unix.WEXITED 0)
         && String.equal out "Cancellation recorded: the job lease was revoked. Worker termination is not confirmed."
         && Poly.equal (Cancellation.job store).state Store.Job_cancelled)));
  Printf.printf "durable cancellation restart: %d checks passed\n%!" !tests

module Bridge_protocol = Sa_plan.Bridge_protocol
let bridge_request (mapping : Store.bridge_mapping) expiry = `Assoc [
  "schema",`String "uos.sa-plan.bridge-bind-request.v1";
  "mapping_id",`String mapping.id; "plan_id",`String "fence";
  "task_id",`String "controller"; "owner",`String "owner";
  "task_attempt",`Int 1; "lease_id",`String "runtime-bridge";
  "expires_at_ns",`Intlit (Int64.to_string expiry)]
let bridge_envelope operation request = Yojson.Safe.to_string (`Assoc [
  "schema",`String "uos.telegram.cancel-transport.v1";
  "operation",`String operation; "request",request])
let with_bridge_protocol run = with_fixture (fun path store ->
  setup store; create store "controller";
  let mapping=ok (Store.ensure_bridge_mapping store {mapping_request with
    ooda_slice_id="bridge-protocol";idempotency_key="bridge-protocol";
    sa_plan_id=Some "fence";sa_task_id=Some "controller"}) in
  ignore (ok (Store.claim_task store ~plan_id:"fence" ~task_id:"controller"
    ~worker:"owner" ~now_ns:100L ~lease_ns:1_000_000_000_000L) : Store.claim);
  run path store mapping)
let () = with_bridge_protocol (fun _path store mapping ->
  let request=bridge_request mapping 500L in
  let raw=Yojson.Safe.to_string request in
  let fields=match request with `Assoc xs->xs|_->assert false in
  List.iter ["01";"1e0";"+1";"1.0"] ~f:(fun number ->
    let malformed=String.substr_replace_all raw ~pattern:"\"task_attempt\":1" ~with_:("\"task_attempt\":" ^ number) in
    check "BRIDGE-PROTOCOL-NONCANONICAL-INTEGER"
      (Result.is_error (Bridge_protocol.decode Bind malformed));
    let frame=bridge_envelope "bind-controller-bridge" request in
    let malformed=String.substr_replace_all frame ~pattern:"\"task_attempt\":1" ~with_:("\"task_attempt\":" ^ number) in
    check "BRIDGE-FRAME-NONCANONICAL-INTEGER"
      (Result.is_error (Cancel_frame.decode malformed)));

  let reject value=Result.is_error (Bridge_protocol.decode Bind (Yojson.Safe.to_string value)) in
  List.iter fields ~f:(fun (name,value)->
    check "BRIDGE-PROTOCOL-DUPLICATE-REFUSED" (reject (`Assoc ((name,value)::fields)));
    check "BRIDGE-PROTOCOL-MISSING-REFUSED"
      (reject (`Assoc (List.filter fields ~f:(fun (key,_)->not (String.equal key name))))));
  List.iter [
    "schema",`String "future"; "owner",`String "owner\nprivate";
    "owner",`String "../owner"; "mapping_id",`String "";
    "lease_id",`String (String.make 241 'x');
    "task_attempt",`Float 1.; "task_attempt",`String "1";
    "task_attempt",`Int 0; "task_attempt",`Intlit "2147483648";
    "expires_at_ns",`Int 0; "expires_at_ns",`Intlit "9223372036854775808";
    "expires_at_ns",`String "500"; "extra",`Bool true
  ] ~f:(fun (key,value)->check "BRIDGE-PROTOCOL-STRICT-FIELDS"
    (reject (`Assoc (List.Assoc.add fields ~equal:String.equal key value))));
  List.iter ["";"[]";"{";"\255";String.make 4097 'x'] ~f:(fun invalid->
    check "BRIDGE-PROTOCOL-BOUNDS" (Result.is_error (Bridge_protocol.decode Bind invalid)));
  let command=ok (Bridge_protocol.decode Bind raw) in
  let lookup=ok (Bridge_protocol.decode Lookup raw) in
  let before=view store "controller" in
  let absent=ok (Bridge_protocol.execute store lookup ~now_ns:101L) in
  check "BRIDGE-PROTOCOL-ABSENT-IS-READONLY"
    (Poly.equal (Yojson.Safe.Util.member "found" absent) (`Bool false)
     && Poly.equal before (view store "controller")
     && Option.is_none (ok (Store.find_bridge_lease store ~mapping_id:mapping.id)));
  List.iter ["plan_id",`String "wrong";"task_id",`String "wrong";
    "owner",`String "wrong";"task_attempt",`Int 2;
    "expires_at_ns",`Intlit "300000000102"] ~f:(fun (key,value)->
      let invalid=ok (Bridge_protocol.decode Bind (Yojson.Safe.to_string
        (`Assoc (List.Assoc.add fields ~equal:String.equal key value)))) in
      check "BRIDGE-PROTOCOL-CONTEXT-REFUSED"
        (Result.is_error (Bridge_protocol.execute store invalid ~now_ns:101L)
         && Option.is_none (ok (Store.find_bridge_lease store ~mapping_id:mapping.id))));
  check "BRIDGE-PROTOCOL-CLOCK-FAILURE"
    (Result.is_error (Bridge_protocol.execute_observed store command
      ~observe_now:(fun ()->failwith "private clock detail"))
     && Option.is_none (ok (Store.find_bridge_lease store ~mapping_id:mapping.id)));
  let bound=ok (Bridge_protocol.execute_observed store command ~observe_now:(fun ()->101L)) in
  let saved=ok (Store.find_bridge_lease store ~mapping_id:mapping.id) in
  check "BRIDGE-PROTOCOL-BOUND-EXACT-UNCHANGED-TASK"
    (Poly.equal (Yojson.Safe.Util.member "found" bound) (`Bool true)
     && Poly.equal (Yojson.Safe.Util.member "historical" bound) (`Bool false)
     && (Poly.equal (Yojson.Safe.Util.member "observed_at_ns" bound) (`Intlit "101")
       || Poly.equal (Yojson.Safe.Util.member "observed_at_ns" bound) (`Int 101))
     && Poly.equal before (view store "controller"));
  check "BRIDGE-PROTOCOL-LIVE-RETRY-REJECTS"
    (Result.is_error (Bridge_protocol.execute store command ~now_ns:102L)
     && Poly.equal saved (ok (Store.find_bridge_lease store ~mapping_id:mapping.id)));
  let expired=ok (Bridge_protocol.execute store lookup ~now_ns:1000L) in
  check "BRIDGE-PROTOCOL-EXPIRED-HISTORY"
    (Poly.equal (Yojson.Safe.Util.member "historical" expired) (`Bool true)
     && Poly.equal saved (ok (Store.find_bridge_lease store ~mapping_id:mapping.id)));
  List.iter ["owner",`String "wrong";"task_attempt",`Int 2;
    "lease_id",`String "wrong";"expires_at_ns",`Int 501] ~f:(fun (key,value)->
      let invalid=ok (Bridge_protocol.decode Lookup (Yojson.Safe.to_string
        (`Assoc (List.Assoc.add fields ~equal:String.equal key value)))) in
      check "BRIDGE-PROTOCOL-LOOKUP-EXACT-OR-REJECT"
        (Result.is_error (Bridge_protocol.execute store invalid ~now_ns:1000L)));
  check "BRIDGE-PROTOCOL-FRAME-ACCEPTS-CLOSED-OPERATION"
    (Result.is_ok (Cancel_frame.decode (bridge_envelope "bind-controller-bridge" request))
     && Result.is_ok (Cancel_frame.decode (bridge_envelope "controller-bridge-result" request))))
let () = with_bridge_protocol (fun path store mapping ->
  let peer=ok (Store.open_db path) in
  let lock=Sqlite3.db_open path in
  Exn.protect ~finally:(fun ()->
    ignore (Sqlite3.exec lock "ROLLBACK" : Sqlite3.Rc.t);
    ignore (Sqlite3.db_close lock : bool);Store.close peer)
    ~f:(fun ()->
      require "BRIDGE-CONTENTION-LOCK" (Poly.equal (Sqlite3.exec lock "BEGIN IMMEDIATE") Sqlite3.Rc.OK);
      let command=ok (Bridge_protocol.decode Bind (Yojson.Safe.to_string (bridge_request mapping 500L))) in
      let now=Atomic.make 101L and started=Atomic.make false and observed=Atomic.make false in
      let worker=Domain.spawn (fun ()->Atomic.set started true;
        Bridge_protocol.execute_observed peer command ~observe_now:(fun ()->
          Atomic.set observed true;Atomic.get now)) in
      while not (Atomic.get started) do Lifetime_unix.sleepf 0.001 done;
      Lifetime_unix.sleepf 0.05;
      let premature=Atomic.get observed in
      Atomic.set now 500L;
      require "BRIDGE-CONTENTION-UNLOCK" (Poly.equal (Sqlite3.exec lock "COMMIT") Sqlite3.Rc.OK);
      let outcome=Domain.join worker in
      check "BRIDGE-CLOCK-AFTER-LOCK" (not premature && Atomic.get observed);
      check "BRIDGE-EXPIRED-IN-LOCK-WAIT-REFUSED"
        (Result.is_error outcome && Option.is_none (ok (Store.find_bridge_lease store ~mapping_id:mapping.id)))))
let () = with_bridge_protocol (fun path store mapping ->
  let now=Int64.of_float (Lifetime_unix.gettimeofday () *. 1_000_000_000.) in
  let expiry=Int64.(now+60_000_000_000L) in
  Cancellation.exec path ("UPDATE sa_plan_task SET lease_until_ns=" ^ Int64.to_string Int64.(now+120_000_000_000L));
  let before=view store "controller" in
  let dir=Stdlib.Sys.getenv "UOS_CANCEL_TRANSPORT_TEST_DIR" in
  let root=Stdlib.Sys.getenv "UOS_CANCEL_GLEAM_TEST_ROOT" in
  let bin s="<<" ^ String.concat ~sep:"," (List.map (String.to_list s) ~f:(fun c->Int.to_string (Char.to_int c))) ^ ">>" in
  let sha p=Digestif.SHA256.(to_hex (digest_string (In_channel.read_all p))) in
  let guardian=Filename.concat dir "guardian.exe" and native=Filename.concat dir "worker.exe" in
  let code=Printf.sprintf
    "code:add_paths(filelib:wildcard(%S)),code:add_patha(%S),C='cepaf_gleam@harness@telegram_store_transport':reviewed_local_configuration(%s,%s,%s,%s,%s),R=telegram_bridge_test:run_native(C,%s,%Ld),io:put_chars(R),halt(0)."
    (Filename.concat root "lib/*/ebin") (Filename.concat root "build/ebin")
    (bin guardian) (bin (sha guardian)) (bin native) (bin (sha native)) (bin path)
    (bin mapping.id) expiry in
  let status,out,errors=run_cancellation_child
    ~program:"/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl"
    ~arguments:["+S";"2:2";"+A";"2";"-noshell";"-eval";code] ~database:path ~input:"" in
  check "BRIDGE-GLEAM-NATIVE-ROUNDTRIP"
    (Poly.equal status (Lifetime_unix.WEXITED 0) && String.is_empty errors
     && String.equal out "bridge_bound_and_reconciled");
  check "BRIDGE-GLEAM-NATIVE-PRESERVES-CONTROLLER"
    (Poly.equal before (view store "controller")
     && match ok (Store.find_bridge_lease store ~mapping_id:mapping.id) with
       | Some lease -> Int64.equal lease.expires_at_ns expiry
          && Int64.equal lease.fencing_token 1L && Poly.equal lease.task_attempt (Some 1)
       | None -> false))

let () = with_bridge_protocol (fun path store mapping ->
  let now=Int64.of_float (Lifetime_unix.gettimeofday () *. 1_000_000_000.) in
  let expiry=Int64.(now+60_000_000_000L) in
  Cancellation.exec path ("UPDATE sa_plan_task SET lease_until_ns=" ^ Int64.to_string Int64.(now+120_000_000_000L));
  let before=view store "controller" in
  let dir=Stdlib.Sys.getenv "UOS_CANCEL_TRANSPORT_TEST_DIR" in
  let root=Stdlib.Sys.getenv "UOS_CANCEL_GLEAM_TEST_ROOT" in
  let profile_dir=path ^ ".profile" in
  Core_unix.mkdir profile_dir ~perm:0o700;
  Exn.protect ~finally:(fun ()->
    let file=Filename.concat profile_dir "profile.json" in
    if Stdlib.Sys.file_exists file then Stdlib.Sys.remove file;
    Core_unix.rmdir profile_dir)
    ~f:(fun ()->
      let bin s="<<" ^ String.concat ~sep:"," (List.map (String.to_list s) ~f:(fun c->Int.to_string (Char.to_int c))) ^ ">>" in
      let sha p=Digestif.SHA256.(to_hex (digest_string (In_channel.read_all p))) in
      let guardian=Filename.concat dir "guardian.exe" and native=Filename.concat dir "worker.exe" in
      let prefix=Printf.sprintf "code:add_paths(filelib:wildcard(%S)),code:add_patha(%S),"
        (Filename.concat root "lib/*/ebin") (Filename.concat root "build/ebin") in
      let run code=run_cancellation_child
        ~program:"/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl"
        ~arguments:["+S";"2:2";"+A";"2";"-noshell";"-eval";prefix ^ code] ~database:path ~input:"" in
      let code=Printf.sprintf
        "D=telegram_action_profile_test:persist_and_bind(%s,%s,%Ld,%s,%s,%s,%s,%s,%Ld),io:put_chars(D),halt(77)."
        (bin profile_dir) (bin mapping.id) expiry (bin guardian) (bin (sha guardian))
        (bin native) (bin (sha native)) (bin path) Int64.(now/1_000_000L) in
      let status,digest,errors=run code in
      require "PROFILE-PERSIST-BIND-PROCESS-EXIT"
        (Poly.equal status (Lifetime_unix.WEXITED 77) && String.is_empty errors
         && String.length digest=64 && String.for_all digest ~f:(fun c->
           Char.is_digit c || (Char.(c >= 'a') && Char.(c <= 'f'))));
      let persisted=In_channel.read_all (Filename.concat profile_dir "profile.json") in
      let saved=ok (Store.find_bridge_lease store ~mapping_id:mapping.id) in
      let status,out,errors=run (Printf.sprintf
        "R=telegram_action_profile_test:recover_lookup(%s,%s),io:put_chars(R),halt(0)."
        (bin profile_dir) (bin digest)) in
      check "PROFILE-SECOND-BEAM-EXACT-RECOVERY"
        (Poly.equal status (Lifetime_unix.WEXITED 0) && String.is_empty errors
         && String.equal out "profile_reloaded_exact_bridge");
      check "PROFILE-RECOVERY-NO-RENEWAL"
        (Poly.equal before (view store "controller")
         && Poly.equal saved (ok (Store.find_bridge_lease store ~mapping_id:mapping.id))
         && String.equal persisted (In_channel.read_all (Filename.concat profile_dir "profile.json"))
         && match saved with Some lease->Int64.equal lease.fencing_token 1L
            && Int64.equal lease.expires_at_ns expiry | None->false)))

(* Actual service action stage: measured chrony clock, canonical coordinator/task,
   public profile and signed receipts, OTP store actor, guardian/native effect,
   and atomic truthful outbox. No real Telegram network recipient. *)
let () =
  let dir=Stdlib.Sys.getenv "UOS_CANCEL_TRANSPORT_TEST_DIR" in
  let root=Stdlib.Sys.getenv "UOS_CANCEL_GLEAM_TEST_ROOT" in
  let bin s="<<" ^ String.concat ~sep:"," (List.map (String.to_list s)
    ~f:(fun c->Int.to_string (Char.to_int c))) ^ ">>" in
  let sha p=Digestif.SHA256.(to_hex (digest_string (In_channel.read_all p))) in
  let guardian=Filename.concat dir "guardian.exe" and worker=Filename.concat dir "worker.exe" in
  List.iter ["success";"existing_absent";"wrong_fence";"revoked_coordinator";"dispatch";"recover";"recover_absent";"recover_dispatch";"proposal";"approval_status";"approval_foreign"] ~f:(fun mode->
    Cancellation.with_case (fun path store request->
      let request=live_cancel_request path request in
      let lease=some (ok (Store.find_bridge_lease store ~mapping_id:request.mapping_id)) in
      let profile_dir=path ^ ".service" in
      Lifetime_unix.mkdir profile_dir 0o700;
      let code=Printf.sprintf
        "code:add_paths(filelib:wildcard(%S)),code:add_patha(%S),{ok,_}=application:ensure_all_started(hackney),R=telegram_action_service_test:run_native(%s,%s,%s,%s,%s,%s,%s,%Ld,%Ld,%Ld,%s),io:put_chars(R),halt(0)."
        (Filename.concat root "lib/*/ebin") (Filename.concat root "build/ebin")
        (bin profile_dir) (bin path) (bin guardian) (bin (sha guardian))
        (bin worker) (bin (sha worker)) (bin request.mapping_id)
        (if String.equal mode "wrong_fence" then Int64.(request.fencing_token+1L) else request.fencing_token)
        lease.expires_at_ns request.target_lease_until_ns (bin mode) in
      let status,out,errors=run_cancellation_child
        ~program:"/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl"
        ~arguments:["+S";"2:2";"+A";"2";"-noshell";"-eval";code] ~database:path ~input:"" in
      if not (Poly.equal status (Lifetime_unix.WEXITED 0)) then
        Printf.eprintf "service action %s stdout=%s stderr=%s\n%!" mode out errors;
      check ("SERVICE-ACTION-" ^ mode ^ "-EXIT")
        (Poly.equal status (Lifetime_unix.WEXITED 0) && String.is_empty errors);
      if String.equal mode "success" then
        check "SERVICE-ACTION-SIGNED-NATIVE-EFFECT-AND-OUTBOX"
          (String.equal out "service_signed_cancel_outbox" && Poly.equal (Cancellation.job store).state Store.Job_cancelled)
      else if String.equal mode "approval_status" || String.equal mode "approval_foreign" then check ("SERVICE-APPROVAL-STATUS-" ^ mode)
        (String.equal out "approval_status_scoped_delivered_no_effect" && Poly.equal (Cancellation.job store).state Store.Job_executing)
      else if String.equal mode "proposal" then check "SERVICE-PROPOSAL-EXACT-TARGET-NO-EFFECT"
        (String.equal out "service_proposal_exact_target_no_effect" && Poly.equal (Cancellation.job store).state Store.Job_executing)
      else if String.equal mode "dispatch" then check "SERVICE-COMMAND-NATIVE-HTTP-DELIVERY"
        (String.equal out "service_command_dispatched_delivered_once" && Poly.equal (Cancellation.job store).state Store.Job_cancelled)
      else if String.equal mode "recover_dispatch" then check "SERVICE-RECOVERY-HTTP-DELIVERED-ONCE"
        (String.equal out "service_recovery_dispatched_delivered_once" && Poly.equal (Cancellation.job store).state Store.Job_cancelled)
      else if String.equal mode "recover" then check "SERVICE-RECOVERY-NEW-EPOCH-OUTBOX-SENDABLE"
        (String.equal out "service_recovery_new_epoch_outbox_sendable" && Poly.equal (Cancellation.job store).state Store.Job_cancelled)
      else if String.equal mode "recover_absent" then check "SERVICE-RECOVERY-ABSENT-NO-REEXECUTION"
        (String.equal out "service_recovery_absent_not_reexecuted" && Poly.equal (Cancellation.job store).state Store.Job_executing)
      else if String.equal mode "revoked_coordinator" then check "SERVICE-ACTION-REVOKED-COORDINATOR-NO-EFFECT"
        (String.equal out "revoked_coordinator_no_effect" && Poly.equal (Cancellation.job store).state Store.Job_executing)
      else if String.equal mode "wrong_fence" then check "SERVICE-ACTION-CHANGED-FENCE-NO-EFFECT"
        (String.equal out "changed_bridge_fence_refused" && Poly.equal (Cancellation.job store).state Store.Job_executing)
      else check "SERVICE-ACTION-PERSISTED-ABSENT-NO-REEXECUTION"
        (String.equal out "persisted_absent_not_reexecuted" && Poly.equal (Cancellation.job store).state Store.Job_executing)))

module Target_protocol = Sa_plan.Target_protocol
let target_json (r:Store.job_cancellation) =
  let controller=Yojson.Safe.to_string (`Assoc [
    "schema",`String "uos.sa-plan.bridge-bind-request.v1";
    "mapping_id",`String r.mapping_id;"plan_id",`String "cancel-plan";
    "task_id",`String "controller";"owner",`String r.owner;
    "task_attempt",`Int 1;"lease_id",`String r.lease_id;
    "expires_at_ns",`Int 30000]) in
  `Assoc ["schema",`String "uos.sa-plan.cancel-target-request.v1";
    "controller_json",`String controller;
    "fencing_token",`String (Int64.to_string r.fencing_token);
    "target_job_id",`String r.target_job_id]

let () = Cancellation.with_case (fun _ store request ->
  let before=Cancellation.job store in
  let run r=Store.inspect_cancellation_target_observed store
    ~mapping_id:r.Store.mapping_id ~owner:r.owner ~lease_id:r.lease_id
    ~fencing_token:r.fencing_token ~target_job_id:r.target_job_id ~observe_now:(fun()->200L) in
  let t=ok(run request) in
  check "TARGET-EXACT-FOUR-FIELD-OBSERVATION"
    (String.equal t.job_id request.target_job_id && String.equal t.target_worker request.target_worker
      && t.target_attempt=request.target_attempt && Int64.equal t.target_lease_until_ns request.target_lease_until_ns);
  List.iter [{request with owner="other"};{request with lease_id="other"};
    {request with fencing_token=2L};{request with target_job_id="foreign/job"};
    {request with target_job_id="cancel-plan/"};{request with target_job_id="cancel-plan/missing"}]
    ~f:(fun r->check "TARGET-SCOPE-AND-FENCE-REFUSED" (Result.is_error(run r)));
  check "TARGET-READS-PRESERVE-JOB" (Poly.equal before (Cancellation.job store) && Cancellation.no_effect store request);
  let raw=Yojson.Safe.to_string(target_json request) in
  let command=ok(Target_protocol.decode raw) in
  let out=ok(Target_protocol.execute_observed store command ~observe_now:(fun()->200L)) in
  let wire=Yojson.Safe.to_string out in
  check "TARGET-PROTOCOL-REDACTED" (not(String.is_substring wire ~substring:"args")
    && not(String.is_substring wire ~substring:"result") && not(String.is_substring wire ~substring:"reason"));
  List.iter ["{}";"[]";raw^"x";String.make 8193 'x'] ~f:(fun s->
    check "TARGET-PROTOCOL-MALFORMED-REFUSED" (Result.is_error(Target_protocol.decode s)));
  let fields=Yojson.Safe.Util.to_assoc(target_json request) in
  List.iter [`Assoc(("extra",`Bool true)::fields);`Assoc(("schema",`String "duplicate")::fields);
    `Assoc(List.Assoc.add fields ~equal:String.equal "fencing_token" (`String "01"));
    `Assoc(List.Assoc.add fields ~equal:String.equal "fencing_token" (`Int 1))]
    ~f:(fun j->check "TARGET-PROTOCOL-CLOSED-SCHEMA"
      (Result.is_error(Target_protocol.decode(Yojson.Safe.to_string j))));
  let controller=Yojson.Safe.Util.(member "controller_json" (target_json request) |> to_string) in
  List.iter ["task_id",`String "different";"task_attempt",`Int 2;
    "expires_at_ns",`Int 30001;"plan_id",`String "foreign"] ~f:(fun (key,value)->
      let inner=Yojson.Safe.Util.to_assoc(Yojson.Safe.from_string controller) in
      let altered=Yojson.Safe.to_string(`Assoc(List.Assoc.add inner ~equal:String.equal key value)) in
      let j=`Assoc(List.Assoc.add fields ~equal:String.equal "controller_json" (`String altered)) in
      let command=ok(Target_protocol.decode(Yojson.Safe.to_string j)) in
      check "TARGET-PROTOCOL-EXACT-CONTROLLER"
        (Result.is_error(Target_protocol.execute_observed store command ~observe_now:(fun()->200L))));
  check "TARGET-PROTOCOL-NO-MUTATION" (Poly.equal before (Cancellation.job store) && Cancellation.no_effect store request))

let () = List.iter [
 "UPDATE sa_plan_task SET attempt=2";
 "UPDATE sa_plan_task SET worker='other'";
 "UPDATE sa_plan_task SET state='available'";
 "UPDATE sa_plan_task SET lease_until_ns=200";
 "UPDATE sa_plan_bridge_lease SET task_attempt=NULL";
 "UPDATE sa_plan_bridge_lease SET expires_at_ns=200";
 "UPDATE sa_plan_bridge_lease SET fencing_token=2";
 "UPDATE sa_plan_job SET state='completed'";
 "UPDATE sa_plan_job SET lease_until_ns=200";
 "UPDATE sa_plan_job SET lease_owner='other'";
 "UPDATE sa_plan_job SET worker='bad worker'";
 "UPDATE sa_plan_job SET attempt=2147483648"
] ~f:(fun sql->Cancellation.with_case(fun path store r->
  Cancellation.exec path sql;
  let before=Cancellation.job store in
  let observed=Store.inspect_cancellation_target_observed store ~mapping_id:r.mapping_id
    ~owner:r.owner ~lease_id:r.lease_id ~fencing_token:r.fencing_token
    ~target_job_id:r.target_job_id ~observe_now:(fun()->200L) in
  check "TARGET-STALE-CONTROLLER-OR-JOB-REFUSED" (Result.is_error observed);
  check "TARGET-REFUSAL-NO-MUTATION" (Poly.equal before (Cancellation.job store))))

let () = Cancellation.with_case(fun path store r->
 let peer=ok(Store.open_db path) in
 let lock=Sqlite3.db_open path in
 Exn.protect ~finally:(fun()->ignore(Sqlite3.exec lock "ROLLBACK":Sqlite3.Rc.t);
   ignore(Sqlite3.db_close lock:bool);Store.close peer) ~f:(fun()->
  require "TARGET-CONTENTION-LOCK" (Poly.equal(Sqlite3.exec lock "BEGIN IMMEDIATE") Sqlite3.Rc.OK);
  let observed=Atomic.make false and now=Atomic.make 200L and started=Atomic.make false in
  let worker=Domain.spawn(fun()->Atomic.set started true;
    Store.inspect_cancellation_target_observed peer ~mapping_id:r.mapping_id
    ~owner:r.owner ~lease_id:r.lease_id ~fencing_token:r.fencing_token
    ~target_job_id:r.target_job_id ~observe_now:(fun()->Atomic.set observed true;Atomic.get now)) in
  while not(Atomic.get started) do Lifetime_unix.sleepf 0.001 done;
  Lifetime_unix.sleepf 0.05;
  let premature=Atomic.get observed in
  Atomic.set now 20000L;
  require "TARGET-CONTENTION-UNLOCK" (Poly.equal(Sqlite3.exec lock "COMMIT") Sqlite3.Rc.OK);
  let result=Domain.join worker in
  check "TARGET-CLOCK-AFTER-LOCK" (not premature && Atomic.get observed);
  check "TARGET-EXPIRED-DURING-LOCK-REFUSED" (Result.is_error result && Cancellation.no_effect store r)))

let () = Cancellation.with_case(fun path store request->
 let request=live_cancel_request path request in
 let lease=some(ok(Store.find_bridge_lease store ~mapping_id:request.mapping_id)) in
 let before=Cancellation.job store in
 let dir=Stdlib.Sys.getenv "UOS_CANCEL_TRANSPORT_TEST_DIR"
 and root=Stdlib.Sys.getenv "UOS_CANCEL_GLEAM_TEST_ROOT" in
 let bin s="<<" ^ String.concat ~sep:"," (List.map(String.to_list s) ~f:(fun c->Int.to_string(Char.to_int c))) ^ ">>" in
 let sha p=Digestif.SHA256.(to_hex(digest_string(In_channel.read_all p))) in
 let guardian=Filename.concat dir "guardian.exe" and native=Filename.concat dir "worker.exe" in
 let code=Printf.sprintf
   "code:add_paths(filelib:wildcard(%S)),code:add_patha(%S),C='cepaf_gleam@harness@telegram_store_transport':reviewed_local_configuration(%s,%s,%s,%s,%s),R=telegram_bridge_test:inspect_native(C,%s,%Ld,%Ld),io:put_chars(R),halt(0)."
   (Filename.concat root "lib/*/ebin") (Filename.concat root "build/ebin")
   (bin guardian)(bin(sha guardian))(bin native)(bin(sha native))(bin path)
   (bin request.mapping_id) lease.expires_at_ns request.target_lease_until_ns in
 let status,out,errors=run_cancellation_child
   ~program:"/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl"
   ~arguments:["+S";"2:2";"+A";"2";"-noshell";"-eval";code] ~database:path ~input:"" in
 if not(Poly.equal status (Lifetime_unix.WEXITED 0)) then
   Printf.eprintf "target native stdout=%s stderr=%s\n%!" out errors;
 check "TARGET-GLEAM-NATIVE-ROUNDTRIP" (Poly.equal status (Lifetime_unix.WEXITED 0)
   && String.is_empty errors && String.equal out "exact_target_observed_no_mutation");
 check "TARGET-GLEAM-NATIVE-JOB-PRESERVED" (Poly.equal before (Cancellation.job store)))
