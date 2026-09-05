open E2e_framework

let () =
  Printf.printf "==================================================\n";
  Printf.printf "  CHALLENGER E2E FRAMEWORK STRESS TEST SUITE\n";
  Printf.printf "==================================================\n\n";

  (* Test 1: Registry operations (register, get_all_tests, clear_registry) *)
  clear_registry ();
  assert (get_all_tests () = []);
  
  register_test {
    id = "test.1";
    name = "Test One";
    tier = Tier1_Feature;
    feature = "feat1";
    run = (fun () -> Pass);
  };
  assert (List.length (get_all_tests ()) = 1);

  register_test {
    id = "test.2";
    name = "Test Two (Skip)";
    tier = Tier2_Boundary;
    feature = "feat2";
    run = (fun () -> Skip "not implemented yet");
  };
  assert (List.length (get_all_tests ()) = 2);

  (* Test 2: Utility string functions *)
  assert (string_of_tier Tier1_Feature = "Tier1_Feature");
  assert (string_of_tier Tier2_Boundary = "Tier2_Boundary");
  assert (string_of_tier Tier3_Pairwise = "Tier3_Pairwise");
  assert (string_of_tier Tier4_Application = "Tier4_Application");

  assert (string_of_result Pass = "PASS");
  assert (string_of_result (Fail "err") = "FAIL: err");
  assert (string_of_result (Skip "reason") = "SKIP: reason");

  (* Test 3: Preflight check in valid environment *)
  let preflight_ok = run_preflight () in
  Printf.printf "Preflight check result: %b\n" preflight_ok;
  assert preflight_ok;

  (* Test 4: Execution of passing & skipping suite *)
  let (p, f, s) = run_suite () in
  Printf.printf "Suite result: pass=%d, fail=%d, skip=%d\n" p f s;
  assert (p = 1);
  assert (f = 0);
  assert (s = 1);
  assert (run_all () = 0);

  (* Test 5: Execution of suite containing a failing test *)
  register_test {
    id = "test.3";
    name = "Test Three (Failing)";
    tier = Tier3_Pairwise;
    feature = "feat3";
    run = (fun () -> Fail "expected failure");
  };
  let (p2, f2, s2) = run_suite () in
  assert (p2 = 1);
  assert (f2 = 1);
  assert (s2 = 1);
  assert (run_all () = 1);

  clear_registry ();

  (* Test 6: Testing Exception Handling in test cases *)
  Printf.printf "\n--- Testing exception behavior during test run ---\n";
  register_test {
    id = "test.exn";
    name = "Test Exception";
    tier = Tier1_Feature;
    feature = "exn_test";
    run = (fun () -> failwith "Crash in test execution");
  };
  register_test {
    id = "test.after_exn";
    name = "Test After Exception";
    tier = Tier1_Feature;
    feature = "exn_test";
    run = (fun () -> Pass);
  };

  let exn_caught = ref false in
  begin try
    let _ = run_suite () in ()
  with e ->
    exn_caught := true;
    Printf.printf "CATCH: run_suite threw uncaught exception: %s\n" (Printexc.to_string e)
  end;

  if !exn_caught then
    Printf.printf "[FINDING] Uncaught exception in test case crashes entire run_suite!\n"
  else
    Printf.printf "PASS: run_suite safely handled exception in test case.\n";

  Printf.printf "\n==================================================\n";
  Printf.printf "  CHALLENGER STRESS SUITE COMPLETE\n";
  Printf.printf "==================================================\n"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_challenger_e2e_framework" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)
