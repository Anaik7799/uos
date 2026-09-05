(** Fail-closed Task-9 mutation-frontier target foundation.

    Only the pure declaration, routing, terminal-readback-family, and absent
    prerequisite denominators are constructible.  Owner, registration, and
    Current receipt remain abstract and unconstructible.  This interface
    exposes no frontier setter, target callback, raw frontier value, caller
    digest, capability projection, registration constructor, or Current
    constructor. *)

type owner
type registration
type current_receipt

type terminal_readback_family =
  | Normal_b
  | B_selected_recovery
  | B_restarted_recovery
  | Completion_record
  | Completion_record_selected_recovery
  | Completion_record_restarted_recovery
  | Completion_final
  | Completion_reconcile_applied_exact
  | Completion_reconcile_not_applied

val terminal_readback_families : terminal_readback_family list
val terminal_readback_family_id : terminal_readback_family -> string

type unavailable_prerequisite =
  | Target_owner_part_current
  | Mutation_frontier_operational_owner_current
  | Activity_generation_current_carrier
  | Approval_occurrence_capability_current
  | Writer_fence_session_current_carrier
  | Normal_b_terminal_readback_current_carrier
  | B_selected_recovery_terminal_readback_current_carrier
  | B_restarted_recovery_terminal_readback_current_carrier
  | Completion_record_terminal_readback_current_carrier
  | Completion_record_selected_recovery_terminal_readback_current_carrier
  | Completion_record_restarted_recovery_terminal_readback_current_carrier
  | Completion_final_terminal_readback_current_carrier
  | Completion_reconcile_applied_exact_terminal_readback_current_carrier
  | Completion_reconcile_not_applied_terminal_readback_current_carrier
  | Monotone_frontier_store_current
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
  Jj_runtime_manifest.target_mutation_frontier
    Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val accepted_roles : Jj_action_kind.auxiliary_role list
val accepted_frontiers : Jj_action_kind.frontier_action list
val accepted_effects : Run_topology.effect_kind list

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]

val create_owner_unavailable : unit -> (owner, diagnostic list) result
(** Returns the complete ordered missing-prerequisite denominator and creates
    no owner, registration, frontier transition, or Current receipt. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_campaign_action_source
    | Drop_recovery_schema_source
    | Drop_topology_source
    | Drop_approval_source
    | Drop_writer_lease_source
    | Drop_root_bootstrap_source
    | Drop_conditional_authority_source
    | Drop_dependency_authority_source
    | Drop_event_prefix_source
    | Drop_runtime_current_protocol_source
    | Drop_runtime_registry_source
    | Drop_target_registry_schema
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Substitute_transition_protocol
    | Add_auxiliary_role
    | Drop_frontier_action
    | Substitute_activation_frontier
    | Add_frontier_action
    | Drop_effect
    | Substitute_activation_effect
    | Add_effect
    | Drop_terminal_readback_family
    | Reorder_terminal_readback_families
    | Duplicate_terminal_readback_family
    | Add_diverged_terminal_readback_family
    | Merge_b_selected_restarted
    | Merge_record_selected_restarted
    | Merge_reconcile_outcomes
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_early_terminal_frontier
    | Permit_missing_readback
    | Permit_noncontiguous_readback_prefix
    | Permit_cross_target_capability
    | Permit_cross_activity_capability
    | Permit_cross_generation_capability
    | Permit_cross_session_fence
    | Permit_activation_through_frontier
    | Permit_branch_selection
    | Permit_fence_release
    | Permit_completion_finalize
    | Permit_repository_effect
    | Permit_process_effect
    | Permit_filesystem_effect
    | Permit_frontier_regression
    | Permit_changed_replay
    | Accept_raw_frontier_state
    | Expose_capability
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Promote_unavailable_owner

  val source_digest_with_mutation : source_mutation -> string
end
