type partial_prefix = { completed : int; total : int }

type partial_prefix_error =
  | Nonpositive_total
  | Nonpositive_completed
  | Completed_not_partial
  | Prefix_limit_exceeded

let maximum_prefix_entries = 1024

let partial_prefix ~completed ~total =
  if total <= 0 then Error Nonpositive_total
  else if completed <= 0 then Error Nonpositive_completed
  else if completed >= total then Error Completed_not_partial
  else if total > maximum_prefix_entries then Error Prefix_limit_exceeded
  else Ok { completed; total }

let partial_prefix_completed prefix = prefix.completed
let partial_prefix_total prefix = prefix.total

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

type recovery_step = { ordinal : int; action : Jj_action_kind.t }

let recovery_step_ordinal step = step.ordinal
let recovery_step_action step = step.action
let steps actions = List.mapi (fun ordinal action -> { ordinal; action }) actions

type b_branch = {
  b_disposition_value : b_disposition;
  b_lease_posture_value : lease_posture;
  b_steps_value : recovery_step list;
  b_requires_physical_restoration_value : bool;
}

let b_disposition branch = branch.b_disposition_value
let b_lease_posture branch = branch.b_lease_posture_value
let b_steps branch = branch.b_steps_value
let b_requires_physical_restoration branch =
  branch.b_requires_physical_restoration_value

type completion_record_branch = {
  completion_record_disposition_value : completion_record_disposition;
  completion_record_lease_posture_value : lease_posture;
  completion_record_steps_value : recovery_step list;
}

let completion_record_disposition branch =
  branch.completion_record_disposition_value

let completion_record_lease_posture branch =
  branch.completion_record_lease_posture_value

let completion_record_steps branch = branch.completion_record_steps_value

type family = B_family | Completion_record_family

type conditional_schema =
  | B_schema of b_branch list
  | Completion_record_schema of completion_record_branch list

let family = function
  | B_schema _ -> B_family
  | Completion_record_schema _ -> Completion_record_family

let b_branches = function B_schema branches -> branches | _ -> []

let completion_record_branches = function
  | Completion_record_schema branches -> branches
  | _ -> []

let b_success_action_slots =
  [ B_acquire_writer_lease; B_stage_recovery_set; B_bookmark_set;
    B_bookmark_readback; B_duplicate; B_duplicate_readback;
    B_observe_repository_source_before_partition;
    B_observe_tree_before_partition; B_write_partition;
    B_observe_tree_after_write; B_working_copy_snapshot_1;
    B_snapshot_1_readback; B_new_change; B_new_change_readback;
    B_restore_partition; B_observe_tree_after_restore;
    B_working_copy_snapshot_2; B_snapshot_2_readback;
    B_observe_tree_final; B_observe_repository_source_final;
    B_set_activity_frontier; B_cleanup_recovery_set;
    B_release_writer_lease ]

let completion_record_common_slots =
  [ Record_acquire_writer_lease; Record_stage_recovery_set;
    Record_new_change; Record_new_change_readback;
    Record_write_sealed_record_candidate; Record_write_observe_tree;
    Record_working_copy_snapshot; Record_snapshot_readback;
    Record_snapshot_observe_tree; Record_describe; Record_describe_readback;
    Record_observe_tree_final; Record_observe_repository_source_final;
    Record_set_activity_frontier; Record_cleanup_recovery_set;
    Record_release_writer_lease ]

let completion_record_action_slots = function
  | Existing -> completion_record_common_slots
  | Newly_allocated ->
      [ Record_acquire_writer_lease; Record_stage_recovery_set;
        Record_workspace_add; Record_workspace_readback;
        Record_workspace_observe_tree;
        Record_workspace_observe_repository_source;
        Record_new_change; Record_new_change_readback;
        Record_write_sealed_record_candidate; Record_write_observe_tree;
        Record_working_copy_snapshot; Record_snapshot_readback;
        Record_snapshot_observe_tree; Record_describe;
        Record_describe_readback; Record_observe_tree_final;
        Record_observe_repository_source_final;
        Record_set_activity_frontier; Record_cleanup_recovery_set;
        Record_release_writer_lease ]

let b_slot_rank = function
  | B_acquire_writer_lease -> 0
  | B_stage_recovery_set -> 1
  | B_bookmark_set -> 2
  | B_bookmark_readback -> 3
  | B_duplicate -> 4
  | B_duplicate_readback -> 5
  | B_observe_repository_source_before_partition -> 6
  | B_observe_tree_before_partition -> 7
  | B_write_partition_partial _ -> 8
  | B_write_partition -> 9
  | B_observe_tree_after_write -> 10
  | B_working_copy_snapshot_1 -> 11
  | B_snapshot_1_readback -> 12
  | B_new_change -> 13
  | B_new_change_readback -> 14
  | B_restore_partition_partial _ -> 15
  | B_restore_partition -> 16
  | B_observe_tree_after_restore -> 17
  | B_working_copy_snapshot_2 -> 18
  | B_snapshot_2_readback -> 19
  | B_observe_tree_final -> 20
  | B_observe_repository_source_final -> 21
  | B_set_activity_frontier -> 22
  | B_cleanup_recovery_set -> 23
  | B_release_writer_lease -> 24

let completion_slot_rank = function
  | Record_acquire_writer_lease -> 0
  | Record_stage_recovery_set -> 1
  | Record_workspace_add -> 2
  | Record_workspace_readback -> 3
  | Record_workspace_observe_tree -> 4
  | Record_workspace_observe_repository_source -> 5
  | Record_new_change -> 6
  | Record_new_change_readback -> 7
  | Record_write_candidate_partial _ -> 8
  | Record_write_sealed_record_candidate -> 9
  | Record_write_observe_tree -> 10
  | Record_working_copy_snapshot -> 11
  | Record_snapshot_readback -> 12
  | Record_snapshot_observe_tree -> 13
  | Record_describe -> 14
  | Record_describe_readback -> 15
  | Record_observe_tree_final -> 16
  | Record_observe_repository_source_final -> 17
  | Record_set_activity_frontier -> 18
  | Record_cleanup_recovery_set -> 19
  | Record_release_writer_lease -> 20

let completed_at_or_after rank = function
  | Before_engine -> false
  | After_action slot -> b_slot_rank slot >= rank
  | After_consume slot -> b_slot_rank slot > rank

let completion_completed_at_or_after rank = function
  | Completion_before_engine -> false
  | Completion_after_action slot -> completion_slot_rank slot >= rank
  | Completion_after_consume slot -> completion_slot_rank slot > rank

let b_lease_posture_of_cut = function
  | Before_engine -> Not_acquired
  | After_consume B_acquire_writer_lease -> Not_acquired
  | After_action B_release_writer_lease -> Released
  | After_consume slot | After_action slot ->
      if b_slot_rank slot = 0 then Held else Held

let completion_lease_posture_of_cut = function
  | Completion_before_engine -> Not_acquired
  | Completion_after_consume Record_acquire_writer_lease -> Not_acquired
  | Completion_after_action Record_release_writer_lease -> Released
  | Completion_after_consume _ | Completion_after_action _ -> Held

let lease_posture = function
  | B_success (cut, _) -> b_lease_posture_of_cut cut
  | Completion_record (cut, _, _) -> completion_lease_posture_of_cut cut

let b_physical_dirty = function
  | Before_engine -> false
  | After_action slot ->
      let rank = b_slot_rank slot in
      rank >= 8 && rank < 16
  | After_consume slot ->
      let rank = b_slot_rank slot in
      rank > 9 && rank <= 16

let b_dispositions cut =
  let source_entered = completed_at_or_after 2 cut in
  if not source_entered then [ No_source_effect; Diverged ]
  else if b_physical_dirty cut then
    [ Restore_operation_and_partition; Diverged ]
  else if completed_at_or_after 18 cut then
    [ Restore_operation_only; Forward_complete_exact; Diverged ]
  else [ Restore_operation_only; Diverged ]

let activation = function
  | In_process ->
      [ Jj_action_kind.Frontier_action
          Jj_action_kind.Activate_source_recovery_branch ]
  | Restarted -> []

let auxiliary role = Jj_action_kind.Auxiliary role
let operation value = Jj_action_kind.Jujutsu_operation value

let terminal_frontier =
  Jj_action_kind.Frontier_action
    (Jj_action_kind.Set_activity_frontier
       Jj_action_kind.Reconciled_terminal)

let lease_action ~mode ~posture ~needs_fence =
  match mode, posture with
  | Restarted, _ -> Some (auxiliary Jj_action_kind.Acquire_writer_lease)
  | In_process, Held -> Some (auxiliary Jj_action_kind.Renew_writer_lease)
  | In_process, (Not_acquired | Released) when needs_fence ->
      Some (auxiliary Jj_action_kind.Acquire_writer_lease)
  | In_process, (Not_acquired | Released) -> None

let append_optional value values =
  match value with None -> values | Some item -> values @ [ item ]

let b_actions ~cut ~mode disposition =
  if disposition = Diverged then
    (match mode with
     | In_process -> activation mode
     | Restarted -> [ auxiliary Jj_action_kind.Acquire_writer_lease ])
  else
    let posture = b_lease_posture_of_cut cut in
    let staged = completed_at_or_after 1 cut in
    let needs_fence = disposition <> No_source_effect in
    let lease = lease_action ~mode ~posture ~needs_fence in
    let prefix = append_optional lease (activation mode) in
    let prefix =
      if staged then prefix @ [ auxiliary Jj_action_kind.Reconcile_recovery_set ]
      else prefix
    in
    let restoration =
      match disposition with
      | Restore_operation_only -> [ operation Jj_operation.Operation_restore ]
      | Restore_operation_and_partition ->
          [ operation Jj_operation.Operation_restore;
            auxiliary Jj_action_kind.Restore_partition ]
      | No_source_effect | Forward_complete_exact -> []
      | Diverged -> assert false
    in
    let suffix =
      [ auxiliary Jj_action_kind.Readback_jj_state;
        auxiliary Jj_action_kind.Observe_tree;
        auxiliary Jj_action_kind.Observe_repository_source;
        terminal_frontier ]
      @ (if staged then [ auxiliary Jj_action_kind.Cleanup_recovery_set ] else [])
    in
    let acquired = Option.is_some lease || posture = Held in
    prefix @ restoration @ suffix
    @ if acquired then [ auxiliary Jj_action_kind.Release_writer_lease ] else []

let make_b_branch ~cut ~mode disposition =
  let posture = b_lease_posture_of_cut cut in
  { b_disposition_value = disposition;
    b_lease_posture_value = posture;
    b_steps_value = steps (b_actions ~cut ~mode disposition);
    b_requires_physical_restoration_value =
      disposition = Restore_operation_and_partition }

let completion_slot_valid workspace = function
  | Record_workspace_add | Record_workspace_readback
  | Record_workspace_observe_tree
  | Record_workspace_observe_repository_source ->
      workspace = Newly_allocated
  | _ -> true

let completion_cut_valid workspace = function
  | Completion_before_engine -> true
  | Completion_after_consume slot | Completion_after_action slot ->
      completion_slot_valid workspace slot

let completion_source_entered workspace cut =
  match workspace with
  | Existing -> completion_completed_at_or_after 6 cut
  | Newly_allocated -> completion_completed_at_or_after 2 cut

let completion_workspace_entered workspace cut =
  workspace = Newly_allocated && completion_completed_at_or_after 2 cut

let completion_staged cut = completion_completed_at_or_after 1 cut

let completion_record_actions ~cut ~workspace ~mode =
  let posture = completion_lease_posture_of_cut cut in
  let source_entered = completion_source_entered workspace cut in
  let staged = completion_staged cut in
  let lease = lease_action ~mode ~posture ~needs_fence:true in
  let prefix = append_optional lease (activation mode) in
  let prefix =
    if staged then prefix @ [ auxiliary Jj_action_kind.Reconcile_recovery_set ]
    else prefix
  in
  let operation_restore =
    if source_entered then
      [ operation Jj_operation.Operation_restore;
        auxiliary Jj_action_kind.Readback_jj_state ]
    else []
  in
  let physical_restore =
    if staged then
      [ auxiliary Jj_action_kind.Restore_sealed_record_preimage;
        auxiliary Jj_action_kind.Observe_tree ]
    else []
  in
  let workspace_cleanup =
    if completion_workspace_entered workspace cut then
      [ operation Jj_operation.Workspace_forget;
        auxiliary Jj_action_kind.Readback_jj_state;
        auxiliary Jj_action_kind.Remove_disposable_scope ]
    else []
  in
  prefix @ operation_restore @ physical_restore @ workspace_cleanup
  @ [ auxiliary Jj_action_kind.Readback_jj_state;
      auxiliary Jj_action_kind.Observe_tree;
      auxiliary Jj_action_kind.Observe_repository_source; terminal_frontier ]
  @ (if staged then [ auxiliary Jj_action_kind.Cleanup_recovery_set ] else [])
  @ [ auxiliary Jj_action_kind.Release_writer_lease ]

let make_completion_record_branch ~cut ~workspace ~mode disposition =
  let branch_actions =
    match disposition with
    | Record_diverged ->
        (match mode with
         | In_process -> activation mode
         | Restarted -> [ auxiliary Jj_action_kind.Acquire_writer_lease ])
    | Restore_record_exact -> completion_record_actions ~cut ~workspace ~mode
  in
  { completion_record_disposition_value = disposition;
    completion_record_lease_posture_value =
      completion_lease_posture_of_cut cut;
    completion_record_steps_value = steps branch_actions }

let schema = function
  | B_success (cut, mode) ->
      B_schema
        (List.map (make_b_branch ~cut ~mode) (b_dispositions cut))
  | Completion_record (cut, workspace, mode) ->
      let dispositions =
        if completion_cut_valid workspace cut
           && completion_source_entered workspace cut
        then [ Restore_record_exact; Record_diverged ]
        else [ Record_diverged ]
      in
      Completion_record_schema
        (List.map
           (make_completion_record_branch ~cut ~workspace ~mode)
           dispositions)

let digest_actions actions =
  actions
  |> List.map Jj_action_kind.action_key
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

type authority_mutation =
  | Disposition
  | Action
  | Action_order
  | Cut
  | Workspace
  | Mode

let execution_mode_key = function
  | In_process -> "in-process"
  | Restarted -> "restarted"

let workspace_branch_key = function
  | Existing -> "existing"
  | Newly_allocated -> "newly-allocated"

let lease_posture_key = function
  | Not_acquired -> "not-acquired"
  | Held -> "held"
  | Released -> "released"

let b_disposition_key = function
  | No_source_effect -> "no-source-effect"
  | Restore_operation_only -> "restore-operation-only"
  | Restore_operation_and_partition -> "restore-operation-and-partition"
  | Forward_complete_exact -> "forward-complete-exact"
  | Diverged -> "diverged"

let completion_record_disposition_key = function
  | Restore_record_exact -> "restore-record-exact"
  | Record_diverged -> "record-diverged"

let partial_prefix_key prefix =
  Printf.sprintf "partial:%d/%d"
    (partial_prefix_completed prefix) (partial_prefix_total prefix)

let b_slot_key = function
  | B_acquire_writer_lease -> "acquire-writer-lease"
  | B_stage_recovery_set -> "stage-recovery-set"
  | B_bookmark_set -> "bookmark-set"
  | B_bookmark_readback -> "bookmark-readback"
  | B_duplicate -> "duplicate"
  | B_duplicate_readback -> "duplicate-readback"
  | B_observe_repository_source_before_partition ->
      "observe-repository-source-before-partition"
  | B_observe_tree_before_partition -> "observe-tree-before-partition"
  | B_write_partition_partial prefix ->
      "write-partition-" ^ partial_prefix_key prefix
  | B_write_partition -> "write-partition"
  | B_observe_tree_after_write -> "observe-tree-after-write"
  | B_working_copy_snapshot_1 -> "working-copy-snapshot-1"
  | B_snapshot_1_readback -> "snapshot-1-readback"
  | B_new_change -> "new-change"
  | B_new_change_readback -> "new-change-readback"
  | B_restore_partition_partial prefix ->
      "restore-partition-" ^ partial_prefix_key prefix
  | B_restore_partition -> "restore-partition"
  | B_observe_tree_after_restore -> "observe-tree-after-restore"
  | B_working_copy_snapshot_2 -> "working-copy-snapshot-2"
  | B_snapshot_2_readback -> "snapshot-2-readback"
  | B_observe_tree_final -> "observe-tree-final"
  | B_observe_repository_source_final -> "observe-repository-source-final"
  | B_set_activity_frontier -> "set-activity-frontier"
  | B_cleanup_recovery_set -> "cleanup-recovery-set"
  | B_release_writer_lease -> "release-writer-lease"

let completion_slot_key = function
  | Record_acquire_writer_lease -> "acquire-writer-lease"
  | Record_stage_recovery_set -> "stage-recovery-set"
  | Record_workspace_add -> "workspace-add"
  | Record_workspace_readback -> "workspace-readback"
  | Record_workspace_observe_tree -> "workspace-observe-tree"
  | Record_workspace_observe_repository_source ->
      "workspace-observe-repository-source"
  | Record_new_change -> "new-change"
  | Record_new_change_readback -> "new-change-readback"
  | Record_write_candidate_partial prefix ->
      "write-candidate-" ^ partial_prefix_key prefix
  | Record_write_sealed_record_candidate -> "write-sealed-record-candidate"
  | Record_write_observe_tree -> "write-observe-tree"
  | Record_working_copy_snapshot -> "working-copy-snapshot"
  | Record_snapshot_readback -> "snapshot-readback"
  | Record_snapshot_observe_tree -> "snapshot-observe-tree"
  | Record_describe -> "describe"
  | Record_describe_readback -> "describe-readback"
  | Record_observe_tree_final -> "observe-tree-final"
  | Record_observe_repository_source_final -> "observe-repository-source-final"
  | Record_set_activity_frontier -> "set-activity-frontier"
  | Record_cleanup_recovery_set -> "cleanup-recovery-set"
  | Record_release_writer_lease -> "release-writer-lease"

let representative_partial = { completed = 1; total = 2 }

let b_authority_slots =
  [ B_acquire_writer_lease; B_stage_recovery_set; B_bookmark_set;
    B_bookmark_readback; B_duplicate; B_duplicate_readback;
    B_observe_repository_source_before_partition;
    B_observe_tree_before_partition;
    B_write_partition_partial representative_partial; B_write_partition;
    B_observe_tree_after_write; B_working_copy_snapshot_1;
    B_snapshot_1_readback; B_new_change; B_new_change_readback;
    B_restore_partition_partial representative_partial; B_restore_partition;
    B_observe_tree_after_restore; B_working_copy_snapshot_2;
    B_snapshot_2_readback; B_observe_tree_final;
    B_observe_repository_source_final; B_set_activity_frontier;
    B_cleanup_recovery_set; B_release_writer_lease ]

let completion_authority_slots =
  [ Record_acquire_writer_lease; Record_stage_recovery_set;
    Record_workspace_add; Record_workspace_readback;
    Record_workspace_observe_tree;
    Record_workspace_observe_repository_source; Record_new_change;
    Record_new_change_readback;
    Record_write_candidate_partial representative_partial;
    Record_write_sealed_record_candidate; Record_write_observe_tree;
    Record_working_copy_snapshot; Record_snapshot_readback;
    Record_snapshot_observe_tree; Record_describe; Record_describe_readback;
    Record_observe_tree_final; Record_observe_repository_source_final;
    Record_set_activity_frontier; Record_cleanup_recovery_set;
    Record_release_writer_lease ]

let b_cut_key = function
  | Before_engine -> "before-engine"
  | After_consume slot -> "after-consume:" ^ b_slot_key slot
  | After_action slot -> "after-action:" ^ b_slot_key slot

let completion_cut_key = function
  | Completion_before_engine -> "before-engine"
  | Completion_after_consume slot ->
      "after-consume:" ^ completion_slot_key slot
  | Completion_after_action slot ->
      "after-action:" ^ completion_slot_key slot

let b_authority_cuts =
  Before_engine
  :: List.concat_map
       (fun slot -> [ After_consume slot; After_action slot ])
       b_authority_slots

let completion_authority_cuts =
  Completion_before_engine
  :: List.concat_map
       (fun slot ->
         [ Completion_after_consume slot; Completion_after_action slot ])
       completion_authority_slots

let swap_first_two = function
  | first :: second :: tail -> second :: first :: tail
  | values -> values

let authority_projection mutation =
  let mutated which = mutation = Some which in
  let modes =
    let values = [ In_process; Restarted ] in
    if mutated Mode then List.rev values else values
  in
  let workspaces =
    let values = [ Existing; Newly_allocated ] in
    if mutated Workspace then List.rev values else values
  in
  let b_cuts =
    if mutated Cut then List.tl b_authority_cuts else b_authority_cuts
  in
  let disposition_pending = ref (mutated Disposition) in
  let action_pending = ref (mutated Action) in
  let order_pending = ref (mutated Action_order) in
  let project_actions steps =
    let values =
      List.map
        (fun step ->
          Jj_id.length_frame
            [ string_of_int (recovery_step_ordinal step);
              Jj_action_kind.action_key (recovery_step_action step) ])
        steps
    in
    let values =
      if !action_pending then begin
        action_pending := false;
        match values with
        | [] -> [ "mutant-action" ]
        | _ :: tail -> "mutant-action" :: tail
      end else values
    in
    if !order_pending && List.length values >= 2 then begin
      order_pending := false;
      swap_first_two values
    end else values
  in
  let project_b_branch branch =
    let disposition = b_disposition_key (b_disposition branch) in
    let disposition =
      if !disposition_pending then begin
        disposition_pending := false;
        "mutant-disposition"
      end else disposition
    in
    Jj_id.length_frame
      [ disposition; lease_posture_key (b_lease_posture branch);
        string_of_bool (b_requires_physical_restoration branch);
        Jj_id.length_frame (project_actions (b_steps branch)) ]
  in
  let project_record_branch branch =
    Jj_id.length_frame
      [ completion_record_disposition_key
          (completion_record_disposition branch);
        lease_posture_key (completion_record_lease_posture branch);
        Jj_id.length_frame
          (project_actions (completion_record_steps branch)) ]
  in
  let b_rows =
    List.concat_map
      (fun mode ->
        List.map
          (fun cut ->
            Jj_id.length_frame
              ([ "b"; execution_mode_key mode; b_cut_key cut ]
               @ List.map project_b_branch
                   (b_branches (schema (B_success (cut, mode))))))
          b_cuts)
      modes
  in
  let completion_rows =
    List.concat_map
      (fun workspace ->
        List.concat_map
          (fun mode ->
            List.map
              (fun cut ->
                Jj_id.length_frame
                  ([ "completion-record"; workspace_branch_key workspace;
                     execution_mode_key mode; completion_cut_key cut ]
                   @ List.map project_record_branch
                       (completion_record_branches
                          (schema (Completion_record (cut, workspace, mode))))))
              completion_authority_cuts)
          modes)
      workspaces
  in
  [ "jj-recovery-authority-v2"; Jj_action_kind.source_digest;
    "partial-prefix-max:" ^ string_of_int maximum_prefix_entries;
    Jj_id.length_frame (List.map b_slot_key b_authority_slots);
    Jj_id.length_frame (List.map completion_slot_key completion_authority_slots);
    Jj_id.length_frame (List.map execution_mode_key modes);
    Jj_id.length_frame (List.map workspace_branch_key workspaces);
    Jj_id.length_frame (List.map b_cut_key b_cuts);
    Jj_id.length_frame
      (List.map completion_cut_key completion_authority_cuts);
    Jj_id.length_frame b_rows; Jj_id.length_frame completion_rows ]

let digest_authority mutation =
  authority_projection mutation
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let source_digest = digest_authority None

module For_test = struct
  type mutation = authority_mutation =
    | Disposition
    | Action
    | Action_order
    | Cut
    | Workspace
    | Mode

  let digest_actions = digest_actions
  let source_digest_with_mutation mutation = digest_authority (Some mutation)
end
