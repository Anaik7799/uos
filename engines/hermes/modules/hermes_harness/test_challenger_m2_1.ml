(* Challenger 1 (M2 Tier 1 & Tier 2) Stress Test Suite *)

let fail_count = ref 0

let check cond msg =
  if not cond then (
    incr fail_count;
    Printf.printf "FAIL: %s\n" msg
  )

let test_context_engine_stress () =
  Printf.printf "[CHALLENGER] Stress-testing Context_engine...\n";
  (* Negative max_context_tokens *)
  let st_neg = Context_engine.create ~max_context_tokens:(-100) in
  check (st_neg.max_context_tokens = 0) "Context_engine.create -100 tokens should clamp to 0";
  check (st_neg.total_tokens = 0) "Context_engine initial tokens should be 0";

  (* Negative reference token count *)
  let ref_neg = { Context_engine.ref_id = "r_neg"; kind = "file"; uri = "uri"; content = "c"; token_count = -50 } in
  let st1 = Context_engine.add_reference st_neg ref_neg in
  check (st1.total_tokens = 0) "add_reference with negative token_count should clamp to 0";

  (* Duplicate ref_id update *)
  let r1 = { Context_engine.ref_id = "dup"; kind = "file"; uri = "u1"; content = "c1"; token_count = 100 } in
  let r2 = { Context_engine.ref_id = "dup"; kind = "file"; uri = "u2"; content = "c2"; token_count = 200 } in
  let st2 = Context_engine.add_reference (Context_engine.create ~max_context_tokens:1000) r1 in
  let st3 = Context_engine.add_reference st2 r2 in
  check (List.length st3.active_references = 1) "add_reference should deduplicate by ref_id";
  check (st3.total_tokens = 200) "add_reference replacement should update total_tokens to 200";

  (* Removal from empty & non-existent *)
  let st4 = Context_engine.remove_reference st3 ~ref_id:"non_existent" in
  check (st4.total_tokens = 200) "remove_reference non_existent should leave tokens intact";
  let st5 = Context_engine.remove_reference st4 ~ref_id:"dup" in
  check (st5.total_tokens = 0 && st5.active_references = []) "remove_reference should clear state";
  ()

let test_context_compression_stress () =
  Printf.printf "[CHALLENGER] Stress-testing Context_compression...\n";
  (* keep_last_n <= 0 *)
  let sys = `Assoc [ ("role", `String "system"); ("content", `String "Sys") ] in
  let u1 = `Assoc [ ("role", `String "user"); ("content", `String "U1") ] in
  let u2 = `Assoc [ ("role", `String "user"); ("content", `String "U2") ] in
  let res0 = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = 0 }) [ sys; u1; u2 ] in
  check (res0.compressed_messages = [ sys ]) "keep_last_n = 0 should preserve system message and drop rest";

  let res_neg = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = -5 }) [ sys; u1; u2 ] in
  check (res_neg.compressed_messages = [ sys ]) "keep_last_n = -5 should clamp to 0 and preserve system message";

  (* Empty message list *)
  let res_empty = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = 5 }) [] in
  check (res_empty.original_count = 0 && res_empty.compressed_count = 0) "compress_history [] should be empty";

  (* Summarize single non-system message fallback *)
  let res_sum1 = Context_compression.compress_history ~strategy:(Summarize_history { summary_prefix = "P:" }) [ u1 ] in
  check (res_sum1.compressed_count = 1 && res_sum1.tokens_saved = 0) "Summarizing 1 normal message should be no-op";
  ()

let test_turn_finalization_stress () =
  Printf.printf "[CHALLENGER] Stress-testing Turn_finalization...\n";
  (* Negative turns/tokens & empty turn_id *)
  let r = Turn_finalization.create_receipt ~turn_id:"" ~status:"ok" ~turns:(-10) ~tokens:(-500) ~final_output:None in
  check (r.turn_id = "unknown") "Empty turn_id should clamp to 'unknown'";
  check (r.turns_executed = 0) "Negative turns should clamp to 0";
  check (r.total_tokens_used = 0) "Negative tokens should clamp to 0";

  let summary = Turn_finalization.summarize r ~metadata:[ ("k1", `String "v1") ] in
  check (summary.receipt.turn_id = "unknown" && List.length summary.metadata = 1) "Summarize should retain metadata";
  ()

let test_conversation_loop_stress () =
  Printf.printf "[CHALLENGER] Stress-testing Conversation_loop...\n";
  (* Negative max_turns init *)
  let st0 = Conversation_loop.init_state ~model_id:"gpt-5" ~max_turns:(-3) in
  check (st0.budget.maximum = 0) "init_state with negative max_turns should clamp budget.maximum to 0";
  let st1, _ = Conversation_loop.step_turn st0 ~messages:[ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ] in
  check (st1.step = Conversation_loop.Interrupted) "step_turn with zero budget should transition to Interrupted";

  (* Step turn on empty message list *)
  let st_normal = Conversation_loop.init_state ~model_id:"gpt-5" ~max_turns:5 in
  let st_empty, _ = Conversation_loop.step_turn st_normal ~messages:[] in
  check (st_empty.step = Conversation_loop.Complete) "step_turn on [] should transition to Complete";

  (* Step turn on tool call *)
  let tool_msg = `Assoc [ ("role", `String "assistant"); ("tool_calls", `List [ `Assoc [ ("id", `String "1") ] ]) ] in
  let st_tool, _ = Conversation_loop.step_turn st_normal ~messages:[ tool_msg ] in
  check (st_tool.step = Conversation_loop.ToolCall) "step_turn on tool_calls should transition to ToolCall";
  ()

let test_prompt_assembly_stress () =
  Printf.printf "[CHALLENGER] Stress-testing Prompt_assembly...\n";
  (* Uppercase model string *)
  let sys = `Assoc [ ("role", `String "system"); ("content", `String "Sys") ] in
  let res_upper = Prompt_assembly.apply_developer_role ~model_id:"OPENAI/GPT-5.4" [ sys ] in
  check (res_upper = [ `Assoc [ ("role", `String "developer"); ("content", `String "Sys") ] ])
    "apply_developer_role should handle uppercase model ID";

  (* Non-zero index system message *)
  let user = `Assoc [ ("role", `String "user"); ("content", `String "Hi") ] in
  let res_indexed = Prompt_assembly.apply_developer_role ~model_id:"openai/gpt-5.4" [ user; sys ] in
  check (res_indexed = [ user; sys ]) "System message at non-zero index should NOT be converted to developer";
  ()

let () =
  Printf.printf "==================================================\n";
  Printf.printf "  CHALLENGER 1 (M2 TIER 1 & 2) EMPIRICAL SUITE\n";
  Printf.printf "==================================================\n";
  test_context_engine_stress ();
  test_context_compression_stress ();
  test_turn_finalization_stress ();
  test_conversation_loop_stress ();
  test_prompt_assembly_stress ();
  if !fail_count = 0 then (
    Printf.printf "==================================================\n";
    Printf.printf "  ALL EMPIRICAL CHALLENGER STRESS TESTS PASSED!\n";
    Printf.printf "==================================================\n"
  ) else (
    Printf.printf "==================================================\n";
    Printf.printf "  CHALLENGER STRESS TESTS FAILED: %d failures!\n" !fail_count;
    Printf.printf "==================================================\n"
  );
  let self =
    Suite_telemetry.observe ~suite:"test_challenger_m2_1"
      ~passed:(if !fail_count = 0 then 1 else 0) ~failed:!fail_count ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)
