(** Fail-closed Task-9 approval-nonce target foundation.

    The pure runtime declaration, target, role, effect, and missing owner
    denominator are constructible.  The target owner, registration, and
    Current receipt remain abstract and unconstructible.  This interface
    exposes no public key, signature, nonce, capability, callback, caller
    digest, or owner-internal approval value. *)

type owner
type registration
type current_receipt

type unavailable_prerequisite =
  | Target_owner_part_current
  | Approval_owner_current
  | Campaign_open_current_carrier
  | Request_bound_guard_current_carrier
  | Approval_nonce_transition_current
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
  Jj_runtime_manifest.target_approval Jj_runtime_manifest.declaration
val target_protocol : Jj_target_protocol.t
val accepted_roles : Jj_action_kind.auxiliary_role list
val accepted_effects : Run_topology.effect_kind list

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]

val create_owner_unavailable : unit -> (owner, diagnostic list) result
(** Returns every missing prerequisite in canonical order and constructs no
    owner, registration, approval capability, or Current receipt. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_topology_source
    | Drop_approval_owner_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_role
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_prerequisite
    | Reorder_prerequisites
    | Substitute_prerequisite
    | Add_public_key
    | Add_signature
    | Add_nonce
    | Expose_capability
    | Add_callback
    | Accept_caller_digest
    | Add_current_constructor

  val source_digest_with_mutation : source_mutation -> string
end
