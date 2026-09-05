type auxiliary_role =
  | Acquire_clock
  | Observe_external_resource
  | Observe_repository_source
  | Observe_release_bundle
  | Consume_approval_nonce
  | Acquire_writer_lease
  | Renew_writer_lease
  | Release_writer_lease
  | Observe_tree
  | Observe_object
  | Acquire_network_scope
  | Release_network_scope
  | Acquire_credential_lease
  | Release_credential_lease
  | Materialize_candidate
  | Write_partition
  | Restore_partition
  | Restore_sealed_record_preimage
  | Write_sealed_record_candidate
  | Remove_disposable_scope
  | Stage_recovery_set
  | Reconcile_recovery_set
  | Cleanup_recovery_set
  | Verify_candidate_tree
  | Execute_jj_process
  | Readback_jj_state
  | Reserve_completion_receipt
  | Finalize_completion_receipt
  | Execute_formal_oracle

type candidate_step =
  | Toolchain_check
  | Jj_reverse_cone
  | Jj_live_campaign
  | Jj_formal_receipt_validation
  | Jj_precompletion_readback

type formal_tool = Gospel | Z3 | Rocq | Iris | Quint

type formal_case =
  | Positive
  | Negative_control of Jj_id.Negative_control.t

type formal_process = {
  tool : formal_tool;
  case : formal_case;
}

type activity_frontier = Reconciled_terminal

type frontier_action =
  | Activate_source_recovery_branch
  | Set_activity_frontier of activity_frontier

type t =
  | Jujutsu_operation of Jj_operation.t
  | Auxiliary of auxiliary_role
  | Candidate_process of candidate_step
  | Formal_process of formal_process
  | Frontier_action of frontier_action

let auxiliary_roles =
  [ Acquire_clock; Observe_external_resource; Observe_repository_source;
    Observe_release_bundle; Consume_approval_nonce; Acquire_writer_lease;
    Renew_writer_lease; Release_writer_lease; Observe_tree; Observe_object;
    Acquire_network_scope; Release_network_scope; Acquire_credential_lease;
    Release_credential_lease; Materialize_candidate; Write_partition;
    Restore_partition; Restore_sealed_record_preimage;
    Write_sealed_record_candidate; Remove_disposable_scope;
    Stage_recovery_set; Reconcile_recovery_set; Cleanup_recovery_set;
    Verify_candidate_tree; Execute_jj_process; Readback_jj_state;
    Reserve_completion_receipt; Finalize_completion_receipt;
    Execute_formal_oracle ]

let candidate_steps =
  [ Toolchain_check; Jj_reverse_cone; Jj_live_campaign;
    Jj_formal_receipt_validation; Jj_precompletion_readback ]

let formal_tools = [ Gospel; Z3; Rocq; Iris; Quint ]

let formal_case_schema =
  [ "positive"; "negative-control:<bounded-id>" ]

let frontier_actions =
  [ Activate_source_recovery_branch;
    Set_activity_frontier Reconciled_terminal ]

let auxiliary_role_key = function
  | Acquire_clock -> "acquire-clock"
  | Observe_external_resource -> "observe-external-resource"
  | Observe_repository_source -> "observe-repository-source"
  | Observe_release_bundle -> "observe-release-bundle"
  | Consume_approval_nonce -> "consume-approval-nonce"
  | Acquire_writer_lease -> "acquire-writer-lease"
  | Renew_writer_lease -> "renew-writer-lease"
  | Release_writer_lease -> "release-writer-lease"
  | Observe_tree -> "observe-tree"
  | Observe_object -> "observe-object"
  | Acquire_network_scope -> "acquire-network-scope"
  | Release_network_scope -> "release-network-scope"
  | Acquire_credential_lease -> "acquire-credential-lease"
  | Release_credential_lease -> "release-credential-lease"
  | Materialize_candidate -> "materialize-candidate"
  | Write_partition -> "write-partition"
  | Restore_partition -> "restore-partition"
  | Restore_sealed_record_preimage -> "restore-sealed-record-preimage"
  | Write_sealed_record_candidate -> "write-sealed-record-candidate"
  | Remove_disposable_scope -> "remove-disposable-scope"
  | Stage_recovery_set -> "stage-recovery-set"
  | Reconcile_recovery_set -> "reconcile-recovery-set"
  | Cleanup_recovery_set -> "cleanup-recovery-set"
  | Verify_candidate_tree -> "verify-candidate-tree"
  | Execute_jj_process -> "execute-jj-process"
  | Readback_jj_state -> "readback-jj-state"
  | Reserve_completion_receipt -> "reserve-completion-receipt"
  | Finalize_completion_receipt -> "finalize-completion-receipt"
  | Execute_formal_oracle -> "execute-formal-oracle"

let candidate_step_key = function
  | Toolchain_check -> "toolchain-check"
  | Jj_reverse_cone -> "jj-reverse-cone"
  | Jj_live_campaign -> "jj-live-campaign"
  | Jj_formal_receipt_validation -> "jj-formal-receipt-validation"
  | Jj_precompletion_readback -> "jj-precompletion-readback"

let formal_tool_key = function
  | Gospel -> "gospel"
  | Z3 -> "z3"
  | Rocq -> "rocq"
  | Iris -> "iris"
  | Quint -> "quint"

let formal_process ~tool ~case = { tool; case }

let formal_process_tool process = process.tool

let formal_process_case process = process.case

let formal_case_key = function
  | Positive -> "positive"
  | Negative_control identity ->
      "negative-control:" ^ Jj_id.Negative_control.to_string identity

let formal_process_key process =
  formal_tool_key process.tool ^ ":" ^ formal_case_key process.case

let frontier_action_key = function
  | Activate_source_recovery_branch -> "activate-source-recovery-branch"
  | Set_activity_frontier Reconciled_terminal ->
      "set-activity-frontier:reconciled-terminal"

let action_key = function
  | Jujutsu_operation operation ->
      "jujutsu:" ^ (Jj_operation.declaration operation).key
  | Auxiliary role -> "auxiliary:" ^ auxiliary_role_key role
  | Candidate_process step -> "candidate-process:" ^ candidate_step_key step
  | Formal_process process -> "formal-process:" ^ formal_process_key process
  | Frontier_action action -> "frontier:" ^ frontier_action_key action

let digest_denominators ~auxiliary_roles ~candidate_steps ~formal_tools
    ~formal_case_schema ~frontier_actions =
  let section name values =
    Jj_id.length_frame (name :: values)
  in
  String.concat "\n"
    [ section "operation-authority" [ Jj_operation.source_digest ];
      section "auxiliary-role"
        (List.map auxiliary_role_key auxiliary_roles);
      section "candidate-step"
        (List.map candidate_step_key candidate_steps);
      section "formal-tool" (List.map formal_tool_key formal_tools);
      section "formal-case-schema" formal_case_schema;
      section "frontier-action"
        (List.map frontier_action_key frontier_actions) ]
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let source_digest =
  digest_denominators ~auxiliary_roles ~candidate_steps ~formal_tools
    ~formal_case_schema ~frontier_actions

module For_test = struct
  let digest_denominators = digest_denominators
end
