let checks = ref 0
let failures = ref 0
let skipped = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf "FAIL: %s\n" name
  end

let contains text fragment =
  let text = String.lowercase_ascii text in
  let fragment = String.lowercase_ascii fragment in
  let n = String.length text and m = String.length fragment in
  let rec loop i =
    i + m <= n
    && (String.sub text i m = fragment || loop (i + 1))
  in
  m = 0 || loop 0

let is_error = function Error _ -> true | Ok _ -> false
let error_mentions fragment = function Error text -> contains text fragment | Ok _ -> false
let ok = function Ok value -> value | Error error -> failwith error

let prefix_unavailable prerequisite = function
  | Error diagnostic ->
      Run_event_store.prefix_diagnostic_prerequisite diagnostic = prerequisite
      && Run_event_store.prefix_diagnostic_code diagnostic
         = "event-prefix-prerequisite-unavailable:"
           ^ Run_event_store.prefix_prerequisite_id prerequisite
      && Run_event_store.prefix_diagnostic_coordinate diagnostic
         = "L3/Observe/run-event-prefix"
      && Run_event_store.prefix_diagnostic_origin diagnostic
         = Run_event_store.Prefix_evidence
  | Ok _ -> false

let protocol_ok = function
  | Ok value -> value
  | Error error ->
      failwith (Dependability_sqlite_test_protocol.string_of_error error)

let opaque_fixture_reference registry fixture =
  let registry, lease =
    protocol_ok (Dependability_sqlite_test_protocol.acquire registry fixture)
  in
  protocol_ok (Dependability_sqlite_test_protocol.reference registry lease)

let provenance : Run_model.provenance =
  { source_revision = "80f93278"; source_clean = true;
    configuration_digest = String.make 64 'a';
    authority_digest = String.make 64 'b';
    executable_digest = String.make 64 'c' }

let coordinate : Ops_capability.coordinate =
  { level = Ops_capability.L2; phase = Ops_capability.Observe }

let make ?(sequence = 0L) ?(event_id = "event-0")
    ?(kind = Run_model.Run_declared) ?(subject = Run_model.Run)
    ?(payload = `Assoc []) ?previous_digest ?(provenance = provenance) run_id =
  ok
    (Run_model.make ~run_id ~sequence ~event_id ~kind ~subject
       ~plane:Ops_capability.Control_plane ~coordinate
       ~rca_origin:Ops_capability.Control
       ~occurred_at_ns:(Int64.add 100L sequence)
       ~monotonic_at_ns:(Int64.add 50L sequence)
       ~provenance ~payload ~previous_digest)

let next ?(event_id = "heartbeat") (previous : Run_model.event) =
  make previous.Run_model.run_id
    ~sequence:(Int64.succ previous.sequence) ~event_id
    ~kind:Run_model.Heartbeat ~subject:Run_model.Run
    ~previous_digest:previous.digest

let same_summary (left : Run_snapshot.summary) (right : Run_snapshot.summary) =
  left = right

let () =
  (* Fixture references are the entire test location capability.  The protocol
     never resolves a filename and leases are reclaimed by their owner, not by
     this caller. *)
  let fixtures =
    protocol_ok (Dependability_sqlite_test_protocol.create ~maximum_live:32)
  in
  let location fixture = opaque_fixture_reference fixtures fixture in
  let open_store fixture = Run_event_store.open_store (location fixture) in
  let module Closed = Dependability_sqlite.Closed_operation in

  check "closed event denominator detects a missing immutable insert"
    (Closed.source_digest
     <> Closed.For_test.source_digest_with_mutation
          Closed.For_test.Drop_event_insert);

  Printf.printf "[unit] opaque locations, append identity, and ordered reads\n";
  let store = ok (open_store Dependability_sqlite_test_protocol.In_memory) in
  let prefix_prerequisites =
    [ Run_event_store.Typed_execution_identity_current_carrier;
      Admitted_plan_current_carrier;
      Typed_prefix_denominator_current_carrier;
      Dispatch_claim_current_carrier;
      Owner_session_current_carrier;
      Terminal_target_disposition_current_carrier ]
  in
  check "event-prefix production remains unavailable without typed plan inputs"
    (Run_event_store.event_prefix_production_posture = `Implemented_unavailable
     && List.for_all
          (fun prerequisite ->
            prefix_unavailable prerequisite
              (Run_event_store.prefix_prerequisite_status prerequisite))
          prefix_prerequisites
     && prefix_unavailable Run_event_store.Admitted_plan_current_carrier
          (Run_event_store.prepare_event_prefix store));
  let prefix_source_mutations =
    [ Run_event_store.For_test.Drop_execution_binding; Drop_plan_binding;
      Drop_prefix_denominator; Drop_owner_session_binding; Drop_event_identity;
      Drop_sequence_binding; Drop_previous_digest_binding; Accept_gap;
      Accept_duplicate; Accept_noncontiguous_prefix; Accept_running_target;
      Accept_cross_context; Accept_stale_owner; Expose_event_list;
      Expose_event_payload; Expose_store_handle; Add_caller_digest; Add_callback;
      Construct_current_without_readback ]
  in
  check "event-prefix source identity kills every completeness and escape mutant"
    (String.length Run_event_store.event_prefix_source_digest = 64
     && List.for_all
          (fun mutation ->
            Run_event_store.event_prefix_source_digest
            <> Run_event_store.For_test.event_prefix_source_digest_with_mutation
                 mutation)
          prefix_source_mutations);
  let run0 = make "run-1" in
  let run1 = next ~event_id:"run-1-heartbeat" run0 in
  check "first event appends" (Run_event_store.append store run0 = Ok ());
  check "byte-identical replay is idempotent"
    (Run_event_store.append store run0 = Ok ());
  check "contiguous hash-linked event appends"
    (Run_event_store.append store run1 = Ok ());
  check "events returns the complete valid stream including sequence zero"
    (match Run_event_store.events store ~run_id:"run-1" with
     | Ok [ zero; one ] -> zero.sequence = 0L && one.sequence = 1L
     | _ -> false);
  check "events_after is strictly greater than its cursor"
    (match Run_event_store.events_after store ~run_id:"run-1" ~sequence:0L with
     | Ok [ event ] -> event.sequence = 1L
     | _ -> false);
  check "missing runs are empty"
    (Run_event_store.events store ~run_id:"missing" = Ok []
     && Run_event_store.events_after store ~run_id:"missing" ~sequence:0L = Ok []);
  check "negative cursor is refused"
    (error_mentions "nonnegative"
       (Run_event_store.events_after store ~run_id:"run-1" ~sequence:(-1L)));
  let id_conflict =
    make "run-1" ~sequence:2L ~event_id:"run-1-heartbeat"
      ~kind:Run_model.Heartbeat ~subject:Run_model.Run
      ~payload:(`Assoc [ ("changed", `Bool true) ])
      ~previous_digest:run1.digest
  in
  check "same run and event id with different payload is rejected"
    (error_mentions "divergent" (Run_event_store.append store id_conflict));
  let sequence_conflict =
    make "run-1" ~sequence:1L ~event_id:"different-id"
      ~kind:Run_model.Heartbeat ~subject:Run_model.Run
      ~payload:(`Assoc [ ("changed", `Bool true) ])
      ~previous_digest:run0.digest
  in
  check "same run and sequence with different identity is rejected"
    (error_mentions "divergent" (Run_event_store.append store sequence_conflict));
  let bad_first = make "bad-first" ~sequence:1L ~event_id:"bad-first-1" in
  check "first sequence must be zero"
    (is_error (Run_event_store.append store bad_first));
  let gap0 = make "gap-run" ~event_id:"gap-0" in
  let gap2 =
    make "gap-run" ~sequence:2L ~event_id:"gap-2"
      ~kind:Run_model.Heartbeat ~subject:Run_model.Run
      ~previous_digest:gap0.digest
  in
  check "gap fixture head appends" (Run_event_store.append store gap0 = Ok ());
  check "forward gap is rejected"
    (error_mentions "gap" (Run_event_store.append store gap2));
  let wrong_previous =
    make "gap-run" ~sequence:1L ~event_id:"wrong-previous"
      ~kind:Run_model.Heartbeat ~subject:Run_model.Run
      ~previous_digest:(String.make 64 'f')
  in
  check "wrong previous digest is rejected"
    (error_mentions "previous" (Run_event_store.append store wrong_previous));

  Printf.printf "[feature] snapshots and summaries derive from event authority\n";
  let run3_0 = make "run-3" in
  let run3_1 = next ~event_id:"run-3-1" run3_0 in
  let run3_2 = next ~event_id:"run-3-2" run3_1 in
  List.iter
    (fun event -> check ("append " ^ event.Run_model.event_id)
        (Run_event_store.append store event = Ok ()))
    [ run3_0; run3_1; run3_2 ];
  let expected_run3 = ok (Run_snapshot.fold [ run3_0; run3_1; run3_2 ]) in
  check "snapshot is exactly the deterministic fold"
    (match Run_event_store.snapshot store ~run_id:"run-3" with
     | Ok actual ->
         same_summary (Run_snapshot.summary actual) (Run_snapshot.summary expected_run3)
     | Error _ -> false);
  check "snapshot rejects a missing stream"
    (error_mentions "missing" (Run_event_store.snapshot store ~run_id:"no-run"));
  check "runs rejects a negative limit"
    (error_mentions "nonnegative" (Run_event_store.runs store ~limit:(-1)));
  check "runs zero limit returns empty" (Run_event_store.runs store ~limit:0 = Ok []);
  check "runs summary is the fold summary, not a second truth"
    (match Run_event_store.runs store ~limit:1 with
     | Ok [ summary ] -> same_summary summary (Run_snapshot.summary expected_run3)
     | _ -> false);
  check "append-only storage guards reject update and delete attempts"
    (Run_event_store.For_test.verify_append_only_guards store = Ok ());
  Run_event_store.close store;

  Printf.printf "[integrity] closed seams inject only typed adversarial history\n";
  let history = ok (open_store Dependability_sqlite_test_protocol.In_memory) in
  let history_head = make "read-gap" ~event_id:"read-gap-0" in
  let history_gap =
    make "read-gap" ~sequence:2L ~event_id:"read-gap-2"
      ~kind:Run_model.Heartbeat ~subject:Run_model.Run
      ~previous_digest:history_head.digest
  in
  check "history fixture head appends"
    (Run_event_store.append history history_head = Ok ());
  check "actor-owned history injection admits a typed event only"
    (Run_event_store.For_test.inject_history history history_gap = Ok ());
  check "readback refuses an actor-owned injected sequence gap"
    (error_mentions "gap" (Run_event_store.events history ~run_id:"read-gap"));
  Run_event_store.close history;
  let malformed = ok (open_store Dependability_sqlite_test_protocol.In_memory) in
  check "actor-owned malformed history injection is admitted through a closed tag"
    (Run_event_store.For_test.inject_history_fault malformed
       (Run_event_store.For_test.Malformed_stored_event "malformed") = Ok ());
  check "malformed actor-owned stored history fails closed on readback"
    (error_mentions "json" (Run_event_store.snapshot malformed ~run_id:"malformed"));
  Run_event_store.close malformed;

  Printf.printf "[structure] registered open faults fail closed\n";
  check "registered open fault is refused without a physical location"
    (error_mentions "injected"
       (open_store
          (Dependability_sqlite_test_protocol.Fault_injection
             Dependability_sqlite_test_protocol.Open_failure)));
  let spawn_fault =
    Run_event_store.For_test.open_store_with_fault
      Run_event_store.For_test.Fail_after_spawn_before_registration
      (location Dependability_sqlite_test_protocol.In_memory)
  in
  check "post-spawn registration fault closes and joins its actor"
    (error_mentions "post-spawn" spawn_fault && error_mentions "join" spawn_fault);
  let unsupported_schema =
    Run_event_store.For_test.open_store_with_fault
      Run_event_store.For_test.Unsupported_schema
      (location Dependability_sqlite_test_protocol.In_memory)
  in
  check "closed unsupported-schema fixture is refused during initialization"
    (error_mentions "unsupported" unsupported_schema);

  Printf.printf "[fault] typed actor and close failures are bounded\n";
  let dropped = ok (open_store Dependability_sqlite_test_protocol.In_memory) in
  check "dropped-reply fault is admitted by the closed actor seam"
    (Run_event_store.For_test.arm_fault dropped
       Run_event_store.For_test.Drop_next_reply = Ok ());
  check "dropped reply returns a named deadline refusal"
    (error_mentions "deadline" (Run_event_store.append dropped (make "drop-reply")));
  check "dropped-reply actor remains closeable"
    (Run_event_store.For_test.close_result dropped = Ok ());
  let drain = ok (open_store Dependability_sqlite_test_protocol.In_memory) in
  check "failure-drain fault is admitted by the closed actor seam"
    (Run_event_store.For_test.arm_fault drain
       Run_event_store.For_test.Fail_next_failure_drain = Ok ());
  check "failure drain refuses its interrupted append"
    (is_error (Run_event_store.append drain (make "drain-fault")));
  check "failed actor close joins before reporting closed"
    (Run_event_store.For_test.close_result drain = Ok ()
     && Run_event_store.For_test.writer_joined drain
     && Run_event_store.For_test.lifecycle drain
        = Run_event_store.For_test.Observed_closed);
  let close_fault =
    ok
      (open_store
         (Dependability_sqlite_test_protocol.Fault_injection
            Dependability_sqlite_test_protocol.Close_failure))
  in
  check "registered close fault is a typed close refusal"
    (is_error (Run_event_store.For_test.close_result close_fault));
  check "forced test cleanup remains confined to an exhausted actor"
    (Run_event_store.For_test.force_cleanup close_fault = Ok ()
     && Run_event_store.For_test.writer_joined close_fault
     && Run_event_store.For_test.authority_state close_fault
        = Dependability_sqlite.Database_released);

  Printf.printf "[lifecycle] close is concurrent-safe and terminal\n";
  let concurrent = ok (open_store Dependability_sqlite_test_protocol.In_memory) in
  let event = make "concurrent" in
  let results = Array.make 8 None in
  let domains =
    List.init 8 (fun index ->
        Domain.spawn (fun () ->
            results.(index) <- Some (Run_event_store.append concurrent event)))
  in
  List.iter Domain.join domains;
  check "concurrent identical replay remains idempotent"
    (Array.for_all (function Some (Ok ()) -> true | Some (Error _) | None -> false)
       results);
  let close_results = Array.make 4 None in
  let closers =
    List.init 4 (fun index ->
        Domain.spawn (fun () ->
            close_results.(index) <- Some (Run_event_store.For_test.close_result concurrent)))
  in
  List.iter Domain.join closers;
  check "every concurrent closer receives the same terminal receipt"
    (Array.for_all (function Some (Ok ()) -> true | Some (Error _) | None -> false)
       close_results);
  check "operations after close are refused by name"
    (error_mentions "closed" (Run_event_store.append concurrent (make "after-close"))
     && error_mentions "closed" (Run_event_store.events concurrent ~run_id:"concurrent"));

  Printf.printf "[finalize] scoped finalization failures remain observable\n";
  let finalized = ok (open_store Dependability_sqlite_test_protocol.In_memory) in
  let before = Run_event_store.For_test.finalize_summary finalized in
  let finalize_failure = Run_event_store.For_test.exercise_finalize_failure finalized in
  let after = Run_event_store.For_test.finalize_summary finalized in
  check "real constraint finalization remains a named typed failure"
    (error_mentions "constraint" finalize_failure
     && error_mentions "finalize" finalize_failure);
  check "finalize failure remains in the scoped interval census"
    (after.failed = before.failed + 1 && after.intervals >= before.intervals + 1
     && not after.active);
  Run_event_store.close finalized;

  Printf.printf "run_event_store: %d checks, %d failures\n" !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_event_store"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:!skipped
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
