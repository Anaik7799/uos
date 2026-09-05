(* Homeostasis controls: unit / property / chaos. The controllers must be
   differential (different telemetry -> different alerts) and honest about
   absence (empty window = Green, never an alarm). *)

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    print_endline ("FAILED: " ^ name)
  end

let is_p0 = function Homeostasis.P0 _ -> true | _ -> false
let is_p1 = function Homeostasis.P1 _ -> true | _ -> false
let is_p2 = function Homeostasis.P2 _ -> true | _ -> false

(* ------------------------------------------------------------------ unit *)

let () =
  check "lyapunov measures distance from goal"
    (Homeostasis.lyapunov ~total:8 ~satisfied:7 = 1);
  check "lyapunov is zero at convergence" (Homeostasis.lyapunov ~total:8 ~satisfied:8 = 0);
  check "lyapunov never negative" (Homeostasis.lyapunov ~total:3 ~satisfied:5 = 0);
  check "empty window is Green (absence is not a violation)"
    (Homeostasis.frontier_alert ~satisfied_counts:[] ~total:8 = Homeostasis.Green);
  check "ascending frontier is Green"
    (Homeostasis.frontier_alert ~satisfied_counts:[ 5; 6; 7 ] ~total:8 = Homeostasis.Green);
  check "reaching the goal is Green"
    (Homeostasis.frontier_alert ~satisfied_counts:[ 6; 7; 8 ] ~total:8 = Homeostasis.Green);
  check "steady AT the goal is Green, not stalled"
    (Homeostasis.frontier_alert ~satisfied_counts:[ 8; 8; 8 ] ~total:8 = Homeostasis.Green);
  check "a shrink anywhere is P0 (cross-run regression)"
    (is_p0 (Homeostasis.frontier_alert ~satisfied_counts:[ 5; 6; 5 ] ~total:8));
  check "a shrink at the head is P0"
    (is_p0 (Homeostasis.frontier_alert ~satisfied_counts:[ 7; 6; 6 ] ~total:8));
  check "three equal observations short of the goal is P2 stalled"
    (is_p2 (Homeostasis.frontier_alert ~satisfied_counts:[ 7; 7; 7 ] ~total:8));
  check "two equal observations are not yet stalled"
    (Homeostasis.frontier_alert ~satisfied_counts:[ 7; 7 ] ~total:8 = Homeostasis.Green);
  (* Blueprint growth must not false-alarm: satisfied grew, total grew more. *)
  check "growing the blueprint never alarms while satisfied is non-decreasing"
    (Homeostasis.frontier_alert ~satisfied_counts:[ 6; 6; 7 ] ~total:9 = Homeostasis.Green)

let () =
  check "constant window has no transitions" (Homeostasis.transitions [ true; true; true ] = 0);
  check "empty window has no transitions" (Homeostasis.transitions [] = 0);
  check "one flip is one transition" (Homeostasis.transitions [ true; false ] = 1);
  check "flap counts every flip" (Homeostasis.transitions [ true; false; true ] = 2);
  check "constant pass window is Green"
    (Homeostasis.flap_alert ~scenario:"gemini.schema" ~window:[ true; true; true ]
    = Homeostasis.Green);
  check "constant fail window is Green here (divergence is the compare's job)"
    (Homeostasis.flap_alert ~scenario:"gemini.schema" ~window:[ false; false ]
    = Homeostasis.Green);
  check "a single state change is a P2 note"
    (is_p2 (Homeostasis.flap_alert ~scenario:"gemini.schema" ~window:[ true; false ]));
  (let alert = Homeostasis.flap_alert ~scenario:"gemini.schema" ~window:[ true; false; true ] in
   check "flapping is P1" (is_p1 alert);
   check "the flapping alert names the scenario"
     (match alert with
     | Homeostasis.P1 detail ->
         String.length detail >= String.length "gemini.schema"
         && (let rec has i =
               i + String.length "gemini.schema" <= String.length detail
               && (String.sub detail i (String.length "gemini.schema") = "gemini.schema"
                  || has (i + 1))
             in
             has 0)
     | _ -> false))

let () =
  let b = Homeostasis.breaker ~threshold:3 in
  check "fresh breaker admits" (Homeostasis.admits b);
  let b1 = Homeostasis.observe b ~ok:false in
  let b2 = Homeostasis.observe b1 ~ok:false in
  check "below threshold still admits" (Homeostasis.admits b2);
  check "failure count is visible" (Homeostasis.failures b2 = 2);
  let b3 = Homeostasis.observe b2 ~ok:false in
  check "threshold consecutive failures open the circuit" (not (Homeostasis.admits b3));
  check "a success while closed resets the count"
    (Homeostasis.failures (Homeostasis.observe b2 ~ok:true) = 0);
  check "an open breaker stays open even on success (human reset only)"
    (not (Homeostasis.admits (Homeostasis.observe b3 ~ok:true)));
  check "threshold clamps to >= 1"
    (not (Homeostasis.admits (Homeostasis.observe (Homeostasis.breaker ~threshold:0) ~ok:false)))

let () =
  check "worst of nothing is Green" (Homeostasis.worst [] = Homeostasis.Green);
  check "worst keeps the highest severity"
    (is_p1 (Homeostasis.worst [ Homeostasis.Green; Homeostasis.P2 "a"; Homeostasis.P1 "b" ]));
  check "P0 absorbs"
    (is_p0
       (Homeostasis.worst
          [ Homeostasis.P1 "a"; Homeostasis.P0 "stop"; Homeostasis.P2 "c" ]));
  check "severity is ordered"
    (Homeostasis.severity Homeostasis.Green < Homeostasis.severity (Homeostasis.P2 "")
    && Homeostasis.severity (Homeostasis.P2 "") < Homeostasis.severity (Homeostasis.P1 "")
    && Homeostasis.severity (Homeostasis.P1 "") < Homeostasis.severity (Homeostasis.P0 ""));
  check "describe renders green" (Homeostasis.describe Homeostasis.Green = "green");
  check "describe renders the detail"
    (Homeostasis.describe (Homeostasis.P0 "x") <> "green")

(* ------------------------------------------------- regression (P0 sensor) *)

let has_sub text needle =
  let n = String.length needle and l = String.length text in
  let rec loop i = i + n <= l && (String.sub text i n = needle || loop (i + 1)) in
  n = 0 || loop 0

let () =
  check "a window that never passed is not a regression"
    (not (Homeostasis.regressed ~window:[ false; false ]));
  check "pass then fail is a regression" (Homeostasis.regressed ~window:[ true; false ]);
  check "recovered is not a regression"
    (not (Homeostasis.regressed ~window:[ true; false; true ]));
  check "empty window is not a regression" (not (Homeostasis.regressed ~window:[]));
  check "pass, flap, end failing is a regression"
    (Homeostasis.regressed ~window:[ true; false; true; false ]);
  check "regression alert is P0 naming the scenario"
    (match Homeostasis.regression_alert ~scenario:"gemini.schema" ~window:[ true; false ] with
    | Homeostasis.P0 detail -> has_sub detail "gemini.schema"
    | _ -> false);
  check "a recovery yields Green from the regression sensor"
    (Homeostasis.regression_alert ~scenario:"s" ~window:[ false; true ] = Homeostasis.Green);
  check "a first-time failure is NOT a regression (it is a first measurement)"
    (Homeostasis.regression_alert ~scenario:"s" ~window:[ false ] = Homeostasis.Green)

(* -------------------------------------------------------------- property *)

let () =
  Random.init 20260808;
  (* 300 random non-decreasing frontier windows: never P0. *)
  let violations = ref 0 in
  for _ = 1 to 300 do
    let total = 1 + Random.int 12 in
    let length = 1 + Random.int 8 in
    let counts = ref [] in
    let current = ref (Random.int (total + 1)) in
    for _ = 1 to length do
      current := min total (!current + Random.int 3);
      counts := !current :: !counts
    done;
    let window = List.rev !counts in
    if is_p0 (Homeostasis.frontier_alert ~satisfied_counts:window ~total) then incr violations
  done;
  check "property: monotone frontiers never P0 (300 windows)" (!violations = 0);
  (* 300 random constant scenario windows: never any alert. *)
  let flap_violations = ref 0 in
  for _ = 1 to 300 do
    let value = Random.bool () in
    let window = List.init (1 + Random.int 10) (fun _ -> value) in
    if Homeostasis.flap_alert ~scenario:"s" ~window <> Homeostasis.Green then
      incr flap_violations
  done;
  check "property: constant windows never alert (300 windows)" (!flap_violations = 0)

(* ----------------------------------------------------------------- chaos *)

let () =
  Random.init 424242;
  (* Inject a shrink at a random position into a monotone window: P0 must fire
     every time -- the detector cannot be outrun. *)
  let missed = ref 0 in
  for _ = 1 to 300 do
    let total = 2 + Random.int 10 in
    let length = 3 + Random.int 6 in
    let base = List.init length (fun i -> min total (i + 1)) in
    let position = 1 + Random.int (length - 1) in
    let window =
      List.mapi (fun i x -> if i = position then max 0 (List.nth base (i - 1) - 1) else x) base
    in
    (* Only count windows where the injection produced a real shrink. *)
    let rec has_shrink prev = function
      | [] -> false
      | x :: tl -> x < prev || has_shrink x tl
    in
    match window with
    | first :: rest when has_shrink first rest ->
        if not (is_p0 (Homeostasis.frontier_alert ~satisfied_counts:window ~total)) then
          incr missed
    | _ -> ()
  done;
  check "chaos: every injected regression fires P0 (300 injections)" (!missed = 0);
  (* A breaker fed random garbage after opening never silently re-closes. *)
  let reopened = ref 0 in
  for _ = 1 to 100 do
    let b = ref (Homeostasis.breaker ~threshold:2) in
    b := Homeostasis.observe !b ~ok:false;
    b := Homeostasis.observe !b ~ok:false;
    for _ = 1 to 20 do
      b := Homeostasis.observe !b ~ok:(Random.bool ())
    done;
    if Homeostasis.admits !b then incr reopened
  done;
  check "chaos: an open breaker never self-heals (100 storms)" (!reopened = 0)

let () =
  Printf.printf "homeostasis: passed: %d failed: %d\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_homeostasis" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_homeostasis ]);
  exit (Suite_telemetry.exit_code self)
