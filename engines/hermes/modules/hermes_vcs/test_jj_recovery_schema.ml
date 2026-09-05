let failures = ref []
let check name condition = if not condition then failures := name :: !failures

let actions steps = List.map Jj_recovery_schema.recovery_step_action steps
let auxiliary role = Jj_action_kind.Auxiliary role
let operation value = Jj_action_kind.Jujutsu_operation value
let frontier value = Jj_action_kind.Frontier_action value

let activated = frontier Jj_action_kind.Activate_source_recovery_branch
let terminal =
  frontier
    (Jj_action_kind.Set_activity_frontier Jj_action_kind.Reconciled_terminal)

let find_b disposition schema =
  List.find_opt
    (fun branch -> Jj_recovery_schema.b_disposition branch = disposition)
    (Jj_recovery_schema.b_branches schema)

let find_record disposition schema =
  List.find_opt
    (fun branch ->
      Jj_recovery_schema.completion_record_disposition branch = disposition)
    (Jj_recovery_schema.completion_record_branches schema)

let () =
  check "R1 partial prefixes are positive bounded and genuinely partial"
    (Result.is_error (Jj_recovery_schema.partial_prefix ~completed:0 ~total:3)
     && Result.is_error
          (Jj_recovery_schema.partial_prefix ~completed:3 ~total:3)
     && Result.is_error
          (Jj_recovery_schema.partial_prefix ~completed:1 ~total:1025)
     && match Jj_recovery_schema.partial_prefix ~completed:2 ~total:3 with
        | Ok prefix ->
            Jj_recovery_schema.partial_prefix_completed prefix = 2
            && Jj_recovery_schema.partial_prefix_total prefix = 3
        | Error _ -> false);

  let before =
    Jj_recovery_schema.schema
      (Jj_recovery_schema.B_success
         (Jj_recovery_schema.Before_engine, Jj_recovery_schema.In_process))
  in
  check "R2 request families are disjoint and before-engine invents no effect"
    (Jj_recovery_schema.family before = Jj_recovery_schema.B_family
     && List.map Jj_recovery_schema.b_disposition
          (Jj_recovery_schema.b_branches before)
        = [ Jj_recovery_schema.No_source_effect;
            Jj_recovery_schema.Diverged ]
     && Jj_recovery_schema.completion_record_branches before = []);

  let posture cut =
    Jj_recovery_schema.lease_posture
      (Jj_recovery_schema.B_success (cut, Jj_recovery_schema.In_process))
  in
  check "R3 lease posture is derived from the typed prefix"
    (posture
       (Jj_recovery_schema.After_consume
          Jj_recovery_schema.B_acquire_writer_lease)
       = Jj_recovery_schema.Not_acquired
     && posture
          (Jj_recovery_schema.After_action
             Jj_recovery_schema.B_acquire_writer_lease)
        = Jj_recovery_schema.Held
     && posture
          (Jj_recovery_schema.After_action
             Jj_recovery_schema.B_release_writer_lease)
        = Jj_recovery_schema.Released);

  let after_bookmark =
    Jj_recovery_schema.schema
      (Jj_recovery_schema.B_success
         (Jj_recovery_schema.After_action Jj_recovery_schema.B_bookmark_set,
          Jj_recovery_schema.In_process))
  in
  check "R4 no-source-effect is impossible after source target entry"
    (find_b Jj_recovery_schema.No_source_effect after_bookmark = None
     && Option.is_some
          (find_b Jj_recovery_schema.Restore_operation_only after_bookmark));

  let partial =
    match Jj_recovery_schema.partial_prefix ~completed:1 ~total:3 with
    | Ok prefix -> prefix
    | Error _ -> failwith "valid partial prefix refused"
  in
  let physical =
    Jj_recovery_schema.schema
      (Jj_recovery_schema.B_success
         (Jj_recovery_schema.After_action
            (Jj_recovery_schema.B_write_partition_partial partial),
          Jj_recovery_schema.In_process))
  in
  let physical_steps =
    match
      find_b Jj_recovery_schema.Restore_operation_and_partition physical
    with
    | None -> []
    | Some branch -> actions (Jj_recovery_schema.b_steps branch)
  in
  check "R5 physical recovery activates renews and restores operation before bytes"
    (physical_steps
     = [ activated; auxiliary Jj_action_kind.Renew_writer_lease;
         auxiliary Jj_action_kind.Reconcile_recovery_set;
         operation Jj_operation.Operation_restore;
         auxiliary Jj_action_kind.Restore_partition;
         auxiliary Jj_action_kind.Readback_jj_state;
         auxiliary Jj_action_kind.Observe_tree;
         auxiliary Jj_action_kind.Observe_repository_source; terminal;
         auxiliary Jj_action_kind.Cleanup_recovery_set;
         auxiliary Jj_action_kind.Release_writer_lease ]);

  let restarted =
    Jj_recovery_schema.schema
      (Jj_recovery_schema.B_success
         (Jj_recovery_schema.After_action
            (Jj_recovery_schema.B_write_partition_partial partial),
          Jj_recovery_schema.Restarted))
  in
  let restarted_steps =
    match
      find_b Jj_recovery_schema.Restore_operation_and_partition restarted
    with
    | None -> []
    | Some branch -> actions (Jj_recovery_schema.b_steps branch)
  in
  check "R6 restarted recovery reacquires and never repeats activation"
    (match restarted_steps with
     | first :: rest ->
         first = auxiliary Jj_action_kind.Acquire_writer_lease
         && not (List.mem activated rest)
     | [] -> false);

  let diverged_in_process =
    match find_b Jj_recovery_schema.Diverged physical with
    | None -> []
    | Some branch -> actions (Jj_recovery_schema.b_steps branch)
  in
  let diverged_restarted =
    match find_b Jj_recovery_schema.Diverged restarted with
    | None -> [ activated ]
    | Some branch -> actions (Jj_recovery_schema.b_steps branch)
  in
  check "R7 divergence has no restore cleanup release or source effect"
    (diverged_in_process = [ activated ]
     && diverged_restarted
        = [ auxiliary Jj_action_kind.Acquire_writer_lease ]);

  let forward =
    Jj_recovery_schema.schema
      (Jj_recovery_schema.B_success
         (Jj_recovery_schema.After_action
            Jj_recovery_schema.B_working_copy_snapshot_2,
          Jj_recovery_schema.In_process))
  in
  check "R8 forward completion appears only after intended source actions"
    (Option.is_some
       (find_b Jj_recovery_schema.Forward_complete_exact forward)
     && find_b Jj_recovery_schema.Forward_complete_exact after_bookmark = None);

  let record workspace =
    Jj_recovery_schema.schema
      (Jj_recovery_schema.Completion_record
         (Jj_recovery_schema.Completion_after_action
            (Jj_recovery_schema.Record_write_candidate_partial partial),
          workspace, Jj_recovery_schema.In_process))
  in
  let record_actions workspace =
    match
      find_record Jj_recovery_schema.Restore_record_exact (record workspace)
    with
    | None -> []
    | Some branch ->
        actions (Jj_recovery_schema.completion_record_steps branch)
  in
  let existing_actions = record_actions Jj_recovery_schema.Existing in
  let new_actions = record_actions Jj_recovery_schema.Newly_allocated in
  check "R9 record recovery restores sealed preimages and never partitions"
    (List.mem
       (auxiliary Jj_action_kind.Restore_sealed_record_preimage)
       existing_actions
     && not
          (List.mem (auxiliary Jj_action_kind.Restore_partition)
             existing_actions));
  check "R10 newly allocated record recovery alone forgets and removes scope"
    (not (List.mem (operation Jj_operation.Workspace_forget) existing_actions)
     && List.mem (operation Jj_operation.Workspace_forget) new_actions
     && List.mem (auxiliary Jj_action_kind.Remove_disposable_scope) new_actions);

  check "R11 recovery-step ordinals encode exact list cardinality"
    (let ordinals =
       match
         find_b Jj_recovery_schema.Restore_operation_and_partition physical
       with
       | None -> []
       | Some branch ->
           List.map Jj_recovery_schema.recovery_step_ordinal
             (Jj_recovery_schema.b_steps branch)
     in
     ordinals = List.init (List.length ordinals) Fun.id);
  check "R12 schema digest is identity-free and order-sensitive"
    (String.length Jj_recovery_schema.source_digest = 64
     && Jj_recovery_schema.source_digest
        <> Jj_recovery_schema.For_test.digest_actions
             (List.rev physical_steps));
  let mutation_changes_authority mutation =
    Jj_recovery_schema.source_digest
    <> Jj_recovery_schema.For_test.source_digest_with_mutation mutation
  in
  check "R13 disposition mutation changes recovery authority digest"
    (mutation_changes_authority Jj_recovery_schema.For_test.Disposition);
  check "R14 action mutation changes recovery authority digest"
    (mutation_changes_authority Jj_recovery_schema.For_test.Action);
  check "R15 action-order mutation changes recovery authority digest"
    (mutation_changes_authority Jj_recovery_schema.For_test.Action_order);
  check "R16 cut mutation changes recovery authority digest"
    (mutation_changes_authority Jj_recovery_schema.For_test.Cut);
  check "R17 workspace mutation changes recovery authority digest"
    (mutation_changes_authority Jj_recovery_schema.For_test.Workspace);
  check "R18 mode mutation changes recovery authority digest"
    (mutation_changes_authority Jj_recovery_schema.For_test.Mode);

  List.iter (fun name -> Printf.printf "FAILED: %s\n" name)
    (List.rev !failures);
  let failed = List.length !failures in
  let passed = 18 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_recovery_schema"
    ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vcs ]);
  exit (Suite_telemetry.exit_code self)
