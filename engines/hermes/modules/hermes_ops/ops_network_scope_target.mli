(** Fail-closed Task-9 network-scope target foundation.

    This module exposes only the closed declaration, routing, operation-policy,
    lifecycle, and missing-prerequisite authority.  Owner, registration, and
    Current receipt are abstract and unconstructible.  It provides no network
    backend, raw endpoint, socket, request bytes, credential, capability,
    callback, register, acquire, release, or Current API. *)

type owner
type registration
type current_receipt

type unavailable_prerequisite =
  | Target_owner_part_current
  | Network_scope_operational_owner_current
  | Controlled_network_backend_current
  | Named_remote_identity_current_carrier
  | Remote_operation_intent_current_carrier
  | Credential_lease_current_carrier
  | Bounded_clock_current_carrier
  | Approval_occurrence_capability_current
  | Network_scope_release_eligibility_current
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
  Jj_runtime_manifest.target_network_scope Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val accepted_roles : Jj_action_kind.auxiliary_role list
val accepted_effects : Run_topology.effect_kind list
val binding_ids : string list
(** Exact ordered action-to-effect identities for source comparison only. *)

val operation_policy_binding_ids : string list
(** Exact ordered Git-fetch/Git-push policy identities.  They grant no
    operation, network, credential, or target authority. *)

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]
val create_owner_unavailable : unit -> (owner, diagnostic list) result
(** Returns the complete ordered missing-prerequisite denominator and creates
    no owner, registration, network operation, or Current receipt. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_operation_source
    | Drop_dependency_schema_source
    | Drop_topology_source
    | Drop_network_owner_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_acquire_role
    | Drop_release_role
    | Reorder_roles
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_acquire_binding
    | Drop_release_binding
    | Reorder_bindings
    | Duplicate_binding
    | Bind_release_to_credential_effect
    | Drop_git_fetch_policy
    | Drop_git_push_policy
    | Reorder_operation_policies
    | Bind_fetch_to_remote_publish
    | Drop_fetch_local_mutation_authority
    | Permit_push_without_remote_cas
    | Claim_remote_activity_projection_complete
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_acquire_without_backend
    | Permit_acquire_without_named_remote
    | Permit_acquire_without_operation_intent
    | Permit_acquire_without_credential
    | Permit_acquire_without_clock
    | Permit_acquire_without_approval
    | Permit_release_without_eligibility
    | Permit_release_during_active_operation
    | Permit_after_expiry
    | Permit_after_revocation
    | Permit_after_cleanup
    | Permit_changed_replay
    | Accept_raw_remote
    | Add_raw_endpoint
    | Add_raw_socket
    | Add_raw_request_bytes
    | Expose_credential
    | Expose_capability
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Promote_unavailable_backend

  val source_digest_with_mutation : source_mutation -> string
end
