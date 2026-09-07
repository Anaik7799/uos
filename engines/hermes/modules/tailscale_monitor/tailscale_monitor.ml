let check_interval_sec = 60.0

let run_cmd cmd =
  let ic = Unix.open_process_in cmd in
  let rec read_all acc =
    try read_all (acc ^ input_line ic ^ "\n")
    with End_of_file -> acc
  in
  let out = read_all "" in
  let _ = Unix.close_process_in ic in
  out

let gather_diagnostics () =
  let status = run_cmd "tailscale status" in
  let netcheck = run_cmd "tailscale netcheck 2>&1" in
  let ip_link = run_cmd "ip a show tailscale0 2>&1" in
  let routes = run_cmd "ip route show table 52 2>&1" in
  let svc = run_cmd "systemctl status tailscaled --no-pager 2>&1" in
  Printf.sprintf
    "=== RCA DIAGNOSTIC REPORT ===\n\n[Tailscale Status]\n%s\n[Tailscale Netcheck]\n%s\n[Interface]\n%s\n[Routes]\n%s\n[Service]\n%s"
    status netcheck ip_link routes svc

let send_email diag =
  let tmp = "/tmp/ts_diag.txt" in
  let oc = open_out tmp in
  Printf.fprintf oc "%s" diag;
  close_out oc;
  let _ = Sys.command "cat /tmp/ts_diag.txt | mail -s \"CRITICAL: Tailscale Degraded on nas-1\" root@localhost" in
  ()

let publish_zenoh diag =
  let alert_json =
    `Assoc [
      ("alert", `String "Tailscale status check failed. Service is degraded.");
      ("host", `String "nas-1");
      ("diagnostics", `String diag)
    ]
  in
  let payload = Yojson.Safe.to_string alert_json in
  let _ = Hermes_zenoh.publish ~key:"indrajaal/tailscale/alert" ~payload in

  let prompt_text =
    "Tailscale is degraded on nas-1. Please review the following diagnostic RCA payload and work out a fix:\n\n" ^ diag
  in
  let prompt_json =
    `Assoc [
      ("prompt", `String prompt_text)
    ]
  in
  let prompt_payload = Yojson.Safe.to_string prompt_json in
  let _ = Hermes_zenoh.publish ~key:"hermes/agy/prompt" ~payload:prompt_payload in
  ()

let () =
  Printf.printf "Tailscale Monitor Service with RCA Diagnostics starting...\n%!";
  let rec loop () =
    let is_ok = 
       match Sys.command "tailscale status >/dev/null 2>&1" with
       | 0 -> true
       | _ -> false
    in
    if not is_ok then begin
       Printf.printf "[%f] DEGRADED: Initiating comprehensive RCA diagnostics...\n%!" (Unix.time ());
       let diag = gather_diagnostics () in
       Printf.printf "Diagnostics captured (%d bytes).\n%!" (String.length diag);
       send_email diag;
       publish_zenoh diag;
    end else begin
       Printf.printf "[%f] Tailscale is healthy.\n%!" (Unix.time ())
    end;
    Unix.sleepf check_interval_sec;
    loop ()
  in
  loop ()
