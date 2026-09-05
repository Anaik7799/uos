type owner = |
type registration = |
type current_receipt = |

type unavailable_prerequisite =
  | Target_owner_part_current
  | Release_observation_operational_owner_current
  | Release_dependency_owner_allocation_current
  | Release_activation_least_authority_current
  | Release_request_current_carrier
  | Signed_release_ticket_current_carrier
  | Approval_occurrence_capabilities_current
  | Bounded_clock_current_carrier
  | External_resource_host_current
  | Controlled_release_bundle_observer_current
  | Release_pin_current_carrier
  | Release_tree_observation_current_carrier
  | Release_phase_projection_current
  | Dependency_carrier_owner_current
  | Effect_target_registration_current
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

let runtime_declaration = Jj_runtime_manifest.target_release
let target_protocol = Jj_target_protocol.Release
let accepted_roles = [ Jj_action_kind.Observe_release_bundle ]
let accepted_effects = [ Run_topology.Repository_source_observation ]
let binding_ids =
  [ "auxiliary:observe-release-bundle->repository-source-observation" ]

let release_phase_action_ids =
  [ "auxiliary:acquire-clock";
    "auxiliary:observe-external-resource";
    "auxiliary:observe-release-bundle";
    "auxiliary:observe-tree" ]

let activation_role_ids =
  [ "acquire-clock"; "observe-external-resource";
    "observe-release-bundle"; "observe-tree"; "consume-approval-nonce" ]

let prerequisites =
  [ Target_owner_part_current;
    Release_observation_operational_owner_current;
    Release_dependency_owner_allocation_current;
    Release_activation_least_authority_current;
    Release_request_current_carrier;
    Signed_release_ticket_current_carrier;
    Approval_occurrence_capabilities_current;
    Bounded_clock_current_carrier;
    External_resource_host_current;
    Controlled_release_bundle_observer_current;
    Release_pin_current_carrier;
    Release_tree_observation_current_carrier;
    Release_phase_projection_current;
    Dependency_carrier_owner_current;
    Effect_target_registration_current;
    Event_effect_readback_current ]

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Release_observation_operational_owner_current ->
      "release-observation-operational-owner-current"
  | Release_dependency_owner_allocation_current ->
      "release-dependency-owner-allocation-current"
  | Release_activation_least_authority_current ->
      "release-activation-least-authority-current"
  | Release_request_current_carrier -> "release-request-current-carrier"
  | Signed_release_ticket_current_carrier ->
      "signed-release-ticket-current-carrier"
  | Approval_occurrence_capabilities_current ->
      "approval-occurrence-capabilities-current"
  | Bounded_clock_current_carrier -> "bounded-clock-current-carrier"
  | External_resource_host_current -> "external-resource-host-current"
  | Controlled_release_bundle_observer_current ->
      "controlled-release-bundle-observer-current"
  | Release_pin_current_carrier -> "release-pin-current-carrier"
  | Release_tree_observation_current_carrier ->
      "release-tree-observation-current-carrier"
  | Release_phase_projection_current -> "release-phase-projection-current"
  | Dependency_carrier_owner_current ->
      "dependency-carrier-owner-current"
  | Effect_target_registration_current ->
      "effect-target-registration-current"
  | Event_effect_readback_current -> "event-effect-readback-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-jj-release-target";
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

let source_fields ~declaration ~target ~roles ~effects ~bindings
    ~phase_actions ~activation_roles ~missing =
  [ ("schema", "ops-jj-release-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("dependency-schema-source", Jj_dependency_schema.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("campaign-action-source", Jj_campaign_action.source_digest);
    ("approval-source", Jj_approval.source_digest);
    ("release-protocol-source", Jj_release_protocol.source_digest);
    ("source-manifest-source", Jj_source_manifest.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("runtime-declaration", declaration);
    ("target-protocol", target);
    ("accepted-role-order", String.concat "," roles);
    ("accepted-effect-order", String.concat "," effects);
    ("action-effect-binding-order", String.concat "," bindings);
    ("release-phase-action-order", String.concat "," phase_actions);
    ("activation-role-order", String.concat "," activation_roles);
    ("consume-role", "consume-approval-nonce");
    ("consume-law", "scoped-immediately-before-each-approved-occurrence");
    ("missing-prerequisites", String.concat "," missing);
    ("release-tag", "present-exact");
    ("release-tag-mobility", "immutable");
    ("release-commit", "exact");
    ("release-tree", "exact");
    ("release-archive", "exact");
    ("release-documentation", "exact");
    ("release-executable", "exact-provenance-required");
    ("release-config", "exact-isolated");
    ("release-license", "exact-current-required");
    ("release-ticket", "signed-current-required");
    ("release-ticket-expiry", "current-required");
    ("release-nonce-phase", "exact-release-phase");
    ("release-bundle-approval", "exact-approved");
    ("release-checkout", "operator-supplied-bundle-only");
    ("network-acquisition", "forbidden");
    ("source-bytes-projection", "absent");
    ("raw-path", "absent");
    ("raw-bundle-bytes", "absent");
    ("network", "absent");
    ("credential", "absent");
    ("process", "absent");
    ("repository-mutation", "absent");
    ("candidate-write", "absent");
    ("formal-execution", "absent");
    ("full-production-activation", "absent");
    ("callback", "absent");
    ("caller-digest", "rejected");
    ("registration-constructor", "absent");
    ("current-constructor", "absent");
    ("owner-promotion", "implemented-unavailable");
    ("redaction", "immutable-redacted-receipt-only");
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
    ~effects:effect_ids ~bindings:binding_ids
    ~phase_actions:release_phase_action_ids
    ~activation_roles:activation_role_ids ~missing:prerequisite_ids
  |> digest

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_dependency_schema_source
    | Drop_action_kind_source
    | Drop_campaign_action_source
    | Drop_approval_source
    | Drop_release_protocol_source
    | Drop_source_manifest_source
    | Drop_topology_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_role
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_binding
    | Substitute_binding_effect
    | Drop_release_phase_action
    | Reorder_release_phase_actions
    | Duplicate_release_phase_action
    | Add_release_phase_action
    | Drop_activation_role
    | Add_activation_role
    | Drop_consume_role
    | Permit_unscoped_consume
    | Replace_tree_with_object
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_missing_tag
    | Permit_moving_tag
    | Permit_commit_mismatch
    | Permit_tree_mismatch
    | Permit_archive_mismatch
    | Permit_documentation_mismatch
    | Permit_executable_mismatch
    | Permit_config_mismatch
    | Permit_missing_license
    | Permit_unsigned_ticket
    | Permit_expired_ticket
    | Permit_cross_phase_nonce
    | Permit_unapproved_bundle
    | Permit_inherited_checkout
    | Permit_network_acquisition
    | Permit_source_bytes_projection
    | Add_raw_path
    | Add_raw_bundle_bytes
    | Add_network
    | Add_credential
    | Add_process
    | Add_repository_mutation
    | Add_candidate_write
    | Add_formal_execution
    | Add_full_production_activation
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Promote_unavailable_owner

  let drop_field name fields =
    List.filter
      (fun (candidate, _) -> not (String.equal candidate name))
      fields

  let replace_field name value fields =
    List.map
      (fun ((candidate, _) as field) ->
        if String.equal candidate name then (candidate, value) else field)
      fields

  let without value values =
    List.filter (fun candidate -> not (String.equal candidate value)) values

  let replace_value before after values =
    List.map
      (fun value -> if String.equal value before then after else value)
      values

  let base_declaration = runtime_declaration_id runtime_declaration
  let base_target = Jj_target_protocol.key target_protocol

  let compose ?(declaration = base_declaration) ?(target = base_target)
      ?(roles = role_ids) ?(effects = effect_ids)
      ?(bindings = binding_ids) ?(phase_actions = release_phase_action_ids)
      ?(activation_roles = activation_role_ids)
      ?(missing = prerequisite_ids) ?(mutate = Fun.id) () =
    source_fields ~declaration ~target ~roles ~effects ~bindings
      ~phase_actions ~activation_roles ~missing
    |> mutate |> digest

  let source_digest_with_mutation = function
    | Drop_runtime_manifest_source ->
        compose ~mutate:(drop_field "runtime-manifest-source") ()
    | Drop_target_protocol_source ->
        compose ~mutate:(drop_field "target-protocol-source") ()
    | Drop_dependency_schema_source ->
        compose ~mutate:(drop_field "dependency-schema-source") ()
    | Drop_action_kind_source ->
        compose ~mutate:(drop_field "action-kind-source") ()
    | Drop_campaign_action_source ->
        compose ~mutate:(drop_field "campaign-action-source") ()
    | Drop_approval_source ->
        compose ~mutate:(drop_field "approval-source") ()
    | Drop_release_protocol_source ->
        compose ~mutate:(drop_field "release-protocol-source") ()
    | Drop_source_manifest_source ->
        compose ~mutate:(drop_field "source-manifest-source") ()
    | Drop_topology_source -> compose ~mutate:(drop_field "topology-source") ()
    | Drop_runtime_declaration -> compose ~declaration:"" ()
    | Substitute_runtime_declaration ->
        compose
          ~declaration:
            (runtime_declaration_id
               Jj_runtime_manifest.target_repository_source)
          ()
    | Drop_target_protocol -> compose ~target:"" ()
    | Drop_role -> compose ~roles:[] ()
    | Add_role ->
        compose ~roles:(role_ids @ [ "observe-repository-source" ]) ()
    | Drop_effect -> compose ~effects:[] ()
    | Add_effect ->
        compose ~effects:(effect_ids @ [ "external-resource-observation" ]) ()
    | Drop_binding -> compose ~bindings:[] ()
    | Substitute_binding_effect ->
        compose
          ~bindings:
            [ "auxiliary:observe-release-bundle->external-resource-observation" ]
          ()
    | Drop_release_phase_action ->
        compose
          ~phase_actions:
            (match release_phase_action_ids with [] -> [] | _ :: rest -> rest)
          ()
    | Reorder_release_phase_actions ->
        compose ~phase_actions:(List.rev release_phase_action_ids) ()
    | Duplicate_release_phase_action ->
        compose
          ~phase_actions:
            (List.hd release_phase_action_ids :: release_phase_action_ids)
          ()
    | Add_release_phase_action ->
        compose
          ~phase_actions:
            (release_phase_action_ids @ [ "jujutsu-operation:version" ])
          ()
    | Drop_activation_role ->
        compose ~activation_roles:(without "acquire-clock" activation_role_ids)
          ()
    | Add_activation_role ->
        compose
          ~activation_roles:(activation_role_ids @ [ "execute-jj-process" ])
          ()
    | Drop_consume_role ->
        compose
          ~activation_roles:
            (without "consume-approval-nonce" activation_role_ids)
          ()
    | Permit_unscoped_consume ->
        compose ~mutate:(replace_field "consume-law" "ambient-unscoped") ()
    | Replace_tree_with_object ->
        compose
          ~phase_actions:
            (replace_value "auxiliary:observe-tree"
               "auxiliary:observe-object" release_phase_action_ids)
          ()
    | Drop_prerequisite ->
        compose
          ~missing:(match prerequisite_ids with [] -> [] | _ :: rest -> rest)
          ()
    | Reorder_prerequisites -> compose ~missing:(List.rev prerequisite_ids) ()
    | Duplicate_prerequisite ->
        compose ~missing:(List.hd prerequisite_ids :: prerequisite_ids) ()
    | Substitute_prerequisite ->
        compose
          ~missing:
            (replace_value "release-activation-least-authority-current"
               "full-production-activation-current" prerequisite_ids)
          ()
    | Permit_missing_tag ->
        compose ~mutate:(replace_field "release-tag" "optional") ()
    | Permit_moving_tag ->
        compose ~mutate:(replace_field "release-tag-mobility" "moving") ()
    | Permit_commit_mismatch ->
        compose ~mutate:(replace_field "release-commit" "mismatch-permitted") ()
    | Permit_tree_mismatch ->
        compose ~mutate:(replace_field "release-tree" "mismatch-permitted") ()
    | Permit_archive_mismatch ->
        compose ~mutate:(replace_field "release-archive" "mismatch-permitted") ()
    | Permit_documentation_mismatch ->
        compose
          ~mutate:(replace_field "release-documentation" "mismatch-permitted")
          ()
    | Permit_executable_mismatch ->
        compose
          ~mutate:(replace_field "release-executable" "mismatch-permitted")
          ()
    | Permit_config_mismatch ->
        compose ~mutate:(replace_field "release-config" "mismatch-permitted")
          ()
    | Permit_missing_license ->
        compose ~mutate:(replace_field "release-license" "optional") ()
    | Permit_unsigned_ticket ->
        compose ~mutate:(replace_field "release-ticket" "unsigned-permitted") ()
    | Permit_expired_ticket ->
        compose ~mutate:(replace_field "release-ticket-expiry" "expired-permitted")
          ()
    | Permit_cross_phase_nonce ->
        compose ~mutate:(replace_field "release-nonce-phase" "any-phase") ()
    | Permit_unapproved_bundle ->
        compose ~mutate:(replace_field "release-bundle-approval" "optional") ()
    | Permit_inherited_checkout ->
        compose ~mutate:(replace_field "release-checkout" "inherited-permitted")
          ()
    | Permit_network_acquisition ->
        compose ~mutate:(replace_field "network-acquisition" "permitted") ()
    | Permit_source_bytes_projection ->
        compose ~mutate:(replace_field "source-bytes-projection" "present") ()
    | Add_raw_path -> compose ~mutate:(replace_field "raw-path" "present") ()
    | Add_raw_bundle_bytes ->
        compose ~mutate:(replace_field "raw-bundle-bytes" "present") ()
    | Add_network -> compose ~mutate:(replace_field "network" "present") ()
    | Add_credential ->
        compose ~mutate:(replace_field "credential" "present") ()
    | Add_process -> compose ~mutate:(replace_field "process" "present") ()
    | Add_repository_mutation ->
        compose ~mutate:(replace_field "repository-mutation" "present") ()
    | Add_candidate_write ->
        compose ~mutate:(replace_field "candidate-write" "present") ()
    | Add_formal_execution ->
        compose ~mutate:(replace_field "formal-execution" "present") ()
    | Add_full_production_activation ->
        compose ~mutate:(replace_field "full-production-activation" "present")
          ()
    | Add_callback -> compose ~mutate:(replace_field "callback" "present") ()
    | Accept_caller_digest ->
        compose ~mutate:(replace_field "caller-digest" "accepted") ()
    | Add_registration_constructor ->
        compose ~mutate:(replace_field "registration-constructor" "present") ()
    | Add_current_constructor ->
        compose ~mutate:(replace_field "current-constructor" "present") ()
    | Promote_unavailable_owner ->
        compose ~mutate:(replace_field "owner-promotion" "current") ()
end
