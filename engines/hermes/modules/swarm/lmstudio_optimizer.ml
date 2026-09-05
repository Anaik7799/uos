open Lmstudio_intent
open Lmstudio_db

type stabilization_recommendation =
  | Keep_Stable of string
  | Mitigate_VRAM of string * int (* recommend new max_tokens *)
  | Inject_JSON_Schema of string * string (* prompt suffix payload *)

(* Analyzes the last N SQLite transactions to compute success trends and diagnose failure root-causes *)
let analyze_and_optimize t (current_env : lmstudio_envelope) =
  let sql = "SELECT evaluation_score, vram_ok, context_ok, vector_space FROM lmstudio_history ORDER BY id DESC LIMIT 5;" in
  let stmt = Sqlite3.prepare t.db sql in
  let rec gather acc =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let score = Sqlite3.column_double stmt 0 in
        let vram = Sqlite3.column_int64 stmt 1 = 1L in
        let ctx = Sqlite3.column_int64 stmt 2 = 1L in
        let vec = Sqlite3.column_text stmt 3 in
        gather ((score, vram, ctx, vec) :: acc)
    | Sqlite3.Rc.DONE -> acc
    | _ -> acc
  in
  let records = gather [] in
  ignore (Sqlite3.finalize stmt : Sqlite3.Rc.t);

  if List.length records = 0 then
    Keep_Stable "No transaction history available. Staying on default envelope."
  else
    let total = float_of_int (List.length records) in
    let avg_score = List.fold_left (fun sum (s, _, _, _) -> sum +. s) 0.0 records /. total in
    let vram_failures = List.fold_left (fun count (_, vram, _, _) -> if not vram then count + 1 else count) 0 records in
    let context_failures = List.fold_left (fun count (_, _, ctx, _) -> if not ctx then count + 1 else count) 0 records in
    let format_failures = List.fold_left (fun count (s, vram, ctx, vec) -> 
      if s < 0.6 && vram && ctx && vec = "Structured_JSON_Formatting" then count + 1 else count
    ) 0 records in

    let _ = Swarm_zenoh.publish_telemetry (
      Printf.sprintf "{\"optimizer_telemetry\": {\"avg_score\": %.2f, \"vram_faults\": %d, \"ctx_faults\": %d, \"format_faults\": %d}}" 
        avg_score vram_failures context_failures format_failures
    ) in

    if vram_failures > 0 then
      let current_max = match current_env.params.max_tokens with Some m -> m | None -> 8192 in
      let reduced_max = current_max / 2 in
      Mitigate_VRAM (
        Printf.sprintf "High VRAM collision rate detected (%d/%d transactions failed due to memory limit). Reducing context window margins." 
          vram_failures (List.length records),
        reduced_max
      )
    else if format_failures > 0 then
      Inject_JSON_Schema (
        "Model formatting deviations observed. Injecting a strict JSON schema enforcement wrapper suffix.",
        "Your output must be validated against JSON Schema: {\"type\": \"object\", \"required\": [\"id\", \"status\"]}"
      )
    else if avg_score >= 0.8 then
      Keep_Stable "All performance metrics are healthy. Maintaining current execution parameters."
    else
      Keep_Stable "System state is stable but sub-optimal. No immediate resource faults observed."

(* Applies the mitigation to create a hardened, safe envelope *)
let apply_optimization mitigation (env : lmstudio_envelope) =
  match mitigation with
  | Keep_Stable msg ->
      Printf.printf "[Optimizer Status] %s\n" msg;
      env
  | Mitigate_VRAM (msg, new_max) ->
      Printf.printf "[Optimizer Mitigation] %s\n" msg;
      let _ = Swarm_zenoh.publish_telemetry "{\"alert\": \"VRAM_MITIGATION_APPLIED\"}" in
      { env with params = { env.params with max_tokens = Some new_max } }
  | Inject_JSON_Schema (msg, schema_suffix) ->
      Printf.printf "[Optimizer Mitigation] %s\n" msg;
      let _ = Swarm_zenoh.publish_telemetry "{\"alert\": \"SCHEMA_INJECTION_APPLIED\"}" in
      (* Appends schema validator to the stop sequences or indicates structured output constraint *)
      { env with params = { env.params with json_schema_structured_output = true; stop_sequences = [schema_suffix] } }
