open Run_jj_runtime_core

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin incr failed; Printf.printf "FAILED: %s\n" name end

let unavailable code = function
  | Error diagnostic ->
      diagnostic_code diagnostic = code
      && diagnostic_coordinate diagnostic = "L3/Orient/run-jj-runtime-core"
  | Ok _ -> false

let get = function Ok value -> value | Error _ -> failwith "pure subset refused"

let count_slot slot rows =
  List.fold_left
    (fun count (_, observed) -> if String.equal observed slot then count + 1 else count)
    0 rows

let () =
  check "T9C01 runtime core exports only its nominal manifest declaration"
    (Jj_runtime_manifest.declaration_key runtime_core_declaration = "runtime.core"
     && String.length
          (Jj_runtime_manifest.declaration_digest runtime_core_declaration) = 64);
  check "T9C02 live preparation remains exact implemented-unavailable"
    (live_preparation_posture = `Implemented_unavailable
     && unavailable Live_process_source_unfrozen
          (live_prerequisite_status Frozen_process_source_authority)
     && unavailable Process_registry_current_unavailable
          (live_prerequisite_status Process_registry_current_carrier)
     && unavailable Recovery_only_current_unavailable
          (live_prerequisite_status Recovery_only_current_receipt)
     && unavailable Release_terminal_cleanup_denominator_unavailable
          (live_prerequisite_status Release_terminal_cleanup_denominator));
  let ids = For_test.process_request_ids in
  let slots = For_test.process_request_slots in
  check "T9C03 private process schema is the exact unique 44-request denominator"
    (List.length ids = 44
     && List.length ids = List.length (List.sort_uniq String.compare ids));
  check "T9C04 requests map exactly 34/5/5 to the three nominal process slots"
    (For_test.manifest_process_slot_ids
       = [ "process.jujutsu"; "process.candidate"; "process.formal" ]
     && count_slot "process.jujutsu" slots = 34
     && count_slot "process.candidate" slots = 5
     && count_slot "process.formal" slots = 5);
  let production = get (validate_subset Production) in
  let candidate = get (validate_subset Candidate) in
  let formal = get (validate_subset Formal) in
  check "T9C05 phantom profiles retain exact pure nonauthorizing subsets"
    (subset_profile_id production = "production"
     && subset_count production = 34
     && subset_profile_id candidate = "candidate" && subset_count candidate = 5
     && subset_profile_id formal = "formal" && subset_count formal = 5
     && List.for_all
          (fun digest -> String.length digest = 64)
          [ subset_digest production; subset_digest candidate;
            subset_digest formal ]);
  check "T9C06 Recovery_only and Release refuse exact missing prerequisites"
    (unavailable Recovery_only_current_unavailable
       (validate_subset Recovery_only)
     && unavailable Release_terminal_cleanup_denominator_unavailable
       (validate_subset Release));
  let mutations =
    [ For_test.Drop_jujutsu_request; For_test.Drop_candidate_request;
      For_test.Drop_formal_request; For_test.Duplicate_request;
      For_test.Swap_process_slot; For_test.Drop_manifest_process_slot;
      For_test.Add_argv_field; For_test.Add_executable_field;
      For_test.Add_cwd_field; For_test.Add_environment_field;
      For_test.Add_path_field; For_test.Permit_live_preparation;
      For_test.Invent_process_registry_current;
      For_test.Guess_release_terminal_cleanup;
      For_test.Add_current_constructor; For_test.Add_activation_constructor ]
  in
  check "T9C07 source identity rejects denominator authority and escape mutants"
    (String.length source_digest = 64
     && String.length For_test.process_schema_digest = 64
     && List.for_all
          (fun mutation ->
            source_digest <> For_test.source_digest_with_mutation mutation)
          mutations);
  check "T9C08 profile manifest is closed and unavailable profiles stay inert"
    (List.map
       (fun (Profile profile) -> profile_id profile)
       profiles
     = [ "production"; "candidate"; "formal"; "recovery-only"; "release" ]);
  Printf.printf "run_jj_operator_runtime pure spine: %d passed, %d failed\n"
    !passed !failed;
  let telemetry =
    Suite_telemetry.observe ~suite:"test_run_jj_operator_runtime"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit telemetry ~targets:[ Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code telemetry)
