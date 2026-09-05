open Lmstudio_intent

type model_status =
  | Idle
  | Loading of string
  | Active of string
  | Unloaded of string
  | Crash_Fault of string

type log_metric = {
  vram_usage_bytes : int64;
  context_tokens : int;
  tokens_per_second : float;
}

let publish_monitor_event event_json =
  Swarm_zenoh.publish_telemetry (Printf.sprintf "{\"monitor_event\": %s}" event_json)

let load_model env model_id =
  let url = Printf.sprintf "http://%s:%d/api/v1/model/load" env.topology.api_host env.topology.api_port in
  let cmd = Printf.sprintf "curl -s -X POST %s -H \"Content-Type: application/json\" -d '{\"model\": \"%s\"}'" url model_id in
  let _ = publish_monitor_event (Printf.sprintf "{\"action\": \"load_model_started\", \"model\": \"%s\"}" model_id) in
  match Unix.system (cmd ^ " > /dev/null 2>&1") with
  | Unix.WEXITED 0 ->
      let _ = publish_monitor_event (Printf.sprintf "{\"action\": \"load_model_success\", \"model\": \"%s\"}" model_id) in
      Ok ()
  | _ ->
      let _ = publish_monitor_event (Printf.sprintf "{\"action\": \"load_model_failed\", \"model\": \"%s\"}" model_id) in
      Error ("Failed to load model " ^ model_id)

let unload_model env model_id =
  let url = Printf.sprintf "http://%s:%d/api/v1/model/unload" env.topology.api_host env.topology.api_port in
  let cmd = Printf.sprintf "curl -s -X POST %s -H \"Content-Type: application/json\" -d '{\"model\": \"%s\"}'" url model_id in
  let _ = publish_monitor_event (Printf.sprintf "{\"action\": \"unload_model_started\", \"model\": \"%s\"}" model_id) in
  match Unix.system (cmd ^ " > /dev/null 2>&1") with
  | Unix.WEXITED 0 ->
      let _ = publish_monitor_event (Printf.sprintf "{\"action\": \"unload_model_success\", \"model\": \"%s\"}" model_id) in
      Ok ()
  | _ ->
      let _ = publish_monitor_event (Printf.sprintf "{\"action\": \"unload_model_failed\", \"model\": \"%s\"}" model_id) in
      Error ("Failed to unload model " ^ model_id)

let contains_sub s sub =
  let rec check i j =
    if j >= String.length sub then true
    else if i + j >= String.length s then false
    else if s.[i+j] = sub.[j] then check i (j + 1)
    else false
  in
  let rec loop i =
    if i >= String.length s then false
    else if check i 0 then true
    else loop (i + 1)
  in
  loop 0

(* Scans an input stream (representing local log tailing) and alerts on anomalies *)
let parse_log_line line =
  if contains_sub line "Error" || contains_sub line "Failed" || contains_sub line "except" then
    if contains_sub line "VRAM" then
      let _ = publish_monitor_event "{\"alert\": \"VRAM_LIMIT_EXCEEDED\"}" in
      Some (Crash_Fault "Out of VRAM")
    else if contains_sub line "context" then
      let _ = publish_monitor_event "{\"alert\": \"CONTEXT_WINDOW_EXCEEDED\"}" in
      Some (Crash_Fault "Context Window Overflow")
    else
      let _ = publish_monitor_event "{\"alert\": \"GENERIC_ENGINE_ERROR\"}" in
      Some (Crash_Fault line)
  else if contains_sub line "Loaded" then
    Some (Active "Gemma-4-E4B")
  else if contains_sub line "Unloaded" then
    Some (Unloaded "Gemma-4-E4B")
  else
    None

let check_status env =
  let url = Printf.sprintf "http://%s:%d/v1/models" env.topology.api_host env.topology.api_port in
  let cmd = Printf.sprintf "curl -s --connect-timeout 2 %s" url in
  match Unix.system (cmd ^ " > /dev/null 2>&1") with
  | Unix.WEXITED 0 ->
      let _ = publish_monitor_event "{\"status\": \"engine_online\"}" in
      Ok (Active env.topology.model_id)
  | _ ->
      let _ = publish_monitor_event "{\"status\": \"engine_offline\"}" in
      Error "LM Studio engine is unreachable"
