open Collateral_verifier

let check name f =
  match f () with
  | true -> Printf.printf "PASS %s\n" name; true
  | false -> Printf.printf "FAIL %s\n" name; false
  | exception exn -> Printf.printf "FAIL %s (%s)\n" name (Printexc.to_string exn); false

let () =
  let p = ref 0 and f = ref 0 in
  let run name fn = if check name fn then incr p else incr f in

  run "staging_root make on empty path fails" (fun () ->
    Result.is_error (staging_root ~project_root:"." "")
  );

  run "staging_root make on valid path succeeds" (fun () ->
    Result.is_ok (staging_root ~project_root:"." "state/tmp/acquire")
  );

  run "verify_one on missing authority ID fails" (fun () ->
    match Authority_catalog.make_catalog_manifest () with
    | Error _ -> false
    | Ok manifest ->
        match staging_root ~project_root:"." "state/tmp/acquire" with
        | Error _ -> false
        | Ok staged ->
            let aid = match Source_artifact.Id.make "missing-id" with Ok x -> x | Error _ -> failwith "id" in
            match verify_one ~manifest ~staged_root:staged ~authority_id:aid with
            | Error [Missing_member "missing-id"] -> true
            | _ -> false
  );

  Printf.printf "test_collateral_verifier: %d passed, %d failed\n" !p !f;
  let self = Suite_telemetry.observe ~suite:"test_collateral_verifier" ~passed:!p ~failed:!f ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.agent_time_hook; Stanza.run_swarm_bridge_programme ]);
  exit (Suite_telemetry.exit_code self)