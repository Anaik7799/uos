(* ==============================================================================
   uos_web_watchdog.ml — External out-of-BEAM outage detector and bounded
   recovery actor for the UOS cockpit plane.

   Contract      : SC-JIDOKA-001 (Andon), SC-CHECKLIST-001, SC-DIAGRAM-001
   Twin authority: formal/lean/UosCoreEvoUnifiedDigitalTwin.lean
                   THM_EXT_04 — critical recovery must lie outside the
                   protected fate domain (cockpitBeam).
   Fate domain   : hostSystemd. This program MUST NOT be hosted inside the
                   cockpit BEAM; doing so re-creates the co-residency defect
                   that left the plane dark for 41 h on 2026-11-03/05.
   Zero Muda     : pure OCaml 5.5 + unix. 0 Python, 0 shell helper, 0 NIF.

   Exit 0 = plane healthy. Exit 1 = degraded; an Andon record is appended and a
   bounded recovery attempt may have been made. Fail-closed: an unreadable
   probe counts as a failure, never as health.
   ============================================================================== *)

let uos_root =
  match Sys.getenv_opt "UOS_ROOT" with
  | Some r -> r
  | None -> "/home/an/NAS-setup/uos"

let cockpit_unit = "c3i-gleam-server.service"
let max_recovery_attempts = 1

(* ---------- bounded process capture -------------------------------------- *)

let capture_raw cmd args =
  let argv = Array.of_list (cmd :: args) in
  let r, w = Unix.pipe () in
  let dn = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0o666 in
  match Unix.fork () with
  | 0 ->
    Unix.close r;
    Unix.dup2 w Unix.stdout;
    Unix.dup2 dn Unix.stderr;
    Unix.close w; Unix.close dn;
    (try Unix.execvp cmd argv with _ -> exit 127)
  | pid ->
    Unix.close w; Unix.close dn;
    let buf = Buffer.create 4096 in
    let chunk = Bytes.create 4096 in
    let rec drain () =
      let n = try Unix.read r chunk 0 4096 with _ -> 0 in
      if n > 0 then (Buffer.add_subbytes buf chunk 0 n; drain ())
    in
    drain ();
    Unix.close r;
    let status = try snd (Unix.waitpid [] pid) with _ -> Unix.WEXITED 127 in
    let code = match status with Unix.WEXITED c -> c | _ -> 129 in
    (code, Buffer.contents buf)

let contains haystack needle =
  let hl = String.length haystack and nl = String.length needle in
  if nl = 0 then true
  else if nl > hl then false
  else begin
    let found = ref false in
    let i = ref 0 in
    while (not !found) && !i <= hl - nl do
      if String.sub haystack !i nl = needle then found := true;
      incr i
    done;
    !found
  end
(* REVIEW FIX (Pi+Argon finding 2, HIGH): every external probe is wrapped in a
   hard `timeout -k` so a hung ss/curl/systemctl cannot block the oneshot unit
   indefinitely, stalling the timer without ever writing an Andon record. *)
let capture ?(secs = 10) cmd args =
  capture_raw "timeout" ("-k" :: "2" :: string_of_int secs :: cmd :: args)


(* ---------- probes -------------------------------------------------------- *)

(* A port is bound only on positive evidence. An ss failure is NOT health. *)
let port_bound listeners port =
  match listeners with
  | None -> false
  | Some out -> contains out (":" ^ string_of_int port ^ " ")

let route_ok path =
  let url = "http://127.0.0.1:4100" ^ path in
  let code, out =
    capture "curl"
      [ "-s"; "-o"; "/dev/null"; "-w"; "%{http_code}"; "--max-time"; "8"; url ]
  in
  code = 0 && String.trim out = "200"

let unit_active unit =
  let code, out = capture "systemctl" [ "--user"; "is-active"; unit ] in
  code = 0 && String.trim out = "active"

(* REVIEW FIX (Pi+Argon finding 2, HIGH): a unit can be rate-limited into
   `failed` by Restart=always, after which `start` is refused until the limit
   window clears. Detect it so recovery can reset-failed first. *)
let unit_failed unit =
  let code, out = capture ~secs:10 "systemctl" [ "--user"; "is-failed"; unit ] in
  ignore code;
  String.trim out = "failed"

(* REVIEW FIX (Pi+Argon finding 1, HIGH): HTTP 200 is not liveness. A wedged
   BEAM can still serve shallow routes while the supervised actor mesh is dead,
   so the external authority asserts a SEMANTIC invariant from the plane's own
   status payload: the FPP supervisor running and its 40 actors alive. Absence
   of the field counts as unhealthy, never as health. *)
let deep_health () =
  let code, out =
    capture ~secs:12 "curl"
      [ "-s"; "--max-time"; "10"; "http://127.0.0.1:4100/api/v1/core-evo/status" ]
  in
  let ok =
    code = 0
    && contains out "\"fpp_supervisor_running\":true"
    && contains out "\"fpp_live_actors_alive\":40"
  in
  (ok, String.length out)

(* Dead-man channel for the in-BEAM HA model (inversion step 3). The in-BEAM
   ha/* modules remain the rich internal health model; this watchdog consumes
   their PRODUCT and treats absence or staleness as a fault. The receipt is not
   published yet, so `Absent` is reported honestly rather than defaulted. *)
type ha_receipt = Absent | Stale of float | Fresh of float

let ha_receipt_state max_age_s =
  let p = Filename.concat uos_root "var/ha/latest-health.json" in
  match (try Some (Unix.stat p) with _ -> None) with
  | None -> Absent
  | Some st ->
    let age = Unix.gettimeofday () -. st.Unix.st_mtime in
    if age > max_age_s then Stale age else Fresh age

(* ---------- receipts and Andon ------------------------------------------- *)

let utc_now () =
  let t = Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1) t.Unix.tm_mday
    t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec

let rec mkdir_p dir =
  if not (Sys.file_exists dir) then begin
    mkdir_p (Filename.dirname dir);
    try Unix.mkdir dir 0o755 with _ -> ()
  end

let jbool b = if b then "true" else "false"
let jstr s = "\"" ^ s ^ "\""

let write_file path content =
  mkdir_p (Filename.dirname path);
  let oc = open_out path in
  output_string oc content;
  close_out oc

let append_file path content =
  mkdir_p (Filename.dirname path);
  let oc = open_out_gen [ Open_append; Open_creat ] 0o644 path in
  output_string oc content;
  close_out oc

(* ---------- main --------------------------------------------------------- *)

let () =
  let now = utc_now () in

  (* One ss call; None means the probe itself failed -> treated as not bound. *)
  let listeners =
    let code, out = capture "ss" [ "-ltn" ] in
    if code = 0 then Some out else None
  in
  let probe_readable = listeners <> None in

  let p4100 = port_bound listeners 4100 in
  let p4101 = port_bound listeners 4101 in
  let p4200 = port_bound listeners 4200 in
  let p7447 = port_bound listeners 7447 in

  let routes = [ "/"; "/core-evo"; "/api/v1/core-evo/status"; "/links"; "/wiki"; "/zk" ] in
  let route_results = List.map (fun r -> (r, route_ok r)) routes in
  let routes_ok = List.length (List.filter snd route_results) in
  let routes_total = List.length routes in

  let cockpit_up = unit_active cockpit_unit in
  let cockpit_failed = unit_failed cockpit_unit in
  let deep_ok, deep_bytes = deep_health () in
  let ha = ha_receipt_state 300.0 in

  (* Degradation: the cockpit's own sockets or routes, or an unreadable probe.
     The HA receipt is advisory until the in-BEAM publisher ships. *)
  let listeners_healthy = p4100 && p4101 && p4200 && p7447 in
  let routes_healthy = routes_ok = routes_total in
  (* REVIEW FIX (Pi+Argon finding 1, HIGH): deep semantic health joins the
     verdict, so a wedged BEAM serving shallow 200s is no longer healthy. *)
  let degraded =
    (not probe_readable) || (not listeners_healthy) || (not routes_healthy)
    || (not deep_ok)
  in

  (* Bounded recovery: only when the unit is genuinely inactive, at most once.
     Recovery lives HERE, outside the BEAM — that is the whole point. *)
  (* REVIEW FIX (Pi+Argon finding 2, HIGH): the original single `start` was a
     no-op against the two states that matter most.
       (a) unit `failed`   -> rate-limited by Restart=always; reset-failed first
       (b) unit `inactive` -> plain start
       (c) unit `active` but routes/deep health bad -> WEDGED; `start` does
           nothing here, so a restart is required.
     Still at most one bounded action per tick. *)
  let recovery_attempted = ref false in
  let recovery_result = ref "not_required" in
  if max_recovery_attempts > 0 then begin
    if cockpit_failed then begin
      recovery_attempted := true;
      let _ = capture ~secs:15 "systemctl" [ "--user"; "reset-failed"; cockpit_unit ] in
      let code, _ = capture ~secs:30 "systemctl" [ "--user"; "start"; cockpit_unit ] in
      recovery_result := if code = 0 then "reset_failed_then_start" else "reset_failed_start_failed"
    end else if not cockpit_up then begin
      recovery_attempted := true;
      let code, _ = capture ~secs:30 "systemctl" [ "--user"; "start"; cockpit_unit ] in
      recovery_result := if code = 0 then "start_issued" else "start_failed"
    end else if (not routes_healthy) || (not deep_ok) then begin
      recovery_attempted := true;
      let code, _ = capture ~secs:60 "systemctl" [ "--user"; "restart"; cockpit_unit ] in
      recovery_result := if code = 0 then "restart_issued_wedged" else "restart_failed_wedged"
    end
  end;

  let ha_str =
    match ha with
    | Absent -> "absent"
    | Stale a -> Printf.sprintf "stale_%.0fs" a
    | Fresh a -> Printf.sprintf "fresh_%.0fs" a
  in

  let routes_json =
    String.concat ","
      (List.map (fun (r, ok) -> Printf.sprintf "{\"path\":%s,\"ok\":%s}" (jstr r) (jbool ok))
         route_results)
  in

  let receipt =
    Printf.sprintf
      "{\n\
      \  \"schema\": \"uos.web-watchdog.v1\",\n\
      \  \"observed_utc\": %s,\n\
      \  \"fate_domain\": \"hostSystemd\",\n\
      \  \"protected_domain\": \"cockpitBeam\",\n\
      \  \"twin\": \"formal/lean/UosCoreEvoUnifiedDigitalTwin.lean\",\n\
      \  \"probe_readable\": %s,\n\
      \  \"listeners\": {\"4100\": %s, \"4101\": %s, \"4200\": %s, \"7447\": %s},\n\
      \  \"routes_ok\": %d,\n\
      \  \"routes_total\": %d,\n\
      \  \"routes\": [%s],\n\
      \  \"cockpit_unit_active\": %s,\n\
      \  \"cockpit_unit_failed\": %s,\n\
      \  \"deep_health_ok\": %s,\n\
      \  \"deep_health_bytes\": %d,\n\
      \  \"ha_receipt\": %s,\n\
      \  \"recovery_attempted\": %s,\n\
      \  \"recovery_result\": %s,\n\
      \  \"status\": %s,\n\
      \  \"admitted_ev_ceiling\": 93,\n\
      \  \"admission\": \"NOT_GRANTED_BY_WATCHDOG_OBSERVATION\"\n\
      }\n"
      (jstr now) (jbool probe_readable)
      (jbool p4100) (jbool p4101) (jbool p4200) (jbool p7447)
      routes_ok routes_total routes_json
      (jbool cockpit_up) (jbool cockpit_failed) (jbool deep_ok) deep_bytes (jstr ha_str)
      (jbool !recovery_attempted) (jstr !recovery_result)
      (jstr (if degraded then "degraded" else "healthy"))
  in

  let base = Filename.concat uos_root "var/watchdog" in
  write_file (Filename.concat base "latest.json") receipt;

  if degraded then begin
    let andon =
      Printf.sprintf
        "{\"schema\":\"uos.andon.v1\",\"utc\":%s,\"source\":\"uos-web-watchdog\",\
         \"topic\":\"indrajaal/l0/const/andon/halt\",\"published_to_zenoh\":false,\
         \"reason\":\"cockpit plane degraded\",\"listeners_healthy\":%s,\
         \"routes_ok\":%d,\"routes_total\":%d,\"cockpit_unit_active\":%s,\
         \"recovery_result\":%s}\n"
        (jstr now) (jbool listeners_healthy) routes_ok routes_total
        (jbool cockpit_up) (jstr !recovery_result)
    in
    append_file (Filename.concat base "andon.jsonl") andon;
    prerr_endline ("[ANDON] uos-web-watchdog: plane degraded at " ^ now);
    print_string receipt;
    exit 1
  end else begin
    print_string receipt;
    exit 0
  end
