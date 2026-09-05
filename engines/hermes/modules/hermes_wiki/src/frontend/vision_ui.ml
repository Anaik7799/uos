let () =
  let ws_url = 
    match Sys.getenv_opt "HERMES_VISION_KPI_WS" with
    | Some ws -> ws
    | None -> "ws://localhost:8080/kpi"
  in
  Printf.printf "[Bonsai UI] Mounting Dashboard...\n";
  Printf.printf "1. Rendering Datarhei WebRTC <iframe src='http://datarhei-node:8080/ui/player/'>...\n";
  Printf.printf "2. Connecting to WebSocket %s for KPI Telemetry...\n" ws_url;
  Printf.printf "3. Rendering KPI Sidebar (FPS, Latency, Active Objects)...\n"
