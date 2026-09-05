open Ffmpeg_intent

let execute_intent intent =
  let cmd = compile_intent intent in
  Printf.printf "[FFmpeg Controller] Executing: %s\n%!" cmd;
  let _ = Swarm_zenoh.publish_telemetry (Printf.sprintf "{\"event\": \"intent_execution_started\", \"command\": \"%s\"}" cmd) in
  match Unix.system (cmd ^ " > /dev/null 2>&1 &") with
  | Unix.WEXITED 0 -> 
      let _ = Swarm_zenoh.publish_telemetry "{\"event\": \"intent_execution_success\"}" in
      Ok ()
  | _ -> 
      let _ = Swarm_zenoh.publish_telemetry "{\"event\": \"intent_execution_failed\"}" in
      Error "Failed to dispatch FFmpeg swarm job"
