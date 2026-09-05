open Message_hygiene
open Turn_budget

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let test_turn_budget_zero_and_negative () =
  Printf.printf "[Turn_budget] Testing zero and negative caps...\n";
  (* Zero cap *)
  let tb_zero = create 0 in
  assert (tb_zero.maximum = 0);
  assert (used tb_zero = 0);
  assert (remaining tb_zero = 0);
  let res_zero = consume tb_zero in
  assert (not res_zero.allowed);
  assert (res_zero.budget.consumed = 0);
  assert (res_zero.budget.maximum = 0);
  assert (refund tb_zero = tb_zero);

  (* Negative cap *)
  let tb_neg = create (-10) in
  assert (tb_neg.maximum = -10);
  assert (used tb_neg = 0);
  assert (remaining tb_neg = 0); (* max 0 (-10 - 0) = 0 *)
  let res_neg = consume tb_neg in
  assert (not res_neg.allowed);
  assert (res_neg.budget = tb_neg);
  assert (refund tb_neg = tb_neg);
  Printf.printf "  => PASS\n"

let test_turn_budget_consumption_and_refunds () =
  Printf.printf "[Turn_budget] Testing consumption beyond cap and multiple refunds...\n";
  let cap2 = create 2 in
  assert (used cap2 = 0);
  assert (remaining cap2 = 2);

  let c1 = consume cap2 in
  assert (c1.allowed);
  assert (used c1.budget = 1);
  assert (remaining c1.budget = 1);

  let c2 = consume c1.budget in
  assert (c2.allowed);
  assert (used c2.budget = 2);
  assert (remaining c2.budget = 0);

  let c3 = consume c2.budget in
  assert (not c3.allowed);
  assert (used c3.budget = 2);
  assert (remaining c3.budget = 0);

  let c4 = consume c3.budget in
  assert (not c4.allowed);
  assert (used c4.budget = 2);
  assert (remaining c4.budget = 0);

  (* Multiple refunds *)
  let r1 = refund c4.budget in
  assert (used r1 = 1);
  assert (remaining r1 = 1);

  let r2 = refund r1 in
  assert (used r2 = 0);
  assert (remaining r2 = 2);

  (* Excess refund: should not underflow below 0 *)
  let r3 = refund r2 in
  assert (used r3 = 0);
  assert (remaining r3 = 2);

  let r4 = refund r3 in
  assert (used r4 = 0);
  assert (remaining r4 = 2);
  Printf.printf "  => PASS\n"

let test_turn_budget_remaining_calc () =
  Printf.printf "[Turn_budget] Testing remaining calculation bounds...\n";
  let b1 = { maximum = 5; consumed = 2 } in
  assert (remaining b1 = 3);
  let b2 = { maximum = 5; consumed = 5 } in
  assert (remaining b2 = 0);
  let b3 = { maximum = 5; consumed = 7 } in
  assert (remaining b3 = 0); (* max 0 (5 - 7) = 0 *)
  let b4 = { maximum = -5; consumed = 0 } in
  assert (remaining b4 = 0);
  let b5 = { maximum = -5; consumed = 2 } in
  assert (remaining b5 = 0);
  Printf.printf "  => PASS\n"

let test_message_hygiene_surrogate_utf8 () =
  Printf.printf "[Message_hygiene] Testing surrogate UTF-8 byte replacement & boundary cases...\n";
  (* Boundary 1: U+D7FF = \237\159\191 (byte 2 = 0x9F < 0xA0) -> valid UTF-8, must NOT be replaced *)
  let u_d7ff = "\237\159\191" in
  assert (replace_surrogate_utf8 u_d7ff = u_d7ff);

  (* Boundary 2: U+D800 = \237\160\128 (byte 2 = 0xA0, byte 3 = 0x80) -> surrogate, MUST be replaced *)
  let u_d800 = "\237\160\128" in
  assert (replace_surrogate_utf8 u_d800 = "\239\191\189");

  (* Mid surrogate: U+DBFF = \237\175\191 *)
  let u_dbff = "\237\175\191" in
  assert (replace_surrogate_utf8 u_dbff = "\239\191\189");

  (* Boundary 3: U+DC00 = \237\176\128 *)
  let u_dc00 = "\237\176\128" in
  assert (replace_surrogate_utf8 u_dc00 = "\239\191\189");

  (* Boundary 4: U+DFFF = \237\191\191 (byte 2 = 0xBF, byte 3 = 0xBF) -> surrogate, MUST be replaced *)
  let u_dfff = "\237\191\191" in
  assert (replace_surrogate_utf8 u_dfff = "\239\191\189");

  (* Boundary 5: U+E000 = \238\128\128 (byte 1 = 0xEE != 0xED) -> valid UTF-8, must NOT be replaced *)
  let u_e000 = "\238\128\128" in
  assert (replace_surrogate_utf8 u_e000 = u_e000);

  (* Truncated sequences: single trailing 0xED byte *)
  assert (replace_surrogate_utf8 "prefix\237" = "prefix\237");

  (* Truncated sequences: 2 trailing bytes 0xED 0xA0 *)
  assert (replace_surrogate_utf8 "prefix\237\160" = "prefix\237\160");

  (* Invalid second byte: 0xED 0x80 0x80 (0x80 < 0xA0) *)
  assert (replace_surrogate_utf8 "\237\128\128" = "\237\128\128");

  (* Invalid third byte: 0xED 0xA0 0x3F (0x3F < 0x80) *)
  assert (replace_surrogate_utf8 "\237\160?" = "\237\160?");

  (* Consecutive surrogates *)
  assert (replace_surrogate_utf8 "\237\160\128\237\191\191" = "\239\191\189\239\191\189");

  (* Embedded surrogates in sentence *)
  let text = "Hello \237\160\128 World \237\191\191!" in
  let clean = replace_surrogate_utf8 text in
  assert (clean = "Hello \239\191\189 World \239\191\189!");

  (* Idempotency test *)
  assert (replace_surrogate_utf8 clean = clean);
  Printf.printf "  => PASS\n"

let test_message_hygiene_non_object_json () =
  Printf.printf "[Message_hygiene] Testing non-object JSON values and fallbacks...\n";
  let model_id = "openai/gpt-4o" in
  (* String node *)
  assert (sanitize_message ~model_id (`String "test\237\160\128") = `String "test\239\191\189");

  (* Scalar nodes *)
  assert (sanitize_message ~model_id (`Int 100) = `Int 100);
  assert (sanitize_message ~model_id (`Float 2.718) = `Float 2.718);
  assert (sanitize_message ~model_id (`Bool true) = `Bool true);
  assert (sanitize_message ~model_id `Null = `Null);

  (* List node *)
  let list_val = `List [ `String "a\237\160\128"; `Int 5; `Bool false ] in
  assert (sanitize_message ~model_id list_val = `List [ `String "a\239\191\189"; `Int 5; `Bool false ]);

  (* Non-Assoc tool call fallback *)
  assert (sanitize_tool_call ~keep_thought_signature:false (`String "tc\237\160\128") = `String "tc\239\191\189");
  assert (sanitize_tool_call ~keep_thought_signature:true (`Int 999) = `Int 999);

  (* tool_calls containing non-List *)
  let msg_bad_tc_type = `Assoc [ ("tool_calls", `String "not_a_list\237\160\128") ] in
  let san_bad_tc = sanitize_message ~model_id msg_bad_tc_type in
  assert (member "tool_calls" san_bad_tc = Some (`String "not_a_list\239\191\189"));

  (* tool_calls containing List of non-Assoc elements *)
  let msg_non_assoc_tcs = `Assoc [ ("tool_calls", `List [ `Int 1; `String "call\237\160\128" ]) ] in
  let san_non_assoc_tcs = sanitize_message ~model_id msg_non_assoc_tcs in
  assert (member "tool_calls" san_non_assoc_tcs = Some (`List [ `Int 1; `String "call\239\191\189" ]));
  Printf.printf "  => PASS\n"

let test_message_hygiene_gemma_and_case () =
  Printf.printf "[Message_hygiene] Testing Gemma/Gemini model string matching and case insensitivity...\n";
  let gemma_models = [
    "google/gemma-2-9b";
    "google/gemma-7b-it";
    "GEMMA-2B";
    "Google/Gemini-1.5-Pro";
    "GOOGLE/GEMINI-2.5-FLASH";
    "my-custom-gemma-v1";
  ] in
  List.iter (fun m ->
    assert (model_consumes_thought_signature m)
  ) gemma_models;

  let non_gemma_models = [
    "openai/gpt-4o";
    "anthropic/claude-3-5-sonnet";
    "meta/llama-3-70b";
    "deepseek-v3";
    "";
  ] in
  List.iter (fun m ->
    assert (not (model_consumes_thought_signature m))
  ) non_gemma_models;

  (* Verify extra_content preservation logic *)
  let msg_with_thought =
    `Assoc [
      ("role", `String "assistant");
      ("tool_calls", `List [
        `Assoc [
          ("id", `String "call_1");
          ("call_id", `String "secret_call_id");
          ("response_item_id", `String "secret_item_id");
          ("extra_content", `Assoc [ ("thought_signature", `String "sig123\237\160\128") ])
        ]
      ])
    ]
  in

  (* For Gemma (thought signature kept, surrogate sanitized inside extra_content) *)
  let san_gemma = sanitize_message ~model_id:"GEMMA-7B-IT" msg_with_thought in
  let calls_gemma = match member "tool_calls" san_gemma with Some (`List [ c ]) -> c | _ -> failwith "gemma call" in
  assert (member "call_id" calls_gemma = None); (* call_id always stripped *)
  assert (member "response_item_id" calls_gemma = None); (* response_item_id always stripped *)
  let ec_gemma = match member "extra_content" calls_gemma with Some (`Assoc fields) -> fields | _ -> failwith "extra_content" in
  assert (List.assoc "thought_signature" ec_gemma = `String "sig123\239\191\189");

  (* For GPT-4o (thought signature stripped) *)
  let san_gpt = sanitize_message ~model_id:"OPENAI/GPT-4O" msg_with_thought in
  let calls_gpt = match member "tool_calls" san_gpt with Some (`List [ c ]) -> c | _ -> failwith "gpt call" in
  assert (member "call_id" calls_gpt = None);
  assert (member "response_item_id" calls_gpt = None);
  assert (member "extra_content" calls_gpt = None);
  Printf.printf "  => PASS\n"

let test_message_hygiene_codex_and_fields () =
  Printf.printf "[Message_hygiene] Testing Codex reasoning/message items and private field stripping...\n";
  let msg =
    `Assoc [
      ("role", `String "assistant");
      ("_internal_state", `String "secret");
      ("tool_name", `String "my_tool");
      ("codex_reasoning_items", `List [ `String "r1"; `String "r2" ]);
      ("codex_message_items", `List [ `String "m1" ]);
      ("content", `String "Hello \237\160\128 World");
      ("name", `String "user1")
    ]
  in
  let san = sanitize_message ~model_id:"openai/gpt-4o" msg in
  assert (member "_internal_state" san = None);
  assert (member "tool_name" san = None);
  assert (member "codex_reasoning_items" san = None);
  assert (member "codex_message_items" san = None);
  assert (member "content" san = Some (`String "Hello \239\191\189 World"));
  assert (member "name" san = Some (`String "user1"));
  assert (member "role" san = Some (`String "assistant"));
  Printf.printf "  => PASS\n"

let () =
  Printf.printf "=== STARTING EMPIRICAL CHALLENGER STRESS SUITE (M1) ===\n";
  test_turn_budget_zero_and_negative ();
  test_turn_budget_consumption_and_refunds ();
  test_turn_budget_remaining_calc ();
  test_message_hygiene_surrogate_utf8 ();
  test_message_hygiene_non_object_json ();
  test_message_hygiene_gemma_and_case ();
  test_message_hygiene_codex_and_fields ();
  Printf.printf "=== ALL EMPIRICAL CHALLENGER STRESS TESTS PASSED 100%% ===\n"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_challenger_m1" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)
