open Run_abandonment_authority

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin incr failed; Printf.printf "FAILED: %s\n" name end

let unavailable prerequisite = function
  | Error diagnostic ->
      diagnostic_prerequisite diagnostic = prerequisite
      && diagnostic_code diagnostic
         = "abandonment-prerequisite-unavailable:" ^ prerequisite_id prerequisite
      && diagnostic_coordinate diagnostic = "L3/Act/run-abandonment-authority"
      && diagnostic_origin diagnostic = Specification
  | Ok _ -> false

let roles =
  [ Claim; Target_entry; Effect; Event; Frontier; Session; Before_after ]

let positions denominator =
  List.map (denominator_position denominator) roles

let _native_reconcile_type :
    Run_root_bootstrap.abandonment_recovery_part ->
    (Dependability_dispatch_store.abandonment_inventory_current, diagnostic)
    result =
  reconcile_recovery_only

let _native_create_type :
    Run_root_bootstrap.abandonment_authority_part -> (t, diagnostic) result =
  create

let () =
  check "A01 production posture stays implemented-unavailable"
    (production_posture = `Implemented_unavailable);
  check "A02 purposes remain distinct and canonical"
    (purpose_id Global_no_effect = "global-no-effect"
     && purpose_id Fenced_unentered_tail = "fenced-unentered-tail");
  let global = denominator Global_no_effect in
  let fenced = denominator Fenced_unentered_tail in
  check "A03 both purposes retain the exact ordered seven-role denominator"
    (denominator_count global = 7
     && denominator_count fenced = 7
     && List.for_all (denominator_requires global) roles
     && List.for_all (denominator_requires fenced) roles
     && positions global
        = [ Some 0; Some 1; Some 2; Some 3; Some 4; Some 5; Some 6 ]
     && positions fenced
        = [ Some 0; Some 1; Some 2; Some 3; Some 4; Some 5; Some 6 ]);
  check "A04 global no-effect retains its exact role obligations"
    (List.map (role_requirement global) roles
     = [ Exact_dispatch_session_attempt_claim;
         No_source_changing_target_entry;
         No_effect_applied;
         No_effect_event;
         No_mutation_attempted;
         Quiescent_or_fenced_dead;
         Exact_operation_tree_source_equal_and_resources_released ]);
  check "A05 fenced tail retains its exact causal role obligations"
    (List.map (role_requirement fenced) roles
     = [ Exact_dispatch_session_attempt_claim;
         Terminal_entered_target_prefix_and_tail_unentered;
         Terminal_entered_effect_prefix_and_tail_unentered;
         Terminal_entered_event_prefix_and_tail_unentered;
         Terminal_mutation_frontier_and_tail_unentered;
         Quiescent_or_fenced_dead;
         Pending_transition_and_writer_fence_retained ]);
  let prerequisites =
    [ Root_abandonment_authority_part; Root_abandonment_recovery_part;
      Approved_plan_current_receipt; Dispatch_claim_current_receipt;
      Target_entry_inventory_current_receipt; Effect_prefix_current_receipt;
      Event_prefix_current_receipt; Frontier_current_receipt;
      Quiescent_or_fenced_current_receipt; Before_after_current_receipt;
      Seven_distinct_producer_seals; Dispatch_abandonment_writer_capability;
    ]
  in
  check "A06 every absent native prerequisite has an exact fail-closed diagnostic"
    (List.for_all
       (fun prerequisite ->
         unavailable prerequisite (prerequisite_status prerequisite))
       prerequisites);
  check "A07 create requires the absent native root authority part"
    (unavailable Root_abandonment_authority_part
       (prerequisite_status Root_abandonment_authority_part));
  check "A08 both commitment purposes refuse before current evidence exists"
    (unavailable Approved_plan_current_receipt (commit_global_no_effect ())
     && unavailable Approved_plan_current_receipt
          (commit_fenced_unentered_tail ()));
  check "A09 native dispatch inventory exists but takeover root remains absent"
    (Result.is_ok
       (prerequisite_status Dispatch_abandonment_inventory_current_carrier)
     && unavailable Root_abandonment_recovery_part
          (prerequisite_status Root_abandonment_recovery_part));
  let denominator_mutations =
    [ For_test.Drop_claim; Drop_target_entry; Drop_effect; Drop_event;
      Drop_frontier; Drop_session; Drop_before_after; Duplicate_session;
      Swap_effect_and_event; Use_other_purpose_requirements ]
  in
  check "A10 dropped duplicated swapped and cross-purpose denominators refuse"
    (List.for_all
       (fun mutation ->
         not (For_test.denominator_is_exact_with_mutation Global_no_effect
                mutation)
         && not
              (For_test.denominator_is_exact_with_mutation
                 Fenced_unentered_tail mutation))
       denominator_mutations);
  let source_mutations =
    [ For_test.Drop_lower_protocol_source; Drop_root_bootstrap_source;
      Drop_dispatch_store_source;
      Drop_global_no_effect_purpose; Drop_fenced_unentered_tail_purpose;
      Drop_role_denominator; Swap_role_order;
      Drop_current_receipt_prerequisites; Drop_producer_seals_prerequisite;
      Drop_dispatch_writer_prerequisite; Enable_create; Enable_commit;
      Enable_reconcile; Coerce_global_to_fenced_purpose;
      Use_placeholder_recovery_carrier; Use_unit_create_placeholder ]
  in
  check "A11 source identity binds every lower source algebra and posture field"
    (String.length source_digest = 64
     && List.for_all
          (fun mutation ->
            source_digest <> For_test.source_digest_with_mutation mutation)
          source_mutations);
  check "A12 public role and requirement projections are fixed identifiers"
    (List.map role_id roles
     = [ "claim"; "target-entry"; "effect"; "event"; "frontier";
         "session"; "before-after" ]
     && requirement_id No_mutation_attempted = "no-mutation-attempted"
     && requirement_id Pending_transition_and_writer_fence_retained
        = "pending-transition-and-writer-fence-retained");
  Printf.printf "run_abandonment_authority: %d passed, %d failed\n"
    !passed !failed;
  let telemetry =
    Suite_telemetry.observe ~suite:"test_run_abandonment_authority"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit telemetry ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code telemetry)
