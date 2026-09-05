(* Laws of the parity ledger. The load-bearing claim is the RANKING: a flip on
   a never-flipping scenario must carry more bits than a flip on a flappy one,
   with the exact values pinned as anchors (log2 58 for a 0-flip-in-28 history
   under Jeffreys), not asserted as vague inequalities. Every property carries
   a negative control -- a check no wrong input fails is not a check
   (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let near expected actual tolerance = Float.abs (expected -. actual) < tolerance

(* Build history rows for one scenario: oldest first, contract irrelevant. *)
let rows_of scenario verdicts = List.map (fun v -> ("c", scenario, v)) verdicts

let repeat count value = List.init count (fun _ -> value)

open Parity_ledger

let () =
  (* ANCHOR: 29 steady runs then a flip. Prior transitions 28, flips 0;
     Jeffreys P(change) = 0.5/29, surprisal = log2 58 = 5.858 bits. *)
  let steady_flip = assess (rows_of "steady" (repeat 29 true @ [ false ])) in
  (match steady_flip.movers with
  | [ entry ] ->
      check (near 5.858 entry.surprisal_bits 0.01)
        "ANCHOR a first flip after 29 steady runs carries log2 58 = 5.86 bits";
      check (not entry.last_passed) "ANCHOR the flip's verdict is reported";
      check (entry.flips = 0) "ANCHOR prior flips are counted before the newest"
  | _ -> check false "ANCHOR the steady-then-flip scenario is a mover");

  (* ANCHOR: a perfectly alternating scenario's next flip is expected --
     28 of 28 prior transitions flipped; surprisal = -log2(28.5/29) = 0.025b. *)
  let flappy =
    assess (rows_of "flappy" (List.init 30 (fun i -> i mod 2 = 0)))
  in
  (match flappy.movers with
  | [ entry ] ->
      check (near 0.025 entry.surprisal_bits 0.01)
        "ANCHOR an expected flip on an alternating scenario is ~0.025 bits"
  | _ -> check false "ANCHOR the alternating scenario is a mover");

  (* The ranking claim itself, as a ratio: the headline is two orders of
     magnitude above the background, from the same formula, no tuned weights. *)
  (match (steady_flip.movers, flappy.movers) with
  | [ headline ], [ background ] ->
      check
        (headline.surprisal_bits > 100.0 *. background.surprisal_bits)
        "RANK a never-flipped flip outranks an always-flipping flip 100x"
  | _ -> check false "RANK both anchor scenarios produced movers");

  (* Antitone in prior flips: more history of flipping, less surprise. *)
  let surprisal_with_flips flips =
    let verdicts =
      (* [flips] alternations first, then steady to 29 observations, then the
         newest flip. *)
      let rec build i previous acc =
        if i = 29 then List.rev acc
        else
          let v = if i <= flips then not previous else previous in
          build (i + 1) v (v :: acc)
      in
      let prior = build 1 true [ true ] in
      let last_prior = List.nth prior 28 in
      prior @ [ not last_prior ]
    in
    match (assess (rows_of "s" verdicts)).movers with
    | [ entry ] -> entry.surprisal_bits
    | _ -> Float.nan
  in
  check
    (surprisal_with_flips 0 > surprisal_with_flips 5
    && surprisal_with_flips 5 > surprisal_with_flips 14)
    "LAW surprisal is antitone in the prior flip count";

  (* A steady scenario that stays steady is NOT a mover -- and it is counted,
     not dropped. Negative control for the mover filter. *)
  let all_steady = assess (rows_of "calm" (repeat 30 true)) in
  check (all_steady.movers = [] && all_steady.steady = 1)
    "STEADY an unmoved scenario is steady, never a mover";

  (* One observation is NEW: no transition, no prior, no surprisal claim. *)
  let fresh = assess (rows_of "newborn" [ true ]) in
  check (fresh.fresh = [ "newborn" ] && fresh.movers = [] && fresh.steady = 0)
    "NEW a single observation is reported as new, with no invented prior";

  (* Determinism and boundedness of the render, with disclosure. *)
  let many =
    assess
      (List.concat_map
         (fun i ->
           rows_of (Printf.sprintf "s%02d" i) (repeat 5 true @ [ false ]))
         (List.init 40 (fun i -> i)))
  in
  let text = render many in
  check (render many = text) "RENDER is deterministic";
  let lines = String.split_on_char '\n' text in
  check (List.length lines < 15) "RENDER a 40-mover run is bounded";
  let has needle =
    let n = String.length needle in
    let rec at i =
      i + n <= String.length text && (String.sub text i n = needle || at (i + 1))
    in
    at 0
  in
  check (has "30 more mover") "RENDER what was truncated is disclosed";
  check (has "40 moved") "RENDER the full mover count survives truncation";

  (* Negative control on the assessor itself: different histories must yield
     different gauges -- an assess that returns the same surprisal for a
     steady flip and a flappy flip measures nothing. *)
  (match (steady_flip.movers, flappy.movers) with
  | [ a ], [ b ] ->
      check
        (Float.abs (a.surprisal_bits -. b.surprisal_bits) > 1.0)
        "CONTROL distinct histories yield distinct surprisal"
  | _ -> check false "CONTROL both control scenarios produced movers");

  Printf.printf "parity ledger: %d passed, %d failed\n" !passed
    (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_parity_ledger" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_parity_ledger ]);
  exit (Suite_telemetry.exit_code self)
