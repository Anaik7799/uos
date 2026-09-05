let () =
  let open Fractal_parity in
  let chain =
    List.init 7 (fun index ->
      { id = "n" ^ string_of_int index; level = level_of_int index;
        parent = if index = 0 then None else Some ("n" ^ string_of_int (index - 1));
        label = "node"; source_anchor = "README.md" })
  in
  assert (validate chain = Ok ());
  let evidence = [ { node_id = "n6"; snapshot_digest = "snapshot"; check = "parity"; passed = true } ] in
  assert (status ~snapshot_digest:"snapshot" chain evidence "n0" = Verified);
  assert (status ~snapshot_digest:"other" chain evidence "n0" = Unmapped)

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_fractal_parity" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_fractal_parity ]);
  exit (Suite_telemetry.exit_code self)
