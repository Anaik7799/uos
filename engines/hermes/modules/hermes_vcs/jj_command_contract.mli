(** Closed operation-indexed command-contract declarations.
    No argv is renderable until Task 10A freezes the official grammar source. *)

type source_status = Unfrozen_source_blocker
type at_operation = Not_applicable | At_exact_operation_with_ignore_working_copy
type precondition = No_extra_precondition
  | Requires_current_ignore_or_auto_track_exclusion
  | Requires_exact_before_state
  | Requires_remote_scope
  | Requires_exact_before_state_and_remote_scope
type output_contract = Output_contract_pending_source_freeze

type t

val operation : t -> Jj_operation.t
val source_status : t -> source_status
val at_operation : t -> at_operation
val precondition : t -> precondition
val output_contract : t -> output_contract
val all : t list
val for_operation : Jj_operation.t -> t
val source_digest : string
