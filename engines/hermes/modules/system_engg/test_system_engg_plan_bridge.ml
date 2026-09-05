let check name f =
  match f () with
  | true -> Printf.printf "PASS %s\n" name; true
  | false -> Printf.printf "FAIL %s\n" name; false
  | exception exn -> Printf.printf "FAIL %s (%s)\n" name (Printexc.to_string exn); false

let () =
  let p = ref 0 and f = ref 0 in
  let run name fn = if check name fn then incr p else incr f in

  let db_path = "test_phase0_sa_plan.sqlite3" in
  if Sys.file_exists db_path then Sys.remove db_path;

  run "Exact replay is idempotent" (fun () ->
    match Sa_plan.Store.open_db db_path with
    | Error _ -> false
    | Ok db ->
      let nodes = List.map Phase0_programme.to_plan_node Phase0_programme.tasks in
      let r1 = Sa_plan.Store.register_plan db ~id:"system-engg/phase-0/v1" ~title:"Phase 0" ~nodes in
      let r2 = Sa_plan.Store.register_plan db ~id:"system-engg/phase-0/v1" ~title:"Phase 0" ~nodes in
      Sa_plan.Store.close db;
      Result.is_ok r1 && Result.is_ok r2
  );

  run "Changed dependency rejects" (fun () ->
    match Sa_plan.Store.open_db db_path with
    | Error _ -> false
    | Ok db ->
      let nodes = List.map Phase0_programme.to_plan_node Phase0_programme.tasks in
      let bad_nodes = match nodes with 
        | hd :: tl -> { hd with dependencies = ["BAD_DEP"] } :: tl
        | [] -> []
      in
      let r3 = Sa_plan.Store.register_plan db ~id:"system-engg/phase-0/v1" ~title:"Phase 0" ~nodes:bad_nodes in
      Sa_plan.Store.close db;
      Result.is_error r3
  );
  
  if Sys.file_exists db_path then Sys.remove db_path;

  Printf.printf "test_system_engg_plan_bridge: %d passed, %d failed\n" !p !f;
  let self = Suite_telemetry.observe ~suite:"test_system_engg_plan_bridge" ~passed:!p ~failed:!f ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.agent_time_hook; Stanza.run_swarm_bridge_programme ]);
  exit (Suite_telemetry.exit_code self)