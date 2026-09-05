let failures = ref []
let check name condition = if not condition then failures := name :: !failures

let request_id text =
  match Jj_id.Request.make text with
  | Ok value -> value
  | Error _ -> failwith ("invalid conditional request fixture: " ^ text)

let ids values render = List.map render values

let native_create_join :
    Run_root_bootstrap.conditional_interpreter_part ->
    (Run_conditional_authority.interpreter,
     Run_conditional_authority.diagnostic) result =
  Run_conditional_authority.create

let () =
  let b_plan =
    match
      Jj_campaign_action.derive_b_campaign_plan
        ~request_id:(request_id "conditional-b-1")
    with
    | Ok value -> value
    | Error _ -> failwith "B conditional plan fixture refused"
  in
  let completion_plan =
    match
      Jj_campaign_action.derive_completion_reconcile_plan
        ~request_id:(request_id "conditional-completion-1")
    with
    | Ok value -> value
    | Error _ -> failwith "completion conditional plan fixture refused"
  in
  check "T1 family denominator is exact and ordered"
    (ids Run_conditional_authority.families
       Run_conditional_authority.packed_family_id
     = [ "b-campaign"; "completion-reconcile" ]);
  check "T2 B lifecycle state denominator is exact and family-specialized"
    (ids
       (Run_conditional_authority.lifecycle_states
          Run_conditional_authority.B_family)
       Run_conditional_authority.lifecycle_state_id
     = [ "guarded"; "consume-ready"; "action-terminal";
         "decision-pending"; "continue-selected"; "branch-selected";
         "decision-indeterminate" ]);
  check "T3 completion lifecycle has one decision and three exact outcomes"
    (ids
       (Run_conditional_authority.lifecycle_states
          Run_conditional_authority.Completion_family)
       Run_conditional_authority.lifecycle_state_id
     = [ "guarded"; "consume-ready"; "action-terminal";
         "decision-pending"; "applied-exact-selected";
         "not-applied-selected"; "diverged-selected";
         "decision-indeterminate" ]);
  check "T4 internal event denominator is exact and ordered"
    (ids Run_conditional_authority.events
       Run_conditional_authority.event_id
     = [ "prefix-complete"; "decision-committed";
         "decision-replayed"; "condition-not-selected-recorded";
         "decision-refused" ]);
  check "T5 channel denominator is exact and ordered"
    (ids Run_conditional_authority.channels
       Run_conditional_authority.channel_id
     = [ "family-prefix-identity"; "decision-receipt";
         "selected-branch-identity"; "node-disposition" ]);
  let b_schema =
    match Run_conditional_authority.derive b_plan with
    | Ok value -> value
    | Error _ -> failwith "B conditional authority schema refused"
  in
  let completion_schema =
    match Run_conditional_authority.derive completion_plan with
    | Ok value -> value
    | Error _ -> failwith "completion conditional authority schema refused"
  in
  let decisions schema =
    Run_conditional_authority.decision_preparations schema
  in
  check "T6 B decisions equal the exact campaign control denominator"
    (Run_conditional_authority.family_id b_schema = "b-campaign"
     && List.length (decisions b_schema)
        = Jj_campaign_action.decision_node_count b_plan
     && List.length (decisions b_schema) = 23
     && List.for_all
          (fun decision ->
            Run_conditional_authority.decision_node_id decision
            = Run_conditional_authority.decision_control_id decision
            && Run_conditional_authority.decision_prefix_id decision <> ""
            && Run_conditional_authority.decision_branch_ids decision <> []
            && String.length
                 (Run_conditional_authority.decision_preparation_digest
                    decision) = 64)
          (decisions b_schema));
  check "T7 completion derives exactly one comparison decision"
    (Run_conditional_authority.family_id completion_schema
       = "completion-reconcile"
     && List.length (decisions completion_schema) = 1
     && List.length
          (Run_conditional_authority.decision_branch_ids
             (List.hd (decisions completion_schema))) = 3);
  check "T8 derived schemas validate against campaign nodes edges and digests"
    (Result.is_ok (Run_conditional_authority.validate b_schema)
     && Result.is_ok (Run_conditional_authority.validate completion_schema)
     && String.length (Run_conditional_authority.schema_digest b_schema) = 64
     && String.length
          (Run_conditional_authority.schema_digest completion_schema) = 64);
  check "T9 every structural mismatch mutant is rejected"
    (List.for_all
       (fun mutation ->
         b_schema
         |> Run_conditional_authority.For_test.mutate mutation
         |> Run_conditional_authority.validate
         |> Result.is_error)
       [ Run_conditional_authority.For_test.Drop_decision;
         Run_conditional_authority.For_test.Reorder_decisions;
         Run_conditional_authority.For_test.Mismatch_control;
         Run_conditional_authority.For_test.Mismatch_prefix;
         Run_conditional_authority.For_test.Mismatch_branch;
         Run_conditional_authority.For_test.Mismatch_family;
         Run_conditional_authority.For_test.Drop_state;
         Run_conditional_authority.For_test.Reorder_events;
         Run_conditional_authority.For_test.Drop_channel;
         Run_conditional_authority.For_test.Mismatch_projection_digest ]
     && List.for_all
          (fun mutation ->
            completion_schema
            |> Run_conditional_authority.For_test.mutate mutation
            |> Run_conditional_authority.validate
            |> Result.is_error)
          [ Run_conditional_authority.For_test.Drop_decision;
            Run_conditional_authority.For_test.Mismatch_control;
            Run_conditional_authority.For_test.Mismatch_prefix;
            Run_conditional_authority.For_test.Mismatch_branch;
            Run_conditional_authority.For_test.Drop_state;
            Run_conditional_authority.For_test.Reorder_events;
            Run_conditional_authority.For_test.Drop_channel;
            Run_conditional_authority.For_test.Mismatch_projection_digest ]);
  let b_replay =
    match Jj_campaign_action.derive_b_campaign_plan
            ~request_id:(request_id "conditional-b-1") with
    | Error _ -> failwith "B conditional plan replay refused"
    | Ok plan ->
        begin match Run_conditional_authority.derive plan with
        | Ok value -> value
        | Error _ -> failwith "B conditional schema replay refused"
        end
  in
  check "T10 schema digest is replay-stable and request-bound"
    (Run_conditional_authority.schema_digest b_schema
       = Run_conditional_authority.schema_digest b_replay
     && Run_conditional_authority.schema_digest b_schema
        <> Run_conditional_authority.schema_digest completion_schema);
  check "T11 absent store and owner receipts remain exactly unavailable"
    (Run_conditional_authority.production_posture
       = `Implemented_unavailable
     && (ignore native_create_join; true)
     && ids Run_conditional_authority.unavailable_operations
          Run_conditional_authority.unavailable_operation_id
        = [ "prepare-prefix"; "create-interpreter"; "prepare-decision";
            "close-dormant"; "close-claimed-unentered";
            "validate-campaign-terminal"; "reconcile-recovery-only" ]
     && List.for_all
          (fun operation ->
            Result.is_error
              (Run_conditional_authority.prerequisite_status operation))
          Run_conditional_authority.unavailable_operations);
  check "T12 source digest binds denominators and forbids caller authority seams"
    (String.length Run_conditional_authority.source_digest = 64
     && List.for_all
          (fun mutation ->
            Run_conditional_authority.source_digest
            <> Run_conditional_authority.For_test
                 .source_digest_with_mutation mutation)
          [ Run_conditional_authority.For_test.Drop_family;
            Run_conditional_authority.For_test.Drop_state_schema;
            Run_conditional_authority.For_test.Drop_event;
            Run_conditional_authority.For_test.Drop_channel_schema;
            Run_conditional_authority.For_test.Drop_decision_field;
            Run_conditional_authority.For_test.Add_caller_branch_input;
            Run_conditional_authority.For_test.Add_caller_outcome_input;
            Run_conditional_authority.For_test.Add_caller_list_input;
            Run_conditional_authority.For_test.Add_caller_digest_input;
            Run_conditional_authority.For_test.Add_caller_callback_input;
            Run_conditional_authority.For_test.Construct_authorizing_type;
            Run_conditional_authority.For_test
              .Use_placeholder_interpreter_part;
            Run_conditional_authority.For_test
              .Use_placeholder_recovery_carriers ]);
  List.iter (fun name -> Printf.printf "FAILED: %s\n" name)
    (List.rev !failures);
  let failed = List.length !failures in
  let passed = 12 - failed in
  let self =
    Suite_telemetry.observe ~suite:"test_run_conditional_authority"
      ~passed ~failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
