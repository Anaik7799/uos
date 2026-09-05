type owner = |
type registration = |
type current_receipt = |

type unavailable_prerequisite =
  | Target_owner_part_current
  | Candidate_verification_operational_owner_current
  | Candidate_activation_current_carrier
  | Frozen_candidate_process_source_authority
  | Candidate_process_obligation_schema_current
  | Candidate_process_registry_current
  | Registered_candidate_executable_current
  | Candidate_configuration_current_carrier
  | Materialized_candidate_current_carrier
  | A1_candidate_plan_current_carrier
  | Candidate_suite_manifest_current_carrier
  | Approval_occurrence_capabilities_current
  | Receipt_bound_resource_envelope_current
  | Request_bound_candidate_step_current_carrier
  | Candidate_process_apply_once_current
  | Ordered_candidate_step_readback_current
  | Candidate_cleanup_eligibility_current
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

let runtime_declaration = Jj_runtime_manifest.target_candidate_verification
let target_protocol = Jj_target_protocol.Candidate_verification
let grouping_roles = [ Jj_action_kind.Verify_candidate_tree ]
let accepted_steps = Jj_action_kind.candidate_steps
let accepted_effects = [ Run_topology.Candidate_tree_verification ]

let binding_ids =
  [ "candidate:toolchain-check->candidate-tree-verification";
    "candidate:jj-reverse-cone->candidate-tree-verification";
    "candidate:jj-live-campaign->candidate-tree-verification";
    "candidate:jj-formal-receipt-validation->candidate-tree-verification";
    "candidate:jj-precompletion-readback->candidate-tree-verification" ]

let prerequisites =
  [ Target_owner_part_current;
    Candidate_verification_operational_owner_current;
    Candidate_activation_current_carrier;
    Frozen_candidate_process_source_authority;
    Candidate_process_obligation_schema_current;
    Candidate_process_registry_current;
    Registered_candidate_executable_current;
    Candidate_configuration_current_carrier;
    Materialized_candidate_current_carrier;
    A1_candidate_plan_current_carrier;
    Candidate_suite_manifest_current_carrier;
    Approval_occurrence_capabilities_current;
    Receipt_bound_resource_envelope_current;
    Request_bound_candidate_step_current_carrier;
    Candidate_process_apply_once_current;
    Ordered_candidate_step_readback_current;
    Candidate_cleanup_eligibility_current;
    Dependency_carrier_owner_current;
    Effect_target_registration_current;
    Event_effect_readback_current ]

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Candidate_verification_operational_owner_current ->
      "candidate-verification-operational-owner-current"
  | Candidate_activation_current_carrier ->
      "candidate-activation-current-carrier"
  | Frozen_candidate_process_source_authority ->
      "frozen-candidate-process-source-authority"
  | Candidate_process_obligation_schema_current ->
      "candidate-process-obligation-schema-current"
  | Candidate_process_registry_current ->
      "candidate-process-registry-current"
  | Registered_candidate_executable_current ->
      "registered-candidate-executable-current"
  | Candidate_configuration_current_carrier ->
      "candidate-configuration-current-carrier"
  | Materialized_candidate_current_carrier ->
      "materialized-candidate-current-carrier"
  | A1_candidate_plan_current_carrier ->
      "a1-candidate-plan-current-carrier"
  | Candidate_suite_manifest_current_carrier ->
      "candidate-suite-manifest-current-carrier"
  | Approval_occurrence_capabilities_current ->
      "approval-occurrence-capabilities-current"
  | Receipt_bound_resource_envelope_current ->
      "receipt-bound-resource-envelope-current"
  | Request_bound_candidate_step_current_carrier ->
      "request-bound-candidate-step-current-carrier"
  | Candidate_process_apply_once_current ->
      "candidate-process-apply-once-current"
  | Ordered_candidate_step_readback_current ->
      "ordered-candidate-step-readback-current"
  | Candidate_cleanup_eligibility_current ->
      "candidate-cleanup-eligibility-current"
  | Dependency_carrier_owner_current ->
      "dependency-carrier-owner-current"
  | Effect_target_registration_current ->
      "effect-target-registration-current"
  | Event_effect_readback_current -> "event-effect-readback-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-candidate-tree-verification-target";
    origin = `Evidence }

let production_posture = `Implemented_unavailable
let create_owner_unavailable () = Error (List.map diagnostic prerequisites)

let grouping_role_ids =
  List.map Jj_action_kind.auxiliary_role_key grouping_roles
let step_ids = List.map Jj_action_kind.candidate_step_key accepted_steps
let effect_ids = List.map Run_topology.effect_kind_id accepted_effects
let prerequisite_ids = List.map prerequisite_id prerequisites

let runtime_declaration_id declaration =
  Jj_id.length_frame
    [ Jj_runtime_manifest.declaration_key declaration;
      Jj_runtime_manifest.declaration_digest declaration ]

let target_registry_schema_digest =
  Run_effect_authority.canonical_jj_target_registry_schema ()
  |> Run_effect_authority.jj_target_registry_schema_digest

let source_fields ~declaration ~target ~grouping_roles ~steps ~effects
    ~bindings ~missing =
  [ ("schema", "ops-candidate-tree-verification-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("process-protocol-source", Jj_process_protocol.source_digest);
    ("dependency-schema-source", Jj_dependency_schema.source_digest);
    ("campaign-action-source", Jj_campaign_action.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("dependability-process-protocol-source",
     Dependability_process_protocol.source_digest);
    ("runtime-core-source", Run_jj_runtime_core.source_digest);
    ("filesystem-materialization-source",
     Ops_filesystem_materialization_target.source_digest);
    ("dependency-authority-source", Run_dependency_authority.source_digest);
    ("swarm-preparation-source", Run_swarm_preparation.source_digest);
    ("event-prefix-source", Run_event_store.event_prefix_source_digest);
    ("target-registry-schema", target_registry_schema_digest);
    ("runtime-declaration", declaration);
    ("target-protocol", target);
    ("grouping-role-order", String.concat "," grouping_roles);
    ("candidate-step-order", String.concat "," steps);
    ("accepted-effect-order", String.concat "," effects);
    ("step-effect-binding-order", String.concat "," bindings);
    ("missing-prerequisites", String.concat "," missing);
    ("grouping-role-contract", "nonexecuting-target-identity-only");
    ("candidate-process-action-count", "5");
    ("materialized-candidate-gate", "exact-current-required");
    ("a1-plan-gate", "exact-current-required");
    ("suite-manifest-gate", "exact-current-required");
    ("approval-occurrence-gate", "one-current-capability-per-step");
    ("resource-preflight-gate", "receipt-bound-current-required");
    ("candidate-configuration-gate", "exact-current-required");
    ("registered-executable-gate", "exact-current-required");
    ("failed-step-policy", "stop-before-later-steps");
    ("cleanup-gate", "fifth-step-terminal-required");
    ("candidate-binding", "exact");
    ("activity-binding", "exact");
    ("changed-replay", "absorbing-conflict");
    ("production-activation", "rejected");
    ("production-authority", "rejected");
    ("raw-argv", "absent");
    ("executable-path", "absent");
    ("cwd-or-path", "absent");
    ("environment", "absent");
    ("process-request-or-handle", "absent");
    ("callback-or-caller-digest", "absent:rejected");
    ("capability-serialization", "forbidden");
    ("current-authority", "unconstructible");
    ("production-posture", "implemented-unavailable") ]

let digest fields =
  fields
  |> List.map (fun (name, value) -> Jj_id.length_frame [ name; value ])
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let source_digest =
  source_fields ~declaration:(runtime_declaration_id runtime_declaration)
    ~target:(Jj_target_protocol.key target_protocol)
    ~grouping_roles:grouping_role_ids ~steps:step_ids ~effects:effect_ids
    ~bindings:binding_ids ~missing:prerequisite_ids
  |> digest

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_process_protocol_source
    | Drop_dependency_schema_source
    | Drop_campaign_action_source
    | Drop_topology_source
    | Drop_dependability_process_protocol_source
    | Drop_runtime_core_source
    | Drop_filesystem_materialization_source
    | Drop_dependency_authority_source
    | Drop_swarm_preparation_source
    | Drop_event_prefix_source
    | Drop_target_registry_schema
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Substitute_jujutsu_protocol
    | Drop_grouping_role
    | Add_auxiliary_role
    | Drop_toolchain_step
    | Drop_reverse_cone_step
    | Drop_live_campaign_step
    | Drop_formal_receipt_validation_step
    | Drop_precompletion_readback_step
    | Reorder_steps
    | Duplicate_step
    | Interpose_formal_step
    | Add_sixth_candidate_step
    | Promote_grouping_role_to_process_action
    | Drop_effect
    | Substitute_process_attempt_effect
    | Add_effect
    | Drop_toolchain_binding
    | Drop_reverse_cone_binding
    | Drop_live_campaign_binding
    | Drop_formal_receipt_validation_binding
    | Drop_precompletion_readback_binding
    | Reorder_bindings
    | Duplicate_binding
    | Swap_toolchain_precompletion_bindings
    | Add_grouping_role_effect_binding
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_without_materialized_candidate
    | Permit_without_a1_plan
    | Permit_without_suite_manifest
    | Permit_without_approval_occurrence
    | Permit_without_resource_preflight
    | Permit_without_candidate_configuration
    | Permit_without_registered_executable
    | Permit_continue_after_failed_step
    | Permit_cleanup_before_fifth_terminal
    | Permit_cross_candidate
    | Permit_cross_activity
    | Permit_changed_replay
    | Accept_production_activation
    | Accept_forbidden_production_authority
    | Accept_raw_argv
    | Accept_executable_path
    | Accept_cwd_or_path
    | Accept_environment
    | Expose_process_request_or_handle
    | Add_callback_or_caller_digest
    | Serialize_capability
    | Forge_current_authority

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
      ?(grouping_roles = grouping_role_ids) ?(steps = step_ids)
      ?(effects = effect_ids) ?(bindings = binding_ids)
      ?(missing = prerequisite_ids) ?(mutate = Fun.id) () =
    source_fields ~declaration ~target ~grouping_roles ~steps ~effects
      ~bindings ~missing
    |> mutate |> digest

  let toolchain_binding =
    "candidate:toolchain-check->candidate-tree-verification"
  let precompletion_binding =
    "candidate:jj-precompletion-readback->candidate-tree-verification"

  let source_digest_with_mutation = function
    | Drop_runtime_manifest_source ->
        compose ~mutate:(drop_field "runtime-manifest-source") ()
    | Drop_target_protocol_source ->
        compose ~mutate:(drop_field "target-protocol-source") ()
    | Drop_action_kind_source ->
        compose ~mutate:(drop_field "action-kind-source") ()
    | Drop_process_protocol_source ->
        compose ~mutate:(drop_field "process-protocol-source") ()
    | Drop_dependency_schema_source ->
        compose ~mutate:(drop_field "dependency-schema-source") ()
    | Drop_campaign_action_source ->
        compose ~mutate:(drop_field "campaign-action-source") ()
    | Drop_topology_source -> compose ~mutate:(drop_field "topology-source") ()
    | Drop_dependability_process_protocol_source ->
        compose
          ~mutate:(drop_field "dependability-process-protocol-source")
          ()
    | Drop_runtime_core_source ->
        compose ~mutate:(drop_field "runtime-core-source") ()
    | Drop_filesystem_materialization_source ->
        compose ~mutate:(drop_field "filesystem-materialization-source") ()
    | Drop_dependency_authority_source ->
        compose ~mutate:(drop_field "dependency-authority-source") ()
    | Drop_swarm_preparation_source ->
        compose ~mutate:(drop_field "swarm-preparation-source") ()
    | Drop_event_prefix_source ->
        compose ~mutate:(drop_field "event-prefix-source") ()
    | Drop_target_registry_schema ->
        compose ~mutate:(drop_field "target-registry-schema") ()
    | Drop_runtime_declaration -> compose ~declaration:"" ()
    | Substitute_runtime_declaration ->
        compose
          ~declaration:(runtime_declaration_id Jj_runtime_manifest.target_jj)
          ()
    | Drop_target_protocol -> compose ~target:"" ()
    | Substitute_jujutsu_protocol -> compose ~target:"jujutsu" ()
    | Drop_grouping_role -> compose ~grouping_roles:[] ()
    | Add_auxiliary_role ->
        compose ~grouping_roles:(grouping_role_ids @ [ "execute-jj-process" ])
          ()
    | Drop_toolchain_step ->
        compose ~steps:(without "toolchain-check" step_ids) ()
    | Drop_reverse_cone_step ->
        compose ~steps:(without "jj-reverse-cone" step_ids) ()
    | Drop_live_campaign_step ->
        compose ~steps:(without "jj-live-campaign" step_ids) ()
    | Drop_formal_receipt_validation_step ->
        compose ~steps:(without "jj-formal-receipt-validation" step_ids) ()
    | Drop_precompletion_readback_step ->
        compose ~steps:(without "jj-precompletion-readback" step_ids) ()
    | Reorder_steps -> compose ~steps:(List.rev step_ids) ()
    | Duplicate_step -> compose ~steps:(List.hd step_ids :: step_ids) ()
    | Interpose_formal_step ->
        compose
          ~steps:
            (match step_ids with
             | first :: rest -> first :: "formal:gospel" :: rest
             | [] -> [ "formal:gospel" ])
          ()
    | Add_sixth_candidate_step ->
        compose ~steps:(step_ids @ [ "candidate-summary" ]) ()
    | Promote_grouping_role_to_process_action ->
        compose
          ~mutate:
            (replace_field "grouping-role-contract" "sixth-process-action")
          ()
    | Drop_effect -> compose ~effects:[] ()
    | Substitute_process_attempt_effect ->
        compose ~effects:[ "process-attempt" ] ()
    | Add_effect ->
        compose ~effects:(effect_ids @ [ "formal-oracle-execution" ]) ()
    | Drop_toolchain_binding ->
        compose ~bindings:(without toolchain_binding binding_ids) ()
    | Drop_reverse_cone_binding ->
        compose
          ~bindings:
            (without
               "candidate:jj-reverse-cone->candidate-tree-verification"
               binding_ids)
          ()
    | Drop_live_campaign_binding ->
        compose
          ~bindings:
            (without
               "candidate:jj-live-campaign->candidate-tree-verification"
               binding_ids)
          ()
    | Drop_formal_receipt_validation_binding ->
        compose
          ~bindings:
            (without
               "candidate:jj-formal-receipt-validation->candidate-tree-verification"
               binding_ids)
          ()
    | Drop_precompletion_readback_binding ->
        compose ~bindings:(without precompletion_binding binding_ids) ()
    | Reorder_bindings -> compose ~bindings:(List.rev binding_ids) ()
    | Duplicate_binding ->
        compose ~bindings:(List.hd binding_ids :: binding_ids) ()
    | Swap_toolchain_precompletion_bindings ->
        compose
          ~bindings:
            (List.map
               (fun binding ->
                 if String.equal binding toolchain_binding then
                   "candidate:toolchain-check->jj-precompletion-readback"
                 else if String.equal binding precompletion_binding then
                   "candidate:jj-precompletion-readback->toolchain-check"
                 else binding)
               binding_ids)
          ()
    | Add_grouping_role_effect_binding ->
        compose
          ~bindings:
            (binding_ids
             @ [ "auxiliary:verify-candidate-tree->candidate-tree-verification" ])
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
            (replace_value "registered-candidate-executable-current"
               "caller-executable-current" prerequisite_ids)
          ()
    | Permit_without_materialized_candidate ->
        compose ~mutate:(replace_field "materialized-candidate-gate" "omitted")
          ()
    | Permit_without_a1_plan ->
        compose ~mutate:(replace_field "a1-plan-gate" "omitted") ()
    | Permit_without_suite_manifest ->
        compose ~mutate:(replace_field "suite-manifest-gate" "omitted") ()
    | Permit_without_approval_occurrence ->
        compose ~mutate:(replace_field "approval-occurrence-gate" "omitted") ()
    | Permit_without_resource_preflight ->
        compose ~mutate:(replace_field "resource-preflight-gate" "omitted") ()
    | Permit_without_candidate_configuration ->
        compose
          ~mutate:(replace_field "candidate-configuration-gate" "omitted")
          ()
    | Permit_without_registered_executable ->
        compose ~mutate:(replace_field "registered-executable-gate" "omitted")
          ()
    | Permit_continue_after_failed_step ->
        compose ~mutate:(replace_field "failed-step-policy" "continue") ()
    | Permit_cleanup_before_fifth_terminal ->
        compose ~mutate:(replace_field "cleanup-gate" "early-permitted") ()
    | Permit_cross_candidate ->
        compose ~mutate:(replace_field "candidate-binding" "any") ()
    | Permit_cross_activity ->
        compose ~mutate:(replace_field "activity-binding" "any") ()
    | Permit_changed_replay ->
        compose ~mutate:(replace_field "changed-replay" "stable") ()
    | Accept_production_activation ->
        compose ~mutate:(replace_field "production-activation" "accepted") ()
    | Accept_forbidden_production_authority ->
        compose ~mutate:(replace_field "production-authority" "accepted") ()
    | Accept_raw_argv ->
        compose ~mutate:(replace_field "raw-argv" "accepted") ()
    | Accept_executable_path ->
        compose ~mutate:(replace_field "executable-path" "accepted") ()
    | Accept_cwd_or_path ->
        compose ~mutate:(replace_field "cwd-or-path" "accepted") ()
    | Accept_environment ->
        compose ~mutate:(replace_field "environment" "accepted") ()
    | Expose_process_request_or_handle ->
        compose ~mutate:(replace_field "process-request-or-handle" "present") ()
    | Add_callback_or_caller_digest ->
        compose
          ~mutate:(replace_field "callback-or-caller-digest" "present:accepted")
          ()
    | Serialize_capability ->
        compose ~mutate:(replace_field "capability-serialization" "allowed") ()
    | Forge_current_authority ->
        compose ~mutate:(replace_field "current-authority" "constructible") ()
end
