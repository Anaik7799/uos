let exec db sql =
  match Sqlite3.exec db sql with
  | rc when Sqlite3.Rc.is_success rc -> ()
  | rc ->
      failwith
        (Printf.sprintf "sqlite fixture failed: %s: %s" (Sqlite3.Rc.to_string rc)
           (Sqlite3.errmsg db))

let contains text fragment =
  let text_length = String.length text and fragment_length = String.length fragment in
  let rec search offset =
    offset + fragment_length <= text_length
    &&
    (String.sub text offset fragment_length = fragment || search (offset + 1))
  in
  fragment_length = 0 || search 0

let schema =
  {|
CREATE TABLE source_snapshot (
  id INTEGER PRIMARY KEY,
  digest TEXT NOT NULL,
  entry_count INTEGER NOT NULL,
  recorded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE parity_scenario (
  snapshot_digest TEXT NOT NULL,
  id TEXT NOT NULL,
  feature_id TEXT NOT NULL,
  contract_id TEXT NOT NULL,
  fixture_digest TEXT NOT NULL,
  reference_digest TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, id)
);
CREATE TABLE parity_trace_pair (
  snapshot_digest TEXT NOT NULL,
  scenario_id TEXT NOT NULL,
  trace_id TEXT NOT NULL,
  reference_trace TEXT NOT NULL,
  candidate_trace TEXT NOT NULL,
  normalization_version TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, scenario_id, trace_id)
);
CREATE TABLE parity_verification (
  snapshot_digest TEXT NOT NULL,
  scenario_id TEXT NOT NULL,
  trace_id TEXT NOT NULL,
  verifier TEXT NOT NULL,
  harness_revision TEXT NOT NULL,
  check_name TEXT NOT NULL,
  passed INTEGER NOT NULL,
  evidence_digest TEXT NOT NULL,
  PRIMARY KEY(snapshot_digest, scenario_id, trace_id, verifier, harness_revision, check_name)
);
|}

let with_fixture f =
  let source_path = Filename.temp_file "hermes-import-source" ".sqlite3" in
  let target_path = Filename.temp_file "hermes-import-target" ".sqlite3" in
  Fun.protect
    ~finally:(fun () ->
      List.iter
        (fun path -> if Sys.file_exists path then Sys.remove path)
        [ source_path; target_path ])
    (fun () ->
      let source = Sqlite3.db_open source_path in
      let target = Sqlite3.db_open target_path in
      Fun.protect
        ~finally:(fun () ->
          ignore (Sqlite3.db_close source);
          ignore (Sqlite3.db_close target))
        (fun () ->
          exec source schema;
          exec target schema;
          f ~source_path ~target_path ~source ~target))

let () =
  with_fixture (fun ~source_path ~target_path ~source ~target ->
    let digest = String.make 64 'a' in
    let scenario id feature =
      Printf.sprintf
        "INSERT INTO parity_scenario VALUES ('%s','%s','%s','contract','fixture-%s','reference-%s');"
        digest id feature id id
    in
    exec source
      (Printf.sprintf "INSERT INTO source_snapshot(digest,entry_count) VALUES ('%s',8556);" digest);
    exec source (scenario "shared" "agent_loop");
    exec source (scenario "source-only" "tool_execution");
    exec target (scenario "shared" "agent_loop");
    exec source
      (Printf.sprintf
        "INSERT INTO parity_trace_pair VALUES ('%s','source-only','trace-1','reference','candidate','v1');"
        digest);
    exec source
      (Printf.sprintf
        "INSERT INTO parity_verification VALUES ('%s','source-only','trace-1','parity-v1','rev-1','equal',0,'evidence');"
        digest);
    match Evidence_import.analyze ~source_path ~target_path with
    | Error diagnostic -> failwith diagnostic
    | Ok plan ->
        let source_store_digest = plan.source_store_digest in
        let target_store_digest = plan.target_store_digest in
        let plan_digest = plan.plan_digest in
        assert (plan.snapshot_digest = Some digest);
        assert (plan.source_entry_count = Some 8556);
        assert (plan.scenarios.source_rows = 2);
        assert (plan.scenarios.target_rows = 1);
        assert (plan.scenarios.missing_from_target = 1);
        assert (plan.traces.missing_from_target = 1);
        assert (plan.verifications.missing_from_target = 1);
        assert (plan.source_passed = 0);
        assert (plan.source_failed = 1);
        assert (Evidence_import.admissible plan);
        let rendered = Evidence_import.render plan in
        assert (contains rendered ("plan_digest: " ^ plan.plan_digest));
        assert
          (contains rendered
             "source_historical_verdicts: 0 passed, 1 failed");
        assert (contains rendered "decision: PLANNER_ADMISSIBLE");
        exec source
          "UPDATE parity_scenario SET feature_id='changed-payload' WHERE id='source-only';";
        (match Evidence_import.analyze ~source_path ~target_path with
        | Error diagnostic -> failwith diagnostic
        | Ok changed ->
            assert (changed.source_store_digest <> source_store_digest);
            assert (changed.target_store_digest = target_store_digest);
            assert (changed.plan_digest <> plan_digest)));
  with_fixture (fun ~source_path ~target_path ~source ~target ->
    let digest = String.make 64 'b' in
    exec source
      (Printf.sprintf
        "INSERT INTO source_snapshot(digest,entry_count) VALUES ('%s',1);"
        digest);
    exec source
      (Printf.sprintf
        "INSERT INTO parity_scenario VALUES ('%s','shared','agent_loop','contract','fixture','reference');"
        digest);
    exec target
      (Printf.sprintf
        "INSERT INTO parity_scenario VALUES ('%s','shared','tool_execution','contract','fixture','reference');"
        digest);
    match Evidence_import.analyze ~source_path ~target_path with
    | Error diagnostic -> failwith diagnostic
    | Ok plan ->
        assert (plan.scenarios.conflicts = 1);
        assert (not (Evidence_import.admissible plan)));
  with_fixture (fun ~source_path ~target_path ~source ~target ->
    let digest = String.make 64 'c' in
    exec source
      (Printf.sprintf
        "INSERT INTO source_snapshot(digest,entry_count) VALUES ('%s',1);"
        digest);
    exec target "ALTER TABLE parity_scenario ADD COLUMN imported_note TEXT;";
    match Evidence_import.analyze ~source_path ~target_path with
    | Error diagnostic -> failwith diagnostic
    | Ok plan ->
        assert (not plan.schema_compatible);
        assert (not (Evidence_import.admissible plan)));
  with_fixture (fun ~source_path ~target_path ~source ~target:_ ->
    let digest = String.make 64 'd' in
    exec source
      (Printf.sprintf
        "INSERT INTO source_snapshot(digest,entry_count) VALUES ('%s',1);"
        digest);
    exec source
      (Printf.sprintf
        "INSERT INTO parity_scenario VALUES ('%s','bad-verdict','agent_loop','contract','fixture','reference');"
        digest);
    exec source
      (Printf.sprintf
        "INSERT INTO parity_trace_pair VALUES ('%s','bad-verdict','trace','reference','candidate','v1');"
        digest);
    exec source
      (Printf.sprintf
        "INSERT INTO parity_verification VALUES ('%s','bad-verdict','trace','parity-v1','rev','equal',2,'evidence');"
        digest);
    match Evidence_import.analyze ~source_path ~target_path with
    | Error _ -> ()
    | Ok _ -> failwith "malformed verification verdict was accepted");
  with_fixture (fun ~source_path ~target_path ~source ~target:_ ->
    let snapshot_digest = String.make 64 'e' in
    let row_digest = String.make 64 'f' in
    exec source
      (Printf.sprintf
        "INSERT INTO source_snapshot(digest,entry_count) VALUES ('%s',1);"
        snapshot_digest);
    exec source
      (Printf.sprintf
        "INSERT INTO parity_scenario VALUES ('%s','wrong-snapshot','agent_loop','contract','fixture','reference');"
        row_digest);
    match Evidence_import.analyze ~source_path ~target_path with
    | Error diagnostic -> failwith diagnostic
    | Ok plan -> assert (not (Evidence_import.admissible plan)));
  let self =
    Suite_telemetry.observe ~suite:"test_evidence_import" ~passed:7 ~failed:0
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_evidence_import ]);
  exit (Suite_telemetry.exit_code self)
