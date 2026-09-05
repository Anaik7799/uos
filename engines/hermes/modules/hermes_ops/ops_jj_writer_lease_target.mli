(** Fail-closed Task-9 writer-lease target foundation.

    Only the pure runtime declaration, target, role, effect, and missing
    prerequisite denominators are constructible.  Owner, registration, and
    Current receipt remain abstract.  No raw lock, time, lease, capability,
    callback, caller digest, or lower acquisition contract crosses this
    interface. *)

type owner
type registration
type current_receipt

type unavailable_prerequisite =
  | Target_owner_part_current
  | Writer_lease_operational_owner_current
  | Physical_owner_lock_backend
  | Authority_role_session_fence
  | Nominal_writer_peer_open_fence
  | Authority_writer_fence_transition
  | Approval_occurrence_capability_current
  | Bounded_clock_current_carrier
  | Repository_before_state_current_carrier
  | Quiescence_or_fenced_session_current_carrier
  | Mutation_frontier_release_eligibility_current
  | Dependency_carrier_owner_current
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
  Jj_runtime_manifest.target_writer_lease Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val accepted_roles : Jj_action_kind.auxiliary_role list
val accepted_effects : Run_topology.effect_kind list

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]

val create_owner_unavailable : unit -> (owner, diagnostic list) result
(** Returns the complete ordered missing-prerequisite denominator without
    acquiring, renewing, releasing, registering, or projecting a lease. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_topology_source
    | Drop_writer_lease_owner_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_acquire_role
    | Drop_renew_role
    | Drop_release_role
    | Reorder_roles
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_acquire_without_lock
    | Permit_renew_without_held
    | Permit_release_after_unreconciled
    | Permit_release_without_frontier
    | Permit_cross_session_lease
    | Permit_cross_repository_lease
    | Accept_raw_lock
    | Accept_raw_time
    | Accept_raw_lease
    | Expose_capability
    | Add_callback
    | Accept_caller_digest
    | Add_current_constructor
    | Forge_registration
    | Promote_lower_contract
    | Merge_acquire_renew_release

  val source_digest_with_mutation : source_mutation -> string
end
