(** Fail-closed Task-9 credential-lease target foundation.

    Only the pure declaration, routing, lifecycle, and unavailable
    prerequisite identities are constructible.  Owner, registration, and
    Current receipt remain abstract and unconstructible.  This interface
    exposes no secret/provider handoff, credential or authorization string,
    environment, raw endpoint, lease capability/reference, callback,
    register, acquire, release, or Current operation. *)

type owner
type registration
type current_receipt

type unavailable_prerequisite =
  | Target_owner_part_current
  | Credential_lease_operational_owner_current
  | Controlled_secret_provider_handoff_current
  | Credential_declaration_current_carrier
  | Remote_operation_context_current_carrier
  | Authority_role_session_fence
  | Approval_occurrence_capability_current
  | Bounded_clock_current_carrier
  | Request_bound_credential_transition_current_carrier
  | Remote_terminal_readback_cleanup_eligibility_current
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
  Jj_runtime_manifest.target_credential_lease
    Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val accepted_roles : Jj_action_kind.auxiliary_role list
val accepted_effects : Run_topology.effect_kind list
val binding_ids : string list
(** Exact ordered action-to-effect identities for source comparison only. *)

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]
val create_owner_unavailable : unit -> (owner, diagnostic list) result
(** Returns the complete ordered missing-prerequisite denominator and creates
    no owner, registration, credential transition, or Current receipt. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_dependency_schema_source
    | Drop_topology_source
    | Drop_credential_source
    | Drop_root_bootstrap_source
    | Drop_dependency_authority_source
    | Drop_swarm_preparation_source
    | Drop_event_prefix_source
    | Drop_target_registry_schema
    | Drop_credential_config_declaration
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Substitute_network_scope_protocol
    | Drop_acquire_role
    | Drop_release_role
    | Reorder_roles
    | Add_role
    | Drop_effect
    | Substitute_network_scope_effect
    | Add_effect
    | Drop_acquire_binding
    | Drop_release_binding
    | Reorder_bindings
    | Duplicate_binding
    | Bind_acquire_to_network_scope_effect
    | Bind_release_to_network_scope_effect
    | Merge_acquire_release
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_acquire_without_provider
    | Permit_acquire_without_declaration
    | Permit_acquire_without_remote_context
    | Permit_acquire_without_approval
    | Permit_acquire_without_clock
    | Permit_cross_remote_lease
    | Permit_cross_transport_lease
    | Permit_cross_session_lease
    | Permit_cross_activity_lease
    | Permit_expired_lease
    | Permit_revoked_lease
    | Permit_cleaned_lease_reuse
    | Permit_release_before_terminal_readback
    | Permit_changed_replay
    | Accept_secret_bytes
    | Accept_credential_string
    | Accept_auth_header
    | Accept_environment
    | Accept_raw_endpoint
    | Expose_lease_capability
    | Accept_lease_reference_as_authority
    | Serialize_dependency_carrier
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Promote_unavailable_lease
    | Expose_redacted_remote
    | Bind_source_digest_to_secret_bytes

  val source_digest_with_mutation : source_mutation -> string
end
