let () =
  (* The inventory is part of the inner property/fuzz loops.  Hashing must
     remain available when the external sha256sum oracle is absent; otherwise
     thousands of process launches turn a bounded suite into a timeout. *)
  let saved_path = Sys.getenv_opt "PATH" in
  Unix.putenv "PATH" "";
  let in_process_digest = Inventory.sha256_string "abc" in
  Unix.putenv "PATH" (Option.value saved_path ~default:"");
  assert
    (in_process_digest
     = Ok "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  match Inventory.scan ~root:"modules/hermes_harness/fixtures/reference" with
  | Error message -> failwith message
  | Ok entries ->
      assert
        (List.map (fun (entry : Inventory.entry) -> entry.Inventory.path) entries
        = [ "agent/main.py"; "providers/openrouter.py"; "root.py" ]);
      assert
        (List.map (fun (entry : Inventory.entry) -> entry.Inventory.domain) entries
        = [ "agent"; "providers"; "root" ]);
      assert (String.length (Inventory.snapshot_digest entries) = 64);
      let summaries = Inventory.summarize entries in
      assert
        (List.map (fun (summary : Inventory.domain_summary) -> summary.Inventory.domain) summaries
        = [ "agent"; "providers"; "root" ]);
      assert
        (List.map (fun (summary : Inventory.domain_summary) -> summary.Inventory.file_count) summaries = [ 1; 1; 1 ])

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_inventory" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_inventory ]);
  exit (Suite_telemetry.exit_code self)
