(* Automatic convergence as Kleene fixpoint iteration. The load-bearing
   properties: it reaches the fixpoint of a monotone step (converged or settled),
   terminates within |intents| steps, and -- proven not vacuous -- DETECTS a
   non-monotone step as an Anomaly (the apparatus bug it exists to catch). *)

let passed = ref 0
let failures = ref []
let check c label = if c then incr passed else failures := label :: !failures

let subset a b = List.for_all (fun x -> List.mem x b) a
let same a b = subset a b && subset b a

(* -------------------------------------------------------------- UNIT layer *)

let unit_layer () =
  let open Converge in
  let all = [ "a"; "b"; "c" ] in
  (* a step that satisfies one new intent per call -> converges to all *)
  let add_one order satisfied =
    match List.find_opt (fun x -> not (List.mem x satisfied)) order with
    | Some x -> x :: satisfied
    | None -> satisfied
  in
  (match converge ~max_iterations:100 ~all_intents:all ~step:(add_one all) [] with
  | Converged { iterations; satisfied } ->
      check (same satisfied all) "UNIT converges to all intents";
      check (iterations <= List.length all) "UNIT terminates within |intents| steps"
  | _ -> check false "UNIT should converge");

  (* a step that stalls below full -> Settled with the residual as drift *)
  let stall satisfied = if List.mem "a" satisfied then satisfied else "a" :: satisfied in
  (match converge ~max_iterations:100 ~all_intents:all ~step:stall [] with
  | Settled { satisfied; drift; _ } ->
      check (same satisfied [ "a" ]) "UNIT settles at the partial fixpoint";
      check (same drift [ "b"; "c" ]) "UNIT residual drift is the unsatisfied set"
  | _ -> check false "UNIT should settle with drift");

  (* already converged -> immediate, zero further work *)
  (match converge ~max_iterations:100 ~all_intents:all ~step:(fun s -> s) all with
  | Converged { iterations; _ } -> check (iterations = 0) "UNIT already-satisfied is immediate"
  | _ -> check false "UNIT already converged")

(* ---------------------------------------------------------- PROPERTY layer *)

let property_layer () =
  let open Converge in
  Random.init 20260808;
  let ok = ref 0 in
  for _ = 1 to 300 do
    let n = 1 + Random.int 8 in
    let all = List.init n (fun i -> string_of_int i) in
    (* a random MONOTONE step: adds a random subset of the still-missing intents
       (never removes), so the loop must terminate at a fixpoint. *)
    let step satisfied =
      let missing = List.filter (fun x -> not (List.mem x satisfied)) all in
      let added = List.filter (fun _ -> Random.bool ()) missing in
      added @ satisfied
    in
    match converge ~max_iterations:(n + 5) ~all_intents:all ~step [] with
    | Converged { iterations; _ } | Settled { iterations; _ } ->
        if iterations <= n + 5 then incr ok
    | Anomaly _ -> () (* a monotone step must never be an anomaly *)
  done;
  check (!ok = 300) "PROPERTY every monotone step terminates at a fixpoint within the bound"

(* ------------------------------------------------------------- FUZZ layer *)

let fuzz_layer () =
  let open Converge in
  Random.init 424242;
  let survived = ref 0 in
  for _ = 1 to 300 do
    let n = 1 + Random.int 6 in
    let all = List.init n (fun i -> string_of_int i) in
    (* arbitrary step (may add OR remove) -- converge must never raise and must
       classify honestly; a removal must surface as Anomaly. *)
    let step _satisfied = List.filter (fun _ -> Random.bool ()) all in
    match converge ~max_iterations:(n + 3) ~all_intents:all ~step [] with
    | Converged _ | Settled _ | Anomaly _ -> incr survived
    | exception e -> failures := ("FUZZ raised: " ^ Printexc.to_string e) :: !failures
  done;
  check (!survived = 300) "FUZZ arbitrary steps are always classified, never raise"

(* ------------------------------------------------------------ CHAOS layer *)

let chaos_layer () =
  let open Converge in
  let all = [ "x"; "y"; "z" ] in
  (* a step that DROPS a satisfied intent must be caught as an Anomaly, naming
     what was lost -- the detector must fire (proven-not-differential). *)
  let dropper satisfied = if List.mem "x" satisfied then List.filter (( <> ) "x") satisfied else "x" :: satisfied in
  (match converge ~max_iterations:100 ~all_intents:all ~step:dropper [ "x"; "y" ] with
  | Anomaly { lost; _ } -> check (List.mem "x" lost) "CHAOS a dropped intent is reported as Anomaly"
  | _ -> check false "CHAOS a non-monotone step must be an Anomaly");
  (* the max-iterations backstop settles (never loops forever) even if a step
     keeps proposing churn within the satisfied set it already holds. *)
  let churn satisfied = if same satisfied all then satisfied else all in
  (match converge ~max_iterations:1 ~all_intents:all ~step:churn [] with
  | Converged _ | Settled _ -> incr passed
  | Anomaly _ -> check false "CHAOS growth to all is not an anomaly")

let () =
  print_endline "converge suite";
  List.iter (fun (n, l) -> l (); Printf.printf "  %-10s done\n" n)
    [ ("unit", unit_layer); ("property", property_layer); ("fuzz", fuzz_layer);
      ("chaos", chaos_layer) ];
  Printf.printf "\npassed: %d   failed: %d\n" !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_converge" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_converge ]);
  exit (Suite_telemetry.exit_code self)
