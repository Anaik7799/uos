module S = Zigvm_harness_support.Infranodus_scenario

let require label condition = if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let write path = let channel = open_out_bin path in output_string channel "evidence"; close_out channel
let contains haystack needle =
  let rec loop offset =
    if offset + String.length needle > String.length haystack then false
    else if String.sub haystack offset (String.length needle) = needle then true
    else loop (offset + 1)
  in loop 0

let () =
  let declared = S.evidence_manifest S.feature_scenarios in
  require "LAW EVIDENCE-DECLARED-INITIAL-STATE"
    (List.for_all (fun row -> row.S.state = S.Declared) declared);
  require "MUT-EVIDENCE-1-DECLARED-NOT-PASS"
    (List.for_all (fun row -> S.evidence_state_name row.S.state <> "Executed_pass") declared);
  let directory = Filename.temp_dir "zigvm-evidence-" "" in
  let screenshot = Filename.concat directory "scenario-f1-1-mobile.png" in
  let video = Filename.concat directory "scenario-f1-1-mobile.webm" in
  let trace = Filename.concat directory "scenario-f1-1-mobile.zip" in
  List.iter write [ screenshot; video; trace ];
  let viewport = List.hd S.canonical_viewports in
  let row = S.{ scenario_id = "scenario-f1-1"; feature_id = Some "F1.1";
    viewport; screenshot; video; trace; state = Executed_pass } in
  require "LAW EVIDENCE-EXECUTED-ARTIFACT-CLOSURE"
    (Result.is_ok (S.validate_evidence ~exists:Sys.file_exists [ row ]));
  let mismatch = { row with feature_id = Some "F7.10" } in
  require "MUT-EVIDENCE-2-FEATURE-ID-MISMATCH"
    (Result.is_error (S.validate_evidence ~exists:Sys.file_exists [ mismatch ]));
  let unavailable = { row with feature_id = None; state = S.Unavailable_observed "external provider session absent" } in
  require "LAW EVIDENCE-TERMINAL-UNAVAILABLE"
    (Result.is_ok (S.validate_evidence ~exists:(fun _ -> false) [ unavailable ]));
  require "LAW EVIDENCE-NO-PENDING-VOCABULARY"
    (not (contains (Yojson.Safe.to_string (S.evidence_to_yojson row)) "pending"))
