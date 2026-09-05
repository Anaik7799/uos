open Dependability_process

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let () =
  let declaration =
    Dependability_process_test_protocol.unavailable_production_declaration ()
  in
  check "R31 production preparation refuses while registered target authority is absent"
    (match prepare declaration with
     | Error Missing_registered_target_authority -> true
     | Ok _ | Error _ -> false);
  check "R31 test fixtures are a finite closed capability set"
    (Dependability_process_test_protocol.all_fixtures
     = [ Dependability_process_test_protocol.Exit_zero;
         Exit_nonzero;
         Timeout;
         Signal;
         Output_bound ]);
  check "R31 a test fixture capability retains only its closed fixture identity"
    (List.for_all
       (fun fixture ->
          Dependability_process_test_protocol.fixture
            (Dependability_process_test_protocol.declare fixture)
          = fixture)
       Dependability_process_test_protocol.all_fixtures);
  check "R31 each fixture has one canonical non-command identity"
    (List.map Dependability_process_test_protocol.key
       Dependability_process_test_protocol.all_fixtures
     = [ "exit-zero"; "exit-nonzero"; "timeout"; "signal";
         "output-bound" ]);
  let self =
    Suite_telemetry.observe ~suite:"test_dependability_process" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_dependability_process ]);
  exit (Suite_telemetry.exit_code self)
