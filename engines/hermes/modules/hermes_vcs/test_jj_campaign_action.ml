let failures = ref []
let check name condition = if not condition then failures := name :: !failures

let request_id text =
  match Jj_id.Request.make text with
  | Ok value -> value
  | Error _ -> failwith ("invalid request fixture: " ^ text)

let approval_id text =
  match Jj_id.Approval.make text with
  | Ok value -> value
  | Error _ -> failwith ("invalid approval fixture: " ^ text)

let operation_id text =
  match Jj_id.Operation.make text with
  | Ok value -> value
  | Error _ -> failwith ("invalid operation fixture: " ^ text)

let receipt_id text =
  match Jj_id.Receipt.make text with
  | Ok value -> value
  | Error _ -> failwith ("invalid receipt fixture: " ^ text)

let formal_source text =
  match Jj_id.Formal_source.make text with
  | Ok value -> value
  | Error _ -> failwith "invalid formal source fixture"

let formal_model text =
  match Jj_id.Formal_model.make text with
  | Ok value -> value
  | Error _ -> failwith "invalid formal model fixture"

let negative_control text =
  match Jj_id.Negative_control.make text with
  | Ok value -> value
  | Error _ -> failwith ("invalid negative-control fixture: " ^ text)

let action_keys values =
  List.map
    (fun occurrence ->
      Jj_action_kind.action_key
        (Jj_campaign_action.occurrence_action occurrence))
    values

let () =
  let release =
    Jj_campaign_action.release_request ~request_id:(request_id "release-1")
  in
  check "C1 release is a closed phase-indexed exact standalone projection"
    (action_keys (Jj_campaign_action.standalone_phase_declarations release)
     = [ "auxiliary:acquire-clock";
         "auxiliary:observe-external-resource";
         "auxiliary:observe-release-bundle";
         "auxiliary:observe-tree" ]);
  let formal_negative_controls =
    [ negative_control "mutant.drop-readback";
      negative_control "mutant.accept-divergence" ]
  in
  let formal_manifest =
    match
      Jj_campaign_action.formal_manifest ~tool:Jj_action_kind.Quint
        ~model:(formal_model (String.make 64 'b'))
        ~source:(formal_source (String.make 64 'a'))
        ~negative_controls:formal_negative_controls
    with
    | Ok value -> value
    | Error _ -> failwith "formal manifest fixture refused"
  in
  let formal_request =
    Jj_campaign_action.formal_request ~request_id:(request_id "formal-1")
      ~manifest:formal_manifest
  in
  let formal_occurrences =
    Jj_campaign_action.standalone_phase_declarations formal_request
  in
  let a0 = Jj_campaign_action.a0_request ~request_id:(request_id "a0-1") in
  check "C2 A0 preserves the exact ordered observation denominator"
    (action_keys (Jj_campaign_action.standalone_phase_declarations a0)
     = [ "auxiliary:acquire-clock";
         "auxiliary:observe-external-resource";
         "jujutsu:operation-head";
         "jujutsu:status-at-operation";
         "jujutsu:resolve-list-at-operation";
         "jujutsu:operation-log-at-operation";
         "jujutsu:revision-log-at-operation";
         "jujutsu:bookmark-list-at-operation";
         "jujutsu:workspace-list-at-operation";
         "jujutsu:remote-list-at-operation";
         "jujutsu:diff-summary-at-operation";
         "jujutsu:diff-stat-at-operation";
         "jujutsu:diff-patch-at-operation";
         "auxiliary:observe-repository-source";
         "auxiliary:observe-tree" ]);
  let a1 =
    Jj_campaign_action.a1_request ~request_id:(request_id "a1-1")
      ~selected_objects:2 ~classified_objects:3
  in
  check "C3 A1 derives bounded multiplicity and the fixed candidate suffix"
    (match a1 with
     | Error _ -> false
     | Ok request ->
         let keys = action_keys
             (Jj_campaign_action.standalone_phase_declarations request) in
         List.length keys = 12
         && List.filter (String.equal "jujutsu:file-show-at-operation") keys
            |> List.length = 2
         && List.filter (String.equal "auxiliary:observe-object") keys
            |> List.length = 3
         && List.rev keys |> List.hd = "auxiliary:remove-disposable-scope");
  check "C4 unbounded A1 multiplicity refuses"
    (Result.is_error
       (Jj_campaign_action.a1_request ~request_id:(request_id "a1-big")
          ~selected_objects:1025 ~classified_objects:0));
  let b_plan =
    Jj_campaign_action.derive_b_campaign_plan
      ~request_id:(request_id "b-1")
  in
  check "C5 structural B owns one exact spine and all canonical cut branches"
    (match b_plan with
     | Error _ -> false
     | Ok plan ->
         List.length (Jj_campaign_action.common_declarations plan) = 23
         && List.length (Jj_campaign_action.conditional_branches plan) > 46
         && List.for_all
              (fun branch ->
                match Jj_campaign_action.branch_guard branch with
                | Jj_campaign_action.B_guard (_, _) -> true
                | Jj_campaign_action.Completion_guard _ -> false)
              (Jj_campaign_action.conditional_branches plan));
  let completion =
    Jj_campaign_action.derive_completion_reconcile_plan
      ~request_id:(request_id "completion-1")
  in
  check "C6 completion reconciliation has one prefix and exactly three guards"
    (match completion with
     | Error _ -> false
     | Ok plan ->
         List.length (Jj_campaign_action.common_declarations plan) = 4
         && List.map
              (fun branch ->
                match Jj_campaign_action.branch_guard branch with
                | Jj_campaign_action.Completion_guard outcome -> outcome
                | Jj_campaign_action.B_guard _ -> Jj_campaign_action.Diverged)
              (Jj_campaign_action.conditional_branches plan)
            = [ Jj_campaign_action.Applied_exact;
                Jj_campaign_action.Not_applied;
                Jj_campaign_action.Diverged ]);
  let release_occurrences =
    Jj_campaign_action.standalone_phase_declarations release in
  check "C7 occurrence and nonce identities are distinct and canonical bytes bind order"
    (let occurrence_ids = List.map Jj_campaign_action.occurrence_id release_occurrences in
     let nonce_ids = List.map Jj_campaign_action.occurrence_nonce release_occurrences in
     List.length occurrence_ids = List.length (List.sort_uniq String.compare occurrence_ids)
     && List.length nonce_ids = List.length (List.sort_uniq String.compare nonce_ids)
     && String.length (Jj_campaign_action.canonical_unsigned_bytes release_occurrences) > 0);
  let completion_reserve =
    Jj_campaign_action.completion_reserve_request
      ~request_id:(request_id "completion-reserve-1") in
  check "C8 completion reserve has the sole allocation occurrence"
    (action_keys
       (Jj_campaign_action.standalone_phase_declarations completion_reserve)
     = [ "auxiliary:reserve-completion-receipt" ]);
  let completion_record_existing =
    Jj_campaign_action.completion_record_request
      ~request_id:(request_id "completion-record-existing-1")
      ~workspace_branch:Jj_recovery_schema.Existing in
  check "C9 completion record existing workspace has the exact ordered denominator"
    (action_keys
       (Jj_campaign_action.standalone_phase_declarations
          completion_record_existing)
     = [ "auxiliary:acquire-writer-lease";
         "auxiliary:stage-recovery-set";
         "jujutsu:new-change";
         "auxiliary:readback-jj-state";
         "auxiliary:write-sealed-record-candidate";
         "auxiliary:observe-tree";
         "jujutsu:working-copy-snapshot";
         "auxiliary:readback-jj-state";
         "auxiliary:observe-tree";
         "jujutsu:describe";
         "auxiliary:readback-jj-state";
         "auxiliary:observe-tree";
         "auxiliary:observe-repository-source";
         "frontier:set-activity-frontier:reconciled-terminal";
         "auxiliary:cleanup-recovery-set";
         "auxiliary:release-writer-lease" ]);
  let completion_record_new =
    Jj_campaign_action.completion_record_request
      ~request_id:(request_id "completion-record-new-1")
      ~workspace_branch:Jj_recovery_schema.Newly_allocated in
  check "C10 completion record new workspace inserts its exact observation join"
    (let keys =
       action_keys
         (Jj_campaign_action.standalone_phase_declarations
            completion_record_new) in
     List.length keys = 20
     && List.filter (String.equal "jujutsu:workspace-add") keys
        |> List.length = 1
     && List.nth keys 2 = "jujutsu:workspace-add"
     && List.nth keys 3 = "auxiliary:readback-jj-state"
     && List.nth keys 4 = "auxiliary:observe-tree"
     && List.nth keys 5 = "auxiliary:observe-repository-source");
  let completion_final =
    Jj_campaign_action.completion_final_request
      ~request_id:(request_id "completion-final-1") in
  check "C11 completion final has the exact no-extra-action order"
    (action_keys
       (Jj_campaign_action.standalone_phase_declarations completion_final)
     = [ "auxiliary:acquire-writer-lease";
         "jujutsu:bookmark-set";
         "auxiliary:readback-jj-state";
         "auxiliary:observe-tree";
         "auxiliary:observe-repository-source";
         "frontier:set-activity-frontier:reconciled-terminal";
         "auxiliary:release-writer-lease";
         "auxiliary:finalize-completion-receipt" ]);
  check "C12 conditional signed denominators are exact and identity-disjoint"
    (match b_plan, completion with
     | Ok b, Ok c ->
         Jj_campaign_action.conditional_branch_count b = 105
         && Jj_campaign_action.conditional_branch_count c = 3
         && Jj_campaign_action.conditional_identities_are_disjoint b
         && Jj_campaign_action.conditional_identities_are_disjoint c
         && String.length
              (Jj_campaign_action.canonical_conditional_unsigned_bytes b) > 0
         && String.length
              (Jj_campaign_action.canonical_conditional_unsigned_bytes c) > 0
     | _ -> false);
  check "C13 B nodes wrap every occurrence and own one decision per prefix"
    (match b_plan with
     | Error _ -> false
     | Ok plan ->
         let occurrences =
           List.length (Jj_campaign_action.common_declarations plan)
           + List.fold_left
               (fun count branch ->
                 count
                 + List.length
                     (Jj_campaign_action.branch_declarations branch))
               0 (Jj_campaign_action.conditional_branches plan)
         in
         Jj_campaign_action.consume_node_count plan = occurrences
         && Jj_campaign_action.action_node_count plan = occurrences
         && Jj_campaign_action.decision_node_count plan = 23
         && Jj_campaign_action.node_count plan = (2 * occurrences) + 23
         && List.for_all
              (fun node ->
                match Jj_campaign_action.node_kind node with
                | Jj_campaign_action.Consume_node_kind ->
                    Jj_campaign_action.node_nonce node = None
                | Jj_campaign_action.Action_node_kind ->
                    Option.is_some (Jj_campaign_action.node_nonce node)
                | Jj_campaign_action.Decision_node_kind ->
                    Jj_campaign_action.node_nonce node = None)
              (Jj_campaign_action.conditional_nodes plan));
  check "C14 completion owns one final decision and no intermediate control"
    (match completion with
     | Error _ -> false
     | Ok plan ->
         Jj_campaign_action.decision_node_count plan = 1
         && Jj_campaign_action.control_count plan = 1
         && List.length
              (List.filter
                 (fun node ->
                   Jj_campaign_action.node_guard_shape node
                   = Jj_campaign_action.Always_guard)
                 (Jj_campaign_action.conditional_nodes plan))
            = 9);
  check "C15 guarded DAGs are exact deterministic acyclic and aggregate-reaching"
    (match b_plan, completion with
     | Ok b, Ok c ->
         let b_branch_occurrences =
           List.fold_left
             (fun count branch ->
               count
               + List.length (Jj_campaign_action.branch_declarations branch))
             0 (Jj_campaign_action.conditional_branches b)
         in
         let edge_projection plan =
           List.map
             (fun edge ->
               (Jj_campaign_action.edge_source edge,
                Jj_campaign_action.edge_target edge))
             (Jj_campaign_action.guarded_edges plan)
         in
         let b_replay =
           Jj_campaign_action.derive_b_campaign_plan
             ~request_id:(request_id "b-1")
         in
         List.length (Jj_campaign_action.guarded_edges b)
           = 137 + (4 * b_branch_occurrences)
         && List.length (Jj_campaign_action.guarded_edges c) = 38
         && (match b_replay with
             | Ok replay -> edge_projection replay = edge_projection b
             | Error _ -> false)
         && Jj_campaign_action.edges_are_acyclic b
         && Jj_campaign_action.edges_are_acyclic c
         && Jj_campaign_action.all_nodes_reach_aggregate b
         && Jj_campaign_action.all_nodes_reach_aggregate c
     | _ -> false);
  check "C16 canonical bytes bind every signed node and guarded edge"
    (match b_plan, completion with
     | Ok b, Ok c ->
         let changed plan mutation =
           Jj_campaign_action.canonical_conditional_unsigned_bytes plan
           <> Jj_campaign_action.For_test.canonical_with_mutation plan mutation
         in
         changed b Jj_campaign_action.For_test.Drop_node
         && changed b Jj_campaign_action.For_test.Drop_edge
         && changed b Jj_campaign_action.For_test.Reverse_edge
         && changed c Jj_campaign_action.For_test.Drop_node
         && changed c Jj_campaign_action.For_test.Drop_edge
         && changed c Jj_campaign_action.For_test.Reverse_edge
     | _ -> false);
  let shared_request = request_id "standalone-shared" in
  let fixture =
    Jj_campaign_action.fixture_manifest
      (match Jj_id.Receipt.make "fixture-main" with
       | Ok value -> value
       | Error _ -> failwith "fixture identity refused")
  in
  let failure =
    Jj_campaign_action.causal_failure
      (match Jj_id.Event.make "causal-failure-main" with
       | Ok value -> value
       | Error _ -> failwith "failure identity refused")
  in
  let vault =
    Jj_campaign_action.sealed_vault
      (match Jj_id.Receipt.make "sealed-vault-main" with
       | Ok value -> value
       | Error _ -> failwith "vault identity refused")
  in
  let disposable =
    Jj_campaign_action.disposable_request ~request_id:shared_request
      ~profile:Jj_campaign_action.Semantics ~fixture
  in
  check "C17 Disposable binds profile and fixture to one exact base denominator"
    (action_keys (Jj_campaign_action.standalone_phase_declarations disposable)
     = [ "auxiliary:acquire-clock";
         "auxiliary:observe-external-resource";
         "auxiliary:materialize-candidate";
         "jujutsu:repository-init";
         "auxiliary:remove-disposable-scope" ]
     && let surface =
          Jj_campaign_action.disposable_request ~request_id:shared_request
            ~profile:Jj_campaign_action.Surface_equivalence ~fixture
        in
        Jj_campaign_action.canonical_unsigned_bytes
          (Jj_campaign_action.standalone_phase_declarations disposable)
        <> Jj_campaign_action.canonical_unsigned_bytes
             (Jj_campaign_action.standalone_phase_declarations surface));
  let partial =
    match Jj_recovery_schema.partial_prefix ~completed:1 ~total:3 with
    | Ok value -> value
    | Error _ -> failwith "partial-prefix fixture refused"
  in
  let b_cut =
    Jj_recovery_schema.After_action
      (Jj_recovery_schema.B_write_partition_partial partial)
  in
  let b_recovery =
    Jj_campaign_action.b_recovery_request ~request_id:shared_request
      ~causal_failure:failure ~cut:b_cut ~sealed_vault:vault
  in
  let expected_b_recovery =
    Jj_recovery_schema.schema
      (Jj_recovery_schema.B_success
         (b_cut, Jj_recovery_schema.Restarted))
    |> Jj_recovery_schema.b_branches
    |> List.concat_map Jj_recovery_schema.b_steps
    |> List.map Jj_recovery_schema.recovery_step_action
    |> List.map Jj_action_kind.action_key
  in
  check "C18 B_recovery is restart-only and equals its complete schema denominator"
    (action_keys
       (Jj_campaign_action.standalone_phase_declarations b_recovery)
     = expected_b_recovery);
  let record_cut =
    Jj_recovery_schema.Completion_after_action
      (Jj_recovery_schema.Record_write_candidate_partial partial)
  in
  let record_recovery =
    Jj_campaign_action.completion_record_recovery_request
      ~request_id:shared_request ~causal_failure:failure ~cut:record_cut
      ~workspace_branch:Jj_recovery_schema.Newly_allocated
      ~mode:Jj_recovery_schema.In_process ~sealed_vault:vault
      ~scope_class:Jj_campaign_action.Disposable_test
  in
  let expected_record_recovery =
    Jj_recovery_schema.schema
      (Jj_recovery_schema.Completion_record
         (record_cut, Jj_recovery_schema.Newly_allocated,
          Jj_recovery_schema.In_process))
    |> Jj_recovery_schema.completion_record_branches
    |> List.concat_map Jj_recovery_schema.completion_record_steps
    |> List.map Jj_recovery_schema.recovery_step_action
    |> List.map Jj_action_kind.action_key
  in
  check "C19 Completion_record_recovery equals its exact cut/workspace/mode schema"
    (action_keys
       (Jj_campaign_action.standalone_phase_declarations record_recovery)
     = expected_record_recovery
     && let production =
          Jj_campaign_action.completion_record_recovery_request
            ~request_id:shared_request ~causal_failure:failure ~cut:record_cut
            ~workspace_branch:Jj_recovery_schema.Newly_allocated
            ~mode:Jj_recovery_schema.In_process ~sealed_vault:vault
            ~scope_class:Jj_campaign_action.Production_record
        in
        Jj_campaign_action.canonical_unsigned_bytes
          (Jj_campaign_action.standalone_phase_declarations record_recovery)
        <> Jj_campaign_action.canonical_unsigned_bytes
             (Jj_campaign_action.standalone_phase_declarations production));
  check "C20 ten standalone phases are identity-disjoint from conditional families"
    (Jj_campaign_action.standalone_phase_count = 10
     && let declarations =
          [ Jj_campaign_action.standalone_phase_declarations disposable;
            Jj_campaign_action.standalone_phase_declarations b_recovery;
            Jj_campaign_action.standalone_phase_declarations record_recovery ]
          |> List.concat
        in
        let identities =
          List.map Jj_campaign_action.occurrence_id declarations
          @ List.map Jj_campaign_action.occurrence_nonce declarations
        in
        List.length identities
        = List.length (List.sort_uniq String.compare identities));
  let approval_reference = approval_id "campaign-approval" in
  let approval_receipt = receipt_id "campaign-evidence" in
  let expected_operation = operation_id "operation-before" in
  let make_payload occurrence phase_context =
    Jj_campaign_action.approval_payload ~approval_reference ~occurrence
      ~phase_context
      ~constraints:
        [ Jj_campaign_action.Authorized_phase;
          Jj_campaign_action.Exact_head;
          Jj_campaign_action.No_publication ]
      ~expected_identities:
        [ Jj_campaign_action.Expected_operation expected_operation;
          Jj_campaign_action.Expected_receipt approval_receipt ]
  in
  let first declarations = List.hd declarations in
  let a1_request =
    match Jj_campaign_action.a1_request
            ~request_id:(request_id "a1-approval")
            ~selected_objects:2 ~classified_objects:1 with
    | Ok value -> value
    | Error _ -> failwith "A1 approval fixture refused"
  in
  let approval_payloads =
    [ make_payload (first release_occurrences)
        (Jj_campaign_action.Approval_release approval_receipt);
      make_payload
        (List.nth formal_occurrences 2)
        (Jj_campaign_action.Approval_formal
           (formal_manifest, approval_receipt));
      make_payload
        (first (Jj_campaign_action.standalone_phase_declarations a0))
        (Jj_campaign_action.Approval_a0 expected_operation);
      make_payload
        (first (Jj_campaign_action.standalone_phase_declarations a1_request))
        (Jj_campaign_action.Approval_a1 (2, 1, approval_receipt));
      (match b_plan with
       | Error _ -> Error Jj_campaign_action.Empty_manifest
       | Ok plan ->
           make_payload (first (Jj_campaign_action.common_declarations plan))
             (Jj_campaign_action.Approval_b
                (Jj_campaign_action.B_success_context
                   (expected_operation, approval_receipt))));
      (match completion with
       | Error _ -> Error Jj_campaign_action.Empty_manifest
       | Ok plan ->
           make_payload (first (Jj_campaign_action.common_declarations plan))
             (Jj_campaign_action.Approval_completion
                (Jj_campaign_action.Completion_reconcile_pending_context
                   approval_receipt))) ]
  in
  check "C21 six approval contexts bind one closed occurrence projection"
    (List.for_all
       (function
         | Error _ -> false
         | Ok payload ->
             let projection =
               Jj_campaign_action.approval_projection payload in
             projection.occurrence_ordinal
             = Jj_campaign_action.occurrence_ordinal projection.occurrence
             && String.length
                  (Jj_campaign_action.canonical_approval_unsigned_bytes
                     payload) > 0)
       approval_payloads);
  let release_payload =
    match List.hd approval_payloads with
    | Ok value -> value
    | Error _ -> failwith "release approval payload refused"
  in
  let approval_changed mutation =
    Jj_campaign_action.canonical_approval_unsigned_bytes release_payload
    <> Jj_campaign_action.For_test.canonical_approval_with_mutation
         release_payload mutation
  in
  check "C22 phase mutant changes canonical approval bytes"
    (approval_changed Jj_campaign_action.For_test.Change_approval_phase);
  check "C23 occurrence-order mutant changes canonical approval bytes"
    (approval_changed Jj_campaign_action.For_test.Change_occurrence_ordinal);
  check "C24 constraint mutant changes canonical approval bytes"
    (approval_changed Jj_campaign_action.For_test.Change_approval_constraint);
  check "C25 expected-identity mutant changes canonical approval bytes"
    (approval_changed Jj_campaign_action.For_test.Change_expected_identity);
  check "C26 mismatched phase and empty approval denominators refuse"
    (Result.is_error
       (make_payload (first release_occurrences)
          (Jj_campaign_action.Approval_a0 expected_operation))
     && (match b_plan with
         | Error _ -> false
         | Ok plan ->
             Result.is_error
               (make_payload
                  (first (Jj_campaign_action.common_declarations plan))
                  (Jj_campaign_action.Approval_b
                     (Jj_campaign_action.B_recovery_context
                        (Jj_recovery_schema.Before_engine,
                         expected_operation, approval_receipt)))))
     && (match completion with
         | Error _ -> false
         | Ok plan ->
             Result.is_error
               (make_payload
                  (first (Jj_campaign_action.common_declarations plan))
                  (Jj_campaign_action.Approval_completion
                     (Jj_campaign_action.Completion_reconcile_outcome_context
                        (Jj_campaign_action.Applied_exact,
                         approval_receipt)))))
     && Result.is_error
          (Jj_campaign_action.approval_payload ~approval_reference
             ~occurrence:(first release_occurrences)
             ~phase_context:
               (Jj_campaign_action.Approval_release approval_receipt)
             ~constraints:[]
             ~expected_identities:
               [Jj_campaign_action.Expected_operation expected_operation])
     && Result.is_error
          (Jj_campaign_action.approval_payload ~approval_reference
             ~occurrence:(first release_occurrences)
             ~phase_context:
               (Jj_campaign_action.Approval_release approval_receipt)
             ~constraints:[Jj_campaign_action.Authorized_phase]
             ~expected_identities:[]));
  check "C27 source digest binds campaign bounds and approval constraints"
    (String.length Jj_campaign_action.source_digest = 64
     && Jj_campaign_action.source_digest
        <> Jj_campaign_action.For_test.source_digest_with_mutation
             Jj_campaign_action.For_test.Change_manifest_bound
     && Jj_campaign_action.source_digest
        <> Jj_campaign_action.For_test.source_digest_with_mutation
             Jj_campaign_action.For_test.Drop_constraint
     && Jj_campaign_action.source_digest
        <> Jj_campaign_action.For_test.source_digest_with_mutation
             Jj_campaign_action.For_test.Drop_descriptor_schema);
  let phase_ids =
    List.map Jj_campaign_action.standalone_phase_kind_id
      Jj_campaign_action.standalone_phase_kinds
  in
  check "C28 standalone phase-family denominator is closed exact and digest-bound"
    (phase_ids
     = [ "release"; "formal"; "disposable"; "a0"; "a1";
         "b-recovery"; "completion-reserve"; "completion-record";
         "completion-record-recovery"; "completion-final" ]
     && (match Jj_campaign_action.standalone_phase_kind release with
         | Jj_campaign_action.Release_phase -> true
         | Jj_campaign_action.Formal_phase
         | Jj_campaign_action.Disposable_phase
         | Jj_campaign_action.A0_phase
         | Jj_campaign_action.A1_phase
         | Jj_campaign_action.B_recovery_phase
         | Jj_campaign_action.Completion_reserve_phase
         | Jj_campaign_action.Completion_record_phase
         | Jj_campaign_action.Completion_record_recovery_phase
         | Jj_campaign_action.Completion_final_phase -> false)
     && String.length
          Jj_campaign_action.standalone_phase_denominator_digest = 64
     && List.for_all
          (fun mutation ->
            Jj_campaign_action.standalone_phase_denominator_digest
            <> Jj_campaign_action.For_test
                 .standalone_phase_denominator_digest_with_mutation mutation)
          [ Jj_campaign_action.For_test.Drop_descriptor;
            Jj_campaign_action.For_test.Reorder_descriptors;
            Jj_campaign_action.For_test.Mismatch_identity ]);
  let release_descriptors =
    List.map Jj_campaign_action.occurrence_descriptor release_occurrences
  in
  check "C29 occurrence descriptors expose exact phase ordinal and stable identities"
    (List.map
       (fun (descriptor : Jj_campaign_action.occurrence_descriptor) ->
         descriptor.occurrence_phase_ordinal)
       release_descriptors
     = [ 0; 1; 2; 3 ]
     && List.for_all
          (fun (descriptor : Jj_campaign_action.occurrence_descriptor) ->
            descriptor.occurrence_phase_id = "release"
            && String.length descriptor.stable_occurrence_id > 0
            && String.length descriptor.stable_nonce_id > 0
            && Jj_action_kind.action_key descriptor.occurrence_action_identity
               <> "")
          release_descriptors
     && String.length (Jj_campaign_action.standalone_projection_digest release)
        = 64
     && List.for_all
          (fun mutation ->
            Jj_campaign_action.standalone_projection_digest release
            <> Jj_campaign_action.For_test
                 .standalone_projection_digest_with_mutation release mutation)
          [ Jj_campaign_action.For_test.Drop_descriptor;
            Jj_campaign_action.For_test.Reorder_descriptors;
            Jj_campaign_action.For_test.Mismatch_identity ]);
  check "C30 conditional node descriptors bind node guard control prefix and branch identity"
    (match b_plan with
     | Error _ -> false
     | Ok plan ->
         let descriptors =
           List.map Jj_campaign_action.conditional_node_descriptor
             (Jj_campaign_action.conditional_nodes plan)
         in
         List.exists
           (function
             | Jj_campaign_action.Decision_descriptor
                 { node_id; guard = Jj_campaign_action.Always_guard_descriptor;
                   control_id; prefix_id; branch_ids } ->
                 node_id = control_id && prefix_id <> "" && branch_ids <> []
             | Jj_campaign_action.Decision_descriptor
                 { node_id; guard =
                     Jj_campaign_action.All_continue_guard_descriptor
                       { control_ids };
                   control_id; prefix_id; branch_ids } ->
                 node_id = control_id && control_ids <> []
                 && prefix_id <> "" && branch_ids <> []
             | Jj_campaign_action.Consume_descriptor _
             | Jj_campaign_action.Action_descriptor _
             | Jj_campaign_action.Decision_descriptor _ -> false)
           descriptors
         && List.for_all
              (function
                | Jj_campaign_action.Consume_descriptor
                    { node_id; parent_occurrence_id; _ } ->
                    node_id <> parent_occurrence_id
                | Jj_campaign_action.Action_descriptor
                    { node_id; occurrence; _ } ->
                    node_id = occurrence.stable_occurrence_id
                | Jj_campaign_action.Decision_descriptor
                    { node_id; control_id; _ } -> node_id = control_id)
              descriptors
         && List.for_all
              (fun mutation ->
                Jj_campaign_action.conditional_node_projection_digest plan
                <> Jj_campaign_action.For_test
                     .conditional_node_projection_digest_with_mutation
                       plan mutation)
              [ Jj_campaign_action.For_test.Drop_descriptor;
                Jj_campaign_action.For_test.Reorder_descriptors;
                Jj_campaign_action.For_test.Mismatch_identity ]);
  check "C31 guarded edge descriptors bind label and exact guard identity"
    (match completion with
     | Error _ -> false
     | Ok plan ->
         let descriptors =
           List.map Jj_campaign_action.conditional_edge_descriptor
             (Jj_campaign_action.guarded_edges plan)
         in
         descriptors <> []
         && List.for_all
              (fun (descriptor :
                      Jj_campaign_action.conditional_edge_descriptor) ->
                descriptor.edge_source_id <> ""
                && descriptor.edge_target_id <> ""
                && descriptor.edge_label <> ""
                && descriptor.edge_guard_identity <> "")
              descriptors
         && List.exists
              (fun (descriptor :
                      Jj_campaign_action.conditional_edge_descriptor) ->
                String.starts_with ~prefix:"branch:" descriptor.edge_label
                && String.starts_with ~prefix:"branch-selected:"
                     descriptor.edge_guard_identity)
              descriptors
         && List.for_all
              (fun mutation ->
                Jj_campaign_action.guarded_edge_projection_digest plan
                <> Jj_campaign_action.For_test
                     .guarded_edge_projection_digest_with_mutation
                       plan mutation)
              [ Jj_campaign_action.For_test.Drop_descriptor;
                Jj_campaign_action.For_test.Reorder_descriptors;
                Jj_campaign_action.For_test.Mismatch_identity ]);
  check "C32 whole conditional descriptor projection is request-bound"
    (match b_plan, completion with
     | Ok b, Ok c ->
         String.length (Jj_campaign_action.conditional_projection_digest b)
           = 64
         && String.length
              (Jj_campaign_action.conditional_projection_digest c) = 64
         && Jj_campaign_action.conditional_projection_digest b
            <> Jj_campaign_action.conditional_projection_digest c
     | _ -> false);
  check "C33 formal manifest binds tool model source and nonempty controls"
    (Jj_campaign_action.formal_manifest_tool formal_manifest
       = Jj_action_kind.Quint
     && Jj_id.Formal_model.to_string
          (Jj_campaign_action.formal_manifest_model formal_manifest)
        = String.make 64 'b'
     && Jj_id.Formal_source.to_string
          (Jj_campaign_action.formal_manifest_source formal_manifest)
        = String.make 64 'a'
     && Jj_campaign_action.formal_manifest_negative_controls formal_manifest
        = formal_negative_controls
     && List.map Jj_action_kind.formal_case_key
          (Jj_campaign_action.formal_manifest_cases formal_manifest)
        = [ "positive"; "negative-control:mutant.drop-readback";
            "negative-control:mutant.accept-divergence" ]
     && String.length
          (Jj_campaign_action.formal_manifest_digest formal_manifest) = 64);
  check "C34 formal declarations are exact request-manifest occurrences"
    (action_keys formal_occurrences
     = [ "auxiliary:acquire-clock";
         "auxiliary:observe-external-resource";
         "formal-process:quint:positive";
         "formal-process:quint:negative-control:mutant.drop-readback";
         "formal-process:quint:negative-control:mutant.accept-divergence" ]
     && List.for_all
          (fun occurrence ->
            String.starts_with ~prefix:"formal:"
              (Jj_campaign_action.occurrence_phase occurrence))
          formal_occurrences);
  let formal_consumptions =
    Jj_campaign_action.standalone_approval_consumptions formal_request
  in
  check "C35 formal work inserts one nonce-free parent-bound approval consume"
    (List.map Jj_campaign_action.approval_consume_parent_ordinal
       formal_consumptions = [ 2; 3; 4 ]
     && List.map Jj_campaign_action.approval_consume_parent_occurrence_id
          formal_consumptions
        = List.map Jj_campaign_action.occurrence_id
            (List.filter
               (fun occurrence ->
                 match Jj_campaign_action.occurrence_action occurrence with
                 | Jj_action_kind.Formal_process _ -> true
                 | _ -> false)
               formal_occurrences)
     && List.for_all
          (fun consume ->
            Jj_campaign_action.approval_consume_action consume
              = Jj_action_kind.Consume_approval_nonce
            && String.length
                 (Jj_campaign_action.approval_consume_id consume) = 72)
          formal_consumptions);
  check "C36 formal manifests reject empty duplicate and unbounded controls"
    (Result.is_error
       (Jj_campaign_action.formal_manifest ~tool:Jj_action_kind.Quint
          ~model:(formal_model (String.make 64 'b'))
          ~source:(formal_source (String.make 64 'a')) ~negative_controls:[])
     && Result.is_error
          (Jj_campaign_action.formal_manifest ~tool:Jj_action_kind.Quint
             ~model:(formal_model (String.make 64 'b'))
             ~source:(formal_source (String.make 64 'a'))
             ~negative_controls:
               [ negative_control "mutant.same";
                 negative_control "mutant.same" ])
     && Result.is_error
          (Jj_campaign_action.formal_manifest ~tool:Jj_action_kind.Quint
             ~model:(formal_model (String.make 64 'b'))
             ~source:(formal_source (String.make 64 'a'))
             ~negative_controls:
               (List.init 1024 (fun ordinal ->
                  negative_control ("mutant." ^ string_of_int ordinal)))));
  check "C37 source identity binds formal manifest and consume join schemas"
    (Jj_campaign_action.source_digest
       <> Jj_campaign_action.For_test.source_digest_with_mutation
            Jj_campaign_action.For_test.Drop_formal_manifest_schema
     && Jj_campaign_action.source_digest
        <> Jj_campaign_action.For_test.source_digest_with_mutation
             Jj_campaign_action.For_test.Drop_formal_consume_schema);
  check "C38 formal projection identity binds every concrete approval consume"
    (Jj_campaign_action.standalone_projection_digest formal_request
       <> Jj_campaign_action.For_test
            .standalone_projection_digest_without_approval_consumptions
              formal_request
     && Jj_campaign_action.standalone_projection_digest release
        = Jj_campaign_action.For_test
            .standalone_projection_digest_without_approval_consumptions
              release);
  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 38 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_campaign_action"
    ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vcs ]);
  exit (Suite_telemetry.exit_code self)
