open Lmstudio_monitor

let start_cpu_probe () =
  (* Runs an SSH command to razer-1 to poll CPU usage (Windows PowerShell) and pipes to Zenoh *)
  let cmd = "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o BatchMode=yes -l abhijitnaik1@hotmail.com 100.114.9.28 \"powershell -Command \\\"while(\\$true){ Get-WmiObject Win32_Processor | Select-Object -ExpandProperty LoadPercentage; Start-Sleep -Seconds 2 }\\\"\"" in
  let fpid = Unix.fork () in
  if fpid = 0 then begin
      let ic = Unix.open_process_in cmd in
      try
        while true do
          let line = input_line ic in
          let line = String.trim line in
          if line <> "" then
            let _ = Swarm_zenoh.publish_telemetry (Printf.sprintf "{\"razer_1_probe\": {\"cpu_utilization_percent\": %s}}" line) in
            ()
        done;
        exit 0
      with _ ->
        ignore (Unix.close_process_in ic);
        exit 1
  end else fpid

let start_log_probe () =
  (* Tails the LM Studio logs directory on Windows over SSH *)
  let cmd = "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o BatchMode=yes -l abhijitnaik1@hotmail.com 100.114.9.28 \"powershell -Command \\\"Get-Content C:\\Users\\abhij\\.lmstudio\\apps\\bionic\\server-logs\\2026-08\\*.log -Wait -Tail 1\\\"\"" in
  let fpid = Unix.fork () in
  if fpid = 0 then begin
      let ic = Unix.open_process_in cmd in
      try
        while true do
          let line = input_line ic in
          let line = String.trim line in
          if line <> "" then begin
            (* Stream raw logs to zenoh and run them through our monitor parser *)
            let _ = Swarm_zenoh.publish_telemetry (Printf.sprintf "{\"razer_1_probe\": {\"raw_log\": \"%s\"}}" (String.escaped line)) in
            match parse_log_line line with
            | Some (Crash_Fault msg) ->
                let _ = Swarm_zenoh.publish_telemetry (Printf.sprintf "{\"monitor_event\": {\"alert\": \"REMOTE_CRASH_DETECTED\", \"msg\": \"%s\"}}" msg) in ()
            | _ -> ()
          end
        done;
        exit 0
      with _ ->
        ignore (Unix.close_process_in ic);
        exit 1
  end else fpid

let init_remote_probes () =
  print_endline "[Razer-1 Probe] Initializing remote SSH probes to 100.114.9.28...";
  let cpu_pid = start_cpu_probe () in
  let log_pid = start_log_probe () in
  (cpu_pid, log_pid)

let kill_remote_probes (cpu_pid, log_pid) =
  print_endline "[Razer-1 Probe] Shutting down remote probes...";
  try Unix.kill cpu_pid Sys.sigkill with _ -> ();
  try Unix.kill log_pid Sys.sigkill with _ -> ()
