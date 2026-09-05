type t = |

type unavailable_prerequisite =
  | Preparation_current
  | Activity_result_current
  | Event_prefix_current
  | Readback_current
  | Composed_authority_current

type diagnostic = {
  prerequisite : unavailable_prerequisite;
  message : string;
  coordinate : string;
  origin : [ `Evidence ];
}

let diagnostic_prerequisite diagnostic = diagnostic.prerequisite
let diagnostic_message diagnostic = diagnostic.message
let diagnostic_coordinate diagnostic = diagnostic.coordinate
let diagnostic_origin diagnostic = diagnostic.origin

let prerequisites =
  [ Preparation_current; Activity_result_current; Event_prefix_current;
    Readback_current; Composed_authority_current ]

let prerequisite_id = function
  | Preparation_current -> "preparation-current"
  | Activity_result_current -> "activity-result-current"
  | Event_prefix_current -> "event-prefix-current"
  | Readback_current -> "readback-current"
  | Composed_authority_current -> "composed-authority-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/jj-receipt-integration";
    origin = `Evidence }

let production_posture = `Implemented_unavailable

let finalize_unavailable () = Error (List.map diagnostic prerequisites)

let prerequisite_ids = List.map prerequisite_id prerequisites

let source_fields prerequisite_denominator =
  [ ("schema", "jj-receipt-integration-foundation-v1");
    ("receipt-core-source", Jj_receipt_core.source_digest);
    ("prerequisite-order", String.concat "," prerequisite_denominator);
    ("join-shape",
     "preparation,activity-result,event-prefix,readback,composed-authority");
    ("finalization", "implemented-unavailable");
    ("owner-receipt-constructor", "absent");
    ("payload-projection", "absent");
    ("capability-projection", "absent");
    ("caller-digest", "rejected");
    ("current-promotion", "absent");
    ("authority-posture", "non-authorizing") ]

let digest fields =
  fields
  |> List.map (fun (name, value) -> Jj_id.length_frame [ name; value ])
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let source_digest = digest (source_fields prerequisite_ids)

module For_test = struct
  type source_mutation =
    | Drop_preparation
    | Drop_activity_result
    | Drop_event_prefix
    | Drop_readback
    | Drop_composed_authority
    | Reorder_prerequisites
    | Substitute_event_prefix
    | Drop_core_source
    | Add_owner_receipt_constructor
    | Expose_payload
    | Expose_capability
    | Accept_caller_digest
    | Promote_current

  let drop_id id ids =
    List.filter (fun candidate -> not (String.equal candidate id)) ids

  let substitute_id before after ids =
    List.map
      (fun candidate ->
        if String.equal candidate before then after else candidate)
      ids

  let drop_field name fields =
    List.filter
      (fun (candidate, _) -> not (String.equal candidate name))
      fields

  let replace_field name value fields =
    List.map
      (fun ((candidate, _) as field) ->
        if String.equal candidate name then (candidate, value) else field)
      fields

  let source_digest_with_mutation mutation =
    let denominator, mutate_fields =
      match mutation with
      | Drop_preparation ->
          (drop_id "preparation-current" prerequisite_ids, fun fields -> fields)
      | Drop_activity_result ->
          (drop_id "activity-result-current" prerequisite_ids,
           fun fields -> fields)
      | Drop_event_prefix ->
          (drop_id "event-prefix-current" prerequisite_ids, fun fields -> fields)
      | Drop_readback ->
          (drop_id "readback-current" prerequisite_ids, fun fields -> fields)
      | Drop_composed_authority ->
          (drop_id "composed-authority-current" prerequisite_ids,
           fun fields -> fields)
      | Reorder_prerequisites -> (List.rev prerequisite_ids, fun fields -> fields)
      | Substitute_event_prefix ->
          (substitute_id "event-prefix-current" "event-list" prerequisite_ids,
           fun fields -> fields)
      | Drop_core_source ->
          (prerequisite_ids, drop_field "receipt-core-source")
      | Add_owner_receipt_constructor ->
          (prerequisite_ids,
           replace_field "owner-receipt-constructor" "public")
      | Expose_payload ->
          (prerequisite_ids, replace_field "payload-projection" "public")
      | Expose_capability ->
          (prerequisite_ids, replace_field "capability-projection" "public")
      | Accept_caller_digest ->
          (prerequisite_ids, replace_field "caller-digest" "accepted")
      | Promote_current ->
          (prerequisite_ids, replace_field "current-promotion" "public")
    in
    source_fields denominator |> mutate_fields |> digest
end
