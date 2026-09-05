open Lmstudio_intent

let execute_intent env prompt =
  let cmd = synthesize_curl_command env prompt in
  Printf.printf "[LMStudio Controller] Executing: %s\n%!" cmd;
  let _ = Swarm_zenoh.publish_telemetry (Printf.sprintf "{\"event\": \"lmstudio_intent_started\", \"model\": \"%s\"}" env.topology.model_id) in
  match Unix.system (cmd ^ " > /dev/null 2>&1 &") with
  | Unix.WEXITED 0 -> 
      let _ = Swarm_zenoh.publish_telemetry "{\"event\": \"lmstudio_intent_success\"}" in
      Ok ()
  | _ -> 
      let _ = Swarm_zenoh.publish_telemetry "{\"event\": \"lmstudio_intent_failed\"}" in
      Error "Failed to dispatch LM Studio intent"
