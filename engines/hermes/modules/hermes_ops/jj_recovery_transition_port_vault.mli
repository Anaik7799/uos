(** Fail-closed recovery-transition-port vault foundation.

    This module declares the exact single-use port lifecycle and binding
    denominator only.  [vault], [resolver], [retained_port], and
    [current_reference] are abstract and unconstructible.  No preparation,
    resolution, application, closure, reconciliation, capability, store,
    callback, serialization, repository, filesystem, completion, or parity
    authority is exposed while the ordered prerequisites remain absent. *)

type vault
type resolver
type retained_port
type current_reference

type lifecycle_state =
  | Prepared
  | Applied
  | Diverged
  | Closed_unused
  | Session_fenced
  | Indeterminate

val lifecycle_states : lifecycle_state list
val lifecycle_state_id : lifecycle_state -> string

type unavailable_prerequisite =
  | Root_recovery_port_issuer_current
  | Root_recovery_port_lifecycle_current
  | Activation_recovery_port_preparation_current
  | Authority_store_recovery_port_prepared_row_current
  | Authority_store_recovery_port_reference_sealing_current
  | Authority_store_recovery_port_atomic_withdrawal_current
  | Authority_store_recovery_port_lifecycle_current
  | Owner_session_current_carrier
  | Activation_generation_current_carrier
  | Activity_identity_current_carrier
  | Source_transition_commitment_current_carrier
  | B_selected_decision_current_carrier
  | Selected_prefix_current_carrier
  | Bounded_expiry_current_carrier
  | Dependency_carrier_owner_current
  | Transition_target_resolver_registration_current
  | Event_effect_readback_current
  | Recovery_port_readback_current_carrier
  | Terminal_or_close_unused_evidence_current
  | Session_fence_current_carrier
  | Drain_barrier_current_carrier

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
  Jj_runtime_manifest.runtime_recovery_port_vault
    Jj_runtime_manifest.declaration

val target_slot :
  Jj_runtime_manifest.target_transition Jj_runtime_manifest.slot

val consumer : Jj_action_kind.frontier_action

val binding_ids : string list
(** Exact ordered reference-binding fields.  The strings are source schema
    identities only and carry no reference or resolver authority. *)

val callsite_ids : string list
(** Exact issuer, retained-holder, resolver, and nonauthorizing-carrier
    census.  The strings do not make any callsite current. *)

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]

val create_vault_unavailable : unit -> (vault, diagnostic list) result
(** Provisional source-bound refusal.  Root currently exposes issuer and
    lifecycle capabilities, but no nominal recovery-port-vault part.  This
    function consumes neither capability and mints no vault, retained port,
    resolver, reference, or Current value. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_port_protocol_source
    | Drop_runtime_current_protocol_source
    | Drop_runtime_manifest_source
    | Drop_action_kind_source
    | Drop_authority_store_source
    | Drop_recovery_set_vault_source
    | Drop_root_bootstrap_source
    | Drop_dependency_authority_source
    | Drop_conditional_authority_source
    | Drop_topology_source
    | Drop_event_prefix_source
    | Drop_runtime_registry_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_slot
    | Substitute_target_slot
    | Drop_consumer
    | Substitute_consumer
    | Drop_lifecycle_state
    | Reorder_lifecycle_states
    | Duplicate_lifecycle_state
    | Merge_applied_diverged
    | Merge_closed_fenced
    | Drop_binding_field
    | Reorder_binding_fields
    | Duplicate_binding_field
    | Drop_callsite
    | Reorder_callsites
    | Substitute_callsite
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_create_without_issuer_current
    | Permit_create_without_lifecycle_current
    | Permit_prepare_without_activation_preparation
    | Permit_prepare_cross_activity
    | Permit_prepare_cross_commitment
    | Permit_prepare_cross_session
    | Permit_prepare_cross_generation
    | Permit_prepare_wrong_target
    | Permit_prepare_wrong_consumer
    | Permit_prepare_after_expiry
    | Permit_changed_prepare_replay
    | Expose_retained_port
    | Serialize_retained_port
    | Authorize_reference
    | Serialize_reference
    | Expose_reference_fields
    | Permit_dashboard_resolver
    | Permit_resolve_without_selected_decision
    | Permit_resolve_without_prefix
    | Permit_resolve_cross_binding
    | Permit_duplicate_resolution
    | Permit_late_apply_after_unused
    | Permit_late_apply_after_fence
    | Permit_close_unused_without_evidence
    | Permit_fence_without_session_death
    | Guess_lost_reply
    | Permit_reconcile_without_readback
    | Permit_state_regression
    | Permit_terminal_without_barrier
    | Permit_drain_with_live_prepared
    | Permit_cross_owner_session
    | Permit_cross_store_epoch
    | Expose_issuer_capability
    | Expose_lifecycle_capability
    | Expose_broad_activation_owner
    | Expose_database
    | Expose_location
    | Expose_sql
    | Expose_store
    | Expose_payload
    | Add_callback
    | Accept_caller_digest
    | Add_vault_constructor
    | Add_resolver_constructor
    | Add_current_constructor
    | Promote_unavailable_vault
    | Alias_recovery_set_vault
    | Add_repository_mutation
    | Add_filesystem_effect
    | Promote_reference_to_completion_credit
    | Promote_reference_to_parity_credit

  val source_digest_with_mutation : source_mutation -> string
end
