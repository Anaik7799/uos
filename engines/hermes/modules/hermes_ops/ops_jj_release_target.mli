(** Fail-closed Task-9/10A release-observation target foundation.

    The sole target role observes an operator-supplied release bundle.  The
    four release-phase actions and five-role activation subset are pure source
    identities only.  Owner, registration, and Current receipt are abstract
    and unconstructible.  No network acquisition, credential, process,
    repository mutation, candidate/formal execution, source bytes, path,
    callback, or full production activation crosses this interface. *)

type owner
type registration
type current_receipt

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
  Jj_runtime_manifest.target_release Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val accepted_roles : Jj_action_kind.auxiliary_role list
val accepted_effects : Run_topology.effect_kind list
(* Pure ordered source-comparison identities; none grants activation. *)
val binding_ids : string list
val release_phase_action_ids : string list
val activation_role_ids : string list

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]
val create_owner_unavailable : unit -> (owner, diagnostic list) result
(** Returns the complete ordered missing-prerequisite denominator and creates
    no owner, registration, observation receipt, or Current value. *)

val source_digest : string

module For_test : sig
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

  val source_digest_with_mutation : source_mutation -> string
end
