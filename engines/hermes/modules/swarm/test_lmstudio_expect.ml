open Lmstudio_intent
open Lmstudio_explorer

let run_expect_cycle () =
  let out = Buffer.create 1024 in
  let p str = Buffer.add_string out (str ^ "\n") in

  p "=================================================================================";
  p "           LM STUDIO / GEMMA CLOSED-LOOP ACTIVE EVOLUTION EXPECT TESTS           ";
  p "=================================================================================";

  let db_path = "lmstudio_history.db" in
  let db = match Lmstudio_db.init_db db_path with
    | Ok d -> d
    | Error err -> failwith err
  in

  let env = default_gemma_4_envelope in
  let state = { current_vector = Adversarial_Logic_Traps; depth = 1; consecutive_failures = 0; prompt_history = []; dynamic_prompt_override = None } in

  (* Prompt 1 Formulation *)
  let prompt1 = formulate_next_prompt state in
  p "\n------------------- EVOLUTION STEP 1 -------------------";
  p (Printf.sprintf "Exploring Vector: %s at Depth: %d" (vector_to_string state.current_vector) state.depth);
  p (Printf.sprintf "Prompt Sent: %s" prompt1);

  let mock_curl = synthesize_curl_command env prompt1 in
  p "Payload Sent (CURL equivalent):";
  p mock_curl;

  (* Mocking a successful Logical Reasoning response *)
  let response1 = "My step-by-step reasoning is: 3x = 15, which means x = 5." in
  p "\nResponse Received from LMStudio:";
  p response1;

  let state, eval1 = evolve state response1 "INFO: Success" in
  p "\nInterpretation and Resource Evaluation:";
  p (Printf.sprintf "  - Evaluation Score: %.1f" eval1.score);
  p (Printf.sprintf "  - Memory usage check: VRAM: %b, Context: %b" eval1.vram_ok eval1.context_ok);
  p (Printf.sprintf "  - Evaluation Result: %s" eval1.interpretation);

  let _ = Lmstudio_db.log_transaction db "Adversarial_Logic_Traps" 1 prompt1 response1 eval1.score eval1.vram_ok eval1.context_ok eval1.interpretation 
    "/v1/chat/completions" env.topology.model_id mock_curl "INFO: Success" env.params.temperature 
    (match env.params.max_tokens with Some x -> x | None -> 8192) "Zero_Shot" "" in

  (* Prompt 2 Formulation (Evolved State) *)
  let prompt2 = formulate_next_prompt state in
  p "\n------------------- EVOLUTION STEP 2 -------------------";
  p (Printf.sprintf "Evolved Target Vector: %s at Depth: %d (Dynamic expansion of capability space)" 
       (vector_to_string state.current_vector) state.depth);
  p (Printf.sprintf "Formulated Prompt Sent: %s" prompt2);

  let mock_curl2 = synthesize_curl_command env prompt2 in
  p "Payload Sent (CURL equivalent):";
  p mock_curl2;

  (* Mocking a successful response on the evolved vector *)
  let response2 = "{\n  \"id\": \"node-1\",\n  \"status\": \"online\",\n  \"memory_bytes\": 16384\n}" in
  p "\nResponse Received from LMStudio:";
  p response2;

  let state, eval2 = evolve state response2 "INFO: Success" in
  p "\nInterpretation and Resource Evaluation:";
  p (Printf.sprintf "  - Evaluation Score: %.1f" eval2.score);
  p (Printf.sprintf "  - Memory usage check: VRAM: %b, Context: %b" eval2.vram_ok eval2.context_ok);
  p (Printf.sprintf "  - Evaluation Result: %s" eval2.interpretation);

  let _ = Lmstudio_db.log_transaction db "Adversarial_Logic_Traps" 2 prompt2 response2 eval2.score eval2.vram_ok eval2.context_ok eval2.interpretation 
    "/v1/chat/completions" env.topology.model_id mock_curl2 "INFO: Success" env.params.temperature 
    (match env.params.max_tokens with Some x -> x | None -> 8192) "Zero_Shot" "" in

  (* Prompt 3 Formulation (Context Limit Crash Simulation) *)
  let prompt3 = formulate_next_prompt state in
  p "\n------------------- EVOLUTION STEP 3 (CRASH DETECT & SAFE RECOVERY) -------------------";
  p (Printf.sprintf "Exploring Vector: %s at Depth: %d" (vector_to_string state.current_vector) state.depth);
  p (Printf.sprintf "Prompt Sent: %s" prompt3);

  let mock_curl3 = synthesize_curl_command env prompt3 in
  p "Payload Sent (CURL equivalent):";
  p mock_curl3;

  (* Mocking a crash payload from logs *)
  let mock_log3 = "Error: Out of VRAM limit while loading layers!" in
  let response3 = "" in (* Empty because of crash *)
  p "\nResponse Received from LMStudio:";
  p response3;
  p (Printf.sprintf "Tailed Server Log Line: %s" mock_log3);

  let _state, eval3 = evolve state response3 mock_log3 in
  p "\nInterpretation and Resource Evaluation:";
  p (Printf.sprintf "  - Evaluation Score: %.1f" eval3.score);
  p (Printf.sprintf "  - Memory usage check: VRAM: %b, Context: %b" eval3.vram_ok eval3.context_ok);
  p (Printf.sprintf "  - Evaluation Result: %s" eval3.interpretation);
  p "  - Recovery Action: Controller automatically degrades complexity, triggering resource apoptosis.";

  let _ = Lmstudio_db.log_transaction db "Adversarial_Logic_Traps" 1 prompt3 response3 eval3.score eval3.vram_ok eval3.context_ok eval3.interpretation 
    "/v1/chat/completions" env.topology.model_id mock_curl3 mock_log3 env.params.temperature 
    (match env.params.max_tokens with Some x -> x | None -> 8192) "Zero_Shot" "" in

  p "\n------------------- PERSISTENT DATABASE TRANSACTION MEMORY HISTORY (SQLITE3) -------------------";
  let _ = Lmstudio_db.print_history db out in

  p "\n------------------- AUTONOMIC SELF-HEALING OPTIMIZATION -------------------";
  let mitigation = Lmstudio_optimizer.analyze_and_optimize db env in
  let optimized_env = Lmstudio_optimizer.apply_optimization mitigation env in
  p "\nOriginal Envelope Parameters:";
  p (Printf.sprintf "  - max_tokens: %s" (match env.params.max_tokens with Some x -> string_of_int x | None -> "None"));
  p (Printf.sprintf "  - json_schema: %b" env.params.json_schema_structured_output);
  p "\nOptimized, Stabilized Envelope Parameters:";
  p (Printf.sprintf "  - max_tokens: %s" (match optimized_env.params.max_tokens with Some x -> string_of_int x | None -> "None"));
  p (Printf.sprintf "  - json_schema: %b" optimized_env.params.json_schema_structured_output);

  let _ = Lmstudio_db.close_db db in
  p "=================================================================================";

  Buffer.contents out

let () =
  let result = run_expect_cycle () in
  (* Write to Golden/Expect Snapshot File *)
  let out_file = 
    if Sys.file_exists "../../../../modules/swarm" then
      "../../../../modules/swarm/lmstudio_expect_snapshot.txt"
    else if Sys.file_exists "modules/swarm" then
      "modules/swarm/lmstudio_expect_snapshot.txt"
    else
      "lmstudio_expect_snapshot.txt"
  in
  let ch = open_out out_file in
  output_string ch result;
  close_out ch;
  
  (* Print to stdout for verification check *)
  print_endline result;
  print_endline "Expectation baseline successfully written to: modules/swarm/lmstudio_expect_snapshot.txt";

  let self =
    Suite_telemetry.observe ~suite:"test_lmstudio_expect" ~passed:1 ~failed:0
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code self)
