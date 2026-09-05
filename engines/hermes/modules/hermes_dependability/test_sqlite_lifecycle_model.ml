open Sqlite_lifecycle_model
module Closed = Dependability_sqlite.Closed_operation

let _opaque_open_boundary :
    location:Dependability_sqlite_location.reference ->
    maximum_total_attempts:int ->
    (Dependability_sqlite.owned_database, Dependability_sqlite.close_error) result =
  Dependability_sqlite.open_database

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let find_law id report =
  List.find_opt (fun (law : law_result) -> String.equal law.id id) report.laws

let law_holds id report =
  match find_law id report with
  | Some law -> law.holds && Option.is_none law.counterexample
  | None -> false

let mutant_killed id report =
  List.exists
    (fun (mutant : mutant_result) ->
      String.equal mutant.id id && mutant.premise_reachable && mutant.killed
      && Option.is_some mutant.witness)
    report.mutants

let expected_laws =
  [ "SQL.STMT.NO_DOUBLE_FINALIZE"; "SQL.STMT.KEEPALIVE";
    "SQL.STMT.EXPLICIT_TOTAL"; "SQL.STMT.FINALIZE_FAILURE_REPORTED";
    "SQL.CLOSE_V2.TERMINAL_ON_ACCEPT";
    "SQL.CLOSE_V2.PHYSICAL_AFTER_FINALIZE";
    "SQL.CLOSE_V2.FINALIZE_FAILURE_TYPED";
    "SQL.ACTOR.CLOSED_OWNS_NOTHING"; "SQL.ACTOR.BUSY_NOT_SUCCESS";
    "SQL.ACTOR.EXHAUSTION_FAILS_NAMED"; "SQL.ACTOR.ONE_CLOSE_OWNER";
    "SQL.ACTOR.SUCCESS_DRAINS"; "SQL.ACTOR.SETUP_OWNERSHIP";
    "SQL.ACTOR.NO_ADMIT_AFTER_CLOSE"; "SQL.ACTOR.BOUNDED_TERMINAL";
    "SQL.ACTOR.FAILURE_CLEANUP_TRACKED"; "SQL.ACTOR.NO_LOST_RESULTS";
    "SQL.ACTOR.QUIESCENCE_AUTHORIZED";
    "SQL.ACTOR.FRESH_QUIESCENCE_EPOCH";
    "SQL.ACTOR.GLOBAL_BUDGET_MONOTONE";
    "SQL.ACTOR.GENERATION_RECEIPT";
    "SQL.ACTOR.FOLLOWERS_SAME_RECEIPT";
    "SQL.ACTOR.WRITER_TERMINAL_JOIN";
    "SQL.ACTOR.CLEANUP_OWNER_REACHABLE"; "SQL.ACTOR.PROGRESS_TOTAL" ]

let expected_mutants =
  [ "MUT.STMT.DROP_KEEPALIVE"; "MUT.STMT.DISCARD_FINALIZE_FAILURE";
    "MUT.CLOSE_V2.RETRY_DEFERRED";
    "MUT.CLOSE_V2.RELEASE_BEFORE_FINALIZE";
    "MUT.CLOSE_V2.DISCARD_FINALIZE_FAILURE";
    "MUT.ACTOR.IGNORE_BUSY"; "MUT.ACTOR.CLOSE_BEFORE_JOIN";
    "MUT.ACTOR.ABANDON_SPAWNED"; "MUT.ACTOR.DOUBLE_ELECT";
    "MUT.ACTOR.ADMIT_DURING_CLOSING"; "MUT.ACTOR.RESET_RETRY_BUDGET";
    "MUT.ACTOR.BUSY_WITHOUT_QUIESCENCE";
    "MUT.ACTOR.REUSE_STALE_QUIESCENCE";
    "MUT.ACTOR.RESET_GLOBAL_BUDGET";
    "MUT.ACTOR.SPLIT_FOLLOWER_RECEIPT";
    "MUT.ACTOR.FALSE_EXTERNAL_JOIN"; "MUT.ACTOR.DROP_CLEANUP_OWNER";
    "MUT.ACTOR.ABANDON_ENQUEUE_FAILURE";
    "MUT.ACTOR.ABANDON_FAILURE_DRAIN" ]

let () =
  let report = explore () in
  check "M1 formal exploration is non-vacuous"
    (report.statement_states > 1 && report.close_v2_states > 1
     && report.actor_states > 1 && report.healthy_statement_trace
     && report.healthy_close_v2_trace && report.healthy_close_trace);
  check "M1a theorem and mutant census is exact with reachable premises"
    (List.sort String.compare
       (List.map (fun (law : law_result) -> law.id) report.laws)
       = List.sort String.compare expected_laws
     && List.sort String.compare
          (List.map (fun (mutant : mutant_result) -> mutant.id) report.mutants)
        = List.sort String.compare expected_mutants
     && List.for_all
          (fun (law : law_result) ->
            law.premise_reachable && Option.is_some law.premise_witness)
          report.laws
     && List.for_all
          (fun (mutant : mutant_result) ->
            mutant.premise_reachable && Option.is_some mutant.premise_witness)
          report.mutants);
  check "M2 real statement traces never double-finalize"
    (law_holds "SQL.STMT.NO_DOUBLE_FINALIZE" report);
  check "M3 custom finalization cannot overlap retained explicit finalization"
    (law_holds "SQL.STMT.KEEPALIVE" report);
  check "M4 successful explicit finalization is total and singular"
    (law_holds "SQL.STMT.EXPLICIT_TOTAL" report);
  check "M5 Closed entails released DB, joined writer, and success acknowledgement"
    (law_holds "SQL.ACTOR.CLOSED_OWNS_NOTHING" report);
  check "M6 db_close=false never invents success"
    (law_holds "SQL.ACTOR.BUSY_NOT_SUCCESS" report);
  check "M7 cleanup exhaustion is named and never Closed"
    (law_holds "SQL.ACTOR.EXHAUSTION_FAILS_NAMED" report);
  check "M8 only one concurrent closer is elected"
    (law_holds "SQL.ACTOR.ONE_CLOSE_OWNER" report);
  check "M9 successful close drains admitted work"
    (law_holds "SQL.ACTOR.SUCCESS_DRAINS" report);
  check "M10 setup exceptions retain or discharge DB ownership"
    (law_holds "SQL.ACTOR.SETUP_OWNERSHIP" report);
  check "M11 closed and closing actors admit no new operation"
    (law_holds "SQL.ACTOR.NO_ADMIT_AFTER_CLOSE" report);
  check "M12 every bounded path has an honest terminal observation"
    (law_holds "SQL.ACTOR.BOUNDED_TERMINAL" report);
  check "M13 busy close attempts require an admitted quiescence epoch"
    (law_holds "SQL.ACTOR.QUIESCENCE_AUTHORIZED" report);
  check "M14 the lifetime close budget is monotone across generations"
    (law_holds "SQL.ACTOR.GLOBAL_BUDGET_MONOTONE" report);
  check "M15 every close terminal names its elected generation"
    (law_holds "SQL.ACTOR.GENERATION_RECEIPT" report);
  check "M16 concurrent followers receive the elected owner's exact result"
    (law_holds "SQL.ACTOR.FOLLOWERS_SAME_RECEIPT" report);
  check "M17 Closed distinguishes writer termination from external join"
    (law_holds "SQL.ACTOR.WRITER_TERMINAL_JOIN" report);
  check "M18 retained cleanup has a reachable typed owner"
    (law_holds "SQL.ACTOR.CLEANUP_OWNER_REACHABLE" report);
  check "M19 every Closing state has acyclic progress to a terminal receipt"
    (law_holds "SQL.ACTOR.PROGRESS_TOTAL" report);
  check "M20 finalize failure, cleanup, and request-conservation laws are present"
    (List.for_all
       (fun id -> law_holds id report)
       [ "SQL.STMT.FINALIZE_FAILURE_REPORTED";
         "SQL.ACTOR.FAILURE_CLEANUP_TRACKED";
         "SQL.ACTOR.NO_LOST_RESULTS" ]);
  check "M21 close_v2 release and fresh-epoch laws are evidence-gated"
    (List.for_all
       (fun id -> law_holds id report)
       [ "SQL.CLOSE_V2.TERMINAL_ON_ACCEPT";
         "SQL.CLOSE_V2.PHYSICAL_AFTER_FINALIZE";
         "SQL.CLOSE_V2.FINALIZE_FAILURE_TYPED";
         "SQL.ACTOR.FRESH_QUIESCENCE_EPOCH" ]);
  check "X1 dropping keep-alive has a double-finalize witness"
    (mutant_killed "MUT.STMT.DROP_KEEPALIVE" report);
  check "X2 ignoring db_close=false has a false-success witness"
    (mutant_killed "MUT.ACTOR.IGNORE_BUSY" report);
  check "X3 marking Closed before join has an ownership witness"
    (mutant_killed "MUT.ACTOR.CLOSE_BEFORE_JOIN" report);
  check "X4 abandoning a spawned writer has a leak witness"
    (mutant_killed "MUT.ACTOR.ABANDON_SPAWNED" report);
  check "X5 electing two concurrent closers has a split-owner witness"
    (mutant_killed "MUT.ACTOR.DOUBLE_ELECT" report);
  check "X6 admitting during Closing has a late-work witness"
    (mutant_killed "MUT.ACTOR.ADMIT_DURING_CLOSING" report);
  check "X7 resetting the retry budget per caller has an unbounded witness"
    (mutant_killed "MUT.ACTOR.RESET_RETRY_BUDGET" report);
  check "X8 bypassing quiescence admission has a close-attempt witness"
    (mutant_killed "MUT.ACTOR.BUSY_WITHOUT_QUIESCENCE" report);
  check "X9 resetting the lifetime budget has a monotonicity witness"
    (mutant_killed "MUT.ACTOR.RESET_GLOBAL_BUDGET" report);
  check "X10 splitting a follower receipt has an equivalence witness"
    (mutant_killed "MUT.ACTOR.SPLIT_FOLLOWER_RECEIPT" report);
  check "X11 inventing an external join has an ownership witness"
    (mutant_killed "MUT.ACTOR.FALSE_EXTERNAL_JOIN" report);
  check "X12 dropping a retained cleanup owner has a leak witness"
    (mutant_killed "MUT.ACTOR.DROP_CLEANUP_OWNER" report);
  check "X13 discarding finalize failure has an evidence-loss witness"
    (mutant_killed "MUT.STMT.DISCARD_FINALIZE_FAILURE" report);
  check "X14 close_v2 retry, early release, and failure-discard mutants are killed"
    (List.for_all
       (fun id -> mutant_killed id report)
       [ "MUT.CLOSE_V2.RETRY_DEFERRED";
         "MUT.CLOSE_V2.RELEASE_BEFORE_FINALIZE";
         "MUT.CLOSE_V2.DISCARD_FINALIZE_FAILURE" ]);
  check "X15 stale quiescence reuse has a cross-generation witness"
    (mutant_killed "MUT.ACTOR.REUSE_STALE_QUIESCENCE" report);
  let require_ok label = function
    | Ok value -> value
    | Error _ -> failwith ("fixture failed: " ^ label)
  in
  let location_registry =
    require_ok "create opaque SQLite-location registry"
      (Dependability_sqlite_test_protocol.create ~maximum_live:32)
  in
  let acquire_location fixture =
    let _registry, lease =
      require_ok "acquire opaque SQLite location"
        (Dependability_sqlite_test_protocol.acquire location_registry fixture)
    in
    let location =
      require_ok "project opaque SQLite location"
        (Dependability_sqlite_test_protocol.reference location_registry lease)
    in
    (lease, location)
  in
  let open_fixture ?(fixture = Dependability_sqlite_test_protocol.In_memory)
      ~maximum_total_attempts () =
    let _lease, location = acquire_location fixture in
    Dependability_sqlite.open_database ~location ~maximum_total_attempts
  in
  let witness generation epoch =
    require_ok (Printf.sprintf "quiescence witness epoch %d" epoch)
      (Dependability_sqlite.observe_quiescence generation ~epoch
         ~live_statements:0 ~active_handlers:0 ~queued_requests:0)
  in
  let database =
    require_ok "open global-budget database"
      (open_fixture ~maximum_total_attempts:3 ())
  in
  let first_generation =
    require_ok "begin global-budget generation 1"
      (Dependability_sqlite.begin_generation database)
  in
  let first =
    Dependability_sqlite.For_test.close_as_busy ~generation:first_generation
      ~witness:(witness first_generation 1)
  in
  let second_generation =
    require_ok "begin global-budget generation 2"
      (Dependability_sqlite.begin_generation database)
  in
  let stale_epoch =
    Dependability_sqlite.observe_quiescence second_generation ~epoch:1
      ~live_statements:0 ~active_handlers:0 ~queued_requests:0
  in
  let older_epoch =
    Dependability_sqlite.observe_quiescence second_generation ~epoch:0
      ~live_statements:0 ~active_handlers:0 ~queued_requests:0
  in
  let second =
    Dependability_sqlite.For_test.close_as_busy ~generation:second_generation
      ~witness:(witness second_generation 2)
  in
  let third_generation =
    require_ok "begin global-budget generation 3"
      (Dependability_sqlite.begin_generation database)
  in
  let third =
    Dependability_sqlite.For_test.close_as_busy ~generation:third_generation
      ~witness:(witness third_generation 3)
  in
  let denied_generation = Dependability_sqlite.begin_generation database in
  check "D1 injected Busy policy cannot reset its lifetime-global budget"
    (match first, second, third, denied_generation with
     | Error (Dependability_sqlite.Database_busy _, _),
       Error (Dependability_sqlite.Database_busy _, _),
       Error (Dependability_sqlite.Lifetime_close_budget_exhausted _, consumed),
       Error (Dependability_sqlite.Lifetime_close_budget_exhausted _) ->
         Dependability_sqlite.close_attempts consumed = 1
         && Dependability_sqlite.remaining_close_attempts consumed = 0
         && Dependability_sqlite.total_close_attempts database = 3
     | _ -> false);
  check "D1a stale and older quiescence epochs are rejected across generations"
    (match stale_epoch, older_epoch with
     | Error (Dependability_sqlite.Invalid_quiescence_witness _),
       Error (Dependability_sqlite.Invalid_quiescence_witness _) -> true
     | _ -> false);
  check "D1b injected-Busy policy fixture still closes natively during disposal"
    (Dependability_sqlite.For_test.dispose database);
  let native_database =
    require_ok "open close-v2 classification database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let native_statement =
    require_ok "prepare retained close-v2 statement"
      (Dependability_sqlite.For_test.prepare native_database
         Dependability_sqlite.For_test.Retain_select_one)
  in
  let native_observation =
    require_ok "probe installed sqlite3 close semantics"
      (Dependability_sqlite.For_test.native_close_probe native_database)
  in
  let terminal_before_finalize =
    Dependability_sqlite.begin_generation native_database
  in
  let admission_before_finalize =
    Dependability_sqlite.For_test.prepare native_database
      Dependability_sqlite.For_test.Retain_select_two
  in
  let native_finalize =
    Dependability_sqlite.For_test.finalize native_database native_statement
  in
  let native_finalize_replay =
    Dependability_sqlite.For_test.finalize native_database native_statement
  in
  check "D2 installed binding is close_v2: terminal handle, deferred then finalized release"
    (native_observation = Dependability_sqlite.Native_close_v2_deferred
     && terminal_before_finalize = Error Dependability_sqlite.Database_already_released
     && (match admission_before_finalize with
         | Error (Dependability_sqlite.Prepare_failed _) -> true
         | Error (Dependability_sqlite.Body_failed _
                 | Dependability_sqlite.Statement_finalize_failed _
                 | Dependability_sqlite.Body_and_finalize_failed _)
         | Ok _ -> false)
     && native_finalize = Ok ()
     && native_finalize_replay = Error Dependability_sqlite.Finalize_already_consumed
     && Dependability_sqlite.database_state native_database
        = Dependability_sqlite.Database_released);
  let failed_finalize_database =
    require_ok "open close-v2 finalize-failure database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let failure_setup =
    Closed.execute failed_finalize_database Closed.Lifecycle_setup_finalize_failure
  in
  let failed_statement =
    require_ok "prepare retained finalize-failure statement"
      (Dependability_sqlite.For_test.prepare failed_finalize_database
         Dependability_sqlite.For_test.Retain_duplicate_failure)
  in
  let failed_step = Dependability_sqlite.For_test.step failed_statement in
  let failed_close_observation =
    require_ok "probe close-v2 before failing finalize"
      (Dependability_sqlite.For_test.native_close_probe failed_finalize_database)
  in
  let failed_finalize =
    Dependability_sqlite.For_test.finalize failed_finalize_database failed_statement
  in
  check "D2a finalize failure stays typed and cannot claim physical release"
    (failure_setup = Ok ()
     && (match failed_step with
         | Error (Dependability_sqlite.Statement_step_failed _) -> true
         | Ok (Dependability_sqlite.Row | Dependability_sqlite.Done)
         | Error _ -> false)
     && failed_close_observation = Dependability_sqlite.Native_close_v2_deferred
     && (match failed_finalize with Error _ -> true | Ok () -> false)
     && Dependability_sqlite.database_state failed_finalize_database
        = Dependability_sqlite.Database_close_v2_deferred);
  let immediate_database =
    require_ok "open immediate-close database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let immediate_generation =
    require_ok "begin immediate-close generation"
      (Dependability_sqlite.begin_generation immediate_database)
  in
  let immediate_witness = witness immediate_generation 1 in
  let immediate_close =
    Dependability_sqlite.close_database ~generation:immediate_generation
      ~witness:immediate_witness
  in
  let terminal_attempts =
    Dependability_sqlite.total_close_attempts immediate_database
  in
  check "D3 real clean close is immediate and terminal with no replay"
    (match
       immediate_close,
       Dependability_sqlite.close_database ~generation:immediate_generation
         ~witness:immediate_witness,
       Dependability_sqlite.begin_generation immediate_database
     with
     | Ok _, Error (Dependability_sqlite.Database_already_released, _),
       Error Dependability_sqlite.Database_already_released ->
         Dependability_sqlite.total_close_attempts immediate_database
         = terminal_attempts
         && terminal_attempts = 1
         && Dependability_sqlite.database_state immediate_database
            = Dependability_sqlite.Database_released
     | _ -> false);
  let composition_database =
    require_ok "open finalize-composition database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let composition =
    Closed.execute composition_database Closed.Lifecycle_statement_composition
  in
  check "D4 with_statement composes typed step and finalization failures"
    (match composition with
     | Ok { Closed.lifecycle_scope_closed = true;
            lifecycle_finalize_failure_composed = true;
            lifecycle_body_and_finalize_failure_composed = true } -> true
     | _ -> false);
  let composition_generation =
    require_ok "begin finalize-composition close generation"
      (Dependability_sqlite.begin_generation composition_database)
  in
  check "D5 real composition fixture closes through its admitted authority"
    (match
       Dependability_sqlite.close_database ~generation:composition_generation
         ~witness:(witness composition_generation 1)
     with
     | Ok _ -> true
     | Error _ -> false);
  let released_lease, released_location = acquire_location In_memory in
  let _registry, _release =
    require_ok "release opaque SQLite location before open"
      (Dependability_sqlite_test_protocol.release location_registry released_lease)
  in
  let released_open =
    Dependability_sqlite.open_database ~location:released_location
      ~maximum_total_attempts:1
  in
  let _fault_open_lease, fault_open_location =
    acquire_location (Fault_injection Open_failure)
  in
  let first_fault_open =
    Dependability_sqlite.open_database ~location:fault_open_location
      ~maximum_total_attempts:1
  in
  let replayed_fault_open =
    Dependability_sqlite.open_database ~location:fault_open_location
      ~maximum_total_attempts:1
  in
  check "D6 opaque released/open-fault locations refuse with stable typed replay"
    (match released_open, first_fault_open, replayed_fault_open with
     | Error Dependability_sqlite.Database_location_released,
       Error (Dependability_sqlite.Database_open_failed first),
       Error (Dependability_sqlite.Database_open_failed replayed) ->
         first = replayed
     | _ -> false);
  let _temporary_lease, temporary_location = acquire_location Temporary_file in
  let first_temporary_open =
    Dependability_sqlite.open_database ~location:temporary_location
      ~maximum_total_attempts:1
  in
  let replayed_temporary_open =
    Dependability_sqlite.open_database ~location:temporary_location
      ~maximum_total_attempts:1
  in
  let temporary_unavailable =
    match first_temporary_open, replayed_temporary_open with
    | Error (Dependability_sqlite.Database_open_failed first),
      Error (Dependability_sqlite.Database_open_failed replayed) ->
        first <> "" && first = replayed
    | (Ok first, Ok replayed) ->
        ignore (Dependability_sqlite.For_test.dispose first);
        ignore (Dependability_sqlite.For_test.dispose replayed);
        false
    | Ok database, Error _ | Error _, Ok database ->
        ignore (Dependability_sqlite.For_test.dispose database);
        false
    | Error _, Error _ -> false
  in
  check "D6d temporary-file location is unavailable without filesystem owner"
    temporary_unavailable;
  let close_fault_database =
    require_ok "open close-fault opaque location"
      (open_fixture ~fixture:(Fault_injection Close_failure)
         ~maximum_total_attempts:1 ())
  in
  let close_fault_generation =
    require_ok "begin close-fault generation"
      (Dependability_sqlite.begin_generation close_fault_database)
  in
  let close_fault_witness = witness close_fault_generation 1 in
  let close_fault =
    Dependability_sqlite.close_database ~generation:close_fault_generation
      ~witness:close_fault_witness
  in
  let close_fault_replay =
    Dependability_sqlite.close_database ~generation:close_fault_generation
      ~witness:close_fault_witness
  in
  check "D6a opaque close-fault location consumes authority before stable refusal"
    (match close_fault, close_fault_replay with
     | Error (Dependability_sqlite.Database_close_raised first, consumed),
       Error (Dependability_sqlite.Terminal_close_generation generation, _) ->
         first <> "" && Dependability_sqlite.close_attempts consumed = 1
         && generation = Dependability_sqlite.close_generation consumed
     | _ -> false);
  check "D6b close-fault disposal bypasses no public filename or native handle"
    (Dependability_sqlite.For_test.dispose close_fault_database);
  let busy_once_database =
    require_ok "open busy-once opaque location"
      (open_fixture ~fixture:(Fault_injection Busy_once)
         ~maximum_total_attempts:2 ())
  in
  let busy_once_generation =
    require_ok "begin busy-once generation"
      (Dependability_sqlite.begin_generation busy_once_database)
  in
  let busy_once_first =
    Dependability_sqlite.close_database ~generation:busy_once_generation
      ~witness:(witness busy_once_generation 1)
  in
  let busy_once_replay_generation =
    require_ok "begin busy-once replay generation"
      (Dependability_sqlite.begin_generation busy_once_database)
  in
  let busy_once_replay =
    Dependability_sqlite.close_database ~generation:busy_once_replay_generation
      ~witness:(witness busy_once_replay_generation 2)
  in
  check "D6c opaque busy-once location replays into one native terminal close"
    (match busy_once_first, busy_once_replay with
     | Error (Dependability_sqlite.Database_busy _, first), Ok second ->
         Dependability_sqlite.close_attempts first = 1
         && Dependability_sqlite.close_attempts second = 1
         && Dependability_sqlite.total_close_attempts busy_once_database = 2
         && Dependability_sqlite.database_state busy_once_database
            = Dependability_sqlite.Database_released
     | _ -> false);
  let closed_database =
    require_ok "open closed-operation completion database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let closed_receipt : Closed.completion_receipt =
    { receipt_digest = "receipt-digest"; request_id = "request-1";
      action = "verify"; scope = "whole-system";
      verdict = Closed.Succeeded; output = "ok";
      source_revision = "source-1"; source_clean = true;
      configuration_digest = "configuration-1";
      authority_digest = "authority-1"; run_id = "run-1";
      recorded_at_ns = 10L }
  in
  let closed_observation : Closed.completion_observation =
    { receipt_digest = closed_receipt.receipt_digest; surface = "ocaml-api";
      plane = "control-plane"; fractal_coordinate = "L6/completion";
      ooda_phase = "observe"; rca_origin = None; mediation = "closed-owner";
      resource = "sqlite"; duration_ns = 2L; observed_at_ns = 11L;
      event_json = "{}" }
  in
  let closed_interaction : Closed.completion_interaction =
    { interaction_id = "interaction-1"; run_id = "run-1"; actor = "tester";
      kind = Closed.Decision; body = "closed operation";
      body_digest = "body-digest"; recorded_at_ns = 12L }
  in
  let closed_source : Closed.current_source =
    { source_revision = closed_receipt.source_revision; source_clean = true;
      configuration_digest = closed_receipt.configuration_digest;
      authority_digest = closed_receipt.authority_digest }
  in
  let initialize_closed =
    Closed.execute closed_database Closed.Completion_initialize_v1
  in
  let record_first =
    Closed.execute closed_database
      (Closed.Completion_record (closed_receipt, closed_observation))
  in
  let record_replay =
    Closed.execute closed_database
      (Closed.Completion_record (closed_receipt, closed_observation))
  in
  let interaction_first =
    Closed.execute closed_database
      (Closed.Completion_append_interaction closed_interaction)
  in
  let interaction_replay =
    Closed.execute closed_database
      (Closed.Completion_append_interaction closed_interaction)
  in
  let counts = Closed.execute closed_database Closed.Completion_counts in
  let receipt_current =
    Closed.execute closed_database
      (Closed.Completion_receipt_current
         (closed_source, closed_receipt.receipt_digest))
  in
  let success_current =
    Closed.execute closed_database
      (Closed.Completion_has_current_success
         (closed_source, closed_receipt.action, closed_receipt.scope))
  in
  check "D6e closed completion operations replay and read back exact changes"
    (initialize_closed = Ok ()
     && record_first = Ok Closed.Inserted
     && record_replay = Ok Closed.Replayed
     && interaction_first = Ok Closed.Inserted
     && interaction_replay = Ok Closed.Replayed
     && counts = Ok ({ receipts = 1; observations = 2; interactions = 1 }
                     : Closed.completion_counts)
     && receipt_current = Ok true && success_current = Ok true);
  let divergent_receipt =
    { closed_receipt with receipt_digest = "different-receipt" }
  in
  check "D6f closed completion replay conflict changes no stored row"
    (match
       Closed.execute closed_database
         (Closed.Completion_record (divergent_receipt, closed_observation)),
       Closed.execute closed_database Closed.Completion_counts
     with
     | Error Closed.Divergent_replay,
       Ok { receipts = 1; observations = 2; interactions = 1 } -> true
     | _ -> false);
  let captured_scope = ref None in
  let scoped_read =
    Closed.with_transaction closed_database ~mode:Closed.Read_only
      (fun scope ->
        captured_scope := Some scope;
        match Closed.execute_in scope Closed.Completion_counts with
        | Ok counts -> Ok counts
        | Error error -> Error error)
  in
  let stale_scope =
    match !captured_scope with
    | None -> None
    | Some scope -> Some (Closed.execute_in scope Closed.Completion_counts)
  in
  let read_only_write =
    Closed.with_transaction closed_database ~mode:Closed.Read_only
      (fun scope ->
        match
          Closed.execute_in scope
            (Closed.Completion_append_interaction
               { closed_interaction with interaction_id = "interaction-2" })
        with
        | Ok value -> Ok value
        | Error error -> Error error)
  in
  check "D6g closed transaction scopes invalidate and reject writes when read-only"
    (match scoped_read, stale_scope, read_only_write with
     | Ok { receipts = 1; observations = 2; interactions = 1 },
       Some (Error Closed.Transaction_scope_closed),
       Error Closed.Write_in_read_only_scope -> true
     | _ -> false);
  check "D6h a volatile database binds one closed operation family"
    (match Closed.execute closed_database Closed.Lifecycle_observe_changes with
     | Error (Closed.Family_mismatch _) -> true
     | _ -> false);
  check "D6i closed operation source digest covers its exact denominator"
    (String.length Closed.source_digest = 64
     && Closed.source_digest
        <> Closed.For_test.source_digest_with_mutation
             Closed.For_test.Drop_completion_counts);
  let effect_database =
    require_ok "open closed-operation effect database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let effect_pending : Closed.effect_row =
    { schema_version = 1; stored_key = "effect-key-1";
      stored_request_digest = "request-digest";
      stored_target_digest = "target-digest";
      stored_target_authority_digest = "target-authority-digest";
      stored_effect_kind = "verification-suite-execution";
      stored_state = "pending"; stored_disposition = None;
      stored_output = None; stored_output_digest = None;
      stored_receipt_digest = None; stored_diagnostic = None;
      stored_no_replay = false; stored_row_digest = "pending-row-digest" }
  in
  let effect_applied : Closed.effect_row =
    { effect_pending with stored_state = "applied";
      stored_disposition = Some "first-applied";
      stored_output = Some "output";
      stored_output_digest = Some "output-digest";
      stored_receipt_digest = Some "receipt-digest";
      stored_row_digest = "applied-row-digest" }
  in
  let effect_initialize =
    Closed.execute effect_database Closed.Effect_initialize_v1
  in
  let effect_absent =
    Closed.execute effect_database (Closed.Effect_read effect_pending.stored_key)
  in
  let effect_insert =
    Closed.execute effect_database (Closed.Effect_insert_pending effect_pending)
  in
  let effect_conflicting_insert =
    Closed.execute effect_database
      (Closed.Effect_insert_pending
         { effect_pending with stored_request_digest = "different-request";
                               stored_row_digest = "different-row" })
  in
  let effect_bad_cas =
    Closed.execute effect_database
      (Closed.Effect_cas_pending
         { expected = { effect_pending with stored_row_digest = "stale-row" };
           replacement = effect_applied })
  in
  let effect_after_bad_cas =
    Closed.execute effect_database (Closed.Effect_read effect_pending.stored_key)
  in
  let effect_good_cas =
    Closed.execute effect_database
      (Closed.Effect_cas_pending
         { expected = effect_pending; replacement = effect_applied })
  in
  let effect_readback =
    Closed.execute effect_database (Closed.Effect_read effect_pending.stored_key)
  in
  check "D6j closed effect insert and CAS are atomic with exact readback"
    (effect_initialize = Ok () && effect_absent = Ok None
     && effect_insert = Ok effect_pending
     && effect_conflicting_insert = Ok effect_pending
     && (match effect_bad_cas with Error (Closed.Operation_failed _) -> true | _ -> false)
     && effect_after_bad_cas = Ok (Some effect_pending)
     && effect_good_cas = Ok effect_applied
     && effect_readback = Ok (Some effect_applied));
  let effect_read_only_write =
    Closed.with_transaction effect_database ~mode:Closed.Read_only
      (fun scope ->
        Closed.execute_in scope
          (Closed.Effect_insert_pending
             { effect_pending with stored_key = "effect-key-2" }))
  in
  check "D6k closed effect family rejects cross-family and read-only writes"
    (effect_read_only_write = Error Closed.Write_in_read_only_scope
     && (match
           Closed.execute closed_database Closed.Effect_initialize_v1,
           Closed.execute effect_database Closed.Completion_counts
         with
         | Error (Closed.Family_mismatch _),
           Error (Closed.Family_mismatch _) -> true
         | _ -> false));
  check "D6l closed operation digest detects a missing effect CAS"
    (Closed.source_digest
     <> Closed.For_test.source_digest_with_mutation
          Closed.For_test.Drop_effect_cas_pending
     && Closed.source_digest
        <> Closed.For_test.source_digest_with_mutation
             Closed.For_test.Drop_completion_store_owner_cas
     && Closed.source_digest
        <> Closed.For_test.source_digest_with_mutation
             Closed.For_test.Drop_dispatch_store_pointer_cas
     && Closed.source_digest
        <> Closed.For_test.source_digest_with_mutation
             Closed.For_test.Drop_authority_store_pointer_cas);
  let scoped_database =
    require_ok "open scoped-data database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let literal_key = "key'; DROP TABLE ledger; --" in
  let literal_blob = "\000\255binary\000payload" in
  let scoped_result =
    Closed.execute scoped_database
      (Closed.Lifecycle_scoped_data_contract
         { lifecycle_literal_key = literal_key;
           lifecycle_literal_blob = literal_blob;
           lifecycle_literal_wide = Int64.max_int;
           lifecycle_literal_small = 42 })
  in
  check "D7 scoped bind/column operations preserve binary data and reject misuse"
    (match scoped_result with
     | Ok observation ->
         observation.lifecycle_selected_key = literal_key
         && observation.lifecycle_selected_blob = literal_blob
         && observation.lifecycle_selected_wide = Int64.max_int
         && observation.lifecycle_selected_small = 42
         && observation.lifecycle_change_count = 1
         && observation.lifecycle_column_before_row_rejected
         && observation.lifecycle_type_mismatch_rejected
         && observation.lifecycle_invalid_column_rejected
         && observation.lifecycle_escaped_bind_rejected
         && observation.lifecycle_escaped_column_rejected
     | Error _ -> false);
  let schema_rejections =
    Closed.execute scoped_database Closed.Lifecycle_schema_rejection_contract
  in
  check "D8 schema execution is closed to one admitted DDL statement"
    (schema_rejections = Ok true);
  let transaction_database =
    require_ok "open transaction database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let transaction_setup =
    Closed.execute transaction_database Closed.Lifecycle_transaction_initialize
  in
  let insert_value scope value =
    Closed.execute_in scope (Closed.Lifecycle_transaction_insert value)
  in
  let count_values database =
    Closed.execute database Closed.Lifecycle_transaction_count
  in
  let committed =
    Closed.with_transaction transaction_database ~mode:Closed.Read_write
      (fun scope ->
        match insert_value scope "commit" with
        | Ok () -> Ok "committed"
        | Error error -> Error error)
  in
  let rolled_back =
    Closed.with_transaction transaction_database ~mode:Closed.Read_write
      (fun scope ->
        match insert_value scope "rollback" with
        | Ok () -> Error (Closed.Operation_failed "body-refused")
        | Error error -> Error error)
  in
  let exception_rolled_back =
    Closed.with_transaction transaction_database ~mode:Closed.Read_write
      (fun scope ->
        match insert_value scope "exception" with
        | Ok () -> failwith "body-raised"
        | Error error -> Error error)
  in
  let nested_result = ref None in
  let nested_outer =
    Closed.with_transaction transaction_database ~mode:Closed.Read_write
      (fun _scope ->
        nested_result :=
          Some
            (Closed.with_transaction transaction_database ~mode:Closed.Read_write
               (fun _ -> Ok ()));
        Error (Closed.Operation_failed "outer-rollback"))
  in
  check "D9 owned transactions commit only Ok and roll back Error/exception"
    (transaction_setup = Ok () && committed = Ok "committed"
     && rolled_back = Error (Closed.Operation_failed "body-refused")
     && (match exception_rolled_back with Error (Closed.Operation_failed _) -> true | _ -> false)
     && (match !nested_result with
         | Some (Error (Closed.Operation_failed _)) -> true
         | _ -> false)
     && nested_outer = Error (Closed.Operation_failed "outer-rollback")
     && count_values transaction_database = Ok 1
     && Dependability_sqlite.transaction_status transaction_database
        = Dependability_sqlite.Transaction_idle);
  let begin_fault_database =
    require_ok "open begin-fault database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let body_calls = ref 0 in
  let begin_fault =
    Dependability_sqlite.For_test.with_transaction_fault
      Dependability_sqlite.For_test.Fail_transaction_begin begin_fault_database
      (fun _ -> incr body_calls; Ok ())
  in
  let commit_fault =
    Dependability_sqlite.For_test.with_transaction_fault
      Dependability_sqlite.For_test.Fail_transaction_commit transaction_database
      (fun scope ->
        match insert_value scope "commit-fault" with
        | Ok () -> Ok ()
        | Error error -> Error error)
  in
  let rollback_fault_database =
    require_ok "open rollback-fault database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let rollback_fault =
    Dependability_sqlite.For_test.with_transaction_fault
      Dependability_sqlite.For_test.Fail_transaction_rollback
      rollback_fault_database (fun _ -> Error "body-and-rollback")
  in
  let poisoned_exec =
    Closed.execute rollback_fault_database Closed.Lifecycle_transaction_initialize
  in
  let commit_rollback_fault_database =
    require_ok "open commit-rollback-fault database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let commit_rollback_fault =
    Dependability_sqlite.For_test.with_transaction_fault
      Dependability_sqlite.For_test.Fail_transaction_commit_and_rollback
      commit_rollback_fault_database (fun _ -> Ok ())
  in
  check "D10 transaction boundary failures compose and failed cleanup poisons authority"
    (!body_calls = 0
     && (match begin_fault with
         | Error (Dependability_sqlite.Transaction_begin_failed _) -> true
         | _ -> false)
     && (match commit_fault with
         | Error (Dependability_sqlite.Transaction_commit_failed _) -> true
         | _ -> false)
     && count_values transaction_database = Ok 1
     && (match rollback_fault with
         | Error
             (Dependability_sqlite.Transaction_body_and_rollback_failed
                ("body-and-rollback", _)) -> true
         | _ -> false)
     && Dependability_sqlite.transaction_status rollback_fault_database
        = Dependability_sqlite.Transaction_indeterminate
     && (match poisoned_exec with
         | Error (Closed.Operation_failed _) -> true
         | _ -> false)
     && (match commit_rollback_fault with
         | Error
             (Dependability_sqlite.Transaction_commit_and_rollback_failed _) ->
             true
         | _ -> false)
     && Dependability_sqlite.transaction_status commit_rollback_fault_database
        = Dependability_sqlite.Transaction_indeterminate);
  let quiescence_database =
    require_ok "open internal-quiescence database"
      (open_fixture ~maximum_total_attempts:1 ())
  in
  let quiescence_generation =
    require_ok "begin internal-quiescence generation"
      (Dependability_sqlite.begin_generation quiescence_database)
  in
  let live_observation =
    Closed.execute quiescence_database
      (Closed.Lifecycle_live_statement_observation quiescence_generation)
  in
  let quiescence_after =
    Dependability_sqlite.observe_internal_quiescence quiescence_generation
      ~epoch:1 ~active_handlers:0 ~queued_requests:0
  in
  let intervals =
    Dependability_sqlite.finalize_interval_observations quiescence_database
  in
  check "D11 internal quiescence and finalize intervals share scoped lifetime identity"
    ((match live_observation with
         | Ok { Closed.lifecycle_live_count = 1;
                lifecycle_quiescence_refused = true } -> true
         | _ -> false)
     && Dependability_sqlite.live_statement_count quiescence_database = 0
     && not (Dependability_sqlite.finalize_interval_active quiescence_database)
     && (match intervals with
         | [ interval ] ->
             interval.database_identity
             = Dependability_sqlite.database_identity quiescence_database
             && interval.statement_identity > 0
             && interval.interval_identity > 0
             && interval.live_statements_at_enter = 1
             && interval.live_statements_at_exit = 0
             && interval.finalize_interval_outcome
                = Dependability_sqlite.Finalize_interval_succeeded
         | _ -> false)
     && (match quiescence_after with Ok _ -> true | Error _ -> false));
  check "D12 typed SQLite errors have stable nonempty renderings"
    (List.for_all
       (fun detail -> String.trim detail <> "")
       [ Dependability_sqlite.string_of_finalize_error
           Dependability_sqlite.Finalize_already_consumed;
         Dependability_sqlite.string_of_statement_error
           (Dependability_sqlite.Prepare_failed "prepare");
         Dependability_sqlite.string_of_statement_use_error
           (Dependability_sqlite.Statement_column_without_row 0);
         Dependability_sqlite.string_of_database_error
           Dependability_sqlite.Database_transaction_indeterminate;
         Dependability_sqlite.string_of_transaction_error Fun.id
           (Dependability_sqlite.Transaction_body_failed "body");
         Dependability_sqlite.string_of_close_error
           Dependability_sqlite.Database_already_released ]);
  Printf.printf "sqlite_lifecycle_model: %d passed, %d failed\n" !passed !failed;
  Printf.printf
    "sqlite_lifecycle_census: statement_states=%d close_v2_states=%d actor_states=%d laws=%d mutants=%d\n"
    report.statement_states report.close_v2_states report.actor_states
    (List.length report.laws) (List.length report.mutants);
  let self = Suite_telemetry.observe ~suite:"test_sqlite_lifecycle_model" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_dependability_core; Stanza.hermes_dependability_sqlite; Stanza.hermes_dependability_solver; Stanza.hermes_dependability_process; Stanza.hermes_dependability_topology ]);
  exit (Suite_telemetry.exit_code self)
