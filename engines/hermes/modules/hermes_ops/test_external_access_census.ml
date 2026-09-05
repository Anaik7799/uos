let () =
  let synthetic =
    [ ("fixture/sqlite.ml", "let db = Sqlite3.db_open path");
      ("fixture/shell.ml", "let _ = Unix.system command");
      ("fixture/socket.ml", "let fd = Unix.socket domain kind proto");
      ("fixture/safe.ml", "let note = \"Sqlite3.db_open is documentation\"");
      ("fixture/comment-string.ml",
       "(* a comment may name \"(*\" and \"*)\" without changing nesting *)\nlet safe = true") ]
  in
  let synthetic_findings = External_access_census.inspect_sources synthetic in
  let negative_controls_pass =
    List.length synthetic_findings = 3
    && not (List.exists
              (fun finding ->
                List.mem finding.External_access_census.path
                  [ "fixture/safe.ml"; "fixture/comment-string.ml" ])
              synthetic_findings)
    && External_access_census.counts_by_rule synthetic_findings
       = [ External_access_census.{ rule = "R31-NETWORK-DIRECT"; count = 1 };
           { rule = "R31-SHELL-DIRECT"; count = 1 };
           { rule = "R31-SQLITE-DIRECT"; count = 1 } ]
  in
  let live = External_access_census.inspect_tree ~root:"modules" in
  List.iter
    (fun finding -> Printf.eprintf "BYPASS %s:%d %s\n"
        finding.External_access_census.path finding.line finding.rule)
    live;
  let passed = if negative_controls_pass then 1 else 0 in
  let failed = (if negative_controls_pass then 0 else 1) + (if live = [] then 0 else 1) in
  let self =
    Suite_telemetry.observe ~suite:"test_external_access_census"
      ~passed ~failed ~skipped:0
  in
  Printf.printf "CENSUS denominator=modules findings=%d\n" (List.length live);
  External_access_census.counts_by_rule live
  |> List.iter (fun (item : External_access_census.rule_count) ->
       Printf.printf "CENSUS-METRIC rule=%s count=%d\n" item.rule item.count);
  Printf.printf "SUMMARY %d passed, %d failed, 0 skipped\n" passed failed;
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
