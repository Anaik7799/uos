open Ops_external_resource_target
module Receipt = Jj_receipt
module Repository = Ops_repository_source_target
module Approval = Ops_jj_approval_target
module Writer_lease = Ops_jj_writer_lease_target
module Transition = Ops_jj_transition_target
module Mutation_frontier = Ops_jj_mutation_frontier_target
module Network_scope = Ops_network_scope_target
module Credential_lease = Ops_credential_lease_target
module Filesystem_materialization = Ops_filesystem_materialization_target
module Candidate_verification = Ops_candidate_tree_verification_target
module Release = Ops_jj_release_target

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.eprintf "FAILED: %s\n" name
  end

let unavailable_is_exact = function
  | Error diagnostics ->
      List.map diagnostic_prerequisite diagnostics = prerequisites
      && List.for_all
           (fun diagnostic ->
             diagnostic_coordinate diagnostic
             = "L3/Orient/ops-external-resource-target"
             && diagnostic_origin diagnostic = `Evidence)
           diagnostics
  | Ok _ -> false

let receipt_unavailable_is_exact = function
  | Error diagnostics ->
      List.map Receipt.diagnostic_prerequisite diagnostics
      = Receipt.prerequisites
      && List.for_all
           (fun diagnostic ->
             Receipt.diagnostic_coordinate diagnostic
             = "L3/Orient/jj-receipt-integration"
             && Receipt.diagnostic_origin diagnostic = `Evidence)
           diagnostics
  | Ok _ -> false

let repository_unavailable_is_exact = function
  | Error diagnostics ->
      List.map Repository.diagnostic_prerequisite diagnostics
      = Repository.prerequisites
      && List.for_all
           (fun diagnostic ->
             Repository.diagnostic_coordinate diagnostic
             = "L3/Orient/ops-repository-source-target"
             && Repository.diagnostic_origin diagnostic = `Evidence)
           diagnostics
  | Ok _ -> false

let approval_unavailable_is_exact = function
  | Error diagnostics ->
      List.map Approval.diagnostic_prerequisite diagnostics
      = Approval.prerequisites
      && List.for_all
           (fun diagnostic ->
             Approval.diagnostic_coordinate diagnostic
             = "L3/Orient/ops-jj-approval-target"
             && Approval.diagnostic_origin diagnostic = `Evidence)
           diagnostics
  | Ok _ -> false

let writer_lease_unavailable_is_exact = function
  | Error diagnostics ->
      List.map Writer_lease.diagnostic_prerequisite diagnostics
      = Writer_lease.prerequisites
      && List.for_all
           (fun diagnostic ->
             Writer_lease.diagnostic_coordinate diagnostic
             = "L3/Orient/ops-jj-writer-lease-target"
             && Writer_lease.diagnostic_origin diagnostic = `Evidence)
           diagnostics
  | Ok _ -> false

let transition_unavailable_is_exact = function
  | Error diagnostics ->
      List.map Transition.diagnostic_prerequisite diagnostics
      = Transition.prerequisites
      && List.for_all
           (fun diagnostic ->
             Transition.diagnostic_coordinate diagnostic
             = "L3/Orient/ops-jj-transition-target"
             && Transition.diagnostic_origin diagnostic = `Evidence)
           diagnostics
  | Ok _ -> false

let mutation_frontier_unavailable_is_exact = function
  | Error diagnostics ->
      List.map Mutation_frontier.diagnostic_prerequisite diagnostics
      = Mutation_frontier.prerequisites
      && List.for_all
           (fun diagnostic ->
             Mutation_frontier.diagnostic_coordinate diagnostic
             = "L3/Orient/ops-jj-mutation-frontier-target"
             && Mutation_frontier.diagnostic_origin diagnostic = `Evidence)
           diagnostics
  | Ok _ -> false

let network_scope_unavailable_is_exact = function
  | Error diagnostics ->
      List.map Network_scope.diagnostic_prerequisite diagnostics
      = Network_scope.prerequisites
      && List.for_all
           (fun diagnostic ->
             Network_scope.diagnostic_coordinate diagnostic
             = "L3/Orient/ops-network-scope-target"
             && Network_scope.diagnostic_origin diagnostic = `Evidence)
           diagnostics
  | Ok _ -> false

let credential_lease_unavailable_is_exact = function
  | Error diagnostics ->
      List.map Credential_lease.diagnostic_prerequisite diagnostics
      = Credential_lease.prerequisites
      && List.for_all
           (fun diagnostic ->
             Credential_lease.diagnostic_coordinate diagnostic
             = "L3/Orient/ops-credential-lease-target"
             && Credential_lease.diagnostic_origin diagnostic = `Evidence)
           diagnostics
  | Ok _ -> false

let filesystem_materialization_unavailable_is_exact = function
  | Error diagnostics ->
      List.map Filesystem_materialization.diagnostic_prerequisite diagnostics
      = Filesystem_materialization.prerequisites
      && List.for_all
           (fun diagnostic ->
             Filesystem_materialization.diagnostic_coordinate diagnostic
             = "L3/Orient/ops-filesystem-materialization-target"
             && Filesystem_materialization.diagnostic_origin diagnostic
                = `Evidence)
           diagnostics
  | Ok _ -> false

let candidate_verification_unavailable_is_exact = function
  | Error diagnostics ->
      List.map Candidate_verification.diagnostic_prerequisite diagnostics
      = Candidate_verification.prerequisites
      && List.for_all
           (fun diagnostic ->
             Candidate_verification.diagnostic_coordinate diagnostic
             = "L3/Orient/ops-candidate-tree-verification-target"
             && Candidate_verification.diagnostic_origin diagnostic
                = `Evidence)
           diagnostics
  | Ok _ -> false

let release_unavailable_is_exact = function
  | Error diagnostics ->
      List.map Release.diagnostic_prerequisite diagnostics
      = Release.prerequisites
      && List.for_all
           (fun diagnostic ->
             Release.diagnostic_coordinate diagnostic
             = "L3/Orient/ops-jj-release-target"
             && Release.diagnostic_origin diagnostic = `Evidence)
           diagnostics
  | Ok _ -> false

let () =
  check "J09T01 external resource target owns one protocol role and effect"
    (Jj_runtime_manifest.declaration_key runtime_declaration
       = "target.external-resource"
     && Jj_runtime_manifest.declaration_digest runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.target_external_resource
     && target_protocol = Jj_target_protocol.External_resource
     && accepted_roles = [ Jj_action_kind.Observe_external_resource ]
     && accepted_effects = [ Run_topology.External_resource_observation ]
     && Jj_target_protocol.target
          (Jj_action_kind.Auxiliary
             Jj_action_kind.Observe_external_resource)
        = target_protocol);
  check "J09T02 owner and host-current production stay exact unavailable"
    (production_posture = `Implemented_unavailable
     && prerequisites
        = [ Target_owner_part_current; Controlled_resource_observer;
            Receipt_bound_resource_envelope; Event_effect_readback_current ]
     && unavailable_is_exact (create_owner_unavailable ()));
  let mutations =
    [ For_test.Drop_runtime_manifest_source;
      For_test.Drop_target_protocol_source;
      For_test.Drop_action_kind_source; For_test.Drop_topology_source;
      For_test.Drop_runtime_declaration;
      For_test.Substitute_runtime_declaration;
      For_test.Drop_target_protocol; For_test.Drop_role; For_test.Add_role;
      For_test.Drop_effect; For_test.Add_effect; For_test.Drop_owner_part;
      For_test.Drop_resource_observer; For_test.Drop_receipt_bound_envelope;
      For_test.Drop_event_effect_readback; For_test.Add_raw_host;
      For_test.Add_raw_path; For_test.Add_environment;
      For_test.Add_executable; For_test.Add_probe_callback;
      For_test.Promote_unavailable_evidence;
      For_test.Add_current_constructor ]
  in
  check "J09T03 source authority kills every denominator and escape mutant"
    (String.length source_digest = 64
     && List.for_all
          (fun mutation ->
            source_digest <> For_test.source_digest_with_mutation mutation)
          mutations);
  check "J09T04 receipt facade refuses the exact absent integration join"
    (Receipt.production_posture = `Implemented_unavailable
     && Receipt.prerequisites
        = [ Receipt.Preparation_current; Receipt.Activity_result_current;
            Receipt.Event_prefix_current; Receipt.Readback_current;
            Receipt.Composed_authority_current ]
     && receipt_unavailable_is_exact (Receipt.finalize_unavailable ()));
  let receipt_mutations =
    [ Receipt.For_test.Drop_preparation;
      Receipt.For_test.Drop_activity_result;
      Receipt.For_test.Drop_event_prefix;
      Receipt.For_test.Drop_readback;
      Receipt.For_test.Drop_composed_authority;
      Receipt.For_test.Reorder_prerequisites;
      Receipt.For_test.Substitute_event_prefix;
      Receipt.For_test.Drop_core_source;
      Receipt.For_test.Add_owner_receipt_constructor;
      Receipt.For_test.Expose_payload;
      Receipt.For_test.Expose_capability;
      Receipt.For_test.Accept_caller_digest;
      Receipt.For_test.Promote_current ]
  in
  check "J09T05 receipt source identity kills every join and escape mutant"
    (String.length Receipt.source_digest = 64
     && List.for_all
          (fun mutation ->
            Receipt.source_digest
            <> Receipt.For_test.source_digest_with_mutation mutation)
          receipt_mutations);
  check "J09T06 repository source owns exact protocol roles and effect"
    (Jj_runtime_manifest.declaration_key Repository.runtime_declaration
       = "target.repository-source"
     && Jj_runtime_manifest.declaration_digest Repository.runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.target_repository_source
     && Repository.target_protocol = Jj_target_protocol.Repository_source
     && Repository.accepted_roles
        = [ Jj_action_kind.Observe_repository_source;
            Jj_action_kind.Observe_tree; Jj_action_kind.Observe_object ]
     && Repository.accepted_effects
        = [ Run_topology.Repository_source_observation ]
     && List.for_all
          (fun role ->
            Jj_target_protocol.target (Jj_action_kind.Auxiliary role)
            = Repository.target_protocol)
          Repository.accepted_roles);
  check "J09T07 A0 and production prerequisites are exact and unavailable"
    (Repository.a0_operations
     = [ Jj_operation.Operation_head; Jj_operation.Status_at_operation;
         Jj_operation.Resolve_list_at_operation;
         Jj_operation.Operation_log_at_operation;
         Jj_operation.Revision_log_at_operation;
         Jj_operation.Bookmark_list_at_operation;
         Jj_operation.Workspace_list_at_operation;
         Jj_operation.Remote_list_at_operation;
         Jj_operation.Diff_summary_at_operation;
         Jj_operation.Diff_stat_at_operation;
         Jj_operation.Diff_patch_at_operation ]
     && Repository.prerequisites
        = [ Repository.Target_owner_part_current;
            Repository.Production_root_config_current;
            Repository.Controlled_filesystem_observer;
            Repository.Dependency_authority_current;
            Repository.External_resource_host_current;
            Repository.Jujutsu_operation_readbacks_current;
            Repository.Event_prefix_current;
            Repository.Effect_target_registry_current ]
     && Repository.production_posture = `Implemented_unavailable
     && repository_unavailable_is_exact
          (Repository.create_owner_unavailable ()));
  let repository_mutations =
    [ Repository.For_test.Drop_runtime_manifest_source;
      Repository.For_test.Drop_target_protocol_source;
      Repository.For_test.Drop_action_kind_source;
      Repository.For_test.Drop_operation_source;
      Repository.For_test.Drop_topology_source;
      Repository.For_test.Drop_runtime_declaration;
      Repository.For_test.Substitute_runtime_declaration;
      Repository.For_test.Drop_target_protocol;
      Repository.For_test.Drop_source_role;
      Repository.For_test.Drop_tree_role;
      Repository.For_test.Drop_object_role;
      Repository.For_test.Add_role;
      Repository.For_test.Drop_effect;
      Repository.For_test.Add_effect;
      Repository.For_test.Drop_a0_operation;
      Repository.For_test.Reorder_a0_operations;
      Repository.For_test.Duplicate_a0_operation;
      Repository.For_test.Drop_prerequisite;
      Repository.For_test.Reorder_prerequisites;
      Repository.For_test.Add_raw_root;
      Repository.For_test.Add_raw_path;
      Repository.For_test.Add_source_bytes;
      Repository.For_test.Add_manifest_input;
      Repository.For_test.Add_secret_scan_input;
      Repository.For_test.Add_environment;
      Repository.For_test.Add_process;
      Repository.For_test.Add_network;
      Repository.For_test.Add_probe_callback;
      Repository.For_test.Accept_caller_digest;
      Repository.For_test.Promote_disposable_receipt;
      Repository.For_test.Add_current_constructor ]
  in
  check "J09T08 repository source identity kills denominator and escape mutants"
    (String.length Repository.source_digest = 64
     && List.for_all
          (fun mutation ->
            Repository.source_digest
            <> Repository.For_test.source_digest_with_mutation mutation)
          repository_mutations);
  check "J09T09 approval target owns its exact declaration protocol role and effect"
    (Jj_runtime_manifest.declaration_key Approval.runtime_declaration
       = "target.approval"
     && Jj_runtime_manifest.declaration_digest Approval.runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.target_approval
     && Approval.target_protocol = Jj_target_protocol.Approval
     && Approval.accepted_roles = [ Jj_action_kind.Consume_approval_nonce ]
     && Approval.accepted_effects
        = [ Run_topology.Approval_nonce_consumption ]
     && Jj_target_protocol.target
          (Jj_action_kind.Auxiliary Jj_action_kind.Consume_approval_nonce)
        = Approval.target_protocol);
  check "J09T10 approval owner and Current receipt stay exact unavailable"
    (Approval.prerequisites
     = [ Approval.Target_owner_part_current;
         Approval.Approval_owner_current;
         Approval.Campaign_open_current_carrier;
         Approval.Request_bound_guard_current_carrier;
         Approval.Approval_nonce_transition_current;
         Approval.Dependency_carrier_owner_current;
         Approval.Event_effect_readback_current ]
     && Approval.production_posture = `Implemented_unavailable
     && approval_unavailable_is_exact (Approval.create_owner_unavailable ()));
  let approval_mutations =
    [ Approval.For_test.Drop_runtime_manifest_source;
      Approval.For_test.Drop_target_protocol_source;
      Approval.For_test.Drop_action_kind_source;
      Approval.For_test.Drop_topology_source;
      Approval.For_test.Drop_approval_owner_source;
      Approval.For_test.Drop_runtime_declaration;
      Approval.For_test.Substitute_runtime_declaration;
      Approval.For_test.Drop_target_protocol;
      Approval.For_test.Drop_role;
      Approval.For_test.Add_role;
      Approval.For_test.Drop_effect;
      Approval.For_test.Add_effect;
      Approval.For_test.Drop_prerequisite;
      Approval.For_test.Reorder_prerequisites;
      Approval.For_test.Substitute_prerequisite;
      Approval.For_test.Add_public_key;
      Approval.For_test.Add_signature;
      Approval.For_test.Add_nonce;
      Approval.For_test.Expose_capability;
      Approval.For_test.Add_callback;
      Approval.For_test.Accept_caller_digest;
      Approval.For_test.Add_current_constructor ]
  in
  check "J09T11 approval source identity kills 22 denominator and escape mutants"
    (String.length Approval.source_digest = 64
     && List.length approval_mutations = 22
     && List.for_all
          (fun mutation ->
            Approval.source_digest
            <> Approval.For_test.source_digest_with_mutation mutation)
          approval_mutations);
  check "J09T12 writer lease owns its exact declaration protocol roles and effect"
    (Jj_runtime_manifest.declaration_key Writer_lease.runtime_declaration
       = "target.writer-lease"
     && Jj_runtime_manifest.declaration_digest Writer_lease.runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.target_writer_lease
     && Writer_lease.target_protocol = Jj_target_protocol.Writer_lease
     && Writer_lease.accepted_roles
        = [ Jj_action_kind.Acquire_writer_lease;
            Jj_action_kind.Renew_writer_lease;
            Jj_action_kind.Release_writer_lease ]
     && Writer_lease.accepted_effects
        = [ Run_topology.Writer_lease_transition ]
     && List.for_all
          (fun role ->
            Jj_target_protocol.target (Jj_action_kind.Auxiliary role)
            = Writer_lease.target_protocol)
          Writer_lease.accepted_roles);
  check "J09T13 writer lease owner and Current receipt stay exact unavailable"
    (Writer_lease.prerequisites
     = [ Writer_lease.Target_owner_part_current;
         Writer_lease.Writer_lease_operational_owner_current;
         Writer_lease.Physical_owner_lock_backend;
         Writer_lease.Authority_role_session_fence;
         Writer_lease.Nominal_writer_peer_open_fence;
         Writer_lease.Authority_writer_fence_transition;
         Writer_lease.Approval_occurrence_capability_current;
         Writer_lease.Bounded_clock_current_carrier;
         Writer_lease.Repository_before_state_current_carrier;
         Writer_lease.Quiescence_or_fenced_session_current_carrier;
         Writer_lease.Mutation_frontier_release_eligibility_current;
         Writer_lease.Dependency_carrier_owner_current;
         Writer_lease.Event_effect_readback_current ]
     && Writer_lease.production_posture = `Implemented_unavailable
     && writer_lease_unavailable_is_exact
          (Writer_lease.create_owner_unavailable ()));
  let writer_lease_mutations =
    [ Writer_lease.For_test.Drop_runtime_manifest_source;
      Writer_lease.For_test.Drop_target_protocol_source;
      Writer_lease.For_test.Drop_action_kind_source;
      Writer_lease.For_test.Drop_topology_source;
      Writer_lease.For_test.Drop_writer_lease_owner_source;
      Writer_lease.For_test.Drop_runtime_declaration;
      Writer_lease.For_test.Substitute_runtime_declaration;
      Writer_lease.For_test.Drop_target_protocol;
      Writer_lease.For_test.Drop_acquire_role;
      Writer_lease.For_test.Drop_renew_role;
      Writer_lease.For_test.Drop_release_role;
      Writer_lease.For_test.Reorder_roles;
      Writer_lease.For_test.Add_role;
      Writer_lease.For_test.Drop_effect;
      Writer_lease.For_test.Add_effect;
      Writer_lease.For_test.Drop_prerequisite;
      Writer_lease.For_test.Reorder_prerequisites;
      Writer_lease.For_test.Duplicate_prerequisite;
      Writer_lease.For_test.Substitute_prerequisite;
      Writer_lease.For_test.Permit_acquire_without_lock;
      Writer_lease.For_test.Permit_renew_without_held;
      Writer_lease.For_test.Permit_release_after_unreconciled;
      Writer_lease.For_test.Permit_release_without_frontier;
      Writer_lease.For_test.Permit_cross_session_lease;
      Writer_lease.For_test.Permit_cross_repository_lease;
      Writer_lease.For_test.Accept_raw_lock;
      Writer_lease.For_test.Accept_raw_time;
      Writer_lease.For_test.Accept_raw_lease;
      Writer_lease.For_test.Expose_capability;
      Writer_lease.For_test.Add_callback;
      Writer_lease.For_test.Accept_caller_digest;
      Writer_lease.For_test.Add_current_constructor;
      Writer_lease.For_test.Forge_registration;
      Writer_lease.For_test.Promote_lower_contract;
      Writer_lease.For_test.Merge_acquire_renew_release ]
  in
  check "J09T14 writer lease source kills 35 safety and escape mutants"
    (String.length Writer_lease.source_digest = 64
     && List.length writer_lease_mutations = 35
     && List.for_all
          (fun mutation ->
            Writer_lease.source_digest
            <> Writer_lease.For_test.source_digest_with_mutation mutation)
          writer_lease_mutations);
  check "J09T15 transition target owns exact declaration actions and effects"
    (Jj_runtime_manifest.declaration_key Transition.runtime_declaration
       = "target.transition"
     && Jj_runtime_manifest.declaration_digest Transition.runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.target_transition
     && Transition.target_protocol = Jj_target_protocol.Transition
     && Transition.accepted_roles
        = [ Jj_action_kind.Stage_recovery_set;
            Jj_action_kind.Reconcile_recovery_set;
            Jj_action_kind.Cleanup_recovery_set ]
     && Transition.accepted_frontiers
        = [ Jj_action_kind.Activate_source_recovery_branch ]
     && Transition.accepted_effects
        = [ Run_topology.Controlled_filesystem_materialization;
            Run_topology.Production_activation_transition ]
     && List.for_all
          (fun role ->
            Jj_target_protocol.target (Jj_action_kind.Auxiliary role)
            = Transition.target_protocol)
          Transition.accepted_roles
     && List.for_all
          (fun frontier ->
            Jj_target_protocol.target (Jj_action_kind.Frontier_action frontier)
            = Transition.target_protocol)
          Transition.accepted_frontiers);
  check "J09T16 transition bindings and unavailable prerequisites are exact"
    (Transition.binding_ids
     = [ "auxiliary:stage-recovery-set->controlled-filesystem-materialization";
         "auxiliary:reconcile-recovery-set->controlled-filesystem-materialization";
         "auxiliary:cleanup-recovery-set->controlled-filesystem-materialization";
         "frontier:activate-source-recovery-branch->production-activation-transition" ]
     && Transition.prerequisites
        = [ Transition.Target_owner_part_current;
            Transition.Recovery_vault_owner_current;
            Transition.Recovery_transition_port_vault_current;
            Transition.Execution_local_transition_resolver_current;
            Transition.Recovery_transition_reference_current_carrier;
            Transition.Source_change_transition_commitment_current_carrier;
            Transition.B_selected_decision_current_carrier;
            Transition.Owner_produced_prefix_current_carrier;
            Transition.Apply_once_pending_transition_conversion_current;
            Transition.Dependency_carrier_owner_current;
            Transition.Effect_target_registration_current;
            Transition.Event_effect_readback_current ]
     && Transition.production_posture = `Implemented_unavailable
     && transition_unavailable_is_exact
          (Transition.create_owner_unavailable ()));
  let transition_mutations =
    [ Transition.For_test.Drop_runtime_manifest_source;
      Transition.For_test.Drop_target_protocol_source;
      Transition.For_test.Drop_action_kind_source;
      Transition.For_test.Drop_topology_source;
      Transition.For_test.Drop_recovery_vault_source;
      Transition.For_test.Drop_transition_port_protocol_source;
      Transition.For_test.Drop_runtime_declaration;
      Transition.For_test.Substitute_runtime_declaration;
      Transition.For_test.Drop_target_protocol;
      Transition.For_test.Drop_stage_role;
      Transition.For_test.Drop_reconcile_role;
      Transition.For_test.Drop_cleanup_role;
      Transition.For_test.Reorder_roles;
      Transition.For_test.Add_role;
      Transition.For_test.Drop_frontier;
      Transition.For_test.Substitute_frontier;
      Transition.For_test.Drop_filesystem_effect;
      Transition.For_test.Drop_activation_effect;
      Transition.For_test.Reorder_effects;
      Transition.For_test.Add_effect;
      Transition.For_test.Drop_stage_binding;
      Transition.For_test.Drop_reconcile_binding;
      Transition.For_test.Drop_cleanup_binding;
      Transition.For_test.Drop_activation_binding;
      Transition.For_test.Reorder_bindings;
      Transition.For_test.Duplicate_binding;
      Transition.For_test.Swap_stage_activation_effect_binding;
      Transition.For_test.Bind_reconcile_to_activation_effect;
      Transition.For_test.Bind_activation_to_filesystem_effect;
      Transition.For_test.Drop_prerequisite;
      Transition.For_test.Reorder_prerequisites;
      Transition.For_test.Duplicate_prerequisite;
      Transition.For_test.Substitute_prerequisite;
      Transition.For_test.Permit_stage_without_vault;
      Transition.For_test.Permit_reconcile_without_prefix;
      Transition.For_test.Permit_cleanup_before_terminal;
      Transition.For_test.Permit_activation_without_selected_decision;
      Transition.For_test.Permit_activation_without_commitment;
      Transition.For_test.Permit_cross_session_reference;
      Transition.For_test.Permit_cross_activity_reference;
      Transition.For_test.Permit_cross_generation_reference;
      Transition.For_test.Accept_caller_cut;
      Transition.For_test.Accept_caller_effect;
      Transition.For_test.Add_raw_path;
      Transition.For_test.Add_raw_bytes;
      Transition.For_test.Expose_vault_capability;
      Transition.For_test.Expose_transition_port;
      Transition.For_test.Add_callback;
      Transition.For_test.Accept_caller_digest;
      Transition.For_test.Add_registration_constructor;
      Transition.For_test.Add_current_constructor;
      Transition.For_test.Merge_recovery_role_allocation ]
  in
  check "J09T17 transition source kills 52 binding safety and escape mutants"
    (String.length Transition.source_digest = 64
     && List.length transition_mutations = 52
     && List.for_all
          (fun mutation ->
            Transition.source_digest
            <> Transition.For_test.source_digest_with_mutation mutation)
          transition_mutations);
  check "J09T18 mutation frontier owns exact declaration action and effect"
    (Jj_runtime_manifest.declaration_key
       Mutation_frontier.runtime_declaration
       = "target.mutation-frontier"
     && Jj_runtime_manifest.declaration_digest
          Mutation_frontier.runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.target_mutation_frontier
     && Mutation_frontier.target_protocol = Jj_target_protocol.Mutation_frontier
     && Mutation_frontier.accepted_roles = []
     && Mutation_frontier.accepted_frontiers
        = [ Jj_action_kind.Set_activity_frontier
              Jj_action_kind.Reconciled_terminal ]
     && Mutation_frontier.accepted_effects
        = [ Run_topology.Jujutsu_local_mutation ]
     && Jj_target_protocol.target
          (Jj_action_kind.Frontier_action
             (Jj_action_kind.Set_activity_frontier
                Jj_action_kind.Reconciled_terminal))
        = Mutation_frontier.target_protocol
     && Jj_target_protocol.target
          (Jj_action_kind.Frontier_action
             Jj_action_kind.Activate_source_recovery_branch)
        = Jj_target_protocol.Transition
     && Run_topology.action_work_gaps
          (Run_topology.Mutation_frontier_work
             (Jj_action_kind.Set_activity_frontier
                Jj_action_kind.Reconciled_terminal))
        = []);
  check "J09T19 mutation frontier terminal families and prerequisites are exact"
    (Mutation_frontier.terminal_readback_families
     = [ Mutation_frontier.Normal_b;
         Mutation_frontier.B_selected_recovery;
         Mutation_frontier.B_restarted_recovery;
         Mutation_frontier.Completion_record;
         Mutation_frontier.Completion_record_selected_recovery;
         Mutation_frontier.Completion_record_restarted_recovery;
         Mutation_frontier.Completion_final;
         Mutation_frontier.Completion_reconcile_applied_exact;
         Mutation_frontier.Completion_reconcile_not_applied ]
     && List.map Mutation_frontier.terminal_readback_family_id
          Mutation_frontier.terminal_readback_families
        = [ "normal-b"; "b-selected-recovery"; "b-restarted-recovery";
            "completion-record"; "completion-record-selected-recovery";
            "completion-record-restarted-recovery"; "completion-final";
            "completion-reconcile-applied-exact";
            "completion-reconcile-not-applied" ]
     && Mutation_frontier.prerequisites
        = [ Mutation_frontier.Target_owner_part_current;
            Mutation_frontier.Mutation_frontier_operational_owner_current;
            Mutation_frontier.Activity_generation_current_carrier;
            Mutation_frontier.Approval_occurrence_capability_current;
            Mutation_frontier.Writer_fence_session_current_carrier;
            Mutation_frontier.Normal_b_terminal_readback_current_carrier;
            Mutation_frontier.B_selected_recovery_terminal_readback_current_carrier;
            Mutation_frontier.B_restarted_recovery_terminal_readback_current_carrier;
            Mutation_frontier.Completion_record_terminal_readback_current_carrier;
            Mutation_frontier.Completion_record_selected_recovery_terminal_readback_current_carrier;
            Mutation_frontier.Completion_record_restarted_recovery_terminal_readback_current_carrier;
            Mutation_frontier.Completion_final_terminal_readback_current_carrier;
            Mutation_frontier.Completion_reconcile_applied_exact_terminal_readback_current_carrier;
            Mutation_frontier.Completion_reconcile_not_applied_terminal_readback_current_carrier;
            Mutation_frontier.Monotone_frontier_store_current;
            Mutation_frontier.Dependency_carrier_owner_current;
            Mutation_frontier.Effect_target_registration_current;
            Mutation_frontier.Event_effect_readback_current ]
     && Mutation_frontier.production_posture = `Implemented_unavailable
     && mutation_frontier_unavailable_is_exact
          (Mutation_frontier.create_owner_unavailable ()));
  let mutation_frontier_mutations =
    [ Mutation_frontier.For_test.Drop_runtime_manifest_source;
      Mutation_frontier.For_test.Drop_target_protocol_source;
      Mutation_frontier.For_test.Drop_action_kind_source;
      Mutation_frontier.For_test.Drop_campaign_action_source;
      Mutation_frontier.For_test.Drop_recovery_schema_source;
      Mutation_frontier.For_test.Drop_topology_source;
      Mutation_frontier.For_test.Drop_approval_source;
      Mutation_frontier.For_test.Drop_writer_lease_source;
      Mutation_frontier.For_test.Drop_root_bootstrap_source;
      Mutation_frontier.For_test.Drop_conditional_authority_source;
      Mutation_frontier.For_test.Drop_dependency_authority_source;
      Mutation_frontier.For_test.Drop_event_prefix_source;
      Mutation_frontier.For_test.Drop_runtime_current_protocol_source;
      Mutation_frontier.For_test.Drop_runtime_registry_source;
      Mutation_frontier.For_test.Drop_target_registry_schema;
      Mutation_frontier.For_test.Drop_runtime_declaration;
      Mutation_frontier.For_test.Substitute_runtime_declaration;
      Mutation_frontier.For_test.Drop_target_protocol;
      Mutation_frontier.For_test.Substitute_transition_protocol;
      Mutation_frontier.For_test.Add_auxiliary_role;
      Mutation_frontier.For_test.Drop_frontier_action;
      Mutation_frontier.For_test.Substitute_activation_frontier;
      Mutation_frontier.For_test.Add_frontier_action;
      Mutation_frontier.For_test.Drop_effect;
      Mutation_frontier.For_test.Substitute_activation_effect;
      Mutation_frontier.For_test.Add_effect;
      Mutation_frontier.For_test.Drop_terminal_readback_family;
      Mutation_frontier.For_test.Reorder_terminal_readback_families;
      Mutation_frontier.For_test.Duplicate_terminal_readback_family;
      Mutation_frontier.For_test.Add_diverged_terminal_readback_family;
      Mutation_frontier.For_test.Merge_b_selected_restarted;
      Mutation_frontier.For_test.Merge_record_selected_restarted;
      Mutation_frontier.For_test.Merge_reconcile_outcomes;
      Mutation_frontier.For_test.Drop_prerequisite;
      Mutation_frontier.For_test.Reorder_prerequisites;
      Mutation_frontier.For_test.Duplicate_prerequisite;
      Mutation_frontier.For_test.Substitute_prerequisite;
      Mutation_frontier.For_test.Permit_early_terminal_frontier;
      Mutation_frontier.For_test.Permit_missing_readback;
      Mutation_frontier.For_test.Permit_noncontiguous_readback_prefix;
      Mutation_frontier.For_test.Permit_cross_target_capability;
      Mutation_frontier.For_test.Permit_cross_activity_capability;
      Mutation_frontier.For_test.Permit_cross_generation_capability;
      Mutation_frontier.For_test.Permit_cross_session_fence;
      Mutation_frontier.For_test.Permit_activation_through_frontier;
      Mutation_frontier.For_test.Permit_branch_selection;
      Mutation_frontier.For_test.Permit_fence_release;
      Mutation_frontier.For_test.Permit_completion_finalize;
      Mutation_frontier.For_test.Permit_repository_effect;
      Mutation_frontier.For_test.Permit_process_effect;
      Mutation_frontier.For_test.Permit_filesystem_effect;
      Mutation_frontier.For_test.Permit_frontier_regression;
      Mutation_frontier.For_test.Permit_changed_replay;
      Mutation_frontier.For_test.Accept_raw_frontier_state;
      Mutation_frontier.For_test.Expose_capability;
      Mutation_frontier.For_test.Add_callback;
      Mutation_frontier.For_test.Accept_caller_digest;
      Mutation_frontier.For_test.Add_registration_constructor;
      Mutation_frontier.For_test.Add_current_constructor;
      Mutation_frontier.For_test.Promote_unavailable_owner ]
  in
  check "J09T20 mutation frontier source kills 60 authority and escape mutants"
    (String.length Mutation_frontier.source_digest = 64
     && List.length mutation_frontier_mutations = 60
     && List.for_all
          (fun mutation ->
            Mutation_frontier.source_digest
            <> Mutation_frontier.For_test.source_digest_with_mutation mutation)
          mutation_frontier_mutations);
  check "J09T21 network scope owns exact declaration routing and effect"
    (Jj_runtime_manifest.declaration_key Network_scope.runtime_declaration
       = "target.network-scope"
     && Jj_runtime_manifest.declaration_digest Network_scope.runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.target_network_scope
     && Network_scope.target_protocol = Jj_target_protocol.Network_scope
     && Network_scope.accepted_roles
        = [ Jj_action_kind.Acquire_network_scope;
            Jj_action_kind.Release_network_scope ]
     && Network_scope.accepted_effects
        = [ Run_topology.Network_scope_transition ]
     && Network_scope.binding_ids
        = [ "auxiliary:acquire-network-scope->network-scope-transition";
            "auxiliary:release-network-scope->network-scope-transition" ]
     && List.for_all
          (fun role ->
            Jj_target_protocol.target (Jj_action_kind.Auxiliary role)
            = Network_scope.target_protocol
            && Run_topology.action_work_gaps
                 (Run_topology.Network_scope_work role)
               = []
            && Option.map Jj_dependency_schema.owner
                 (Jj_dependency_schema.for_role role)
               = Some Jj_dependency_schema.Network_scope_owner)
          Network_scope.accepted_roles);
  check "J09T22 network policies and unavailable prerequisites are exact"
    (Network_scope.operation_policy_binding_ids
     = [ "git-fetch->remote-synchronization->jujutsu-remote-synchronization:local-mutation-approval+writer-lease+recovery-required:implemented-unavailable:remote-activity-scope-actions-omitted";
         "git-push->remote-publication->jujutsu-remote-publish:expected-remote-tip-cas-required:implemented-unavailable:remote-cas-proof-missing" ]
     && Run_topology.effect_kind_of_jujutsu_operation Jj_operation.Git_fetch
        = Run_topology.Jujutsu_remote_synchronization
     && Run_topology.effect_kind_of_jujutsu_operation Jj_operation.Git_push
        = Run_topology.Jujutsu_remote_publish
     && Dependability_network.all_operations
        = [ Dependability_network.Remote_synchronization;
            Dependability_network.Remote_publication ]
     && (Jj_operation.declaration Jj_operation.Git_fetch).recovery
        = Jj_operation.Recovery_before_state
     && (Jj_operation.declaration Jj_operation.Git_push).activation
        = Jj_operation.Implemented_unavailable
     && Network_scope.prerequisites
        = [ Network_scope.Target_owner_part_current;
            Network_scope.Network_scope_operational_owner_current;
            Network_scope.Controlled_network_backend_current;
            Network_scope.Named_remote_identity_current_carrier;
            Network_scope.Remote_operation_intent_current_carrier;
            Network_scope.Credential_lease_current_carrier;
            Network_scope.Bounded_clock_current_carrier;
            Network_scope.Approval_occurrence_capability_current;
            Network_scope.Network_scope_release_eligibility_current;
            Network_scope.Dependency_carrier_owner_current;
            Network_scope.Effect_target_registration_current;
            Network_scope.Event_effect_readback_current ]
     && Network_scope.production_posture = `Implemented_unavailable
     && network_scope_unavailable_is_exact
          (Network_scope.create_owner_unavailable ())); 
  let network_scope_mutations =
    [ Network_scope.For_test.Drop_runtime_manifest_source;
      Network_scope.For_test.Drop_target_protocol_source;
      Network_scope.For_test.Drop_action_kind_source;
      Network_scope.For_test.Drop_operation_source;
      Network_scope.For_test.Drop_dependency_schema_source;
      Network_scope.For_test.Drop_topology_source;
      Network_scope.For_test.Drop_network_owner_source;
      Network_scope.For_test.Drop_runtime_declaration;
      Network_scope.For_test.Substitute_runtime_declaration;
      Network_scope.For_test.Drop_target_protocol;
      Network_scope.For_test.Drop_acquire_role;
      Network_scope.For_test.Drop_release_role;
      Network_scope.For_test.Reorder_roles;
      Network_scope.For_test.Add_role;
      Network_scope.For_test.Drop_effect;
      Network_scope.For_test.Add_effect;
      Network_scope.For_test.Drop_acquire_binding;
      Network_scope.For_test.Drop_release_binding;
      Network_scope.For_test.Reorder_bindings;
      Network_scope.For_test.Duplicate_binding;
      Network_scope.For_test.Bind_release_to_credential_effect;
      Network_scope.For_test.Drop_git_fetch_policy;
      Network_scope.For_test.Drop_git_push_policy;
      Network_scope.For_test.Reorder_operation_policies;
      Network_scope.For_test.Bind_fetch_to_remote_publish;
      Network_scope.For_test.Drop_fetch_local_mutation_authority;
      Network_scope.For_test.Permit_push_without_remote_cas;
      Network_scope.For_test.Claim_remote_activity_projection_complete;
      Network_scope.For_test.Drop_prerequisite;
      Network_scope.For_test.Reorder_prerequisites;
      Network_scope.For_test.Duplicate_prerequisite;
      Network_scope.For_test.Substitute_prerequisite;
      Network_scope.For_test.Permit_acquire_without_backend;
      Network_scope.For_test.Permit_acquire_without_named_remote;
      Network_scope.For_test.Permit_acquire_without_operation_intent;
      Network_scope.For_test.Permit_acquire_without_credential;
      Network_scope.For_test.Permit_acquire_without_clock;
      Network_scope.For_test.Permit_acquire_without_approval;
      Network_scope.For_test.Permit_release_without_eligibility;
      Network_scope.For_test.Permit_release_during_active_operation;
      Network_scope.For_test.Permit_after_expiry;
      Network_scope.For_test.Permit_after_revocation;
      Network_scope.For_test.Permit_after_cleanup;
      Network_scope.For_test.Permit_changed_replay;
      Network_scope.For_test.Accept_raw_remote;
      Network_scope.For_test.Add_raw_endpoint;
      Network_scope.For_test.Add_raw_socket;
      Network_scope.For_test.Add_raw_request_bytes;
      Network_scope.For_test.Expose_credential;
      Network_scope.For_test.Expose_capability;
      Network_scope.For_test.Add_callback;
      Network_scope.For_test.Accept_caller_digest;
      Network_scope.For_test.Add_registration_constructor;
      Network_scope.For_test.Add_current_constructor;
      Network_scope.For_test.Promote_unavailable_backend ]
  in
  check "J09T23 network scope source kills 55 authority and escape mutants"
    (String.length Network_scope.source_digest = 64
     && List.length network_scope_mutations = 55
     && List.for_all
          (fun mutation ->
            Network_scope.source_digest
            <> Network_scope.For_test.source_digest_with_mutation mutation)
          network_scope_mutations);
  check "J09T24 credential lease owns exact declaration routing and effect"
    (Jj_runtime_manifest.declaration_key Credential_lease.runtime_declaration
       = "target.credential-lease"
     && Jj_runtime_manifest.declaration_digest
          Credential_lease.runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.target_credential_lease
     && Credential_lease.target_protocol = Jj_target_protocol.Credential_lease
     && Credential_lease.accepted_roles
        = [ Jj_action_kind.Acquire_credential_lease;
            Jj_action_kind.Release_credential_lease ]
     && Credential_lease.accepted_effects
        = [ Run_topology.Credential_lease_transition ]
     && Credential_lease.binding_ids
        = [ "auxiliary:acquire-credential-lease->credential-lease-transition";
            "auxiliary:release-credential-lease->credential-lease-transition" ]
     && List.for_all
          (fun role ->
            Jj_target_protocol.target (Jj_action_kind.Auxiliary role)
            = Credential_lease.target_protocol
            && Run_topology.action_work_gaps
                 (Run_topology.Credential_lease_work role)
               = []
            && Option.map Jj_dependency_schema.owner
                 (Jj_dependency_schema.for_role role)
               = Some Jj_dependency_schema.Credential_lease_owner
            && Option.map Jj_dependency_schema.carrier_class
                 (Jj_dependency_schema.for_role role)
               = Some Jj_dependency_schema.Nonserializable_bridge_carrier)
          Credential_lease.accepted_roles);
  check "J09T25 credential lease prerequisites remain exact unavailable"
    (Credential_lease.prerequisites
     = [ Credential_lease.Target_owner_part_current;
         Credential_lease.Credential_lease_operational_owner_current;
         Credential_lease.Controlled_secret_provider_handoff_current;
         Credential_lease.Credential_declaration_current_carrier;
         Credential_lease.Remote_operation_context_current_carrier;
         Credential_lease.Authority_role_session_fence;
         Credential_lease.Approval_occurrence_capability_current;
         Credential_lease.Bounded_clock_current_carrier;
         Credential_lease.Request_bound_credential_transition_current_carrier;
         Credential_lease.Remote_terminal_readback_cleanup_eligibility_current;
         Credential_lease.Dependency_carrier_owner_current;
         Credential_lease.Effect_target_registration_current;
         Credential_lease.Event_effect_readback_current ]
     && Credential_lease.production_posture = `Implemented_unavailable
     && credential_lease_unavailable_is_exact
          (Credential_lease.create_owner_unavailable ())); 
  let credential_lease_mutations =
    [ Credential_lease.For_test.Drop_runtime_manifest_source;
      Credential_lease.For_test.Drop_target_protocol_source;
      Credential_lease.For_test.Drop_action_kind_source;
      Credential_lease.For_test.Drop_dependency_schema_source;
      Credential_lease.For_test.Drop_topology_source;
      Credential_lease.For_test.Drop_credential_source;
      Credential_lease.For_test.Drop_root_bootstrap_source;
      Credential_lease.For_test.Drop_dependency_authority_source;
      Credential_lease.For_test.Drop_swarm_preparation_source;
      Credential_lease.For_test.Drop_event_prefix_source;
      Credential_lease.For_test.Drop_target_registry_schema;
      Credential_lease.For_test.Drop_credential_config_declaration;
      Credential_lease.For_test.Drop_runtime_declaration;
      Credential_lease.For_test.Substitute_runtime_declaration;
      Credential_lease.For_test.Drop_target_protocol;
      Credential_lease.For_test.Substitute_network_scope_protocol;
      Credential_lease.For_test.Drop_acquire_role;
      Credential_lease.For_test.Drop_release_role;
      Credential_lease.For_test.Reorder_roles;
      Credential_lease.For_test.Add_role;
      Credential_lease.For_test.Drop_effect;
      Credential_lease.For_test.Substitute_network_scope_effect;
      Credential_lease.For_test.Add_effect;
      Credential_lease.For_test.Drop_acquire_binding;
      Credential_lease.For_test.Drop_release_binding;
      Credential_lease.For_test.Reorder_bindings;
      Credential_lease.For_test.Duplicate_binding;
      Credential_lease.For_test.Bind_acquire_to_network_scope_effect;
      Credential_lease.For_test.Bind_release_to_network_scope_effect;
      Credential_lease.For_test.Merge_acquire_release;
      Credential_lease.For_test.Drop_prerequisite;
      Credential_lease.For_test.Reorder_prerequisites;
      Credential_lease.For_test.Duplicate_prerequisite;
      Credential_lease.For_test.Substitute_prerequisite;
      Credential_lease.For_test.Permit_acquire_without_provider;
      Credential_lease.For_test.Permit_acquire_without_declaration;
      Credential_lease.For_test.Permit_acquire_without_remote_context;
      Credential_lease.For_test.Permit_acquire_without_approval;
      Credential_lease.For_test.Permit_acquire_without_clock;
      Credential_lease.For_test.Permit_cross_remote_lease;
      Credential_lease.For_test.Permit_cross_transport_lease;
      Credential_lease.For_test.Permit_cross_session_lease;
      Credential_lease.For_test.Permit_cross_activity_lease;
      Credential_lease.For_test.Permit_expired_lease;
      Credential_lease.For_test.Permit_revoked_lease;
      Credential_lease.For_test.Permit_cleaned_lease_reuse;
      Credential_lease.For_test.Permit_release_before_terminal_readback;
      Credential_lease.For_test.Permit_changed_replay;
      Credential_lease.For_test.Accept_secret_bytes;
      Credential_lease.For_test.Accept_credential_string;
      Credential_lease.For_test.Accept_auth_header;
      Credential_lease.For_test.Accept_environment;
      Credential_lease.For_test.Accept_raw_endpoint;
      Credential_lease.For_test.Expose_lease_capability;
      Credential_lease.For_test.Accept_lease_reference_as_authority;
      Credential_lease.For_test.Serialize_dependency_carrier;
      Credential_lease.For_test.Add_callback;
      Credential_lease.For_test.Accept_caller_digest;
      Credential_lease.For_test.Add_registration_constructor;
      Credential_lease.For_test.Add_current_constructor;
      Credential_lease.For_test.Promote_unavailable_lease;
      Credential_lease.For_test.Expose_redacted_remote;
      Credential_lease.For_test.Bind_source_digest_to_secret_bytes ]
  in
  check "J09T26 credential lease source kills 63 authority and escape mutants"
    (String.length Credential_lease.source_digest = 64
     && List.length credential_lease_mutations = 63
     && List.for_all
          (fun mutation ->
            Credential_lease.source_digest
            <> Credential_lease.For_test.source_digest_with_mutation mutation)
          credential_lease_mutations);
  check "J09T27 filesystem materialization owns exact routing and preconditions"
    (Jj_runtime_manifest.declaration_key
       Filesystem_materialization.runtime_declaration
       = "target.filesystem-materialization"
     && Jj_runtime_manifest.declaration_digest
          Filesystem_materialization.runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.target_filesystem_materialization
     && Filesystem_materialization.target_protocol
        = Jj_target_protocol.Filesystem_materialization
     && Filesystem_materialization.accepted_roles
        = [ Jj_action_kind.Materialize_candidate;
            Jj_action_kind.Write_partition;
            Jj_action_kind.Restore_partition;
            Jj_action_kind.Restore_sealed_record_preimage;
            Jj_action_kind.Write_sealed_record_candidate;
            Jj_action_kind.Remove_disposable_scope ]
     && Filesystem_materialization.accepted_effects
        = [ Run_topology.Controlled_filesystem_materialization ]
     && Filesystem_materialization.binding_ids
        = [ "auxiliary:materialize-candidate->controlled-filesystem-materialization";
            "auxiliary:write-partition->controlled-filesystem-materialization";
            "auxiliary:restore-partition->controlled-filesystem-materialization";
            "auxiliary:restore-sealed-record-preimage->controlled-filesystem-materialization";
            "auxiliary:write-sealed-record-candidate->controlled-filesystem-materialization";
            "auxiliary:remove-disposable-scope->controlled-filesystem-materialization" ]
     && Filesystem_materialization.role_precondition_ids
        = [ "materialize-candidate:target-absent";
            "write-partition:target-present";
            "restore-partition:target-present";
            "restore-sealed-record-preimage:target-present";
            "write-sealed-record-candidate:target-absent";
            "remove-disposable-scope:target-present" ]
     && List.for_all
          (fun role ->
            Jj_target_protocol.target (Jj_action_kind.Auxiliary role)
            = Filesystem_materialization.target_protocol
            && Run_topology.action_work_gaps
                 (Run_topology.Materialization_work role)
               = []
            && Option.map Jj_dependency_schema.owner
                 (Jj_dependency_schema.for_role role)
               = Some Jj_dependency_schema.Filesystem_materialization_owner
            && Option.map Jj_dependency_schema.carrier_class
                 (Jj_dependency_schema.for_role role)
               = Some Jj_dependency_schema.Nonserializable_bridge_carrier)
          Filesystem_materialization.accepted_roles);
  check "J09T28 filesystem materialization stays exact unavailable"
    (Filesystem_materialization.prerequisites
     = [ Filesystem_materialization.Target_owner_part_current;
         Filesystem_materialization.Filesystem_materialization_operational_owner_current;
         Filesystem_materialization.Descriptor_relative_filesystem_backend_current;
         Filesystem_materialization.Owner_held_root_directory_current_carrier;
         Filesystem_materialization.Resolve_beneath_no_xdev_current_carrier;
         Filesystem_materialization.Action_bound_materialization_intent_current_carrier;
         Filesystem_materialization.Authority_role_session_fence;
         Filesystem_materialization.Approval_occurrence_capability_current;
         Filesystem_materialization.Writer_fence_session_current_carrier;
         Filesystem_materialization.Activity_generation_current_carrier;
         Filesystem_materialization.Source_change_transition_commitment_current_carrier;
         Filesystem_materialization.Mutation_frontier_may_have_applied_current;
         Filesystem_materialization.Bounded_clock_current_carrier;
         Filesystem_materialization.Prefix_journal_apply_once_current;
         Filesystem_materialization.Recovery_vault_purpose_capability_current;
         Filesystem_materialization.Recovery_vault_sealed_object_set_current;
         Filesystem_materialization.Sealed_record_allowlist_current_carrier;
         Filesystem_materialization.Exact_preimage_candidate_metadata_current_carrier;
         Filesystem_materialization.Terminal_readback_cleanup_eligibility_current;
         Filesystem_materialization.Dependency_carrier_owner_current;
         Filesystem_materialization.Effect_target_registration_current;
         Filesystem_materialization.Event_effect_readback_current ]
     && Filesystem_materialization.production_posture
        = `Implemented_unavailable
     && filesystem_materialization_unavailable_is_exact
          (Filesystem_materialization.create_owner_unavailable ())); 
  let filesystem_materialization_mutations =
    [ Filesystem_materialization.For_test.Drop_runtime_manifest_source;
      Filesystem_materialization.For_test.Drop_target_protocol_source;
      Filesystem_materialization.For_test.Drop_action_kind_source;
      Filesystem_materialization.For_test.Drop_dependency_schema_source;
      Filesystem_materialization.For_test.Drop_campaign_action_source;
      Filesystem_materialization.For_test.Drop_recovery_schema_source;
      Filesystem_materialization.For_test.Drop_partition_source;
      Filesystem_materialization.For_test.Drop_topology_source;
      Filesystem_materialization.For_test.Drop_filesystem_source;
      Filesystem_materialization.For_test.Drop_recovery_vault_source;
      Filesystem_materialization.For_test.Drop_writer_lease_source;
      Filesystem_materialization.For_test.Drop_root_bootstrap_source;
      Filesystem_materialization.For_test.Drop_dependency_authority_source;
      Filesystem_materialization.For_test.Drop_swarm_preparation_source;
      Filesystem_materialization.For_test.Drop_event_prefix_source;
      Filesystem_materialization.For_test.Drop_target_registry_schema;
      Filesystem_materialization.For_test.Drop_runtime_declaration;
      Filesystem_materialization.For_test.Substitute_runtime_declaration;
      Filesystem_materialization.For_test.Drop_target_protocol;
      Filesystem_materialization.For_test.Substitute_transition_protocol;
      Filesystem_materialization.For_test.Drop_materialize_candidate_role;
      Filesystem_materialization.For_test.Drop_write_partition_role;
      Filesystem_materialization.For_test.Drop_restore_partition_role;
      Filesystem_materialization.For_test.Drop_restore_sealed_record_preimage_role;
      Filesystem_materialization.For_test.Drop_write_sealed_record_candidate_role;
      Filesystem_materialization.For_test.Drop_remove_disposable_scope_role;
      Filesystem_materialization.For_test.Reorder_roles;
      Filesystem_materialization.For_test.Add_stage_recovery_set_role;
      Filesystem_materialization.For_test.Drop_effect;
      Filesystem_materialization.For_test.Substitute_candidate_verification_effect;
      Filesystem_materialization.For_test.Add_effect;
      Filesystem_materialization.For_test.Drop_materialize_candidate_binding;
      Filesystem_materialization.For_test.Drop_write_partition_binding;
      Filesystem_materialization.For_test.Drop_restore_partition_binding;
      Filesystem_materialization.For_test.Drop_restore_sealed_record_preimage_binding;
      Filesystem_materialization.For_test.Drop_write_sealed_record_candidate_binding;
      Filesystem_materialization.For_test.Drop_remove_disposable_scope_binding;
      Filesystem_materialization.For_test.Reorder_bindings;
      Filesystem_materialization.For_test.Duplicate_binding;
      Filesystem_materialization.For_test.Merge_partition_write_restore;
      Filesystem_materialization.For_test.Merge_record_write_restore;
      Filesystem_materialization.For_test.Drop_prerequisite;
      Filesystem_materialization.For_test.Reorder_prerequisites;
      Filesystem_materialization.For_test.Duplicate_prerequisite;
      Filesystem_materialization.For_test.Substitute_prerequisite;
      Filesystem_materialization.For_test.Permit_without_descriptor_backend;
      Filesystem_materialization.For_test.Permit_without_owner_root;
      Filesystem_materialization.For_test.Permit_without_approval;
      Filesystem_materialization.For_test.Permit_without_writer_fence;
      Filesystem_materialization.For_test.Permit_without_mutation_frontier;
      Filesystem_materialization.For_test.Permit_without_apply_once_journal;
      Filesystem_materialization.For_test.Permit_wrong_role_precondition;
      Filesystem_materialization.For_test.Permit_cross_purpose_vault;
      Filesystem_materialization.For_test.Permit_cross_activity_materialization;
      Filesystem_materialization.For_test.Permit_cross_generation_materialization;
      Filesystem_materialization.For_test.Permit_unsealed_record_write;
      Filesystem_materialization.For_test.Permit_unsealed_record_restore;
      Filesystem_materialization.For_test.Permit_present_absent_mismatch;
      Filesystem_materialization.For_test.Permit_mode_or_symlink_mismatch;
      Filesystem_materialization.For_test.Permit_cleanup_before_terminal_readback;
      Filesystem_materialization.For_test.Permit_changed_replay;
      Filesystem_materialization.For_test.Accept_raw_path;
      Filesystem_materialization.For_test.Accept_raw_bytes;
      Filesystem_materialization.For_test.Expose_filesystem_handle;
      Filesystem_materialization.For_test.Expose_recovery_vault_capability;
      Filesystem_materialization.For_test.Add_callback;
      Filesystem_materialization.For_test.Accept_caller_digest;
      Filesystem_materialization.For_test.Add_registration_constructor;
      Filesystem_materialization.For_test.Add_current_constructor;
      Filesystem_materialization.For_test.Promote_unavailable_backend ]
  in
  check "J09T29 filesystem materialization kills 70 authority and escape mutants"
    (String.length Filesystem_materialization.source_digest = 64
     && List.length filesystem_materialization_mutations = 70
     && List.for_all
          (fun mutation ->
            Filesystem_materialization.source_digest
            <> Filesystem_materialization.For_test.source_digest_with_mutation
                 mutation)
          filesystem_materialization_mutations);
  check "J09T30 candidate target owns five steps and no sixth grouping action"
    (Jj_runtime_manifest.declaration_key
       Candidate_verification.runtime_declaration
       = "target.candidate-verification"
     && Jj_runtime_manifest.declaration_digest
          Candidate_verification.runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.target_candidate_verification
     && Candidate_verification.target_protocol
        = Jj_target_protocol.Candidate_verification
     && Candidate_verification.grouping_roles
        = [ Jj_action_kind.Verify_candidate_tree ]
     && Candidate_verification.accepted_steps
        = [ Jj_action_kind.Toolchain_check;
            Jj_action_kind.Jj_reverse_cone;
            Jj_action_kind.Jj_live_campaign;
            Jj_action_kind.Jj_formal_receipt_validation;
            Jj_action_kind.Jj_precompletion_readback ]
     && Candidate_verification.accepted_effects
        = [ Run_topology.Candidate_tree_verification ]
     && Candidate_verification.binding_ids
        = [ "candidate:toolchain-check->candidate-tree-verification";
            "candidate:jj-reverse-cone->candidate-tree-verification";
            "candidate:jj-live-campaign->candidate-tree-verification";
            "candidate:jj-formal-receipt-validation->candidate-tree-verification";
            "candidate:jj-precompletion-readback->candidate-tree-verification" ]
     && List.for_all
          (fun step ->
            Jj_target_protocol.target (Jj_action_kind.Candidate_process step)
            = Candidate_verification.target_protocol
            && Run_topology.action_work_gaps
                 (Run_topology.Candidate_verification_work step)
               = [])
          Candidate_verification.accepted_steps
     && Jj_target_protocol.target
          (Jj_action_kind.Auxiliary Jj_action_kind.Verify_candidate_tree)
        = Candidate_verification.target_protocol
     && Option.map Jj_dependency_schema.owner
          (Jj_dependency_schema.for_role
             Jj_action_kind.Verify_candidate_tree)
        = Some Jj_dependency_schema.Candidate_verification_owner
     && Option.map Jj_dependency_schema.carrier_class
          (Jj_dependency_schema.for_role
             Jj_action_kind.Verify_candidate_tree)
        = Some Jj_dependency_schema.Nonserializable_bridge_carrier
     && List.length Candidate_verification.binding_ids = 5);
  check "J09T31 candidate target prerequisites stay exact unavailable"
    (Candidate_verification.prerequisites
     = [ Candidate_verification.Target_owner_part_current;
         Candidate_verification.Candidate_verification_operational_owner_current;
         Candidate_verification.Candidate_activation_current_carrier;
         Candidate_verification.Frozen_candidate_process_source_authority;
         Candidate_verification.Candidate_process_obligation_schema_current;
         Candidate_verification.Candidate_process_registry_current;
         Candidate_verification.Registered_candidate_executable_current;
         Candidate_verification.Candidate_configuration_current_carrier;
         Candidate_verification.Materialized_candidate_current_carrier;
         Candidate_verification.A1_candidate_plan_current_carrier;
         Candidate_verification.Candidate_suite_manifest_current_carrier;
         Candidate_verification.Approval_occurrence_capabilities_current;
         Candidate_verification.Receipt_bound_resource_envelope_current;
         Candidate_verification.Request_bound_candidate_step_current_carrier;
         Candidate_verification.Candidate_process_apply_once_current;
         Candidate_verification.Ordered_candidate_step_readback_current;
         Candidate_verification.Candidate_cleanup_eligibility_current;
         Candidate_verification.Dependency_carrier_owner_current;
         Candidate_verification.Effect_target_registration_current;
         Candidate_verification.Event_effect_readback_current ]
     && Candidate_verification.production_posture
        = `Implemented_unavailable
     && candidate_verification_unavailable_is_exact
          (Candidate_verification.create_owner_unavailable ())); 
  let candidate_verification_mutations =
    [ Candidate_verification.For_test.Drop_runtime_manifest_source;
      Candidate_verification.For_test.Drop_target_protocol_source;
      Candidate_verification.For_test.Drop_action_kind_source;
      Candidate_verification.For_test.Drop_process_protocol_source;
      Candidate_verification.For_test.Drop_dependency_schema_source;
      Candidate_verification.For_test.Drop_campaign_action_source;
      Candidate_verification.For_test.Drop_topology_source;
      Candidate_verification.For_test.Drop_dependability_process_protocol_source;
      Candidate_verification.For_test.Drop_runtime_core_source;
      Candidate_verification.For_test.Drop_filesystem_materialization_source;
      Candidate_verification.For_test.Drop_dependency_authority_source;
      Candidate_verification.For_test.Drop_swarm_preparation_source;
      Candidate_verification.For_test.Drop_event_prefix_source;
      Candidate_verification.For_test.Drop_target_registry_schema;
      Candidate_verification.For_test.Drop_runtime_declaration;
      Candidate_verification.For_test.Substitute_runtime_declaration;
      Candidate_verification.For_test.Drop_target_protocol;
      Candidate_verification.For_test.Substitute_jujutsu_protocol;
      Candidate_verification.For_test.Drop_grouping_role;
      Candidate_verification.For_test.Add_auxiliary_role;
      Candidate_verification.For_test.Drop_toolchain_step;
      Candidate_verification.For_test.Drop_reverse_cone_step;
      Candidate_verification.For_test.Drop_live_campaign_step;
      Candidate_verification.For_test.Drop_formal_receipt_validation_step;
      Candidate_verification.For_test.Drop_precompletion_readback_step;
      Candidate_verification.For_test.Reorder_steps;
      Candidate_verification.For_test.Duplicate_step;
      Candidate_verification.For_test.Interpose_formal_step;
      Candidate_verification.For_test.Add_sixth_candidate_step;
      Candidate_verification.For_test.Promote_grouping_role_to_process_action;
      Candidate_verification.For_test.Drop_effect;
      Candidate_verification.For_test.Substitute_process_attempt_effect;
      Candidate_verification.For_test.Add_effect;
      Candidate_verification.For_test.Drop_toolchain_binding;
      Candidate_verification.For_test.Drop_reverse_cone_binding;
      Candidate_verification.For_test.Drop_live_campaign_binding;
      Candidate_verification.For_test.Drop_formal_receipt_validation_binding;
      Candidate_verification.For_test.Drop_precompletion_readback_binding;
      Candidate_verification.For_test.Reorder_bindings;
      Candidate_verification.For_test.Duplicate_binding;
      Candidate_verification.For_test.Swap_toolchain_precompletion_bindings;
      Candidate_verification.For_test.Add_grouping_role_effect_binding;
      Candidate_verification.For_test.Drop_prerequisite;
      Candidate_verification.For_test.Reorder_prerequisites;
      Candidate_verification.For_test.Duplicate_prerequisite;
      Candidate_verification.For_test.Substitute_prerequisite;
      Candidate_verification.For_test.Permit_without_materialized_candidate;
      Candidate_verification.For_test.Permit_without_a1_plan;
      Candidate_verification.For_test.Permit_without_suite_manifest;
      Candidate_verification.For_test.Permit_without_approval_occurrence;
      Candidate_verification.For_test.Permit_without_resource_preflight;
      Candidate_verification.For_test.Permit_without_candidate_configuration;
      Candidate_verification.For_test.Permit_without_registered_executable;
      Candidate_verification.For_test.Permit_continue_after_failed_step;
      Candidate_verification.For_test.Permit_cleanup_before_fifth_terminal;
      Candidate_verification.For_test.Permit_cross_candidate;
      Candidate_verification.For_test.Permit_cross_activity;
      Candidate_verification.For_test.Permit_changed_replay;
      Candidate_verification.For_test.Accept_production_activation;
      Candidate_verification.For_test.Accept_forbidden_production_authority;
      Candidate_verification.For_test.Accept_raw_argv;
      Candidate_verification.For_test.Accept_executable_path;
      Candidate_verification.For_test.Accept_cwd_or_path;
      Candidate_verification.For_test.Accept_environment;
      Candidate_verification.For_test.Expose_process_request_or_handle;
      Candidate_verification.For_test.Add_callback_or_caller_digest;
      Candidate_verification.For_test.Serialize_capability;
      Candidate_verification.For_test.Forge_current_authority ]
  in
  check "J09T32 candidate source kills 68 authority and escape mutants"
    (String.length Candidate_verification.source_digest = 64
     && List.length candidate_verification_mutations = 68
     && List.for_all
          (fun mutation ->
            Candidate_verification.source_digest
            <> Candidate_verification.For_test.source_digest_with_mutation
                 mutation)
          candidate_verification_mutations);
  check "J09T33 release target owns its least-authority observation boundary"
    (Jj_runtime_manifest.declaration_key Release.runtime_declaration
       = "target.release"
     && Jj_runtime_manifest.declaration_digest Release.runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.target_release
     && Release.target_protocol = Jj_target_protocol.Release
     && Release.accepted_roles
        = [ Jj_action_kind.Observe_release_bundle ]
     && Release.accepted_effects
        = [ Run_topology.Repository_source_observation ]
     && Release.binding_ids
        = [ "auxiliary:observe-release-bundle->repository-source-observation" ]
     && Release.release_phase_action_ids
        = [ "auxiliary:acquire-clock";
            "auxiliary:observe-external-resource";
            "auxiliary:observe-release-bundle";
            "auxiliary:observe-tree" ]
     && Release.activation_role_ids
        = [ "acquire-clock"; "observe-external-resource";
            "observe-release-bundle"; "observe-tree";
            "consume-approval-nonce" ]
     && Jj_target_protocol.target
          (Jj_action_kind.Auxiliary Jj_action_kind.Observe_release_bundle)
        = Release.target_protocol
     && Run_topology.action_work_gaps
          (Run_topology.Repository_source_work
             Jj_action_kind.Observe_release_bundle)
        = []
     && Option.map Jj_dependency_schema.owner
          (Jj_dependency_schema.for_role
             Jj_action_kind.Observe_release_bundle)
        = Some Jj_dependency_schema.Release_owner
     && Option.map Jj_dependency_schema.carrier_class
          (Jj_dependency_schema.for_role
             Jj_action_kind.Observe_release_bundle)
        = Some Jj_dependency_schema.Nonserializable_bridge_carrier);
  check "J09T34 release prerequisites remain exact unavailable"
    (Release.prerequisites
     = [ Release.Target_owner_part_current;
         Release.Release_observation_operational_owner_current;
         Release.Release_dependency_owner_allocation_current;
         Release.Release_activation_least_authority_current;
         Release.Release_request_current_carrier;
         Release.Signed_release_ticket_current_carrier;
         Release.Approval_occurrence_capabilities_current;
         Release.Bounded_clock_current_carrier;
         Release.External_resource_host_current;
         Release.Controlled_release_bundle_observer_current;
         Release.Release_pin_current_carrier;
         Release.Release_tree_observation_current_carrier;
         Release.Release_phase_projection_current;
         Release.Dependency_carrier_owner_current;
         Release.Effect_target_registration_current;
         Release.Event_effect_readback_current ]
     && Release.production_posture = `Implemented_unavailable
     && release_unavailable_is_exact (Release.create_owner_unavailable ()));
  let release_mutations =
    [ Release.For_test.Drop_runtime_manifest_source;
      Release.For_test.Drop_target_protocol_source;
      Release.For_test.Drop_dependency_schema_source;
      Release.For_test.Drop_action_kind_source;
      Release.For_test.Drop_campaign_action_source;
      Release.For_test.Drop_approval_source;
      Release.For_test.Drop_release_protocol_source;
      Release.For_test.Drop_source_manifest_source;
      Release.For_test.Drop_topology_source;
      Release.For_test.Drop_runtime_declaration;
      Release.For_test.Substitute_runtime_declaration;
      Release.For_test.Drop_target_protocol;
      Release.For_test.Drop_role;
      Release.For_test.Add_role;
      Release.For_test.Drop_effect;
      Release.For_test.Add_effect;
      Release.For_test.Drop_binding;
      Release.For_test.Substitute_binding_effect;
      Release.For_test.Drop_release_phase_action;
      Release.For_test.Reorder_release_phase_actions;
      Release.For_test.Duplicate_release_phase_action;
      Release.For_test.Add_release_phase_action;
      Release.For_test.Drop_activation_role;
      Release.For_test.Add_activation_role;
      Release.For_test.Drop_consume_role;
      Release.For_test.Permit_unscoped_consume;
      Release.For_test.Replace_tree_with_object;
      Release.For_test.Drop_prerequisite;
      Release.For_test.Reorder_prerequisites;
      Release.For_test.Duplicate_prerequisite;
      Release.For_test.Substitute_prerequisite;
      Release.For_test.Permit_missing_tag;
      Release.For_test.Permit_moving_tag;
      Release.For_test.Permit_commit_mismatch;
      Release.For_test.Permit_tree_mismatch;
      Release.For_test.Permit_archive_mismatch;
      Release.For_test.Permit_documentation_mismatch;
      Release.For_test.Permit_executable_mismatch;
      Release.For_test.Permit_config_mismatch;
      Release.For_test.Permit_missing_license;
      Release.For_test.Permit_unsigned_ticket;
      Release.For_test.Permit_expired_ticket;
      Release.For_test.Permit_cross_phase_nonce;
      Release.For_test.Permit_unapproved_bundle;
      Release.For_test.Permit_inherited_checkout;
      Release.For_test.Permit_network_acquisition;
      Release.For_test.Permit_source_bytes_projection;
      Release.For_test.Add_raw_path;
      Release.For_test.Add_raw_bundle_bytes;
      Release.For_test.Add_network;
      Release.For_test.Add_credential;
      Release.For_test.Add_process;
      Release.For_test.Add_repository_mutation;
      Release.For_test.Add_candidate_write;
      Release.For_test.Add_formal_execution;
      Release.For_test.Add_full_production_activation;
      Release.For_test.Add_callback;
      Release.For_test.Accept_caller_digest;
      Release.For_test.Add_registration_constructor;
      Release.For_test.Add_current_constructor;
      Release.For_test.Promote_unavailable_owner ]
  in
  check "J09T35 release source kills 61 authority and escape mutants"
    (String.length Release.source_digest = 64
     && List.length release_mutations = 61
     && List.for_all
          (fun mutation ->
            Release.source_digest
            <> Release.For_test.source_digest_with_mutation mutation)
          release_mutations);
  Printf.printf "ops_jj_target foundation: %d passed, %d failed\n"
    !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_jj_target"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)
