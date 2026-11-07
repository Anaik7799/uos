(* ==========================================================================
   verification_plane_simulate — plant each known failure mode and record
   whether the plane's own instruments DETECT it.

   WHY: an FMEA detection rating (Det) that an author assigns from judgement is
   an opinion. Det here is MEASURED: each mode is planted as a real fixture, the
   real instrument is run, and Det is derived from whether it fired. A mode the
   instruments cannot catch gets Det 5 because that was observed, not feared.

   THREE OUTCOMES, NOT TWO. The first version of this harness scored a mode
   "detected" whenever the planted fixture produced the expected verdict -- so a
   fixture that reports WORLD_FAIL on a healthy node, or PASS having read
   nothing, counted as a success. But those verdicts are the DEFECT MANIFESTING,
   not an instrument catching it. That version reported 7/7 detected, which is
   precisely the false green this whole effort exists to prevent, produced by
   the harness built to measure it.

   The outcomes are:
     DETECTED   -- an instrument fires and names the mode. Det = 1.
     PREVENTED  -- the substrate makes the mode unreachable by construction.
                   Det = 1, and the mode's occurrence is structurally 1.
     MANIFESTS  -- the fixture reproduces the defect and NOTHING catches it.
                   Det = 5, measured, not feared.

   HONEST BOUNDARY: this simulates a mode in a FIXTURE, not in the live plane.
   A caught fixture proves the instrument CAN fire; it does not prove it would
   fire on every real instance. Detection is evidence about the instrument, not
   a guarantee about the tree.

   authority NONE. EV ceiling 93.
   ========================================================================== *)

type mode = {
  id : string;
  title : string;
  fixture : string;        (* mojo source planted under formal/mojo/sim *)
  detector : string;       (* falsify | substrate | none *)
  expect : string;         (* substring proving the OUTCOME named below *)
  outcome : string;        (* DETECTED | PREVENTED | MANIFESTS -- what the run
                              must show for this mode to be classified *)
  severity : int;          (* S 1..5, from the canonical FMEA rubric *)
  occurrence : int;        (* O 1..5, from OBSERVED history in this effort *)
}

let modes = [
  (* Caught by tools/mojo_arm_falsifiability.ml *)
  { id = "FM-01"; title = "literal tautology arm";
    fixture = "sim_fm01.mojo"; detector = "falsify";
    expect = "UNFALSIFIABLE"; outcome = "DETECTED";
    severity = 4; occurrence = 5 };
  { id = "FM-02"; title = "structurally unfalsifiable arm (variable cancels)";
    fixture = "sim_fm02.mojo"; detector = "falsify";
    expect = "UNFALSIFIABLE"; outcome = "DETECTED";
    severity = 5; occurrence = 4 };
  { id = "FM-09"; title = "inverted polarity: arm fails when system is repaired";
    fixture = "sim_fm09.mojo"; detector = "falsify";
    expect = "UNFALSIFIABLE"; outcome = "DETECTED";
    severity = 4; occurrence = 3 };
  (* Made unreachable by the substrate's verdict function *)
  { id = "FM-07"; title = "zero-algebra run masked by a world failure";
    fixture = "sim_fm07.mojo"; detector = "substrate";
    expect = "VACUOUS"; outcome = "PREVENTED";
    severity = 5; occurrence = 2 };
  (* Caught by SC-VP-04 in tools/mojo_arm_falsifiability.ml *)
  { id = "FM-04"; title = "control pins a subject value (Caught by SC-VP-04)";
    fixture = "sim_fm04.mojo"; detector = "falsify";
    expect = "\"pinned_probes\":1"; outcome = "DETECTED";
    severity = 4; occurrence = 3 };
  (* Made unreachable by SC-VP-02 in oracle_substrate.mojo *)
  { id = "FM-05"; title = "world() on an absent instrument (Prevented by SC-VP-02)";
    fixture = "sim_fm05.mojo"; detector = "substrate";
    expect = "\"status\":\"VACUOUS\""; outcome = "PREVENTED";
    severity = 4; occurrence = 4 };
  (* Made unreachable by SC-VP-01 in oracle_substrate.mojo *)
  { id = "FM-06a"; title = "algebra-only run with 0 world checks (Prevented by SC-VP-01)";
    fixture = "sim_fm06_algebra_only.mojo"; detector = "substrate";
    expect = "\"status\":\"BLIND\""; outcome = "PREVENTED";
    severity = 5; occurrence = 3 };
  (* Residual open gap: bare world() without world_or_blind *)
  { id = "FM-06b"; title = "world() on an absent subject without world_or_blind";
    fixture = "sim_fm06.mojo"; detector = "substrate";
    expect = "\"status\":\"PASS\""; outcome = "MANIFESTS";
    severity = 5; occurrence = 3 };
]

let sh cmd =
  let ic = Unix.open_process_in (cmd ^ " 2>&1") in
  let b = Buffer.create 4096 in
  (try while true do Buffer.add_channel b ic 1 done with End_of_file -> ());
  let st = Unix.close_process_in ic in
  let rc = match st with Unix.WEXITED c -> c | _ -> 127 in
  (rc, Buffer.contents b)

let contains h n =
  let hn = String.length h and nn = String.length n in
  let rec go i = if i + nn > hn then false
    else if String.sub h i nn = n then true else go (i+1) in
  nn > 0 && go 0

let () =
  let results = List.map (fun m ->
    let path = Filename.concat "formal/mojo/sim" m.fixture in
    if not (Sys.file_exists path) then (m, false, "fixture missing")
    else begin
      let (rc, out) =
        match m.detector with
        | "falsify" ->
          sh (Printf.sprintf
                "./toolchains/opam-ocaml/bin/ocaml -I +unix unix.cma \
                 tools/mojo_arm_falsifiability.ml %s" (Filename.quote path))
        | _ ->
          sh (Printf.sprintf
                "./tools/mojo run -I formal/mojo -I formal/mojo/sim %s"
                (Filename.quote path)) in
      ignore rc;
      (* The run must EXHIBIT what the mode claims. For DETECTED that is an
         instrument firing; for PREVENTED and MANIFESTS it is the substrate
         verdict. Classification is confirmed only if the expected string is
         present -- otherwise the mode did not reproduce and is UNCONFIRMED,
         which is reported as such rather than silently passing. *)
      let shown = contains out m.expect in
      let note =
        if not shown then "UNCONFIRMED"
        else m.outcome in
      (m, (note = "DETECTED" || note = "PREVENTED"), note)
    end) modes in
  (* Det from observation: detected => 1 (deterministic before effect), else 5 *)
  prerr_endline
    "  mode    S  O  Det  RPN  F  outcome      title";
  prerr_endline
    "  ------  -  -  ---  ---  -  -----------  ---------------------------";
  let band r = if r <= 5 then 1 else if r <= 15 then 2
    else if r <= 35 then 3 else if r <= 70 then 4 else 5 in
  let rows = List.map (fun (m, covered, note) ->
    let d = if covered then 1 else 5 in
    ignore note;
    let rpn = m.severity * m.occurrence * d in
    let f = max m.severity (band rpn) in
    prerr_endline (Printf.sprintf "  %-6s  %d  %d  %3d  %3d  %d  %-11s  %s"
      m.id m.severity m.occurrence d rpn f note m.title);
    (m, covered, d, rpn, f)) results in
  let fmax = List.fold_left (fun a (_,_,_,_,f) -> max a f) 0 rows in
  let missed = List.filter (fun (_,d,_,_,_) -> not d) rows in
  prerr_endline (Printf.sprintf
    "\n  F (task) = max over modes = %d\n  \
     simulated %d | covered (DETECTED or PREVENTED) %d | \
     MANIFESTS UNDETECTED %d"
    fmax (List.length rows) (List.length rows - List.length missed)
    (List.length missed));
  prerr_endline
    "  Det is MEASURED, not judged: 1 where an instrument fired or the \
     substrate made the\n  mode unreachable, 5 where the fixture reproduced \
     the defect and nothing caught it.\n  The MANIFESTS rows are the plane's \
     real detection gap: each was found by READING,\n  and no instrument \
     would find the next one.";
  Printf.printf "{\"schema\":\"uos.verification-plane-fmea.v1\",\"f_task\":%d,\
                 \"modes\":[" fmax;
  List.iteri (fun i (m, det, d, rpn, f) ->
    Printf.printf "%s{\"id\":%S,\"title\":%S,\"S\":%d,\"O\":%d,\"Det\":%d,\
                   \"RPN\":%d,\"F\":%d,\"detected\":%b}"
      (if i = 0 then "" else ",") m.id m.title m.severity m.occurrence d rpn f det)
    rows;
  print_string "],\"authority\":\"NONE\",\"ev_ceiling\":93}\n";
  exit (if missed = [] then 0 else 1)
