let passed = ref 0
let failed = ref 0

let check name predicate =
  if predicate () then (incr passed; Printf.printf "PASS %s\n" name)
  else (incr failed; Printf.eprintf "FAIL %s\n" name)

let () =
  List.iter
    (fun law ->
      check ("EA-FORMAL " ^ External_access.law_id law)
        (fun () -> External_access.prove_finite law))
    External_access.laws;
  check "EA-FORMAL-NONVACUITY every law has a killed mutant" (fun () ->
      List.length External_access.laws = List.length External_access.mutants
      && List.for_all External_access.mutant_is_killed External_access.mutants);
  check "EA-FORMAL-LIFECYCLE execution cannot precede admission" (fun () ->
      External_access.lifecycle_reachability_gaps () = []);
  check "EA-FORMAL-CREDIT evidence cannot escalate" (fun () ->
      External_access.credit_non_escalation_gaps () = []);
  let self =
    Suite_telemetry.observe ~suite:"test_external_access_formal"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  Printf.printf "SUMMARY %d passed, %d failed, 0 skipped\n" !passed !failed;
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability ]);
  exit (Suite_telemetry.exit_code self)
