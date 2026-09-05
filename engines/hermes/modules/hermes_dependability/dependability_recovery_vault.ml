type rca_origin =
  | Specification
  | Implementation
  | Environment
  | Evidence
  | Control

type diagnostic_kind =
  | Invalid_clock
  | Invalid_inventory_context
  | Invalid_object_metadata
  | Invalid_object_size
  | Incomplete_sealed_set
  | Duplicate_sealed_object
  | Unbounded_sealed_set
  | Filesystem_backend_unavailable
  | Request_conflict
  | Invalid_transition
  | Indeterminate_effect
  | Reconciliation_mismatch
  | Terminal_state
  | Inventory_preparation_failed

type diagnostic = {
  kind : diagnostic_kind;
  coordinate : string;
  origin : rca_origin;
}

let diagnostic_code diagnostic =
  match diagnostic.kind with
  | Invalid_clock -> "invalid-clock"
  | Invalid_inventory_context -> "invalid-inventory-context"
  | Invalid_object_metadata -> "invalid-object-metadata"
  | Invalid_object_size -> "invalid-object-size"
  | Incomplete_sealed_set -> "incomplete-sealed-set"
  | Duplicate_sealed_object -> "duplicate-sealed-object"
  | Unbounded_sealed_set -> "unbounded-sealed-set"
  | Filesystem_backend_unavailable -> "filesystem-backend-unavailable"
  | Request_conflict -> "request-conflict"
  | Invalid_transition -> "invalid-transition"
  | Indeterminate_effect -> "indeterminate-effect"
  | Reconciliation_mismatch -> "reconciliation-mismatch"
  | Terminal_state -> "terminal-state"
  | Inventory_preparation_failed -> "inventory-preparation-failed"

let diagnostic_coordinate diagnostic = diagnostic.coordinate
let diagnostic_origin diagnostic = diagnostic.origin

let diagnostic ?(origin = Control) kind =
  { kind; coordinate = "L5/recovery-vault"; origin }

let length_frame fields =
  fields
  |> List.map (fun field -> Printf.sprintf "%d:%s" (String.length field) field)
  |> String.concat ""

let sha256 fields =
  fields |> length_frame |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

type b_success = |
type completion_record = |

type _ purpose =
  | B_success : b_success purpose
  | Completion_record : completion_record purpose

type packed_purpose = Pack_purpose : 'purpose purpose -> packed_purpose

let purpose_key : type p. p purpose -> string = function
  | B_success -> "b-success"
  | Completion_record -> "completion-record"

let purpose_id (Pack_purpose purpose) = purpose_key purpose

type context = {
  inventory_context : Dependability_owner_inventory.context;
  observed_at : Dependability_clock.receipt;
  digest : string;
}

type current_context = { context : context; digest : string }

let owner_identity value =
  match Dependability_owner_inventory.Identity.make value with
  | Ok identity -> Ok identity
  | Error _ -> Error (diagnostic Invalid_inventory_context)

let prepare_context ~manifest ~authority ~recovery_attempt ~challenge
    ~transition ~observed_at =
  match Dependability_clock.validate observed_at with
  | Error _ -> Error (diagnostic ~origin:Evidence Invalid_clock)
  | Ok () ->
      let manifest_text = Jj_id.Receipt.to_string manifest in
      let owner_session_text =
        Dependability_authority_store.owner_session_digest authority
      in
      let attempt_text = Jj_id.Request.to_string recovery_attempt in
      let challenge_text = Jj_id.Receipt.to_string challenge in
      let transition_text =
        Jj_id.Receipt.to_string transition
      in
      (match
         ( owner_identity manifest_text,
           owner_identity owner_session_text,
           owner_identity attempt_text,
           owner_identity challenge_text,
           owner_identity transition_text )
       with
       | Ok manifest, Ok owner_session, Ok recovery_attempt, Ok challenge,
         Ok transition ->
           (match
              Dependability_owner_inventory.make_context ~manifest
                ~owner_session ~recovery_attempt ~challenge ~transition
            with
            | Error _ -> Error (diagnostic Invalid_inventory_context)
            | Ok inventory_context ->
                let digest =
                  sha256
                    [ "dependability-recovery-vault-context-v1";
                      manifest_text; owner_session_text; attempt_text;
                      challenge_text; transition_text;
                      Dependability_clock.digest observed_at;
                      Jj_source_manifest.source_digest;
                      Jj_recovery_schema.source_digest ]
                in
                Ok { inventory_context; observed_at; digest })
       | _ -> Error (diagnostic Invalid_inventory_context))

let context_digest (context : context) = context.digest

let validate_context_current ~now context =
  match Dependability_clock.validate_current ~now context.observed_at with
  | Error _ -> Error (diagnostic ~origin:Evidence Invalid_clock)
  | Ok () ->
      Ok
        { context;
          digest =
            sha256
              [ "dependability-recovery-vault-current-context-v1";
                context.digest; Dependability_clock.digest now ] }

let current_context_digest (context : current_context) = context.digest

type anchors = {
  operation : Jj_id.Operation.t;
  workspace : Jj_id.Workspace.t;
  source : Jj_id.Receipt.t;
  digest : string;
}

let prepare_anchors ~operation ~workspace ~source =
  { operation; workspace; source;
    digest =
      sha256
        [ "dependability-recovery-vault-anchors-v1";
          Jj_id.Operation.to_string operation;
          Jj_id.Workspace.to_string workspace;
          Jj_id.Receipt.to_string source ] }

type object_role = Original | Candidate | Remainder

let object_role_id = function
  | Original -> "original"
  | Candidate -> "candidate"
  | Remainder -> "remainder"

let role_ordinal = function Original -> 0 | Candidate -> 1 | Remainder -> 2

type object_state =
  | Absent
  | Present of {
      mode : Jj_split_manifest.file_mode;
      size_bytes : int;
      content_digest : Jj_split_manifest.Digest.t;
      symlink_target_digest : Jj_split_manifest.Digest.t option;
    }

type sealed_object = {
  role : object_role;
  locator : Jj_id.Receipt.t;
  state : object_state;
  digest : string;
}

let max_object_size_bytes = 1_073_741_824

let mode_key = function
  | Jj_split_manifest.Regular -> "regular"
  | Jj_split_manifest.Executable -> "executable"
  | Jj_split_manifest.Symlink -> "symlink"

let seal_absent ?(role = Original) ~locator () =
  if role <> Original then Error (diagnostic Invalid_object_metadata)
  else
    Ok
      { role; locator; state = Absent;
        digest =
          sha256
            [ "dependability-recovery-vault-object-v1";
              object_role_id role; Jj_id.Receipt.to_string locator; "absent" ] }

let seal_present ~role ~locator ~mode ~size_bytes ~content_digest
    ~symlink_target_digest =
  let content = Jj_split_manifest.Digest.to_string content_digest in
  let metadata_valid =
    match mode, symlink_target_digest with
    | Jj_split_manifest.Symlink, Some target ->
        String.equal content (Jj_split_manifest.Digest.to_string target)
    | (Jj_split_manifest.Regular | Jj_split_manifest.Executable), None -> true
    | _ -> false
  in
  if size_bytes < 0 || size_bytes > max_object_size_bytes then
    Error (diagnostic Invalid_object_size)
  else if not metadata_valid then Error (diagnostic Invalid_object_metadata)
  else
    let symlink =
      match symlink_target_digest with
      | None -> "none"
      | Some digest -> Jj_split_manifest.Digest.to_string digest
    in
    Ok
      { role; locator;
        state =
          Present { mode; size_bytes; content_digest; symlink_target_digest };
        digest =
          sha256
            [ "dependability-recovery-vault-object-v1";
              object_role_id role; Jj_id.Receipt.to_string locator; "present";
              mode_key mode; string_of_int size_bytes; content; symlink ] }

let sealed_object_digest (object_ : sealed_object) = object_.digest

type 'purpose prepared = {
  purpose : 'purpose purpose;
  context : current_context;
  anchors : anchors;
  objects : sealed_object list;
  entry_count : int;
  digest : string;
}

let max_entries = 256

let compare_object left right =
  let locator_compare =
    String.compare (Jj_id.Receipt.to_string left.locator)
      (Jj_id.Receipt.to_string right.locator)
  in
  if locator_compare <> 0 then locator_compare
  else Int.compare (role_ordinal left.role) (role_ordinal right.role)

let validate_objects objects =
  let sorted = List.sort compare_object objects in
  let rec loop current_locator roles entries = function
    | [] ->
        let complete = roles = [] || roles = [ Original; Candidate; Remainder ] in
        if not complete then Error (diagnostic Incomplete_sealed_set)
        else Ok (List.rev entries, if roles = [] then 0 else 1)
    | object_ :: rest ->
        let locator = Jj_id.Receipt.to_string object_.locator in
        (match current_locator with
         | None -> loop (Some locator) [ object_.role ] (object_ :: entries) rest
         | Some current when String.equal current locator ->
             if List.mem object_.role roles then
               Error (diagnostic Duplicate_sealed_object)
             else loop current_locator (roles @ [ object_.role ])
                    (object_ :: entries) rest
         | Some _ ->
             if roles <> [ Original; Candidate; Remainder ] then
               Error (diagnostic Incomplete_sealed_set)
             else
               (match loop (Some locator) [ object_.role ]
                        (object_ :: entries) rest with
                | Error _ as error -> error
                | Ok (entries, count) -> Ok (entries, count + 1)))
  in
  if objects = [] then Error (diagnostic Incomplete_sealed_set)
  else loop None [] [] sorted

let prepare ~purpose ~context ~anchors ~objects =
  match validate_objects objects with
  | Error _ as error -> error
  | Ok (objects, entry_count) ->
      if entry_count > max_entries then Error (diagnostic Unbounded_sealed_set)
      else
        Ok
          { purpose; context; anchors; objects; entry_count;
            digest =
              sha256
                ([ "dependability-recovery-vault-prepared-v1";
                   purpose_key purpose; context.digest; anchors.digest;
                   string_of_int entry_count ]
                @ List.map sealed_object_digest objects) }

let prepared_status (_ : 'purpose prepared) = `Prepared_nonauthorizing
let prepared_entry_count (prepared : 'purpose prepared) = prepared.entry_count
let prepared_digest (prepared : 'purpose prepared) = prepared.digest

type 'purpose operational_capability = string
type 'purpose recovery_capability = string
type lifecycle_capability = string
type effect_receipt = { effect_digest : string; effect_replayed : bool }

let unavailable () =
  Error
    (diagnostic ~origin:Environment Filesystem_backend_unavailable)

let open_operational ~purpose:_ ~context:_ = unavailable ()
let open_recovery ~purpose:_ ~context:_ = unavailable ()
let stage_once _ _ ~request:_ = unavailable ()
let restore_once _ _ ~request:_ = unavailable ()
let readback_once _ _ ~request:_ = unavailable ()
let cleanup_once _ _ ~request:_ = unavailable ()
let effect_receipt_digest (receipt : effect_receipt) = receipt.effect_digest
let effect_receipt_replayed (receipt : effect_receipt) = receipt.effect_replayed

type action = Stage | Restore | Readback | Cleanup

let action_id = function
  | Stage -> "stage"
  | Restore -> "restore"
  | Readback -> "readback"
  | Cleanup -> "cleanup"

type lifecycle_state =
  | Prepared
  | Staging
  | Staged
  | Restoring
  | Restored
  | Reading_back
  | Readback_verified
  | Cleaning
  | Cleaned
  | Indeterminate of action

let source_digest =
  sha256
    [ "dependability-recovery-vault-v1";
      "purpose-separated-b-success-completion-record";
      "sealed-original-candidate-remainder-content-identities";
      "manifest-session-transition-currentness";
      "stage-restore-readback-cleanup-prefix-machine";
      "reply-loss-reconciled-never-guessed";
      "prepared-inventory-only-no-producer-seal";
      "filesystem-backend-unavailable";
      "no-path-bytes-handle-upper-authority" ]

module For_test = struct
  type injected_outcome = Applied_exact | Reply_lost
  type lost_reply_resolution =
    | Applied_exact_on_readback
    | Not_applied_on_readback

  type transition_receipt = { digest : string; replayed : bool }

  type normal = {
    lifecycle : lifecycle_state;
    staged : int;
    restored : int;
    read_back : int;
    cleaned : int;
  }

  type recorded_outcome =
    | Recorded_applied
    | Recorded_lost
    | Recorded_resolved of {
        resolution : lost_reply_resolution;
        readback : string;
        resolution_digest : string;
      }

  type record = {
    request : string;
    action : action;
    evidence : string;
    item_digest : string;
    initial_digest : string;
    outcome : recorded_outcome;
  }

  type pending = {
    request : string;
    action : action;
    evidence : string;
    item_digest : string;
    prior : normal;
  }

  type 'purpose model = {
    prepared : 'purpose prepared;
    normal : normal;
    pending : pending option;
    records : record list;
  }

  let initial =
    { lifecycle = Prepared; staged = 0; restored = 0; read_back = 0;
      cleaned = 0 }

  let start prepared =
    { prepared; normal = initial; pending = None; records = [] }

  let state model =
    match model.pending with
    | None -> model.normal.lifecycle
    | Some pending -> Indeterminate pending.action

  let original_objects prepared =
    List.filter
      (fun (object_ : sealed_object) -> object_.role = Original)
      prepared.objects

  let action_total prepared = function
    | Stage | Cleanup -> List.length prepared.objects
    | Restore | Readback -> prepared.entry_count

  let action_completed normal = function
    | Stage -> normal.staged
    | Restore -> normal.restored
    | Readback -> normal.read_back
    | Cleanup -> normal.cleaned

  let active_action normal =
    match normal.lifecycle with
    | Prepared | Staging | Staged -> Some Stage
    | Restoring | Restored -> Some Restore
    | Reading_back | Readback_verified -> Some Readback
    | Cleaning | Cleaned -> Some Cleanup
    | Indeterminate _ -> None

  let completed model =
    let action =
      match model.pending with
      | Some pending -> pending.action
      | None ->
          (match active_action model.normal with
           | Some action -> action
           | None -> Stage)
    in
    action_completed model.normal action

  let total model =
    let action =
      match model.pending with
      | Some pending -> pending.action
      | None ->
          (match active_action model.normal with
           | Some action -> action
           | None -> Stage)
    in
    action_total model.prepared action

  let lifecycle_key = function
    | Prepared -> "prepared"
    | Staging -> "staging"
    | Staged -> "staged"
    | Restoring -> "restoring"
    | Restored -> "restored"
    | Reading_back -> "reading-back"
    | Readback_verified -> "readback-verified"
    | Cleaning -> "cleaning"
    | Cleaned -> "cleaned"
    | Indeterminate action -> "indeterminate-" ^ action_id action

  let resolution_key = function
    | Applied_exact_on_readback -> "applied-exact-on-readback"
    | Not_applied_on_readback -> "not-applied-on-readback"

  let recorded_outcome_fields = function
    | Recorded_applied -> [ "applied" ]
    | Recorded_lost -> [ "reply-lost" ]
    | Recorded_resolved { resolution; readback; resolution_digest } ->
        [ "resolved"; resolution_key resolution; readback; resolution_digest ]

  let record_digest (record : record) =
    sha256
      ([ "dependability-recovery-vault-record-v1"; record.request;
         action_id record.action; record.evidence; record.item_digest;
         record.initial_digest ]
      @ recorded_outcome_fields record.outcome)

  let model_digest model =
    let pending_fields =
      match model.pending with
      | None -> [ "no-pending" ]
      | Some pending ->
          [ "pending"; pending.request; action_id pending.action;
            pending.evidence; pending.item_digest ]
    in
    sha256
      ([ "dependability-recovery-vault-model-v1"; model.prepared.digest;
         lifecycle_key (state model); string_of_int model.normal.staged;
         string_of_int model.normal.restored;
         string_of_int model.normal.read_back;
         string_of_int model.normal.cleaned ]
      @ pending_fields @ List.map record_digest model.records)

  let check_current model now =
    match
      Dependability_clock.validate_current ~now
        model.prepared.context.context.observed_at
    with
    | Ok () -> Ok ()
    | Error _ -> Error (diagnostic ~origin:Evidence Invalid_clock)

  let expected_action normal =
    match normal.lifecycle with
    | Prepared | Staging -> Ok Stage
    | Staged | Restoring -> Ok Restore
    | Restored | Reading_back -> Ok Readback
    | Readback_verified | Cleaning -> Ok Cleanup
    | Cleaned -> Error (diagnostic Terminal_state)
    | Indeterminate _ -> Error (diagnostic Indeterminate_effect)

  let nth_digest (values : sealed_object list) index =
    match List.nth_opt values index with
    | Some object_ -> Ok object_.digest
    | None -> Error (diagnostic Invalid_transition)

  let item_digest prepared normal action =
    let values =
      match action with
      | Stage -> prepared.objects
      | Restore | Readback -> original_objects prepared
      | Cleanup -> List.rev prepared.objects
    in
    nth_digest values (action_completed normal action)

  let advance prepared normal action =
    match expected_action normal with
    | Error _ as error -> error
    | Ok expected when expected <> action ->
        Error (diagnostic Invalid_transition)
    | Ok _ ->
        let total = action_total prepared action in
        let next = action_completed normal action + 1 in
        if next > total then Error (diagnostic Invalid_transition)
        else
          match action with
          | Stage ->
              Ok
                { normal with staged = next;
                  lifecycle = if next = total then Staged else Staging }
          | Restore ->
              Ok
                { normal with restored = next;
                  lifecycle = if next = total then Restored else Restoring }
          | Readback ->
              Ok
                { normal with read_back = next;
                  lifecycle =
                    if next = total then Readback_verified else Reading_back }
          | Cleanup ->
              Ok
                { normal with cleaned = next;
                  lifecycle = if next = total then Cleaned else Cleaning }

  let find_record request (records : record list) =
    List.find_opt
      (fun (record : record) -> String.equal record.request request)
      records

  let same_initial (record : record) action evidence =
    record.action = action && String.equal record.evidence evidence

  let step model ~now ~request ~action ~evidence ~outcome =
    match check_current model now with
    | Error _ as error -> error
    | Ok () ->
        let request = Jj_id.Request.to_string request in
        let evidence = Jj_id.Receipt.to_string evidence in
        (match find_record request model.records with
         | Some record when same_initial record action evidence ->
             Ok (model, { digest = record.initial_digest; replayed = true })
         | Some _ -> Error (diagnostic Request_conflict)
         | None ->
             (match model.pending with
              | Some _ -> Error (diagnostic Indeterminate_effect)
              | None ->
                  (match expected_action model.normal with
                   | Error _ as error -> error
                   | Ok expected when expected <> action ->
                       Error (diagnostic Invalid_transition)
                   | Ok _ ->
                       (match item_digest model.prepared model.normal action with
                        | Error _ as error -> error
                        | Ok item_digest ->
                            let initial_digest =
                              sha256
                                [ "dependability-recovery-vault-transition-v1";
                                  model_digest model; request; action_id action;
                                  evidence; item_digest ]
                            in
                            let record outcome =
                              { request; action; evidence; item_digest;
                                initial_digest; outcome }
                            in
                            (match outcome with
                             | Applied_exact ->
                                 (match
                                    advance model.prepared model.normal action
                                  with
                                  | Error _ as error -> error
                                  | Ok normal ->
                                      Ok
                                        ( { model with normal;
                                            records =
                                              model.records
                                              @ [ record Recorded_applied ] },
                                          { digest = initial_digest;
                                            replayed = false } ))
                             | Reply_lost ->
                                 let pending =
                                   { request; action; evidence; item_digest;
                                     prior = model.normal }
                                 in
                                 Ok
                                   ( { model with pending = Some pending;
                                       records =
                                         model.records
                                         @ [ record Recorded_lost ] },
                                     { digest = initial_digest;
                                       replayed = false } ))))))

  let replace_record (replacement : record) (records : record list) =
    List.map
      (fun (record : record) ->
        if String.equal record.request replacement.request then replacement
        else record)
      records

  let reconcile_lost_reply model ~now ~request ~action ~readback ~resolution =
    match check_current model now with
    | Error _ as error -> error
    | Ok () ->
        let request = Jj_id.Request.to_string request in
        let readback = Jj_id.Receipt.to_string readback in
        (match find_record request model.records with
         | None -> Error (diagnostic Reconciliation_mismatch)
         | Some record when record.action <> action ->
             Error (diagnostic Request_conflict)
         | Some record ->
             (match record.outcome with
              | Recorded_applied ->
                  Error (diagnostic Reconciliation_mismatch)
              | Recorded_resolved resolved ->
                  if
                    resolved.resolution = resolution
                    && String.equal resolved.readback readback
                  then
                    Ok
                      ( model,
                        { digest = resolved.resolution_digest; replayed = true } )
                  else Error (diagnostic Request_conflict)
              | Recorded_lost ->
                  (match model.pending with
                   | None -> Error (diagnostic Reconciliation_mismatch)
                   | Some pending
                     when not (String.equal pending.request request)
                          || pending.action <> action ->
                       Error (diagnostic Reconciliation_mismatch)
                   | Some pending ->
                       let normal_result =
                         match resolution with
                         | Applied_exact_on_readback ->
                             advance model.prepared pending.prior action
                         | Not_applied_on_readback -> Ok pending.prior
                       in
                       (match normal_result with
                        | Error _ as error -> error
                        | Ok normal ->
                            let resolution_digest =
                              sha256
                                [ "dependability-recovery-vault-reconcile-v1";
                                  record.initial_digest; readback;
                                  resolution_key resolution ]
                            in
                            let replacement =
                              { record with
                                outcome =
                                  Recorded_resolved
                                    { resolution; readback; resolution_digest } }
                            in
                            Ok
                              ( { model with normal; pending = None;
                                  records =
                                    replace_record replacement model.records },
                                { digest = resolution_digest;
                                  replayed = false } )))))

  let receipt_digest (receipt : transition_receipt) = receipt.digest
  let receipt_replayed (receipt : transition_receipt) = receipt.replayed

  let prepare_recovery_inventory model ~now =
    match check_current model now with
    | Error _ as error -> error
    | Ok () ->
        let row_digests =
          List.map
            (fun (object_ : sealed_object) -> object_.digest)
            model.prepared.objects
          @ List.map record_digest model.records
          @ [ model_digest model ]
        in
        let rec identities acc = function
          | [] -> Ok (List.rev acc)
          | value :: rest ->
              (match Dependability_owner_inventory.Identity.make value with
               | Error _ ->
                   Error (diagnostic Inventory_preparation_failed)
               | Ok identity -> identities (identity :: acc) rest)
        in
        (match identities [] row_digests with
         | Error _ as error -> error
         | Ok rows ->
             (match
                Dependability_owner_inventory.make_denominator ~expected:rows
                  ~observed:rows
              with
              | Error _ ->
                  Error (diagnostic Inventory_preparation_failed)
              | Ok denominator ->
                  (match
                     Dependability_owner_inventory.Identity.make
                       (model_digest model)
                   with
                   | Error _ ->
                       Error (diagnostic Inventory_preparation_failed)
                   | Ok owner_readback ->
                       (match
                          Dependability_owner_inventory.prepare_fragment
                            ~role:Dependability_owner_inventory.Recovery_vault
                            ~context:
                              model.prepared.context.context.inventory_context
                            ~denominator ~owner_readback
                        with
                        | Error _ ->
                            Error (diagnostic Inventory_preparation_failed)
                        | Ok fragment -> Ok fragment))))

  type mutation =
    | Cross_purpose_restore
    | Emit_raw_payload
    | Skip_currentness
    | Drop_replay_check
    | Guess_lost_reply
    | Forge_current_inventory
    | Skip_cleanup_order
    | Unbind_manifest_session
    | Enable_filesystem_backend

  let mutation_key = function
    | Cross_purpose_restore -> "cross-purpose-restore"
    | Emit_raw_payload -> "emit-raw-payload"
    | Skip_currentness -> "skip-currentness"
    | Drop_replay_check -> "drop-replay-check"
    | Guess_lost_reply -> "guess-lost-reply"
    | Forge_current_inventory -> "forge-current-inventory"
    | Skip_cleanup_order -> "skip-cleanup-order"
    | Unbind_manifest_session -> "unbind-manifest-session"
    | Enable_filesystem_backend -> "enable-filesystem-backend"

  let source_digest_with_mutation mutation =
    sha256
      [ "dependability-recovery-vault-mutant-v1"; mutation_key mutation;
        source_digest ]
end
