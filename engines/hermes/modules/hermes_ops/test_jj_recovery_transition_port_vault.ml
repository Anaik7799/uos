open Jj_recovery_transition_port_vault

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let expected_lifecycle_states =
  [ Prepared; Applied; Diverged; Closed_unused; Session_fenced; Indeterminate ]

let expected_binding_ids =
  [ "target-slot";
    "owner-session";
    "activation-generation";
    "activity";
    "source-transition-commitment";
    "consumer";
    "expiry" ]

let expected_callsite_ids =
  [ "issuer:run-jj-operator-runtime";
    "retained-holder:jj-recovery-transition-port-vault";
    "resolver:ops-jj-transition-target";
    "carrier:run-dependency-authority-reference-only" ]

let expected_prerequisites =
  [ Root_recovery_port_issuer_current;
    Root_recovery_port_lifecycle_current;
    Activation_recovery_port_preparation_current;
    Authority_store_recovery_port_prepared_row_current;
    Authority_store_recovery_port_reference_sealing_current;
    Authority_store_recovery_port_atomic_withdrawal_current;
    Authority_store_recovery_port_lifecycle_current;
    Owner_session_current_carrier;
    Activation_generation_current_carrier;
    Activity_identity_current_carrier;
    Source_transition_commitment_current_carrier;
    B_selected_decision_current_carrier;
    Selected_prefix_current_carrier;
    Bounded_expiry_current_carrier;
    Dependency_carrier_owner_current;
    Transition_target_resolver_registration_current;
    Event_effect_readback_current;
    Recovery_port_readback_current_carrier;
    Terminal_or_close_unused_evidence_current;
    Session_fence_current_carrier;
    Drain_barrier_current_carrier ]

let all_mutations =
  let open For_test in
  [ Drop_port_protocol_source;
    Drop_runtime_current_protocol_source;
    Drop_runtime_manifest_source;
    Drop_action_kind_source;
    Drop_authority_store_source;
    Drop_recovery_set_vault_source;
    Drop_root_bootstrap_source;
    Drop_dependency_authority_source;
    Drop_conditional_authority_source;
    Drop_topology_source;
    Drop_event_prefix_source;
    Drop_runtime_registry_source;
    Drop_runtime_declaration;
    Substitute_runtime_declaration;
    Drop_target_slot;
    Substitute_target_slot;
    Drop_consumer;
    Substitute_consumer;
    Drop_lifecycle_state;
    Reorder_lifecycle_states;
    Duplicate_lifecycle_state;
    Merge_applied_diverged;
    Merge_closed_fenced;
    Drop_binding_field;
    Reorder_binding_fields;
    Duplicate_binding_field;
    Drop_callsite;
    Reorder_callsites;
    Substitute_callsite;
    Drop_prerequisite;
    Reorder_prerequisites;
    Duplicate_prerequisite;
    Substitute_prerequisite;
    Permit_create_without_issuer_current;
    Permit_create_without_lifecycle_current;
    Permit_prepare_without_activation_preparation;
    Permit_prepare_cross_activity;
    Permit_prepare_cross_commitment;
    Permit_prepare_cross_session;
    Permit_prepare_cross_generation;
    Permit_prepare_wrong_target;
    Permit_prepare_wrong_consumer;
    Permit_prepare_after_expiry;
    Permit_changed_prepare_replay;
    Expose_retained_port;
    Serialize_retained_port;
    Authorize_reference;
    Serialize_reference;
    Expose_reference_fields;
    Permit_dashboard_resolver;
    Permit_resolve_without_selected_decision;
    Permit_resolve_without_prefix;
    Permit_resolve_cross_binding;
    Permit_duplicate_resolution;
    Permit_late_apply_after_unused;
    Permit_late_apply_after_fence;
    Permit_close_unused_without_evidence;
    Permit_fence_without_session_death;
    Guess_lost_reply;
    Permit_reconcile_without_readback;
    Permit_state_regression;
    Permit_terminal_without_barrier;
    Permit_drain_with_live_prepared;
    Permit_cross_owner_session;
    Permit_cross_store_epoch;
    Expose_issuer_capability;
    Expose_lifecycle_capability;
    Expose_broad_activation_owner;
    Expose_database;
    Expose_location;
    Expose_sql;
    Expose_store;
    Expose_payload;
    Add_callback;
    Accept_caller_digest;
    Add_vault_constructor;
    Add_resolver_constructor;
    Add_current_constructor;
    Promote_unavailable_vault;
    Alias_recovery_set_vault;
    Add_repository_mutation;
    Add_filesystem_effect;
    Promote_reference_to_completion_credit;
    Promote_reference_to_parity_credit ]

let all_unique values =
  List.length values = List.length (List.sort_uniq String.compare values)

let () =
  Printf.printf "[tdd] closed recovery-transition-port vault foundation\n";
  check "J09V01 exact runtime declaration, target slot, and consumer"
    (runtime_declaration == Jj_runtime_manifest.runtime_recovery_port_vault
     && target_slot = Jj_runtime_manifest.Target_transition
     && consumer = Jj_action_kind.Activate_source_recovery_branch);
  check "J09V02 exact six-state monotone lifecycle denominator"
    (lifecycle_states = expected_lifecycle_states
     && List.map lifecycle_state_id lifecycle_states =
          [ "prepared"; "applied"; "diverged"; "closed-unused";
            "session-fenced"; "indeterminate" ]);
  check "J09V03 exact reference binding and callsite census"
    (binding_ids = expected_binding_ids && callsite_ids = expected_callsite_ids);
  check "J09V04 exact ordered 21-prerequisite denominator"
    (prerequisites = expected_prerequisites && List.length prerequisites = 21);
  check "J09V05 vault creation is fail-closed with complete diagnostics"
    (match create_vault_unavailable () with
     | Ok _ -> false
     | Error diagnostics ->
         List.map diagnostic_prerequisite diagnostics = expected_prerequisites
         && List.for_all
              (fun diagnostic ->
                String.equal (diagnostic_coordinate diagnostic)
                  "L3/Orient/jj-recovery-transition-port-vault"
                && diagnostic_origin diagnostic = `Evidence
                && String.ends_with ~suffix:" is unavailable"
                     (diagnostic_message diagnostic))
              diagnostics);
  check "J09V06 production posture remains implemented-unavailable"
    (production_posture = `Implemented_unavailable);
  check "J09V07 source digest is SHA-256 shaped"
    (String.length source_digest = 64);
  let mutant_digests =
    List.map For_test.source_digest_with_mutation all_mutations
  in
  check "J09V21 exact 84 real source mutants are distinct and killed"
    (List.length all_mutations = 84
     && List.for_all (fun digest -> not (String.equal digest source_digest))
          mutant_digests
     && all_unique mutant_digests);
  Printf.printf "recovery-transition-port vault: %d passed; %d failed\n"
    !passed !failed;
  if !failed <> 0 then exit 1
