(* Empirical Challenger Verification Suite for M3 (Tier 3 & Tier 4 E2E Test Suite) *)

open E2e_framework

let verify_test_registration () =
  print_endline "[Challenger M3] Step 1: Registering all test suites...";
  E2e_framework.register_test {
    id = "framework.sanity";
    name = "E2E Framework Preflight & Infrastructure Sanity Check";
    tier = E2e_framework.Tier1_Feature;
    feature = "e2e_framework";
    run = (fun () -> E2e_framework.Pass);
  };
  E2e_tier1_tests.register_all ();
  E2e_tier2_tests.register_all ();
  ignore (E2e_tier3_tests.register_all ());
  ignore (E2e_tier4_tests.register_all ());
  print_endline "[Challenger M3] All test suites registered successfully."

let verify_extended_qcheck_fuzzing () =
  print_endline "[Challenger M3] Step 2: Running extended QCheck property fuzzing (10,000 iterations)...";
  let open QCheck in
  let op_gen =
    Gen.oneof
      [
        Gen.map (fun max -> `Create max) Gen.nat_small;
        Gen.return `Consume;
        Gen.return `Refund;
      ]
  in
  let ops_gen = Gen.list_size (Gen.int_range 1 50) op_gen in
  let arbitrary_ops = make ops_gen in
  let prop ops =
    let init_b = Turn_budget.create 10 in
    let final_b =
      List.fold_left
        (fun b op ->
          match op with
          | `Create max -> Turn_budget.create max
          | `Consume -> (Turn_budget.consume b).budget
          | `Refund -> Turn_budget.refund b)
        init_b ops
    in
    let u = Turn_budget.used final_b in
    let r = Turn_budget.remaining final_b in
    u >= 0 && r >= 0
  in
  let qcheck_test = Test.make ~count:10000 ~name:"budget_invariants_extended" arbitrary_ops prop in
  match Test.check_exn qcheck_test with
  | () -> print_endline "[Challenger M3] Extended QCheck property fuzzing PASSED (10,000 iterations)."
  | exception e ->
      print_endline ("[Challenger M3] FATAL: Extended QCheck property fuzzing failed: " ^ Printexc.to_string e);
      exit 1

let verify_pairwise_edge_cases () =
  print_endline "[Challenger M3] Step 3: Verifying Pairwise Edge Cases (Message Hygiene + Prompt Assembly)...";
  let surrogate_str = "Instruction \237\160\128 with extra bytes \237\161\135" in
  let raw_msgs =
    [
      `Assoc [ ("role", `String "system"); ("content", `String surrogate_str) ];
      `Assoc
        [
          ("role", `String "user");
          ("content", `String "Hello world");
          ("_internal_id", `String "secret_999");
          ("codex_reasoning_items", `List [ `String "thought 1"; `String "thought 2" ]);
        ];
    ]
  in
  let sanitized = Message_hygiene.sanitize_messages ~model_id:"openai/gpt-5.4" raw_msgs in
  let assembled = Prompt_assembly.assemble ~model_id:"openai/gpt-5.4" ~messages:sanitized in
  (match assembled with
  | `Assoc fields -> (
      match List.assoc_opt "messages" fields with
      | Some (`List [ `Assoc sys_fields; `Assoc user_fields ]) ->
          let sys_role_ok = List.assoc_opt "role" sys_fields = Some (`String "developer") in
          let sys_content_ok =
            match List.assoc_opt "content" sys_fields with
            | Some (`String s) -> String.contains s '\239'
            | _ -> false
          in
          let user_clean = not (List.mem_assoc "_internal_id" user_fields) && not (List.mem_assoc "codex_reasoning_items" user_fields) in
          if sys_role_ok && sys_content_ok && user_clean then
            print_endline "[Challenger M3] Pairwise Hygiene + Prompt Assembly check PASSED."
          else (
            print_endline "[Challenger M3] FATAL: Pairwise Hygiene + Prompt Assembly validation failed.";
            exit 1)
      | _ ->
          print_endline "[Challenger M3] FATAL: Assembled messages list structure mismatch.";
          exit 1)
  | _ ->
      print_endline "[Challenger M3] FATAL: Assembled result is not JSON object.";
      exit 1)

let verify_multi_turn_exhaustion_recovery () =
  print_endline "[Challenger M3] Step 4: Verifying Multi-Turn Budget Exhaustion Recovery...";
  let b0 = Turn_budget.create 3 in
  let res1 = Turn_budget.consume b0 in
  let res2 = Turn_budget.consume res1.budget in
  let res3 = Turn_budget.consume res2.budget in
  let res4 = Turn_budget.consume res3.budget in
  if res1.allowed && res2.allowed && res3.allowed && not res4.allowed then (
    let b_refunded = Turn_budget.refund res3.budget in
    let res5 = Turn_budget.consume b_refunded in
    if res5.allowed && Turn_budget.remaining res5.budget = 0 then
      print_endline "[Challenger M3] Multi-Turn Budget Exhaustion Recovery check PASSED."
    else (
      print_endline "[Challenger M3] FATAL: Consume after single refund failed.";
      exit 1)
  ) else (
    print_endline "[Challenger M3] FATAL: Budget consumption sequence mismatch.";
    exit 1)

let () =
  print_endline "=== Starting Challenger M3 Verification Harness ===";
  verify_test_registration ();
  verify_extended_qcheck_fuzzing ();
  verify_pairwise_edge_cases ();
  verify_multi_turn_exhaustion_recovery ();
  print_endline "[Challenger M3] Step 5: Executing full E2E test suite...";
  let exit_code = E2e_framework.run_all () in
  if exit_code = 0 then
    print_endline "=== Challenger M3 Verification Harness COMPLETED SUCCESSFULLY ==="
  else print_endline "=== Challenger M3 Verification Harness FAILED ===";
  (* run_all is 0|1 by contract (e2e_framework.mli), so failed IS the code. *)
  let self =
    Suite_telemetry.observe ~suite:"test_challenger_m3_1" ~passed:(1 - exit_code)
      ~failed:exit_code ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)
