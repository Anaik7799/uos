(** Pure, non-authorizing operation intent. No execution carrier is accepted. *)

type applicability = Unavailable_until_bridge | Implemented_unavailable
type error = Unsafe_operation_declaration
type t

type projection = {
  operation : Jj_operation.t;
  repository : Jj_id.Repository.t;
  workspace : Jj_id.Workspace.t;
  expected_before : Jj_id.Operation.t;
  approval_reference : Jj_id.Approval.t;
  approval : Jj_operation.approval_class;
  budget : Jj_budget.t;
  postcondition : Jj_operation.postcondition;
  recovery : Jj_operation.recovery_policy;
  applicability : applicability;
}

val make : operation:Jj_operation.t -> repository:Jj_id.Repository.t ->
  workspace:Jj_id.Workspace.t -> expected_before:Jj_id.Operation.t ->
  approval_reference:Jj_id.Approval.t -> (t, error) result
val projection : t -> projection
val source_digest : string

module For_test : sig
  type source_mutation = Drop_projection_field | Change_applicability
  val source_digest_with_mutation : source_mutation -> string
end
