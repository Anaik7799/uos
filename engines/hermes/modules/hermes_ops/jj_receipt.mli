(** Bounded nonauthorizing integration receipt facade.

    Finalization remains unavailable until every owner-produced Current
    carrier in the fixed join exists.  This interface exposes neither a
    [Jj_receipt_core.receipt] nor any payload, capability, owner receipt,
    caller digest, or Current constructor. *)

type t

type unavailable_prerequisite =
  | Preparation_current
  | Activity_result_current
  | Event_prefix_current
  | Readback_current
  | Composed_authority_current

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

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]

val finalize_unavailable : unit -> (t, diagnostic list) result
(** Fails with the complete ordered prerequisite denominator.  It cannot
    allocate, normalize, finalize, or project an owner receipt. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_preparation
    | Drop_activity_result
    | Drop_event_prefix
    | Drop_readback
    | Drop_composed_authority
    | Reorder_prerequisites
    | Substitute_event_prefix
    | Drop_core_source
    | Add_owner_receipt_constructor
    | Expose_payload
    | Expose_capability
    | Accept_caller_digest
    | Promote_current

  val source_digest_with_mutation : source_mutation -> string
end
