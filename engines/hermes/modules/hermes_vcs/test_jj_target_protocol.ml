let failures = ref []
let check name condition = if not condition then failures := name :: !failures

let formal_process tool case =
  Jj_action_kind.formal_process ~tool ~case

let negative_control =
  match Jj_id.Negative_control.make "mutant.target-routing" with
  | Ok value -> value
  | Error _ -> failwith "negative-control fixture refused"

let all_actions =
  List.map (fun operation -> Jj_action_kind.Jujutsu_operation operation)
    Jj_operation.all
  @ List.map (fun role -> Jj_action_kind.Auxiliary role)
      Jj_action_kind.auxiliary_roles
  @ List.map (fun step -> Jj_action_kind.Candidate_process step)
      Jj_action_kind.candidate_steps
  @ List.map
      (fun tool ->
        Jj_action_kind.Formal_process
          (formal_process tool Jj_action_kind.Positive))
      Jj_action_kind.formal_tools
  @ List.map (fun action -> Jj_action_kind.Frontier_action action)
      Jj_action_kind.frontier_actions

let () =
  let open Jj_action_kind in
  let open Jj_target_protocol in
  check "T1 target denominator is closed and unique"
    (List.length all = 15
     && List.length (List.sort_uniq String.compare (List.map key all)) = 15);
  check "T2 every closed action has exactly one target"
    (List.length all_actions = 75
     && List.for_all (fun action -> List.mem (target action) all) all_actions
     && target
          (Formal_process
             (formal_process ~tool:Quint
                ~case:(Negative_control negative_control)))
        = Formal);
  check "T3 release and clock observations remain distinct targets"
    (target (Auxiliary Acquire_clock) = Clock
     && target (Auxiliary Observe_release_bundle) = Release);
  check "T4 recovery and frontier actions use their exact target classes"
    (target (Auxiliary Reconcile_recovery_set) = Transition
     && target (Frontier_action Activate_source_recovery_branch) = Transition
     && target (Frontier_action (Set_activity_frontier Reconciled_terminal))
        = Mutation_frontier);
  check "T5 process families cannot collapse into a generic target"
    (target (Jujutsu_operation Jj_operation.Version) = Jujutsu
     && target (Candidate_process Toolchain_check) = Candidate_verification
     && target
          (Formal_process (formal_process ~tool:Z3 ~case:Positive)) = Formal);
  check "T6 target authority digest is SHA-256 shaped"
    (String.length source_digest = 64);
  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 6 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_target_protocol"
    ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_jj_protocol ]);
  exit (Suite_telemetry.exit_code self)
