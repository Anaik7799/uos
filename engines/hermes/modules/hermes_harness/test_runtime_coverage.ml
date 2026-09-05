let () =
  let open Runtime_coverage in
  let s =
    coverage ~executed:[ "agent/a.py"; "agent/b.py" ] ~anchors:[ "agent/a.py"; "agent/c.py" ]
  in
  assert (s.total = 2);
  assert (s.covered = 1);
  assert (percent s = 50);
  let status name = List.find (fun x -> x.anchor = name) s.statuses in
  assert (status "agent/a.py").covered;
  assert (not (status "agent/c.py").covered);

  (* Honesty: empty anchors is 0%, never a vacuous 100%. *)
  let empty = coverage ~executed:[] ~anchors:[] in
  assert (percent empty = 0);

  (* An executed file that is not an anchor does not inflate coverage. *)
  let s2 = coverage ~executed:[ "agent/x.py"; "agent/y.py" ] ~anchors:[ "agent/a.py" ] in
  assert (s2.covered = 0 && s2.total = 1);

  assert (String.length (describe s) > 0);
  print_endline "runtime_coverage: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_runtime_coverage" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_runtime_coverage ]);
  exit (Suite_telemetry.exit_code self)
