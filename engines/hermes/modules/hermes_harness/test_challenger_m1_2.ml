open Turn_budget
open Message_hygiene

let member name = function `Assoc fields -> List.assoc_opt name fields | _ -> None

let test_turn_budget_adversarial () =
  print_endline "[CHALLENGER] Testing Turn_budget edge cases...";
  (* 1. Zero cap *)
  let zero = create 0 in
  assert (zero.maximum = 0);
  assert (zero.consumed = 0);
  assert (used zero = 0);
  assert (remaining zero = 0);
  let zero_consumed = consume zero in
  assert (not zero_consumed.allowed);
  assert (zero_consumed.budget = zero);
  assert (used zero_consumed.budget = 0);
  assert (remaining zero_consumed.budget = 0);
  let zero_refunded = refund zero in
  assert (zero_refunded = zero);

  (* 2. Negative cap *)
  let neg = create (-10) in
  assert (neg.maximum = -10);
  assert (neg.consumed = 0);
  assert (used neg = 0);
  assert (remaining neg = 0);
  let neg_consumed = consume neg in
  assert (not neg_consumed.allowed);
  assert (neg_consumed.budget = neg);
  assert (used neg_consumed.budget = 0);
  assert (remaining neg_consumed.budget = 0);
  let neg_refunded = refund neg in
  assert (neg_refunded = neg);

  (* 3. Double/multi refunds & underflow protection *)
  let b = create 2 in
  assert (used b = 0);
  let b1 = (consume b).budget in
  assert (used b1 = 1);
  let b2 = refund b1 in
  assert (used b2 = 0);
  assert (remaining b2 = 2);
  let b3 = refund b2 in
  assert (used b3 = 0);
  assert (remaining b3 = 2);
  let b4 = refund b3 in
  assert (used b4 = 0);
  assert (remaining b4 = 2);

  (* 4. Consumption beyond cap *)
  let b_cap1 = create 1 in
  let r1 = consume b_cap1 in
  assert (r1.allowed);
  assert (used r1.budget = 1);
  assert (remaining r1.budget = 0);
  let r2 = consume r1.budget in
  assert (not r2.allowed);
  assert (used r2.budget = 1);
  assert (remaining r2.budget = 0);
  let r3 = consume r2.budget in
  assert (not r3.allowed);
  assert (used r3.budget = 1);
  let r4 = consume r3.budget in
  assert (not r4.allowed);
  assert (used r4.budget = 1);

  (* 5. Remaining calculation on arbitrary budget values *)
  assert (remaining { maximum = 10; consumed = 0 } = 10);
  assert (remaining { maximum = 10; consumed = 4 } = 6);
  assert (remaining { maximum = 10; consumed = 10 } = 0);
  assert (remaining { maximum = 10; consumed = 15 } = 0);
  assert (remaining { maximum = -5; consumed = 0 } = 0);
  assert (remaining { maximum = -5; consumed = 5 } = 0);
  print_endline "[CHALLENGER] Turn_budget edge cases: PASS"

let test_message_hygiene_adversarial () =
  print_endline "[CHALLENGER] Testing Message_hygiene edge cases...";
  (* 1. Invalid surrogate UTF-8 byte sequences *)
  let test_strings = [
    "";
    "plain ascii 123 !@#$";
    "\237\159\191"; (* U+D7FF - valid UTF-8, byte 2 = 0x9F *)
    "\238\160\128"; (* U+E000 - valid UTF-8, byte 1 = 0xEE *)
    "\237\160\128"; (* U+D800 - surrogate *)
    "\237\163\191"; (* U+D8FF - surrogate *)
    "\237\191\191"; (* U+DFFF - surrogate *)
    "Prefix\237\160\128Middle\237\191\191Suffix";
    "\237\160\128\237\191\191"; (* two adjacent surrogates *)
    "abc\237"; (* truncated at 1 byte *)
    "abc\237\160"; (* truncated at 2 bytes *)
    "abc\237\160\000"; (* 3rd byte not in 0x80..0xBF *)
  ] in

  List.iter (fun s ->
    let cleaned = replace_surrogate_utf8 s in
    let idempotency = replace_surrogate_utf8 cleaned in
    assert (cleaned = idempotency)
  ) test_strings;

  assert (replace_surrogate_utf8 "\237\160\128" = "\239\191\189");
  assert (replace_surrogate_utf8 "\237\191\191" = "\239\191\189");
  assert (replace_surrogate_utf8 "\237\160\128\237\191\191" = "\239\191\189\239\191\189");
  assert (replace_surrogate_utf8 "abc\237" = "abc\237");
  assert (replace_surrogate_utf8 "abc\237\160" = "abc\237\160");
  assert (replace_surrogate_utf8 "\237\159\191" = "\237\159\191");

  (* 2. Non-object JSON values *)
  assert (sanitize_message ~model_id:"gpt-4o" (`String "str\237\160\128") = `String "str\239\191\189");
  assert (sanitize_message ~model_id:"gpt-4o" (`Int 42) = `Int 42);
  assert (sanitize_message ~model_id:"gpt-4o" (`Float 3.14) = `Float 3.14);
  assert (sanitize_message ~model_id:"gpt-4o" (`Bool false) = `Bool false);
  assert (sanitize_message ~model_id:"gpt-4o" `Null = `Null);
  assert (sanitize_message ~model_id:"gpt-4o" (`List [`String "a\237\160\128"]) = `List [`String "a\239\191\189"]);

  assert (sanitize_tool_call ~keep_thought_signature:false (`String "tc\237\160\128") = `String "tc\239\191\189");
  assert (sanitize_tool_call ~keep_thought_signature:true (`Int 99) = `Int 99);

  let bad_tc_msg = `Assoc [ ("tool_calls", `Int 123) ] in
  assert (sanitize_message ~model_id:"gpt-4o" bad_tc_msg = `Assoc [ ("tool_calls", `Int 123) ]);

  (* 3. Gemma & Uppercase model strings *)
  assert (model_consumes_thought_signature "google/gemma-2-9b");
  assert (model_consumes_thought_signature "google/gemma-2-27b-it");
  assert (model_consumes_thought_signature "gemma-7b");
  assert (model_consumes_thought_signature "GEMMA-7B-IT");
  assert (model_consumes_thought_signature "GOOGLE/GEMINI-2.5");
  assert (model_consumes_thought_signature "gemini-pro");
  assert (not (model_consumes_thought_signature "openai/gpt-4o"));
  assert (not (model_consumes_thought_signature "OPENAI/GPT-4O"));
  assert (not (model_consumes_thought_signature "anthropic/claude-3-5-sonnet"));
  assert (not (model_consumes_thought_signature ""));

  (* 4. Codex reasoning / message items stripping *)
  let msg_with_codex =
    `Assoc [
      ("role", `String "assistant");
      ("content", `String "main content");
      ("codex_reasoning_items", `List [`String "r1"; `String "r2"]);
      ("codex_message_items", `List [`String "m1"]);
      ("tool_name", `String "old_tool");
      ("_internal_flag", `Bool true);
    ]
  in
  let sanitized_codex = sanitize_message ~model_id:"openai/gpt-4o" msg_with_codex in
  assert (member "codex_reasoning_items" sanitized_codex = None);
  assert (member "codex_message_items" sanitized_codex = None);
  assert (member "tool_name" sanitized_codex = None);
  assert (member "_internal_flag" sanitized_codex = None);
  assert (member "role" sanitized_codex = Some (`String "assistant"));
  assert (member "content" sanitized_codex = Some (`String "main content"));

  (* 5. Tool call extra content filtering *)
  let tool_call_data =
    `Assoc [
      ("id", `String "call_123");
      ("call_id", `String "internal_call_id");
      ("response_item_id", `String "item_456");
      ("type", `String "function");
      ("extra_content", `Assoc [ ("thought_signature", `String "sig\237\160\128") ]);
    ]
  in
  (* Standard model (GPT-4o) *)
  let tc_std = sanitize_tool_call ~keep_thought_signature:false tool_call_data in
  assert (member "call_id" tc_std = None);
  assert (member "response_item_id" tc_std = None);
  assert (member "extra_content" tc_std = None);
  assert (member "id" tc_std = Some (`String "call_123"));
  assert (member "type" tc_std = Some (`String "function"));

  (* Gemma model *)
  let tc_gemma = sanitize_tool_call ~keep_thought_signature:true tool_call_data in
  assert (member "call_id" tc_gemma = None);
  assert (member "response_item_id" tc_gemma = None);
  assert (member "id" tc_gemma = Some (`String "call_123"));
  assert (member "type" tc_gemma = Some (`String "function"));
  let extra = match member "extra_content" tc_gemma with Some e -> e | None -> failwith "missing extra_content" in
  assert (member "thought_signature" extra = Some (`String "sig\239\191\189"));

  print_endline "[CHALLENGER] Message_hygiene edge cases: PASS"

let () =
  print_endline "=== Starting Challenger 2 M1 Stress Tests ===";
  test_turn_budget_adversarial ();
  test_message_hygiene_adversarial ();
  print_endline "=== All Challenger 2 M1 Stress Tests PASSED Cleanly ==="

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_challenger_m1_2" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)
