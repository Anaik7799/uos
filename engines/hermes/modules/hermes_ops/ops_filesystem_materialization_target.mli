(** Fail-closed Task-9 filesystem-materialization target foundation.

    Only the pure declaration, six-role routing, precondition, lifecycle, and
    unavailable-prerequisite identities are constructible.  Owner,
    registration, and Current receipt remain abstract and unconstructible.
    This interface exposes no native path, bytes, filesystem handle, recovery
    vault capability, callback, caller digest, register, materialize, restore,
    cleanup, or Current operation. *)

type owner
type registration
type current_receipt

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

type diagnostic = private {
  prerequisite : unavailable_prerequisite;
  message : string;
  coordinate : string;
  origin : [ `Evidence ];
}

val diagnostic_prerequisite : diagnostic -> unavailable_prerequisite
val diagnostic_message : diagnostic -> string
val diagnostic_coordinate : diagnostic -> string
val diagnostic_origin : diagnostic -> [ `Evidence ]

val runtime_declaration :
  Jj_runtime_manifest.target_filesystem_materialization
    Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val accepted_roles : Jj_action_kind.auxiliary_role list
val accepted_effects : Run_topology.effect_kind list
(* Exact ordered source-comparison identities.  They grant no target,
   filesystem, recovery-vault, or effect authority. *)
val binding_ids : string list
val role_precondition_ids : string list

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]
val create_owner_unavailable : unit -> (owner, diagnostic list) result
(** Returns the complete ordered missing-prerequisite denominator and creates
    no owner, registration, filesystem effect, or Current receipt. *)

val source_digest : string

module For_test : sig
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

  val source_digest_with_mutation : source_mutation -> string
end
