type diagnostic_code =
  | Generation_overflow
  | Generation_gap
  | Generation_stale
  | Generation_conflict

type rca_origin = Implementation_origin | Dependency_origin

type diagnostic = {
  diagnostic_code : diagnostic_code;
  diagnostic_message : string;
  diagnostic_coordinate : string;
  diagnostic_rca_origin : rca_origin;
}

let diagnostic diagnostic_code diagnostic_message diagnostic_rca_origin =
  { diagnostic_code; diagnostic_message;
    diagnostic_coordinate = "task8/runtime-registry/schema";
    diagnostic_rca_origin }

type manifest_generation = int
let epoch_zero = 0
let generation_index generation = generation

let successor generation =
  if generation = max_int then
    Error
      (diagnostic Generation_overflow "manifest generation overflow"
         Implementation_origin)
  else Ok (generation + 1)

type prepared_row = {
  row_manifest_digest : string;
  row_receipt_digest : string;
}

type conflict_row = {
  conflict_first_manifest_digest : string;
  conflict_first_receipt_digest : string;
  conflict_second_manifest_digest : string;
}

type row = Prepared_row of prepared_row | Conflict_row of conflict_row

type registry_state = {
  state_next_generation : int;
  state_rows : (int * row) list;
}

type registry = { registry_cell : registry_state Atomic.t }

type prepared_generation = {
  prepared_registry_cell : registry_state Atomic.t;
  prepared_generation_value : int;
  prepared_generation_receipt : string;
}

type prepare_receipt = {
  prepared_generation_index : int;
  prepared_manifest_digest : string;
  prepared_slot_count : int;
  prepared_slot_schema_digest : string;
  prepared_receipt_digest : string;
  prepared_was_replayed : bool;
}

let create_volatile_registry () =
  { registry_cell =
      Atomic.make { state_next_generation = 0; state_rows = [] } }

type generation_state =
  | Generation_absent
  | Generation_schema_prepared
  | Generation_schema_conflict

type generation_readback = {
  readback_generation_index : int;
  readback_generation_state : generation_state;
  readback_manifest_digest : string option;
  readback_conflicting_manifest_digest : string option;
  readback_receipt_digest : string option;
}

let fixed_slot_keys = Jj_runtime_manifest.production_slot_keys
let fixed_slot_count = List.length fixed_slot_keys

let digest values =
  values |> Jj_id.length_frame |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let slot_schema_digest_of keys =
  digest ("runtime-registry-slot-schema-v1" :: keys)

let slot_schema_digest = slot_schema_digest_of fixed_slot_keys

let receipt_digest generation manifest_digest =
  digest
    [ "runtime-registry-schema-preparation-v1";
      string_of_int generation; manifest_digest; slot_schema_digest ]

let receipt_of_row generation row ~replayed =
  { prepared_generation_index = generation;
    prepared_manifest_digest = row.row_manifest_digest;
    prepared_slot_count = fixed_slot_count;
    prepared_slot_schema_digest = slot_schema_digest;
    prepared_receipt_digest = row.row_receipt_digest;
    prepared_was_replayed = replayed }

let prepared_of_row registry generation row =
  { prepared_registry_cell = registry.registry_cell;
    prepared_generation_value = generation;
    prepared_generation_receipt = row.row_receipt_digest }

let rec prepare_generation_schema_once registry ~generation ~manifest =
  let manifest_digest = Jj_runtime_manifest.production_digest manifest in
  let before = Atomic.get registry.registry_cell in
  match List.assoc_opt generation before.state_rows with
  | Some (Conflict_row _) ->
      Error
        (diagnostic Generation_conflict
           "manifest generation is conflict-fenced" Implementation_origin)
  | Some (Prepared_row row) when row.row_manifest_digest = manifest_digest ->
      Ok
        (prepared_of_row registry generation row,
         receipt_of_row generation row ~replayed:true)
  | Some (Prepared_row row) ->
      let conflicted =
        Conflict_row
          { conflict_first_manifest_digest = row.row_manifest_digest;
            conflict_first_receipt_digest = row.row_receipt_digest;
            conflict_second_manifest_digest = manifest_digest }
      in
      let after =
        { before with
          state_rows =
            List.map
              (fun (index, existing) ->
                if index = generation then (index, conflicted)
                else (index, existing))
              before.state_rows }
      in
      if Atomic.compare_and_set registry.registry_cell before after then
        Error
          (diagnostic Generation_conflict
             "changed manifest conflicts with prepared generation"
             Implementation_origin)
      else prepare_generation_schema_once registry ~generation ~manifest
  | None when generation > before.state_next_generation ->
      Error
        (diagnostic Generation_gap "manifest generation skips its predecessor"
           Implementation_origin)
  | None when generation < before.state_next_generation ->
      Error
        (diagnostic Generation_stale "manifest generation is stale or missing"
           Implementation_origin)
  | None ->
      let row =
        { row_manifest_digest = manifest_digest;
          row_receipt_digest = receipt_digest generation manifest_digest }
      in
      let after =
        { state_next_generation = before.state_next_generation + 1;
          state_rows = before.state_rows @ [ (generation, Prepared_row row) ] }
      in
      if Atomic.compare_and_set registry.registry_cell before after then
        Ok
          (prepared_of_row registry generation row,
           receipt_of_row generation row ~replayed:false)
      else prepare_generation_schema_once registry ~generation ~manifest

let read_generation registry ~generation =
  let state = Atomic.get registry.registry_cell in
  match List.assoc_opt generation state.state_rows with
  | None ->
      { readback_generation_index = generation;
        readback_generation_state = Generation_absent;
        readback_manifest_digest = None;
        readback_conflicting_manifest_digest = None;
        readback_receipt_digest = None }
  | Some (Prepared_row row) ->
      { readback_generation_index = generation;
        readback_generation_state = Generation_schema_prepared;
        readback_manifest_digest = Some row.row_manifest_digest;
        readback_conflicting_manifest_digest = None;
        readback_receipt_digest = Some row.row_receipt_digest }
  | Some (Conflict_row row) ->
      { readback_generation_index = generation;
        readback_generation_state = Generation_schema_conflict;
        readback_manifest_digest = Some row.conflict_first_manifest_digest;
        readback_conflicting_manifest_digest =
          Some row.conflict_second_manifest_digest;
        readback_receipt_digest = Some row.conflict_first_receipt_digest }

type registration_prerequisite =
  | Durable_generation_owner
  | Target_registry_current_view
  | Process_registry_current_view
  | Runtime_current_views
  | Activation_current_views
  | Store_current_views
  | Slot_generation_grant_protocol
  | Current_attestation_seal_protocol
  | Manifest_formal_posture_projection

let registration_prerequisites =
  [ Durable_generation_owner; Target_registry_current_view;
    Process_registry_current_view; Runtime_current_views;
    Activation_current_views; Store_current_views;
    Slot_generation_grant_protocol; Current_attestation_seal_protocol;
    Manifest_formal_posture_projection ]

let registration_prerequisite_id = function
  | Durable_generation_owner -> "durable-generation-owner"
  | Target_registry_current_view -> "target-registry-current-view"
  | Process_registry_current_view -> "process-registry-current-view"
  | Runtime_current_views -> "runtime-current-views"
  | Activation_current_views -> "activation-current-views"
  | Store_current_views -> "store-current-views"
  | Slot_generation_grant_protocol -> "slot-generation-grant-protocol"
  | Current_attestation_seal_protocol -> "current-attestation-seal-protocol"
  | Manifest_formal_posture_projection ->
      "manifest-formal-posture-projection"

type unavailable = {
  unavailable_operation : string;
  unavailable_prerequisites : registration_prerequisite list;
  unavailable_coordinate : string;
  unavailable_rca_origin : rca_origin;
}

type jj_runtime_manifest_current = |

let register_current_unavailable _registry _prepared =
  let prepared_belongs_to_registry registry prepared =
    registry.registry_cell == prepared.prepared_registry_cell
    &&
    match
      List.assoc_opt prepared.prepared_generation_value
        (Atomic.get registry.registry_cell).state_rows
    with
    | Some (Prepared_row row) ->
        row.row_receipt_digest = prepared.prepared_generation_receipt
    | Some (Conflict_row row) ->
        row.conflict_first_receipt_digest = prepared.prepared_generation_receipt
    | None -> false
  in
  let prepared_lineage_is_known =
    prepared_belongs_to_registry _registry _prepared
  in
  Error
    { unavailable_operation = "register-current";
      unavailable_prerequisites = registration_prerequisites;
      unavailable_coordinate =
        (if prepared_lineage_is_known then "task8/runtime-registry/current"
         else "task8/runtime-registry/foreign-or-stale-preparation");
      unavailable_rca_origin = Dependency_origin }

let production_posture = `Implemented_unavailable

let source_digest_of laws prerequisites schema_digest =
  digest
    ([ "runtime-registry-foundation-v1"; Jj_runtime_manifest.source_digest;
       Jj_runtime_current_protocol.source_digest; schema_digest ]
     @ laws @ List.map registration_prerequisite_id prerequisites)

let laws =
  [ "generation-order"; "same-row-replay"; "conflict-absorbing";
    "production-profile-only"; "no-current-forgery" ]

let source_digest =
  source_digest_of laws registration_prerequisites slot_schema_digest

module For_test = struct
  type slot_schema_mutation = Drop_slot | Reorder_slots | Duplicate_slot

  let slot_schema_digest_with_mutation mutation =
    let keys =
      match mutation, fixed_slot_keys with
      | Drop_slot, [] -> []
      | Drop_slot, _ :: rest -> rest
      | Reorder_slots, keys -> List.rev keys
      | Duplicate_slot, [] -> [ "duplicate"; "duplicate" ]
      | Duplicate_slot, first :: _ -> first :: fixed_slot_keys
    in
    slot_schema_digest_of keys

  type source_mutation =
    | Drop_generation_order
    | Permit_overwrite
    | Permit_conflict_recovery
    | Drop_slot_schema
    | Permit_test_profile
    | Forge_current
    | Drop_current_prerequisite

  let source_digest_with_mutation mutation =
    match mutation with
    | Drop_generation_order ->
        source_digest_of (List.tl laws) registration_prerequisites
          slot_schema_digest
    | Permit_overwrite ->
        source_digest_of ("permit-overwrite" :: laws) registration_prerequisites
          slot_schema_digest
    | Permit_conflict_recovery ->
        source_digest_of ("permit-conflict-recovery" :: laws)
          registration_prerequisites slot_schema_digest
    | Drop_slot_schema ->
        source_digest_of laws registration_prerequisites "slot-schema-dropped"
    | Permit_test_profile ->
        source_digest_of ("permit-test-profile" :: laws)
          registration_prerequisites slot_schema_digest
    | Forge_current ->
        source_digest_of ("forge-current" :: laws) registration_prerequisites
          slot_schema_digest
    | Drop_current_prerequisite ->
        source_digest_of laws
          (match registration_prerequisites with [] -> [] | _ :: rest -> rest)
          slot_schema_digest
end
