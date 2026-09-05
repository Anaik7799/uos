type owner = |
type registration = |
type current_receipt = |

type unavailable_prerequisite =
  | Target_owner_part_current
  | Approval_owner_current
  | Campaign_open_current_carrier
  | Request_bound_guard_current_carrier
  | Approval_nonce_transition_current
  | Dependency_carrier_owner_current
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

let runtime_declaration = Jj_runtime_manifest.target_approval
let target_protocol = Jj_target_protocol.Approval
let accepted_roles = [ Jj_action_kind.Consume_approval_nonce ]
let accepted_effects = [ Run_topology.Approval_nonce_consumption ]

let prerequisites =
  [ Target_owner_part_current; Approval_owner_current;
    Campaign_open_current_carrier; Request_bound_guard_current_carrier;
    Approval_nonce_transition_current; Dependency_carrier_owner_current;
    Event_effect_readback_current ]

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Approval_owner_current -> "approval-owner-current"
  | Campaign_open_current_carrier -> "campaign-open-current-carrier"
  | Request_bound_guard_current_carrier ->
      "request-bound-guard-current-carrier"
  | Approval_nonce_transition_current ->
      "approval-nonce-transition-current"
  | Dependency_carrier_owner_current ->
      "dependency-carrier-owner-current"
  | Event_effect_readback_current -> "event-effect-readback-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-jj-approval-target";
    origin = `Evidence }

let production_posture = `Implemented_unavailable
let create_owner_unavailable () = Error (List.map diagnostic prerequisites)

let role_ids = List.map Jj_action_kind.auxiliary_role_key accepted_roles
let effect_ids = List.map Run_topology.effect_kind_id accepted_effects
let prerequisite_ids = List.map prerequisite_id prerequisites

let runtime_declaration_id declaration =
  Jj_id.length_frame
    [ Jj_runtime_manifest.declaration_key declaration;
      Jj_runtime_manifest.declaration_digest declaration ]

let source_fields ~declaration ~target ~roles ~effects ~missing =
  [ ("schema", "ops-jj-approval-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("approval-owner-source", Dependability_approval.source_digest);
    ("runtime-declaration", declaration);
    ("target-protocol", target);
    ("accepted-roles", String.concat "," roles);
    ("accepted-effects", String.concat "," effects);
    ("missing-prerequisites", String.concat "," missing);
    ("public-key", "absent:owner-private");
    ("signature", "absent:owner-private");
    ("nonce", "absent:owner-private");
    ("capability", "absent:owner-resolved");
    ("callback", "absent");
    ("caller-digest", "rejected");
    ("current-constructor", "absent");
    ("production-posture", "implemented-unavailable") ]

let digest fields =
  fields
  |> List.map (fun (name, value) -> Jj_id.length_frame [ name; value ])
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let source_digest =
  source_fields ~declaration:(runtime_declaration_id runtime_declaration)
    ~target:(Jj_target_protocol.key target_protocol) ~roles:role_ids
    ~effects:effect_ids ~missing:prerequisite_ids
  |> digest

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_topology_source
    | Drop_approval_owner_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_role
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_prerequisite
    | Reorder_prerequisites
    | Substitute_prerequisite
    | Add_public_key
    | Add_signature
    | Add_nonce
    | Expose_capability
    | Add_callback
    | Accept_caller_digest
    | Add_current_constructor

  let drop_field name fields =
    List.filter
      (fun (candidate, _) -> not (String.equal candidate name))
      fields

  let replace_field name value fields =
    List.map
      (fun ((candidate, _) as field) ->
        if String.equal candidate name then (candidate, value) else field)
      fields

  let substitute_first before after values =
    let rec substitute = function
      | [] -> []
      | value :: rest when String.equal value before -> after :: rest
      | value :: rest -> value :: substitute rest
    in
    substitute values

  let source_digest_with_mutation mutation =
    let declaration, target, roles, effects, missing, mutate_fields =
      match mutation with
      | Drop_runtime_manifest_source ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, drop_field "runtime-manifest-source")
      | Drop_target_protocol_source ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, drop_field "target-protocol-source")
      | Drop_action_kind_source ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, drop_field "action-kind-source")
      | Drop_topology_source ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, drop_field "topology-source")
      | Drop_approval_owner_source ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, drop_field "approval-owner-source")
      | Drop_runtime_declaration ->
          ("", Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, Fun.id)
      | Substitute_runtime_declaration ->
          (runtime_declaration_id Jj_runtime_manifest.target_writer_lease,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, Fun.id)
      | Drop_target_protocol ->
          (runtime_declaration_id runtime_declaration, "", role_ids,
           effect_ids, prerequisite_ids, Fun.id)
      | Drop_role ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, [], effect_ids,
           prerequisite_ids, Fun.id)
      | Add_role ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol,
           role_ids @ [ "acquire-writer-lease" ], effect_ids,
           prerequisite_ids, Fun.id)
      | Drop_effect ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, [],
           prerequisite_ids, Fun.id)
      | Add_effect ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids,
           effect_ids @ [ "writer-lease-transition" ], prerequisite_ids,
           Fun.id)
      | Drop_prerequisite ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           (match prerequisite_ids with [] -> [] | _ :: rest -> rest), Fun.id)
      | Reorder_prerequisites ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           List.rev prerequisite_ids, Fun.id)
      | Substitute_prerequisite ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           substitute_first "request-bound-guard-current-carrier"
             "caller-selected-guard" prerequisite_ids,
           Fun.id)
      | Add_public_key ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, replace_field "public-key" "public-string")
      | Add_signature ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, replace_field "signature" "public-bytes")
      | Add_nonce ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, replace_field "nonce" "public-string")
      | Expose_capability ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, replace_field "capability" "public")
      | Add_callback ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, replace_field "callback" "public-function")
      | Accept_caller_digest ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, replace_field "caller-digest" "accepted")
      | Add_current_constructor ->
          (runtime_declaration_id runtime_declaration,
           Jj_target_protocol.key target_protocol, role_ids, effect_ids,
           prerequisite_ids, replace_field "current-constructor" "public")
    in
    source_fields ~declaration ~target ~roles ~effects ~missing
    |> mutate_fields |> digest
end
