open Lmstudio_dashboard_web

let failures = ref 0

let check name condition =
  if condition then Printf.printf "PASS %s\n" name
  else begin incr failures; Printf.printf "FAIL %s\n" name end

let contains text fragment =
  let n = String.length text and m = String.length fragment in
  let rec loop i =
    i + m <= n && (String.sub text i m = fragment || loop (i + 1))
  in
  m = 0 || loop 0

let count_occurrences text fragment =
  let n = String.length text and m = String.length fragment in
  let rec loop index count =
    if index + m > n then count
    else if String.sub text index m = fragment then
      loop (index + m) (count + 1)
    else loop (index + 1) count
  in
  if m = 0 then 0 else loop 0 0

let () =
  let programme : Lmstudio_dashboard_web.programme_summary =
    { registered_nodes = 83; total_nodes = 83; tasks_ready = 1;
      tasks_waiting = 80;
      tasks_executing = 2; tasks_completed = 0;
      lifecycle_projection_running = true; recovery_projection_jobs = 1 }
  in
  let snapshot =
    Lmstudio_dashboard_web.make_snapshot
      ~public_url:"http://vm-1.tail55d152.ts.net:9501"
      ~timestamp:"20260812-2152" ~programme
      ~bridge:(partial "Task 1A blocks admission")
      ~fpp:(partial "normative-window correction in progress")
      ~formal:(unavailable_observed "real bounded solver receipt pending")
      ~browser:(unavailable_observed "typed navigation timed out")
      ~canonical_bridge_calls:0 ~residual_direct_calls:2
      ~knowledge_artifacts:5
  in
  let html =
    Lmstudio_dashboard_web.render_dashboard snapshot
      [ ("20260812-2152", "<script>alert(1)</script>", "Score: 0.4", "advice") ]
  in
  check "valid Tailscale snapshot is admitted"
    (Lmstudio_dashboard_web.validate_snapshot snapshot = []);
  List.iter
    (fun heading -> check ("section " ^ heading) (contains html heading))
    [ "Overview"; "Runs"; "Admission"; "Effects"; "Verification";
      "Predictive"; "Knowledge"; "UI quality" ];
  check "durable denominator is rendered" (contains html "83 / 83");
  check "current-head and exact-intelligence receipts are rendered"
    (contains html "full safety carrier 82/82"
     && contains html "exact five-action graph and lossless ordered MBSE projection 177/177"
     && contains html "Rete dispatch 21/21, analysis 34/34, and live six-gate assurance 45/45"
     && contains html "duplicate convergence 74/74; cache-authorization review remains open");
  check "mandatory timestamp is rendered" (contains html "20260812-2152");
  check "status is explicit" (contains html "Unavailable observed");
  check "accessible document and table semantics are rendered"
    (contains html "lang=\"en\"" && contains html "<caption>"
     && contains html "role=\"rowheader\"");
  check "every dashboard status/state row has row-header semantics"
    (count_occurrences html "role=\"rowheader\"" >= 12
     && count_occurrences html "<caption>" >= 4);
  check "structural validity is not mislabeled evidence verification"
    (contains html "Snapshot schema: Valid"
     && not (contains html "Snapshot validation: Verified"));
  check "prediction identifies the current partial instead of a stale task"
    (contains html
       "Next measurement: resolve the current FPP / MBSE partial"
     && contains html "normative-window correction in progress"
     && not (contains html "close Task 1A"));
  check "untrusted history is escaped"
    (contains html "&lt;script&gt;alert(1)&lt;/script&gt;"
     && not (contains html "<script>alert(1)</script>"));
  check "no forbidden URL is generated"
    (not (contains html "localhost") && not (contains html "127.0.0.1")
     && not (contains html "0.0.0.0"));
  check "stylesheet is a same-origin Tailscale FQDN resource"
    (contains html
       "href=\"http://vm-1.tail55d152.ts.net:9501/dashboard.css\""
     && contains Lmstudio_dashboard_web.dashboard_style "@media"
     && not (contains Lmstudio_dashboard_web.dashboard_style "url("));
  let invalid =
    Lmstudio_dashboard_web.make_snapshot
      ~public_url:"http://127.0.0.1:9501" ~timestamp:"20260812-2152"
      ~programme ~bridge:(partial "not a receipt")
      ~fpp:(partial "not a receipt") ~formal:(partial "not a receipt")
      ~browser:(partial "not a receipt")
      ~canonical_bridge_calls:1 ~residual_direct_calls:0
      ~knowledge_artifacts:5
  in
  check "raw IP URL is rejected"
    (Lmstudio_dashboard_web.validate_snapshot invalid <> []
     && Lmstudio_dashboard_web.validate_public_url
          "http://127.0.0.1:9501" |> Result.is_error
     && Lmstudio_dashboard_web.validate_public_url
          "http://vm-1.tail55d152.ts.net:9501" = Ok ());
  check "hostile FQDN carriers are rejected before URL composition"
    (List.for_all
       (fun value ->
         Lmstudio_dashboard_web.validate_tailscale_fqdn value
         |> Result.is_error)
       [ "vm.ts.net/path"; "vm.ts.net:1234"; ".ts.net";
         "-vm.tail.ts.net"; "vm..tail.ts.net"; "http://vm.tail.ts.net" ]
     && Lmstudio_dashboard_web.validate_tailscale_fqdn
          "vm-1.tail55d152.ts.net" = Ok ());
  let history_db = Sqlite3.db_open ":memory:" in
  check "missing history schema is a typed error"
    (Lmstudio_dashboard_web.get_recent_history history_db |> Result.is_error);
  ignore
    (Sqlite3.exec history_db
       "CREATE TABLE lmstudio_history (id INTEGER PRIMARY KEY, timestamp TEXT, vector_space TEXT, evaluation_score REAL, interpretation TEXT, oracle_advice TEXT)");
  ignore
    (Sqlite3.exec history_db
       "INSERT INTO lmstudio_history VALUES (1, '20260812-2152', 'space', 0.5, 'interpretation', 'stored oracle')");
  check "stored Oracle advice is retained by the bounded history reader"
    (match Lmstudio_dashboard_web.get_recent_history history_db with
     | Ok [ (_, _, _, "stored oracle") ] -> true
     | _ -> false);
  ignore (Sqlite3.exec history_db "DELETE FROM lmstudio_history");
  let oversized = String.make 4097 'x' in
  let statement =
    Sqlite3.prepare history_db
      "INSERT INTO lmstudio_history VALUES (2, ?, 'space', 0.5, 'interpretation', 'oracle')"
  in
  ignore (Sqlite3.bind statement 1 (Sqlite3.Data.TEXT oversized));
  ignore (Sqlite3.step statement); ignore (Sqlite3.finalize statement);
  check "oversized database text is refused"
    (Lmstudio_dashboard_web.get_recent_history history_db |> Result.is_error);
  ignore (Sqlite3.db_close history_db);
  check "raising snapshot provider becomes a typed refusal"
    (Lmstudio_dashboard_web.observe_snapshot
       (fun () -> failwith "fault-injected snapshot provider")
     |> Result.is_error);
  check "DREAM_PORT is injectable and bounded"
    (Lmstudio_dashboard_web.port_from_environment
       ~getenv:(fun _ -> Some "9501") = Ok 9501
     && Lmstudio_dashboard_web.port_from_environment
          ~getenv:(fun _ -> Some "70000") |> Result.is_error
     && Lmstudio_dashboard_web.port_from_environment
          ~getenv:(fun _ -> Some "not-a-port") |> Result.is_error
     && Lmstudio_dashboard_web.port_from_environment
          ~getenv:(fun _ -> None) |> Result.is_error);
  check "request surface rejects unknown paths and methods"
    (Lmstudio_dashboard_web.resolve_request ~method_name:"GET" ~target:"/"
       = Dashboard
     && Lmstudio_dashboard_web.resolve_request ~method_name:"GET"
          ~target:"/unknown" = Not_found
     && Lmstudio_dashboard_web.resolve_request ~method_name:"HEAD" ~target:"/"
          = Dashboard
     && Lmstudio_dashboard_web.resolve_request ~method_name:"GET"
          ~target:"/dashboard.css" = Dashboard_style
     && Lmstudio_dashboard_web.resolve_request ~method_name:"POST" ~target:"/"
          = Method_not_allowed);
  let total = 28 in
  let observation =
    Suite_telemetry.observe ~suite:"test_lmstudio_dashboard_web"
      ~passed:(total - !failures) ~failed:!failures ~skipped:0
  in
  print_string
    (Suite_telemetry.emit observation
       ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code observation)
