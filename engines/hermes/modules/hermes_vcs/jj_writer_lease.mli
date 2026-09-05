(** Validation-only writer-lease witnesses. This module does not acquire,
    renew, persist, or release a physical lease. It fences governed callers
    only; an external writer is sensed and makes the witness stale. *)

type claim = {
  lease_id : Jj_id.Lease.t;
  repository : Jj_id.Repository.t;
  workspace : Jj_id.Workspace.t;
  expected_operation : Jj_id.Operation.t;
  expected_change : Jj_id.Change.t;
  expected_commit : Jj_id.Commit.t;
  holder : Jj_id.Approval.t;
  expires_at_epoch : int64;
  fence_epoch : int64;
  operator_quiescence : Jj_id.Receipt.t;
  release_readback : Jj_id.Receipt.t option;
}

type validation_error = Invalid_fence | Already_expired | Already_released
type mutation_state = Not_started | Started
type stale_reason =
  | Head_changed
  | External_writer_detected
  | Lease_expired
  | Lease_expired_during_started_mutation

type state

val validate : now_epoch:int64 -> claim -> (state, validation_error) result

val observe :
  state ->
  now_epoch:int64 ->
  observed_operation:Jj_id.Operation.t ->
  external_writer_detected:bool ->
  mutation_state:mutation_state ->
  state

val permits_next : state -> bool
val started_mutation_may_complete : state -> bool
val requires_full_readback : state -> bool
val stale_reason : state -> stale_reason option
val source_digest : string
