(* Drift diagnosis over reconciliation output: each drift kind yields the right
   advice; a satisfied intent yields none; the fail-closed gate rejects a
   corrupted reconciliation (actual = desired yet marked drift); and the blocked
   path joins hazards to countermeasures through the rule engine's bindings. *)

let directive ~id ~target =
  Blueprint.
    { id; target; desired = Parity_algebra.Verified;
      intent = "a perfectly substantive intent for testing"; requires = [] }

let reconciled ~id ~target ~actual : Blueprint.reconciled =
  let d = directive ~id ~target in
  if actual = Parity_algebra.Verified then
    { directive = d; outcome = Blueprint.Satisfied; diagnostic = None }
  else
    { directive = d;
      outcome = Blueprint.Drift { desired = Parity_algebra.Verified; actual };
      diagnostic = None }

let () =
  let open Drift_rules in
  (* Satisfied-only: converged, no advice. *)
  (match diagnose [ reconciled ~id:"a" ~target:"hermes.x.a" ~actual:Parity_algebra.Verified ] with
  | Ok [] -> ()
  | Ok advice -> failwith (Printf.sprintf "expected no advice, got %d" (List.length advice))
  | Error e -> failwith e);

  (* Each drift kind yields its advice. *)
  (match
     diagnose
       [ reconciled ~id:"d" ~target:"hermes.x.d" ~actual:Parity_algebra.Divergent;
         reconciled ~id:"u" ~target:"hermes.x.u" ~actual:Parity_algebra.Unmapped;
         reconciled ~id:"b" ~target:"hermes.x.b" ~actual:Parity_algebra.Blocked ]
   with
  | Ok advice ->
      let find target = List.find (fun a -> a.target = target) advice in
      assert ((find "hermes.x.d").action = "fix-candidate");
      assert ((find "hermes.x.u").action = "capture-and-compare");
      let blocked = find "hermes.x.b" in
      assert (blocked.action = "apply-countermeasure" || blocked.action = "manual-countermeasure")
  | Error e -> failwith e);

  (* The fail-closed gate: an entry marked drift whose actual EQUALS its desired
     verdict is a corrupted reconciliation -- rejected, never diagnosed. *)
  let corrupted : Blueprint.reconciled =
    { directive = directive ~id:"c" ~target:"hermes.x.c";
      outcome =
        Blueprint.Drift { desired = Parity_algebra.Verified; actual = Parity_algebra.Verified };
      diagnostic = None }
  in
  (match diagnose [ corrupted ] with
  | Error _ -> ()
  | Ok _ -> failwith "a corrupted reconciliation must be rejected");
  print_endline "drift_rules: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_drift_rules" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_drift_rules ]);
  exit (Suite_telemetry.exit_code self)
