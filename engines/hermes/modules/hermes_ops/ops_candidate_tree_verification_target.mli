(** Fail-closed Task-9 candidate-tree verification target foundation.

    Exactly five Candidate-process steps are routable.  The sole auxiliary
    [Verify_candidate_tree] role is only their nonexecuting grouping/target
    identity and never creates a sixth action.  Owner, registration, and
    Current receipt remain abstract and unconstructible.  No executable,
    argv, cwd/path, environment, process request/handle, callback, capability,
    production authority, or Current operation is exposed. *)

type owner
type registration
type current_receipt

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
  Jj_runtime_manifest.target_candidate_verification
    Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val grouping_roles : Jj_action_kind.auxiliary_role list
val accepted_steps : Jj_action_kind.candidate_step list
val accepted_effects : Run_topology.effect_kind list
(* Exact ordered step-to-effect identities for source comparison only. *)
val binding_ids : string list

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]
val create_owner_unavailable : unit -> (owner, diagnostic list) result
(** Returns the complete ordered missing-prerequisite denominator and creates
    no owner, registration, process action, or Current receipt. *)

val source_digest : string

module For_test : sig
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

  val source_digest_with_mutation : source_mutation -> string
end
