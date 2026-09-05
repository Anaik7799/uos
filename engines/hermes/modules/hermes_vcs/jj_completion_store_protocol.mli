(** Pure, non-authorizing completion-receipt store requests. *)

type role = Completion_reservation | Completion_final
type kind = Reserve | Finalize
type prepared

val prepare_reserve :
  completion:Jj_id.Receipt.t ->
  source:Jj_id.Receipt.t ->
  head:Jj_id.Operation.t ->
  campaign:Jj_id.Intent.t ->
  payload:Jj_id.Receipt.t ->
  (prepared, Jj_error.t) result

val prepare_finalize :
  completion:Jj_id.Receipt.t ->
  source:Jj_id.Receipt.t ->
  head:Jj_id.Operation.t ->
  campaign:Jj_id.Intent.t ->
  payload:Jj_id.Receipt.t ->
  bookmark:Jj_id.Bookmark.t ->
  readback:Jj_id.Receipt.t ->
  lease_release:Jj_id.Receipt.t ->
  (prepared, Jj_error.t) result

val kind : prepared -> kind
val role : prepared -> role
val completion_id : prepared -> Jj_id.Receipt.t
(* Digest of the reservation payload shared by Reserve and Finalize.  It
    deliberately excludes the request kind and finalization-only dependencies,
    so the store can prove that finalization closes the exact reservation. *)
val reservation_payload_digest : prepared -> string
val payload_digest : prepared -> string
val canonical_digest : prepared -> string
val compatible_replay : prepared -> prepared -> bool
val source_digest : string
