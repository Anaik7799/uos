open Phase0_programme

let check name f =
  match f () with
  | true -> Printf.printf "PASS %s\n" name; true
  | false -> Printf.printf "FAIL %s\n" name; false
  | exception exn -> Printf.printf "FAIL %s (%s)\n" name (Printexc.to_string exn); false

let () =
  let p = ref 0 and f = ref 0 in
  let run name fn = if check name fn then incr p else incr f in

  run "validates exactly 17 nodes and acyclic order" (fun () ->
    match validate () with
    | Ok () -> true
    | Error _ -> false
  );

  run "ready_to_apply is false while pending" (fun () ->
    not (ready_to_apply ())
  );

  run "MUT-P0-INFER-PUBLISHED is killed" (fun () ->
    not (ready_to_apply ())
  );

  run "MUT-P0-BYPASS-REVIEW is killed" (fun () ->
    let p02 = List.find (fun t -> t.id = "SE.P0.2") tasks in
    List.mem "SE.P0.1" p02.dependencies
  );

  Printf.printf "test_phase0_programme: %d passed, %d failed\n" !p !f;
  let self = Suite_telemetry.observe ~suite:"test_phase0_programme" ~passed:!p ~failed:!f ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.agent_time_hook; Stanza.run_swarm_bridge_programme ]);
  exit (Suite_telemetry.exit_code self)