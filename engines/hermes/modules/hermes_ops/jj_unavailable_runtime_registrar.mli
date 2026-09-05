(** Fail-closed epoch-zero Formal-unavailable registrar foundation.

    The three lower declaration constants are pure schema identities.  They
    are not typed unavailable attestations and grant no target, process,
    activation, registration, executable, or Current authority.  This module
    exposes no generic registrar, registry, generation grant, owner claim,
    attestation, callback, executable, activation capability, store, or raw
    effect while the exact prerequisites remain absent. *)

type registration

type unavailable_prerequisite =
  | Manifest_typed_unavailable_formal_posture_current
  | Formal_unavailability_reason_attestation_current
  | Formal_unavailability_source_attestation_current
  | Formal_unavailability_context_attestation_current
  | Durable_generation_owner_current
  | Epoch_zero_prepared_generation_current
  | Epoch_zero_target_formal_grant_current
  | Epoch_zero_process_formal_grant_current
  | Epoch_zero_activation_formal_grant_current
  | Target_formal_unavailable_owner_claim_current
  | Process_formal_unavailable_owner_claim_current
  | Activation_formal_unavailable_owner_claim_current
  | Target_formal_unavailable_attestation_seal_current
  | Process_formal_unavailable_attestation_seal_current
  | Activation_formal_unavailable_attestation_seal_current
  | Target_formal_unavailable_view_registration_current
  | Process_formal_unavailable_view_registration_current
  | Activation_formal_unavailable_view_registration_current
  | Epoch_zero_formal_product_closer_current
  | Epoch_zero_publication_current
  | Epoch_zero_readback_current
  | Stale_epoch_zero_fence_current
  | Epoch_one_concrete_formal_successor_current

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

val epoch_zero : Run_jj_runtime_registry.manifest_generation
(** The public lower generation identity only.  It is not a preparation,
    grant, registration, publication, or Current receipt. *)

val target_declaration :
  Jj_runtime_manifest.target_formal Jj_runtime_manifest.declaration

val process_declaration :
  Jj_runtime_manifest.process_formal Jj_runtime_manifest.declaration

val activation_declaration :
  Jj_runtime_manifest.activation_formal Jj_runtime_manifest.declaration

val slot_ids : string list
val reason_ids : string list
val binding_ids : string list
val lifecycle_law_ids : string list
(** Ordered source-schema identities only.  They carry no declaration
    posture, reason attestation, view, or registration authority. *)

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]

val register_epoch_zero_unavailable :
  unit -> (registration, diagnostic list) result
(** Returns every missing prerequisite in canonical order.  It does not call
    [Run_jj_runtime_registry.register_current_unavailable] and cannot create a
    Formal target, process, activation, executable, or Current value. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_runtime_current_protocol_source
    | Drop_runtime_registry_source
    | Drop_target_declaration
    | Substitute_target_available
    | Drop_process_declaration
    | Substitute_process_available
    | Drop_activation_declaration
    | Substitute_activation_available
    | Drop_slot
    | Reorder_slots
    | Duplicate_slot
    | Drop_reason
    | Reorder_reasons
    | Substitute_reason
    | Drop_binding
    | Reorder_bindings
    | Duplicate_binding
    | Cross_bind_reason
    | Drop_lifecycle_law
    | Reorder_lifecycle_laws
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_epoch_nonzero
    | Permit_concrete_target_epoch_zero
    | Permit_concrete_process_epoch_zero
    | Permit_concrete_activation_epoch_zero
    | Permit_mixed_formal_posture
    | Permit_missing_reason
    | Permit_missing_source
    | Permit_missing_context
    | Permit_target_without_grant
    | Permit_process_without_grant
    | Permit_activation_without_grant
    | Permit_target_cross_slot_grant
    | Permit_process_cross_slot_grant
    | Permit_activation_cross_slot_grant
    | Permit_target_without_claim
    | Permit_process_without_claim
    | Permit_activation_without_claim
    | Permit_target_without_seal
    | Permit_process_without_seal
    | Permit_activation_without_seal
    | Permit_cross_generation
    | Permit_grant_reuse
    | Permit_same_row_changed_replay
    | Permit_overwrite_epoch_zero
    | Permit_partial_formal_product
    | Permit_publish_before_close
    | Permit_rollback_generation
    | Permit_stale_epoch_zero_use
    | Permit_unavailable_epoch_one
    | Register_current_executable
    | Expose_activation_capability
    | Expose_target_current
    | Expose_process_current
    | Expose_activation_current
    | Add_generic_registrar
    | Accept_caller_digest
    | Add_callback
    | Promote_unavailable_registrar
    | Expose_registry
    | Expose_generation_grant
    | Expose_current_attestation
    | Expose_database
    | Expose_store
    | Add_repository_mutation
    | Add_process_effect
    | Promote_registration_to_completion_credit
    | Promote_registration_to_parity_credit

  val source_digest_with_mutation : source_mutation -> string
end
