let passed = ref 0
let failed = ref 0
let check name condition =
  if condition then incr passed else (incr failed; Printf.printf "FAILED: %s\n" name)

let int_member name json =
  match Yojson.Safe.Util.member name json with `Int value -> value | _ -> -1

let string_member name json =
  match Yojson.Safe.Util.member name json with
  | `String value -> value
  | _ -> ""

let get = function Ok value -> value | Error _ -> failwith "valid declaration refused"

let () =
  check "F1 portfolio denominator is exactly the five registered owners"
    (List.map (fun (item : Run_fpp_authority.model_entry) -> item.owner)
       Run_fpp_authority.all = Fpp_window_authority.owners);
  check "F2 all real models validate and every module mapping resolves"
    (Run_fpp_authority.validate () = []
     && Run_fpp_authority.diagnostics () = []
     && Run_fpp_authority.module_mapping_gaps () = []
     && Run_fpp_authority.debug_mapping_gaps () = []);
  check "F3 portfolio identity is SHA-256 shaped and deterministic"
    (String.length Run_fpp_authority.source_digest = 64
     && Run_fpp_authority.source_digest = Run_fpp_authority.source_digest);
  check "F4 Ops receipt exposes exact model and module denominators"
    (let json = Run_fpp_authority.receipt_json () in
     int_member "model_total" json = 5
     && int_member "model_valid" json = 5
     && int_member "module_interface_total" json = 39
     && int_member "module_mapping_gaps" json = 0
     && int_member "debug_intent_total" json = 9
     && int_member "debug_mapping_gaps" json = 0
     && string_member "task7a_declaration_digest" json
        = Run_topology.task7a_declaration_digest
     && string_member "jujutsu_fragment_digest" json
        = Run_fpp_authority.jujutsu_fragment_digest
            Run_fpp_authority.jujutsu_fragment
     && int_member "jujutsu_fragment_gaps" json = 0
     && string_member "activation_posture" json
        = "implemented-unavailable");
  let request_id = get (Jj_id.Request.make "task7a-projection-test") in
  let formal_manifest =
    get
      (Jj_campaign_action.formal_manifest ~tool:Jj_action_kind.Gospel
         ~model:(get (Jj_id.Formal_model.make (String.make 64 'b')))
         ~source:(get (Jj_id.Formal_source.make (String.make 64 'a')))
         ~negative_controls:
           [ get (Jj_id.Negative_control.make "mutant.drop-obligation");
             get (Jj_id.Negative_control.make "mutant.accept-failure") ])
  in
  let formal_request =
    Jj_campaign_action.formal_request ~request_id ~manifest:formal_manifest
  in
  let formal_projection =
    Run_topology.standalone_phase_activity formal_request
  in
  let b_plan = get (Jj_campaign_action.derive_b_campaign_plan ~request_id) in
  let completion_plan =
    get (Jj_campaign_action.derive_completion_reconcile_plan ~request_id)
  in
  let receipt_id = get (Jj_id.Receipt.make "task7a-receipt") in
  let event_id = get (Jj_id.Event.make "task7a-event") in
  let phase_projections =
    [ Run_topology.standalone_phase_activity
        (Jj_campaign_action.release_request ~request_id);
      Run_topology.standalone_phase_activity
        formal_request;
      Run_topology.standalone_phase_activity
        (Jj_campaign_action.disposable_request ~request_id
           ~profile:Jj_campaign_action.Semantics
           ~fixture:(Jj_campaign_action.fixture_manifest receipt_id));
      Run_topology.standalone_phase_activity
        (Jj_campaign_action.a0_request ~request_id);
      Run_topology.standalone_phase_activity
        (get
           (Jj_campaign_action.a1_request ~request_id ~selected_objects:1
              ~classified_objects:1));
      Run_topology.standalone_phase_activity
        (Jj_campaign_action.b_recovery_request ~request_id
           ~causal_failure:(Jj_campaign_action.causal_failure event_id)
           ~cut:Jj_recovery_schema.Before_engine
           ~sealed_vault:(Jj_campaign_action.sealed_vault receipt_id));
      Run_topology.standalone_phase_activity
        (Jj_campaign_action.completion_reserve_request ~request_id);
      Run_topology.standalone_phase_activity
        (Jj_campaign_action.completion_record_request ~request_id
           ~workspace_branch:Jj_recovery_schema.Existing);
      Run_topology.standalone_phase_activity
        (Jj_campaign_action.completion_record_recovery_request ~request_id
           ~causal_failure:(Jj_campaign_action.causal_failure event_id)
           ~cut:Jj_recovery_schema.Completion_before_engine
           ~workspace_branch:Jj_recovery_schema.Existing
           ~mode:Jj_recovery_schema.Restarted
           ~sealed_vault:(Jj_campaign_action.sealed_vault receipt_id)
           ~scope_class:Jj_campaign_action.Production_record);
      Run_topology.standalone_phase_activity
        (Jj_campaign_action.completion_final_request ~request_id) ]
  in
  let b_projection = get (Run_topology.b_success_activity b_plan) in
  let completion_projection =
    get (Run_topology.completion_reconcile_activity completion_plan)
  in
  check "F4b formal topology inserts approval consumption before every process"
    (match formal_projection with
     | Error _ -> false
     | Ok activity ->
         let work_ids =
           List.map
             (fun (action : Run_topology.declarative_action) ->
               Run_topology.action_work_id action.work)
             activity.actions
         in
         let rec dependencies_are_linear previous = function
           | [] -> true
           | (action : Run_topology.declarative_action) :: rest ->
               action.dependency_ids
                 = (match previous with None -> [] | Some id -> [ id ])
               && dependencies_are_linear (Some action.stable_id) rest
         in
         work_ids
           = [ "clock:acquire-clock";
               "external-resource:observe-external-resource";
               "approval-nonce:consume-approval-nonce";
               "formal-oracle:gospel:positive";
               "approval-nonce:consume-approval-nonce";
               "formal-oracle:gospel:negative-control:mutant.drop-obligation";
               "approval-nonce:consume-approval-nonce";
               "formal-oracle:gospel:negative-control:mutant.accept-failure" ]
         && dependencies_are_linear None activity.actions);
  check "F5 Task-7A pure Jujutsu/FPP declaration is exact and non-live"
    (List.map Run_topology.effect_kind_id Run_topology.effect_kinds
       = [ "dependability-process-attempt";
           "verification-suite-execution";
           "durable-artifact-publication";
           "external-resource-observation";
           "repository-source-observation";
           "approval-nonce-consumption";
           "writer-lease-transition";
           "production-activation-transition";
           "network-scope-transition";
           "credential-lease-transition";
           "controlled-filesystem-materialization";
           "candidate-tree-verification";
           "jujutsu-observation";
           "jujutsu-local-mutation";
           "jujutsu-history-rewrite";
           "jujutsu-recovery";
           "jujutsu-remote-synchronization";
           "jujutsu-remote-publish";
           "formal-oracle-execution" ]
     && (List.map Run_topology.effect_kind_of_jujutsu_operation Jj_operation.all
         |> List.for_all (fun kind -> List.mem kind Run_topology.effect_kinds))
     && Run_topology.effect_kind_of_jujutsu_operation Jj_operation.Git_fetch
        = Run_topology.Jujutsu_remote_synchronization
     && Run_topology.action_work_gaps
          (Run_topology.Writer_lease_work Jj_action_kind.Acquire_writer_lease)
        = []
     && Run_topology.action_work_gaps
          (Run_topology.Writer_lease_work Jj_action_kind.Acquire_clock)
        <> []
     && Run_topology.action_work_gaps
          (Run_topology.Activation_transition_work
             Jj_action_kind.Activate_source_recovery_branch)
        = []
     && Run_topology.action_work_gaps
          (Run_topology.Activation_transition_work
             (Jj_action_kind.Set_activity_frontier
                Jj_action_kind.Reconciled_terminal))
        <> []
     && Run_topology.action_work_gaps
          (Run_topology.Jujutsu_readback_work
             Jj_action_kind.Readback_jj_state)
        = []
     && Run_topology.action_work_gaps
          (Run_topology.Jujutsu_readback_work
             Jj_action_kind.Reserve_completion_receipt)
        <> []
     && Run_topology.action_work_gaps
          (Run_topology.Completion_receipt_work
             Jj_action_kind.Reserve_completion_receipt)
        = []
     && Run_topology.action_work_gaps
          (Run_topology.Completion_receipt_work
             Jj_action_kind.Finalize_completion_receipt)
        = []
     && Run_topology.action_work_gaps
          (Run_topology.Completion_receipt_work
             Jj_action_kind.Readback_jj_state)
        <> []
     && Run_topology.action_work_id
          (Run_topology.Completion_receipt_work
             Jj_action_kind.Reserve_completion_receipt)
        <> Run_topology.action_work_id
             (Run_topology.Completion_receipt_work
                Jj_action_kind.Finalize_completion_receipt)
     && Run_topology.task7a_completion_receipt_work_ids
        = [ Run_topology.action_work_id
              (Run_topology.Completion_receipt_work
                 Jj_action_kind.Reserve_completion_receipt);
            Run_topology.action_work_id
              (Run_topology.Completion_receipt_work
                 Jj_action_kind.Finalize_completion_receipt) ]
     && String.length Run_topology.task7a_completion_receipt_work_digest = 64
     && List.length Run_topology.task7a_action_work_class_ids = 16
     && List.length
          (List.sort_uniq String.compare
             Run_topology.task7a_action_work_class_ids) = 16
     && String.length Run_topology.task7a_action_work_class_digest = 64
     && Run_topology.live_execution_posture = `Implemented_unavailable
     && Run_topology.task7a_declaration_gaps () = []
     && List.length Run_topology.task7a_declaration_activities
        = List.length Jj_operation.all + 1
     && Run_topology.constructible_static_template_count
        = Run_topology.expected_static_template_count
     && Run_topology.expected_static_template_count = 47
     && List.length Run_topology.task7a_static_templates = 47
     && String.length Run_topology.task7a_static_template_digest = 64
     && List.for_all Result.is_ok phase_projections
     && String.length Run_topology.task7a_declaration_digest = 64
     && List.for_all
          (fun mutation ->
             Run_topology.task7a_declaration_digest
             <> Run_topology.For_test.task7a_declaration_digest_with_mutation
                  mutation)
          [ Run_topology.For_test.Drop_declaration_activity;
            Duplicate_declaration_action;
            Claim_live_bridge;
            Drop_static_template;
            Reorder_work_class;
            Flatten_conditional_controls;
            Swap_completion_receipt_order ]
     && Run_topology.conditional_projection_posture
        = `Implemented
     && List.for_all
          (fun prerequisite ->
             Result.is_ok
               (Run_topology.conditional_projection_prerequisite_status
                  prerequisite))
          [ Run_topology.Public_ten_phase_enum;
            Occurrence_phase_ordinal_accessor;
            Conditional_node_identity_accessor;
            Conditional_guard_control_ids;
            Conditional_edge_label_accessor;
            Readback_completion_work_carriers;
            Multi_target_activity_schema;
            Conditional_activity_schema;
            Failure_recovery_policy_schema;
            Plan_dispatch_identity_schema ]
     && Run_topology.conditional_projection_family_id b_projection
        = "b-campaign"
     && Run_topology.conditional_projection_family_id completion_projection
        = "completion-reconcile"
     && Run_topology.conditional_projection_plan_digest b_projection
        = Jj_campaign_action.conditional_projection_digest b_plan
     && Run_topology.conditional_projection_plan_digest completion_projection
        = Jj_campaign_action.conditional_projection_digest completion_plan
     && Run_topology.conditional_projection_dispatch_key b_projection
        <> Run_topology.conditional_projection_dispatch_key completion_projection
     && List.length
          (Run_topology.conditional_projection_external_actions b_projection)
        = Jj_campaign_action.action_node_count b_plan
     && List.length
          (Run_topology.conditional_projection_internal_controls b_projection)
        = Jj_campaign_action.consume_node_count b_plan
          + Jj_campaign_action.decision_node_count b_plan
     && List.length (Run_topology.conditional_projection_edges b_projection)
        = List.length (Jj_campaign_action.guarded_edges b_plan)
     && List.length
          (Run_topology.conditional_projection_external_actions
             completion_projection)
        = Jj_campaign_action.action_node_count completion_plan
     && List.length
          (Run_topology.conditional_projection_internal_controls
             completion_projection)
        = Jj_campaign_action.consume_node_count completion_plan
          + Jj_campaign_action.decision_node_count completion_plan
     && List.length
          (Run_topology.conditional_projection_edges completion_projection)
        = List.length (Jj_campaign_action.guarded_edges completion_plan)
     && List.for_all
          (fun action -> Run_topology.action_work_gaps action.Run_topology.work = [])
          (Run_topology.conditional_projection_external_actions b_projection
           @ Run_topology.conditional_projection_external_actions
               completion_projection)
     && Run_fpp_authority.activation_posture = `Implemented_unavailable
     && Run_fpp_authority.jujutsu_fragment_gaps () = []
     && String.length
          (Run_fpp_authority.jujutsu_fragment_digest
             Run_fpp_authority.jujutsu_fragment) = 64
     && List.length
          (Run_fpp_authority.jujutsu_operation_activity_ids
             Run_fpp_authority.jujutsu_fragment)
        = List.length Jj_operation.all
     && List.length
          (Run_fpp_authority.standalone_phase_template_ids
             Run_fpp_authority.jujutsu_fragment)
        = Jj_campaign_action.standalone_phase_count
     && List.length
          (Run_fpp_authority.conditional_family_template_ids
             Run_fpp_authority.jujutsu_fragment)
        = 2
     && List.length
          (Run_fpp_authority.candidate_verification_action_ids
             Run_fpp_authority.jujutsu_fragment)
        = List.length Jj_action_kind.candidate_steps
     && List.length
          (Run_fpp_authority.formal_oracle_action_ids
             Run_fpp_authority.jujutsu_fragment)
        = 0
     && Run_fpp_authority.action_work_class_ids
          Run_fpp_authority.jujutsu_fragment
        = Run_topology.task7a_action_work_class_ids
     && Run_fpp_authority.completion_receipt_work_ids
          Run_fpp_authority.jujutsu_fragment
        = Run_topology.task7a_completion_receipt_work_ids
     && Run_fpp_authority.static_template_digest
          Run_fpp_authority.jujutsu_fragment
        = Run_topology.task7a_static_template_digest
     && List.for_all
          (fun mutation ->
             let mutated =
               Run_fpp_authority.For_test.mutate_fragment mutation
             in
             Run_fpp_authority.For_test.validate_fragment mutated <> []
             && Run_fpp_authority.jujutsu_fragment_digest mutated
                <> Run_fpp_authority.jujutsu_fragment_digest
                     Run_fpp_authority.jujutsu_fragment)
          [ Run_fpp_authority.For_test.Drop_jujutsu_effect;
            Duplicate_operation_activity;
            Drop_conditional_channel;
            Claim_live_activation;
            Drop_phase_template;
            Flatten_conditional_template;
            Swap_completion_receipt_work ]);
  List.iter
    (fun (name, mutation) ->
      check ("NEGATIVE CONTROL: " ^ name)
        (Run_fpp_authority.For_test.validate_entries
           (Run_fpp_authority.For_test.mutate mutation) <> []))
    [ ("Wiki omitted", Run_fpp_authority.For_test.Drop_wiki);
      ("Harness duplicated", Duplicate_harness);
      ("Ops model renamed", Rename_ops_model);
      ("mapped component removed", Drop_mapped_component);
      ("debug component removed", Drop_debug_component);
      ("debug event removed", Drop_debug_event) ];
  Printf.printf "run_fpp_authority: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_run_fpp_authority"
      ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
