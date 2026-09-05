type rca_origin = Specification | Implementation | Environment | Evidence | Control

type diagnostic_kind =
  | Invalid_digest
  | Invalid_clock
  | Physical_owner_lock_unavailable
  | Database_unavailable
  | Schema_unavailable
  | Role_already_transferred
  | Role_wrong_session
  | Owner_not_active
  | Request_conflict
  | Stale_generation
  | Invalid_state_transition
  | Missing_activation
  | Currentness_unavailable
  | Inventory_unavailable
  | Drain_receipt_required
  | Drain_receipt_mismatch
  | Close_unavailable
  | Peer_bundle_already_split
  | Peer_open_already_consumed
  | Invalid_nonce_denominator
  | Missing_approval_nonce
  | Approval_inventory_mismatch

type diagnostic = {
  kind : diagnostic_kind;
  coordinate : string;
  origin : rca_origin;
}

let kind_code = function
  | Invalid_digest -> "invalid-digest"
  | Invalid_clock -> "invalid-clock"
  | Physical_owner_lock_unavailable -> "physical-owner-lock-unavailable"
  | Database_unavailable -> "database-unavailable"
  | Schema_unavailable -> "schema-unavailable"
  | Role_already_transferred -> "role-already-transferred"
  | Role_wrong_session -> "role-wrong-session"
  | Owner_not_active -> "owner-not-active"
  | Request_conflict -> "request-conflict"
  | Stale_generation -> "stale-generation"
  | Invalid_state_transition -> "invalid-state-transition"
  | Missing_activation -> "missing-activation"
  | Currentness_unavailable -> "currentness-unavailable"
  | Inventory_unavailable -> "inventory-unavailable"
  | Drain_receipt_required -> "drain-receipt-required"
  | Drain_receipt_mismatch -> "drain-receipt-mismatch"
  | Close_unavailable -> "close-unavailable"
  | Peer_bundle_already_split -> "peer-bundle-already-split"
  | Peer_open_already_consumed -> "peer-open-already-consumed"
  | Invalid_nonce_denominator -> "invalid-nonce-denominator"
  | Missing_approval_nonce -> "missing-approval-nonce"
  | Approval_inventory_mismatch -> "approval-inventory-mismatch"

let origin_of_kind = function
  | Physical_owner_lock_unavailable | Database_unavailable | Close_unavailable ->
      Environment
  | Currentness_unavailable -> Evidence
  | Schema_unavailable | Inventory_unavailable -> Control
  | Invalid_digest | Invalid_clock | Role_already_transferred
  | Role_wrong_session | Owner_not_active | Request_conflict
  | Stale_generation | Invalid_state_transition | Missing_activation
  | Drain_receipt_required | Drain_receipt_mismatch
  | Peer_bundle_already_split | Peer_open_already_consumed
  | Invalid_nonce_denominator | Missing_approval_nonce
  | Approval_inventory_mismatch -> Control

let diagnostic kind =
  { kind; coordinate = "L5/dependability-authority-store";
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
  build : Digest.t;
  root : Digest.t;
  configuration : Digest.t;
  host : Digest.t;
  pins : Digest.t;
  observed_at : Dependability_clock.receipt;
  bootstrap_digest_value : string;
}

let prepare_bootstrap ~build ~root ~configuration ~host ~pins ~observed_at =
  match Dependability_clock.validate observed_at with
  | Error _ -> Error (diagnostic Invalid_clock)
  | Ok () ->
      let bootstrap_digest_value =
        sha256
          [ "dependability-authority-bootstrap-v1"; Digest.to_hex build;
            Digest.to_hex root; Digest.to_hex configuration;
            Digest.to_hex host; Digest.to_hex pins;
            Dependability_clock.digest observed_at ]
      in
      Ok
        { build; root; configuration; host; pins; observed_at;
          bootstrap_digest_value }

let bootstrap_digest context = context.bootstrap_digest_value

type lifecycle_state = Active | Draining | Closed

type transition_row = {
  key_digest : string;
  generation : int;
  ordinal : int;
  status : status;
  activation_id : string;
  request_digest : string;
  evidence_digest : string;
  context_digest : string;
  time_digest : string;
}

and status = Missing | Root_active | Classified_active

type store = {
  database : Dependability_sqlite.owned_database;
  bootstrap : bootstrap_context;
  store_epoch : string;
  session_generation : int;
  session_digest : string;
  mutable lifecycle : lifecycle_state;
  mutable clock_receipts :
    (string * Dependability_clock.receipt) list;
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
  opened_peer_opens : peer_operational_open_bundle;
}

and peer_operational_open_bundle = {
  peer_open_store : store;
  mutable peer_open_split : bool;
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
let peer_operational_open_bundle opened = opened.opened_peer_opens

type peer_open = {
  peer_fence_store : store;
  peer_fence_session : string;
  peer_fence_epoch : string;
  mutable peer_fence_consumed : bool;
}

type writer_operational_open = Writer_operational_open of peer_open
type dispatch_operational_open = Dispatch_operational_open of peer_open
type vault_operational_open = Vault_operational_open of peer_open
type completion_operational_open = Completion_operational_open of peer_open

let make_peer_open store =
  { peer_fence_store = store; peer_fence_session = store.session_digest;
    peer_fence_epoch = store.store_epoch; peer_fence_consumed = false }

let split_peer_operational_open_once bundle =
  let store = bundle.peer_open_store in
  match store.lifecycle with
  | Draining | Closed -> Error (diagnostic Owner_not_active)
  | Active when bundle.peer_open_split ->
      Error (diagnostic Peer_bundle_already_split)
  | Active ->
      bundle.peer_open_split <- true;
      Ok
        ( Writer_operational_open (make_peer_open store),
          Dispatch_operational_open (make_peer_open store),
          Vault_operational_open (make_peer_open store),
          Completion_operational_open (make_peer_open store) )

let consume_peer_open fence authority =
  let store = authority.operational_store in
  if store != fence.peer_fence_store
     || not (String.equal store.session_digest fence.peer_fence_session)
     || not (String.equal store.store_epoch fence.peer_fence_epoch)
  then Error (diagnostic Role_wrong_session)
  else match store.lifecycle with
    | Draining | Closed -> Error (diagnostic Owner_not_active)
    | Active when fence.peer_fence_consumed ->
        Error (diagnostic Peer_open_already_consumed)
    | Active ->
        fence.peer_fence_consumed <- true;
        Ok ()

let consume_writer_operational_open (Writer_operational_open fence) ~authority =
  consume_peer_open fence authority
let consume_dispatch_operational_open (Dispatch_operational_open fence)
    ~authority =
  consume_peer_open fence authority
let consume_vault_operational_open (Vault_operational_open fence) ~authority =
  consume_peer_open fence authority
let consume_completion_operational_open (Completion_operational_open fence)
    ~authority =
  consume_peer_open fence authority

type writer_inventory_fence = |
type dispatch_inventory_fence = |
type vault_inventory_fence = |
type completion_inventory_fence = |

let peer_inventory_fence_posture = `Implemented_unavailable
let owner_session_generation operational =
  operational.operational_store.session_generation
let owner_session_digest operational = operational.operational_store.session_digest
let store_epoch_digest operational = operational.operational_store.store_epoch
let operational_posture _ = `Volatile_test_foundation

let ( let* ) result f = match result with Ok value -> f value | Error _ as error -> error

module Closed = Dependability_sqlite.Closed_operation

let execute ?scope database operation =
  let result = match scope with
    | None -> Closed.execute database operation
    | Some scope -> Closed.execute_in scope operation
  in
  match result with Ok value -> Ok value | Error _ -> Error (diagnostic Database_unavailable)

let initialize_schema database = execute database Closed.Authority_store_initialize_v1

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
  match Closed.with_transaction database ~mode:Closed.Read_write (fun scope ->
    match body scope with
    | Ok value -> Ok value
    | Error error ->
        body_error := Some error;
        Error (Closed.Operation_failed (diagnostic_code error))) with
  | Ok value -> Ok value
  | Error _ ->
      begin match !body_error with Some error -> Error error
      | None -> Error (diagnostic Database_unavailable) end

let insert_initial_owner_session database bootstrap store_epoch session_digest =
  let time_digest = Dependability_clock.digest bootstrap.observed_at in
  let transition_id =
    sha256
      [ "authority-owner-session-transition-v1"; store_epoch; session_digest;
        "1"; "0"; "active"; bootstrap.bootstrap_digest_value; time_digest ]
  in
  execute database
    (Closed.Authority_store_insert_initial_owner
       { authority_initial_session = session_digest;
         authority_initial_epoch = store_epoch;
         authority_initial_bootstrap_digest = bootstrap.bootstrap_digest_value;
         authority_initial_time_digest = time_digest;
         authority_initial_transition_id = transition_id })

let open_first_or_successor ~location ~bootstrap =
  match Dependability_sqlite_location.registration location with
  | Some _ -> Error (diagnostic Physical_owner_lock_unavailable)
  | None ->
      begin match
        Dependability_sqlite.open_database ~location ~maximum_total_attempts:1
      with
      | Error _ -> Error (diagnostic Database_unavailable)
      | Ok database ->
          if Dependability_sqlite.storage_posture database
             <> Dependability_sqlite.Volatile_test
          then begin
            ignore (close_database_quietly database);
            Error (diagnostic Physical_owner_lock_unavailable)
          end else
            let store_epoch =
              sha256
                [ "authority-store-volatile-epoch-v1";
                  Dependability_sqlite_location.reference_digest location;
                  bootstrap.bootstrap_digest_value ]
            in
            let session_digest =
              sha256
                [ "authority-owner-session-v1"; store_epoch; "1";
                  bootstrap.bootstrap_digest_value;
                  Dependability_clock.digest bootstrap.observed_at ]
            in
            begin match initialize_schema database with
            | Error _ as error ->
                ignore (close_database_quietly database);
                error
            | Ok () ->
                begin match
                  insert_initial_owner_session database bootstrap store_epoch
                    session_digest
                with
                | Error _ as error ->
                    ignore (close_database_quietly database);
                    error
                | Ok () ->
                    let store =
                      { database; bootstrap; store_epoch; session_generation = 1;
                        session_digest; lifecycle = Active;
                        clock_receipts =
                          [ (Dependability_clock.digest bootstrap.observed_at,
                             bootstrap.observed_at) ];
                        drain_value = None; close_value = None }
                    in
                    Ok
                      { opened_operational = { operational_store = store };
                        opened_roles =
                          { role_store = store;
                            transferred = Array.make 8 false };
                        opened_peer_opens =
                          { peer_open_store = store;
                            peer_open_split = false } }
                end
            end
      end

type approval_nonce_capability = { approval_nonce_store : store; approval_nonce_session : string }
type approval_dormancy_capability = { approval_dormancy_store : store; approval_dormancy_session : string }
type approval_abandonment_capability = { approval_abandonment_store : store; approval_abandonment_session : string }
type writer_fence_capability = { writer_fence_store : store; writer_fence_session : string }
type production_activation_capability = { activation_store : store; activation_session : string }
type recovery_port_issuer_capability = { recovery_issuer_store : store; recovery_issuer_session : string }
type recovery_port_lifecycle_capability = { recovery_lifecycle_store : store; recovery_lifecycle_session : string }
type lifecycle_capability = { lifecycle_store : store; lifecycle_session : string }

let take_role bundle index construct =
  if bundle.transferred.(index) then
    Error (diagnostic Role_already_transferred)
  else begin
    bundle.transferred.(index) <- true;
    Ok (construct bundle.role_store bundle.role_store.session_digest)
  end

let take_approval_nonce bundle =
  take_role bundle 0 (fun store session ->
      { approval_nonce_store = store; approval_nonce_session = session })
let take_approval_dormancy bundle =
  take_role bundle 1 (fun store session ->
      { approval_dormancy_store = store; approval_dormancy_session = session })
let take_approval_abandonment bundle =
  take_role bundle 2 (fun store session ->
      { approval_abandonment_store = store;
        approval_abandonment_session = session })
let take_writer_fence bundle =
  take_role bundle 3 (fun store session ->
      { writer_fence_store = store; writer_fence_session = session })
let take_production_activation bundle =
  take_role bundle 4 (fun store session ->
      { activation_store = store; activation_session = session })
let take_recovery_port_issuer bundle =
  take_role bundle 5 (fun store session ->
      { recovery_issuer_store = store; recovery_issuer_session = session })
let take_recovery_port_lifecycle bundle =
  take_role bundle 6 (fun store session ->
      { recovery_lifecycle_store = store; recovery_lifecycle_session = session })
let take_lifecycle bundle =
  take_role bundle 7 (fun store session ->
      { lifecycle_store = store; lifecycle_session = session })

type approval_identity = Approval_identity of Digest.t
type approval_occurrence = Approval_occurrence of Digest.t * Digest.t

type approval_campaign_key = {
  approval_key_store : store;
  approval_key_epoch : string;
  approval_key_session : string;
  approval_key_digest : string;
  approval_key_identity : string;
  approval_key_plan : string;
}

type approval_campaign_row = {
  campaign_key_digest : string;
  campaign_approval_identity : string;
  campaign_plan_digest : string;
  campaign_request_digest : string;
  campaign_verification_digest : string;
  campaign_denominator_digest : string;
  campaign_occurrence_count : int;
  campaign_session_digest : string;
  campaign_store_epoch : string;
  campaign_time_digest : string;
  campaign_registration_id : string;
}

type approval_nonce_row = {
  nonce_key_digest : string;
  nonce_occurrence_ordinal : int;
  nonce_occurrence_identity : string;
  nonce_identity : string;
  nonce_transition_ordinal : int;
  nonce_state_value : approval_nonce_state;
  nonce_request_digest : string;
  nonce_verification_digest : string;
  nonce_session_digest : string;
  nonce_store_epoch : string;
  nonce_time_digest : string;
  nonce_transition_id : string;
}

and approval_nonce_state =
  | Available
  | Consumed
  | Dormant_closed
  | Abandoned_closed

type prepared_approval_campaign = {
  prepared_campaign_key : approval_campaign_key;
  prepared_campaign_row : approval_campaign_row;
  prepared_nonce_rows : approval_nonce_row list;
  prepared_campaign_time : Dependability_clock.receipt;
}

type approval_campaign_receipt = {
  campaign_receipt_store : store;
  campaign_receipt_key : approval_campaign_key;
  campaign_receipt_row : approval_campaign_row;
  campaign_receipt_nonces : approval_nonce_row list;
  campaign_receipt_digest_value : string;
  campaign_receipt_was_replayed : bool;
}

type approval_occurrence_nonce = {
  occurrence_nonce_store : store;
  occurrence_nonce_epoch : string;
  occurrence_nonce_session : string;
  occurrence_nonce_key : string;
  occurrence_nonce_identity : string;
  occurrence_nonce_occurrence : string;
}

type approval_nonce_readback = {
  nonce_readback_store : store;
  nonce_readback_nonce : approval_occurrence_nonce;
  nonce_readback_row : approval_nonce_row;
  nonce_readback_time : Dependability_clock.receipt;
  nonce_readback_digest_value : string;
}

type approval_nonce_current = {
  nonce_current_row : approval_nonce_row;
  nonce_current_digest_value : string;
}

let approval_identity digest = Approval_identity digest
let approval_occurrence ~identity ~nonce =
  Approval_occurrence (identity, nonce)

let approval_nonce_transition_posture = `Implemented_unavailable

let check_active store session =
  if not (String.equal store.session_digest session) then
    Error (diagnostic Role_wrong_session)
  else match store.lifecycle with
    | Active -> Ok ()
    | Draining | Closed -> Error (diagnostic Owner_not_active)

type activation_key = {
  key_store : store;
  key_store_epoch : string;
  key_session : string;
  key_digest_value : string;
}

let prepare_activation_key capability ~root =
  let store = capability.activation_store in
  let* () = check_active store capability.activation_session in
  if not (Digest.equal root store.bootstrap.root) then
    Error (diagnostic Role_wrong_session)
  else
    let key_digest_value =
      sha256
        [ "authority-production-activation-key-v1"; store.store_epoch;
          store.session_digest; Digest.to_hex store.bootstrap.root ]
    in
    Ok
      { key_store = store; key_store_epoch = store.store_epoch;
        key_session = store.session_digest; key_digest_value }

let activation_key_digest key = key.key_digest_value

type prepared_initialization = {
  initialization_key : activation_key;
  initialization_row : transition_row;
  initialization_time : Dependability_clock.receipt;
}

type prepared_root_activation = {
  root_key : activation_key;
  root_predecessor_digest : string;
  root_row : transition_row;
  root_time : Dependability_clock.receipt;
}

type prepared_classification = {
  classification_key : activation_key;
  classification_predecessor_digest : string;
  classification_row : transition_row;
  classification_time : Dependability_clock.receipt;
}

and activation_readback = {
  readback_store : store;
  readback_key : activation_key;
  readback_row : transition_row;
  readback_time : Dependability_clock.receipt;
  readback_digest_value : string;
}

type transition_receipt = {
  transition_row : transition_row;
  transition_digest_value : string;
  transition_was_replayed : bool;
}

type activation_current = {
  current_row : transition_row;
  current_digest_value : string;
}

let status_name = function
  | Missing -> "missing"
  | Root_active -> "root-active"
  | Classified_active -> "classified-active"

let status_of_name = function
  | "missing" -> Ok Missing
  | "root-active" -> Ok Root_active
  | "classified-active" -> Ok Classified_active
  | _ -> Error (diagnostic Database_unavailable)

let validate_time receipt =
  match Dependability_clock.validate receipt with
  | Ok () -> Ok ()
  | Error _ -> Error (diagnostic Invalid_clock)

let make_row ~key ~generation ~ordinal ~status ~request ~evidence ~context
    ~observed_at =
  let time_digest = Dependability_clock.digest observed_at in
  let activation_id =
    sha256
      [ "authority-activation-transition-v1"; key.key_digest_value;
        string_of_int generation; string_of_int ordinal; status_name status;
        Digest.to_hex request; Digest.to_hex evidence; Digest.to_hex context;
        time_digest ]
  in
  { key_digest = key.key_digest_value; generation; ordinal; status;
    activation_id; request_digest = Digest.to_hex request;
    evidence_digest = Digest.to_hex evidence;
    context_digest = Digest.to_hex context; time_digest }

let prepare_initialization ~key ~request ~evidence ~context ~observed_at =
  let* () = validate_time observed_at in
  let row =
    make_row ~key ~generation:0 ~ordinal:0 ~status:Missing ~request ~evidence
      ~context ~observed_at
  in
  Ok
    { initialization_key = key; initialization_row = row;
      initialization_time = observed_at }

let read_pointer ?scope database key_digest =
  let* pointer = execute ?scope database (Closed.Authority_store_read_pointer key_digest) in
  match pointer with None -> Ok None
  | Some pointer -> Ok (Some (pointer.authority_pointer_generation,
                              pointer.authority_pointer_ordinal))

let closed_transition (row : transition_row) : Closed.authority_store_transition =
  { authority_transition_key = row.key_digest;
    authority_transition_generation = row.generation;
    authority_transition_ordinal = row.ordinal;
    authority_transition_status = status_name row.status;
    authority_transition_id = row.activation_id;
    authority_transition_request_digest = row.request_digest;
    authority_transition_evidence_digest = row.evidence_digest;
    authority_transition_context_digest = row.context_digest;
    authority_transition_time_digest = row.time_digest }

let transition_of_closed (row : Closed.authority_store_transition) =
  let* status = status_of_name row.authority_transition_status in
  Ok { key_digest = row.authority_transition_key;
       generation = row.authority_transition_generation;
       ordinal = row.authority_transition_ordinal; status;
       activation_id = row.authority_transition_id;
       request_digest = row.authority_transition_request_digest;
       evidence_digest = row.authority_transition_evidence_digest;
       context_digest = row.authority_transition_context_digest;
       time_digest = row.authority_transition_time_digest }

let read_transition ?scope database key_digest generation ordinal =
  let* row = execute ?scope database
      (Closed.Authority_store_read_transition
         { authority_lookup_key = key_digest;
           authority_lookup_generation = generation;
           authority_lookup_ordinal = ordinal }) in
  match row with None -> Ok None
  | Some row -> let* row = transition_of_closed row in Ok (Some row)

let row_equal left right =
  String.equal left.key_digest right.key_digest
  && left.generation = right.generation
  && left.ordinal = right.ordinal
  && left.status = right.status
  && String.equal left.activation_id right.activation_id
  && String.equal left.request_digest right.request_digest
  && String.equal left.evidence_digest right.evidence_digest
  && String.equal left.context_digest right.context_digest
  && String.equal left.time_digest right.time_digest

let insert_transition ~scope database row =
  execute ~scope database (Closed.Authority_store_insert_transition (closed_transition row))

let transition_receipt row replayed =
  { transition_row = row;
    transition_digest_value =
      sha256 [ "authority-transition-receipt-v1"; row.activation_id ];
    transition_was_replayed = replayed }

let remember_clock store receipt =
  let digest = Dependability_clock.digest receipt in
  if not (List.exists (fun (known, _) -> String.equal known digest)
            store.clock_receipts)
  then store.clock_receipts <- (digest, receipt) :: store.clock_receipts

let validate_key capability key =
  let store = capability.activation_store in
  let* () = check_active store capability.activation_session in
  if store != key.key_store
     || not (String.equal store.store_epoch key.key_store_epoch)
     || not (String.equal store.session_digest key.key_session)
  then Error (diagnostic Role_wrong_session)
  else Ok store

let initialize_first_missing capability prepared =
  let key = prepared.initialization_key and row = prepared.initialization_row in
  let* store = validate_key capability key in
  let* receipt =
    transaction store.database (fun scope ->
        let* existing = read_transition ~scope store.database row.key_digest 0 0 in
        match existing with
        | Some existing when row_equal existing row ->
            Ok (transition_receipt existing true)
        | Some _ -> Error (diagnostic Request_conflict)
        | None ->
            let* pointer = read_pointer ~scope store.database row.key_digest in
            begin match pointer with
            | Some _ -> Error (diagnostic Request_conflict)
            | None ->
                let* () = insert_transition ~scope store.database row in
                let* () =
                  execute ~scope store.database
                    (Closed.Authority_store_insert_pointer row.key_digest)
                in
                Ok (transition_receipt row false)
            end)
  in
  remember_clock store prepared.initialization_time;
  Ok receipt

let readback_digest_of_row store row =
  sha256
    [ "authority-activation-readback-v1"; store.store_epoch;
      store.session_digest; row.key_digest; string_of_int row.generation;
      string_of_int row.ordinal; status_name row.status; row.activation_id;
      row.request_digest; row.evidence_digest; row.context_digest;
      row.time_digest ]

let find_clock store digest =
  List.find_map
    (fun (known, receipt) ->
       if String.equal known digest then Some receipt else None)
    store.clock_receipts

let approval_nonce_state_name = function
  | Available -> "available"
  | Consumed -> "consumed"
  | Dormant_closed -> "dormant-closed"
  | Abandoned_closed -> "abandoned-closed"

let approval_nonce_state_of_name = function
  | "available" -> Ok Available
  | "consumed" -> Ok Consumed
  | "dormant-closed" -> Ok Dormant_closed
  | "abandoned-closed" -> Ok Abandoned_closed
  | _ -> Error (diagnostic Schema_unavailable)

let validate_approval_key capability key =
  let store = capability.approval_nonce_store in
  let* () = check_active store capability.approval_nonce_session in
  if store != key.approval_key_store
     || not (String.equal store.store_epoch key.approval_key_epoch)
     || not (String.equal store.session_digest key.approval_key_session)
  then Error (diagnostic Role_wrong_session)
  else Ok store

let prepare_approval_campaign_key capability ~approval ~plan =
  let store = capability.approval_nonce_store in
  let* () = check_active store capability.approval_nonce_session in
  let Approval_identity approval = approval in
  let approval = Digest.to_hex approval and plan = Digest.to_hex plan in
  Ok
    { approval_key_store = store; approval_key_epoch = store.store_epoch;
      approval_key_session = store.session_digest;
      approval_key_digest =
        sha256 [ "authority-approval-campaign-key-v1"; store.store_epoch;
                 store.session_digest; approval; plan ];
      approval_key_identity = approval; approval_key_plan = plan }

let distinct values =
  List.length values = List.length (List.sort_uniq String.compare values)

let prepare_approval_campaign ~key ~request ~verification ~occurrences
    ~observed_at =
  let* () = validate_time observed_at in
  let occurrences =
    List.map
      (fun (Approval_occurrence (identity, nonce)) ->
         Digest.to_hex identity, Digest.to_hex nonce)
      occurrences
  in
  let occurrence_ids = List.map fst occurrences in
  let nonce_ids = List.map snd occurrences in
  if occurrences = [] || not (distinct occurrence_ids)
     || not (distinct nonce_ids)
  then Error (diagnostic Invalid_nonce_denominator)
  else
    let request = Digest.to_hex request in
    let verification = Digest.to_hex verification in
    let time = Dependability_clock.digest observed_at in
    let denominator =
      occurrences
      |> List.mapi (fun ordinal (identity, nonce) ->
             [ string_of_int ordinal; identity; nonce ])
      |> List.flatten
      |> fun fields -> sha256 ("authority-approval-denominator-v1" :: fields)
    in
    let registration =
      sha256
        [ "authority-approval-campaign-registration-v1";
          key.approval_key_epoch; key.approval_key_session;
          key.approval_key_digest; key.approval_key_identity;
          key.approval_key_plan; request; verification; denominator;
          string_of_int (List.length occurrences); time ]
    in
    let campaign =
      { campaign_key_digest = key.approval_key_digest;
        campaign_approval_identity = key.approval_key_identity;
        campaign_plan_digest = key.approval_key_plan;
        campaign_request_digest = request;
        campaign_verification_digest = verification;
        campaign_denominator_digest = denominator;
        campaign_occurrence_count = List.length occurrences;
        campaign_session_digest = key.approval_key_session;
        campaign_store_epoch = key.approval_key_epoch;
        campaign_time_digest = time; campaign_registration_id = registration }
    in
    let nonces =
      List.mapi
        (fun ordinal (occurrence, nonce) ->
           { nonce_key_digest = key.approval_key_digest;
             nonce_occurrence_ordinal = ordinal;
             nonce_occurrence_identity = occurrence; nonce_identity = nonce;
             nonce_transition_ordinal = 0; nonce_state_value = Available;
             nonce_request_digest = request;
             nonce_verification_digest = verification;
             nonce_session_digest = key.approval_key_session;
             nonce_store_epoch = key.approval_key_epoch;
             nonce_time_digest = time;
             nonce_transition_id =
               sha256 [ "authority-approval-nonce-transition-v1";
                        registration; string_of_int ordinal; occurrence;
                        nonce; "0"; "available" ] })
        occurrences
    in
    Ok { prepared_campaign_key = key; prepared_campaign_row = campaign;
         prepared_nonce_rows = nonces; prepared_campaign_time = observed_at }

let closed_campaign (row : approval_campaign_row) : Closed.authority_store_campaign =
  { authority_campaign_key = row.campaign_key_digest;
    authority_campaign_approval_identity = row.campaign_approval_identity;
    authority_campaign_plan_digest = row.campaign_plan_digest;
    authority_campaign_request_digest = row.campaign_request_digest;
    authority_campaign_verification_digest = row.campaign_verification_digest;
    authority_campaign_denominator_digest = row.campaign_denominator_digest;
    authority_campaign_occurrence_count = row.campaign_occurrence_count;
    authority_campaign_session = row.campaign_session_digest;
    authority_campaign_epoch = row.campaign_store_epoch;
    authority_campaign_time_digest = row.campaign_time_digest;
    authority_campaign_registration_id = row.campaign_registration_id }

let campaign_of_closed (row : Closed.authority_store_campaign) =
  { campaign_key_digest = row.authority_campaign_key;
    campaign_approval_identity = row.authority_campaign_approval_identity;
    campaign_plan_digest = row.authority_campaign_plan_digest;
    campaign_request_digest = row.authority_campaign_request_digest;
    campaign_verification_digest = row.authority_campaign_verification_digest;
    campaign_denominator_digest = row.authority_campaign_denominator_digest;
    campaign_occurrence_count = row.authority_campaign_occurrence_count;
    campaign_session_digest = row.authority_campaign_session;
    campaign_store_epoch = row.authority_campaign_epoch;
    campaign_time_digest = row.authority_campaign_time_digest;
    campaign_registration_id = row.authority_campaign_registration_id }

let read_campaign_row ?scope database key =
  let* row = execute ?scope database (Closed.Authority_store_read_campaign key) in
  Ok (Option.map campaign_of_closed row)

let closed_nonce (row : approval_nonce_row) : Closed.authority_store_nonce =
  { authority_nonce_key = row.nonce_key_digest;
    authority_nonce_occurrence_ordinal = row.nonce_occurrence_ordinal;
    authority_nonce_occurrence_identity = row.nonce_occurrence_identity;
    authority_nonce_identity = row.nonce_identity;
    authority_nonce_transition_ordinal = row.nonce_transition_ordinal;
    authority_nonce_state = approval_nonce_state_name row.nonce_state_value;
    authority_nonce_request_digest = row.nonce_request_digest;
    authority_nonce_verification_digest = row.nonce_verification_digest;
    authority_nonce_session = row.nonce_session_digest;
    authority_nonce_epoch = row.nonce_store_epoch;
    authority_nonce_time_digest = row.nonce_time_digest;
    authority_nonce_transition_id = row.nonce_transition_id }

let nonce_of_closed (row : Closed.authority_store_nonce) =
  let* nonce_state_value = approval_nonce_state_of_name row.authority_nonce_state in
  Ok { nonce_key_digest = row.authority_nonce_key;
       nonce_occurrence_ordinal = row.authority_nonce_occurrence_ordinal;
       nonce_occurrence_identity = row.authority_nonce_occurrence_identity;
       nonce_identity = row.authority_nonce_identity;
       nonce_transition_ordinal = row.authority_nonce_transition_ordinal;
       nonce_state_value; nonce_request_digest = row.authority_nonce_request_digest;
       nonce_verification_digest = row.authority_nonce_verification_digest;
       nonce_session_digest = row.authority_nonce_session;
       nonce_store_epoch = row.authority_nonce_epoch;
       nonce_time_digest = row.authority_nonce_time_digest;
       nonce_transition_id = row.authority_nonce_transition_id }

let nonce_rows_of_closed rows =
  let rec loop values = function
    | [] -> Ok (List.rev values)
    | row :: rest -> let* row = nonce_of_closed row in loop (row :: values) rest
  in loop [] rows

let read_nonce_rows ?scope database key =
  let* rows = execute ?scope database (Closed.Authority_store_read_nonces key) in
  nonce_rows_of_closed rows

let insert_campaign_row ~scope database row =
  execute ~scope database (Closed.Authority_store_insert_campaign (closed_campaign row))

let insert_nonce_row ~scope database row =
  execute ~scope database (Closed.Authority_store_insert_nonce (closed_nonce row))

let campaign_receipt store key row nonces replayed =
  { campaign_receipt_store = store; campaign_receipt_key = key;
    campaign_receipt_row = row; campaign_receipt_nonces = nonces;
    campaign_receipt_digest_value =
      sha256 [ "authority-approval-campaign-receipt-v1";
               row.campaign_registration_id ];
    campaign_receipt_was_replayed = replayed }

let register_approval_campaign_once capability prepared =
  let key = prepared.prepared_campaign_key in
  let row = prepared.prepared_campaign_row in
  let* store = validate_approval_key capability key in
  let* receipt = transaction store.database (fun scope ->
      let* existing =
        read_campaign_row ~scope store.database row.campaign_key_digest
      in
      match existing with
      | Some existing ->
          let* nonces =
            read_nonce_rows ~scope store.database row.campaign_key_digest
          in
          if existing = row && nonces = prepared.prepared_nonce_rows
          then Ok (campaign_receipt store key existing nonces true)
          else Error (diagnostic Request_conflict)
      | None ->
          let* () = insert_campaign_row ~scope store.database row in
          let rec insert = function
            | [] -> Ok ()
            | nonce :: rest ->
                let* () = insert_nonce_row ~scope store.database nonce in
                insert rest
          in
          let* () = insert prepared.prepared_nonce_rows in
          Ok (campaign_receipt store key row prepared.prepared_nonce_rows false))
  in
  remember_clock store prepared.prepared_campaign_time;
  Ok receipt

let approval_campaign_receipt_digest receipt = receipt.campaign_receipt_digest_value
let approval_campaign_occurrence_count receipt = receipt.campaign_receipt_row.campaign_occurrence_count
let approval_campaign_replayed receipt = receipt.campaign_receipt_was_replayed

let approval_occurrence_nonce receipt ~occurrence =
  let Approval_occurrence (identity, nonce) = occurrence in
  let identity = Digest.to_hex identity and nonce = Digest.to_hex nonce in
  match List.find_opt
    (fun row -> String.equal row.nonce_occurrence_identity identity
                && String.equal row.nonce_identity nonce)
    receipt.campaign_receipt_nonces
  with
  | None -> Error (diagnostic Missing_approval_nonce)
  | Some row ->
      Ok { occurrence_nonce_store = receipt.campaign_receipt_store;
           occurrence_nonce_epoch = row.nonce_store_epoch;
           occurrence_nonce_session = row.nonce_session_digest;
           occurrence_nonce_key = row.nonce_key_digest;
           occurrence_nonce_identity = row.nonce_identity;
           occurrence_nonce_occurrence = row.nonce_occurrence_identity }

let read_current_nonce_row database nonce =
  let* row =
    execute database
      (Closed.Authority_store_read_current_nonce
         { authority_nonce_lookup_key = nonce.occurrence_nonce_key;
           authority_nonce_lookup_identity = nonce.occurrence_nonce_identity })
  in
  match row with
  | None -> Ok None
  | Some row -> let* row = nonce_of_closed row in Ok (Some row)

let validate_occurrence_nonce capability nonce =
  let store = capability.approval_nonce_store in
  let* () = check_active store capability.approval_nonce_session in
  if store != nonce.occurrence_nonce_store
     || not (String.equal store.store_epoch nonce.occurrence_nonce_epoch)
     || not (String.equal store.session_digest nonce.occurrence_nonce_session)
  then Error (diagnostic Role_wrong_session) else Ok store

let nonce_readback_digest store row =
  sha256 [ "authority-approval-nonce-readback-v1"; store.store_epoch;
           store.session_digest; row.nonce_key_digest; row.nonce_identity;
           row.nonce_occurrence_identity;
           string_of_int row.nonce_transition_ordinal;
           approval_nonce_state_name row.nonce_state_value;
           row.nonce_transition_id; row.nonce_time_digest ]

let read_approval_nonce capability nonce =
  let* store = validate_occurrence_nonce capability nonce in
  let* row = read_current_nonce_row store.database nonce in
  match row with
  | None -> Error (diagnostic Missing_approval_nonce)
  | Some row when not (String.equal row.nonce_occurrence_identity
                         nonce.occurrence_nonce_occurrence) ->
      Error (diagnostic Missing_approval_nonce)
  | Some row ->
      begin match find_clock store row.nonce_time_digest with
      | None -> Error (diagnostic Currentness_unavailable)
      | Some nonce_readback_time ->
          Ok { nonce_readback_store = store; nonce_readback_nonce = nonce;
               nonce_readback_row = row; nonce_readback_time;
               nonce_readback_digest_value = nonce_readback_digest store row }
      end

let approval_nonce_readback_state readback = readback.nonce_readback_row.nonce_state_value
let approval_nonce_readback_digest readback = readback.nonce_readback_digest_value

let reconcile_approval_nonce_current capability ~now readback =
  let* store = validate_occurrence_nonce capability readback.nonce_readback_nonce in
  if store != readback.nonce_readback_store then Error (diagnostic Role_wrong_session)
  else match Dependability_clock.validate_current ~now readback.nonce_readback_time with
    | Error _ -> Error (diagnostic Currentness_unavailable)
    | Ok () ->
        let* fresh = read_approval_nonce capability readback.nonce_readback_nonce in
        if not (String.equal fresh.nonce_readback_digest_value
                  readback.nonce_readback_digest_value)
        then Error (diagnostic Stale_generation)
        else Ok { nonce_current_row = fresh.nonce_readback_row;
                  nonce_current_digest_value =
                    sha256 [ "authority-approval-nonce-current-v1";
                             fresh.nonce_readback_digest_value;
                             Dependability_clock.digest now ] }

let approval_nonce_current_state current = current.nonce_current_row.nonce_state_value
let approval_nonce_current_digest current = current.nonce_current_digest_value

type approval_campaign_inventory_readback = {
  approval_inventory_readback_store : store;
  approval_inventory_readback_campaign_digest : string;
  approval_inventory_readback_campaign_key : string;
  approval_inventory_readback_campaign_row : approval_campaign_row;
  approval_inventory_readback_history : approval_nonce_row list;
  approval_inventory_readback_current : approval_nonce_row list;
  approval_inventory_readback_times : Dependability_clock.receipt list;
  approval_inventory_readback_digest_value : string;
}

type approval_inventory_current = {
  approval_inventory_current_digest_value : string;
  approval_inventory_current_nonce_count : int;
}

type approval_inventory_terminal_prerequisite =
  | Campaign_open_current
  | Conditional_decision_terminal_evidence
  | Abandonment_terminal_evidence

type global_approval_inventory_prerequisite =
  | Closed_approval_campaign_inventory

let approval_inventory_terminal_prerequisites =
  [ Campaign_open_current; Conditional_decision_terminal_evidence;
    Abandonment_terminal_evidence ]

let approval_inventory_terminal_posture = `Implemented_unavailable

let global_approval_inventory_prerequisites =
  [ Closed_approval_campaign_inventory ]

let global_approval_inventory_posture = `Implemented_unavailable

let canonical_digest value = Result.is_ok (Digest.make value)

let nonce_identity_equal left right =
  left.nonce_occurrence_ordinal = right.nonce_occurrence_ordinal
  && String.equal left.nonce_occurrence_identity
       right.nonce_occurrence_identity
  && String.equal left.nonce_identity right.nonce_identity

let nonce_immutable_fields_equal initial row =
  String.equal initial.nonce_key_digest row.nonce_key_digest
  && nonce_identity_equal initial row
  && String.equal initial.nonce_request_digest row.nonce_request_digest
  && String.equal initial.nonce_verification_digest
       row.nonce_verification_digest
  && String.equal initial.nonce_session_digest row.nonce_session_digest
  && String.equal initial.nonce_store_epoch row.nonce_store_epoch

let canonical_nonce_row row =
  row.nonce_occurrence_ordinal >= 0
  && row.nonce_transition_ordinal >= 0
  && List.for_all canonical_digest
       [ row.nonce_key_digest; row.nonce_occurrence_identity;
         row.nonce_identity; row.nonce_request_digest;
         row.nonce_verification_digest; row.nonce_session_digest;
         row.nonce_store_epoch; row.nonce_time_digest;
         row.nonce_transition_id ]

let approval_inventory_digest_of store campaign history current =
  let nonce_fields row =
    [ string_of_int row.nonce_occurrence_ordinal;
      row.nonce_occurrence_identity; row.nonce_identity;
      string_of_int row.nonce_transition_ordinal;
      approval_nonce_state_name row.nonce_state_value;
      row.nonce_request_digest; row.nonce_verification_digest;
      row.nonce_session_digest; row.nonce_store_epoch;
      row.nonce_time_digest; row.nonce_transition_id ]
  in
  sha256
    ([ "authority-approval-campaign-inventory-readback-v1";
       store.store_epoch; store.session_digest;
       campaign.campaign_key_digest; campaign.campaign_registration_id;
       campaign.campaign_denominator_digest;
       string_of_int campaign.campaign_occurrence_count;
       "history" ]
     @ List.concat_map nonce_fields history
     @ [ "current" ]
     @ List.concat_map nonce_fields current)

let validate_campaign_receipt capability campaign =
  let store = capability.approval_nonce_store in
  let* () = check_active store capability.approval_nonce_session in
  let key = campaign.campaign_receipt_key in
  let row = campaign.campaign_receipt_row in
  if store != campaign.campaign_receipt_store
     || store != key.approval_key_store
     || not (String.equal store.store_epoch key.approval_key_epoch)
     || not (String.equal store.session_digest key.approval_key_session)
     || not (String.equal row.campaign_key_digest key.approval_key_digest)
     || not (String.equal row.campaign_store_epoch store.store_epoch)
     || not (String.equal row.campaign_session_digest store.session_digest)
  then Error (diagnostic Approval_inventory_mismatch)
  else Ok (store, row)

let read_approval_campaign_inventory capability ~campaign =
  let* store, expected_campaign =
    validate_campaign_receipt capability campaign
  in
  let* stored_campaign =
    read_campaign_row store.database expected_campaign.campaign_key_digest
  in
  let* stored_campaign =
    match stored_campaign with
    | Some row when row = expected_campaign -> Ok row
    | Some _ | None -> Error (diagnostic Approval_inventory_mismatch)
  in
  let initial = campaign.campaign_receipt_nonces in
  if List.length initial <> stored_campaign.campaign_occurrence_count
     || not
          (List.mapi
             (fun ordinal row -> row.nonce_occurrence_ordinal = ordinal)
             initial
           |> List.for_all Fun.id)
     || List.exists (fun row -> not (canonical_nonce_row row)) initial
     || List.length initial
        <> List.length
             (List.sort_uniq
                (fun left right ->
                  compare
                    (left.nonce_occurrence_ordinal, left.nonce_occurrence_identity,
                     left.nonce_identity)
                    (right.nonce_occurrence_ordinal,
                     right.nonce_occurrence_identity, right.nonce_identity))
                initial)
  then Error (diagnostic Approval_inventory_mismatch)
  else
    let* history =
      read_nonce_rows store.database stored_campaign.campaign_key_digest
    in
    let rec read_currents currents times = function
      | [] -> Ok (List.rev currents, List.rev times)
      | expected :: rest ->
          let transitions =
            List.filter (nonce_identity_equal expected) history
          in
          let contiguous =
            List.mapi
              (fun ordinal row -> row.nonce_transition_ordinal = ordinal)
              transitions
            |> List.for_all Fun.id
          in
          if transitions = [] || not contiguous
             || List.exists
                  (fun row ->
                    not (canonical_nonce_row row)
                    || not (nonce_immutable_fields_equal expected row))
                  transitions
          then Error (diagnostic Approval_inventory_mismatch)
          else
            let nonce =
              { occurrence_nonce_store = store;
                occurrence_nonce_epoch = expected.nonce_store_epoch;
                occurrence_nonce_session = expected.nonce_session_digest;
                occurrence_nonce_key = expected.nonce_key_digest;
                occurrence_nonce_identity = expected.nonce_identity;
                occurrence_nonce_occurrence =
                  expected.nonce_occurrence_identity }
            in
            let* current = read_current_nonce_row store.database nonce in
            begin match current, List.rev transitions with
            | Some current, latest :: _ when current = latest ->
                begin match find_clock store current.nonce_time_digest with
                | None -> Error (diagnostic Currentness_unavailable)
                | Some time ->
                    read_currents (current :: currents) (time :: times) rest
                end
            | Some _, _ | None, _ ->
                Error (diagnostic Approval_inventory_mismatch)
            end
    in
    let* current, times = read_currents [] [] initial in
    if List.length history
       <> List.fold_left
            (fun count expected ->
              count
              + List.length (List.filter (nonce_identity_equal expected) history))
            0 initial
    then Error (diagnostic Approval_inventory_mismatch)
    else
      Ok
        { approval_inventory_readback_store = store;
          approval_inventory_readback_campaign_digest =
            campaign.campaign_receipt_digest_value;
          approval_inventory_readback_campaign_key =
            stored_campaign.campaign_key_digest;
          approval_inventory_readback_campaign_row = stored_campaign;
          approval_inventory_readback_history = history;
          approval_inventory_readback_current = current;
          approval_inventory_readback_times = times;
          approval_inventory_readback_digest_value =
            approval_inventory_digest_of store stored_campaign history current }

let approval_campaign_inventory_readback_digest readback =
  readback.approval_inventory_readback_digest_value

let approval_campaign_inventory_readback_nonce_count readback =
  List.length readback.approval_inventory_readback_current

let reconcile_approval_campaign_inventory_current capability ~now ~campaign
    readback =
  let* store, campaign_row = validate_campaign_receipt capability campaign in
  if store != readback.approval_inventory_readback_store
     || not
          (String.equal campaign.campaign_receipt_digest_value
             readback.approval_inventory_readback_campaign_digest)
     || not
          (String.equal campaign_row.campaign_key_digest
             readback.approval_inventory_readback_campaign_key)
  then Error (diagnostic Approval_inventory_mismatch)
  else
    let rec validate_clocks = function
      | [] -> Ok ()
      | observed :: rest ->
          begin match Dependability_clock.validate_current ~now observed with
          | Error _ -> Error (diagnostic Currentness_unavailable)
          | Ok () -> validate_clocks rest
          end
    in
    let* () = validate_clocks readback.approval_inventory_readback_times in
    let* fresh = read_approval_campaign_inventory capability ~campaign in
    if not
         (String.equal fresh.approval_inventory_readback_digest_value
            readback.approval_inventory_readback_digest_value)
       || fresh.approval_inventory_readback_history
          <> readback.approval_inventory_readback_history
       || fresh.approval_inventory_readback_current
          <> readback.approval_inventory_readback_current
    then Error (diagnostic Approval_inventory_mismatch)
    else
      Ok
        { approval_inventory_current_digest_value =
            sha256
              [ "authority-approval-campaign-inventory-current-v1";
                fresh.approval_inventory_readback_digest_value ];
          approval_inventory_current_nonce_count =
            List.length fresh.approval_inventory_readback_current }

let approval_inventory_digest inventory =
  inventory.approval_inventory_current_digest_value

let approval_inventory_campaign_count _inventory = 1

let approval_inventory_nonce_count inventory =
  inventory.approval_inventory_current_nonce_count

let read_status capability key =
  let* store = validate_key capability key in
  let* pointer = read_pointer store.database key.key_digest_value in
  match pointer with
  | None -> Error (diagnostic Missing_activation)
  | Some (generation, ordinal) ->
      let* row =
        read_transition store.database key.key_digest_value generation ordinal
      in
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

let prepare_next expected_status next_status next_ordinal predecessor request
    evidence context observed_at =
  if predecessor.readback_row.status <> expected_status
     || predecessor.readback_row.ordinal + 1 <> next_ordinal
  then Error (diagnostic Invalid_state_transition)
  else
    let* () = validate_time observed_at in
    let row =
      make_row ~key:predecessor.readback_key
        ~generation:predecessor.readback_row.generation ~ordinal:next_ordinal
        ~status:next_status ~request ~evidence ~context ~observed_at
    in
    Ok (row, predecessor.readback_digest_value)

let prepare_root_activation ~predecessor ~request ~context ~observed_at =
  let root_evidence =
    match Digest.make predecessor.readback_store.bootstrap.bootstrap_digest_value with
    | Ok digest -> digest
    | Error _ -> assert false
  in
  let* row, predecessor_digest =
    prepare_next Missing Root_active 1 predecessor request root_evidence context
      observed_at
  in
  Ok
    { root_key = predecessor.readback_key;
      root_predecessor_digest = predecessor_digest; root_row = row;
      root_time = observed_at }

let prepare_classification ~predecessor ~request ~evidence ~context ~observed_at =
  let* row, predecessor_digest =
    prepare_next Root_active Classified_active 2 predecessor request evidence
      context observed_at
  in
  Ok
    { classification_key = predecessor.readback_key;
      classification_predecessor_digest = predecessor_digest;
      classification_row = row; classification_time = observed_at }

let update_pointer ~scope database row expected_ordinal =
  let* changed =
    execute ~scope database
      (Closed.Authority_store_pointer_cas
         { authority_pointer_cas_key = row.key_digest;
           authority_pointer_cas_generation = row.generation;
           authority_pointer_expected_ordinal = expected_ordinal;
           authority_pointer_replacement_ordinal = row.ordinal })
  in
  if changed then Ok () else Error (diagnostic Stale_generation)

let apply_next store predecessor_digest row =
  transaction store.database (fun scope ->
      let* existing =
        read_transition ~scope store.database row.key_digest row.generation
          row.ordinal
      in
      match existing with
      | Some existing when row_equal existing row ->
          Ok (transition_receipt existing true)
      | Some _ -> Error (diagnostic Request_conflict)
      | None ->
          let previous_ordinal = row.ordinal - 1 in
          let* previous =
            read_transition ~scope store.database row.key_digest row.generation
              previous_ordinal
          in
          begin match previous with
          | None -> Error (diagnostic Stale_generation)
          | Some previous
            when not
              (String.equal (readback_digest_of_row store previous)
                 predecessor_digest) ->
              Error (diagnostic Stale_generation)
          | Some _ ->
              let* pointer = read_pointer ~scope store.database row.key_digest in
              begin match pointer with
              | Some (generation, ordinal)
                when generation = row.generation
                     && ordinal = previous_ordinal ->
                  let* () = insert_transition ~scope store.database row in
                  let* () =
                    update_pointer ~scope store.database row previous_ordinal
                  in
                  Ok (transition_receipt row false)
              | Some _ | None -> Error (diagnostic Stale_generation)
              end
          end)

let activate_root_once capability prepared =
  let* store = validate_key capability prepared.root_key in
  let* receipt =
    apply_next store prepared.root_predecessor_digest prepared.root_row
  in
  remember_clock store prepared.root_time;
  Ok receipt

let classify_once capability prepared =
  let* store = validate_key capability prepared.classification_key in
  let* receipt =
    apply_next store prepared.classification_predecessor_digest
      prepared.classification_row
  in
  remember_clock store prepared.classification_time;
  Ok receipt

let transition_status receipt = receipt.transition_row.status
let transition_generation receipt = receipt.transition_row.generation
let transition_id receipt = receipt.transition_digest_value
let transition_replayed receipt = receipt.transition_was_replayed
let readback_status readback = readback.readback_row.status
let readback_generation readback = readback.readback_row.generation
let readback_digest readback = readback.readback_digest_value

let reconcile_current capability ~now readback =
  let* store = validate_key capability readback.readback_key in
  if store != readback.readback_store then
    Error (diagnostic Role_wrong_session)
  else
    begin match
      Dependability_clock.validate_current ~now readback.readback_time
    with
    | Error _ -> Error (diagnostic Currentness_unavailable)
    | Ok () ->
        let* fresh = read_status capability readback.readback_key in
        if not (String.equal fresh.readback_digest_value
                  readback.readback_digest_value)
        then Error (diagnostic Stale_generation)
        else
          Ok
            { current_row = fresh.readback_row;
              current_digest_value =
                sha256
                  [ "authority-activation-current-v1";
                    fresh.readback_digest_value;
                    Dependability_clock.digest now ] }
    end

let current_status current = current.current_row.status
let current_generation current = current.current_row.generation
let current_digest current = current.current_digest_value

let all_transition_ids database =
  execute database Closed.Authority_store_inventory_ids

let inventory_identity value =
  match Dependability_owner_inventory.Identity.make value with
  | Ok identity -> Ok identity
  | Error _ -> Error (diagnostic Inventory_unavailable)

let prepare_activation_inventory capability ~manifest ~recovery_attempt
    ~challenge ~transition =
  let store = capability.activation_store in
  let* () = check_active store capability.activation_session in
  let* transition_ids = all_transition_ids store.database in
  if transition_ids = [] then Error (diagnostic Inventory_unavailable)
  else
    let* owner_session =
      inventory_identity ("session-" ^ store.session_digest)
    in
    let* context =
      match
        Dependability_owner_inventory.make_context ~manifest ~owner_session
          ~recovery_attempt ~challenge ~transition
      with
      | Ok context -> Ok context
      | Error _ -> Error (diagnostic Inventory_unavailable)
    in
    let rec identities acc = function
      | [] -> Ok (List.rev acc)
      | value :: remaining ->
          let* identity = inventory_identity ("activation-" ^ value) in
          identities (identity :: acc) remaining
    in
    let* rows = identities [] transition_ids in
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
        ("readback-" ^ sha256 ("activation-inventory-v1" :: transition_ids))
    in
    match
      Dependability_owner_inventory.prepare_fragment
        ~role:Dependability_owner_inventory.Activation ~context ~denominator
        ~owner_readback
    with
    | Ok fragment -> Ok fragment
    | Error _ -> Error (diagnostic Inventory_unavailable)

let owner_transition store ordinal state_name =
  let time_digest = Dependability_clock.digest store.bootstrap.observed_at in
  let transition_id =
    sha256
      [ "authority-owner-session-transition-v1"; store.store_epoch;
        store.session_digest; string_of_int store.session_generation;
        string_of_int ordinal; state_name;
        store.bootstrap.bootstrap_digest_value; time_digest ]
  in
  transaction store.database (fun scope ->
      let* () =
        execute ~scope store.database
          (Closed.Authority_store_insert_owner_transition
             { authority_owner_transition_generation = store.session_generation;
               authority_owner_transition_ordinal = ordinal;
               authority_owner_transition_state = state_name;
               authority_owner_transition_session = store.session_digest;
               authority_owner_transition_epoch = store.store_epoch;
               authority_owner_transition_bootstrap_digest =
                 store.bootstrap.bootstrap_digest_value;
               authority_owner_transition_time_digest = time_digest;
               authority_owner_transition_id = transition_id })
      in
      let* changed =
        execute ~scope store.database
          (Closed.Authority_store_owner_pointer_cas
             { authority_owner_cas_generation = store.session_generation;
               authority_owner_cas_expected_ordinal = ordinal - 1;
               authority_owner_cas_replacement_ordinal = ordinal;
               authority_owner_cas_state = state_name;
               authority_owner_cas_session = store.session_digest;
               authority_owner_cas_epoch = store.store_epoch })
      in
      if changed then Ok transition_id else Error (diagnostic Stale_generation))

let check_lifecycle_capability capability =
  let store = capability.lifecycle_store in
  if String.equal store.session_digest capability.lifecycle_session then Ok store
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
          drain_digest_value =
            sha256
              [ "authority-drain-receipt-v1"; store.store_epoch;
                store.session_digest; transition_id ];
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
            close_digest_value =
              sha256
                [ "authority-close-receipt-v1"; store.store_epoch;
                  store.session_digest; drain.drain_digest_value;
                  transition_id ];
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
    [ "dependability-authority-store-foundation-v1";
      "registered-production-refuses-without-exclusive-physical-lock";
      "eight-distinct-one-shot-role-transfers";
      "session-and-store-epoch-fenced";
      "append-only-missing-root-classified-transitions";
      "same-request-replay-different-request-conflict";
      "transactional-pointer-cas";
      "bounded-clock-currentness-readback";
      "owner-derived-prepared-inventory-no-seal-forge";
      "one-shot-four-way-peer-operational-open-fences";
      "recovery-inventory-fences-remain-unconstructible";
      "atomic-absent-to-available-approval-nonce-denominator";
      "approval-nonce-replay-conflict-readback-currentness";
      "terminal-nonce-transitions-remain-unavailable";
      "owner-derived-per-campaign-current-nonce-inventory";
      "approval-inventory-current-pointer-clock-reread";
      "approval-inventory-cross-campaign-and-change-refusal";
      "global-approval-inventory-unavailable-without-closed-enumeration";
      "drain-retire-close-replay" ]

module For_test = struct
  type mutation =
    | Drop_role_separation
    | Permit_production_without_lock
    | Drop_session_fence
    | Overwrite_transition
    | Drop_request_replay_check
    | Drop_pointer_cas
    | Skip_current_readback
    | Forge_inventory_current
    | Duplicate_peer_open
    | Forge_inventory_fence
    | Partial_nonce_denominator
    | Overwrite_nonce_state
    | Reopen_terminal_nonce
    | Forge_approval_inventory_current
    | Skip_approval_inventory_readback
    | Permit_global_inventory_without_closed_enumeration

  let mutation_name = function
    | Drop_role_separation -> "drop-role-separation"
    | Permit_production_without_lock -> "permit-production-without-lock"
    | Drop_session_fence -> "drop-session-fence"
    | Overwrite_transition -> "overwrite-transition"
    | Drop_request_replay_check -> "drop-request-replay-check"
    | Drop_pointer_cas -> "drop-pointer-cas"
    | Skip_current_readback -> "skip-current-readback"
    | Forge_inventory_current -> "forge-inventory-current"
    | Duplicate_peer_open -> "duplicate-peer-open"
    | Forge_inventory_fence -> "forge-inventory-fence"
    | Partial_nonce_denominator -> "partial-nonce-denominator"
    | Overwrite_nonce_state -> "overwrite-nonce-state"
    | Reopen_terminal_nonce -> "reopen-terminal-nonce"
    | Forge_approval_inventory_current -> "forge-approval-inventory-current"
    | Skip_approval_inventory_readback -> "skip-approval-inventory-readback"
    | Permit_global_inventory_without_closed_enumeration ->
        "permit-global-inventory-without-closed-enumeration"

  let source_digest_with_mutation mutation =
    sha256
      [ "dependability-authority-store-foundation-v1";
        mutation_name mutation ]

  type approval_inventory_readback_mutation = Current_nonce_identity

  let mutate_approval_inventory_readback Current_nonce_identity readback =
    let mutate_digest digest =
      let replacement = if digest.[0] = '0' then '1' else '0' in
      String.make 1 replacement ^ String.sub digest 1 (String.length digest - 1)
    in
    let current =
      match readback.approval_inventory_readback_current with
      | [] -> []
      | first :: rest ->
          { first with
            nonce_identity = mutate_digest first.nonce_identity }
          :: rest
    in
    { readback with
      approval_inventory_readback_current = current;
      approval_inventory_readback_digest_value =
        approval_inventory_digest_of
          readback.approval_inventory_readback_store
          readback.approval_inventory_readback_campaign_row
          readback.approval_inventory_readback_history current }
end
