open Core

module Observation = Sa_plan.Observation
module Store = Sa_plan.Store

let require law condition =
  if condition then Printf.printf "ok %s\n%!" law
  else begin
    Printf.eprintf "FAIL %s\n%!" law;
    exit 1
  end

let ok = function Ok value -> value | Error message -> failwith message

let body ~boot ~event ~sequence ~candidate =
  `Assoc
    [ "source_journal_ref", `String "journal:nas-1:uos-swarm";
      "host_boot_id", `String boot;
      "event_id", `String event;
      "local_sequence", `Intlit (Int64.to_string sequence);
      "session_ref", `String "session:656f0d2c-6019-4d9e-b0ce-b9e39b240047";
      "resource_ref", `String "session:656f0d2c-6019-4d9e-b0ce-b9e39b240047";
      "epoch", `Intlit "7";
      "candidate_ref", `String candidate ]

let with_hash ?declared body =
  let computed = ok (Observation.computed_payload_hash_of_yojson body) in
  let payload_hash = Option.value declared ~default:computed in
  match body with
  | `Assoc fields -> `Assoc (("payload_hash", `String payload_hash) :: fields)
  | _ -> assert false

let observation ?declared ~boot ~event ~sequence ~candidate () =
  body ~boot ~event ~sequence ~candidate
  |> with_hash ?declared
  |> Observation.of_yojson
  |> ok

let accepted = function
  | Observation.Observation_accepted value -> value
  | Reconciliation_required _ -> failwith "expected accepted observation"

let reconciliation = function
  | Observation.Reconciliation_required value -> value
  | Observation_accepted _ -> failwith "expected reconciliation"

let cleanup path =
  List.iter [ path; path ^ "-wal"; path ^ "-shm" ] ~f:(fun candidate ->
      if Stdlib.Sys.file_exists candidate then Stdlib.Sys.remove candidate)

let () =
  let path =
    Stdlib.Filename.concat (Stdlib.Filename.get_temp_dir_name ())
      (Printf.sprintf "uos-sa-plan-observation-%d.sqlite3" (Caml_unix.getpid ()))
  in
  cleanup path;
  Exn.protect
    ~f:(fun () ->
      let reordered =
        match body ~boot:"boot-a" ~event:"event-1" ~sequence:1L ~candidate:"3644224c" with
        | `Assoc fields -> `Assoc (List.rev fields)
        | _ -> assert false
      in
      let canonical =
        body ~boot:"boot-a" ~event:"event-1" ~sequence:1L ~candidate:"3644224c"
      in
      require "LAW C02-HASH-INDEPENDENT-OF-CLIENT-MEMBER-ORDER"
        (String.equal
           (ok (Observation.computed_payload_hash_of_yojson canonical))
           (ok (Observation.computed_payload_hash_of_yojson reordered)));
      require "LAW C02-UNKNOWN-FIELDS-REJECTED"
        (Result.is_error
           (Observation.computed_payload_hash_of_yojson
              (match canonical with
              | `Assoc fields -> `Assoc (("unbound", `String "escape") :: fields)
              | _ -> assert false)));

      let store_a = ok (Store.open_db path) in
      require "LAW C02-SCHEMA-MIGRATES-TO-V7" (Store.schema_version store_a = 7);
      ok
        (Store.create_plan store_a ~id:"authority-plan"
           ~name:"coordination/observation-authority" ~title:"Authority sentinel"
           ~now_ns:1L);
      ok
        (Store.create_task store_a ~plan_id:"authority-plan" ~id:"sentinel"
           ~name:"coordination/observation-authority/sentinel"
           ~title:"Must remain available" ~parent_id:None ~dependencies:[]
           ~priority:0 ~now_ns:1L);
      let source1, event1 =
        observation ~boot:"boot-a" ~event:"event-1" ~sequence:1L
          ~candidate:"3644224c" ()
      in
      let first = accepted (ok (Observation.ingest store_a source1 event1)) in
      require "LAW C02-FIRST-OBSERVATION-ACCEPTED"
        (Int64.equal first.hermes_sequence 1L && not first.replayed);

      let store_b = ok (Store.open_db path) in
      let second_consumer =
        accepted (ok (Observation.ingest store_b source1 event1))
      in
      require "LAW C02-TWO-CONSUMERS-SAME-EVENT-SAME-RECEIPT"
        (Int64.equal second_consumer.hermes_sequence first.hermes_sequence
         && String.equal second_consumer.payload_hash first.payload_hash
         && second_consumer.replayed);
      Store.close store_b;
      Store.close store_a;

      let store = ok (Store.open_db path) in
      let reopened = accepted (ok (Observation.ingest store source1 event1)) in
      require "LAW C02-REPLAY-AFTER-REOPEN-IS-IDEMPOTENT"
        (Int64.equal reopened.hermes_sequence first.hermes_sequence
         && reopened.replayed);

      let conflicting_source, conflicting_event =
        observation ~boot:"boot-a" ~event:"event-1" ~sequence:1L
          ~candidate:"different-candidate" ()
      in
      let conflict =
        reconciliation
          (ok (Observation.ingest store conflicting_source conflicting_event))
      in
      require "LAW C02-EVENT-BODY-CONFLICT-REJECTS"
        (Poly.equal conflict.kind Observation.Body_conflict);

      let gap_source, gap_event =
        observation ~boot:"boot-a" ~event:"event-3" ~sequence:3L
          ~candidate:"3644224c" ()
      in
      let gap = reconciliation (ok (Observation.ingest store gap_source gap_event)) in
      require "LAW C02-SEQUENCE-GAP-FAILS-CLOSED"
        (Poly.equal gap.kind Observation.Sequence_gap
         && Option.value_map gap.expected_sequence ~default:false
              ~f:(Int64.equal 2L));

      let source2, event2 =
        observation ~boot:"boot-b" ~event:"event-2" ~sequence:2L
          ~candidate:"3644224c" ()
      in
      let after_boot = accepted (ok (Observation.ingest store source2 event2)) in
      require "LAW C02-BOOT-TRANSITION-CONTINUES-STABLE-JOURNAL-SEQUENCE"
        (Int64.equal after_boot.hermes_sequence 2L && not after_boot.replayed);
      let after_repair = accepted (ok (Observation.ingest store gap_source gap_event)) in
      require "LAW C02-GAP-CAN-BE-RECONCILED-WITHOUT-FORGING-EVENT"
        (Int64.equal after_repair.hermes_sequence 3L && not after_repair.replayed);

      let old_source, old_event =
        observation ~boot:"boot-c" ~event:"late-old-event" ~sequence:2L
          ~candidate:"3644224c" ()
      in
      let old = reconciliation (ok (Observation.ingest store old_source old_event)) in
      require "LAW C02-OUT-OF-ORDER-FAILS-CLOSED"
        (Poly.equal old.kind Observation.Out_of_order
         && Option.value_map old.expected_sequence ~default:false
              ~f:(Int64.equal 4L));

      let wrong_source, wrong_event =
        observation ~declared:(String.make 64 '0') ~boot:"boot-c"
          ~event:"event-4" ~sequence:4L ~candidate:"3644224c" ()
      in
      let mismatch =
        reconciliation (ok (Observation.ingest store wrong_source wrong_event))
      in
      require "MUT C02-CLIENT-HASH-IS-NEVER-TRUSTED"
        (Poly.equal mismatch.kind Observation.Payload_hash_mismatch);

      let source4, event4 =
        observation ~boot:"boot-c" ~event:"event-4" ~sequence:4L
          ~candidate:"3644224c" ()
      in
      let forced =
        Store.with_transaction store (fun () ->
            match ok (Observation.ingest store source4 event4) with
            | Observation.Observation_accepted _ -> Error "forced rollback"
            | Reconciliation_required _ -> failwith "unexpected refusal")
      in
      require "LAW C02-OUTER-TRANSACTION-ERROR-ROLLS-BACK-INBOX"
        (Result.is_error forced);
      let after_rollback = accepted (ok (Observation.ingest store source4 event4)) in
      require "LAW C02-ROLLBACK-PRESERVES-FRESH-INSERT-SEMANTICS"
        (Int64.equal after_rollback.hermes_sequence 4L
         && not after_rollback.replayed);

      let sentinel =
        ok (Store.find_task store ~plan_id:"authority-plan" ~id_or_name:"sentinel")
      in
      require "LAW C02-OBSERVATION-CANNOT-MUTATE-TASK-STATE-OR-LEASE"
        (Option.value_map sentinel ~default:false ~f:(fun task ->
             String.equal task.state "available"
             && Option.is_none task.worker
             && task.attempt = 0));
      let reconciliations =
        ok
          (Store.list_session_reconciliations store
             ~source_journal_ref:"journal:nas-1:uos-swarm")
      in
      require "LAW C02-REFUSALS-ARE-DURABLE-AND-VISIBLE"
        (List.length reconciliations = 4
         && List.exists reconciliations ~f:(fun item ->
              Poly.equal item.kind Store.Body_conflict)
         && List.exists reconciliations ~f:(fun item ->
              Poly.equal item.kind Store.Sequence_gap)
         && List.exists reconciliations ~f:(fun item ->
              Poly.equal item.kind Store.Out_of_order)
         && List.exists reconciliations ~f:(fun item ->
              Poly.equal item.kind Store.Payload_hash_mismatch));
      Store.close store;

      let final_store = ok (Store.open_db path) in
      require "LAW C02-RECONCILIATION-SURVIVES-CLOSE-REOPEN"
        (List.length
           (ok
              (Store.list_session_reconciliations final_store
                 ~source_journal_ref:"journal:nas-1:uos-swarm"))
         = 4);
      Store.close final_store)
    ~finally:(fun () -> cleanup path)
