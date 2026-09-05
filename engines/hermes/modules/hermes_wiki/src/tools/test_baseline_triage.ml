(* The ratchet's own laws. The load-bearing one is that a REMOVAL blocks:
   a page that stopped rendering is indistinguishable from a page deliberately
   deleted, so the tool must refuse and let a human make the claim.

   Every property carries a negative control — a check no wrong input fails is
   not a check (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let d n = String.make 64 n
let entry path s r = (path, (d s, d r))

open Baseline_triage

let () =
  (* Parsing refuses rather than skipping: a diff over an unknown population
     is not a ratchet. *)
  (match parse "not a baseline line" with
  | Ok _ -> check false "PARSE an unparseable line must be refused"
  | Error m ->
      check true "PARSE an unparseable line is refused";
      check
        (String.length m > 40)
        "PARSE the refusal explains why rather than just failing");
  (match parse (d 'a' ^ " " ^ d 'b' ^ " pages/x.md\n") with
  | Error m -> check false ("PARSE a valid line :: " ^ m)
  | Ok [ (path, _) ] -> check (path = "pages/x.md") "PARSE a valid line round-trips"
  | Ok _ -> check false "PARSE a valid line yields one entry");

  let before = [ entry "a" 'a' 'a'; entry "b" 'b' 'b'; entry "c" 'c' 'c' ] in

  (* UNCHANGED — the only auto-acceptable shape. *)
  check (verdict (classify ~before ~after:before) = Auto)
    "VERDICT an identical baseline is auto-acceptable";
  check (exit_code Auto = 0) "VERDICT auto exits 0";

  (* RENDERED — the reviewable case: the render digest moved. *)
  let rendered = [ entry "a" 'a' 'z'; entry "b" 'b' 'b'; entry "c" 'c' 'c' ] in
  let dr = classify ~before ~after:rendered in
  check (List.mem (Rendered "a") dr) "CLASSIFY a moved render is Rendered";
  check (verdict dr = Review) "VERDICT a render change needs review";
  check (exit_code Review = 1) "VERDICT review exits 1";

  (* SOURCE-ONLY — the source moved and the render did not. Distinguished
     because it is a no-op render: informative, but not the same risk. *)
  let source_only = [ entry "a" 'z' 'a'; entry "b" 'b' 'b'; entry "c" 'c' 'c' ] in
  check
    (List.mem (Source_only "a") (classify ~before ~after:source_only))
    "CLASSIFY a moved source with a stable render is Source_only";

  (* REMOVED — the one that blocks. *)
  let removed = [ entry "a" 'a' 'a'; entry "b" 'b' 'b' ] in
  let dm = classify ~before ~after:removed in
  check (List.mem (Removed "c") dm) "CLASSIFY a vanished page is Removed";
  check (verdict dm = Block) "VERDICT a removal BLOCKS by default";
  check (exit_code Block = 2) "VERDICT block exits 2";
  (* And it is acknowledgeable — a claim the operator makes explicitly, never
     an inference the tool draws. *)
  check (verdict ~accept_removals:true dm = Review)
    "VERDICT an acknowledged removal downgrades to review, never to auto";

  (* ADDED does not block: a new page cannot regress an old one. This is the
     negative control for the blocking rule — if everything blocked, the
     ratchet would be a brake nobody keeps. *)
  let added = entry "d" 'd' 'd' :: before in
  let da = classify ~before ~after:added in
  check (List.mem (Added "d") da) "CLASSIFY a new page is Added";
  check (verdict da = Review) "VERDICT an addition reviews but does not block";

  (* A mass removal must not push the verdict off the end of a terminal. *)
  let many = List.init 40 (fun i -> entry (Printf.sprintf "p%02d" i) 'a' 'a') in
  let wiped = classify ~before:many ~after:[] in
  check (verdict wiped = Block) "VERDICT a mass removal blocks";
  let text = render wiped in
  check (String.length text < 700) "RENDER a mass removal is bounded";
  let has needle =
    let n = String.length needle in
    let rec at i =
      i + n <= String.length text && (String.sub text i n = needle || at (i + 1))
    in
    at 0
  in
  check (has "more") "RENDER what was truncated is disclosed";
  check (has "REMOVED") "RENDER removals are named, so the fix is a lookup";
  check (render wiped = text) "RENDER is deterministic";

  Printf.printf "baseline triage: %d passed, %d failed\n" !passed
    (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Wiki_suite_telemetry.observe ~suite:"test_baseline_triage" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_baseline_triage ]);
  exit (Wiki_suite_telemetry.exit_code self)
