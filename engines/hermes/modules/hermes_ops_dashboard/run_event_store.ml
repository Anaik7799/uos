module Chan = Domainslib.Chan

type close_resume = Resume_open | Resume_failed of string

type lifecycle =
  | Open
  | Closing of int
  | Closed
  | Close_failed of close_resume * string
  | Failed of string

type control = {
  mutex : Mutex.t;
  condition : Condition.t;
  mutable lifecycle : lifecycle;
  mutable next_close_generation : int;
  mutable close_receipts : (int * (unit, string) result) list;
  mutable writer_terminal : (unit, string) result option;
}

type fault_injection =
  | Fault_drop_next_reply
  | Fault_fail_next_failure_drain

type _ request =
  | Append : Run_model.event -> unit request
  | Events : string -> Run_model.event list request
  | Events_after : string * int64 -> Run_model.event list request
  | Snapshot : string -> Run_snapshot.t request
  | Runs : int -> Run_snapshot.summary list request
  | Connection_check : unit request

type message =
  | Request : 'a request * ('a, string) result Chan.t -> message
  | Terminal_failure of string * (unit, string) result Chan.t
  | Install_close_blocker of (unit, string) result Chan.t
  | Release_close_blocker of (unit, string) result Chan.t
  | Arm_fault of fault_injection * (unit, string) result Chan.t
  | Exercise_finalize_failure of (unit, string) result Chan.t
  | Inject_history of Run_model.event * (unit, string) result Chan.t
  | Inject_history_fault of string * (unit, string) result Chan.t
  | Verify_append_only_guards of (unit, string) result Chan.t
  | Force_cleanup of (unit, string) result Chan.t
  | Stop of (unit, string) result Chan.t

type t = {
  chan : message Chan.t;
  writer : unit Domain.t;
  control : control;
  in_flight : int Atomic.t;
  active_handlers : int Atomic.t;
  queued_requests : int Atomic.t;
  database : Dependability_sqlite.owned_database;
  writer_exited : bool Atomic.t;
  writer_join_claimed : bool Atomic.t;
  writer_joined : bool Atomic.t;
  short_deadline_once : bool Atomic.t;
}

type prefix_rca_origin =
  | Prefix_specification
  | Prefix_implementation
  | Prefix_environment
  | Prefix_evidence
  | Prefix_control

type prefix_prerequisite =
  | Typed_execution_identity_current_carrier
  | Admitted_plan_current_carrier
  | Typed_prefix_denominator_current_carrier
  | Dispatch_claim_current_carrier
  | Owner_session_current_carrier
  | Terminal_target_disposition_current_carrier

type prefix_diagnostic = {
  prefix_prerequisite : prefix_prerequisite;
  prefix_code : string;
  prefix_coordinate : string;
  prefix_origin : prefix_rca_origin;
}

let prefix_prerequisite_id = function
  | Typed_execution_identity_current_carrier ->
      "typed-execution-identity-current-carrier"
  | Admitted_plan_current_carrier -> "admitted-plan-current-carrier"
  | Typed_prefix_denominator_current_carrier ->
      "typed-prefix-denominator-current-carrier"
  | Dispatch_claim_current_carrier -> "dispatch-claim-current-carrier"
  | Owner_session_current_carrier -> "owner-session-current-carrier"
  | Terminal_target_disposition_current_carrier ->
      "terminal-target-disposition-current-carrier"

let prefix_diagnostic prerequisite =
  { prefix_prerequisite = prerequisite;
    prefix_code =
      "event-prefix-prerequisite-unavailable:"
      ^ prefix_prerequisite_id prerequisite;
    prefix_coordinate = "L3/Observe/run-event-prefix";
    prefix_origin = Prefix_evidence }

let prefix_prerequisite_status prerequisite =
  Error (prefix_diagnostic prerequisite)

let prefix_diagnostic_code diagnostic = diagnostic.prefix_code
let prefix_diagnostic_prerequisite diagnostic = diagnostic.prefix_prerequisite
let prefix_diagnostic_coordinate diagnostic = diagnostic.prefix_coordinate
let prefix_diagnostic_origin diagnostic = diagnostic.prefix_origin

type event_prefix_current = |

let prepare_event_prefix _ =
  Error (prefix_diagnostic Admitted_plan_current_carrier)

let event_prefix_production_posture = `Implemented_unavailable

let prefix_sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let prefix_frame value = string_of_int (String.length value) ^ ":" ^ value

let prefix_digest_fields fields =
  fields
  |> List.map (fun (name, value) -> prefix_frame name ^ prefix_frame value)
  |> String.concat ""
  |> prefix_sha256

let prefix_prerequisites =
  [ Typed_execution_identity_current_carrier;
    Admitted_plan_current_carrier;
    Typed_prefix_denominator_current_carrier;
    Dispatch_claim_current_carrier;
    Owner_session_current_carrier;
    Terminal_target_disposition_current_carrier ]

let event_prefix_source_fields =
  [ ("schema", "run-event-prefix-owner-v1");
    ("closed-event-ledger-source",
     Dependability_sqlite.Closed_operation.source_digest);
    ("ledger-query-owner", "run-event-store-actor-only");
    ("prerequisite-denominator",
     prefix_prerequisites
     |> List.map prefix_prerequisite_id
     |> String.concat ",");
    ("execution-binding", "typed-current-exact");
    ("plan-binding", "admitted-current-exact");
    ("prefix-denominator", "typed-plan-derived-exact");
    ("dispatch-binding", "claim-current-exact");
    ("owner-session-binding", "current-generation-exact");
    ("target-disposition", "terminal-only");
    ("event-identity", "exact-unique-event-id-and-digest");
    ("sequence-binding", "zero-based-contiguous-exact-prefix");
    ("previous-digest-binding", "complete-hash-link-chain");
    ("gap-policy", "refuse");
    ("duplicate-policy", "refuse");
    ("noncontiguous-policy", "refuse");
    ("running-target-policy", "refuse-running-or-unknown");
    ("context-policy", "refuse-cross-execution-plan-prefix");
    ("currentness-policy", "refuse-stale-owner-session");
    ("event-list-projection", "absent");
    ("event-payload-projection", "absent");
    ("store-handle-projection", "absent");
    ("caller-input-seams", "no-digest-no-callback");
    ("current-construction", "owner-readback-only-unavailable");
    ("production-posture", "implemented-unavailable") ]

let event_prefix_source_digest =
  prefix_digest_fields event_prefix_source_fields

module Closed = Dependability_sqlite.Closed_operation

type stored_event = Closed.event_row = {
  run_id : string;
  sequence : int64;
  event_id : string;
  event_digest : string;
  event_json : string;
}

let ( let* ) result f =
  match result with Ok value -> f value | Error _ as error -> error

let attach_cleanup_error original = function
  | Ok () -> Error original
  | Error cleanup -> Error (original ^ "; cleanup failed: " ^ cleanup)

let closed_error error = Closed.string_of_error error

let execute ?scope db operation =
  let result =
    match scope with
    | None -> Closed.execute db operation
    | Some scope -> Closed.execute_in scope operation
  in
  match result with Ok value -> Ok value | Error error -> Error (closed_error error)

let with_transaction db ~write f =
  let mode = if write then Closed.Read_write else Closed.Read_only in
  match
    Closed.with_transaction db ~mode (fun scope ->
      match f scope with
      | Ok value -> Ok value
      | Error detail -> Error (Closed.Operation_failed detail))
  with
  | Ok value -> Ok value
  | Error error -> Error (closed_error error)

let verify_connection_configuration db =
  execute db Closed.Event_verify_configuration

let configure db = execute db Closed.Event_configure

let initialize_schema db = execute db Closed.Event_initialize_v1

let decode_event text =
  try Run_model.of_json (Yojson.Safe.from_string text) with
  | Yojson.Json_error error -> Error ("stored event JSON is malformed: " ^ error)
  | exn -> Error ("stored event JSON decode failed: " ^ Printexc.to_string exn)

let stored_events_for_run ?scope db run_id =
  execute ?scope db (Closed.Event_read_stream run_id)

let decode_rows rows =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | row :: rest ->
        let* event = decode_event row.event_json in
        if event.Run_model.run_id <> row.run_id
           || event.sequence <> row.sequence
           || event.event_id <> row.event_id
           || event.digest <> row.event_digest
        then Error ("stored event columns disagree with canonical JSON: " ^ row.event_id)
        else loop (event :: acc) rest
  in
  loop [] rows

let load_events ?scope db run_id =
  let* rows = stored_events_for_run ?scope db run_id in
  decode_rows rows

let canonical_event_json event =
  Run_model.canonical_string (Run_model.to_json event)

let conflict_rows ~scope db (event : Run_model.event) =
  execute ~scope db
    (Closed.Event_conflicts
       { conflict_run_id = event.run_id; conflict_sequence = event.sequence;
         conflict_event_id = event.event_id })

let exact_replay row (event : Run_model.event) event_json =
  row.run_id = event.run_id
  && row.sequence = event.sequence
  && row.event_id = event.event_id
  && row.event_digest = event.digest
  && row.event_json = event_json

let validate_extension ~scope db event =
  let* existing = load_events ~scope db event.Run_model.run_id in
  match existing with
  | [] ->
      let* _ = Run_snapshot.fold [ event ] in
      Ok ()
  | _ ->
      let* snapshot = Run_snapshot.fold existing in
      begin match Run_snapshot.apply snapshot event with
      | Ok (Run_snapshot.Applied _) -> Ok ()
      | Ok (Run_snapshot.Duplicate _) ->
          Error "divergent replay escaped immutable identity checks"
      | Ok (Run_snapshot.Gap { expected; observed }) ->
          Error
            (Printf.sprintf "run-event sequence gap: expected %Ld observed %Ld"
               expected observed)
      | Error _ as error -> error
      end

let insert_event ~scope db (event : Run_model.event) event_json =
  execute ~scope db
    (Closed.Event_insert
       { run_id = event.run_id; sequence = event.sequence;
         event_id = event.event_id; event_digest = event.digest; event_json })

let do_append db event =
  let* event_json = canonical_event_json event in
  with_transaction db ~write:true (fun scope ->
      let* conflicts = conflict_rows ~scope db event in
      match conflicts with
      | [ row ] when exact_replay row event event_json -> Ok ()
      | _ :: _ ->
          Error
            (Printf.sprintf
               "divergent run-event replay: run=%s sequence=%Ld event_id=%s"
               event.Run_model.run_id event.sequence event.event_id)
      | [] ->
          let* () = validate_extension ~scope db event in
          insert_event ~scope db event event_json)

let do_events_after db run_id sequence =
  if sequence < 0L then Error "events_after sequence must be nonnegative"
  else
    with_transaction db ~write:false (fun scope ->
        let* events = load_events ~scope db run_id in
        let* () =
          match events with
          | [] -> Ok ()
          | _ -> let* _ = Run_snapshot.fold events in Ok ()
        in
        Ok (List.filter (fun (event : Run_model.event) -> event.sequence > sequence) events))

let do_events db run_id =
  with_transaction db ~write:false (fun scope ->
      let* events = load_events ~scope db run_id in
      let* () =
        match events with
        | [] -> Ok ()
        | _ -> let* _ = Run_snapshot.fold events in Ok ()
      in
      Ok events)

let rebuild_snapshot ?scope db run_id =
  let* events = load_events ?scope db run_id in
  match events with
  | [] -> Error ("missing or empty run-event stream: " ^ run_id)
  | _ -> Run_snapshot.fold events

let do_snapshot db run_id =
  with_transaction db ~write:false (fun scope -> rebuild_snapshot ~scope db run_id)

let query_run_ids ~scope db limit =
  execute ~scope db (Closed.Event_run_ids limit)

let do_runs db limit =
  if limit < 0 then Error "runs limit must be nonnegative"
  else if limit = 0 then Ok []
  else
    with_transaction db ~write:false (fun scope ->
        let* run_ids = query_run_ids ~scope db limit in
        let rec rebuild acc = function
          | [] -> Ok (List.rev acc)
          | run_id :: rest ->
              let* snapshot = rebuild_snapshot ~scope db run_id in
              rebuild (Run_snapshot.summary snapshot :: acc) rest
        in
        rebuild [] run_ids)

let handle : type a.
    Dependability_sqlite.owned_database ->
    a request -> (a, string) Stdlib.result =
  fun db -> function
    | Append event -> do_append db event
    | Events run_id -> do_events db run_id
    | Events_after (run_id, sequence) -> do_events_after db run_id sequence
    | Snapshot run_id -> do_snapshot db run_id
    | Runs limit -> do_runs db limit
    | Connection_check -> verify_connection_configuration db

let set_failed control reason =
  Mutex.lock control.mutex;
  begin match control.lifecycle with
  | Closed | Close_failed _ | Closing _ -> ()
  | Open | Failed _ -> control.lifecycle <- Failed reason
  end;
  Condition.broadcast control.condition;
  Mutex.unlock control.mutex

let failure_error reason = "run-event actor failed: " ^ reason

let current_failure control =
  Mutex.lock control.mutex;
  let result =
    match control.lifecycle with
    | Failed reason -> Some reason
    | Open | Closing _ | Closed | Close_failed _ -> None
  in
  Mutex.unlock control.mutex;
  result

let send_reply reply result =
  try Chan.send reply result; Ok ()
  with exn -> Error ("actor reply send failed: " ^ Printexc.to_string exn)

let send_reply_or_raise reply result =
  match send_reply reply result with
  | Ok () -> ()
  | Error reason -> failwith reason

let default_request_timeout_ns = 7_000_000_000L
let injected_request_timeout_ns = 500_000_000L
let close_timeout_ns = 7_000_000_000L

let deadline_after timeout_ns =
  Int64.add (Mtime_clock.elapsed_ns ()) timeout_ns

let before_deadline deadline =
  Int64.compare (Mtime_clock.elapsed_ns ()) deadline < 0

let recv_before ~label ~deadline channel =
  let rec loop () =
    match Chan.recv_poll channel with
    | Some value -> Ok value
    | None when before_deadline deadline ->
        Unix.sleepf 0.0005;
        loop ()
    | None -> Error (label ^ " deadline exceeded")
    | exception exn -> Error (label ^ ": " ^ Printexc.to_string exn)
  in
  loop ()

let record_writer_terminal control result =
  Mutex.lock control.mutex;
  if Option.is_none control.writer_terminal then
    control.writer_terminal <- Some result;
  Condition.broadcast control.condition;
  Mutex.unlock control.mutex

let join_writer_before t deadline =
  let rec await_exit () =
    if Atomic.get t.writer_exited then Ok ()
    else if before_deadline deadline then begin
      Unix.sleepf 0.0005;
      await_exit ()
    end else Error "close writer exit deadline exceeded"
  in
  let rec await_join () =
    if Atomic.get t.writer_joined then Ok ()
    else if before_deadline deadline then begin
      Unix.sleepf 0.0005;
      await_join ()
    end else Error "close writer join deadline exceeded"
  in
  let* () = await_exit () in
  if Atomic.get t.writer_joined then Ok ()
  else if Atomic.compare_and_set t.writer_join_claimed false true then
    match Domain.join t.writer with
    | () ->
        Atomic.set t.writer_joined true;
        Ok ()
    | exception exn ->
        Atomic.set t.writer_join_claimed false;
        Error ("close writer join failed: " ^ Printexc.to_string exn)
  else await_join ()

let begin_handler active_handlers queued_requests =
  ignore (Atomic.fetch_and_add queued_requests (-1));
  ignore (Atomic.fetch_and_add active_handlers 1)

let end_handler active_handlers =
  ignore (Atomic.fetch_and_add active_handlers (-1))

let install_close_blocker close_blocker =
  if !close_blocker then Error "injected policy-Busy is already armed"
  else begin
    close_blocker := true;
    Ok ()
  end

let release_close_blocker close_blocker =
  if !close_blocker then begin
    close_blocker := false;
    Ok ()
  end else Error "injected policy-Busy is not armed"

let close_actor_database_attempt db close_blocker close_epoch active_handlers
    queued_requests =
  match Dependability_sqlite.begin_generation db with
  | Error error -> Error (Dependability_sqlite.string_of_close_error error)
  | Ok generation ->
      close_epoch := !close_epoch + 1;
      begin match
        Dependability_sqlite.observe_internal_quiescence generation
          ~epoch:!close_epoch ~active_handlers:(Atomic.get active_handlers)
          ~queued_requests:(Atomic.get queued_requests)
      with
      | Error error -> Error (Dependability_sqlite.string_of_close_error error)
      | Ok witness ->
          let result =
            if !close_blocker then
              Dependability_sqlite.For_test.close_as_busy ~generation ~witness
            else Dependability_sqlite.close_database ~generation ~witness
          in
          begin match result with
          | Ok _ -> Ok ()
          | Error (error, _) ->
              let rendered = Dependability_sqlite.string_of_close_error error in
              if !close_blocker then
                Error
                  ("injected policy Busy: database remains open: " ^ rendered)
              else Error rendered
          end
      end

let exercise_finalize_failure db =
  execute db Closed.Event_test_finalize_failure

let inject_history db event =
  let* event_json = canonical_event_json event in
  with_transaction db ~write:true (fun scope ->
      insert_event ~scope db event event_json)

let inject_history_fault db run_id =
  execute db (Closed.Event_test_insert_malformed run_id)

let verify_append_only_guards db =
  execute db Closed.Event_test_verify_append_only

let force_cleanup_database db =
  if Dependability_sqlite.For_test.dispose db then Ok ()
  else Error "test-only forced database cleanup failed"

let rec failed_loop db chan control close_blocker close_epoch fault
    active_handlers queued_requests reason =
  match Chan.recv chan with
  | Request (_, reply) ->
      begin_handler active_handlers queued_requests;
      send_reply_or_raise reply (Error (failure_error reason));
      end_handler active_handlers;
      failed_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests reason
  | Terminal_failure (_, reply) ->
      send_reply_or_raise reply (Error (failure_error reason));
      failed_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests reason
  | Install_close_blocker reply ->
      send_reply_or_raise reply (Error (failure_error reason));
      failed_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests reason
  | Release_close_blocker reply ->
      send_reply_or_raise reply (release_close_blocker close_blocker);
      failed_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests reason
  | Arm_fault (_, reply) ->
      send_reply_or_raise reply (Error (failure_error reason));
      failed_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests reason
  | Exercise_finalize_failure reply ->
      send_reply_or_raise reply (Error (failure_error reason));
      failed_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests reason
  | Inject_history (_, reply)
  | Inject_history_fault (_, reply)
  | Verify_append_only_guards reply ->
      send_reply_or_raise reply (Error (failure_error reason));
      failed_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests reason
  | Force_cleanup reply ->
      let result = force_cleanup_database db in
      record_writer_terminal control result;
      send_reply_or_raise reply result
  | Stop reply ->
      let result =
        close_actor_database_attempt db close_blocker close_epoch active_handlers
          queued_requests
      in
      begin match result with Ok () -> record_writer_terminal control result | Error _ -> () end;
      send_reply_or_raise reply result;
      begin match result with
      | Ok () -> ()
      | Error _ ->
          failed_loop db chan control close_blocker close_epoch fault
            active_handlers queued_requests reason
      end

let rec writer_loop db chan control close_blocker close_epoch fault
    active_handlers queued_requests =
  match Chan.recv chan with
  | Request (request, reply) ->
      begin_handler active_handlers queued_requests;
      begin match !fault with
      | Some Fault_fail_next_failure_drain ->
          end_handler active_handlers;
          failwith "injected next failure drain"
      | Some Fault_drop_next_reply | None ->
      begin match current_failure control with
      | Some reason ->
          begin match !fault with
          | Some Fault_drop_next_reply -> fault := None
          | Some Fault_fail_next_failure_drain | None ->
              send_reply_or_raise reply (Error (failure_error reason))
          end;
          end_handler active_handlers;
          writer_loop db chan control close_blocker close_epoch fault
            active_handlers queued_requests
      | None ->
          begin match handle db request with
          | result ->
              let result =
                match current_failure control with
                | Some reason -> Error (failure_error reason)
                | None -> result
              in
              begin match !fault with
              | Some Fault_drop_next_reply -> fault := None
              | Some Fault_fail_next_failure_drain | None ->
                  send_reply_or_raise reply result
              end;
              end_handler active_handlers;
              writer_loop db chan control close_blocker close_epoch fault
                active_handlers queued_requests
          | exception exn ->
              let reason = Printexc.to_string exn in
              set_failed control reason;
              send_reply_or_raise reply (Error (failure_error reason));
              end_handler active_handlers;
              failed_loop db chan control close_blocker close_epoch fault
                active_handlers queued_requests reason
          end
      end
      end
  | Terminal_failure (reason, reply) ->
      set_failed control reason;
      send_reply_or_raise reply (Error (failure_error reason));
      failed_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests reason
  | Install_close_blocker reply ->
      send_reply_or_raise reply (install_close_blocker close_blocker);
      writer_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests
  | Release_close_blocker reply ->
      send_reply_or_raise reply (release_close_blocker close_blocker);
      writer_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests
  | Arm_fault (injection, reply) ->
      let result =
        match !fault with
        | Some _ -> Error "a run-event fault is already armed"
        | None -> fault := Some injection; Ok ()
      in
      send_reply_or_raise reply result;
      writer_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests
  | Exercise_finalize_failure reply ->
      send_reply_or_raise reply (exercise_finalize_failure db);
      writer_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests
  | Inject_history (event, reply) ->
      send_reply_or_raise reply (inject_history db event);
      writer_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests
  | Inject_history_fault (run_id, reply) ->
      send_reply_or_raise reply (inject_history_fault db run_id);
      writer_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests
  | Verify_append_only_guards reply ->
      send_reply_or_raise reply (verify_append_only_guards db);
      writer_loop db chan control close_blocker close_epoch fault active_handlers
        queued_requests
  | Force_cleanup reply ->
      let result = force_cleanup_database db in
      record_writer_terminal control result;
      send_reply_or_raise reply result
  | Stop reply ->
      let result =
        close_actor_database_attempt db close_blocker close_epoch active_handlers
          queued_requests
      in
      begin match result with Ok () -> record_writer_terminal control result | Error _ -> () end;
      send_reply_or_raise reply result;
      begin match result with
      | Ok () -> ()
      | Error _ ->
          writer_loop db chan control close_blocker close_epoch fault
            active_handlers queued_requests
      end

let writer_entry db chan control active_handlers queued_requests =
  let close_blocker = ref false in
  let close_epoch = ref 0 in
  let fault = ref None in
  match
    writer_loop db chan control close_blocker close_epoch fault active_handlers
      queued_requests
  with
  | () -> ()
  | exception exn ->
      let reason = "terminal writer exception: " ^ Printexc.to_string exn in
      set_failed control reason;
      begin match !fault with
      | Some Fault_fail_next_failure_drain ->
          fault := None;
          let drain_reason = reason ^ "; injected failure drain" in
          let close_result =
            close_actor_database_attempt db close_blocker close_epoch
              active_handlers queued_requests
          in
          record_writer_terminal control close_result;
          set_failed control
            (match close_result with
             | Ok () -> drain_reason
             | Error close_error ->
                 drain_reason ^ "; cleanup failed: " ^ close_error)
      | Some Fault_drop_next_reply | None ->
          begin match
            failed_loop db chan control close_blocker close_epoch fault
              active_handlers queued_requests reason
          with
          | () -> ()
          | exception drain_exn ->
          let drain_reason =
            reason ^ "; failure drain: " ^ Printexc.to_string drain_exn
          in
              let close_result =
                close_actor_database_attempt db close_blocker close_epoch
                  active_handlers queued_requests
              in
              record_writer_terminal control close_result;
              set_failed control
                (match close_result with
                 | Ok () -> drain_reason
                 | Error close_error ->
                     drain_reason ^ "; cleanup failed: " ^ close_error)
          end
      end

let close_result t =
  let deadline = deadline_after close_timeout_ns in
  let rec await_receipt generation =
    Mutex.lock t.control.mutex;
    let receipt = List.assoc_opt generation t.control.close_receipts in
    Mutex.unlock t.control.mutex;
    match receipt with
    | Some result -> result
    | None when before_deadline deadline ->
        Unix.sleepf 0.0005;
        await_receipt generation
    | None -> Error "close receipt deadline exceeded"
  in
  let elect () =
    Mutex.lock t.control.mutex;
    match t.control.lifecycle with
    | Closed ->
        Mutex.unlock t.control.mutex;
        `Observed (Ok ())
    | Closing generation ->
        Mutex.unlock t.control.mutex;
        `Observed (await_receipt generation)
    | Close_failed (_, reason) ->
        Mutex.unlock t.control.mutex;
        `Observed (Error reason)
    | (Open | Failed _) as lifecycle ->
        let resume =
          match lifecycle with
          | Open -> Resume_open
          | Failed reason -> Resume_failed reason
          | Closed | Closing _ | Close_failed _ -> assert false
        in
        let generation = t.control.next_close_generation in
        t.control.next_close_generation <- generation + 1;
        t.control.lifecycle <- Closing generation;
        begin match t.control.writer_terminal with
        | Some terminal ->
            Mutex.unlock t.control.mutex;
            `Terminal (generation, resume, terminal)
        | None ->
            let reply = Chan.make_unbounded () in
            begin match Chan.send t.chan (Stop reply) with
            | () ->
                Mutex.unlock t.control.mutex;
                `Elected (generation, resume, reply)
            | exception exn ->
                let reason =
                  "close stop enqueue failed: " ^ Printexc.to_string exn
                in
                let result = Error reason in
                t.control.close_receipts <-
                  (generation, result) :: t.control.close_receipts;
                t.control.lifecycle <- Close_failed (resume, reason);
                Condition.broadcast t.control.condition;
                Mutex.unlock t.control.mutex;
                `Observed result
            end
        end
  in
  let publish generation resume result =
    Mutex.lock t.control.mutex;
    t.control.close_receipts <-
      (generation, result) :: t.control.close_receipts;
    t.control.lifecycle <-
      (match result with
       | Ok () -> Closed
       | Error reason -> Close_failed (resume, reason));
    Condition.broadcast t.control.condition;
    Mutex.unlock t.control.mutex;
    result
  in
  match elect () with
  | `Observed result -> result
  | `Terminal (generation, resume, terminal) ->
      let result =
        match join_writer_before t deadline, terminal with
        | Ok (), result -> result
        | Error join, Ok () -> Error join
        | Error join, Error terminal -> Error (terminal ^ "; " ^ join)
      in
      publish generation resume result
  | `Elected (generation, resume, reply) ->
      let stop_result =
        match recv_before ~label:"close stop reply" ~deadline reply with
        | Ok result -> result
        | Error _ as error -> error
      in
      let result =
        match stop_result with
        | Error _ as error -> error
        | Ok () -> join_writer_before t deadline
      in
      publish generation resume result

let close_opening_database db original_error =
  let result =
    match Dependability_sqlite.begin_generation db with
    | Error error -> Error (Dependability_sqlite.string_of_close_error error)
    | Ok generation ->
        begin match
          Dependability_sqlite.observe_internal_quiescence generation ~epoch:1
            ~active_handlers:0 ~queued_requests:0
        with
        | Error error -> Error (Dependability_sqlite.string_of_close_error error)
        | Ok witness ->
            begin match Dependability_sqlite.close_database ~generation ~witness with
            | Ok _ -> Ok ()
            | Error (error, _) ->
                Error (Dependability_sqlite.string_of_close_error error)
            end
        end
  in
  attach_cleanup_error original_error result

let open_store_internal ~fail_after_spawn ~unsupported_schema location =
  match
    Dependability_sqlite.open_database ~location
      ~maximum_total_attempts:3
  with
  | Error error -> Error (Dependability_sqlite.string_of_close_error error)
  | Ok db ->
      let spawned_store = ref None in
      begin match
        try
          begin match
            let* () = configure db in
            let* () =
              if unsupported_schema then
                execute db Closed.Event_test_initialize_unsupported_schema
              else Ok ()
            in
            initialize_schema db
          with
          | Error error -> close_opening_database db error
          | Ok () ->
          let chan = Chan.make_unbounded () in
          let control =
            { mutex = Mutex.create (); condition = Condition.create ();
              lifecycle = Open; next_close_generation = 0;
              close_receipts = []; writer_terminal = None }
          in
          let in_flight = Atomic.make 0 in
          let active_handlers = Atomic.make 0 in
          let queued_requests = Atomic.make 0 in
          let writer_exited = Atomic.make false in
          begin match
            Domain.spawn (fun () ->
                Fun.protect
                  ~finally:(fun () -> Atomic.set writer_exited true)
                  (fun () ->
                    writer_entry db chan control active_handlers queued_requests))
          with
          | writer ->
              let store =
                { chan; writer; control; in_flight; active_handlers;
                  queued_requests; database = db; writer_exited;
                  writer_join_claimed = Atomic.make false;
                  writer_joined = Atomic.make false;
                  short_deadline_once = Atomic.make false }
              in
              (* Ownership is installed before any post-spawn operation can
                 fail, so every exit path can close and join the writer. *)
              spawned_store := Some store;
              if fail_after_spawn then
                attach_cleanup_error
                  "post-spawn registration fault; cleanup and join completed"
                  (close_result store)
              else
                let reply = Chan.make_unbounded () in
                ignore (Atomic.fetch_and_add queued_requests 1);
                begin match Chan.send chan (Request (Connection_check, reply)) with
                | () ->
                    begin match
                      recv_before ~label:"actor connection check reply"
                        ~deadline:(deadline_after default_request_timeout_ns) reply
                    with
                    | Ok (Ok ()) -> Ok store
                    | Ok (Error error) ->
                        attach_cleanup_error error (close_result store)
                    | Error error ->
                        set_failed control error;
                        attach_cleanup_error error (close_result store)
                    end
                | exception exn ->
                    ignore (Atomic.fetch_and_add queued_requests (-1));
                    let error =
                      "actor connection check enqueue failed: "
                      ^ Printexc.to_string exn
                    in
                    set_failed control error;
                    attach_cleanup_error error (close_result store)
                end
          | exception exn ->
              close_opening_database db
                ("spawn run-event actor: " ^ Printexc.to_string exn)
          end
          end
        with exn ->
          let error = "open run-event store: " ^ Printexc.to_string exn in
          match !spawned_store with
          | None -> close_opening_database db error
          | Some store -> attach_cleanup_error error (close_result store)
      with result -> result
      end

let open_store location =
  open_store_internal ~fail_after_spawn:false ~unsupported_schema:false location

let request t request =
  let reply = Chan.make_unbounded () in
  let timeout_ns =
    if Atomic.exchange t.short_deadline_once false then
      injected_request_timeout_ns
    else default_request_timeout_ns
  in
  let deadline = deadline_after timeout_ns in
  Mutex.lock t.control.mutex;
  let admission =
    match t.control.lifecycle with
    | Open ->
        ignore (Atomic.fetch_and_add t.in_flight 1);
        ignore (Atomic.fetch_and_add t.queued_requests 1);
        begin match Chan.send t.chan (Request (request, reply)) with
        | () -> Ok ()
        | exception exn ->
            ignore (Atomic.fetch_and_add t.in_flight (-1));
            ignore (Atomic.fetch_and_add t.queued_requests (-1));
            let reason = Printexc.to_string exn in
            t.control.lifecycle <- Failed reason;
            Condition.broadcast t.control.condition;
            Error ("run-event actor failed while enqueueing: " ^ reason)
        end
    | Closing _ -> Error "run-event store is closing"
    | Closed -> Error "run-event store is closed"
    | Close_failed (_, reason) -> Error ("run-event store close failed: " ^ reason)
    | Failed reason -> Error ("run-event actor failed: " ^ reason)
  in
  Mutex.unlock t.control.mutex;
  match admission with
  | Error _ as error -> error
  | Ok () ->
      let observed =
        recv_before ~label:"run-event actor reply" ~deadline reply
      in
      ignore (Atomic.fetch_and_add t.in_flight (-1));
      begin match observed with
      | Ok result -> result
      | Error reason ->
          set_failed t.control reason;
          Error reason
      end

let append t event = request t (Append event)
let events t ~run_id = request t (Events run_id)
let events_after t ~run_id ~sequence = request t (Events_after (run_id, sequence))
let snapshot t ~run_id = request t (Snapshot run_id)
let runs t ~limit = request t (Runs limit)

let close t =
  match close_result t with
  | Ok () -> ()
  | Error reason -> failwith ("run-event store close failed: " ^ reason)

module For_test = struct
  type prefix_source_mutation =
    | Drop_execution_binding
    | Drop_plan_binding
    | Drop_prefix_denominator
    | Drop_owner_session_binding
    | Drop_event_identity
    | Drop_sequence_binding
    | Drop_previous_digest_binding
    | Accept_gap
    | Accept_duplicate
    | Accept_noncontiguous_prefix
    | Accept_running_target
    | Accept_cross_context
    | Accept_stale_owner
    | Expose_event_list
    | Expose_event_payload
    | Expose_store_handle
    | Add_caller_digest
    | Add_callback
    | Construct_current_without_readback

  let drop name fields =
    List.filter (fun (candidate, _) -> not (String.equal candidate name)) fields

  let replace name value fields =
    List.map
      (fun ((candidate, _) as field) ->
        if String.equal candidate name then (candidate, value) else field)
      fields

  let event_prefix_source_digest_with_mutation mutation =
    let fields =
      match mutation with
      | Drop_execution_binding ->
          drop "execution-binding" event_prefix_source_fields
      | Drop_plan_binding -> drop "plan-binding" event_prefix_source_fields
      | Drop_prefix_denominator ->
          drop "prefix-denominator" event_prefix_source_fields
      | Drop_owner_session_binding ->
          drop "owner-session-binding" event_prefix_source_fields
      | Drop_event_identity ->
          drop "event-identity" event_prefix_source_fields
      | Drop_sequence_binding ->
          drop "sequence-binding" event_prefix_source_fields
      | Drop_previous_digest_binding ->
          drop "previous-digest-binding" event_prefix_source_fields
      | Accept_gap -> replace "gap-policy" "accept" event_prefix_source_fields
      | Accept_duplicate ->
          replace "duplicate-policy" "accept" event_prefix_source_fields
      | Accept_noncontiguous_prefix ->
          replace "noncontiguous-policy" "accept" event_prefix_source_fields
      | Accept_running_target ->
          replace "running-target-policy" "accept-running"
            event_prefix_source_fields
      | Accept_cross_context ->
          replace "context-policy" "accept-cross-context"
            event_prefix_source_fields
      | Accept_stale_owner ->
          replace "currentness-policy" "accept-stale"
            event_prefix_source_fields
      | Expose_event_list ->
          replace "event-list-projection" "public" event_prefix_source_fields
      | Expose_event_payload ->
          replace "event-payload-projection" "public"
            event_prefix_source_fields
      | Expose_store_handle ->
          replace "store-handle-projection" "public"
            event_prefix_source_fields
      | Add_caller_digest ->
          replace "caller-input-seams" "caller-digest"
            event_prefix_source_fields
      | Add_callback ->
          replace "caller-input-seams" "callback" event_prefix_source_fields
      | Construct_current_without_readback ->
          replace "current-construction" "caller-constructible"
            event_prefix_source_fields
    in
    prefix_digest_fields fields

  type lifecycle_observation =
    | Observed_open
    | Observed_closing
    | Observed_failed
    | Observed_close_failed
    | Observed_closed

  type fault =
    | Drop_next_reply
    | Fail_next_failure_drain

  type open_fault =
    | Fail_after_spawn_before_registration
    | Unsupported_schema

  type history_fault = Malformed_stored_event of string

  type finalize_summary = {
    intervals : int;
    succeeded : int;
    failed : int;
    active : bool;
  }

  type finalize_interval = {
    database_identity : int;
    statement_identity : int;
    interval_identity : int;
    outcome : Dependability_sqlite.finalize_interval_outcome;
  }

  type active_finalize_interval = {
    active_database_identity : int;
    active_interval_identity : int;
  }

  let close_result = close_result

  let send_open_control t ~label make_message =
    let reply = Chan.make_unbounded () in
    let deadline = deadline_after default_request_timeout_ns in
    Mutex.lock t.control.mutex;
    let admission =
      match t.control.lifecycle with
      | Open ->
          begin match Chan.send t.chan (make_message reply) with
          | () -> Ok ()
          | exception exn ->
              Error (label ^ " enqueue failed: " ^ Printexc.to_string exn)
          end
      | Failed reason -> Error (failure_error reason)
      | Closing _ -> Error "run-event store is closing"
      | Closed -> Error "run-event store is closed"
      | Close_failed (_, reason) ->
          Error ("run-event store close failed: " ^ reason)
    in
    Mutex.unlock t.control.mutex;
    match admission with
    | Error _ as error -> error
    | Ok () ->
        begin match recv_before ~label:(label ^ " reply") ~deadline reply with
        | Ok result -> result
        | Error reason ->
            set_failed t.control reason;
            Error reason
        end

  let arm_fault t = function
    | Drop_next_reply ->
        let result =
          send_open_control t ~label:"drop-next-reply fault"
            (fun reply -> Arm_fault (Fault_drop_next_reply, reply))
        in
        begin match result with
        | Ok () -> Atomic.set t.short_deadline_once true
        | Error _ -> ()
        end;
        result
    | Fail_next_failure_drain ->
        let result =
          send_open_control t ~label:"failure-drain fault"
            (fun reply -> Arm_fault (Fault_fail_next_failure_drain, reply))
        in
        begin match result with
        | Ok () -> Atomic.set t.short_deadline_once true
        | Error _ -> ()
        end;
        result

  let open_store_with_fault fault location =
    match fault with
    | Fail_after_spawn_before_registration ->
        open_store_internal ~fail_after_spawn:true ~unsupported_schema:false
          location
    | Unsupported_schema ->
        open_store_internal ~fail_after_spawn:false ~unsupported_schema:true
          location

  let inject_history t event =
    send_open_control t ~label:"inject typed history"
      (fun reply -> Inject_history (event, reply))

  let inject_history_fault t = function
    | Malformed_stored_event run_id ->
        send_open_control t ~label:"inject malformed stored history"
          (fun reply -> Inject_history_fault (run_id, reply))

  let verify_append_only_guards t =
    send_open_control t ~label:"verify append-only guards"
      (fun reply -> Verify_append_only_guards reply)

  let lifecycle t =
    Mutex.lock t.control.mutex;
    let observed =
      match t.control.lifecycle with
      | Open -> Observed_open
      | Closing _ -> Observed_closing
      | Failed _ -> Observed_failed
      | Close_failed _ -> Observed_close_failed
      | Closed -> Observed_closed
    in
    Mutex.unlock t.control.mutex;
    observed

  let writer_joined t = Atomic.get t.writer_joined
  let close_attempts t =
    Dependability_sqlite.total_close_attempts t.database
  let authority_state t = Dependability_sqlite.database_state t.database
  let finalize_summary t =
    let observations =
      Dependability_sqlite.finalize_interval_observations t.database
    in
    let succeeded, failed =
      List.fold_left
        (fun (succeeded, failed)
             (observation : Dependability_sqlite.finalize_interval_observation) ->
          match observation.finalize_interval_outcome with
          | Dependability_sqlite.Finalize_interval_succeeded ->
              (succeeded + 1, failed)
          | Dependability_sqlite.Finalize_interval_failed _ ->
              (succeeded, failed + 1))
        (0, 0) observations
    in
    { intervals = List.length observations; succeeded; failed;
      active = Dependability_sqlite.finalize_interval_active t.database }
  let finalize_interval_active t =
    Dependability_sqlite.finalize_interval_active t.database
  let finalize_intervals t =
    Dependability_sqlite.finalize_interval_observations t.database
    |> List.map
         (fun
           (observation : Dependability_sqlite.finalize_interval_observation) ->
           { database_identity = observation.database_identity;
             statement_identity = observation.statement_identity;
             interval_identity = observation.interval_identity;
             outcome = observation.finalize_interval_outcome })

  let active_finalize_interval t =
    let identities observations =
      List.map
        (fun
          (observation : Dependability_sqlite.finalize_interval_observation) ->
          observation.interval_identity)
        observations
    in
    let next_identity observations =
      1
      + List.fold_left
          (fun maximum
               (observation : Dependability_sqlite.finalize_interval_observation) ->
            max maximum observation.interval_identity)
          0 observations
    in
    let rec stable attempts =
      if attempts = 0 then None
      else
        let before =
          Dependability_sqlite.finalize_interval_observations t.database
        in
        if not (Dependability_sqlite.finalize_interval_active t.database) then None
        else
          let after =
            Dependability_sqlite.finalize_interval_observations t.database
          in
          if identities before = identities after then
            Some
              { active_database_identity =
                  Dependability_sqlite.database_identity t.database;
                active_interval_identity = next_identity before }
          else stable (attempts - 1)
    in
    stable 3

  let exercise_finalize_failure t =
    send_open_control t ~label:"exercise finalize failure"
      (fun reply -> Exercise_finalize_failure reply)

  let force_cleanup t =
    if Atomic.get t.writer_joined then
      match Dependability_sqlite.database_state t.database with
      | Dependability_sqlite.Database_released -> Ok ()
      | Dependability_sqlite.Database_open
      | Dependability_sqlite.Database_close_v2_deferred ->
          Error "joined writer did not physically release its database"
    else
      let deadline = deadline_after close_timeout_ns in
      let reply = Chan.make_unbounded () in
      Mutex.lock t.control.mutex;
      let admission =
        match t.control.lifecycle with
        | Closed -> Error "run-event store is already closed"
        | Closing _ -> Error "run-event store is closing"
        | Open | Failed _ | Close_failed _ ->
            begin match Chan.send t.chan (Force_cleanup reply) with
            | () -> Ok ()
            | exception exn ->
                Error
                  ("test cleanup enqueue failed: " ^ Printexc.to_string exn)
            end
      in
      Mutex.unlock t.control.mutex;
      begin match admission with
      | Error _ as error -> error
      | Ok () ->
          let cleanup =
            match recv_before ~label:"test cleanup reply" ~deadline reply with
            | Ok result -> result
            | Error _ as error -> error
          in
          let joined = join_writer_before t deadline in
          let result =
            match cleanup, joined with
            | Ok (), Ok () -> Ok ()
            | Error cleanup, Ok () -> Error cleanup
            | Ok (), Error join -> Error join
            | Error cleanup, Error join -> Error (cleanup ^ "; " ^ join)
          in
          Mutex.lock t.control.mutex;
          t.control.lifecycle <-
            (match result with
             | Ok () -> Closed
             | Error reason -> Close_failed (Resume_open, reason));
          Condition.broadcast t.control.condition;
          Mutex.unlock t.control.mutex;
          result
      end

  let install_close_blocker t =
    send_open_control t ~label:"close blocker"
      (fun reply -> Install_close_blocker reply)

  let release_close_blocker t =
    let reply = Chan.make_unbounded () in
    let deadline = deadline_after default_request_timeout_ns in
    Mutex.lock t.control.mutex;
    let state = t.control.lifecycle in
    let admission =
      match state with
      | Close_failed (resume, _) ->
          begin match Chan.send t.chan (Release_close_blocker reply) with
          | () -> Ok resume
          | exception exn ->
              Error ("close blocker release enqueue failed: " ^ Printexc.to_string exn)
          end
      | Open -> Error "run-event store has no failed close to recover"
      | Failed reason -> Error (failure_error reason)
      | Closing _ -> Error "run-event store is closing"
      | Closed -> Error "run-event store is closed"
    in
    let result =
      match admission with
      | Error _ as error -> error
      | Ok resume ->
          begin match
            recv_before ~label:"close blocker release reply" ~deadline reply
          with
          | Ok (Ok ()) ->
              t.control.lifecycle <-
                (match resume with Resume_open -> Open | Resume_failed reason -> Failed reason);
              Condition.broadcast t.control.condition;
              Ok ()
          | Ok (Error _ as error) -> error
          | Error _ as error -> error
          end
    in
    Mutex.unlock t.control.mutex;
    result

  let fail_writer t reason =
    if String.trim reason = "" then Error "terminal writer failure reason must be nonempty"
    else begin
      (* A monotonic one-second admission window gives already-started callers
         a deterministic chance to enter the actor queue. *)
      let shape_deadline = deadline_after 1_000_000_000L in
      let rec await_actor_shape () =
        if Atomic.get t.active_handlers >= 1
           && Atomic.get t.queued_requests >= 1
        then true
        else if not (before_deadline shape_deadline) then false
        else begin Domain.cpu_relax (); await_actor_shape () end
      in
      if not (await_actor_shape ()) then
        Error "terminal failure injection requires one active handler and one queued request"
      else
        let reply = Chan.make_unbounded () in
        let deadline = deadline_after default_request_timeout_ns in
        Mutex.lock t.control.mutex;
        let admission =
          match t.control.lifecycle with
          | Open ->
              t.control.lifecycle <- Failed reason;
              Condition.broadcast t.control.condition;
              begin match Chan.send t.chan (Terminal_failure (reason, reply)) with
              | () -> Ok ()
              | exception exn ->
                  Error ("terminal failure enqueue failed: " ^ Printexc.to_string exn)
              end
          | Failed existing -> Error (failure_error existing)
          | Closing _ -> Error "run-event store is closing"
          | Closed -> Error "run-event store is closed"
          | Close_failed (_, close_error) ->
              Error ("run-event store close failed: " ^ close_error)
        in
        Mutex.unlock t.control.mutex;
        match admission with
        | Error _ as error -> error
        | Ok () ->
            begin match
              recv_before ~label:"terminal failure reply" ~deadline reply
            with
            | Ok result -> result
            | Error _ as error -> error
            end
    end
end
