(* The classifier is only worth its bytes if its arithmetic is real. These
   layers check the three properties that separate a posterior from a number:
   the likelihoods are distributions, the posterior normalizes, and the state
   is DERIVED from it rather than decided beside it.

   Every property carries a negative control — an input that must fail it. A
   property no wrong input fails is not a test (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let close a b = Float.abs (a -. b) < 1e-9

open Expect_posterior

let ev ?(site = "s") ?(cause = "c") ?(churn = 0.5) ?(kill = 0.9) path output =
  { site; cause; path_changed = path; output_changed = output; churn;
    mutation_kill_rate = kill }

let evidence_space = [ (false, false); (true, false); (false, true); (true, true) ]

(* --------------------------------------------------------- LIKELIHOOD layer *)

let likelihood_layer () =
  (* Exhaustive over the whole support: for a finite space this is a proof, not
     a sample. Each state's likelihoods must sum to 1 or it is not a
     distribution and the posterior is meaningless. *)
  List.iter
    (fun state ->
      let total =
        List.fold_left
          (fun acc (p, o) -> acc +. likelihood state (ev p o))
          0.0 evidence_space
      in
      check (close total 1.0)
        (Printf.sprintf "LIKELIHOOD %s sums to 1 (got %.4f)" (state_name state) total))
    states;
  List.iter
    (fun state ->
      List.iter
        (fun (p, o) ->
          let l = likelihood state (ev p o) in
          check (l >= 0.0 && l <= 1.0)
            (Printf.sprintf "LIKELIHOOD %s is a probability" (state_name state)))
        evidence_space)
    states;
  (* The discriminating claim: path-changed/output-same must be likeliest under
     silent divergence, or the ontology does not earn the state. *)
  let e = ev true false in
  let best =
    List.fold_left
      (fun (bs, bl) s -> let l = likelihood s e in if l > bl then (s, l) else (bs, bl))
      (Stable, -1.0) states
  in
  check (fst best = Silent_divergence)
    "LIKELIHOOD path-changed/output-same is likeliest under silent divergence"

(* ---------------------------------------------------------- POSTERIOR layer *)

let posterior_layer () =
  (match update ~prior:uniform_prior (ev true false) with
  | Error m -> check false ("POSTERIOR uniform update succeeds :: " ^ m)
  | Ok p ->
      let mass = List.fold_left (fun acc (_, q) -> acc +. q) 0.0 p.distribution in
      check (close mass 1.0) "POSTERIOR distribution sums to 1";
      check (p.argmax = Silent_divergence) "POSTERIOR argmax is silent divergence";
      check (p.confidence = List.assoc p.argmax p.distribution)
        "POSTERIOR confidence is the winning mass";
      check (p.marginal > 0.0 && p.marginal <= 1.0) "POSTERIOR marginal is a probability";
      check (p.surprisal > 0.0) "POSTERIOR surprisal is positive for a sub-certain marginal");

  (* The argmax must FOLLOW the arithmetic. Under a prior that rules silent
     divergence out entirely, the same evidence must classify differently —
     which a hardcoded if/else on path_changed could never do. This is the
     check that the specification's version fails. *)
  (match
     update
       ~prior:
         [ (Stable, 0.0); (Silent_divergence, 0.0); (Structural_drift, 1.0);
           (Regressed, 0.0) ]
       (ev true false)
   with
  | Error m -> check false ("POSTERIOR degenerate prior :: " ^ m)
  | Ok p ->
      check (p.argmax = Structural_drift)
        "POSTERIOR argmax follows the prior, not a hardcoded rule";
      check (close (List.assoc Silent_divergence p.distribution) 0.0)
        "POSTERIOR a zero prior stays zero");

  (* Stable evidence classifies as stable under a uniform prior. *)
  (match update ~prior:uniform_prior (ev false false) with
  | Error m -> check false ("POSTERIOR stable :: " ^ m)
  | Ok p -> check (p.argmax = Stable) "POSTERIOR no change classifies stable");

  (* Surprisal measures how poorly the MODEL explains an observation, and this
     pins the counterintuitive-but-correct consequence: a path-only change is
     BETTER explained than a no-change one (silent divergence assigns it 0.90),
     so it carries LESS surprisal. This test exists because the opposite was
     assumed and was wrong. *)
  (match
     (update ~prior:uniform_prior (ev false false), update ~prior:uniform_prior (ev true false))
   with
  | Ok stable, Ok silent ->
      check (silent.surprisal < stable.surprisal)
        "POSTERIOR a well-explained observation carries less surprisal";
      (* Which is exactly why surprisal alone cannot be the work queue. Severity
         x rarity puts the silent divergence first, where it belongs. *)
      check (priority silent > priority stable)
        "POSTERIOR severity x rarity ranks silent divergence above stable";
      (* Not zero: expected severity integrates the residual mass on the
         non-stable states, which is the point of removing the argmax cliff. It
         must still be small. *)
      check (priority stable > 0.0 && priority stable < 0.2)
        "POSTERIOR a stable site has small but non-zero priority"
  | _ -> check false "POSTERIOR surprisal comparison");

  (* The argmax cliff, pinned. Two evidence items either side of a boundary
     must not produce a step change in priority. Expected severity is continuous
     in the distribution; severity-of-argmax was not. *)
  (match
     ( update ~prior:[ (Stable, 0.51); (Silent_divergence, 0.49); (Structural_drift, 0.0);
                       (Regressed, 0.0) ] (ev true false),
       update ~prior:[ (Stable, 0.49); (Silent_divergence, 0.51); (Structural_drift, 0.0);
                       (Regressed, 0.0) ] (ev true false) )
   with
  | Ok a, Ok b ->
      check (Float.abs (priority a -. priority b) < 0.1)
        "POSTERIOR priority is continuous across an argmax boundary (no cliff)"
  | _ -> check false "POSTERIOR argmax cliff comparison")

(* ------------------------------------------------------------ REFUSAL layer *)

let refusal_layer () =
  let bad label prior =
    match update ~prior (ev true false) with
    | Ok _ -> check false ("REFUSAL " ^ label ^ " must be refused")
    | Error _ -> incr passed
  in
  bad "a prior that does not sum to 1" (List.map (fun s -> (s, 0.1)) states);
  bad "a prior missing a state" [ (Stable, 1.0) ];
  bad "a negative prior"
    [ (Stable, -0.5); (Silent_divergence, 0.5); (Structural_drift, 0.5);
      (Regressed, 0.5) ];
  (* Positive control: the refusals above must not be firing on everything. *)
  (match update ~prior:uniform_prior (ev true false) with
  | Ok _ -> incr passed
  | Error m -> check false ("REFUSAL a valid prior is accepted :: " ^ m))

(* ------------------------------------------------------------- RETE layer *)

let rete_layer () =
  let mk site cause kill path output =
    let e = ev ~site ~cause ~kill path output in
    match update ~prior:uniform_prior e with
    | Ok p -> (e, p)
    | Error m -> failwith m
  in
  (* Forty redundant failures, one cause. *)
  let many =
    List.init 40 (fun i -> mk (Printf.sprintf "site_%02d" i) "one-cause" 0.9 false true)
  in
  let clusters = join many in
  check (List.length clusters = 1) "RETE forty failures join to one semantic fact";
  check (List.length (List.hd clusters).members = 40) "RETE the cluster keeps every member";

  (* Distinct causes stay distinct. *)
  let mixed = [ mk "a" "cause-a" 0.9 true false; mk "b" "cause-b" 0.9 false true ] in
  check (List.length (join mixed) = 2) "RETE distinct causes do not merge";

  (* The alpha network WITHHOLDS, it does not delete. This is the departure
     from the specification and the property that keeps a weak test visible. *)
  let weak = [ mk "w" "weak-cause" 0.05 false true ] in
  let t = alpha (join weak) in
  check (t.emitted = []) "RETE a low-kill-rate cluster leaves the dense payload";
  check (List.length t.withheld = 1) "RETE it is WITHHELD, not dropped";
  let text, budget = render t in
  check (budget.clusters_withheld = 1) "RETE the budget vector counts the withheld";
  check (budget.sites_covered = 1) "RETE coverage counts withheld sites too";
  check
    (let needle = "withheld" in
     let n = String.length needle in
     let rec at i =
       i + n <= String.length text && (String.sub text i n = needle || at (i + 1))
     in
     at 0)
    "RETE the rendered block discloses the withholding";

  (* MUTATION-RATE LAUNDERING. One strong site must not admit a cluster of weak
     ones. Thirty-nine members at 0.05 and one at 0.99 average well below the
     floor, so the cluster is withheld — with `List.exists` it would have been
     emitted, carrying thirty-nine sites that discriminate nothing. *)
  let laundered =
    mk "strong" "mixed-cause" 0.99 false true
    :: List.init 39 (fun i -> mk (Printf.sprintf "weak_%02d" i) "mixed-cause" 0.05 false true)
  in
  let lt = alpha (join laundered) in
  check (lt.emitted = []) "RETE one strong site cannot launder a weak cluster";
  check (List.length lt.withheld = 1) "RETE the laundered cluster is withheld";
  (* Positive control: a genuinely strong cluster still gets through, or the
     floor would simply be refusing everything. *)
  let strong = List.init 5 (fun i -> mk (Printf.sprintf "s%d" i) "strong-cause" 0.9 false true) in
  check (List.length (alpha (join strong)).emitted = 1)
    "RETE a genuinely discriminating cluster is still emitted";

  (* Ranking is by severity x rarity, descending. *)
  let ranked = alpha (join [ mk "routine" "c1" 0.9 false false; mk "odd" "c2" 0.9 true false ]) in
  (match ranked.emitted with
  | first :: _ -> check (first.cause_key = "c2") "RETE the high-severity cluster ranks first"
  | [] -> check false "RETE ranking produced no clusters");

  (* Determinism: same input, same bytes. A renderer that varies cannot be
     diffed, and a block that cannot be diffed cannot be reviewed. *)
  let once, _ = render ranked in
  let twice, _ = render ranked in
  check (once = twice) "RETE rendering is deterministic"

(* ------------------------------------------------------------ REPORT layer *)

let contains text needle =
  let n = String.length needle in
  let rec at i =
    i + n <= String.length text && (String.sub text i n = needle || at (i + 1))
  in
  at 0

let report_layer () =
  let mk site cause kill path output =
    let e = ev ~site ~cause ~kill path output in
    match update ~prior:uniform_prior e with Ok p -> (e, p) | Error m -> failwith m
  in
  (* Density rule 3: truncate by budget, and DISCLOSE the truncation. *)
  let many = List.init 12 (fun i -> mk (Printf.sprintf "s%02d" i) (Printf.sprintf "c%02d" i) 0.9 false true) in
  let r = assess ~max_clusters:4 ~negative:negative_space_empty ~oracles:[] many in
  check (List.length r.triage.emitted = 4) "REPORT truncates to the cluster budget";
  check (List.length r.triage.withheld = 8) "REPORT the remainder is withheld, not lost";
  check (r.budget_vector.sites_covered = 12) "REPORT the budget accounts for every site";
  check (contains r.triage.withheld_reason "budget") "REPORT truncation is disclosed by reason";

  (* The recommendation is DERIVED and ordered: silent divergence outranks a
     vacuous oracle, which outranks unexecuted negative space. *)
  let silent = [ mk "s" "silent-cause" 0.9 true false ] in
  let vacuous = [ { invariant = "round-trips"; margin = 0.0; vacuous = true } ] in
  let negative = { negative_space_empty with never_executed = [ "never_run_site" ] } in
  let r_silent = assess ~negative ~oracles:vacuous silent in
  check (contains r_silent.next_measurement "dispatch mutation")
    "REPORT silent divergence outranks every other recommendation";
  let r_vacuous =
    assess ~negative ~oracles:vacuous [ mk "s" "c" 0.9 false false ]
  in
  check (contains r_vacuous.next_measurement "round-trips")
    "REPORT a vacuous oracle outranks negative space";
  let r_negative = assess ~negative ~oracles:[] [ mk "s" "c" 0.9 false false ] in
  check (contains r_negative.next_measurement "never_run_site")
    "REPORT negative space is recommended when nothing outranks it";
  let r_clean = assess ~negative:negative_space_empty ~oracles:[] [] in
  check (contains r_clean.next_measurement "extend the corpus")
    "REPORT a clean board recommends extension, not a re-run";

  (* The block reports the classes it claims to. *)
  let text = render_report r_silent in
  check (contains text "negative space") "REPORT the block carries negative space";
  check (contains text "VACUOUS") "REPORT a vacuous invariant is named as such";
  check (contains text "budget:") "REPORT the block carries the budget vector";
  check (contains text "recommended next measurement:")
    "REPORT the block ends with a measurement, not a summary";
  check (render_report r_silent = text) "REPORT rendering is deterministic"

(* -------------------------------------------------------------- GATE layer *)

let gate_layer () =
  let mk site cause kill path output =
    let e = ev ~site ~cause ~kill path output in
    match update ~prior:uniform_prior e with Ok p -> (e, p) | Error m -> failwith m
  in
  (* A confident silent divergence BLOCKS. This is the whole point: the
     posterior conditions a deterministic decision instead of only printing. *)
  let silent = assess ~negative:negative_space_empty ~oracles:[] [ mk "s" "c" 0.9 true false ] in
  (match gate silent with
  | Proceed -> check false "GATE a confident silent divergence blocks"
  | Blocked_pending_measurement { reason; measurement } ->
      check true "GATE a confident silent divergence blocks";
      check (contains reason "silent-divergence") "GATE the refusal names the state";
      check (contains measurement "dispatch mutation")
        "GATE the refusal carries the measurement that would clear it");

  (* Negative control: a stable board must NOT block, or the gate is a brake
     that is always on and nobody will keep it. *)
  let stable = assess ~negative:negative_space_empty ~oracles:[] [ mk "s" "c" 0.9 false false ] in
  check (gate stable = Proceed) "GATE a stable board proceeds";
  (* A regression is loud on its own; the gate exists for the SILENT case, and
     blocking here would duplicate a signal the logs already carry. *)
  let regressed = assess ~negative:negative_space_empty ~oracles:[] [ mk "s" "c" 0.9 false true ] in
  check (gate regressed = Proceed) "GATE an ordinary regression is left to the logs";
  (* The floor is load-bearing: raise it above the achievable confidence and the
     same evidence proceeds. *)
  check (gate ~confidence_floor:0.999 silent = Proceed)
    "GATE the confidence floor actually gates";
  check (gate silent = gate silent) "GATE is deterministic in the report"

(* ------------------------------------------------------- CALIBRATION layer *)

let calibration_layer () =
  let sample path output realized =
    match update ~prior:uniform_prior (ev path output) with
    | Ok p -> { predicted = p; realized }
    | Error m -> failwith m
  in
  (* Anti-vacuity: an empty sample must refuse, not score perfectly. *)
  (match calibrate [] with
  | Ok _ -> check false "CALIBRATION an empty sample is refused"
  | Error _ -> incr passed);

  (* A classifier whose predictions come true beats an uninformed guess. *)
  (match
     calibrate
       [ sample true false Silent_divergence; sample false false Stable;
         sample false true Regressed; sample true true Structural_drift ]
   with
  | Error m -> check false ("CALIBRATION well-predicted sample :: " ^ m)
  | Ok c ->
      check (c.samples = 4) "CALIBRATION counts its samples";
      check (c.accuracy = 1.0) "CALIBRATION argmax agreement is measured";
      check (c.brier < 0.75) "CALIBRATION brier beats the uniform baseline";
      check (c.log_loss < 2.0) "CALIBRATION log-loss beats the uniform baseline";
      check c.beats_uniform "CALIBRATION a good classifier beats uniform");

  (* THE control that matters. If the realized outcome is always the state the
     classifier thinks least likely, it must report that it does NOT beat
     uniform — otherwise calibration is theatre and the confidence figure is
     decoration. *)
  (match
     calibrate
       [ sample true false Regressed; sample false false Regressed;
         sample true false Stable; sample false true Silent_divergence ]
   with
  | Error m -> check false ("CALIBRATION adversarial sample :: " ^ m)
  | Ok c ->
      check (not c.beats_uniform) "CALIBRATION a wrong classifier does NOT beat uniform";
      check (contains (render_calibration c) "DOES NOT BEAT UNIFORM")
        "CALIBRATION the failure is stated in the rendered line, not buried")

let () =
  Printf.printf "=== expect posterior ===\n";
  List.iter
    (fun (name, layer) -> layer (); Printf.printf "  %-12s done\n" name)
    [ ("likelihood", likelihood_layer); ("posterior", posterior_layer);
      ("refusal", refusal_layer); ("rete", rete_layer); ("report", report_layer); ("gate", gate_layer);
      ("calibration", calibration_layer) ];
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_expect_posterior" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_expect_posterior ]);
  exit (Suite_telemetry.exit_code self)
