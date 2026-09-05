let () =
  let outcomes =
    [ !(Jj_ontology_sysml_cases.outcome);
      !(Jj_algebra_fpp_cases.outcome);
      !(Jj_source_formal_cases.outcome) ]
  in
  let passed = List.fold_left (fun total (value, _) -> total + value) 0 outcomes in
  let failed = List.fold_left (fun total (_, value) -> total + value) 0 outcomes in
  let self =
    Suite_telemetry.observe ~suite:"test_jj_fractal_authority"
      ~passed ~failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vcs ]);
  exit (Suite_telemetry.exit_code self)
