type source_status = Unfrozen_source_blocker
open Jj_operation

type at_operation = Not_applicable | At_exact_operation_with_ignore_working_copy
type precondition = No_extra_precondition
  | Requires_current_ignore_or_auto_track_exclusion
  | Requires_exact_before_state
  | Requires_remote_scope
  | Requires_exact_before_state_and_remote_scope
type output_contract = Output_contract_pending_source_freeze

type t = {
  operation : Jj_operation.t;
  source_status : source_status;
  at_operation : at_operation;
  precondition : precondition;
  output_contract : output_contract;
}

let observation = function
  | Jj_operation.Version -> Not_applicable
  | Operation_head | Status_at_operation | Operation_log_at_operation
  | Revision_log_at_operation | Bookmark_list_at_operation | Workspace_list_at_operation
  | Remote_list_at_operation | Diff_summary_at_operation | Diff_stat_at_operation
  | Diff_patch_at_operation | File_show_at_operation | Resolve_list_at_operation ->
      At_exact_operation_with_ignore_working_copy
  | _ -> Not_applicable

let precondition_for = function
  | Jj_operation.File_untrack -> Requires_current_ignore_or_auto_track_exclusion
  | Bookmark_delete | Workspace_forget | Split_files | Partition_change | Edit | Rebase
  | Squash | Abandon | Operation_restore | Partition_recover ->
      Requires_exact_before_state
  | Git_fetch | Git_push -> Requires_exact_before_state_and_remote_scope
  | _ -> No_extra_precondition

let make operation =
  { operation; source_status = Unfrozen_source_blocker;
    at_operation = observation operation; precondition = precondition_for operation;
    output_contract = Output_contract_pending_source_freeze }

let all = List.map make Jj_operation.all
let operation row = row.operation
let source_status row = row.source_status
let at_operation row = row.at_operation
let precondition row = row.precondition
let output_contract row = row.output_contract

let for_operation operation =
  match List.find_opt (fun row -> row.operation = operation) all with
  | Some row -> row
  | None -> make operation

let at_operation_key = function
  | Not_applicable -> "not-applicable"
  | At_exact_operation_with_ignore_working_copy ->
      "at-exact-operation-with-ignore-working-copy"

let precondition_key = function
  | No_extra_precondition -> "none"
  | Requires_current_ignore_or_auto_track_exclusion -> "ignore-or-auto-track"
  | Requires_exact_before_state -> "exact-before-state"
  | Requires_remote_scope -> "remote-scope"
  | Requires_exact_before_state_and_remote_scope ->
      "exact-before-state-and-remote-scope"

let source_digest =
  all
  |> List.map (fun row ->
         Jj_id.length_frame
           [ (Jj_operation.declaration row.operation).key;
             "unfrozen-source-blocker"; at_operation_key row.at_operation;
             precondition_key row.precondition;
             "output-contract-pending-source-freeze" ])
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
