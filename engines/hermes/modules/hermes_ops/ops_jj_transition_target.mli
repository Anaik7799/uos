(** Fail-closed Task-9 recovery-transition target foundation.

    Only pure declaration, routing, action/effect binding, and unavailable
    prerequisite identities are exposed.  The lower target and dependency
    authorities assign all three recovery-set roles to Transition; their
    operational lifecycle contract is not Current.  Owner, registration, and
    Current receipt are abstract and unconstructible, and no
    register/apply/resolve operation is provided.  No vault capability,
    transition port, path, bytes, callback,
    caller-selected cut/effect, or caller digest crosses this interface. *)

type owner
type registration
type current_receipt

type unavailable_prerequisite =
  | Target_owner_part_current
  | Recovery_vault_owner_current
  | Recovery_transition_port_vault_current
  | Execution_local_transition_resolver_current
  | Recovery_transition_reference_current_carrier
  | Source_change_transition_commitment_current_carrier
  | B_selected_decision_current_carrier
  | Owner_produced_prefix_current_carrier
  | Apply_once_pending_transition_conversion_current
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
  Jj_runtime_manifest.target_transition Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val accepted_roles : Jj_action_kind.auxiliary_role list
val accepted_frontiers : Jj_action_kind.frontier_action list
val accepted_effects : Run_topology.effect_kind list
val binding_ids : string list
(** Exact ordered action-to-effect identities.  They are pure strings for
    source comparison only and grant no target or effect authority. *)

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]
val create_owner_unavailable : unit -> (owner, diagnostic list) result
val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_topology_source
    | Drop_recovery_vault_source
    | Drop_transition_port_protocol_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_stage_role
    | Drop_reconcile_role
    | Drop_cleanup_role
    | Reorder_roles
    | Add_role
    | Drop_frontier
    | Substitute_frontier
    | Drop_filesystem_effect
    | Drop_activation_effect
    | Reorder_effects
    | Add_effect
    | Drop_stage_binding
    | Drop_reconcile_binding
    | Drop_cleanup_binding
    | Drop_activation_binding
    | Reorder_bindings
    | Duplicate_binding
    | Swap_stage_activation_effect_binding
    | Bind_reconcile_to_activation_effect
    | Bind_activation_to_filesystem_effect
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_stage_without_vault
    | Permit_reconcile_without_prefix
    | Permit_cleanup_before_terminal
    | Permit_activation_without_selected_decision
    | Permit_activation_without_commitment
    | Permit_cross_session_reference
    | Permit_cross_activity_reference
    | Permit_cross_generation_reference
    | Accept_caller_cut
    | Accept_caller_effect
    | Add_raw_path
    | Add_raw_bytes
    | Expose_vault_capability
    | Expose_transition_port
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Merge_recovery_role_allocation

  val source_digest_with_mutation : source_mutation -> string
end
