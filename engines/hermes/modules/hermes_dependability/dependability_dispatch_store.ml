type rca_origin = Specification | Implementation | Environment | Evidence | Control

type diagnostic_kind =
  | Invalid_digest
  | Invalid_clock
  | Implemented_unavailable
  | Nominal_open_fence_invalid
  | Database_unavailable
  | Role_already_transferred
  | Role_wrong_session
  | Owner_not_active
  | Request_conflict
  | Stale_attempt
  | Invalid_state_transition
  | Missing_dispatch
  | Currentness_unavailable
  | Decision_protocol_unavailable
  | Abandonment_protocol_unavailable
  | Inventory_unavailable
  | Drain_receipt_required
  | Drain_receipt_mismatch
  | Close_unavailable

type diagnostic = {
  kind : diagnostic_kind;
  coordinate : string;
  origin : rca_origin;
}

let kind_code = function
  | Invalid_digest -> "invalid-digest"
  | Invalid_clock -> "invalid-clock"
  | Implemented_unavailable -> "implemented-unavailable"
  | Nominal_open_fence_invalid -> "nominal-open-fence-invalid"
  | Database_unavailable -> "database-unavailable"
  | Role_already_transferred -> "role-already-transferred"
  | Role_wrong_session -> "role-wrong-session"
  | Owner_not_active -> "owner-not-active"
  | Request_conflict -> "request-conflict"
  | Stale_attempt -> "stale-attempt"
  | Invalid_state_transition -> "invalid-state-transition"
  | Missing_dispatch -> "missing-dispatch"
  | Currentness_unavailable -> "currentness-unavailable"
  | Decision_protocol_unavailable -> "decision-protocol-unavailable"
  | Abandonment_protocol_unavailable -> "abandonment-protocol-unavailable"
  | Inventory_unavailable -> "inventory-unavailable"
  | Drain_receipt_required -> "drain-receipt-required"
  | Drain_receipt_mismatch -> "drain-receipt-mismatch"
  | Close_unavailable -> "close-unavailable"

let origin_of_kind = function
  | Implemented_unavailable | Database_unavailable | Close_unavailable ->
      Environment
  | Currentness_unavailable -> Evidence
  | Invalid_digest | Invalid_clock
  | Nominal_open_fence_invalid
  | Role_already_transferred | Role_wrong_session | Owner_not_active
  | Request_conflict | Stale_attempt | Invalid_state_transition
  | Missing_dispatch | Decision_protocol_unavailable
  | Abandonment_protocol_unavailable | Inventory_unavailable
  | Drain_receipt_required | Drain_receipt_mismatch -> Control

let diagnostic kind =
  { kind; coordinate = "L5/dependability-dispatch-store";
    origin = origin_of_kind kind }

let diagnostic_code value = kind_code value.kind
let diagnostic_coordinate value = value.coordinate
let diagnostic_origin value = value.origin

let length_frame fields =
  fields
  |> List.map (fun field -> Printf.sprintf "%d:%s" (String.length field) field)
  |> String.concat ""

let sha256 fields =
  fields |> length_frame |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

module Digest = struct
  type t = string

  let canonical = function '0' .. '9' | 'a' .. 'f' -> true | _ -> false

  let make value =
    if String.length value = 64 && String.for_all canonical value then Ok value
    else Error (diagnostic Invalid_digest)

  let to_hex value = value
  let equal = String.equal
end

type bootstrap_context = {
  authority : Dependability_authority_store.operational;
  authority_session : string;
  authority_epoch : string;
  authority_generation : int;
  observed_at : Dependability_clock.receipt;
  bootstrap_digest_value : string;
}

let prepare_bootstrap ~authority ~observed_at =
  match Dependability_clock.validate observed_at with
  | Error _ -> Error (diagnostic Invalid_clock)
  | Ok () ->
      let authority_session =
        Dependability_authority_store.owner_session_digest authority
      in
      let authority_epoch =
        Dependability_authority_store.store_epoch_digest authority
      in
      let authority_generation =
        Dependability_authority_store.owner_session_generation authority
      in
      let bootstrap_digest_value =
        sha256
          [ "dependability-dispatch-bootstrap-v1"; authority_session;
            authority_epoch; string_of_int authority_generation;
            Dependability_clock.digest observed_at;
            Jj_campaign_action.source_digest; Jj_operation.source_digest ]
      in
      Ok
        { authority; authority_session; authority_epoch; authority_generation;
          observed_at; bootstrap_digest_value }

let bootstrap_digest context = context.bootstrap_digest_value

type lifecycle_state = Active | Draining | Closed

type dispatch_status =
  | Not_dispatched
  | Dispatch_claimed
  | Terminal
  | Indeterminate

type decision_status = Undecided | Decided | Decision_indeterminate
type abandonment_status = No_abandonment | Abandonment_committed

type dispatch_row = {
  key_digest : string;
  ordinal : int;
  status : dispatch_status;
  transition_id : string;
  request_digest : string;
  time_digest : string;
  owner_session : string;
  recovery_attempt : int;
}

type decision_row = {
  decision_key_digest : string;
  decision_status : decision_status;
  decision_id : string;
  decision_plan_digest : string;
  decision_time_digest : string;
  decision_owner_session : string;
  decision_recovery_attempt : int;
}

type store = {
  database : Dependability_sqlite.owned_database;
  bootstrap : bootstrap_context;
  store_epoch : string;
  session_generation : int;
  recovery_attempt : int;
  session_digest : string;
  mutable lifecycle : lifecycle_state;
  mutable clock_receipts : (string * Dependability_clock.receipt) list;
  mutable drain_value : drain_receipt option;
  mutable close_value : close_receipt option;
}

and operational = { operational_store : store }

and role_bundle = {
  role_store : store;
  transferred : bool array;
}

and lower_open_result = {
  opened_operational : operational;
  opened_roles : role_bundle;
}

and drain_receipt = {
  drain_store : store;
  drain_session : string;
  drain_attempt : int;
  drain_digest_value : string;
  drain_was_replayed : bool;
}

and close_receipt = {
  close_store : store;
  close_session : string;
  close_attempt : int;
  close_digest_value : string;
  close_was_replayed : bool;
}

let operational opened = opened.opened_operational
let role_bundle opened = opened.opened_roles
let owner_session_generation operational =
  operational.operational_store.session_generation
let recovery_attempt_ordinal operational =
  operational.operational_store.recovery_attempt
let owner_session_digest operational =
  operational.operational_store.session_digest
let store_epoch_digest operational = operational.operational_store.store_epoch
let operational_posture _ = `Volatile_test_foundation
let production_posture _ = `Implemented_unavailable

let ( let* ) result f =
  match result with Ok value -> f value | Error _ as error -> error

module Closed = Dependability_sqlite.Closed_operation

let closed_error _ = diagnostic Database_unavailable

let execute ?scope database operation =
  let result =
    match scope with
    | None -> Closed.execute database operation
    | Some scope -> Closed.execute_in scope operation
  in
  match result with Ok value -> Ok value | Error error -> Error (closed_error error)

let initialize_schema database = execute database Closed.Dispatch_store_initialize_v1

let close_database_quietly database =
  match Dependability_sqlite.begin_generation database with
  | Error _ -> false
  | Ok generation ->
      begin match
        Dependability_sqlite.observe_internal_quiescence generation ~epoch:1
          ~active_handlers:0 ~queued_requests:0
      with
      | Error _ -> false
      | Ok witness ->
          Result.is_ok
            (Dependability_sqlite.close_database ~generation ~witness)
      end

let transaction database body =
  let body_error = ref None in
  match
    Closed.with_transaction database ~mode:Closed.Read_write (fun scope ->
      match body scope with
      | Ok value -> Ok value
      | Error error ->
          body_error := Some error;
          Error (Closed.Operation_failed (diagnostic_code error)))
  with
  | Ok value -> Ok value
  | Error _ ->
      begin match !body_error with
      | Some error -> Error error
      | None -> Error (diagnostic Database_unavailable)
      end

let insert_initial_owner_session database bootstrap store_epoch session_digest
    recovery_attempt =
  let time_digest = Dependability_clock.digest bootstrap.observed_at in
  let transition_id =
    sha256
      [ "dispatch-owner-session-transition-v1"; store_epoch; session_digest;
        string_of_int recovery_attempt; "0"; "active";
        bootstrap.bootstrap_digest_value; time_digest ]
  in
  execute database
    (Closed.Dispatch_store_insert_initial_owner
       { dispatch_initial_session = session_digest;
         dispatch_initial_recovery_attempt = recovery_attempt;
         dispatch_initial_store_epoch = store_epoch;
         dispatch_initial_bootstrap_digest = bootstrap.bootstrap_digest_value;
         dispatch_initial_time_digest = time_digest;
         dispatch_initial_transition_id = transition_id })

let open_first_or_successor ~fence ~location ~bootstrap =
  match Dependability_sqlite_location.registration location with
  | Some _ -> Error (diagnostic Implemented_unavailable)
  | None ->
      begin match
        Dependability_authority_store.consume_dispatch_operational_open fence
          ~authority:bootstrap.authority
      with
      | Error _ -> Error (diagnostic Nominal_open_fence_invalid)
      | Ok () ->
      begin match
        Dependability_sqlite.open_database ~location ~maximum_total_attempts:1
      with
      | Error _ -> Error (diagnostic Database_unavailable)
      | Ok database ->
          if Dependability_sqlite.storage_posture database
             <> Dependability_sqlite.Volatile_test
          then begin
            ignore (close_database_quietly database);
            Error (diagnostic Implemented_unavailable)
          end else
            let store_epoch =
              sha256
                [ "dispatch-store-volatile-epoch-v1";
                  Dependability_sqlite_location.reference_digest location;
                  bootstrap.bootstrap_digest_value ]
            in
            let session_generation = bootstrap.authority_generation in
            let recovery_attempt = 1 in
            let session_digest =
              sha256
                [ "dispatch-owner-session-v1"; store_epoch;
                  bootstrap.authority_session; bootstrap.authority_epoch;
                  string_of_int session_generation;
                  string_of_int recovery_attempt;
                  bootstrap.bootstrap_digest_value ]
            in
            begin match initialize_schema database with
            | Error _ as error ->
                ignore (close_database_quietly database);
                error
            | Ok () ->
                begin match
                  insert_initial_owner_session database bootstrap store_epoch
                    session_digest recovery_attempt
                with
                | Error _ as error ->
                    ignore (close_database_quietly database);
                    error
                | Ok () ->
                    let store =
                      { database; bootstrap; store_epoch; session_generation;
                        recovery_attempt; session_digest; lifecycle = Active;
                        clock_receipts =
                          [ (Dependability_clock.digest bootstrap.observed_at,
                             bootstrap.observed_at) ];
                        drain_value = None; close_value = None }
                    in
                    Ok
                      { opened_operational = { operational_store = store };
                        opened_roles =
                          { role_store = store;
                            transferred = Array.make 4 false } }
                end
            end
      end
      end

type dispatch_claim_capability = {
  claim_store : store;
  claim_session : string;
  claim_attempt : int;
}

type conditional_decision_capability = {
  decision_store : store;
  decision_session : string;
  decision_attempt : int;
}

type abandonment_writer_capability = {
  abandonment_store : store;
  abandonment_session : string;
  abandonment_attempt : int;
}

type lifecycle_capability = {
  lifecycle_store : store;
  lifecycle_session : string;
  lifecycle_attempt : int;
}

let take_role bundle index construct =
  if bundle.transferred.(index) then
    Error (diagnostic Role_already_transferred)
  else begin
    bundle.transferred.(index) <- true;
    Ok
      (construct bundle.role_store bundle.role_store.session_digest
         bundle.role_store.recovery_attempt)
  end

let take_dispatch_claim bundle =
  take_role bundle 0 (fun store session attempt ->
      { claim_store = store; claim_session = session; claim_attempt = attempt })

let take_conditional_decision bundle =
  take_role bundle 1 (fun store session attempt ->
      { decision_store = store; decision_session = session;
        decision_attempt = attempt })

let take_abandonment_writer bundle =
  take_role bundle 2 (fun store session attempt ->
      { abandonment_store = store; abandonment_session = session;
        abandonment_attempt = attempt })

let take_lifecycle bundle =
  take_role bundle 3 (fun store session attempt ->
      { lifecycle_store = store; lifecycle_session = session;
        lifecycle_attempt = attempt })

let check_active store session attempt =
  if not (String.equal store.session_digest session)
     || store.recovery_attempt <> attempt
  then Error (diagnostic Role_wrong_session)
  else
    match store.lifecycle with
    | Active -> Ok ()
    | Draining | Closed -> Error (diagnostic Owner_not_active)

type dispatch_key = {
  key_store : store;
  key_store_epoch : string;
  key_session : string;
  key_attempt : int;
  key_digest_value : string;
  key_plan_digest : string;
}

let prepare_dispatch_key capability ~logical_execution ~admission ~plan =
  let store = capability.claim_store in
  let* () = check_active store capability.claim_session capability.claim_attempt in
  let key_digest_value =
    sha256
      [ "dispatch-key-v1"; store.store_epoch; store.session_digest;
        string_of_int store.recovery_attempt;
        Digest.to_hex logical_execution; Digest.to_hex admission;
        Digest.to_hex plan ]
  in
  Ok
    { key_store = store; key_store_epoch = store.store_epoch;
      key_session = store.session_digest; key_attempt = store.recovery_attempt;
      key_digest_value; key_plan_digest = Digest.to_hex plan }

let dispatch_key_digest key = key.key_digest_value

let status_name = function
  | Not_dispatched -> "not-dispatched"
  | Dispatch_claimed -> "dispatch-claimed"
  | Terminal -> "terminal"
  | Indeterminate -> "indeterminate"

let status_of_name = function
  | "not-dispatched" -> Ok Not_dispatched
  | "dispatch-claimed" -> Ok Dispatch_claimed
  | "terminal" -> Ok Terminal
  | "indeterminate" -> Ok Indeterminate
  | _ -> Error (diagnostic Database_unavailable)

let decision_status_name = function
  | Undecided -> "undecided"
  | Decided -> "decided"
  | Decision_indeterminate -> "decision-indeterminate"

let decision_status_of_name = function
  | "undecided" -> Ok Undecided
  | "decided" -> Ok Decided
  | "decision-indeterminate" -> Ok Decision_indeterminate
  | _ -> Error (diagnostic Database_unavailable)

let validate_time receipt =
  match Dependability_clock.validate receipt with
  | Ok () -> Ok ()
  | Error _ -> Error (diagnostic Invalid_clock)

let make_dispatch_row ~key ~ordinal ~status ~request ~observed_at =
  let time_digest = Dependability_clock.digest observed_at in
  let transition_id =
    sha256
      [ "dispatch-transition-v1"; key.key_digest_value;
        string_of_int ordinal; status_name status; Digest.to_hex request;
        time_digest; key.key_session; string_of_int key.key_attempt ]
  in
  { key_digest = key.key_digest_value; ordinal; status; transition_id;
    request_digest = Digest.to_hex request; time_digest;
    owner_session = key.key_session; recovery_attempt = key.key_attempt }

let make_undecided_row key observed_at =
  let decision_time_digest = Dependability_clock.digest observed_at in
  let decision_id =
    sha256
      [ "conditional-decision-v1"; key.key_digest_value;
        decision_status_name Undecided; key.key_plan_digest;
        decision_time_digest; key.key_session; string_of_int key.key_attempt ]
  in
  { decision_key_digest = key.key_digest_value;
    decision_status = Undecided; decision_id;
    decision_plan_digest = key.key_plan_digest; decision_time_digest;
    decision_owner_session = key.key_session;
    decision_recovery_attempt = key.key_attempt }

type prepared_registration = {
  registration_key : dispatch_key;
  registration_row : dispatch_row;
  registration_decision : decision_row;
  registration_time : Dependability_clock.receipt;
}

type prepared_claim = {
  prepared_claim_key : dispatch_key;
  prepared_claim_predecessor : string;
  prepared_claim_row : dispatch_row;
  prepared_claim_time : Dependability_clock.receipt;
}

type transition_receipt = {
  receipt_row : dispatch_row;
  receipt_digest_value : string;
  receipt_was_replayed : bool;
}

type dispatch_readback = {
  readback_store : store;
  readback_key : dispatch_key;
  readback_row : dispatch_row;
  readback_time : Dependability_clock.receipt;
  readback_digest_value : string;
}

type claim_current = {
  current_claim_store : store;
  current_claim_key : dispatch_key;
  current_claim_row : dispatch_row;
  current_claim_readback_digest : string;
  current_claim_session : string;
  current_claim_attempt : int;
  current_claim_digest_value : string;
}

let prepare_registration ~key ~request ~observed_at =
  let* () = validate_time observed_at in
  Ok
    { registration_key = key;
      registration_row =
        make_dispatch_row ~key ~ordinal:0 ~status:Not_dispatched ~request
          ~observed_at;
      registration_decision = make_undecided_row key observed_at;
      registration_time = observed_at }

let read_pointer ?scope database key_digest =
  let* pointer =
    execute ?scope database (Closed.Dispatch_store_read_pointer key_digest)
  in
  match pointer with
  | None -> Ok None
  | Some pointer ->
      Ok
        (Some
           (pointer.dispatch_pointer_ordinal,
            pointer.dispatch_pointer_session,
            pointer.dispatch_pointer_attempt))

let closed_dispatch_row (row : dispatch_row) : Closed.dispatch_store_row =
  { dispatch_row_key = row.key_digest; dispatch_row_ordinal = row.ordinal;
    dispatch_row_status = status_name row.status;
    dispatch_row_transition_id = row.transition_id;
    dispatch_row_request_digest = row.request_digest;
    dispatch_row_time_digest = row.time_digest;
    dispatch_row_owner_session = row.owner_session;
    dispatch_row_recovery_attempt = row.recovery_attempt }

let dispatch_row_of_closed (row : Closed.dispatch_store_row) =
  let* status = status_of_name row.dispatch_row_status in
  Ok
    { key_digest = row.dispatch_row_key; ordinal = row.dispatch_row_ordinal;
      status; transition_id = row.dispatch_row_transition_id;
      request_digest = row.dispatch_row_request_digest;
      time_digest = row.dispatch_row_time_digest;
      owner_session = row.dispatch_row_owner_session;
      recovery_attempt = row.dispatch_row_recovery_attempt }

let read_transition ?scope database key_digest ordinal =
  let* row =
    execute ?scope database
      (Closed.Dispatch_store_read_transition
         { dispatch_lookup_key = key_digest; dispatch_lookup_ordinal = ordinal })
  in
  match row with
  | None -> Ok None
  | Some row -> let* row = dispatch_row_of_closed row in Ok (Some row)

let closed_decision_row (row : decision_row) : Closed.dispatch_store_decision =
  { dispatch_decision_key = row.decision_key_digest;
    dispatch_decision_status = decision_status_name row.decision_status;
    dispatch_decision_id = row.decision_id;
    dispatch_decision_plan_digest = row.decision_plan_digest;
    dispatch_decision_time_digest = row.decision_time_digest;
    dispatch_decision_owner_session = row.decision_owner_session;
    dispatch_decision_recovery_attempt = row.decision_recovery_attempt }

let decision_row_of_closed (row : Closed.dispatch_store_decision) =
  let* decision_status = decision_status_of_name row.dispatch_decision_status in
  Ok
    { decision_key_digest = row.dispatch_decision_key; decision_status;
      decision_id = row.dispatch_decision_id;
      decision_plan_digest = row.dispatch_decision_plan_digest;
      decision_time_digest = row.dispatch_decision_time_digest;
      decision_owner_session = row.dispatch_decision_owner_session;
      decision_recovery_attempt = row.dispatch_decision_recovery_attempt }

let read_decision_row ?scope database key_digest =
  let* row =
    execute ?scope database (Closed.Dispatch_store_read_decision key_digest)
  in
  match row with
  | None -> Ok None
  | Some row -> let* row = decision_row_of_closed row in Ok (Some row)

let dispatch_row_equal left right =
  String.equal left.key_digest right.key_digest
  && left.ordinal = right.ordinal
  && left.status = right.status
  && String.equal left.transition_id right.transition_id
  && String.equal left.request_digest right.request_digest
  && String.equal left.time_digest right.time_digest
  && String.equal left.owner_session right.owner_session
  && left.recovery_attempt = right.recovery_attempt

let decision_row_equal left right =
  String.equal left.decision_key_digest right.decision_key_digest
  && left.decision_status = right.decision_status
  && String.equal left.decision_id right.decision_id
  && String.equal left.decision_plan_digest right.decision_plan_digest
  && String.equal left.decision_time_digest right.decision_time_digest
  && String.equal left.decision_owner_session right.decision_owner_session
  && left.decision_recovery_attempt = right.decision_recovery_attempt

let insert_dispatch_transition ~scope database row =
  execute ~scope database
    (Closed.Dispatch_store_insert_transition (closed_dispatch_row row))

let insert_decision ~scope database row =
  execute ~scope database
    (Closed.Dispatch_store_insert_decision (closed_decision_row row))

let transition_receipt row replayed =
  { receipt_row = row;
    receipt_digest_value =
      sha256 [ "dispatch-transition-receipt-v1"; row.transition_id ];
    receipt_was_replayed = replayed }

let remember_clock store receipt =
  let digest = Dependability_clock.digest receipt in
  if not
       (List.exists
          (fun (known, _) -> String.equal known digest)
          store.clock_receipts)
  then store.clock_receipts <- (digest, receipt) :: store.clock_receipts

let validate_key capability key =
  let store = capability.claim_store in
  let* () = check_active store capability.claim_session capability.claim_attempt in
  if store != key.key_store
     || not (String.equal store.store_epoch key.key_store_epoch)
     || not (String.equal store.session_digest key.key_session)
     || store.recovery_attempt <> key.key_attempt
  then Error (diagnostic Role_wrong_session)
  else Ok store

let register_not_dispatched_once capability prepared =
  let key = prepared.registration_key in
  let row = prepared.registration_row in
  let decision = prepared.registration_decision in
  let* store = validate_key capability key in
  let* receipt =
    transaction store.database (fun scope ->
        let* existing = read_transition ~scope store.database row.key_digest 0 in
        match existing with
        | Some existing when dispatch_row_equal existing row ->
            let* pointer = read_pointer ~scope store.database row.key_digest in
            let* stored_decision =
              read_decision_row ~scope store.database row.key_digest
            in
            begin match pointer, stored_decision with
            | Some (0, session, attempt), Some stored
              when String.equal session store.session_digest
                   && attempt = store.recovery_attempt
                   && decision_row_equal stored decision ->
                Ok (transition_receipt existing true)
            | _ -> Error (diagnostic Stale_attempt)
            end
        | Some _ -> Error (diagnostic Request_conflict)
        | None ->
            let* pointer = read_pointer ~scope store.database row.key_digest in
            let* stored_decision =
              read_decision_row ~scope store.database row.key_digest
            in
            begin match pointer, stored_decision with
            | None, None ->
                let* () = insert_dispatch_transition ~scope store.database row in
                let* () =
                  execute ~scope store.database
                    (Closed.Dispatch_store_insert_pointer
                       { dispatch_pointer_key = row.key_digest;
                         dispatch_pointer_ordinal = 0;
                         dispatch_pointer_session = store.session_digest;
                         dispatch_pointer_attempt = store.recovery_attempt })
                in
                let* () = insert_decision ~scope store.database decision in
                Ok (transition_receipt row false)
            | _ -> Error (diagnostic Request_conflict)
            end)
  in
  remember_clock store prepared.registration_time;
  Ok receipt

let find_clock store digest =
  List.find_map
    (fun (known, receipt) ->
       if String.equal known digest then Some receipt else None)
    store.clock_receipts

let readback_digest_of_row store row =
  sha256
    [ "dispatch-readback-v1"; store.store_epoch; store.session_digest;
      string_of_int store.recovery_attempt; row.key_digest;
      string_of_int row.ordinal; status_name row.status; row.transition_id;
      row.request_digest; row.time_digest ]

let read_dispatch capability key =
  let* store = validate_key capability key in
  let* pointer = read_pointer store.database key.key_digest_value in
  match pointer with
  | None -> Error (diagnostic Missing_dispatch)
  | Some (_, session, attempt)
    when not (String.equal session store.session_digest)
         || attempt <> store.recovery_attempt ->
      Error (diagnostic Stale_attempt)
  | Some (ordinal, _, _) ->
      let* row = read_transition store.database key.key_digest_value ordinal in
      begin match row with
      | None -> Error (diagnostic Currentness_unavailable)
      | Some row ->
          begin match find_clock store row.time_digest with
          | None -> Error (diagnostic Currentness_unavailable)
          | Some readback_time ->
              Ok
                { readback_store = store; readback_key = key;
                  readback_row = row; readback_time;
                  readback_digest_value = readback_digest_of_row store row }
          end
      end

let prepare_claim ~predecessor ~request ~observed_at =
  if predecessor.readback_row.status <> Not_dispatched
     || predecessor.readback_row.ordinal <> 0
  then Error (diagnostic Invalid_state_transition)
  else
    let* () = validate_time observed_at in
    Ok
      { prepared_claim_key = predecessor.readback_key;
        prepared_claim_predecessor = predecessor.readback_digest_value;
        prepared_claim_row =
          make_dispatch_row ~key:predecessor.readback_key ~ordinal:1
            ~status:Dispatch_claimed ~request ~observed_at;
        prepared_claim_time = observed_at }

let update_pointer ~scope database row expected_ordinal =
  let* changed =
    execute ~scope database
      (Closed.Dispatch_store_pointer_cas
         { dispatch_pointer_cas_key = row.key_digest;
           dispatch_pointer_expected_ordinal = expected_ordinal;
           dispatch_pointer_replacement_ordinal = row.ordinal;
           dispatch_pointer_cas_session = row.owner_session;
           dispatch_pointer_cas_attempt = row.recovery_attempt })
  in
  if changed then Ok () else Error (diagnostic Stale_attempt)

let claim_once capability prepared =
  let key = prepared.prepared_claim_key in
  let row = prepared.prepared_claim_row in
  let* store = validate_key capability key in
  let* receipt =
    transaction store.database (fun scope ->
        let* existing = read_transition ~scope store.database row.key_digest 1 in
        match existing with
        | Some existing when dispatch_row_equal existing row ->
            let* pointer = read_pointer ~scope store.database row.key_digest in
            begin match pointer with
            | Some (1, session, attempt)
              when String.equal session store.session_digest
                   && attempt = store.recovery_attempt ->
                Ok (transition_receipt existing true)
            | _ -> Error (diagnostic Stale_attempt)
            end
        | Some _ -> Error (diagnostic Request_conflict)
        | None ->
            let* previous = read_transition ~scope store.database row.key_digest 0 in
            begin match previous with
            | None -> Error (diagnostic Stale_attempt)
            | Some previous
              when not
                (String.equal (readback_digest_of_row store previous)
                   prepared.prepared_claim_predecessor) ->
                Error (diagnostic Stale_attempt)
            | Some _ ->
                let* pointer = read_pointer ~scope store.database row.key_digest in
                let* decision = read_decision_row ~scope store.database row.key_digest in
                begin match pointer, decision with
                | Some (0, session, attempt), Some decision
                  when String.equal session store.session_digest
                       && attempt = store.recovery_attempt
                       && decision.decision_status = Undecided
                       && String.equal decision.decision_plan_digest
                            key.key_plan_digest ->
                    let* () = insert_dispatch_transition ~scope store.database row in
                    let* () = update_pointer ~scope store.database row 0 in
                    Ok (transition_receipt row false)
                | _ -> Error (diagnostic Stale_attempt)
                end
            end)
  in
  remember_clock store prepared.prepared_claim_time;
  Ok receipt

let transition_status receipt = receipt.receipt_row.status
let transition_ordinal receipt = receipt.receipt_row.ordinal
let transition_id receipt = receipt.receipt_digest_value
let transition_replayed receipt = receipt.receipt_was_replayed
let readback_status readback = readback.readback_row.status
let readback_ordinal readback = readback.readback_row.ordinal
let readback_digest readback = readback.readback_digest_value

let reconcile_claim_current capability ~now readback =
  let* store = validate_key capability readback.readback_key in
  if store != readback.readback_store then
    Error (diagnostic Role_wrong_session)
  else
    begin match
      Dependability_clock.validate_current ~now readback.readback_time
    with
    | Error _ -> Error (diagnostic Currentness_unavailable)
    | Ok () ->
        let* fresh = read_dispatch capability readback.readback_key in
        if not
             (String.equal fresh.readback_digest_value
                readback.readback_digest_value)
        then Error (diagnostic Stale_attempt)
        else if fresh.readback_row.status <> Dispatch_claimed then
          Error (diagnostic Invalid_state_transition)
        else
          Ok
            { current_claim_store = store;
              current_claim_key = fresh.readback_key;
              current_claim_row = fresh.readback_row;
              current_claim_readback_digest = fresh.readback_digest_value;
              current_claim_session = store.session_digest;
              current_claim_attempt = store.recovery_attempt;
              current_claim_digest_value =
                sha256
                  [ "dispatch-claim-current-v1";
                    fresh.readback_digest_value;
                    Dependability_clock.digest now ] }
    end

let claim_digest claim = claim.current_claim_digest_value
let claim_owner_session_digest claim = claim.current_claim_session
let claim_recovery_attempt_ordinal claim = claim.current_claim_attempt

let validate_claim_for_role store session attempt claim =
  let* () = check_active store session attempt in
  if store != claim.current_claim_store
     || not (String.equal session claim.current_claim_session)
     || attempt <> claim.current_claim_attempt
  then Error (diagnostic Role_wrong_session)
  else
    let* pointer =
      read_pointer store.database claim.current_claim_row.key_digest
    in
    match pointer with
    | Some (ordinal, pointer_session, pointer_attempt)
      when ordinal = claim.current_claim_row.ordinal
           && String.equal pointer_session session
           && pointer_attempt = attempt ->
        let* row =
          read_transition store.database claim.current_claim_row.key_digest
            ordinal
        in
        begin match row with
        | Some row
          when row.status = Dispatch_claimed
               && String.equal (readback_digest_of_row store row)
                    claim.current_claim_readback_digest -> Ok ()
        | Some _ | None -> Error (diagnostic Stale_attempt)
        end
    | Some _ | None -> Error (diagnostic Stale_attempt)

type decision_readback = {
  decision_readback_store : store;
  decision_readback_claim : claim_current;
  decision_readback_row : decision_row;
  decision_readback_time : Dependability_clock.receipt;
  decision_readback_digest_value : string;
}

type undecided_current = { undecided_current_digest_value : string }
type decision_current = |

let decision_readback_digest_of_row store claim row =
  sha256
    [ "conditional-decision-readback-v1"; store.store_epoch;
      store.session_digest; string_of_int store.recovery_attempt;
      claim.current_claim_digest_value; row.decision_key_digest;
      decision_status_name row.decision_status; row.decision_id;
      row.decision_plan_digest; row.decision_time_digest ]

let read_decision capability claim =
  let store = capability.decision_store in
  let* () =
    validate_claim_for_role store capability.decision_session
      capability.decision_attempt claim
  in
  let* row =
    read_decision_row store.database claim.current_claim_row.key_digest
  in
  match row with
  | None -> Error (diagnostic Currentness_unavailable)
  | Some row ->
      begin match find_clock store row.decision_time_digest with
      | None -> Error (diagnostic Currentness_unavailable)
      | Some decision_readback_time ->
          Ok
            { decision_readback_store = store;
              decision_readback_claim = claim;
              decision_readback_row = row; decision_readback_time;
              decision_readback_digest_value =
                decision_readback_digest_of_row store claim row }
      end

let decision_readback_status readback =
  readback.decision_readback_row.decision_status
let decision_readback_digest readback =
  readback.decision_readback_digest_value

let reconcile_undecided_current capability ~now readback =
  let store = capability.decision_store in
  let* () =
    validate_claim_for_role store capability.decision_session
      capability.decision_attempt readback.decision_readback_claim
  in
  if store != readback.decision_readback_store then
    Error (diagnostic Role_wrong_session)
  else
    begin match
      Dependability_clock.validate_current ~now readback.decision_readback_time
    with
    | Error _ -> Error (diagnostic Currentness_unavailable)
    | Ok () ->
        let* fresh =
          read_decision capability readback.decision_readback_claim
        in
        if not
             (String.equal fresh.decision_readback_digest_value
                readback.decision_readback_digest_value)
        then Error (diagnostic Stale_attempt)
        else if fresh.decision_readback_row.decision_status <> Undecided then
          Error (diagnostic Invalid_state_transition)
        else
          Ok
            { undecided_current_digest_value =
                sha256
                  [ "conditional-undecided-current-v1";
                    fresh.decision_readback_digest_value;
                    Dependability_clock.digest now ] }
    end

let undecided_current_digest current = current.undecided_current_digest_value

type 'family prepared_decision_transition = {
  prepared_decision_claim : claim_current;
  prepared_decision_plan_digest : string;
}

let prepare_decision_transition capability ~claim ~plan =
  let store = capability.decision_store in
  let* () =
    validate_claim_for_role store capability.decision_session
      capability.decision_attempt claim
  in
  ignore (Jj_campaign_action.canonical_conditional_unsigned_bytes plan);
  Error (diagnostic Decision_protocol_unavailable)

let commit_decision_once capability prepared =
  let* () =
    validate_claim_for_role capability.decision_store
      capability.decision_session capability.decision_attempt
      prepared.prepared_decision_claim
  in
  ignore prepared.prepared_decision_plan_digest;
  Error (diagnostic Decision_protocol_unavailable)

type abandonment_readback = {
  abandonment_readback_status_value : abandonment_status;
  abandonment_readback_digest_value : string;
}

type 'purpose abandonment_current = |

type 'purpose prepared_abandonment_transition = {
  prepared_abandonment_claim : claim_current;
  prepared_abandonment_evidence_digest : string;
}

let read_abandonment capability claim =
  let store = capability.abandonment_store in
  let* () =
    validate_claim_for_role store capability.abandonment_session
      capability.abandonment_attempt claim
  in
  let* commitment =
    execute store.database
      (Closed.Dispatch_store_read_abandonment
         claim.current_claim_row.key_digest)
  in
  match commitment with
  | None ->
           Ok
             { abandonment_readback_status_value = No_abandonment;
               abandonment_readback_digest_value =
                 sha256
                   [ "abandonment-readback-v1"; store.store_epoch;
                     store.session_digest; string_of_int store.recovery_attempt;
                     claim.current_claim_digest_value; "no-abandonment" ] }
  | Some commitment ->
           Ok
             { abandonment_readback_status_value = Abandonment_committed;
               abandonment_readback_digest_value =
                 sha256
                   [ "abandonment-readback-v1"; store.store_epoch;
                     store.session_digest; string_of_int store.recovery_attempt;
                     claim.current_claim_digest_value;
                     commitment.dispatch_abandonment_commitment_id;
                     commitment.dispatch_abandonment_evidence_digest ] }

let abandonment_readback_status readback =
  readback.abandonment_readback_status_value
let abandonment_readback_digest readback =
  readback.abandonment_readback_digest_value

let prepare_abandonment_transition capability ~claim ~evidence =
  let store = capability.abandonment_store in
  let* () =
    validate_claim_for_role store capability.abandonment_session
      capability.abandonment_attempt claim
  in
  ignore
    (Dependability_abandonment_protocol.abandonment_evidence_digest evidence);
  Error (diagnostic Abandonment_protocol_unavailable)

let commit_abandonment_once capability prepared =
  let* () =
    validate_claim_for_role capability.abandonment_store
      capability.abandonment_session capability.abandonment_attempt
      prepared.prepared_abandonment_claim
  in
  ignore prepared.prepared_abandonment_evidence_digest;
  Error (diagnostic Abandonment_protocol_unavailable)

type conditional_inventory_current = {
  conditional_inventory_decision_rows : string list;
  conditional_inventory_digest_value : string;
}

type abandonment_inventory_current = {
  abandonment_inventory_commitment_rows : string list;
  abandonment_inventory_digest_value : string;
}

let conditional_inventory_digest_of store owner_rows dispatch_rows
    decision_rows =
  sha256
    ([ "dispatch-conditional-inventory-current-v1"; store.store_epoch;
       store.session_digest; string_of_int store.recovery_attempt ]
     @ List.map (fun row -> "owner:" ^ row) owner_rows
     @ List.map (fun row -> "dispatch:" ^ row) dispatch_rows
     @ List.map (fun row -> "decision:" ^ row) decision_rows)

let abandonment_inventory_digest_of store owner_rows dispatch_rows
    decision_rows abandonment_rows =
  sha256
    ([ "dispatch-abandonment-inventory-current-v1"; store.store_epoch;
       store.session_digest; string_of_int store.recovery_attempt ]
     @ List.map (fun row -> "owner:" ^ row) owner_rows
     @ List.map (fun row -> "dispatch:" ^ row) dispatch_rows
     @ List.map (fun row -> "decision:" ^ row) decision_rows
     @ List.map (fun row -> "abandonment:" ^ row) abandonment_rows)

let inventory_rows_exact rows =
  List.for_all
    (fun row -> Result.is_ok (Digest.make row))
    rows
  && List.length rows = List.length (List.sort_uniq String.compare rows)

let reconcile_restart_inventories capability ~now =
  let store = capability.lifecycle_store in
  let* () =
    check_active store capability.lifecycle_session capability.lifecycle_attempt
  in
  let* () =
    match Dependability_clock.validate now with
    | Ok () -> Ok ()
    | Error _ -> Error (diagnostic Currentness_unavailable)
  in
  let* inventory =
    execute store.database Closed.Dispatch_store_inventory_ids
  in
  let owner_rows = inventory.dispatch_inventory_owner_rows in
  let dispatch_rows = inventory.dispatch_inventory_transition_rows in
  let decision_rows = inventory.dispatch_inventory_decision_rows in
  let abandonment_rows = inventory.dispatch_inventory_abandonment_rows in
  if owner_rows = []
     || not (inventory_rows_exact owner_rows)
     || not (inventory_rows_exact dispatch_rows)
     || not (inventory_rows_exact decision_rows)
     || not (inventory_rows_exact abandonment_rows)
  then Error (diagnostic Currentness_unavailable)
  else
    let decisions =
      { conditional_inventory_decision_rows = decision_rows;
        conditional_inventory_digest_value =
          conditional_inventory_digest_of store owner_rows dispatch_rows
            decision_rows }
    in
    let abandonments =
      { abandonment_inventory_commitment_rows = abandonment_rows;
        abandonment_inventory_digest_value =
          abandonment_inventory_digest_of store owner_rows dispatch_rows
            decision_rows abandonment_rows }
    in
    Ok (decisions, abandonments)

let conditional_inventory_digest inventory =
  inventory.conditional_inventory_digest_value

let conditional_inventory_decision_count inventory =
  List.length inventory.conditional_inventory_decision_rows

let abandonment_inventory_digest inventory =
  inventory.abandonment_inventory_digest_value

let abandonment_inventory_commitment_count inventory =
  List.length inventory.abandonment_inventory_commitment_rows

let conditional_inventory_terminal_posture = `Implemented_unavailable
let abandonment_inventory_terminal_posture = `Implemented_unavailable

let inventory_identity value =
  match Dependability_owner_inventory.Identity.make value with
  | Ok identity -> Ok identity
  | Error _ -> Error (diagnostic Inventory_unavailable)

let prepare_dispatch_inventory capability ~manifest ~recovery_attempt
    ~challenge ~transition =
  let store = capability.lifecycle_store in
  let* () =
    check_active store capability.lifecycle_session capability.lifecycle_attempt
  in
  let* inventory = execute store.database Closed.Dispatch_store_inventory_ids in
  let owner_rows = inventory.dispatch_inventory_owner_rows in
  let dispatch_rows = inventory.dispatch_inventory_transition_rows in
  let decision_rows = inventory.dispatch_inventory_decision_rows in
  let abandonment_rows = inventory.dispatch_inventory_abandonment_rows in
  let raw_rows =
    List.map (fun value -> "owner-" ^ value) owner_rows
    @ List.map (fun value -> "dispatch-" ^ value) dispatch_rows
    @ List.map (fun value -> "decision-" ^ value) decision_rows
    @ List.map (fun value -> "abandonment-" ^ value) abandonment_rows
  in
  if raw_rows = [] then Error (diagnostic Inventory_unavailable)
  else
    let rec identities acc = function
      | [] -> Ok (List.rev acc)
      | value :: remaining ->
          let* identity = inventory_identity value in
          identities (identity :: acc) remaining
    in
    let* rows = identities [] raw_rows in
    let* owner_session = inventory_identity ("session-" ^ store.session_digest) in
    let* context =
      match
        Dependability_owner_inventory.make_context ~manifest ~owner_session
          ~recovery_attempt ~challenge ~transition
      with
      | Ok context -> Ok context
      | Error _ -> Error (diagnostic Inventory_unavailable)
    in
    let* denominator =
      match
        Dependability_owner_inventory.make_denominator ~expected:rows
          ~observed:rows
      with
      | Ok denominator -> Ok denominator
      | Error _ -> Error (diagnostic Inventory_unavailable)
    in
    let* owner_readback =
      inventory_identity
        ("readback-" ^ sha256 ("dispatch-inventory-v1" :: raw_rows))
    in
    match
      Dependability_owner_inventory.prepare_fragment
        ~role:Dependability_owner_inventory.Dispatch ~context ~denominator
        ~owner_readback
    with
    | Ok fragment -> Ok fragment
    | Error _ -> Error (diagnostic Inventory_unavailable)

let owner_transition store ordinal state_name =
  let time_digest = Dependability_clock.digest store.bootstrap.observed_at in
  let transition_id =
    sha256
      [ "dispatch-owner-session-transition-v1"; store.store_epoch;
        store.session_digest; string_of_int store.recovery_attempt;
        string_of_int ordinal; state_name;
        store.bootstrap.bootstrap_digest_value; time_digest ]
  in
  let* changed =
    execute store.database
      (Closed.Dispatch_store_owner_transition
         { dispatch_owner_transition_ordinal = ordinal;
           dispatch_owner_transition_state = state_name;
           dispatch_owner_transition_session = store.session_digest;
           dispatch_owner_transition_attempt = store.recovery_attempt;
           dispatch_owner_transition_epoch = store.store_epoch;
           dispatch_owner_transition_bootstrap_digest =
             store.bootstrap.bootstrap_digest_value;
           dispatch_owner_transition_time_digest = time_digest;
           dispatch_owner_transition_id = transition_id })
  in
  if changed then Ok transition_id else Error (diagnostic Stale_attempt)

let check_lifecycle_capability capability =
  let store = capability.lifecycle_store in
  if String.equal store.session_digest capability.lifecycle_session
     && store.recovery_attempt = capability.lifecycle_attempt
  then Ok store
  else Error (diagnostic Role_wrong_session)

let drain_once capability =
  let* store = check_lifecycle_capability capability in
  match store.lifecycle, store.drain_value with
  | (Draining | Closed), Some receipt ->
      Ok { receipt with drain_was_replayed = true }
  | (Draining | Closed), None -> Error (diagnostic Drain_receipt_required)
  | Active, _ ->
      let* transition_id = owner_transition store 1 "draining" in
      let receipt =
        { drain_store = store; drain_session = store.session_digest;
          drain_attempt = store.recovery_attempt;
          drain_digest_value =
            sha256
              [ "dispatch-drain-receipt-v1"; store.store_epoch;
                store.session_digest; string_of_int store.recovery_attempt;
                transition_id ];
          drain_was_replayed = false }
      in
      store.lifecycle <- Draining;
      store.drain_value <- Some receipt;
      Ok receipt

let drain_receipt_digest receipt = receipt.drain_digest_value
let drain_replayed receipt = receipt.drain_was_replayed

let close_once capability drain =
  let* store = check_lifecycle_capability capability in
  if store != drain.drain_store
     || not (String.equal store.session_digest drain.drain_session)
     || store.recovery_attempt <> drain.drain_attempt
  then Error (diagnostic Drain_receipt_mismatch)
  else
    match store.lifecycle, store.close_value with
    | Closed, Some receipt -> Ok { receipt with close_was_replayed = true }
    | Closed, None -> Error (diagnostic Close_unavailable)
    | Active, _ -> Error (diagnostic Drain_receipt_required)
    | Draining, _ ->
        let* transition_id = owner_transition store 2 "retired" in
        let receipt =
          { close_store = store; close_session = store.session_digest;
            close_attempt = store.recovery_attempt;
            close_digest_value =
              sha256
                [ "dispatch-close-receipt-v1"; store.store_epoch;
                  store.session_digest; string_of_int store.recovery_attempt;
                  drain.drain_digest_value; transition_id ];
            close_was_replayed = false }
        in
        if close_database_quietly store.database then begin
          store.lifecycle <- Closed;
          store.close_value <- Some receipt;
          Ok receipt
        end else Error (diagnostic Close_unavailable)

let close_receipt_digest receipt = receipt.close_digest_value
let close_replayed receipt = receipt.close_was_replayed

let source_digest =
  sha256
    [ "dependability-dispatch-store-foundation-v1";
      "registered-production-refuses-without-nominal-open-fence-and-lock";
      "volatile-open-consumes-same-authority-nominal-dispatch-fence";
      "four-distinct-one-shot-role-transfers";
      "exact-owner-session-and-recovery-attempt-fence";
      "append-only-not-dispatched-to-dispatch-claimed";
      "same-request-replay-different-request-conflict";
      "transactional-dispatch-pointer-cas";
      "bounded-clock-claim-currentness-readback";
      "durable-undecided-conditional-row";
      "decision-protocol-unavailable-without-family-bound-selection";
      "abandonment-protocol-unavailable-without-context-and-tail-ledger";
      "owner-derived-ordered-conditional-inventory-current";
      "owner-derived-ordered-abandonment-inventory-current";
      "restart-inventory-reread-stable-without-terminal-credit";
      "owner-derived-prepared-inventory-no-seal-forge";
      "drain-retire-close-replay" ]

module For_test = struct
  type mutation =
    | Drop_role_separation
    | Permit_production_without_lock
    | Drop_nominal_open_fence
    | Drop_session_attempt_fence
    | Overwrite_dispatch
    | Drop_request_replay_check
    | Drop_pointer_cas
    | Skip_current_readback
    | Forge_decision
    | Forge_abandonment
    | Forge_conditional_inventory
    | Forge_abandonment_inventory
    | Skip_restart_inventory_readback
    | Forge_inventory_current

  let mutation_name = function
    | Drop_role_separation -> "drop-role-separation"
    | Permit_production_without_lock -> "permit-production-without-lock"
    | Drop_nominal_open_fence -> "drop-nominal-open-fence"
    | Drop_session_attempt_fence -> "drop-session-attempt-fence"
    | Overwrite_dispatch -> "overwrite-dispatch"
    | Drop_request_replay_check -> "drop-request-replay-check"
    | Drop_pointer_cas -> "drop-pointer-cas"
    | Skip_current_readback -> "skip-current-readback"
    | Forge_decision -> "forge-decision"
    | Forge_abandonment -> "forge-abandonment"
    | Forge_conditional_inventory -> "forge-conditional-inventory"
    | Forge_abandonment_inventory -> "forge-abandonment-inventory"
    | Skip_restart_inventory_readback -> "skip-restart-inventory-readback"
    | Forge_inventory_current -> "forge-inventory-current"

  let source_digest_with_mutation mutation =
    sha256
      [ "dependability-dispatch-store-foundation-v1";
        mutation_name mutation ]
end
