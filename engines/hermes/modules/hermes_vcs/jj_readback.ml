type recovery_anchor =
  | Before_state of string
  | Partition_anchor of string

type child_status =
  | Exited_zero
  | Exited_nonzero of int
  | Signaled of int
  | Timed_out
  | Not_reaped

type decoded = {
  operation_key : string;
  request_id : string;
  event_id : string;
  postcondition_id : string;
  state_digest : string;
  output_bytes : int;
  recovery_anchor : recovery_anchor option;
}

type decoder =
  max_output_bytes:int -> string -> (decoded, string) result

type refusal =
  | Invalid_digest
  | Missing_recovery_anchor
  | Unexpected_recovery_anchor
  | Wrong_recovery_anchor_kind
  | Output_too_large
  | Decoder_refused
  | Nondeterministic_decoder
  | Child_not_successful
  | Identity_mismatch
  | Postcondition_mismatch
  | Output_length_mismatch
  | Recovery_anchor_mismatch

type expectation = {
  operation : Jj_operation.t;
  request_id : string;
  event_id : string;
  expected_state_digest : string;
  recovery_anchor : recovery_anchor option;
}

type receipt = {
  digest : string;
  operation_key : string;
}

let postcondition_id = function
  | Jj_operation.Version -> "version-exact"
  | Operation_head -> "operation-head-exact"
  | Status_at_operation -> "status-at-operation-exact"
  | Operation_log_at_operation -> "operation-log-at-operation-exact"
  | Revision_log_at_operation -> "revision-log-at-operation-exact"
  | Bookmark_list_at_operation -> "bookmark-list-at-operation-exact"
  | Workspace_list_at_operation -> "workspace-list-at-operation-exact"
  | Remote_list_at_operation -> "remote-list-at-operation-exact"
  | Diff_summary_at_operation -> "diff-summary-at-operation-exact"
  | Diff_stat_at_operation -> "diff-stat-at-operation-exact"
  | Diff_patch_at_operation -> "diff-patch-at-operation-exact"
  | File_show_at_operation -> "file-show-at-operation-exact"
  | Resolve_list_at_operation -> "resolve-list-at-operation-exact"
  | Working_copy_snapshot -> "working-copy-snapshot-exact"
  | Repository_init -> "repository-init-exact"
  | Bookmark_set -> "bookmark-set-exact"
  | Bookmark_delete -> "bookmark-delete-exact"
  | Duplicate -> "duplicate-exact"
  | Describe -> "describe-exact"
  | New_change -> "new-change-exact"
  | File_untrack -> "file-untrack-exact"
  | Workspace_add -> "workspace-add-exact"
  | Workspace_forget -> "workspace-forget-exact"
  | Workspace_update_stale -> "workspace-update-stale-exact"
  | Split_files -> "split-files-exact"
  | Partition_change -> "partition-change-exact"
  | Edit -> "edit-exact"
  | Rebase -> "rebase-exact"
  | Squash -> "squash-exact"
  | Abandon -> "abandon-exact"
  | Operation_restore -> "operation-restore-exact"
  | Partition_recover -> "partition-recover-exact"
  | Git_fetch -> "git-fetch-exact"
  | Git_push -> "git-push-exact"

let valid_digest value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let expected_anchor_shape operation anchor =
  match (Jj_operation.declaration operation).recovery, anchor with
  | Jj_operation.Recovery_none, None -> Ok ()
  | Recovery_none, Some _ -> Error Unexpected_recovery_anchor
  | Recovery_before_state, None | Recovery_partition_anchor, None ->
      Error Missing_recovery_anchor
  | Recovery_before_state, Some (Before_state digest)
  | Recovery_partition_anchor, Some (Partition_anchor digest) ->
      if valid_digest digest then Ok () else Error Invalid_digest
  | Recovery_before_state, Some (Partition_anchor _)
  | Recovery_partition_anchor, Some (Before_state _) ->
      Error Wrong_recovery_anchor_kind

let expect ~operation ~request ~event ~expected_state_digest ~recovery_anchor =
  if not (valid_digest expected_state_digest) then Error Invalid_digest
  else
    match expected_anchor_shape operation recovery_anchor with
    | Error refusal -> Error refusal
    | Ok () ->
        Ok
          { operation;
            request_id = Jj_id.Request.to_string request;
            event_id = Jj_id.Event.to_string event;
            expected_state_digest;
            recovery_anchor }

let anchor_text = function
  | None -> "none"
  | Some (Before_state digest) -> "before:" ^ digest
  | Some (Partition_anchor digest) -> "partition:" ^ digest

let receipt_of expectation decoded raw =
  let operation_key = (Jj_operation.declaration expectation.operation).key in
  let digest =
    Jj_id.length_frame
      [ operation_key; expectation.request_id; expectation.event_id;
        postcondition_id expectation.operation; expectation.expected_state_digest;
        anchor_text expectation.recovery_anchor;
        string_of_int decoded.output_bytes;
        Digestif.SHA256.(to_hex (digest_string raw)) ]
    |> Digestif.SHA256.digest_string
    |> Digestif.SHA256.to_hex
  in
  { digest; operation_key }

let verify (expectation : expectation) ~child ~(decode : decoder) raw =
  let maximum = (Jj_operation.declaration expectation.operation).budget.max_output_bytes in
  if String.length raw > maximum then Error Output_too_large
  else if child <> Exited_zero then Error Child_not_successful
  else
    match decode ~max_output_bytes:maximum raw with
    | Error _ -> Error Decoder_refused
    | Ok first ->
        (match decode ~max_output_bytes:maximum raw with
         | Error _ -> Error Nondeterministic_decoder
         | Ok second when first <> second -> Error Nondeterministic_decoder
         | Ok decoded ->
             let operation_key = (Jj_operation.declaration expectation.operation).key in
             if
               not
                 (String.equal decoded.operation_key operation_key
                  && String.equal decoded.request_id expectation.request_id
                  && String.equal decoded.event_id expectation.event_id)
             then Error Identity_mismatch
             else if decoded.output_bytes <> String.length raw then
               Error Output_length_mismatch
             else if
               not
                 (String.equal decoded.postcondition_id
                    (postcondition_id expectation.operation)
                  && String.equal decoded.state_digest
                       expectation.expected_state_digest)
             then Error Postcondition_mismatch
             else if decoded.recovery_anchor <> expectation.recovery_anchor then
               Error Recovery_anchor_mismatch
             else Ok (receipt_of expectation decoded raw))

let receipt_digest receipt = receipt.digest
let receipt_operation_key receipt = receipt.operation_key

let source_digest =
  let rows =
    Jj_operation.all
    |> List.map (fun operation ->
           Jj_id.length_frame
             [ (Jj_operation.declaration operation).key;
               postcondition_id operation;
               string_of_int
                 (Jj_operation.declaration operation).budget.max_output_bytes ])
  in
  Jj_id.length_frame
    [ "jj-readback.v1"; Jj_id.length_frame rows;
      "child:exited-zero,exited-nonzero,signaled,timed-out,not-reaped";
      "anchor:before-state,partition";
      "law:child-success-and-exact-postcondition;double-decode-deterministic" ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
