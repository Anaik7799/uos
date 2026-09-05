(** Pure authorization policy. A permit is validation evidence only and never
    executes, snapshots, recovers, fetches, or publishes anything. *)

type authority =
  | Observe_only
  | Local_mutation
  | Destructive_local
  | History_rewrite
  | Recovery
  | Fetch
  | Remote_publish

type denial = Snapshot_forbidden | Insufficient_authority | Stale_authority
type decision = Permit | Deny of denial

val evaluate :
  authority -> snapshot_requested:bool -> Jj_operation.t -> decision

(** Denial is the absorbing element. *)
val combine : decision -> decision -> decision
val source_digest : string

module For_test : sig
  type source_mutation = Drop_authority | Change_decision
  val source_digest_with_mutation : source_mutation -> string
end
