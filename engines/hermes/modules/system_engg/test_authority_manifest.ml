open Authority_manifest
open Authority_catalog
open Authority_lock

let check name f =
  match f () with
  | true -> Printf.printf "PASS %s\n" name; true
  | false -> Printf.printf "FAIL %s\n" name; false
  | exception exn -> Printf.printf "FAIL %s (%s)\n" name (Printexc.to_string exn); false

let () =
  let p = ref 0 and f = ref 0 in
  let run name fn = if check name fn then incr p else incr f in

  run "Catalogs and denominators exist" (fun () ->
    String.length opense_cookbook_denominator.expected_digest = 40 &&
    String.length opencaesar_denominator.expected_digest = 64
  );

  run "Manifest builds with exactly 28 rows" (fun () ->
    match make_catalog_manifest () with
    | Error _ -> false
    | Ok manifest ->
        List.length (entries manifest) = 28
  );

  run "Readiness fails when core is unavailable" (fun () ->
    match make_catalog_manifest () with
    | Error _ -> false
    | Ok manifest ->
        match authority_ready manifest with
        | Error _ -> true (* Readiness must fail since core is unavailable *)
        | Ok () -> false
  );

  run "Authority digest is stable" (fun () ->
    match make_catalog_manifest () with
    | Error _ -> false
    | Ok m1 ->
        match make_catalog_manifest () with
        | Error _ -> false
        | Ok m2 ->
            Source_artifact.Sha256.equal (digest m1) (digest m2)
  );

  run "Yojson canonical locking roundtrip" (fun () ->
    let dummy_sha = match Source_artifact.Sha256.of_hex "690ccc185ce93c516385028fce6385633ed772c3bda297ee9450bd8b5905a113" with Ok x -> x | Error _ -> failwith "sha" in
    let dummy_id = match Source_artifact.Id.make "row-01" with Ok x -> x | Error _ -> failwith "id" in
    let entry = {
      manifest_digest = dummy_sha;
      authority_id = dummy_id;
      resolved_revision = Some "commit-sha";
      content_digest = Some dummy_sha;
      license_policy_digest = dummy_sha;
      status = Admitted;
      reason = None;
    } in
    let json = encode_canonical [entry] in
    match decode_strict json with
    | Ok [decoded] ->
        Source_artifact.Sha256.equal decoded.manifest_digest entry.manifest_digest &&
        String.equal (Source_artifact.Id.to_string decoded.authority_id) (Source_artifact.Id.to_string entry.authority_id) &&
        decoded.status = entry.status
    | _ -> false
  );

  Printf.printf "test_authority_manifest: %d passed, %d failed\n" !p !f;
  let self = Suite_telemetry.observe ~suite:"test_authority_manifest" ~passed:!p ~failed:!f ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.agent_time_hook; Stanza.run_swarm_bridge_programme ]);
  exit (Suite_telemetry.exit_code self)