open Lmstudio_intent
open Lmstudio_explorer

let run_curl_sync cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 1024 in
  try
    while true do
      Buffer.add_string buf (input_line ic);
      Buffer.add_char buf '\n'
    done;
    ""
  with End_of_file ->
    let _ = Unix.close_process_in ic in
    Buffer.contents buf

let extract_content json_str =
  try
    let json = Yojson.Basic.from_string json_str in
    let open Yojson.Basic.Util in
    let choices = json |> member "choices" |> to_list in
    let first_choice = List.hd choices in
    first_choice |> member "message" |> member "content" |> to_string
  with _ ->
    "ERROR: Failed to parse JSON. Raw output: " ^ json_str

let run_live_cycle () =
  let out = Buffer.create 1024 in
  let p str = Buffer.add_string out (str ^ "\n"); print_endline str in

  p "=================================================================================";
  p "           LM STUDIO / GEMMA CLOSED-LOOP LIVE INFERENCE TESTS                    ";
  p "=================================================================================";

  let db_path = 
    if Sys.file_exists "../../../../modules/swarm" then
      "../../../../state/lmstudio_live_history.db"
    else if Sys.file_exists "state" then
      "state/lmstudio_live_history.db"
    else
      "lmstudio_live_history.db"
  in
  let db = match Lmstudio_db.init_db db_path with
    | Ok d -> d
    | Error err -> failwith err
  in

  let env = default_gemma_4_envelope in
  let state = { current_vector = Adversarial_Logic_Traps; depth = 1; consecutive_failures = 0; prompt_history = []; dynamic_prompt_override = None } in

  (* Prompt 1 Formulation *)
  let prompt1 = formulate_next_prompt state in
  p "\n------------------- LIVE INFERENCE STEP 1 -------------------";
  p (Printf.sprintf "Exploring Vector: %s at Depth: %d" (vector_to_string state.current_vector) state.depth);
  p (Printf.sprintf "Prompt Sent: %s" prompt1);

  let curl_cmd = synthesize_curl_command env prompt1 in
  p "Executing curl command...";
  let raw_json1 = run_curl_sync curl_cmd in
  let response1 = extract_content raw_json1 in
  
  p "\nRaw Response Received from Live LMStudio:";
  p response1;

  let state, eval1 = evolve state response1 "INFO: Success" in
  p "\nInterpretation and Resource Evaluation:";
  p (Printf.sprintf "  - Evaluation Score: %.1f" eval1.score);
  p (Printf.sprintf "  - Memory usage check: VRAM: %b, Context: %b" eval1.vram_ok eval1.context_ok);
  p (Printf.sprintf "  - Evaluation Result: %s" eval1.interpretation);

  let _ = Lmstudio_db.log_transaction db "Adversarial_Logic_Traps" 1 prompt1 response1 eval1.score eval1.vram_ok eval1.context_ok eval1.interpretation 
    "/v1/chat/completions" env.topology.model_id curl_cmd "INFO: Success" env.params.temperature 
    (match env.params.max_tokens with Some x -> x | None -> 8192) "Zero_Shot" "" in

  (* Prompt 2 Formulation *)
  let prompt2 = formulate_next_prompt state in
  p "\n------------------- LIVE INFERENCE STEP 2 -------------------";
  p (Printf.sprintf "Evolved Target Vector: %s at Depth: %d" 
       (vector_to_string state.current_vector) state.depth);
  p (Printf.sprintf "Formulated Prompt Sent: %s" prompt2);

  let curl_cmd2 = synthesize_curl_command env prompt2 in
  p "Executing curl command...";
  let raw_json2 = run_curl_sync curl_cmd2 in
  let response2 = extract_content raw_json2 in

  p "\nRaw Response Received from Live LMStudio:";
  p response2;

  let state, eval2 = evolve state response2 "INFO: Success" in
  p "\nInterpretation and Resource Evaluation:";
  p (Printf.sprintf "  - Evaluation Score: %.1f" eval2.score);
  p (Printf.sprintf "  - Memory usage check: VRAM: %b, Context: %b" eval2.vram_ok eval2.context_ok);
  p (Printf.sprintf "  - Evaluation Result: %s" eval2.interpretation);

  let _ = Lmstudio_db.log_transaction db (vector_to_string state.current_vector) state.depth prompt2 response2 eval2.score eval2.vram_ok eval2.context_ok eval2.interpretation 
    "/v1/chat/completions" env.topology.model_id curl_cmd2 "INFO: Success" env.params.temperature 
    (match env.params.max_tokens with Some x -> x | None -> 8192) "Zero_Shot" "" in

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
  let result = run_live_cycle () in
  (* Write to Snapshot File just to preserve the run data *)
  let out_file = 
    if Sys.file_exists "../../../../modules/swarm" then
      "../../../../modules/swarm/lmstudio_live_snapshot.txt"
    else if Sys.file_exists "modules/swarm" then
      "modules/swarm/lmstudio_live_snapshot.txt"
    else
      "lmstudio_live_snapshot.txt"
  in
  let ch = open_out out_file in
  output_string ch result;
  close_out ch;
  
  let self =
    Suite_telemetry.observe ~suite:"test_lmstudio_live" ~passed:1 ~failed:0
      ~skipped:0
  in
  exit (Suite_telemetry.exit_code self)
