(* Unit cases for the candidate predicate. The differential fixtures (via the
   path_security adapter) are what PROVE faithfulness against the frozen pathlib
   behaviour; these guard the obvious cases and the tricky non-matches (..b, ./). *)

let () =
  let open Path_safety in
  assert (not (has_traversal_component "a/b"));
  assert (has_traversal_component "a/../b");
  assert (has_traversal_component "../a");
  assert (has_traversal_component "..");
  assert (has_traversal_component "/a/../b");
  assert (has_traversal_component "a/b/../..");
  (* not a traversal: "..b" is a name, "." is dropped, "//" collapses *)
  assert (not (has_traversal_component "a/..b"));
  assert (not (has_traversal_component "a/./b"));
  assert (not (has_traversal_component "a//b"));
  assert (not (has_traversal_component ""));
  assert (not (has_traversal_component "..../x"));
  print_endline "path_safety: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_path_safety" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_path_safety ]);
  exit (Suite_telemetry.exit_code self)
