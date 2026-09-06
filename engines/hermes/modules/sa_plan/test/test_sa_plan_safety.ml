module Safety = Sa_plan_safety

let require law condition =
  if condition then Printf.printf "ok %s\n%!" law
  else (
    prerr_endline ("FAIL " ^ law);
    exit 1)

let packet () =
  Safety.
    {
      uca_id = "UCA-BRIDGE-1";
      control_action = "materialize";
      context = "Codex-originated OODA selection";
      guard = "SA-PLAN-SAFETY-PACKET";
      fmea_id = "FM-BRIDGE-1";
      failure_mode = "unsafe state transition";
      evidence = [ "safety-analysis#bridge"; "law:CP07" ];
    }

let () =
  let valid = packet () in
  require "LAW CP07-SAFETY-PACKET-ACCEPTS-COMPLETE-COORDINATES"
    (Result.is_ok (Safety.validate valid));
  require "LAW CP07-SAFETY-PACKET-REJECTS-MISSING-UCA"
    (Result.is_error (Safety.validate { valid with uca_id = "" }));
  require "LAW CP07-SAFETY-PACKET-REJECTS-MISSING-GUARD"
    (Result.is_error (Safety.validate { valid with guard = "" }));
  require "LAW CP07-SAFETY-PACKET-REJECTS-MISSING-FMEA"
    (Result.is_error (Safety.validate { valid with fmea_id = "" }));
  require "LAW CP07-SAFETY-PACKET-REJECTS-MISSING-EVIDENCE"
    (Result.is_error (Safety.validate { valid with evidence = [] }));
  require "LAW CP07-SAFETY-PACKET-REJECTS-BLANK-EVIDENCE-COORDINATE"
    (Result.is_error (Safety.validate { valid with evidence = [ "" ] }));
  let state_changes = ref 0 in
  let rejected =
    Safety.bind { valid with evidence = [] } (fun () ->
        incr state_changes;
        Ok ())
  in
  require "LAW CP07-SAFETY-PACKET-REJECTION-PRESERVES-TRANSITION-STATE"
    (Result.is_error rejected && !state_changes = 0)
