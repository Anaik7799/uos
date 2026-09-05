type owner = |
type registration = |
type host_current_receipt = |

type unavailable_prerequisite =
  | Target_owner_part_current
  | Controlled_resource_observer
  | Receipt_bound_resource_envelope
  | Event_effect_readback_current

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

let runtime_declaration = Jj_runtime_manifest.target_external_resource
let target_protocol = Jj_target_protocol.External_resource
let accepted_roles = [ Jj_action_kind.Observe_external_resource ]
let accepted_effects = [ Run_topology.External_resource_observation ]

let prerequisites =
  [ Target_owner_part_current; Controlled_resource_observer;
    Receipt_bound_resource_envelope; Event_effect_readback_current ]

let production_posture = `Implemented_unavailable

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Controlled_resource_observer -> "controlled-resource-observer"
  | Receipt_bound_resource_envelope -> "receipt-bound-resource-envelope"
  | Event_effect_readback_current -> "event-effect-readback-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-external-resource-target";
    origin = `Evidence }

let create_owner_unavailable () =
  Error (List.map diagnostic prerequisites)

let source_fields =
  [ ("schema", "ops-external-resource-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("runtime-declaration-key",
     Jj_runtime_manifest.declaration_key runtime_declaration);
    ("runtime-declaration-digest",
     Jj_runtime_manifest.declaration_digest runtime_declaration);
    ("target-protocol", Jj_target_protocol.key target_protocol);
    ("accepted-roles",
     String.concat ","
       (List.map Jj_action_kind.auxiliary_role_key accepted_roles));
    ("accepted-effects",
     String.concat ","
       (List.map Run_topology.effect_kind_id accepted_effects));
    ("target-owner-part", "unavailable:distinct-part-required");
    ("resource-observer", "unavailable:controlled-owner-required");
    ("resource-envelope", "unavailable:receipt-bound-required");
    ("event-effect-readback", "unavailable:owner-current-required");
    ("raw-host", "absent");
    ("raw-path", "absent");
    ("environment", "absent");
    ("executable", "absent");
    ("probe-callback", "absent");
    ("unavailable-evidence", "never-promoted");
    ("current-constructor", "absent");
    ("production-posture", "implemented-unavailable") ]

let digest fields =
  fields
  |> List.map (fun (name, value) -> Jj_id.length_frame [ name; value ])
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let source_digest = digest source_fields

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_topology_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_role
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_owner_part
    | Drop_resource_observer
    | Drop_receipt_bound_envelope
    | Drop_event_effect_readback
    | Add_raw_host
    | Add_raw_path
    | Add_environment
    | Add_executable
    | Add_probe_callback
    | Promote_unavailable_evidence
    | Add_current_constructor

  let drop name fields =
    List.filter (fun (observed, _) -> not (String.equal name observed)) fields

  let replace name value fields =
    List.map
      (fun ((observed, _) as field) ->
        if String.equal name observed then (name, value) else field)
      fields

  let source_digest_with_mutation mutation =
    let fields =
      match mutation with
      | Drop_runtime_manifest_source ->
          drop "runtime-manifest-source" source_fields
      | Drop_target_protocol_source ->
          drop "target-protocol-source" source_fields
      | Drop_action_kind_source -> drop "action-kind-source" source_fields
      | Drop_topology_source -> drop "topology-source" source_fields
      | Drop_runtime_declaration ->
          source_fields
          |> drop "runtime-declaration-key"
          |> drop "runtime-declaration-digest"
      | Substitute_runtime_declaration ->
          source_fields
          |> replace "runtime-declaration-key"
               (Jj_runtime_manifest.declaration_key
                  Jj_runtime_manifest.target_repository_source)
          |> replace "runtime-declaration-digest"
               (Jj_runtime_manifest.declaration_digest
                  Jj_runtime_manifest.target_repository_source)
      | Drop_target_protocol -> drop "target-protocol" source_fields
      | Drop_role -> replace "accepted-roles" "" source_fields
      | Add_role ->
          replace "accepted-roles"
            "observe-external-resource,observe-repository-source"
            source_fields
      | Drop_effect -> replace "accepted-effects" "" source_fields
      | Add_effect ->
          replace "accepted-effects"
            "external-resource-observation,repository-source-observation"
            source_fields
      | Drop_owner_part -> drop "target-owner-part" source_fields
      | Drop_resource_observer -> drop "resource-observer" source_fields
      | Drop_receipt_bound_envelope -> drop "resource-envelope" source_fields
      | Drop_event_effect_readback ->
          drop "event-effect-readback" source_fields
      | Add_raw_host -> replace "raw-host" "public-string" source_fields
      | Add_raw_path -> replace "raw-path" "public-string" source_fields
      | Add_environment -> replace "environment" "public-map" source_fields
      | Add_executable -> replace "executable" "public-string" source_fields
      | Add_probe_callback ->
          replace "probe-callback" "public-function" source_fields
      | Promote_unavailable_evidence ->
          replace "unavailable-evidence" "promoted-current" source_fields
      | Add_current_constructor ->
          replace "current-constructor" "public" source_fields
    in
    digest fields
end
