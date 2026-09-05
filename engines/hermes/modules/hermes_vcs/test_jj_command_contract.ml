let failures = ref []

let check name condition =
  if not condition then failures := name :: !failures

let () =
  check "C1 contract rows have the exact operation denominator and order"
    (List.map Jj_command_contract.operation Jj_command_contract.all = Jj_operation.all);
  check "C2 every row is blocked pending the Task 10A source freeze"
    (List.for_all
       (fun row -> Jj_command_contract.source_status row
                   = Jj_command_contract.Unfrozen_source_blocker)
       Jj_command_contract.all);
  check "C3 observation rows bind ignore-working-copy and operation context"
    (List.for_all
       (fun operation ->
          match Jj_command_contract.at_operation (Jj_command_contract.for_operation operation) with
          | Jj_command_contract.At_exact_operation_with_ignore_working_copy -> true
          | Jj_command_contract.Not_applicable -> operation = Jj_operation.Version)
       [ Jj_operation.Version; Jj_operation.Operation_head;
         Jj_operation.Status_at_operation; Jj_operation.Operation_log_at_operation;
         Jj_operation.Revision_log_at_operation;
         Jj_operation.Bookmark_list_at_operation;
         Jj_operation.Workspace_list_at_operation;
         Jj_operation.Remote_list_at_operation;
         Jj_operation.Diff_summary_at_operation;
         Jj_operation.Diff_stat_at_operation; Jj_operation.Diff_patch_at_operation;
         Jj_operation.File_show_at_operation; Jj_operation.Resolve_list_at_operation ]);
  check "C4 file-untrack has the closed current-ignore precondition"
    (Jj_command_contract.precondition
       (Jj_command_contract.for_operation Jj_operation.File_untrack)
     = Jj_command_contract.Requires_current_ignore_or_auto_track_exclusion);
  check "C5 remote operations require exact state and remote scope together"
    (List.for_all
       (fun operation ->
          Jj_command_contract.precondition
            (Jj_command_contract.for_operation operation)
          = Jj_command_contract.Requires_exact_before_state_and_remote_scope)
       [ Jj_operation.Git_fetch; Jj_operation.Git_push ]);
  List.iter (fun failure -> Printf.printf "FAILED: %s\n" failure) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 5 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_command_contract"
      ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_jj_protocol ]);
  exit (Suite_telemetry.exit_code self)
