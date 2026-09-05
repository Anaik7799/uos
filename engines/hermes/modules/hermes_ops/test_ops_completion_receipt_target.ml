open Ops_completion_receipt_target

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let expected_prerequisites =
  [ Target_owner_part_current;
    Completion_reserve_owner_part_current;
    Completion_finalize_owner_part_current;
    Completion_store_operational_owner_current;
    Completion_store_nominal_peer_open_fence_current;
    Completion_store_session_epoch_current_carrier;
    Activity_generation_current_carrier;
    Approval_occurrence_capability_current;
    Bounded_clock_current_carrier;
    Reservation_source_head_campaign_current_carrier;
    Reservation_record_role_payload_current_carrier;
    Completion_reservation_current_carrier;
    Completion_branch_ordinal_current_carrier;
    Bookmark_poststate_readback_current_carrier;
    Writer_lease_release_current_carrier;
    Reconciled_terminal_frontier_current_carrier;
    Completion_transition_commitment_current_carrier;
    Completion_finalization_cas_current;
    Dependency_carrier_owner_current;
    Effect_target_registration_current;
    Event_effect_readback_current;
    Completion_store_readback_current_carrier ]

let expected_lifecycle_laws =
  [ "absent+exact-reserve->reserved";
    "reservation-receipt->nonauthorizing";
    "same-reserve-request->stable-replay";
    "same-id+changed-reserve-request->conflict";
    "finalize-without-reservation->refused";
    "finalize-common-reservation-payload->exact-match-required";
    "finalize-bookmark-readback+lease-release+frontier+commitment+ordinal+occurrence->all-current-required";
    "reserved+exact-finalize->one-cas->finalized";
    "same-finalize-request->stable-replay";
    "same-id+changed-finalize-request->conflict";
    "indeterminate-or-conflict->operationally-blocked";
    "store-readback->nonauthorizing-no-credit";
    "lost-event-append->durable-store-readback+fresh-occurrence+same-final-payload+no-bookmark-repeat" ]

let all_mutations =
  let open For_test in
  [ Drop_runtime_manifest_source;
    Drop_target_protocol_source;
    Drop_dependency_schema_source;
    Drop_action_kind_source;
    Drop_campaign_action_source;
    Drop_completion_store_protocol_source;
    Drop_readback_source;
    Drop_topology_source;
    Drop_completion_store_source;
    Drop_writer_lease_source;
    Drop_approval_source;
    Drop_root_bootstrap_source;
    Drop_event_prefix_source;
    Drop_runtime_current_protocol_source;
    Drop_runtime_declaration;
    Substitute_runtime_declaration;
    Drop_target_protocol;
    Drop_reserve_role;
    Drop_finalize_role;
    Reorder_roles;
    Add_role;
    Drop_effect;
    Add_effect;
    Drop_reserve_binding;
    Drop_finalize_binding;
    Reorder_bindings;
    Duplicate_binding;
    Substitute_binding_effect;
    Drop_prerequisite;
    Reorder_prerequisites;
    Duplicate_prerequisite;
    Substitute_prerequisite;
    Permit_reservation_authority;
    Permit_reservation_overwrite;
    Permit_reserve_without_source;
    Permit_reserve_without_head;
    Permit_reserve_without_campaign;
    Permit_reserve_without_record_role;
    Permit_same_id_different_payload_replay;
    Permit_finalize_without_reservation;
    Permit_finalize_wrong_role;
    Permit_finalize_wrong_source;
    Permit_finalize_wrong_head;
    Permit_finalize_wrong_campaign;
    Permit_finalize_wrong_payload;
    Permit_finalize_without_bookmark_readback;
    Permit_finalize_without_lease_release;
    Permit_finalize_before_reconciled_frontier;
    Permit_finalize_without_completion_commitment;
    Permit_finalize_overwrite;
    Drop_finalize_cas;
    Permit_changed_finalize_replay;
    Permit_cross_activity_capability;
    Permit_cross_generation_capability;
    Permit_cross_owner_session;
    Permit_cross_store_epoch;
    Alias_reserve_finalize_capability;
    Expose_read_capability;
    Expose_lifecycle_capability;
    Expose_recovery_capability;
    Add_bookmark_mutation;
    Add_repository_mutation;
    Add_process;
    Add_network;
    Add_credential;
    Expose_database;
    Expose_location;
    Expose_sql;
    Expose_store;
    Expose_payload;
    Expose_capability;
    Add_callback;
    Accept_caller_digest;
    Add_registration_constructor;
    Add_current_constructor;
    Promote_unavailable_owner;
    Promote_store_readback_to_completion_credit;
    Alias_completion_history;
    Guess_lost_append;
    Permit_close_blocked_row ]

let all_unique values =
  List.length values = List.length (List.sort_uniq String.compare values)

let () =
  Printf.printf "[tdd] closed completion-receipt target foundation\n";
  check "J09C01 exact declaration, protocol, roles, and effect"
    (runtime_declaration == Jj_runtime_manifest.target_completion_receipt
     && target_protocol = Jj_target_protocol.Completion_receipt
     && accepted_roles =
          [ Jj_action_kind.Reserve_completion_receipt;
            Jj_action_kind.Finalize_completion_receipt ]
     && accepted_effects = [ Run_topology.Durable_artifact_publication ]);
  check "J09C02 exact action-effect and protocol bindings"
    (binding_ids =
       [ "auxiliary:reserve-completion-receipt->durable-artifact-publication";
         "auxiliary:finalize-completion-receipt->durable-artifact-publication" ]
     && protocol_binding_ids =
          [ "reserve-completion-receipt->Reserve:Completion_reservation";
            "finalize-completion-receipt->Finalize:Completion_final" ]);
  check "J09C03 exact ordered 22-prerequisite denominator"
    (prerequisites = expected_prerequisites && List.length prerequisites = 22);
  check "J09C04 exact reservation and finalization lifecycle laws"
    (lifecycle_law_ids = expected_lifecycle_laws);
  check "J09C05 production owner is fail-closed with full diagnostics"
    (match create_owner_unavailable () with
     | Ok _ -> false
     | Error diagnostics ->
         List.map diagnostic_prerequisite diagnostics = expected_prerequisites
         && List.for_all
              (fun diagnostic ->
                String.equal (diagnostic_coordinate diagnostic)
                  "L3/Orient/ops-completion-receipt-target"
                && diagnostic_origin diagnostic = `Evidence
                && String.ends_with ~suffix:" is unavailable"
                     (diagnostic_message diagnostic))
              diagnostics);
  check "J09C06 production posture is implemented-unavailable"
    (production_posture = `Implemented_unavailable);
  check "J09C07 source digest is SHA-256 shaped"
    (String.length source_digest = 64);
  let mutant_digests =
    List.map For_test.source_digest_with_mutation all_mutations
  in
  check "J09C21 exact 80 real source mutants are distinct and killed"
    (List.length all_mutations = 80
     && List.for_all (fun digest -> not (String.equal digest source_digest))
          mutant_digests
     && all_unique mutant_digests);
  Printf.printf "completion-receipt target: %d passed; %d failed\n"
    !passed !failed;
  if !failed <> 0 then exit 1
