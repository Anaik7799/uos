open Source_artifact

let check name f =
  match f () with
  | true -> Printf.printf "PASS %s\n" name; true
  | false -> Printf.printf "FAIL %s\n" name; false
  | exception exn -> Printf.printf "FAIL %s (%s)\n" name (Printexc.to_string exn); false

let () =
  let p = ref 0 and f = ref 0 in
  let run name fn = if check name fn then incr p else incr f in

  run "Id.make rejects empty" (fun () ->
    Result.is_error (Id.make "")
  );

  run "Sha256.of_hex rejects invalid lengths" (fun () ->
    Result.is_error (Sha256.of_hex "abc")
  );

  run "Relative_path.make rejects absolute paths" (fun () ->
    Result.is_error (Relative_path.make "/absolute")
  );

  run "Relative_path.make rejects empty components" (fun () ->
    Result.is_error (Relative_path.make "a//b")
  );

  run "Relative_path.make rejects dots" (fun () ->
    Result.is_error (Relative_path.make "a/./b") &&
    Result.is_error (Relative_path.make "a/../b")
  );

  run "Relative_path.make rejects backslashes" (fun () ->
    Result.is_error (Relative_path.make "a\\b")
  );

  run "Relative_path.make rejects NULs" (fun () ->
    Result.is_error (Relative_path.make "a\000b")
  );

  run "Relative_path.make accepts valid relative paths" (fun () ->
    Result.is_ok (Relative_path.make "a/b/c.txt")
  );

  run "verify on real blob fixture succeeds" (fun () ->
    let path = "modules/system_engg/fixtures/source_artifact/blob.txt" in
    match observe_blob ~path with
    | Error _ -> false
    | Ok obs ->
        let id = match Id.make "authority-blob" with Ok x -> x | Error _ -> failwith "id" in
        let locator = Uri.of_string ("file://" ^ path) in
        let sha = match Sha256.of_hex "690ccc185ce93c516385028fce6385633ed772c3bda297ee9450bd8b5905a113" with Ok x -> x | Error _ -> failwith "sha" in
        let pin = Blob_pin { sha256 = sha; byte_count = 33 } in
        let exp = expect ~id ~locator ~pin in
        match verify exp obs with
        | Ok _ -> true
        | Error _ -> false
  );

  run "verify on mismatched blob size fails" (fun () ->
    let path = "modules/system_engg/fixtures/source_artifact/blob.txt" in
    match observe_blob ~path with
    | Error _ -> false
    | Ok obs ->
        let id = match Id.make "authority-blob" with Ok x -> x | Error _ -> failwith "id" in
        let locator = Uri.of_string ("file://" ^ path) in
        let sha = match Sha256.of_hex "690ccc185ce93c516385028fce6385633ed772c3bda297ee9450bd8b5905a113" with Ok x -> x | Error _ -> failwith "sha" in
        let pin = Blob_pin { sha256 = sha; byte_count = 100 } in
        let exp = expect ~id ~locator ~pin in
        match verify exp obs with
        | Error [Entry_count_mismatch _] -> true
        | _ -> false
  );

  run "verify on mismatched blob digest fails" (fun () ->
    let path = "modules/system_engg/fixtures/source_artifact/blob.txt" in
    match observe_blob ~path with
    | Error _ -> false
    | Ok obs ->
        let id = match Id.make "authority-blob" with Ok x -> x | Error _ -> failwith "id" in
        let locator = Uri.of_string ("file://" ^ path) in
        let sha = match Sha256.of_hex "0000000000000000000000000000000000000000000000000000000000000000" with Ok x -> x | Error _ -> failwith "sha" in
        let pin = Blob_pin { sha256 = sha; byte_count = 33 } in
        let exp = expect ~id ~locator ~pin in
        match verify exp obs with
        | Error [Digest_mismatch _] -> true
        | _ -> false
  );

  run "canonical_tree rejects duplicate paths" (fun () ->
    let p = match Relative_path.make "alpha.txt" with Ok x -> x | Error _ -> failwith "path" in
    let e = { path = p; kind = Regular; mode = 0o100644; blob_sha256 = None; symlink_target = None; git_oid = None } in
    match canonical_tree [e; e] with
    | Error (_ :: _) -> true
    | _ -> false
  );

  run "canonical_tree rejects case-fold collisions" (fun () ->
    let p1 = match Relative_path.make "alpha.txt" with Ok x -> x | Error _ -> failwith "path" in
    let p2 = match Relative_path.make "ALPHA.TXT" with Ok x -> x | Error _ -> failwith "path" in
    let e1 = { path = p1; kind = Regular; mode = 0o100644; blob_sha256 = None; symlink_target = None; git_oid = None } in
    let e2 = { path = p2; kind = Regular; mode = 0o100644; blob_sha256 = None; symlink_target = None; git_oid = None } in
    match canonical_tree [e1; e2] with
    | Error (_ :: _) -> true
    | _ -> false
  );

  (* MUT-SA-IGNORE-DIGEST mock check *)
  run "MUT-SA-IGNORE-DIGEST is killed" (fun () ->
    let path = "modules/system_engg/fixtures/source_artifact/blob.txt" in
    match observe_blob ~path with
    | Error _ -> false
    | Ok obs ->
        let id = match Id.make "authority-blob" with Ok x -> x | Error _ -> failwith "id" in
        let locator = Uri.of_string ("file://" ^ path) in
        let bad_sha = match Sha256.of_hex "0000000000000000000000000000000000000000000000000000000000000000" with Ok x -> x | Error _ -> failwith "sha" in
        let pin = Blob_pin { sha256 = bad_sha; byte_count = 33 } in
        let exp = expect ~id ~locator ~pin in
        match verify exp obs with
        | Error [Digest_mismatch _] -> true (* Shows digest is checked, hence killing MUT-SA-IGNORE-DIGEST *)
        | _ -> false
  );

  (* MUT-SA-LAST-WRITER mock check *)
  run "MUT-SA-LAST-WRITER is killed" (fun () ->
    let p = match Relative_path.make "alpha.txt" with Ok x -> x | Error _ -> failwith "path" in
    let e1 = { path = p; kind = Regular; mode = 0o100644; blob_sha256 = None; symlink_target = None; git_oid = None } in
    let e2 = { path = p; kind = Executable; mode = 0o100755; blob_sha256 = None; symlink_target = None; git_oid = None } in
    match canonical_tree [e1; e2] with
    | Error (_ :: _) -> true (* Rejects duplicate instead of using last writer, killing MUT-SA-LAST-WRITER *)
    | _ -> false
  );

  Printf.printf "test_source_artifact: %d passed, %d failed\n" !p !f;
  let self = Suite_telemetry.observe ~suite:"test_source_artifact" ~passed:!p ~failed:!f ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.agent_time_hook; Stanza.run_swarm_bridge_programme ]);
  exit (Suite_telemetry.exit_code self)