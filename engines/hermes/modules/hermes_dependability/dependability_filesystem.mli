(** Pure, non-authorizing filesystem policy foundation.

    This module intentionally owns neither a directory descriptor nor a native
    path.  Its only backend value records that a descriptor-relative
    [RESOLVE_BENEATH | RESOLVE_NO_XDEV] backend has not been admitted.  Thus a
    declaration can be prepared, but no observation or materialization can
    perform an effect, claim currentness, readback, or apply-once evidence. *)

type backend = No_xdev_unavailable

type role =
  | Observe_tree
  | Observe_object
  | Materialize_candidate
  | Write_partition
  | Restore_partition
  | Write_sealed_record_candidate
  | Restore_sealed_record_preimage
  | Remove_disposable_scope

type precondition = Target_present | Target_absent

type error =
  | Invalid_root
  | Invalid_relative_target
  | Role_precondition_mismatch
  | Unavailable_observed

type root
type target
type prepared

val root : string -> (root, error) result
(** Declares a bounded canonical root identity.  This is not a filesystem
    pathname and cannot be resolved by this foundation. *)

val target : string -> (target, error) result
(** Accepts only a bounded, slash-separated relative target with no empty,
    dot, parent, absolute, or backslash segment. *)

val backend : unit -> backend
val precondition : role -> precondition

val prepare :
  root:root -> role:role -> target:target -> precondition:precondition ->
  (prepared, error) result
(** Forms an immutable policy declaration.  It performs no filesystem effect. *)

val prepared_digest : prepared -> string

val observe_tree : prepared -> (unit, error) result
val observe_object : prepared -> (unit, error) result
val materialize_candidate : prepared -> (unit, error) result
val write_partition : prepared -> (unit, error) result
val restore_partition : prepared -> (unit, error) result
val write_sealed_record_candidate : prepared -> (unit, error) result
val restore_sealed_record_preimage : prepared -> (unit, error) result
val remove_disposable_scope : prepared -> (unit, error) result
(** Each entrypoint is unconditionally [Error Unavailable_observed] until an
    owner-held descriptor-relative backend proves both beneath-root resolution
    and no-cross-device traversal. *)

val source_digest : string

module For_test : sig
  type mutation =
    | Drop_resolve_beneath
    | Drop_resolve_no_xdev
    | Permit_parent_segment
    | Promote_backend
    | Widen_target_bound
    | Drop_role_precondition

  val source_digest_with_mutation : mutation -> string
end
