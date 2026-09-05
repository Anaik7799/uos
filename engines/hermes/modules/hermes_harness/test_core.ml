let () =
  let open Core in
  assert (readiness [] = Pending);
  assert (readiness [ { name = "dune"; status = Passed } ] = Passed);
  assert
    (readiness [ { name = "dune"; status = Failed "missing" } ]
    = Failed "dune: missing");
  let checks =
    Bootstrap.classify ~root:"."
      ~which:(fun name -> if name = "dune" then Some "/bin/dune" else None)
      ~exists:(fun path -> path = "./external/hermes_source" || path = "./sa_plan/dune")
      ~openrouter_configured:false
  in
  assert (List.assoc "dune" checks = Passed);
  assert (List.assoc "cargo" checks = Failed "not found");
  assert (Bootstrap.reference_root "." = "./external/hermes_source")

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_core" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core ]);
  exit (Suite_telemetry.exit_code self)
