(** Identity-free recovery structure.

    Values in this module describe only family, cut, mode, lease posture,
    disposition, role order, and cardinality. They carry no campaign, action,
    failure, vault, nonce, capability, or receipt identity. *)

type partial_prefix
type partial_prefix_error =
  | Nonpositive_total
  | Nonpositive_completed
  | Completed_not_partial
  | Prefix_limit_exceeded

val partial_prefix :
  completed:int -> total:int -> (partial_prefix, partial_prefix_error) result
val partial_prefix_completed : partial_prefix -> int
val partial_prefix_total : partial_prefix -> int

type execution_mode = In_process | Restarted
type workspace_branch = Existing | Newly_allocated
type lease_posture = Not_acquired | Held | Released

type b_success_slot =
  | B_acquire_writer_lease
  | B_stage_recovery_set
  | B_bookmark_set
  | B_bookmark_readback
  | B_duplicate
  | B_duplicate_readback
  | B_observe_repository_source_before_partition
  | B_observe_tree_before_partition
  | B_write_partition_partial of partial_prefix
  | B_write_partition
  | B_observe_tree_after_write
  | B_working_copy_snapshot_1
  | B_snapshot_1_readback
  | B_new_change
  | B_new_change_readback
  | B_restore_partition_partial of partial_prefix
  | B_restore_partition
  | B_observe_tree_after_restore
  | B_working_copy_snapshot_2
  | B_snapshot_2_readback
  | B_observe_tree_final
  | B_observe_repository_source_final
  | B_set_activity_frontier
  | B_cleanup_recovery_set
  | B_release_writer_lease

type b_success_cut =
  | Before_engine
  | After_consume of b_success_slot
  | After_action of b_success_slot

type completion_record_slot =
  | Record_acquire_writer_lease
  | Record_stage_recovery_set
  | Record_workspace_add
  | Record_workspace_readback
  | Record_workspace_observe_tree
  | Record_workspace_observe_repository_source
  | Record_new_change
  | Record_new_change_readback
  | Record_write_candidate_partial of partial_prefix
  | Record_write_sealed_record_candidate
  | Record_write_observe_tree
  | Record_working_copy_snapshot
  | Record_snapshot_readback
  | Record_snapshot_observe_tree
  | Record_describe
  | Record_describe_readback
  | Record_observe_tree_final
  | Record_observe_repository_source_final
  | Record_set_activity_frontier
  | Record_cleanup_recovery_set
  | Record_release_writer_lease

type completion_record_cut_point =
  | Completion_before_engine
  | Completion_after_consume of completion_record_slot
  | Completion_after_action of completion_record_slot

type request =
  | B_success of b_success_cut * execution_mode
  | Completion_record of
      completion_record_cut_point * workspace_branch * execution_mode

type b_disposition =
  | No_source_effect
  | Restore_operation_only
  | Restore_operation_and_partition
  | Forward_complete_exact
  | Diverged

type completion_record_disposition = Restore_record_exact | Record_diverged

type recovery_step
val recovery_step_ordinal : recovery_step -> int
val recovery_step_action : recovery_step -> Jj_action_kind.t

type b_branch
val b_disposition : b_branch -> b_disposition
val b_lease_posture : b_branch -> lease_posture
val b_steps : b_branch -> recovery_step list
val b_requires_physical_restoration : b_branch -> bool

type completion_record_branch
val completion_record_disposition :
  completion_record_branch -> completion_record_disposition
val completion_record_lease_posture :
  completion_record_branch -> lease_posture
val completion_record_steps :
  completion_record_branch -> recovery_step list

type family = B_family | Completion_record_family
type conditional_schema

(** Total structural projection. Runtime readback selects a branch later; the
    caller cannot place a selected disposition in [request]. *)
val schema : request -> conditional_schema
val family : conditional_schema -> family
val b_branches : conditional_schema -> b_branch list
val completion_record_branches :
  conditional_schema -> completion_record_branch list

(** Derived from the owner-prefix cut, never accepted as request input. *)
val lease_posture : request -> lease_posture

(** Canonical action slots, excluding parameterized partial-prefix cuts. *)
val b_success_action_slots : b_success_slot list
val completion_record_action_slots :
  workspace_branch -> completion_record_slot list

val source_digest : string

module For_test : sig
  type mutation = Disposition | Action | Action_order | Cut | Workspace | Mode
  val digest_actions : Jj_action_kind.t list -> string
  val source_digest_with_mutation : mutation -> string
end
