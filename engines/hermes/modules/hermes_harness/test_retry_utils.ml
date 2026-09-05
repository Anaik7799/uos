(* Unit cases for the deterministic branches. The differential fixtures (via the
   retry_after adapter) prove faithfulness against the frozen function; these
   guard the branches: None/bool, int/float (with negative clamp), numeric string
   (with trim and negative clamp), empty, and non-numeric non-date. *)

let () =
  let open Retry_utils in
  assert (parse_retry_after_seconds `Null = None);
  assert (parse_retry_after_seconds (`Bool true) = None);
  assert (parse_retry_after_seconds (`Bool false) = None);
  assert (parse_retry_after_seconds (`Int 5) = Some 5.0);
  assert (parse_retry_after_seconds (`Int (-3)) = Some 0.0);
  assert (parse_retry_after_seconds (`Float 5.5) = Some 5.5);
  assert (parse_retry_after_seconds (`Float (-2.0)) = Some 0.0);
  assert (parse_retry_after_seconds (`String "10") = Some 10.0);
  assert (parse_retry_after_seconds (`String "-2") = Some 0.0);
  assert (parse_retry_after_seconds (`String " 7 ") = Some 7.0);
  assert (parse_retry_after_seconds (`String "") = None);
  assert (parse_retry_after_seconds (`String "  ") = None);
  assert (parse_retry_after_seconds (`String "abc") = None);
  print_endline "retry_utils: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_retry_utils" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_retry_utils ]);
  exit (Suite_telemetry.exit_code self)
