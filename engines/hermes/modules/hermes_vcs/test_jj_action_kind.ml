let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let auxiliary_keys =
  [ "acquire-clock"; "observe-external-resource";
    "observe-repository-source"; "observe-release-bundle";
    "consume-approval-nonce"; "acquire-writer-lease";
    "renew-writer-lease"; "release-writer-lease"; "observe-tree";
    "observe-object"; "acquire-network-scope"; "release-network-scope";
    "acquire-credential-lease"; "release-credential-lease";
    "materialize-candidate"; "write-partition"; "restore-partition";
    "restore-sealed-record-preimage"; "write-sealed-record-candidate";
    "remove-disposable-scope"; "stage-recovery-set";
    "reconcile-recovery-set"; "cleanup-recovery-set";
    "verify-candidate-tree"; "execute-jj-process";
    "readback-jj-state"; "reserve-completion-receipt";
    "finalize-completion-receipt"; "execute-formal-oracle" ]

let candidate_keys =
  [ "toolchain-check"; "jj-reverse-cone"; "jj-live-campaign";
    "jj-formal-receipt-validation"; "jj-precompletion-readback" ]

let formal_keys = [ "gospel"; "z3"; "rocq"; "iris"; "quint" ]

let get = function
  | Ok value -> value
  | Error error -> failwith (Jj_error.to_string error)

let formal_source =
  get (Jj_id.Formal_source.make (String.make 64 'a'))

let formal_model =
  get (Jj_id.Formal_model.make (String.make 64 'b'))

let negative_control =
  get (Jj_id.Negative_control.make "mutant.exact-readback")

let formal_case_schema =
  [ "positive"; "negative-control:<bounded-id>" ]

let () =
  check "A1 exact ordered 29-role auxiliary denominator"
    (List.map Jj_action_kind.auxiliary_role_key
       Jj_action_kind.auxiliary_roles = auxiliary_keys);
  check "A2 auxiliary role identities are unique"
    (List.length auxiliary_keys = 29
     && List.length auxiliary_keys
        = List.length (List.sort_uniq String.compare auxiliary_keys));
  check "A3 exact ordered five-step candidate denominator"
    (List.map Jj_action_kind.candidate_step_key
       Jj_action_kind.candidate_steps = candidate_keys);
  check "A4 exact ordered five-tool formal denominator"
    (List.map Jj_action_kind.formal_tool_key
       Jj_action_kind.formal_tools = formal_keys
     && Jj_id.Formal_source.to_string formal_source = String.make 64 'a'
     && Jj_id.Formal_model.to_string formal_model = String.make 64 'b'
     && Result.is_error
          (Jj_id.Formal_source.make (String.make 63 'a'))
     && Result.is_error
          (Jj_id.Formal_model.make (String.make 64 'A'))
     && Result.is_error
          (Jj_id.Negative_control.make (String.make 129 'a')));
  check "A5 frontier actions are a separate exact two-row denominator"
    (List.map Jj_action_kind.frontier_action_key
       Jj_action_kind.frontier_actions
     = [ "activate-source-recovery-branch";
         "set-activity-frontier:reconciled-terminal" ]
     && not
          (List.exists
             (fun key -> List.mem key auxiliary_keys)
             [ "activate-source-recovery-branch";
               "set-activity-frontier:reconciled-terminal" ]));
  check "A6 the closed action sum preserves each constructor family"
    (Jj_action_kind.action_key
       (Jj_action_kind.Jujutsu_operation Jj_operation.Operation_restore)
       = "jujutsu:operation-restore"
     && Jj_action_kind.action_key
          (Jj_action_kind.Auxiliary Jj_action_kind.Restore_partition)
        = "auxiliary:restore-partition"
     && Jj_action_kind.action_key
          (Jj_action_kind.Candidate_process Jj_action_kind.Jj_live_campaign)
        = "candidate-process:jj-live-campaign"
     && Jj_action_kind.action_key
          (Jj_action_kind.Formal_process
             (Jj_action_kind.formal_process ~tool:Jj_action_kind.Quint
                ~case:Jj_action_kind.Positive))
        = "formal-process:quint:positive"
     && Jj_action_kind.action_key
          (Jj_action_kind.Formal_process
             (Jj_action_kind.formal_process ~tool:Jj_action_kind.Quint
                ~case:(Jj_action_kind.Negative_control negative_control)))
        = "formal-process:quint:negative-control:mutant.exact-readback"
     && Jj_action_kind.action_key
          (Jj_action_kind.Frontier_action
             (Jj_action_kind.Set_activity_frontier
                Jj_action_kind.Reconciled_terminal))
        = "frontier:set-activity-frontier:reconciled-terminal");
  check "A7 source digest covers order and every finite denominator"
    (String.length Jj_action_kind.source_digest = 64
     && Jj_action_kind.source_digest
        <> Jj_action_kind.For_test.digest_denominators
             ~auxiliary_roles:(List.rev Jj_action_kind.auxiliary_roles)
             ~candidate_steps:Jj_action_kind.candidate_steps
             ~formal_tools:Jj_action_kind.formal_tools
             ~formal_case_schema
             ~frontier_actions:Jj_action_kind.frontier_actions
     && Jj_action_kind.source_digest
        <> Jj_action_kind.For_test.digest_denominators
             ~auxiliary_roles:Jj_action_kind.auxiliary_roles
             ~candidate_steps:(List.rev Jj_action_kind.candidate_steps)
             ~formal_tools:Jj_action_kind.formal_tools
             ~formal_case_schema
             ~frontier_actions:Jj_action_kind.frontier_actions
     && Jj_action_kind.source_digest
        <> Jj_action_kind.For_test.digest_denominators
             ~auxiliary_roles:Jj_action_kind.auxiliary_roles
             ~candidate_steps:Jj_action_kind.candidate_steps
             ~formal_tools:Jj_action_kind.formal_tools
             ~formal_case_schema:(List.rev formal_case_schema)
             ~frontier_actions:Jj_action_kind.frontier_actions);
  List.iter (fun name -> Printf.printf "FAILED: %s\n" name)
    (List.rev !failures);
  let failed = List.length !failures in
  let passed = 7 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_action_kind"
    ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vcs ]);
  exit (Suite_telemetry.exit_code self)
