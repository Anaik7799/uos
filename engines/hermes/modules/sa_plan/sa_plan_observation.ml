open Core

type source_journal = { source_journal_ref : string; host_boot_id : string }

type session_observation = {
  event_id : string;
  payload_hash : string;
  local_sequence : int64;
  session_ref : string;
  resource_ref : string;
  epoch : int64;
  candidate_ref : string;
}

type observation_accepted = {
  event_id : string;
  payload_hash : string;
  hermes_sequence : int64;
  replayed : bool;
}

type reconciliation_kind =
  | Payload_hash_mismatch
  | Body_conflict
  | Sequence_conflict
  | Sequence_gap
  | Out_of_order

type reconciliation_required = {
  kind : reconciliation_kind;
  event_id : string;
  payload_hash : string;
  expected_sequence : int64 option;
  actual_sequence : int64;
}

type outcome =
  | Observation_accepted of observation_accepted
  | Reconciliation_required of reconciliation_required

let max_ref_bytes = 4_096
let max_identity_bytes = 256

let validate_text ~label ~max_bytes value =
  if String.is_empty value then Error (label ^ " must not be empty")
  else if String.length value > max_bytes then
    Error (Printf.sprintf "%s exceeds %d bytes" label max_bytes)
  else if String.mem value '\000' then Error (label ^ " must not contain NUL")
  else Ok value

let valid_lower_hex value =
  String.length value = 64
  && String.for_all value ~f:(function
       | '0' .. '9' | 'a' .. 'f' -> true
       | _ -> false)

let make ~source_journal_ref ~host_boot_id ~event_id ~payload_hash
    ~local_sequence ~session_ref ~resource_ref ~epoch ~candidate_ref =
  let open Result.Let_syntax in
  let%bind source_journal_ref =
    validate_text ~label:"source_journal_ref" ~max_bytes:max_ref_bytes
      source_journal_ref
  in
  let%bind host_boot_id =
    validate_text ~label:"host_boot_id" ~max_bytes:max_identity_bytes host_boot_id
  in
  let%bind event_id =
    validate_text ~label:"event_id" ~max_bytes:max_identity_bytes event_id
  in
  let%bind () =
    if valid_lower_hex payload_hash then Ok ()
    else Error "payload_hash must be a lowercase 64-hex SHA-256"
  in
  let%bind () =
    if Int64.(local_sequence > 0L) then Ok ()
    else Error "local_sequence must be positive"
  in
  let%bind session_ref =
    validate_text ~label:"session_ref" ~max_bytes:max_ref_bytes session_ref
  in
  let%bind resource_ref =
    validate_text ~label:"resource_ref" ~max_bytes:max_ref_bytes resource_ref
  in
  let%bind () =
    if Int64.(epoch >= 0L) then Ok () else Error "epoch must be non-negative"
  in
  let%map candidate_ref =
    validate_text ~label:"candidate_ref" ~max_bytes:max_ref_bytes candidate_ref
  in
  ( { source_journal_ref; host_boot_id },
    { event_id; payload_hash; local_sequence; session_ref; resource_ref; epoch;
      candidate_ref } )

let canonical_json (source : source_journal)
    (observation : session_observation) =
  `Assoc
    [ "source_journal_ref", `String source.source_journal_ref;
      "host_boot_id", `String source.host_boot_id;
      "event_id", `String observation.event_id;
      "local_sequence", `Intlit (Int64.to_string observation.local_sequence);
      "session_ref", `String observation.session_ref;
      "resource_ref", `String observation.resource_ref;
      "epoch", `Intlit (Int64.to_string observation.epoch);
      "candidate_ref", `String observation.candidate_ref ]
  |> Yojson.Safe.to_string

let computed_payload_hash source observation =
  canonical_json source observation
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let reconciliation_kind_of_store = function
  | Sa_plan_store.Payload_hash_mismatch -> Payload_hash_mismatch
  | Body_conflict -> Body_conflict
  | Sequence_conflict -> Sequence_conflict
  | Sequence_gap -> Sequence_gap
  | Out_of_order -> Out_of_order

let ingest store source observation =
  let computed_hash = computed_payload_hash source observation in
  let write =
    Sa_plan_store.
      { source_journal_ref = source.source_journal_ref;
        host_boot_id = source.host_boot_id;
        event_id = observation.event_id;
        declared_payload_hash = observation.payload_hash;
        computed_payload_hash = computed_hash;
        local_sequence = observation.local_sequence;
        session_ref = observation.session_ref;
        resource_ref = observation.resource_ref;
        epoch = observation.epoch;
        candidate_ref = observation.candidate_ref }
  in
  Result.map (Sa_plan_store.ingest_session_observation store write) ~f:(function
    | Sa_plan_store.Observation_stored { observation = row; replayed } ->
        Observation_accepted
          { event_id = row.event_id;
            payload_hash = row.payload_hash;
            hermes_sequence = row.hermes_sequence;
            replayed }
    | Sa_plan_store.Observation_reconciliation reconciliation ->
        Reconciliation_required
          { kind = reconciliation_kind_of_store reconciliation.kind;
            event_id = reconciliation.event_id;
            payload_hash = reconciliation.computed_payload_hash;
            expected_sequence = reconciliation.expected_sequence;
            actual_sequence = reconciliation.local_sequence })

let expected_fields =
  String.Set.of_list
    [ "source_journal_ref"; "host_boot_id"; "event_id"; "payload_hash";
      "local_sequence"; "session_ref"; "resource_ref"; "epoch";
      "candidate_ref" ]

let string_member fields name =
  match List.Assoc.find fields ~equal:String.equal name with
  | Some (`String value) -> Ok value
  | Some _ -> Error (name ^ " must be a string")
  | None -> Error ("missing field: " ^ name)

let int64_member fields name =
  match List.Assoc.find fields ~equal:String.equal name with
  | Some (`Int value) -> Ok (Int64.of_int value)
  | Some (`Intlit value) ->
      (try Ok (Int64.of_string value)
       with _ -> Error (name ^ " must be an int64"))
  | Some _ -> Error (name ^ " must be an integer")
  | None -> Error ("missing field: " ^ name)

let of_yojson = function
  | `Assoc fields ->
      let actual_fields =
        List.map fields ~f:fst |> String.Set.of_list
      in
      if List.length fields <> Set.length actual_fields then
        Error "duplicate JSON object member"
      else if not (Set.equal expected_fields actual_fields) then
        let unexpected = Set.diff actual_fields expected_fields |> Set.to_list in
        let missing = Set.diff expected_fields actual_fields |> Set.to_list in
        Error
          (Printf.sprintf "JSON fields mismatch (unexpected=%s missing=%s)"
             (String.concat ~sep:"," unexpected)
             (String.concat ~sep:"," missing))
      else
        let open Result.Let_syntax in
        let%bind source_journal_ref = string_member fields "source_journal_ref" in
        let%bind host_boot_id = string_member fields "host_boot_id" in
        let%bind event_id = string_member fields "event_id" in
        let%bind payload_hash = string_member fields "payload_hash" in
        let%bind local_sequence = int64_member fields "local_sequence" in
        let%bind session_ref = string_member fields "session_ref" in
        let%bind resource_ref = string_member fields "resource_ref" in
        let%bind epoch = int64_member fields "epoch" in
        let%bind candidate_ref = string_member fields "candidate_ref" in
        make ~source_journal_ref ~host_boot_id ~event_id ~payload_hash
          ~local_sequence ~session_ref ~resource_ref ~epoch ~candidate_ref
  | _ -> Error "observation input must be one JSON object"

let computed_payload_hash_of_yojson = function
  | `Assoc fields
    when not (List.Assoc.mem fields ~equal:String.equal "payload_hash") ->
      let placeholder = String.make 64 '0' in
      Result.map (of_yojson (`Assoc (("payload_hash", `String placeholder) :: fields)))
        ~f:(fun (source, observation) ->
          computed_payload_hash source observation)
  | `Assoc _ -> Error "payload_hash must be absent in hash mode"
  | _ -> Error "hash input must be one JSON object"

let reconciliation_kind_to_string = function
  | Payload_hash_mismatch -> "payload_hash_mismatch"
  | Body_conflict -> "body_conflict"
  | Sequence_conflict -> "sequence_conflict"
  | Sequence_gap -> "sequence_gap"
  | Out_of_order -> "out_of_order"

let outcome_to_yojson = function
  | Observation_accepted accepted ->
      `Assoc
        [ "status", `String "accepted";
          "event_id", `String accepted.event_id;
          "payload_hash", `String accepted.payload_hash;
          "hermes_sequence", `Intlit (Int64.to_string accepted.hermes_sequence);
          "replayed", `Bool accepted.replayed ]
  | Reconciliation_required reconciliation ->
      `Assoc
        [ "status", `String "reconciliation_required";
          "kind", `String (reconciliation_kind_to_string reconciliation.kind);
          "event_id", `String reconciliation.event_id;
          "payload_hash", `String reconciliation.payload_hash;
          ( "expected_sequence",
            Option.value_map reconciliation.expected_sequence ~default:`Null
              ~f:(fun value -> `Intlit (Int64.to_string value)) );
          "actual_sequence", `Intlit (Int64.to_string reconciliation.actual_sequence) ]

module _ : module type of Sa_plan_observation = Sa_plan_observation
