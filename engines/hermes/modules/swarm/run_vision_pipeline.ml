open Ffmpeg_intent
open Ffmpeg_controller

let () =
  Printf.printf "Starting Vision Pipeline End-to-End Test (Simulated)...\n%!";
  let sim_intent = Simulate_Stream { sink = "webrtc://0.0.0.0:3333" } in
  (match execute_intent sim_intent with
   | Ok () -> Printf.printf "Simulation started. Will switch to REAL feed in 10s.\n%!"
   | Error e -> Printf.printf "Error: %s\n%!" e; exit 1);
  Unix.sleep 10;
  let stop_intent = Stop_Stream { id = "3333" } in
  let _ = execute_intent stop_intent in
  Unix.sleep 2;
  Printf.printf "Starting Vision Pipeline End-to-End Test (Real Physical Feed)...\n%!";
  let real_intent = Transmux_Stream { source = "udp://0.0.0.0:5000"; sink = "webrtc://0.0.0.0:3333" } in
  match execute_intent real_intent with
  | Ok () -> Printf.printf "Real stream attached to the dashboard sink.\n%!"
  | Error e -> Printf.printf "Error: %s\n%!" e; exit 1
