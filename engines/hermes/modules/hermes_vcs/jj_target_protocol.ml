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

let all =
  [ Clock; External_resource; Repository_source; Approval; Writer_lease;
    Transition; Mutation_frontier; Network_scope; Credential_lease;
    Filesystem_materialization; Candidate_verification; Release;
    Completion_receipt; Jujutsu; Formal ]

let key = function
  | Clock -> "clock"
  | External_resource -> "external-resource"
  | Repository_source -> "repository-source"
  | Approval -> "approval"
  | Writer_lease -> "writer-lease"
  | Transition -> "transition"
  | Mutation_frontier -> "mutation-frontier"
  | Network_scope -> "network-scope"
  | Credential_lease -> "credential-lease"
  | Filesystem_materialization -> "filesystem-materialization"
  | Candidate_verification -> "candidate-verification"
  | Release -> "release"
  | Completion_receipt -> "completion-receipt"
  | Jujutsu -> "jujutsu"
  | Formal -> "formal"

let auxiliary_target = function
  | Jj_action_kind.Acquire_clock -> Clock
  | Observe_external_resource -> External_resource
  | Observe_repository_source | Observe_tree | Observe_object -> Repository_source
  | Observe_release_bundle -> Release
  | Consume_approval_nonce -> Approval
  | Acquire_writer_lease | Renew_writer_lease | Release_writer_lease -> Writer_lease
  | Acquire_network_scope | Release_network_scope -> Network_scope
  | Acquire_credential_lease | Release_credential_lease -> Credential_lease
  | Materialize_candidate | Write_partition | Restore_partition
  | Restore_sealed_record_preimage | Write_sealed_record_candidate
  | Remove_disposable_scope -> Filesystem_materialization
  | Stage_recovery_set | Reconcile_recovery_set | Cleanup_recovery_set -> Transition
  | Verify_candidate_tree -> Candidate_verification
  | Execute_jj_process | Readback_jj_state -> Jujutsu
  | Reserve_completion_receipt | Finalize_completion_receipt -> Completion_receipt
  | Execute_formal_oracle -> Formal

let target = function
  | Jj_action_kind.Jujutsu_operation _ -> Jujutsu
  | Auxiliary role -> auxiliary_target role
  | Candidate_process _ -> Candidate_verification
  | Formal_process _ -> Formal
  | Frontier_action Activate_source_recovery_branch -> Transition
  | Frontier_action (Set_activity_frontier Reconciled_terminal) -> Mutation_frontier

let declared_actions =
  List.map (fun operation -> Jj_action_kind.Jujutsu_operation operation)
    Jj_operation.all
  @ List.map (fun role -> Jj_action_kind.Auxiliary role)
      Jj_action_kind.auxiliary_roles
  @ List.map (fun step -> Jj_action_kind.Candidate_process step)
      Jj_action_kind.candidate_steps
  @ List.map
      (fun tool ->
        Jj_action_kind.Formal_process
          (Jj_action_kind.formal_process ~tool
             ~case:Jj_action_kind.Positive))
      Jj_action_kind.formal_tools
  @ List.map (fun action -> Jj_action_kind.Frontier_action action)
      Jj_action_kind.frontier_actions

let source_digest =
  [ Jj_action_kind.source_digest;
    Jj_id.length_frame (List.map key all);
    "formal-process:any-manifest-case:formal";
    Jj_id.length_frame
      (List.map
      (fun action ->
        Jj_id.length_frame
          [ Jj_action_kind.action_key action; key (target action) ])
      declared_actions) ]
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex
