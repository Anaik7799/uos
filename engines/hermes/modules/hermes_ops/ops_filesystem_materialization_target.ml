type owner = |
type registration = |
type current_receipt = |

type unavailable_prerequisite =
  | Target_owner_part_current
  | Filesystem_materialization_operational_owner_current
  | Descriptor_relative_filesystem_backend_current
  | Owner_held_root_directory_current_carrier
  | Resolve_beneath_no_xdev_current_carrier
  | Action_bound_materialization_intent_current_carrier
  | Authority_role_session_fence
  | Approval_occurrence_capability_current
  | Writer_fence_session_current_carrier
  | Activity_generation_current_carrier
  | Source_change_transition_commitment_current_carrier
  | Mutation_frontier_may_have_applied_current
  | Bounded_clock_current_carrier
  | Prefix_journal_apply_once_current
  | Recovery_vault_purpose_capability_current
  | Recovery_vault_sealed_object_set_current
  | Sealed_record_allowlist_current_carrier
  | Exact_preimage_candidate_metadata_current_carrier
  | Terminal_readback_cleanup_eligibility_current
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

let runtime_declaration =
  Jj_runtime_manifest.target_filesystem_materialization
let target_protocol = Jj_target_protocol.Filesystem_materialization
let accepted_roles =
  [ Jj_action_kind.Materialize_candidate;
    Jj_action_kind.Write_partition;
    Jj_action_kind.Restore_partition;
    Jj_action_kind.Restore_sealed_record_preimage;
    Jj_action_kind.Write_sealed_record_candidate;
    Jj_action_kind.Remove_disposable_scope ]
let accepted_effects = [ Run_topology.Controlled_filesystem_materialization ]

let binding_ids =
  [ "auxiliary:materialize-candidate->controlled-filesystem-materialization";
    "auxiliary:write-partition->controlled-filesystem-materialization";
    "auxiliary:restore-partition->controlled-filesystem-materialization";
    "auxiliary:restore-sealed-record-preimage->controlled-filesystem-materialization";
    "auxiliary:write-sealed-record-candidate->controlled-filesystem-materialization";
    "auxiliary:remove-disposable-scope->controlled-filesystem-materialization" ]

let role_precondition_ids =
  [ "materialize-candidate:target-absent";
    "write-partition:target-present";
    "restore-partition:target-present";
    "restore-sealed-record-preimage:target-present";
    "write-sealed-record-candidate:target-absent";
    "remove-disposable-scope:target-present" ]

let prerequisites =
  [ Target_owner_part_current;
    Filesystem_materialization_operational_owner_current;
    Descriptor_relative_filesystem_backend_current;
    Owner_held_root_directory_current_carrier;
    Resolve_beneath_no_xdev_current_carrier;
    Action_bound_materialization_intent_current_carrier;
    Authority_role_session_fence;
    Approval_occurrence_capability_current;
    Writer_fence_session_current_carrier;
    Activity_generation_current_carrier;
    Source_change_transition_commitment_current_carrier;
    Mutation_frontier_may_have_applied_current;
    Bounded_clock_current_carrier;
    Prefix_journal_apply_once_current;
    Recovery_vault_purpose_capability_current;
    Recovery_vault_sealed_object_set_current;
    Sealed_record_allowlist_current_carrier;
    Exact_preimage_candidate_metadata_current_carrier;
    Terminal_readback_cleanup_eligibility_current;
    Dependency_carrier_owner_current;
    Effect_target_registration_current;
    Event_effect_readback_current ]

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Filesystem_materialization_operational_owner_current ->
      "filesystem-materialization-operational-owner-current"
  | Descriptor_relative_filesystem_backend_current ->
      "descriptor-relative-filesystem-backend-current"
  | Owner_held_root_directory_current_carrier ->
      "owner-held-root-directory-current-carrier"
  | Resolve_beneath_no_xdev_current_carrier ->
      "resolve-beneath-no-xdev-current-carrier"
  | Action_bound_materialization_intent_current_carrier ->
      "action-bound-materialization-intent-current-carrier"
  | Authority_role_session_fence -> "authority-role-session-fence"
  | Approval_occurrence_capability_current ->
      "approval-occurrence-capability-current"
  | Writer_fence_session_current_carrier ->
      "writer-fence-session-current-carrier"
  | Activity_generation_current_carrier ->
      "activity-generation-current-carrier"
  | Source_change_transition_commitment_current_carrier ->
      "source-change-transition-commitment-current-carrier"
  | Mutation_frontier_may_have_applied_current ->
      "mutation-frontier-may-have-applied-current"
  | Bounded_clock_current_carrier -> "bounded-clock-current-carrier"
  | Prefix_journal_apply_once_current ->
      "prefix-journal-apply-once-current"
  | Recovery_vault_purpose_capability_current ->
      "recovery-vault-purpose-capability-current"
  | Recovery_vault_sealed_object_set_current ->
      "recovery-vault-sealed-object-set-current"
  | Sealed_record_allowlist_current_carrier ->
      "sealed-record-allowlist-current-carrier"
  | Exact_preimage_candidate_metadata_current_carrier ->
      "exact-preimage-candidate-metadata-current-carrier"
  | Terminal_readback_cleanup_eligibility_current ->
      "terminal-readback-cleanup-eligibility-current"
  | Dependency_carrier_owner_current ->
      "dependency-carrier-owner-current"
  | Effect_target_registration_current ->
      "effect-target-registration-current"
  | Event_effect_readback_current -> "event-effect-readback-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-filesystem-materialization-target";
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

let target_registry_schema_digest =
  Run_effect_authority.canonical_jj_target_registry_schema ()
  |> Run_effect_authority.jj_target_registry_schema_digest

let source_fields ~declaration ~target ~roles ~effects ~bindings
    ~preconditions ~missing =
  [ ("schema", "ops-filesystem-materialization-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("dependency-schema-source", Jj_dependency_schema.source_digest);
    ("campaign-action-source", Jj_campaign_action.source_digest);
    ("recovery-schema-source", Jj_recovery_schema.source_digest);
    ("partition-source", Jj_partition.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("filesystem-source", Dependability_filesystem.source_digest);
    ("recovery-vault-source", Dependability_recovery_vault.source_digest);
    ("writer-lease-source", Dependability_writer_lease.source_digest);
    ("root-bootstrap-source", Run_root_bootstrap.source_digest);
    ("dependency-authority-source", Run_dependency_authority.source_digest);
    ("swarm-preparation-source", Run_swarm_preparation.source_digest);
    ("event-prefix-source", Run_event_store.event_prefix_source_digest);
    ("target-registry-schema", target_registry_schema_digest);
    ("runtime-declaration", declaration);
    ("target-protocol", target);
    ("accepted-role-order", String.concat "," roles);
    ("accepted-effect-order", String.concat "," effects);
    ("action-effect-binding-order", String.concat "," bindings);
    ("role-precondition-order", String.concat "," preconditions);
    ("missing-prerequisites", String.concat "," missing);
    ("descriptor-backend-gate", "owner-held-current-required");
    ("owner-root-gate", "descriptor-root-current-required");
    ("approval-gate", "occurrence-capability-current-required");
    ("writer-fence-gate", "exact-session-current-required");
    ("mutation-frontier-gate", "may-have-applied-before-entry-required");
    ("apply-once-journal-gate", "prefix-current-required");
    ("role-precondition-enforcement", "exact");
    ("vault-purpose-binding", "exact-b-success-or-completion-record");
    ("activity-binding", "exact");
    ("generation-binding", "exact");
    ("record-write-seal", "sealed-candidate-required");
    ("record-restore-seal", "sealed-preimage-required");
    ("present-absent-binding", "exact");
    ("mode-symlink-binding", "exact");
    ("cleanup-terminal-readback-gate", "exact-current-required");
    ("changed-replay", "absorbing-conflict");
    ("raw-path", "absent");
    ("raw-bytes", "absent");
    ("filesystem-handle-projection", "absent");
    ("recovery-vault-capability-projection", "absent");
    ("callback", "absent");
    ("caller-digest", "rejected");
    ("registration-constructor", "absent");
    ("current-constructor", "absent");
    ("descriptor-backend", "implemented-unavailable");
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
    ~preconditions:role_precondition_ids ~missing:prerequisite_ids
  |> digest

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_dependency_schema_source
    | Drop_campaign_action_source
    | Drop_recovery_schema_source
    | Drop_partition_source
    | Drop_topology_source
    | Drop_filesystem_source
    | Drop_recovery_vault_source
    | Drop_writer_lease_source
    | Drop_root_bootstrap_source
    | Drop_dependency_authority_source
    | Drop_swarm_preparation_source
    | Drop_event_prefix_source
    | Drop_target_registry_schema
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Substitute_transition_protocol
    | Drop_materialize_candidate_role
    | Drop_write_partition_role
    | Drop_restore_partition_role
    | Drop_restore_sealed_record_preimage_role
    | Drop_write_sealed_record_candidate_role
    | Drop_remove_disposable_scope_role
    | Reorder_roles
    | Add_stage_recovery_set_role
    | Drop_effect
    | Substitute_candidate_verification_effect
    | Add_effect
    | Drop_materialize_candidate_binding
    | Drop_write_partition_binding
    | Drop_restore_partition_binding
    | Drop_restore_sealed_record_preimage_binding
    | Drop_write_sealed_record_candidate_binding
    | Drop_remove_disposable_scope_binding
    | Reorder_bindings
    | Duplicate_binding
    | Merge_partition_write_restore
    | Merge_record_write_restore
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_without_descriptor_backend
    | Permit_without_owner_root
    | Permit_without_approval
    | Permit_without_writer_fence
    | Permit_without_mutation_frontier
    | Permit_without_apply_once_journal
    | Permit_wrong_role_precondition
    | Permit_cross_purpose_vault
    | Permit_cross_activity_materialization
    | Permit_cross_generation_materialization
    | Permit_unsealed_record_write
    | Permit_unsealed_record_restore
    | Permit_present_absent_mismatch
    | Permit_mode_or_symlink_mismatch
    | Permit_cleanup_before_terminal_readback
    | Permit_changed_replay
    | Accept_raw_path
    | Accept_raw_bytes
    | Expose_filesystem_handle
    | Expose_recovery_vault_capability
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Promote_unavailable_backend

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
      ?(bindings = binding_ids) ?(preconditions = role_precondition_ids)
      ?(missing = prerequisite_ids) ?(mutate = Fun.id) () =
    source_fields ~declaration ~target ~roles ~effects ~bindings
      ~preconditions ~missing
    |> mutate |> digest

  let source_digest_with_mutation = function
    | Drop_runtime_manifest_source ->
        compose ~mutate:(drop_field "runtime-manifest-source") ()
    | Drop_target_protocol_source ->
        compose ~mutate:(drop_field "target-protocol-source") ()
    | Drop_action_kind_source ->
        compose ~mutate:(drop_field "action-kind-source") ()
    | Drop_dependency_schema_source ->
        compose ~mutate:(drop_field "dependency-schema-source") ()
    | Drop_campaign_action_source ->
        compose ~mutate:(drop_field "campaign-action-source") ()
    | Drop_recovery_schema_source ->
        compose ~mutate:(drop_field "recovery-schema-source") ()
    | Drop_partition_source ->
        compose ~mutate:(drop_field "partition-source") ()
    | Drop_topology_source -> compose ~mutate:(drop_field "topology-source") ()
    | Drop_filesystem_source ->
        compose ~mutate:(drop_field "filesystem-source") ()
    | Drop_recovery_vault_source ->
        compose ~mutate:(drop_field "recovery-vault-source") ()
    | Drop_writer_lease_source ->
        compose ~mutate:(drop_field "writer-lease-source") ()
    | Drop_root_bootstrap_source ->
        compose ~mutate:(drop_field "root-bootstrap-source") ()
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
          ~declaration:
            (runtime_declaration_id Jj_runtime_manifest.target_transition)
          ()
    | Drop_target_protocol -> compose ~target:"" ()
    | Substitute_transition_protocol -> compose ~target:"transition" ()
    | Drop_materialize_candidate_role ->
        compose ~roles:(without "materialize-candidate" role_ids) ()
    | Drop_write_partition_role ->
        compose ~roles:(without "write-partition" role_ids) ()
    | Drop_restore_partition_role ->
        compose ~roles:(without "restore-partition" role_ids) ()
    | Drop_restore_sealed_record_preimage_role ->
        compose
          ~roles:(without "restore-sealed-record-preimage" role_ids)
          ()
    | Drop_write_sealed_record_candidate_role ->
        compose
          ~roles:(without "write-sealed-record-candidate" role_ids)
          ()
    | Drop_remove_disposable_scope_role ->
        compose ~roles:(without "remove-disposable-scope" role_ids) ()
    | Reorder_roles -> compose ~roles:(List.rev role_ids) ()
    | Add_stage_recovery_set_role ->
        compose ~roles:(role_ids @ [ "stage-recovery-set" ]) ()
    | Drop_effect -> compose ~effects:[] ()
    | Substitute_candidate_verification_effect ->
        compose ~effects:[ "candidate-tree-verification" ] ()
    | Add_effect ->
        compose ~effects:(effect_ids @ [ "production-activation-transition" ])
          ()
    | Drop_materialize_candidate_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:materialize-candidate->controlled-filesystem-materialization"
               binding_ids)
          ()
    | Drop_write_partition_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:write-partition->controlled-filesystem-materialization"
               binding_ids)
          ()
    | Drop_restore_partition_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:restore-partition->controlled-filesystem-materialization"
               binding_ids)
          ()
    | Drop_restore_sealed_record_preimage_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:restore-sealed-record-preimage->controlled-filesystem-materialization"
               binding_ids)
          ()
    | Drop_write_sealed_record_candidate_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:write-sealed-record-candidate->controlled-filesystem-materialization"
               binding_ids)
          ()
    | Drop_remove_disposable_scope_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:remove-disposable-scope->controlled-filesystem-materialization"
               binding_ids)
          ()
    | Reorder_bindings -> compose ~bindings:(List.rev binding_ids) ()
    | Duplicate_binding ->
        compose ~bindings:(List.hd binding_ids :: binding_ids) ()
    | Merge_partition_write_restore ->
        compose
          ~bindings:
            (binding_ids
             |> without
                  "auxiliary:write-partition->controlled-filesystem-materialization"
             |> without
                  "auxiliary:restore-partition->controlled-filesystem-materialization"
             |> fun rest ->
             "auxiliary:partition-write-restore->controlled-filesystem-materialization"
             :: rest)
          ()
    | Merge_record_write_restore ->
        compose
          ~bindings:
            (binding_ids
             |> without
                  "auxiliary:restore-sealed-record-preimage->controlled-filesystem-materialization"
             |> without
                  "auxiliary:write-sealed-record-candidate->controlled-filesystem-materialization"
             |> fun rest ->
             "auxiliary:sealed-record-write-restore->controlled-filesystem-materialization"
             :: rest)
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
            (replace_value "descriptor-relative-filesystem-backend-current"
               "pathname-filesystem-backend-current" prerequisite_ids)
          ()
    | Permit_without_descriptor_backend ->
        compose ~mutate:(replace_field "descriptor-backend-gate" "omitted") ()
    | Permit_without_owner_root ->
        compose ~mutate:(replace_field "owner-root-gate" "omitted") ()
    | Permit_without_approval ->
        compose ~mutate:(replace_field "approval-gate" "omitted") ()
    | Permit_without_writer_fence ->
        compose ~mutate:(replace_field "writer-fence-gate" "omitted") ()
    | Permit_without_mutation_frontier ->
        compose ~mutate:(replace_field "mutation-frontier-gate" "omitted") ()
    | Permit_without_apply_once_journal ->
        compose ~mutate:(replace_field "apply-once-journal-gate" "omitted") ()
    | Permit_wrong_role_precondition ->
        compose
          ~preconditions:
            (replace_value "materialize-candidate:target-absent"
               "materialize-candidate:target-present" role_precondition_ids)
          ()
    | Permit_cross_purpose_vault ->
        compose ~mutate:(replace_field "vault-purpose-binding" "any") ()
    | Permit_cross_activity_materialization ->
        compose ~mutate:(replace_field "activity-binding" "any") ()
    | Permit_cross_generation_materialization ->
        compose ~mutate:(replace_field "generation-binding" "any") ()
    | Permit_unsealed_record_write ->
        compose ~mutate:(replace_field "record-write-seal" "optional") ()
    | Permit_unsealed_record_restore ->
        compose ~mutate:(replace_field "record-restore-seal" "optional") ()
    | Permit_present_absent_mismatch ->
        compose ~mutate:(replace_field "present-absent-binding" "ignored") ()
    | Permit_mode_or_symlink_mismatch ->
        compose ~mutate:(replace_field "mode-symlink-binding" "ignored") ()
    | Permit_cleanup_before_terminal_readback ->
        compose
          ~mutate:(replace_field "cleanup-terminal-readback-gate" "omitted")
          ()
    | Permit_changed_replay ->
        compose ~mutate:(replace_field "changed-replay" "stable") ()
    | Accept_raw_path ->
        compose ~mutate:(replace_field "raw-path" "accepted") ()
    | Accept_raw_bytes ->
        compose ~mutate:(replace_field "raw-bytes" "accepted") ()
    | Expose_filesystem_handle ->
        compose ~mutate:(replace_field "filesystem-handle-projection" "present")
          ()
    | Expose_recovery_vault_capability ->
        compose
          ~mutate:
            (replace_field "recovery-vault-capability-projection" "present")
          ()
    | Add_callback -> compose ~mutate:(replace_field "callback" "present") ()
    | Accept_caller_digest ->
        compose ~mutate:(replace_field "caller-digest" "accepted") ()
    | Add_registration_constructor ->
        compose ~mutate:(replace_field "registration-constructor" "present") ()
    | Add_current_constructor ->
        compose ~mutate:(replace_field "current-constructor" "present") ()
    | Promote_unavailable_backend ->
        compose ~mutate:(replace_field "descriptor-backend" "current") ()
end
