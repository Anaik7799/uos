open Lmstudio_monitor

type exploration_vector =
  | JSON_Tool_Orchestration
  | Adversarial_Logic_Traps
  | Context_Decay_Measurement
  | Zig_To_OCaml_Mapping

let vector_to_string = function
  | JSON_Tool_Orchestration -> "JSON_Tool_Orchestration"
  | Adversarial_Logic_Traps -> "Adversarial_Logic_Traps"
  | Context_Decay_Measurement -> "Context_Decay_Measurement"
  | Zig_To_OCaml_Mapping -> "Zig_To_OCaml_Mapping"

type evaluation_result = {
  score : float;
  vram_ok : bool;
  context_ok : bool;
  interpretation : string;
}

type exploration_state = {
  current_vector : exploration_vector;
  depth : int;
  consecutive_failures : int;
  prompt_history : (string * string * evaluation_result) list;
  dynamic_prompt_override : string option;
}

let formulate_next_prompt state =
  let prompt, oracle_flag = match state.dynamic_prompt_override with
    | Some custom_prompt -> custom_prompt, true
    | None ->
        let p = match state.current_vector with
          | JSON_Tool_Orchestration ->
              Printf.sprintf "Output a JSON payload conforming to the call_weather schema. Required fields: [city, unit]. Do not use markdown backticks. Depth: %d" state.depth
          | Adversarial_Logic_Traps ->
              Printf.sprintf "If it takes 5 machines 5 minutes to make 5 widgets, how long does it take 100 machines to make 100 widgets? Explain without using any arithmetic or math numbers in your reasoning. Depth: %d" state.depth
          | Context_Decay_Measurement ->
              Printf.sprintf "Summarize the overarching theme in precisely 5 words. The target fact is hidden exactly in the middle of this large block. Depth: %d" state.depth
          | Zig_To_OCaml_Mapping ->
              Printf.sprintf "Map this Zig comptime struct { const T = type; } to its OCaml GADT equivalent. Depth: %d" state.depth
        in p, false
  in
  let _ = Swarm_zenoh.publish_telemetry (Printf.sprintf "{\"fractal_layer\": \"L2/capability\", \"event\": \"PROMPT_FORMULATION\", \"vector\": \"%s\", \"oracle_guided\": %b}" (vector_to_string state.current_vector) oracle_flag) in
  prompt

let evaluate_response vector output log_line =
  let monitor_status = parse_log_line log_line in
  let vram_ok, context_ok = match monitor_status with
    | Some (Crash_Fault "Out of VRAM") -> false, true
    | Some (Crash_Fault "Context Window Overflow") -> true, false
    | _ -> true, true
  in
  let score, interp =
    if not vram_ok then 0.0, "FAIL: Out of VRAM during execution"
    else if not context_ok then 0.1, "FAIL: Context limit reached"
    else
      match vector with
      | JSON_Tool_Orchestration ->
          if contains_sub output "{" && contains_sub output "}" && contains_sub output "city" then
            1.0, "PASS: Valid tool JSON envelope generated."
          else
            0.3, "FAIL: Missed strict JSON tool envelope constraints."
      | Adversarial_Logic_Traps ->
          if contains_sub output "5" || contains_sub output "100" || contains_sub output "minutes" then
            0.5, "PARTIAL: Reasoning started but failed the adversarial negative constraint (used math/numbers)."
          else if contains_sub output "time remains constant" || contains_sub output "same" then
            1.0, "PASS: Successfully navigated the adversarial logic trap without math."
          else
            0.2, "FAIL: Hallucinated incorrect logic path."
      | Context_Decay_Measurement ->
          let word_count = List.length (String.split_on_char ' ' output) in
          if word_count = 5 then 1.0, "PASS: Precise context attention and length constraint met."
          else 0.4, "PARTIAL: Failed precise attention depth target."
      | Zig_To_OCaml_Mapping ->
          if contains_sub output "type" && contains_sub output "GADT" then 1.0, "PASS: Correct semantic bridging."
          else 0.3, "FAIL: Semantic bridging failure."
  in
  let _ = Swarm_zenoh.publish_telemetry (Printf.sprintf "{\"fractal_layer\": \"L5/trace\", \"event\": \"RESPONSE_EVALUATION\", \"score\": %.2f}" score) in
  { score; vram_ok; context_ok; interpretation = interp }

let rotate_vector = function
  | JSON_Tool_Orchestration -> Adversarial_Logic_Traps
  | Adversarial_Logic_Traps -> Context_Decay_Measurement
  | Context_Decay_Measurement -> Zig_To_OCaml_Mapping
  | Zig_To_OCaml_Mapping -> JSON_Tool_Orchestration

let evolve state last_output mock_log =
  let current_eval = evaluate_response state.current_vector last_output mock_log in
  
  let next_vector, next_depth, next_failures =
    if current_eval.score >= 0.8 then
      if state.depth >= 3 then
        rotate_vector state.current_vector, 1, 0
      else
        state.current_vector, state.depth + 1, 0
    else
      state.current_vector, max 1 (state.depth - 1), state.consecutive_failures + 1
  in
  
  let updated_history = (vector_to_string state.current_vector, last_output, current_eval) :: state.prompt_history in
  let next_state = { 
    current_vector = next_vector; 
    depth = next_depth; 
    consecutive_failures = next_failures;
    prompt_history = updated_history;
    dynamic_prompt_override = None; (* Clear override on evolution step, Oracle will inject it before formulation if needed *)
  } in
  (next_state, current_eval)
