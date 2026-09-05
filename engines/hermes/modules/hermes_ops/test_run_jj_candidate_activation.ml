open Run_jj_candidate_activation

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.eprintf "FAILED: %s\n" name
  end

let pure_subset_is_exact = function
  | Ok subset ->
      Run_jj_runtime_core.subset_profile_id subset = "candidate"
      && Run_jj_runtime_core.subset_count subset = 5
      && String.length (Run_jj_runtime_core.subset_digest subset) = 64
  | Error _ -> false

let owner_unavailable_is_exact = function
  | Error diagnostics ->
      List.map diagnostic_prerequisite diagnostics = prerequisites
      && List.for_all
           (fun diagnostic ->
             diagnostic_coordinate diagnostic
             = "L3/Orient/run-jj-candidate-activation"
             && diagnostic_origin diagnostic = `Evidence
             && not (String.equal (diagnostic_message diagnostic) ""))
           diagnostics
  | Ok _ -> false

let () =
  check "J09A01 candidate activation owns its nominal runtime declaration"
    (Jj_runtime_manifest.declaration_key runtime_declaration
       = "activation.candidate"
     && Jj_runtime_manifest.declaration_digest runtime_declaration
        = Jj_runtime_manifest.declaration_digest
            Jj_runtime_manifest.activation_candidate);
  check "J09A02 candidate activation binds the exact five ordered steps"
    (accepted_steps = Jj_action_kind.candidate_steps
     && step_ids
        = [ "toolchain-check"; "jj-reverse-cone"; "jj-live-campaign";
            "jj-formal-receipt-validation";
            "jj-precompletion-readback" ]
     && pure_subset_is_exact (validated_subset ()));
  check "J09A03 candidate activation binds the exact read-only obligations"
    (obligation_ids
     = [ "exact-source"; "exact-configuration"; "approval-required";
         "resource-preflight-required"; "bridge-admission-required";
         "apply-once-receipt-required"; "readback-required" ]);
  check "J09A04 all sixteen live prerequisites fail closed in order"
    (prerequisites
     = [ Candidate_activation_owner_part_current;
         Runtime_manifest_current_carrier;
         Frozen_candidate_process_source_authority;
         Candidate_process_obligation_schema_current;
         Candidate_process_registry_current;
         Registered_candidate_executable_current;
         Candidate_configuration_current_carrier;
         Materialized_candidate_current_carrier;
         A1_candidate_plan_current_carrier;
         Candidate_suite_manifest_current_carrier;
         Approval_occurrence_capabilities_current;
         Receipt_bound_resource_envelope_current;
         Request_bound_candidate_step_current_carrier;
         Candidate_process_apply_once_current;
         Ordered_candidate_step_readback_current;
         Candidate_cleanup_eligibility_current ]
     && production_posture = `Implemented_unavailable
     && owner_unavailable_is_exact (create_owner_unavailable ()));
  let mutations =
    [ For_test.Drop_runtime_manifest_source;
      For_test.Drop_runtime_current_protocol_source;
      For_test.Drop_action_kind_source;
      For_test.Drop_process_protocol_source;
      For_test.Drop_campaign_action_source;
      For_test.Drop_dependability_process_protocol_source;
      For_test.Drop_dependability_process_source;
      For_test.Drop_runtime_core_source;
      For_test.Drop_candidate_target_source;
      For_test.Drop_topology_source;
      For_test.Drop_swarm_preparation_source;
      For_test.Drop_event_prefix_source;
      For_test.Drop_root_bootstrap_source;
      For_test.Drop_runtime_declaration;
      For_test.Substitute_runtime_declaration;
      For_test.Drop_candidate_step;
      For_test.Reorder_candidate_steps;
      For_test.Duplicate_candidate_step;
      For_test.Add_formal_step;
      For_test.Drop_candidate_obligation;
      For_test.Reorder_candidate_obligations;
      For_test.Add_writer_obligation;
      For_test.Drop_prerequisite;
      For_test.Reorder_prerequisites;
      For_test.Duplicate_prerequisite;
      For_test.Substitute_prerequisite;
      For_test.Permit_live_owner;
      For_test.Invent_runtime_manifest_current;
      For_test.Invent_process_registry_current;
      For_test.Permit_without_materialized_candidate;
      For_test.Permit_without_a1_plan;
      For_test.Permit_without_suite_manifest;
      For_test.Permit_without_approval;
      For_test.Permit_cleanup_before_readback;
      For_test.Add_raw_executable;
      For_test.Add_raw_argv;
      For_test.Add_raw_path;
      For_test.Add_environment;
      For_test.Expose_process;
      For_test.Add_callback;
      For_test.Serialize_capability;
      For_test.Add_current_constructor;
      For_test.Add_activation_dispatch ]
  in
  check "J09A05 source identity kills all lower authority and escape mutants"
    (String.length source_digest = 64
     && List.length mutations = 43
     && List.for_all
          (fun mutation ->
            not
              (String.equal source_digest
                 (For_test.source_digest_with_mutation mutation)))
          mutations);
  Printf.printf "run_jj_candidate_activation foundation: %d passed, %d failed\n"
    !passed !failed;
  let telemetry =
    Suite_telemetry.observe ~suite:"test_run_jj_candidate_activation"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit telemetry ~targets:[ Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code telemetry)
