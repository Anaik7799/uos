type unavailable_code =
  | Invalid_capacity
  | Activity_invalid
  | Registration_capacity_exhausted
  | Registration_conflict
  | Missing_registration
  | Current_registration_unavailable

type current_prerequisite =
  | Target_registry_current
  | Effect_interpreter_current_identity
  | Conditional_interpreter_current
  | Event_store_current_identity

type unavailable = {
  code : unavailable_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
  missing_prerequisites : current_prerequisite list;
}

type prepared_family = Ordinary_activity

type prepared_slot_receipt = {
  prepared_activity_digest : string;
  prepared_family : prepared_family;
  prepared_slot_schema_digest : string;
  prepared_slot_receipt_digest : string;
  prepared_slot_was_replayed : bool;
}

type slot_state =
  | Slot_unregistered
  | Slot_prepared
  | Slot_conflict

type prepared_row = {
  row_activity_authority_digest : string;
  row_slot_schema_digest : string;
  row_slot_receipt_digest : string;
}

type row_state = Prepared_row of prepared_row | Conflicted_row

module Activity_map = Map.Make (String)

type broker = {
  mutex : Mutex.t;
  maximum_registrations : int;
  mutable slots : row_state Activity_map.t;
}

type ordinary

type _ lease_family =
  | Ordinary_family : ordinary lease_family
  | B_family : Jj_campaign_action.b_campaign lease_family
  | Completion_family : Jj_campaign_action.completion_reconcile lease_family

type 'family lease = |
type packed_lease = Lease : 'family lease -> packed_lease

let default_coordinate : Ops_capability.coordinate =
  { Ops_capability.level = Ops_capability.L3;
    phase = Ops_capability.Decide }

let unavailable ?(missing_prerequisites = []) code message =
  { code; message; coordinate = default_coordinate;
    rca_origin = Ops_capability.Control;
    hazard_id = "HZ-OPERATOR-BROKER-UNAVAILABLE";
    missing_prerequisites }

let current_prerequisites =
  [ Target_registry_current; Effect_interpreter_current_identity;
    Conditional_interpreter_current; Event_store_current_identity ]

let current_registration_posture = `Implemented_unavailable

let with_lock mutex body =
  Mutex.lock mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock mutex) body

let create ~maximum_registrations =
  if maximum_registrations < 1 || maximum_registrations > 256 then
    Error
      (unavailable Invalid_capacity
         "maximum_registrations must be in the closed range 1..256")
  else
    Ok
      { mutex = Mutex.create (); maximum_registrations;
        slots = Activity_map.empty }

let sha256 bytes =
  bytes |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let frame value = Printf.sprintf "%d:%s" (String.length value) value
let digest_fields fields = fields |> List.map frame |> String.concat "" |> sha256

let slot_schema_digest activity =
  let declaration = Run_topology.admitted_declaration activity in
  let target_schema_digest =
    Run_effect_authority.canonical_jj_target_registry_schema ()
    |> Run_effect_authority.jj_target_registry_schema_digest
  in
  digest_fields
    [ "operator-broker-prepared-slot-v1";
      Run_topology.admitted_activity_authority_digest activity;
      Run_topology.admitted_activity_digest activity;
      declaration.Run_topology.stable_id; target_schema_digest;
      Run_conditional_authority.source_digest ]

let slot_receipt_digest ~activity_digest ~slot_schema_digest =
  digest_fields
    [ "operator-broker-prepared-receipt-v1"; activity_digest;
      slot_schema_digest; "ordinary" ]

let validate_activity activity =
  let declaration = Run_topology.admitted_declaration activity in
  let activity_digest = Run_topology.admitted_activity_digest activity in
  let stable_id = declaration.Run_topology.stable_id in
  if String.starts_with ~prefix:"activity.jj.conditional." stable_id then
    Error
      (unavailable Activity_invalid
         "conditional activity preparation awaits its family-current owner")
  else match Run_topology.admit_activity ~stable_id with
  | Error issues ->
      Error
        (unavailable Activity_invalid
           ("admitted activity is not in current topology authority: "
            ^ String.concat "; " issues))
  | Ok canonical
    when activity_digest = Run_topology.admitted_activity_digest canonical
         && Run_topology.admitted_activity_authority_digest activity
            = Run_topology.admitted_activity_authority_digest canonical ->
      Ok activity_digest
  | Ok _ ->
      Error
        (unavailable Activity_invalid
           "admitted activity differs from current topology authority")

let receipt row ~activity_digest ~replayed =
  { prepared_activity_digest = activity_digest;
    prepared_family = Ordinary_activity;
    prepared_slot_schema_digest = row.row_slot_schema_digest;
    prepared_slot_receipt_digest = row.row_slot_receipt_digest;
    prepared_slot_was_replayed = replayed }

let conflict () =
  unavailable Registration_conflict
    "prepared operator-broker slot is conflict-fenced"

let prepare_slot broker ~activity =
  match validate_activity activity with
  | Error _ as error -> error
  | Ok activity_digest ->
      let expected =
        let row_slot_schema_digest = slot_schema_digest activity in
        { row_activity_authority_digest =
            Run_topology.admitted_activity_authority_digest activity;
          row_slot_schema_digest;
          row_slot_receipt_digest =
            slot_receipt_digest ~activity_digest ~slot_schema_digest:
              row_slot_schema_digest }
      in
      with_lock broker.mutex (fun () ->
        match Activity_map.find_opt activity_digest broker.slots with
        | Some Conflicted_row -> Error (conflict ())
        | Some (Prepared_row row) when row = expected ->
            Ok (receipt row ~activity_digest ~replayed:true)
        | Some (Prepared_row _) ->
            broker.slots <-
              Activity_map.add activity_digest Conflicted_row broker.slots;
            Error (conflict ())
        | None
          when Activity_map.cardinal broker.slots
               >= broker.maximum_registrations ->
            Error
              (unavailable Registration_capacity_exhausted
                 "fixed operator-broker registration capacity is exhausted")
        | None ->
            broker.slots <-
              Activity_map.add activity_digest (Prepared_row expected)
                broker.slots;
            Ok (receipt expected ~activity_digest ~replayed:false))

let slot_state broker ~activity =
  let activity_digest = Run_topology.admitted_activity_digest activity in
  with_lock broker.mutex (fun () ->
    match Activity_map.find_opt activity_digest broker.slots with
    | None -> Slot_unregistered
    | Some (Prepared_row _) -> Slot_prepared
    | Some Conflicted_row -> Slot_conflict)

let prepared_registration_count broker =
  with_lock broker.mutex (fun () -> Activity_map.cardinal broker.slots)

let current_unavailable () =
  unavailable ~missing_prerequisites:current_prerequisites
    Current_registration_unavailable
    "operator-broker current registration prerequisites are unavailable"

let register_current_unavailable broker prepared =
  with_lock broker.mutex (fun () ->
    match
      Activity_map.find_opt prepared.prepared_activity_digest broker.slots
    with
    | None ->
        Error
          (unavailable Missing_registration
             "prepared activity has no operator-broker slot")
    | Some Conflicted_row -> Error (conflict ())
    | Some (Prepared_row row)
      when row.row_slot_schema_digest
           = prepared.prepared_slot_schema_digest
           && row.row_slot_receipt_digest
              = prepared.prepared_slot_receipt_digest ->
        Error (current_unavailable ())
    | Some (Prepared_row _) ->
        broker.slots <-
          Activity_map.add prepared.prepared_activity_digest Conflicted_row
            broker.slots;
        Error (conflict ()))

let acquire_current_unavailable broker ~activity =
  match validate_activity activity with
  | Error _ as error -> error
  | Ok activity_digest ->
      let expected_schema_digest = slot_schema_digest activity in
      with_lock broker.mutex (fun () ->
        match Activity_map.find_opt activity_digest broker.slots with
        | None ->
            Error
              (unavailable Missing_registration
                 "activity has no prepared operator-broker slot")
        | Some Conflicted_row -> Error (conflict ())
        | Some (Prepared_row row)
          when row.row_activity_authority_digest
               = Run_topology.admitted_activity_authority_digest activity
               && row.row_slot_schema_digest = expected_schema_digest ->
            Error (current_unavailable ())
        | Some (Prepared_row _) ->
            broker.slots <-
              Activity_map.add activity_digest Conflicted_row broker.slots;
            Error (conflict ()))

let family_id : type family. family lease_family -> string = function
  | Ordinary_family -> "ordinary"
  | B_family -> "b-campaign"
  | Completion_family -> "completion-reconcile"

let lease_projection_ids =
  [ "effect-interpreter"; "conditional-interpreter" ]

let effect_interpreter (type family) (lease : family lease) =
  match lease with _ -> .

let conditional_interpreter (type family)
    (_family : family Run_conditional_authority.family)
    (lease : family lease) =
  match lease with _ -> .

module For_test = struct
  type slot_mutation = Slot_schema_identity

  let mutate_digest digest =
    if String.length digest = 0 then "mutated"
    else
      let replacement = if digest.[0] = '0' then '1' else '0' in
      String.make 1 replacement ^ String.sub digest 1 (String.length digest - 1)

  let mutate_prepared_slot broker ~activity Slot_schema_identity =
    let activity_digest = Run_topology.admitted_activity_digest activity in
    with_lock broker.mutex (fun () ->
      match Activity_map.find_opt activity_digest broker.slots with
      | Some (Prepared_row row) ->
          broker.slots <-
            Activity_map.add activity_digest
              (Prepared_row
                 { row with
                   row_slot_schema_digest =
                     mutate_digest row.row_slot_schema_digest })
              broker.slots;
          true
      | None | Some Conflicted_row -> false)
end
