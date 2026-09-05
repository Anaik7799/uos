(* One check per class, the precedence that is load-bearing, and the gate
   property that no justification unblocks a blocking class. Negative
   controls per HZ-FIX-03. *)

let passed = ref 0
let failures = ref []
let check c l = if c then incr passed else failures := l :: !failures

open Diff_triage

let kind ?(status = "diff") e a = classify ~status ~expected:e ~actual:a

let () =
  (* Scrubbers, unit level. *)
  check (scrub_line "at 2026-08-12T04:00:00Z done" = "at <TS> done") "SCRUB timestamp";
  check
    (scrub_line "id 123e4567-e89b-12d3-a456-426614174000 ok" = "id <UUID> ok")
    "SCRUB uuid";
  check (scrub_line "ptr 0xdeadbeef end" = "ptr <ADDR> end") "SCRUB hex address";
  check (scrub_line "wrote /tmp/x_1/y.txt now" = "wrote <TMP> now") "SCRUB tmp path";
  check (scrub_line "worker pid=4242 up" = "worker pid=<PID> up") "SCRUB pid";
  check (scrub_line "took 0.123s and 45ms" = "took <DUR> and <DUR>") "SCRUB durations";
  (* The boundary rule: an identifier containing a date shape is not chewed. *)
  check (scrub_line "x2026-08-12 stays" = "x2026-08-12 stays")
    "SCRUB fires only at token boundaries (negative control)";

  (* The nine classes. *)
  check (kind ~status:"unstable" [ "a" ] [ "a" ] = "unstable") "CLASS unstable wins first";
  check (kind ~status:"error" [ "a" ] [] = "error") "CLASS error";
  check (kind [ "out" ] [] = "emptied") "CLASS vanished output is emptied, never accepted";
  check
    (kind [ "at 2026-01-01T00:00:00Z" ] [ "at 2026-02-02T12:00:00Z" ] = "volatile")
    "CLASS a pure timestamp diff is volatile (scrubber gap), and volatile BLOCKS";
  check (kind [ "a  b" ] [ "a b" ] = "whitespace") "CLASS whitespace collapse is cosmetic";
  check (kind [ "a"; "b" ] [ "b"; "a" ] = "reorder") "CLASS same lines new order";
  check (kind [ "a"; "c" ] [ "a"; "b"; "c" ] = "additive") "CLASS old lines survive";
  check (kind [ "a"; "b"; "c" ] [ "a"; "c" ] = "removal") "CLASS lost lines are removal";
  check (kind [ "x" ] [ "y" ] = "semantic") "CLASS content moved both ways";
  check (List.length classes = 9) "CLASS the taxonomy is exactly nine";

  (* Verdicts, and the gate property. *)
  check (verdict_of "whitespace" = Auto) "VERDICT cosmetic is auto";
  check (verdict_of "removal" = Review) "VERDICT removal needs review";
  check (verdict_of "volatile" = Block) "VERDICT volatile blocks";
  check (exit_code Auto = 0 && exit_code Review = 1 && exit_code Block = 2)
    "VERDICT exit codes are the automation interface";

  (* Justification downgrades review — and ONLY review. *)
  let j = [ ("site:1", "the precedence table changed so nesting differs") ] in
  let _, v, why =
    triage ~justify:j ~site:"site:1" ~status:"diff" ~expected:[ "a" ]
      ~actual:[ "a"; "b" ] ()
  in
  check (v = Auto && String.length why > 0) "GATE a justified review-class downgrades to auto";
  let _, v2, _ =
    triage ~require_justification:true ~justify:[] ~site:"site:2" ~status:"diff"
      ~expected:[ "a" ] ~actual:[ "a"; "b" ] ()
  in
  check (v2 = Block) "GATE require-justification blocks an unjustified review";
  let _, v3, _ =
    triage ~justify:[ ("site:3", "short") ] ~require_justification:true ~site:"site:3"
      ~status:"diff" ~expected:[ "a" ] ~actual:[ "a"; "b" ] ()
  in
  check (v3 = Block) "GATE a too-short reason does not count (a word is not a cause)";
  (* THE property: no reason, however long, unblocks a blocking class. *)
  let _, v4, _ =
    triage
      ~justify:[ ("site:4", "a very long and sincere justification indeed, truly") ]
      ~site:"site:4" ~status:"diff"
      ~expected:[ "at 2026-01-01T00:00:00Z" ] ~actual:[ "at 2027-01-01T00:00:00Z" ] ()
  in
  check (v4 = Block) "GATE no justification unblocks a BLOCKING class (negative control)";

  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_diff_triage" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_diff_triage ]);
  exit (Suite_telemetry.exit_code self)
