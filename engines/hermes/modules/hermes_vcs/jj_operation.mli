(** The sole closed, effect-free user-operation denominator. *)

type t =
  | Version | Operation_head | Status_at_operation | Operation_log_at_operation
  | Revision_log_at_operation | Bookmark_list_at_operation | Workspace_list_at_operation
  | Remote_list_at_operation | Diff_summary_at_operation | Diff_stat_at_operation
  | Diff_patch_at_operation | File_show_at_operation | Resolve_list_at_operation
  | Working_copy_snapshot | Repository_init | Bookmark_set | Bookmark_delete
  | Duplicate | Describe | New_change | File_untrack | Workspace_add
  | Workspace_forget | Workspace_update_stale | Split_files | Partition_change
  | Edit | Rebase | Squash | Abandon | Operation_restore | Partition_recover
  | Git_fetch | Git_push

type risk_class = Risk_observe | Risk_local_mutation | Risk_destructive_local
  | Risk_history_rewrite | Risk_recovery | Risk_remote_read | Risk_remote_publish
type plane = Plane_control | Plane_data
type ooda_phase = Ooda_observe | Ooda_orient | Ooda_decide | Ooda_act
type approval_class = Approval_observation | Approval_mutation | Approval_destructive
  | Approval_recovery | Approval_fetch | Approval_remote_publish
type effect_class = Effect_observation | Effect_local_mutation | Effect_history_rewrite
  | Effect_recovery | Effect_fetch | Effect_remote_publish
type capability_class = Capability_observe | Capability_local_mutation
  | Capability_history_rewrite | Capability_recovery | Capability_fetch
  | Capability_remote_publish
type precondition = Precondition_operation_context | Precondition_mutation_authority
  | Precondition_recovery_anchor | Precondition_fetch_authority
  | Precondition_remote_scope
type postcondition = Postcondition_readback | Postcondition_mutation_readback
  | Postcondition_recovery_readback | Postcondition_remote_readback
type readback_kind = Readback_operation | Readback_mutation | Readback_recovery
  | Readback_fetch | Readback_remote_publish
type recovery_policy = Recovery_none | Recovery_before_state | Recovery_partition_anchor
type activation = Unavailable_until_bridge | Implemented_unavailable

type declaration = private {
  key : string;
  risk : risk_class;
  plane : plane;
  ooda : ooda_phase;
  approval : approval_class;
  effect_class : effect_class;
  capability : capability_class;
  precondition : precondition;
  postcondition : postcondition;
  readback : readback_kind;
  budget : Jj_budget.t;
  recovery : recovery_policy;
  activation : activation;
}

val all : t list
val declaration : t -> declaration
val find : string -> t option
val declaration_is_safe : t -> bool
val digest_of : t list -> string
val source_digest : string

module Testing : sig
  type field = Approval | Recovery | Activation
  val mutated_digest : t -> field -> string
end
