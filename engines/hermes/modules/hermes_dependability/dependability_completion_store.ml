type rca_origin = Specification | Implementation | Environment | Evidence | Control

type diagnostic_kind =
  | Invalid_clock
  | Nominal_peer_open_fence_unavailable
  | Database_unavailable
  | Role_already_transferred
  | Role_wrong_session
  | Owner_not_active
  | Wrong_protocol_kind
  | Reservation_absent
  | Completion_conflict
  | Indeterminate_completion
  | Currentness_unavailable
  | Inventory_unavailable
  | Recovery_manifest_conflict
  | Recovery_currentness_conflict
  | Recovery_blocked
  | Blocked_row_retains_fence
  | Drain_receipt_required
  | Drain_receipt_mismatch
  | Close_unavailable

type diagnostic = {
  kind : diagnostic_kind;
  coordinate : string;
  origin : rca_origin;
}

let diagnostic_code = function
  | { kind = Invalid_clock; _ } -> "invalid-clock"
  | { kind = Nominal_peer_open_fence_unavailable; _ } ->
      "nominal-peer-open-fence-unavailable"
  | { kind = Database_unavailable; _ } -> "database-unavailable"
  | { kind = Role_already_transferred; _ } -> "role-already-transferred"
  | { kind = Role_wrong_session; _ } -> "role-wrong-session"
  | { kind = Owner_not_active; _ } -> "owner-not-active"
  | { kind = Wrong_protocol_kind; _ } -> "wrong-protocol-kind"
  | { kind = Reservation_absent; _ } -> "reservation-absent"
  | { kind = Completion_conflict; _ } -> "completion-conflict"
  | { kind = Indeterminate_completion; _ } -> "indeterminate-completion"
  | { kind = Currentness_unavailable; _ } -> "currentness-unavailable"
  | { kind = Inventory_unavailable; _ } -> "inventory-unavailable"
  | { kind = Recovery_manifest_conflict; _ } -> "recovery-manifest-conflict"
  | { kind = Recovery_currentness_conflict; _ } ->
      "recovery-currentness-conflict"
  | { kind = Recovery_blocked; _ } -> "recovery-blocked"
  | { kind = Blocked_row_retains_fence; _ } -> "blocked-row-retains-fence"
  | { kind = Drain_receipt_required; _ } -> "drain-receipt-required"
  | { kind = Drain_receipt_mismatch; _ } -> "drain-receipt-mismatch"
  | { kind = Close_unavailable; _ } -> "close-unavailable"

let origin_of_kind = function
  | Nominal_peer_open_fence_unavailable
  | Role_already_transferred | Role_wrong_session | Owner_not_active
  | Wrong_protocol_kind | Reservation_absent | Completion_conflict
  | Indeterminate_completion | Inventory_unavailable
  | Recovery_manifest_conflict | Recovery_currentness_conflict
  | Recovery_blocked | Blocked_row_retains_fence | Drain_receipt_required
  | Drain_receipt_mismatch -> Control
  | Invalid_clock | Currentness_unavailable -> Evidence
  | Database_unavailable | Close_unavailable -> Environment

let diagnostic kind =
  { kind; coordinate = "L5/dependability-completion-store";
    origin = origin_of_kind kind }

let diagnostic_origin diagnostic = diagnostic.origin
let diagnostic_coordinate diagnostic = diagnostic.coordinate

let sha256 fields =
  fields |> Jj_id.length_frame |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let ( let* ) result f =
  match result with Ok value -> f value | Error _ as error -> error

type unavailable_prerequisite = Nominal_peer_open_fence
type production_availability =
  | Implemented_unavailable of unavailable_prerequisite list
type row_state = Absent | Reserved | Finalized | Indeterminate | Conflict
type recovery_outcome =
  | Absent_terminal
  | Reserved_terminal
  | Finalized_terminal
  | Indeterminate_blocked
  | Conflict_blocked

type completion_row = {
  completion_id : string;
  state : row_state;
  reservation_payload_digest : string;
  reserve_request_digest : string;
  reserve_time_digest : string;
  reserve_receipt_digest : string;
  finalize_request_digest : string option;
  finalize_time_digest : string option;
  finalize_receipt_digest : string option;
  conflict_digest : string option;
}

type lifecycle_state = Active | Draining | Closed

type store = {
  database : Dependability_sqlite.owned_database;
  authority_session : string;
  authority_epoch : string;
  session : string;
  epoch : string;
  opened_at : Dependability_clock.receipt;
  mutable lifecycle : lifecycle_state;
  mutable clock_receipts : (string * Dependability_clock.receipt) list;
  mutable recovery_results : (string * recovery_result) list;
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

and reserve_capability = {
  reserve_store : store;
  reserve_session : string;
}

and finalize_capability = {
  finalize_store : store;
  finalize_session : string;
}

and read_capability = {
  read_store : store;
  read_session : string;
}

and recovery_capability = {
  recovery_store : store;
  recovery_session : string;
}

and lifecycle_capability = {
  lifecycle_store : store;
  lifecycle_session : string;
}

and reserve_outcome = Reserved_inserted | Reserved_replayed

and reserve_receipt = {
  reserve_receipt_store : store;
  reserve_completion : string;
  reserve_outcome_value : reserve_outcome;
  reserve_digest : string;
}

and finalize_outcome = Finalized_inserted | Finalized_replayed

and finalize_receipt = {
  finalize_receipt_store : store;
  finalize_completion : string;
  finalize_outcome_value : finalize_outcome;
  finalize_digest : string;
}

and readback = {
  readback_store : store;
  readback_completion : string;
  readback_state_value : row_state;
  readback_digest_value : string;
}

and recovery_unbound = {
  unbound_store : store;
  unbound_session : string;
  unbound_attempt : Dependability_owner_inventory.Identity.t;
  unbound_challenge : Dependability_owner_inventory.Identity.t;
  unbound_transition : Dependability_owner_inventory.Identity.t;
  unbound_opened_digest : string;
  mutable bound :
    ( Dependability_owner_inventory.Identity.t
    * recovery_bound
    * bound_manifest_current )
    option;
}

and recovery_bound = {
  bound_unbound : recovery_unbound;
  bound_manifest : Dependability_owner_inventory.Identity.t;
  bound_digest_value : string;
}

and bound_manifest_current = {
  bound_manifest_digest_value : string;
}

and prepared_recovery_current = {
  prepared_bound : recovery_bound;
  prepared_rows : completion_row list;
  prepared_outcome : recovery_outcome;
  prepared_digest : string;
}

and recovery_result = {
  recovery_prepared : prepared_recovery_current;
  recovery_outcome_value : recovery_outcome;
  recovery_digest_value : string;
  recovery_was_replayed : bool;
}

and drain_receipt = {
  drain_store : store;
  drain_session : string;
  drain_digest_value : string;
  drain_was_replayed : bool;
}

and close_receipt = {
  close_store : store;
  close_session : string;
  close_digest_value : string;
  close_was_replayed : bool;
}

let operational opened = opened.opened_operational
let role_bundle opened = opened.opened_roles
let operational_posture _ = `Volatile_test_foundation
let production_availability _ =
  Implemented_unavailable [ Nominal_peer_open_fence ]
let owner_session_digest operational = operational.operational_store.session
let store_epoch_digest operational = operational.operational_store.epoch

module Closed = Dependability_sqlite.Closed_operation

let closed_error _ = diagnostic Database_unavailable

let execute ?scope database operation =
  let result =
    match scope with
    | None -> Closed.execute database operation
    | Some scope -> Closed.execute_in scope operation
  in
  match result with Ok value -> Ok value | Error error -> Error (closed_error error)

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

let initialize_schema database = execute database Closed.Completion_store_initialize_v1

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

let validate_clock receipt =
  match Dependability_clock.validate receipt with
  | Ok () -> Ok ()
  | Error _ -> Error (diagnostic Invalid_clock)

let insert_owner database ~session ~epoch ~authority_session ~authority_epoch
    ~observed_at =
  execute database
    (Closed.Completion_store_insert_owner
       { completion_owner_session = session; completion_store_epoch = epoch;
         completion_authority_session = authority_session;
         completion_authority_epoch = authority_epoch;
         completion_opened_time_digest = Dependability_clock.digest observed_at })

let open_first_or_successor ~authority ~location ~observed_at =
  match Dependability_sqlite_location.registration location with
  | Some _ -> Error (diagnostic Nominal_peer_open_fence_unavailable)
  | None ->
      let* () = validate_clock observed_at in
      begin match
        Dependability_sqlite.open_database ~location ~maximum_total_attempts:1
      with
      | Error _ -> Error (diagnostic Database_unavailable)
      | Ok database ->
          if Dependability_sqlite.storage_posture database
             <> Dependability_sqlite.Volatile_test
          then begin
            ignore (close_database_quietly database);
            Error (diagnostic Nominal_peer_open_fence_unavailable)
          end else
            let authority_session =
              Dependability_authority_store.owner_session_digest authority
            in
            let authority_epoch =
              Dependability_authority_store.store_epoch_digest authority
            in
            let epoch =
              sha256
                [ "completion-store-volatile-epoch-v1"; authority_epoch;
                  authority_session;
                  Dependability_sqlite_location.reference_digest location ]
            in
            let session =
              sha256
                [ "completion-store-owner-session-v1"; epoch;
                  authority_session; authority_epoch;
                  Dependability_clock.digest observed_at ]
            in
            begin match initialize_schema database with
            | Error _ as error ->
                ignore (close_database_quietly database);
                error
            | Ok () ->
                begin match
                  insert_owner database ~session ~epoch ~authority_session
                    ~authority_epoch ~observed_at
                with
                | Error _ as error ->
                    ignore (close_database_quietly database);
                    error
                | Ok () ->
                    let store =
                      { database; authority_session; authority_epoch; session;
                        epoch; opened_at = observed_at; lifecycle = Active;
                        clock_receipts =
                          [ (Dependability_clock.digest observed_at,
                             observed_at) ];
                        recovery_results = []; drain_value = None;
                        close_value = None }
                    in
                    Ok
                      { opened_operational = { operational_store = store };
                        opened_roles =
                          { role_store = store;
                            transferred = Array.make 5 false } }
                end
            end
      end

let take bundle index make =
  if bundle.transferred.(index) then Error (diagnostic Role_already_transferred)
  else begin
    bundle.transferred.(index) <- true;
    Ok (make bundle.role_store bundle.role_store.session)
  end

let take_reserve bundle =
  take bundle 0 (fun reserve_store reserve_session ->
      { reserve_store; reserve_session })
let take_finalize bundle =
  take bundle 1 (fun finalize_store finalize_session ->
      { finalize_store; finalize_session })
let take_read bundle =
  take bundle 2 (fun read_store read_session -> { read_store; read_session })
let take_recovery bundle =
  take bundle 3 (fun recovery_store recovery_session ->
      { recovery_store; recovery_session })
let take_lifecycle bundle =
  take bundle 4 (fun lifecycle_store lifecycle_session ->
      { lifecycle_store; lifecycle_session })

let check_active store session =
  if not (String.equal store.session session) then
    Error (diagnostic Role_wrong_session)
  else match store.lifecycle with
    | Active -> Ok ()
    | Draining | Closed -> Error (diagnostic Owner_not_active)

let validate_current_time store observed_at =
  let* () = validate_clock observed_at in
  match
    Dependability_clock.validate_current ~now:observed_at store.opened_at
  with
  | Ok () -> Ok ()
  | Error _ -> Error (diagnostic Currentness_unavailable)

let remember_clock store receipt =
  let digest = Dependability_clock.digest receipt in
  if not (List.exists (fun (known, _) -> String.equal known digest)
            store.clock_receipts)
  then store.clock_receipts <- (digest, receipt) :: store.clock_receipts

let state_name = function
  | Absent -> "absent"
  | Reserved -> "reserved"
  | Finalized -> "finalized"
  | Indeterminate -> "indeterminate"
  | Conflict -> "conflict"

let state_of_name = function
  | "reserved" -> Ok Reserved
  | "finalized" -> Ok Finalized
  | "indeterminate" -> Ok Indeterminate
  | "conflict" -> Ok Conflict
  | _ -> Error (diagnostic Database_unavailable)

let closed_row (row : completion_row) : Closed.completion_store_row =
  { completion_row_id = row.completion_id;
    completion_row_state = state_name row.state;
    completion_reservation_payload_digest = row.reservation_payload_digest;
    completion_reserve_request_digest = row.reserve_request_digest;
    completion_reserve_time_digest = row.reserve_time_digest;
    completion_reserve_receipt_digest = row.reserve_receipt_digest;
    completion_finalize_request_digest = row.finalize_request_digest;
    completion_finalize_time_digest = row.finalize_time_digest;
    completion_finalize_receipt_digest = row.finalize_receipt_digest;
    completion_conflict_digest = row.conflict_digest }

let row_of_closed (row : Closed.completion_store_row) =
  let* state = state_of_name row.completion_row_state in
  Ok
    { completion_id = row.completion_row_id; state;
      reservation_payload_digest = row.completion_reservation_payload_digest;
      reserve_request_digest = row.completion_reserve_request_digest;
      reserve_time_digest = row.completion_reserve_time_digest;
      reserve_receipt_digest = row.completion_reserve_receipt_digest;
      finalize_request_digest = row.completion_finalize_request_digest;
      finalize_time_digest = row.completion_finalize_time_digest;
      finalize_receipt_digest = row.completion_finalize_receipt_digest;
      conflict_digest = row.completion_conflict_digest }

let read_row ?scope database completion_id =
  let* row = execute ?scope database (Closed.Completion_store_read completion_id) in
  match row with None -> Ok None | Some row -> let* row = row_of_closed row in Ok (Some row)

let option_field = function None -> "-" | Some value -> value

let row_digest row =
  sha256
    [ "completion-store-row-v1"; row.completion_id; state_name row.state;
      row.reservation_payload_digest; row.reserve_request_digest;
      row.reserve_time_digest; row.reserve_receipt_digest;
      option_field row.finalize_request_digest;
      option_field row.finalize_time_digest;
      option_field row.finalize_receipt_digest;
      option_field row.conflict_digest ]

let insert_reservation ~scope database row =
  execute ~scope database
    (Closed.Completion_store_insert_reservation (closed_row row))

let update_conflict ~scope database row conflicting_request =
  let conflict_digest =
    sha256
      [ "completion-store-conflict-v1"; row_digest row;
        conflicting_request ]
  in
  let* changed =
    execute ~scope database
      (Closed.Completion_store_mark_conflict
         { completion_conflict_id = row.completion_id;
           completion_conflict_value = conflict_digest })
  in
  if changed then Ok () else Error (diagnostic Completion_conflict)

type 'a cas_result = Applied of 'a | Conflict_committed

let reserve_once capability ~observed_at prepared =
  match Jj_completion_store_protocol.kind prepared with
  | Jj_completion_store_protocol.Finalize ->
      Error (diagnostic Wrong_protocol_kind)
  | Jj_completion_store_protocol.Reserve ->
      let store = capability.reserve_store in
      let* () = check_active store capability.reserve_session in
      let* () = validate_current_time store observed_at in
      let completion_id =
        Jj_completion_store_protocol.completion_id prepared
        |> Jj_id.Receipt.to_string
      in
      let reservation_payload_digest =
        Jj_completion_store_protocol.reservation_payload_digest prepared
      in
      let request_digest =
        Jj_completion_store_protocol.canonical_digest prepared
      in
      let time_digest = Dependability_clock.digest observed_at in
      let receipt_digest =
        sha256
          [ "completion-store-reserve-receipt-v1"; store.epoch;
            store.session; completion_id; reservation_payload_digest;
            request_digest; time_digest ]
      in
      let candidate =
        { completion_id; state = Reserved; reservation_payload_digest;
          reserve_request_digest = request_digest;
          reserve_time_digest = time_digest;
          reserve_receipt_digest = receipt_digest;
          finalize_request_digest = None; finalize_time_digest = None;
          finalize_receipt_digest = None; conflict_digest = None }
      in
      let* result =
        transaction store.database (fun scope ->
            let* existing = read_row ~scope store.database completion_id in
            match existing with
            | None ->
                let* () = insert_reservation ~scope store.database candidate in
                Ok
                  (Applied
                     { reserve_receipt_store = store;
                       reserve_completion = completion_id;
                       reserve_outcome_value = Reserved_inserted;
                       reserve_digest = receipt_digest })
            | Some row
              when row.state <> Conflict && row.state <> Indeterminate
                   && String.equal row.reservation_payload_digest
                        reservation_payload_digest
                   && String.equal row.reserve_request_digest request_digest ->
                Ok
                  (Applied
                     { reserve_receipt_store = store;
                       reserve_completion = completion_id;
                       reserve_outcome_value = Reserved_replayed;
                       reserve_digest = row.reserve_receipt_digest })
            | Some row when row.state = Conflict ->
                Ok Conflict_committed
            | Some row when row.state = Indeterminate ->
                Error (diagnostic Indeterminate_completion)
            | Some row ->
                let* () = update_conflict ~scope store.database row request_digest in
                Ok Conflict_committed)
      in
      begin match result with
      | Conflict_committed -> Error (diagnostic Completion_conflict)
      | Applied receipt ->
          remember_clock store observed_at;
          Ok receipt
      end

let reserve_outcome receipt = receipt.reserve_outcome_value
let reserve_receipt_digest receipt = receipt.reserve_digest

let update_finalization ~scope database row ~request_digest ~time_digest
    ~receipt_digest =
  let* changed =
    execute ~scope database
      (Closed.Completion_store_finalize
         { completion_finalize_id = row.completion_id;
           completion_finalize_reservation_payload_digest =
             row.reservation_payload_digest;
           completion_finalize_request_value = request_digest;
           completion_finalize_time_value = time_digest;
           completion_finalize_receipt_value = receipt_digest })
  in
  if changed then Ok () else Error (diagnostic Completion_conflict)

let finalize_once capability ~observed_at prepared =
  match Jj_completion_store_protocol.kind prepared with
  | Jj_completion_store_protocol.Reserve ->
      Error (diagnostic Wrong_protocol_kind)
  | Jj_completion_store_protocol.Finalize ->
      let store = capability.finalize_store in
      let* () = check_active store capability.finalize_session in
      let* () = validate_current_time store observed_at in
      let completion_id =
        Jj_completion_store_protocol.completion_id prepared
        |> Jj_id.Receipt.to_string
      in
      let reservation_payload_digest =
        Jj_completion_store_protocol.reservation_payload_digest prepared
      in
      let request_digest =
        Jj_completion_store_protocol.canonical_digest prepared
      in
      let time_digest = Dependability_clock.digest observed_at in
      let* result =
        transaction store.database (fun scope ->
            let* existing = read_row ~scope store.database completion_id in
            match existing with
            | None -> Error (diagnostic Reservation_absent)
            | Some row when row.state = Conflict -> Ok Conflict_committed
            | Some row when row.state = Indeterminate ->
                Error (diagnostic Indeterminate_completion)
            | Some row
              when not
                (String.equal row.reservation_payload_digest
                   reservation_payload_digest) ->
                let* () = update_conflict ~scope store.database row request_digest in
                Ok Conflict_committed
            | Some row when row.state = Finalized ->
                begin match row.finalize_request_digest,
                            row.finalize_receipt_digest with
                | Some known_request, Some known_receipt
                  when String.equal known_request request_digest ->
                    Ok
                      (Applied
                         { finalize_receipt_store = store;
                           finalize_completion = completion_id;
                           finalize_outcome_value = Finalized_replayed;
                           finalize_digest = known_receipt })
                | _ ->
                    let* () =
                      update_conflict ~scope store.database row request_digest
                    in
                    Ok Conflict_committed
                end
            | Some row ->
                let receipt_digest =
                  sha256
                    [ "completion-store-finalize-receipt-v1"; store.epoch;
                      store.session; completion_id;
                      reservation_payload_digest; row.reserve_receipt_digest;
                      request_digest; time_digest ]
                in
                let* () =
                  update_finalization ~scope store.database row ~request_digest
                    ~time_digest ~receipt_digest
                in
                Ok
                  (Applied
                     { finalize_receipt_store = store;
                       finalize_completion = completion_id;
                       finalize_outcome_value = Finalized_inserted;
                       finalize_digest = receipt_digest }))
      in
      begin match result with
      | Conflict_committed -> Error (diagnostic Completion_conflict)
      | Applied receipt ->
          remember_clock store observed_at;
          Ok receipt
      end

let finalize_outcome receipt = receipt.finalize_outcome_value
let finalize_receipt_digest receipt = receipt.finalize_digest

let latest_time_digest row =
  match row.finalize_time_digest with
  | Some digest -> digest
  | None -> row.reserve_time_digest

let find_clock store digest =
  List.find_map
    (fun (known, receipt) ->
       if String.equal known digest then Some receipt else None)
    store.clock_receipts

let readback_of store completion_id row =
  let state, row_identity =
    match row with
    | None -> (Absent, sha256 [ "completion-store-absent-v1"; completion_id ])
    | Some row -> (row.state, row_digest row)
  in
  { readback_store = store; readback_completion = completion_id;
    readback_state_value = state;
    readback_digest_value =
      sha256
        [ "completion-store-readback-v1"; store.epoch; store.session;
          completion_id; state_name state; row_identity ] }

let read_current capability ~observed_at prepared =
  let store = capability.read_store in
  let* () = check_active store capability.read_session in
  let* () = validate_current_time store observed_at in
  let completion_id =
    Jj_completion_store_protocol.completion_id prepared
    |> Jj_id.Receipt.to_string
  in
  let* row = read_row store.database completion_id in
  let* () =
    match row with
    | None -> Ok ()
    | Some row ->
        begin match find_clock store (latest_time_digest row) with
        | None -> Error (diagnostic Currentness_unavailable)
        | Some recorded_at ->
            begin match
              Dependability_clock.validate_current ~now:observed_at recorded_at
            with
            | Ok () -> Ok ()
            | Error _ -> Error (diagnostic Currentness_unavailable)
            end
        end
  in
  Ok (readback_of store completion_id row)

let readback_state readback = readback.readback_state_value
let readback_digest readback = readback.readback_digest_value
let readback_credit _ = `No_credit

let all_rows database =
  let* rows = execute database Closed.Completion_store_all_rows in
  let rec convert values = function
    | [] -> Ok (List.rev values)
    | row :: remaining ->
        let* row = row_of_closed row in
        convert (row :: values) remaining
  in
  convert [] rows

let rows_digest store rows =
  sha256
    ("completion-store-inventory-v1" :: store.epoch :: store.session
     :: List.map row_digest rows)

let owner_identity value =
  match Dependability_owner_inventory.Identity.make value with
  | Ok identity -> Ok identity
  | Error _ -> Error (diagnostic Inventory_unavailable)

let row_identities store rows =
  let values =
    ("completion-session-" ^ store.session)
    :: List.map (fun row -> "completion-row-" ^ row_digest row) rows
  in
  let rec make acc = function
    | [] -> Ok (List.rev acc)
    | value :: remaining ->
        let* identity = owner_identity value in
        make (identity :: acc) remaining
  in
  make [] values

let prepare_inventory_fragment store rows ~manifest ~recovery_attempt
    ~challenge ~transition =
  let open Dependability_owner_inventory in
  let* owner_session = owner_identity ("completion-session-" ^ store.session) in
  let* context =
    match
      make_context ~manifest ~owner_session ~recovery_attempt ~challenge
        ~transition
    with
    | Ok context -> Ok context
    | Error _ -> Error (diagnostic Inventory_unavailable)
  in
  let* identities = row_identities store rows in
  let* denominator =
    match make_denominator ~expected:identities ~observed:identities with
    | Ok denominator -> Ok denominator
    | Error _ -> Error (diagnostic Inventory_unavailable)
  in
  let* owner_readback =
    owner_identity ("completion-readback-" ^ rows_digest store rows)
  in
  match
    prepare_fragment ~role:Completion_store ~context ~denominator
      ~owner_readback
  with
  | Ok fragment -> Ok fragment
  | Error _ -> Error (diagnostic Inventory_unavailable)

let inventory_current capability ~manifest ~recovery_attempt ~challenge
    ~transition =
  let store = capability.read_store in
  let* () = check_active store capability.read_session in
  let* rows = all_rows store.database in
  prepare_inventory_fragment store rows ~manifest ~recovery_attempt ~challenge
    ~transition

let classify_rows = function
  | [] -> Absent_terminal
  | rows when List.exists (fun row -> row.state = Conflict) rows ->
      Conflict_blocked
  | rows when List.exists (fun row -> row.state = Indeterminate) rows ->
      Indeterminate_blocked
  | rows when List.exists (fun row -> row.state = Reserved) rows ->
      Reserved_terminal
  | _ -> Finalized_terminal

let open_recovery_inventory capability ~recovery_attempt ~challenge
    ~transition ~observed_at =
  let store = capability.recovery_store in
  let* () = check_active store capability.recovery_session in
  let* () = validate_current_time store observed_at in
  let* rows = all_rows store.database in
  Ok
    { unbound_store = store; unbound_session = store.session;
      unbound_attempt = recovery_attempt; unbound_challenge = challenge;
      unbound_transition = transition;
      unbound_opened_digest = rows_digest store rows; bound = None }

let bind_recovery_manifest_once unbound manifest =
  match unbound.bound with
  | Some (known, bound, current)
    when Dependability_owner_inventory.Identity.equal known manifest ->
      Ok (bound, current)
  | Some _ -> Error (diagnostic Recovery_manifest_conflict)
  | None ->
      let bound_digest_value =
        sha256
          [ "completion-store-recovery-bound-v1";
            unbound.unbound_store.epoch; unbound.unbound_session;
            Dependability_owner_inventory.Identity.to_string manifest;
            unbound.unbound_opened_digest ]
      in
      let bound = { bound_unbound = unbound; bound_manifest = manifest;
                    bound_digest_value }
      in
      let current =
        { bound_manifest_digest_value =
            sha256
              [ "completion-store-bound-manifest-v1";
                bound_digest_value ] }
      in
      unbound.bound <- Some (manifest, bound, current);
      Ok (bound, current)

let bound_manifest_digest value = value.bound_manifest_digest_value
let recovery_bound_digest value = value.bound_digest_value

let prepare_recovery_current bound ~observed_at =
  let unbound = bound.bound_unbound in
  let store = unbound.unbound_store in
  let* () = check_active store unbound.unbound_session in
  let* () = validate_current_time store observed_at in
  let* rows = all_rows store.database in
  let outcome = classify_rows rows in
  Ok
    { prepared_bound = bound; prepared_rows = rows;
      prepared_outcome = outcome;
      prepared_digest =
        sha256
          [ "completion-store-recovery-current-v1";
            bound.bound_digest_value; rows_digest store rows;
            (match outcome with
             | Absent_terminal -> "absent-terminal"
             | Reserved_terminal -> "reserved-terminal"
             | Finalized_terminal -> "finalized-terminal"
             | Indeterminate_blocked -> "indeterminate-blocked"
             | Conflict_blocked -> "conflict-blocked");
            Dependability_clock.digest observed_at ] }

let reconcile_recovery_once capability prepared =
  let store = capability.recovery_store in
  let* () = check_active store capability.recovery_session in
  if store != prepared.prepared_bound.bound_unbound.unbound_store then
    Error (diagnostic Role_wrong_session)
  else
    let* current_rows = all_rows store.database in
    if not
         (String.equal (rows_digest store current_rows)
            (rows_digest store prepared.prepared_rows))
    then Error (diagnostic Recovery_currentness_conflict)
    else
      match
        List.find_opt
          (fun (digest, _) -> String.equal digest prepared.prepared_digest)
          store.recovery_results
      with
      | Some (_, result) -> Ok { result with recovery_was_replayed = true }
      | None ->
          let outcome = prepared.prepared_outcome in
          let result =
            { recovery_prepared = prepared; recovery_outcome_value = outcome;
              recovery_digest_value =
                sha256
                  [ "completion-store-recovery-result-v1";
                    prepared.prepared_digest ];
              recovery_was_replayed = false }
          in
          store.recovery_results <-
            (prepared.prepared_digest, result) :: store.recovery_results;
          Ok result

let recovery_outcome result = result.recovery_outcome_value
let recovery_result_digest result = result.recovery_digest_value
let recovery_replayed result = result.recovery_was_replayed

let prepare_recovered_fragment result =
  match result.recovery_outcome_value with
  | Indeterminate_blocked | Conflict_blocked ->
      Error (diagnostic Recovery_blocked)
  | Absent_terminal | Reserved_terminal | Finalized_terminal ->
      let prepared = result.recovery_prepared in
      let bound = prepared.prepared_bound in
      let unbound = bound.bound_unbound in
      let* fragment =
        prepare_inventory_fragment unbound.unbound_store prepared.prepared_rows
          ~manifest:bound.bound_manifest
          ~recovery_attempt:unbound.unbound_attempt
          ~challenge:unbound.unbound_challenge
          ~transition:unbound.unbound_transition
      in
      let* completion_readback =
        owner_identity ("completion-recovery-" ^ result.recovery_digest_value)
      in
      begin match
        Dependability_owner_inventory.prepare_recovery_only_terminal_fragment
          ~fragment
          ~readback:
            (Dependability_owner_inventory.Recovery_completion_store_readback
               { completion_readback })
      with
      | Ok prepared -> Ok prepared
      | Error _ -> Error (diagnostic Inventory_unavailable)
      end

let blocked_rows store =
  let* rows = all_rows store.database in
  Ok
    (List.exists
       (fun row -> row.state = Indeterminate || row.state = Conflict)
       rows)

let update_owner_state ~scope store ~from_state ~to_state =
  let* changed =
    execute ~scope store.database
      (Closed.Completion_store_owner_cas
         { completion_owner_from_state = from_state;
           completion_owner_to_state = to_state;
           completion_owner_cas_session = store.session;
           completion_owner_cas_epoch = store.epoch })
  in
  if changed then Ok () else Error (diagnostic Owner_not_active)

let check_lifecycle capability =
  let store = capability.lifecycle_store in
  if String.equal store.session capability.lifecycle_session then Ok store
  else Error (diagnostic Role_wrong_session)

let drain capability =
  let* store = check_lifecycle capability in
  match store.lifecycle, store.drain_value with
  | (Draining | Closed), Some receipt ->
      Ok { receipt with drain_was_replayed = true }
  | (Draining | Closed), None -> Error (diagnostic Drain_receipt_required)
  | Active, _ ->
      let* blocked = blocked_rows store in
      if blocked then Error (diagnostic Blocked_row_retains_fence)
      else
        let* () =
          transaction store.database (fun scope ->
              update_owner_state ~scope store ~from_state:"active"
                ~to_state:"draining")
        in
        let receipt =
          { drain_store = store; drain_session = store.session;
            drain_digest_value =
              sha256
                [ "completion-store-drain-receipt-v1"; store.epoch;
                  store.session ];
            drain_was_replayed = false }
        in
        store.lifecycle <- Draining;
        store.drain_value <- Some receipt;
        Ok receipt

let drain_receipt_digest receipt = receipt.drain_digest_value
let drain_replayed receipt = receipt.drain_was_replayed

let close capability drain =
  let* store = check_lifecycle capability in
  if store != drain.drain_store
     || not (String.equal store.session drain.drain_session)
  then Error (diagnostic Drain_receipt_mismatch)
  else match store.lifecycle, store.close_value with
    | Closed, Some receipt -> Ok { receipt with close_was_replayed = true }
    | Closed, None -> Error (diagnostic Close_unavailable)
    | Active, _ -> Error (diagnostic Drain_receipt_required)
    | Draining, _ ->
        let* () =
          transaction store.database (fun scope ->
              update_owner_state ~scope store ~from_state:"draining"
                ~to_state:"retired")
        in
        let receipt =
          { close_store = store; close_session = store.session;
            close_digest_value =
              sha256
                [ "completion-store-close-receipt-v1"; store.epoch;
                  store.session; drain.drain_digest_value ];
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
    [ "dependability-completion-store-foundation-v1";
      "production-peer-open-unavailable";
      "authority-session-and-store-epoch-bound";
      "five-distinct-one-shot-capabilities";
      "append-only-reservation";
      "same-request-replay-different-request-durable-conflict";
      "common-reservation-payload-finalize-cas";
      "current-clock-bound-readback";
      "owner-derived-recovery-no-third-command";
      "terminal-prepared-fragment-no-producer-seal";
      "blocked-row-retains-fence";
      Jj_completion_store_protocol.source_digest ]

module For_test = struct
  type mutation =
    | Drop_role_separation
    | Permit_production_without_peer_fence
    | Drop_authority_session_binding
    | Overwrite_reservation
    | Drop_replay_check
    | Forge_common_payload_match
    | Skip_current_readback
    | Caller_supplied_reconcile
    | Forge_producer_seal
    | Close_blocked_row

  let name = function
    | Drop_role_separation -> "drop-role-separation"
    | Permit_production_without_peer_fence -> "permit-production-without-peer-fence"
    | Drop_authority_session_binding -> "drop-authority-session-binding"
    | Overwrite_reservation -> "overwrite-reservation"
    | Drop_replay_check -> "drop-replay-check"
    | Forge_common_payload_match -> "forge-common-payload-match"
    | Skip_current_readback -> "skip-current-readback"
    | Caller_supplied_reconcile -> "caller-supplied-reconcile"
    | Forge_producer_seal -> "forge-producer-seal"
    | Close_blocked_row -> "close-blocked-row"

  let source_digest_with_mutation mutation =
    sha256
      [ "dependability-completion-store-foundation-v1"; name mutation ]
end
