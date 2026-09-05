let () =
  let outcomes =
    [ !(Jj_source_manifest_cases.outcome);
      !(Jj_secret_receipt_cases.outcome);
      !(Jj_readback_cases.outcome) ]
  in
  let passed = List.fold_left (fun total (value, _) -> total + value) 0 outcomes in
  let failed = List.fold_left (fun total (_, value) -> total + value) 0 outcomes in
  let self =
    Suite_telemetry.observe ~suite:"test_jj_receipt" ~passed ~failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vcs ]);
  exit (Suite_telemetry.exit_code self)
