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

type declaration = {
  key : string; risk : risk_class; plane : plane; ooda : ooda_phase;
  approval : approval_class; effect_class : effect_class; capability : capability_class;
  precondition : precondition; postcondition : postcondition; readback : readback_kind;
  budget : Jj_budget.t; recovery : recovery_policy;
  activation : activation;
}

let all =
  [ Version; Operation_head; Status_at_operation; Operation_log_at_operation;
    Revision_log_at_operation; Bookmark_list_at_operation; Workspace_list_at_operation;
    Remote_list_at_operation; Diff_summary_at_operation; Diff_stat_at_operation;
    Diff_patch_at_operation; File_show_at_operation; Resolve_list_at_operation;
    Working_copy_snapshot; Repository_init; Bookmark_set; Bookmark_delete; Duplicate;
    Describe; New_change; File_untrack; Workspace_add; Workspace_forget;
    Workspace_update_stale; Split_files; Partition_change; Edit; Rebase; Squash;
    Abandon; Operation_restore; Partition_recover; Git_fetch; Git_push ]

let observe key plane =
  { key; risk = Risk_observe; plane; ooda = Ooda_observe;
    approval = Approval_observation; effect_class = Effect_observation;
    capability = Capability_observe;
    precondition = Precondition_operation_context; postcondition = Postcondition_readback;
    readback = Readback_operation;
    budget = Jj_budget.for_profile Observation; recovery = Recovery_none;
    activation = Unavailable_until_bridge }

let local key =
  { key; risk = Risk_local_mutation; plane = Plane_control; ooda = Ooda_act;
    approval = Approval_mutation; effect_class = Effect_local_mutation;
    capability = Capability_local_mutation;
    precondition = Precondition_mutation_authority;
    postcondition = Postcondition_mutation_readback;
    readback = Readback_mutation;
    budget = Jj_budget.for_profile Local_mutation; recovery = Recovery_before_state;
    activation = Unavailable_until_bridge }

let destructive key =
  { (local key) with risk = Risk_destructive_local; approval = Approval_destructive }

let rewrite key =
  { key; risk = Risk_history_rewrite; plane = Plane_control; ooda = Ooda_act;
    approval = Approval_destructive; effect_class = Effect_history_rewrite;
    capability = Capability_history_rewrite;
    precondition = Precondition_mutation_authority;
    postcondition = Postcondition_mutation_readback;
    readback = Readback_mutation;
    budget = Jj_budget.for_profile History_rewrite; recovery = Recovery_before_state;
    activation = Unavailable_until_bridge }

let recovery key policy =
  { key; risk = Risk_recovery; plane = Plane_control; ooda = Ooda_act;
    approval = Approval_recovery; effect_class = Effect_recovery;
    capability = Capability_recovery;
    precondition = Precondition_recovery_anchor; postcondition = Postcondition_recovery_readback;
    readback = Readback_recovery;
    budget = Jj_budget.for_profile Recovery; recovery = policy;
    activation = Unavailable_until_bridge }

let fetch key =
  { key; risk = Risk_remote_read; plane = Plane_control; ooda = Ooda_act;
    approval = Approval_fetch; effect_class = Effect_fetch; capability = Capability_fetch;
    precondition = Precondition_fetch_authority; postcondition = Postcondition_mutation_readback;
    readback = Readback_fetch; budget = Jj_budget.for_profile Remote;
    recovery = Recovery_before_state; activation = Unavailable_until_bridge }

let publish key =
  { key; risk = Risk_remote_publish; plane = Plane_control; ooda = Ooda_act;
    approval = Approval_remote_publish; effect_class = Effect_remote_publish;
    capability = Capability_remote_publish;
    precondition = Precondition_remote_scope; postcondition = Postcondition_remote_readback;
    readback = Readback_remote_publish; budget = Jj_budget.for_profile Remote;
    recovery = Recovery_before_state; activation = Implemented_unavailable }

let declaration = function
  | Version -> observe "version" Plane_control
  | Operation_head -> observe "operation-head" Plane_control
  | Status_at_operation -> observe "status-at-operation" Plane_control
  | Operation_log_at_operation -> observe "operation-log-at-operation" Plane_control
  | Revision_log_at_operation -> observe "revision-log-at-operation" Plane_control
  | Bookmark_list_at_operation -> observe "bookmark-list-at-operation" Plane_control
  | Workspace_list_at_operation -> observe "workspace-list-at-operation" Plane_control
  | Remote_list_at_operation -> observe "remote-list-at-operation" Plane_control
  | Diff_summary_at_operation -> observe "diff-summary-at-operation" Plane_data
  | Diff_stat_at_operation -> observe "diff-stat-at-operation" Plane_data
  | Diff_patch_at_operation -> observe "diff-patch-at-operation" Plane_data
  | File_show_at_operation -> observe "file-show-at-operation" Plane_data
  | Resolve_list_at_operation -> observe "resolve-list-at-operation" Plane_control
  | Working_copy_snapshot -> local "working-copy-snapshot"
  | Repository_init -> local "repository-init"
  | Bookmark_set -> local "bookmark-set"
  | Bookmark_delete -> destructive "bookmark-delete"
  | Duplicate -> local "duplicate"
  | Describe -> local "describe"
  | New_change -> local "new-change"
  | File_untrack -> local "file-untrack"
  | Workspace_add -> local "workspace-add"
  | Workspace_forget -> destructive "workspace-forget"
  | Workspace_update_stale -> local "workspace-update-stale"
  | Split_files -> rewrite "split-files"
  | Partition_change -> rewrite "partition-change"
  | Edit -> rewrite "edit"
  | Rebase -> rewrite "rebase"
  | Squash -> rewrite "squash"
  | Abandon -> rewrite "abandon"
  | Operation_restore -> recovery "operation-restore" Recovery_before_state
  | Partition_recover -> recovery "partition-recover" Recovery_partition_anchor
  | Git_fetch -> fetch "git-fetch"
  | Git_push -> publish "git-push"

let find key = List.find_opt (fun operation -> String.equal (declaration operation).key key) all

let declaration_is_safe operation =
  let declaration = declaration operation in
  let metadata_matches = match declaration.risk, declaration.approval,
      declaration.effect_class, declaration.capability, declaration.ooda,
      declaration.precondition, declaration.postcondition, declaration.readback with
    | Risk_observe, Approval_observation, Effect_observation, Capability_observe,
      Ooda_observe, Precondition_operation_context, Postcondition_readback,
      Readback_operation
    | Risk_local_mutation, Approval_mutation, Effect_local_mutation,
      Capability_local_mutation, Ooda_act, Precondition_mutation_authority,
      Postcondition_mutation_readback, Readback_mutation
    | Risk_destructive_local, Approval_destructive, Effect_local_mutation,
      Capability_local_mutation, Ooda_act, Precondition_mutation_authority,
      Postcondition_mutation_readback, Readback_mutation
    | Risk_history_rewrite, Approval_destructive, Effect_history_rewrite,
      Capability_history_rewrite, Ooda_act, Precondition_mutation_authority,
      Postcondition_mutation_readback, Readback_mutation
    | Risk_recovery, Approval_recovery, Effect_recovery, Capability_recovery,
      Ooda_act, Precondition_recovery_anchor,
      Postcondition_recovery_readback, Readback_recovery
    | Risk_remote_read, Approval_fetch, Effect_fetch, Capability_fetch,
      Ooda_act, Precondition_fetch_authority,
      Postcondition_mutation_readback, Readback_fetch
    | Risk_remote_publish, Approval_remote_publish, Effect_remote_publish,
      Capability_remote_publish, Ooda_act, Precondition_remote_scope,
      Postcondition_remote_readback, Readback_remote_publish -> true
    | _ -> false
  in
  metadata_matches && Jj_budget.valid declaration.budget

let string_of_risk = function
  | Risk_observe -> "observe" | Risk_local_mutation -> "local-mutation"
  | Risk_destructive_local -> "destructive-local" | Risk_history_rewrite -> "history-rewrite"
  | Risk_recovery -> "recovery" | Risk_remote_read -> "remote-read" | Risk_remote_publish -> "remote-publish"

let string_of_plane = function Plane_control -> "control" | Plane_data -> "data"
let string_of_ooda = function Ooda_observe -> "observe" | Ooda_orient -> "orient" | Ooda_decide -> "decide" | Ooda_act -> "act"

let string_of_approval = function
  | Approval_observation -> "observation"
  | Approval_mutation -> "mutation"
  | Approval_destructive -> "destructive"
  | Approval_recovery -> "recovery"
  | Approval_fetch -> "fetch"
  | Approval_remote_publish -> "remote-publish"

let string_of_effect = function
  | Effect_observation -> "observation"
  | Effect_local_mutation -> "local-mutation"
  | Effect_history_rewrite -> "history-rewrite"
  | Effect_recovery -> "recovery"
  | Effect_fetch -> "fetch"
  | Effect_remote_publish -> "remote-publish"

let string_of_capability = function
  | Capability_observe -> "observe"
  | Capability_local_mutation -> "local-mutation"
  | Capability_history_rewrite -> "history-rewrite"
  | Capability_recovery -> "recovery"
  | Capability_fetch -> "fetch-network-read-plus-local-mutation"
  | Capability_remote_publish -> "remote-publish"

let string_of_precondition = function
  | Precondition_operation_context -> "operation-context"
  | Precondition_mutation_authority -> "mutation-authority"
  | Precondition_recovery_anchor -> "recovery-anchor"
  | Precondition_fetch_authority -> "network-scope-plus-mutation-authority"
  | Precondition_remote_scope -> "remote-scope"

let string_of_postcondition = function
  | Postcondition_readback -> "readback"
  | Postcondition_mutation_readback -> "mutation-readback"
  | Postcondition_recovery_readback -> "recovery-readback"
  | Postcondition_remote_readback -> "remote-readback"

let string_of_readback = function
  | Readback_operation -> "operation"
  | Readback_mutation -> "mutation"
  | Readback_recovery -> "recovery"
  | Readback_fetch -> "fetch-operation-and-network"
  | Readback_remote_publish -> "remote-publish"

let string_of_recovery = function
  | Recovery_none -> "none"
  | Recovery_before_state -> "before-state"
  | Recovery_partition_anchor -> "partition-anchor"

let string_of_activation = function
  | Unavailable_until_bridge -> "unavailable-until-bridge"
  | Implemented_unavailable -> "implemented-unavailable"

let digest_declarations declarations =
  declarations
  |> List.map (fun declaration ->
      Jj_id.length_frame [ declaration.key; string_of_risk declaration.risk;
        string_of_plane declaration.plane; string_of_ooda declaration.ooda;
        string_of_approval declaration.approval;
        string_of_effect declaration.effect_class;
        string_of_capability declaration.capability;
        string_of_precondition declaration.precondition;
        string_of_postcondition declaration.postcondition;
        string_of_readback declaration.readback;
        string_of_int declaration.budget.max_attempts;
        string_of_int declaration.budget.timeout_ms;
        string_of_int declaration.budget.max_output_bytes;
        string_of_recovery declaration.recovery;
        string_of_activation declaration.activation ])
  |> String.concat "\n"
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let digest_of operations =
  digest_declarations (List.map declaration operations)

let source_digest = digest_of all

module Testing = struct
  type field = Approval | Recovery | Activation

  let mutated_digest operation = function
    | Approval ->
        digest_declarations
          [ { (declaration operation) with approval = Approval_observation } ]
    | Recovery ->
        digest_declarations
          [ { (declaration operation) with recovery = Recovery_partition_anchor } ]
    | Activation ->
        digest_declarations
          [ { (declaration operation) with activation = Unavailable_until_bridge } ]
end
