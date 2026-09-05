(** Fail-closed Task-9 completion-receipt target foundation.

    Only the pure declaration, routing, reservation/finalization laws, and
    absent-prerequisite denominator are constructible.  Owner, registration,
    reservation Current, and completion Current remain abstract and
    unconstructible.  This interface exposes no completion-store capability,
    payload, database, location, SQL, callback, bookmark mutation, repository
    mutation, registration constructor, or Current constructor. *)

type owner
type registration
type reservation_current
type completion_current

type unavailable_prerequisite =
  | Target_owner_part_current
  | Completion_reserve_owner_part_current
  | Completion_finalize_owner_part_current
  | Completion_store_operational_owner_current
  | Completion_store_nominal_peer_open_fence_current
  | Completion_store_session_epoch_current_carrier
  | Activity_generation_current_carrier
  | Approval_occurrence_capability_current
  | Bounded_clock_current_carrier
  | Reservation_source_head_campaign_current_carrier
  | Reservation_record_role_payload_current_carrier
  | Completion_reservation_current_carrier
  | Completion_branch_ordinal_current_carrier
  | Bookmark_poststate_readback_current_carrier
  | Writer_lease_release_current_carrier
  | Reconciled_terminal_frontier_current_carrier
  | Completion_transition_commitment_current_carrier
  | Completion_finalization_cas_current
  | Dependency_carrier_owner_current
  | Effect_target_registration_current
  | Event_effect_readback_current
  | Completion_store_readback_current_carrier

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
  Jj_runtime_manifest.target_completion_receipt
    Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val accepted_roles : Jj_action_kind.auxiliary_role list
val accepted_effects : Run_topology.effect_kind list
val binding_ids : string list
(** Exact ordered action-to-effect identities for source comparison only. *)

val protocol_binding_ids : string list
(** Exact ordered action-to-store-protocol identities.  These strings grant
    no store or completion authority. *)

val lifecycle_law_ids : string list
(** Exact ordered reservation/finalization laws for source comparison only.
    The lower completion store remains their sole operational owner. *)

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]

val create_owner_unavailable : unit -> (owner, diagnostic list) result
(** Returns all missing prerequisites in their canonical order and creates no
    owner, registration, reservation, finalization, or Current value. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_dependency_schema_source
    | Drop_action_kind_source
    | Drop_campaign_action_source
    | Drop_completion_store_protocol_source
    | Drop_readback_source
    | Drop_topology_source
    | Drop_completion_store_source
    | Drop_writer_lease_source
    | Drop_approval_source
    | Drop_root_bootstrap_source
    | Drop_event_prefix_source
    | Drop_runtime_current_protocol_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_reserve_role
    | Drop_finalize_role
    | Reorder_roles
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_reserve_binding
    | Drop_finalize_binding
    | Reorder_bindings
    | Duplicate_binding
    | Substitute_binding_effect
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_reservation_authority
    | Permit_reservation_overwrite
    | Permit_reserve_without_source
    | Permit_reserve_without_head
    | Permit_reserve_without_campaign
    | Permit_reserve_without_record_role
    | Permit_same_id_different_payload_replay
    | Permit_finalize_without_reservation
    | Permit_finalize_wrong_role
    | Permit_finalize_wrong_source
    | Permit_finalize_wrong_head
    | Permit_finalize_wrong_campaign
    | Permit_finalize_wrong_payload
    | Permit_finalize_without_bookmark_readback
    | Permit_finalize_without_lease_release
    | Permit_finalize_before_reconciled_frontier
    | Permit_finalize_without_completion_commitment
    | Permit_finalize_overwrite
    | Drop_finalize_cas
    | Permit_changed_finalize_replay
    | Permit_cross_activity_capability
    | Permit_cross_generation_capability
    | Permit_cross_owner_session
    | Permit_cross_store_epoch
    | Alias_reserve_finalize_capability
    | Expose_read_capability
    | Expose_lifecycle_capability
    | Expose_recovery_capability
    | Add_bookmark_mutation
    | Add_repository_mutation
    | Add_process
    | Add_network
    | Add_credential
    | Expose_database
    | Expose_location
    | Expose_sql
    | Expose_store
    | Expose_payload
    | Expose_capability
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Promote_unavailable_owner
    | Promote_store_readback_to_completion_credit
    | Alias_completion_history
    | Guess_lost_append
    | Permit_close_blocked_row

  val source_digest_with_mutation : source_mutation -> string
end
