let passed = ref 0
let failed = ref 0
let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn -> incr failed; Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let () =
  check "F1 two negated laws Unsat plus Sat control is proved" (fun () ->
      Ops_governance_formal.validate_output "unsat\nunsat\nsat\n" = Proved);
  check "F2 a satisfiable theorem negation is a real refutation" (fun () ->
      match Ops_governance_formal.validate_output "sat\nunsat\nsat\n" with Refuted _ -> true | _ -> false);
  check "F3 a dead Unsat control is rejected as vacuous" (fun () ->
      match Ops_governance_formal.validate_output "unsat\nunsat\nunsat\n" with Refuted _ -> true | _ -> false);
  check "F4 malformed or missing solver output is unavailable" (fun () ->
      match Ops_governance_formal.validate_output "garbage\n" with Unavailable _ -> true | _ -> false);
  check "F5 live Z3 discharges the generated governance algebra" (fun () ->
      match Ops_governance_formal.run () with
      | Proved -> true
      | Refuted detail -> Printf.printf "  live refutation: %s\n" detail; false
      | Unavailable detail -> Printf.printf "  unavailable: %s\n" detail; false);
  check "F6 the generated proof participates in the canonical formal gate" (fun () ->
      let report = Ops_formal.run ~only:"governance-z3" () in
      report.discharged = 1 && report.refuted = 0 && report.unavailable = 0);

  Printf.printf "ops_governance_formal: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_governance_formal" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)
