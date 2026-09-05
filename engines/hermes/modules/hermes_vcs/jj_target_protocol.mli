(** Pure, exhaustive action-to-target routing authority.

    These values identify protocol classes only.  They contain no target
    instance, callback, capability, location, or execution authority. *)

type t =
  | Clock
  | External_resource
  | Repository_source
  | Approval
  | Writer_lease
  | Transition
  | Mutation_frontier
  | Network_scope
  | Credential_lease
  | Filesystem_materialization
  | Candidate_verification
  | Release
  | Completion_receipt
  | Jujutsu
  | Formal

val all : t list
val key : t -> string
val target : Jj_action_kind.t -> t
val source_digest : string
