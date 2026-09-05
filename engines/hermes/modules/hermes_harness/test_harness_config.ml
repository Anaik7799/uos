(* Battle-testing the configuration grammar + activity algebra + behaviour.

   The load-bearing properties: the composite fold obeys the SAME laws as the
   parity roll-up (join semilattice, Divergent absorbs, empty is Unmapped never a
   pass); Gate is fail-closed (B does not run when A grants no credit); Annotate
   never changes semantics; plan is total and pure (executes nothing). *)

let passed = ref 0
let failures = ref []

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

let contains text needle =
  let l = String.length text and n = String.length needle in
  let rec loop i = i + n <= l && (String.sub text i n = needle || loop (i + 1)) in
  n = 0 || loop 0

let all_verdicts = Parity_algebra.[ Unmapped; Blocked; Verified; Divergent ]

(* A driver of constants, counting invocations -- lets tests observe exactly
   which primitives ran. *)
let counting_driver ?(capture = Parity_algebra.Verified) ?(compare = Parity_algebra.Verified)
    ?(preflight = Parity_algebra.Verified) () =
  let calls = ref [] in
  let hit name v = calls := name :: !calls; v in
  ( Harness_config.
      { capture = (fun _ -> hit "capture" capture);
        compare = (fun _ -> hit "compare" compare);
        check_contracts = (fun () -> hit "contracts" Parity_algebra.Verified);
        check_determinism = (fun () -> hit "determinism" Parity_algebra.Verified);
        preflight = (fun _ -> hit "preflight" preflight);
        reconcile = (fun _ -> hit "reconcile" Parity_algebra.Verified);
        report = (fun () -> hit "report" Parity_algebra.Verified) },
    calls )

(* --------------------------------------------------------- ALGEBRA layer *)

let algebra_layer () =
  let open Harness_config in
  (* Empty composite is Unmapped -- the vacuous-truth guard. *)
  check (outcome_of_list [] = Parity_algebra.Unmapped) "ALGEBRA empty fold is Unmapped" "";
  (* Join laws, exhaustively over the lattice. *)
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          check
            (outcome_of_list [ a; b ] = outcome_of_list [ b; a ])
            "ALGEBRA fold is commutative" "";
          List.iter
            (fun c ->
              check
                (outcome_of_list [ outcome_of_list [ a; b ]; c ]
                 = outcome_of_list [ a; outcome_of_list [ b; c ] ])
                "ALGEBRA fold is associative" "")
            all_verdicts)
        all_verdicts;
      check (outcome_of_list [ a; a ] = a) "ALGEBRA fold is idempotent" "";
      check
        (outcome_of_list [ a; Parity_algebra.Divergent ] = Parity_algebra.Divergent)
        "ALGEBRA Divergent absorbs" "")
    all_verdicts

(* ------------------------------------------------------------ PLAN layer *)

let plan_layer () =
  let open Harness_config in
  (* plan is total and pure: nothing runs. *)
  let driver, calls = counting_driver () in
  ignore driver;
  let cfg =
    Annotate
      ( "prove the transports slice",
        Seq
          [ Preflight [];
            Gate (Compare (Slices [ "hermes.model_routing.provider_transports" ]), Report) ] )
  in
  let steps = plan cfg in
  check (!calls = []) "PLAN executes nothing" "";
  check (List.length steps = 3) "PLAN linearizes all primitives (both gate arms)"
    (string_of_int (List.length steps));
  (* Intent propagates to the innermost steps. *)
  check
    (List.for_all (fun s -> s.why = Some "prove the transports slice") steps)
    "PLAN intent reaches every step" "";
  check (contains (render_plan steps) "compare") "PLAN renders the actions" ""

(* ------------------------------------------------------- BEHAVIOUR layer *)

let behaviour_layer () =
  let open Harness_config in
  (* A gate is fail-closed: when A grants no credit, B does not run. *)
  let driver, calls = counting_driver ~preflight:Parity_algebra.Blocked () in
  let verdict, outcomes = execute driver (Gate (Preflight [], Compare All)) in
  check (verdict = Parity_algebra.Blocked) "BEHAVIOUR a failed gate carries A's verdict" "";
  check (not (List.mem "compare" !calls)) "BEHAVIOUR gate is fail-closed: B did not run" "";
  check (List.length outcomes = 1) "BEHAVIOUR gated-out B leaves no outcome" "";

  (* When A verifies, B runs and the gate folds both. *)
  let driver2, calls2 = counting_driver () in
  let verdict2, outcomes2 = execute driver2 (Gate (Preflight [], Compare All)) in
  check (verdict2 = Parity_algebra.Verified) "BEHAVIOUR a passed gate runs B" "";
  check (List.mem "compare" !calls2) "BEHAVIOUR B ran after a green gate" "";
  check (List.length outcomes2 = 2) "BEHAVIOUR both arms leave outcomes" "";

  (* Seq/Par outcomes fold with the join; a Divergent child absorbs. *)
  let driver3, _ = counting_driver ~compare:Parity_algebra.Divergent () in
  let verdict3, _ = execute driver3 (Seq [ Capture All; Compare All; Report ]) in
  check (verdict3 = Parity_algebra.Divergent) "BEHAVIOUR Divergent absorbs in Seq" "";
  let verdict4, _ = execute driver3 (Par [ Capture All; Compare All ]) in
  check (verdict4 = Parity_algebra.Divergent) "BEHAVIOUR Divergent absorbs in Par" "";

  (* Par is order-independent in outcome. *)
  let driver5, _ = counting_driver ~capture:Parity_algebra.Blocked () in
  let v_ab, _ = execute driver5 (Par [ Capture All; Compare All ]) in
  let v_ba, _ = execute driver5 (Par [ Compare All; Capture All ]) in
  check (v_ab = v_ba) "BEHAVIOUR Par outcome is order-independent" "";

  (* Annotate is outcome-transparent. *)
  let driver6, _ = counting_driver ~compare:Parity_algebra.Blocked () in
  let bare, _ = execute driver6 (Compare All) in
  let annotated, _ = execute driver6 (Annotate ("why", Compare All)) in
  check (bare = annotated) "BEHAVIOUR Annotate never changes the outcome" "";

  (* Empty composites are Unmapped, never a silent pass. *)
  let driver7, _ = counting_driver () in
  let empty_seq, _ = execute driver7 (Seq []) in
  check (empty_seq = Parity_algebra.Unmapped) "BEHAVIOUR empty Seq is Unmapped" ""

(* ------------------------------------------------------ END-TO-END layer *)

let end_to_end_layer () =
  let open Harness_config in
  (* A realistic declarative config: preflight gates the whole pipeline; capture
     precedes compare; contracts, determinism and reconcile run as intent checks;
     report last. One Divergent (the honest interrupt_control clamp) absorbs into
     the folded verdict -- the config reports reality, not hope. *)
  let blueprint =
    Blueprint.
      [ { id = "transports"; target = "hermes.model_routing.provider_transports";
          desired = Parity_algebra.Verified;
          intent = "reproduce the frozen provider transport shaping and decoding";
          requires = [] } ]
  in
  let cfg =
    Gate
      ( Preflight [],
        Seq
          [ Annotate ("pin the oracle", Capture All);
            Annotate ("measure parity", Compare All);
            Par [ Check_contracts; Check_determinism; Reconcile blueprint ];
            Report ] )
  in
  let driver, calls = counting_driver ~compare:Parity_algebra.Divergent () in
  let verdict, outcomes = execute driver cfg in
  check (verdict = Parity_algebra.Divergent) "E2E the honest divergence absorbs" "";
  check
    (List.length outcomes = 7)
    "E2E all primitives ran and left outcomes" (string_of_int (List.length outcomes));
  List.iter
    (fun name -> check (List.mem name !calls) ("E2E ran " ^ name) "")
    [ "preflight"; "capture"; "compare"; "contracts"; "determinism"; "reconcile"; "report" ];
  (* And the same config under a blocked preflight runs NOTHING downstream. *)
  let driver8, calls8 = counting_driver ~preflight:Parity_algebra.Blocked () in
  let verdict8, _ = execute driver8 cfg in
  check (verdict8 = Parity_algebra.Blocked) "E2E blocked preflight blocks the pipeline" "";
  check
    (not (List.exists (fun c -> c <> "preflight") !calls8))
    "E2E nothing downstream of a failed gate ran" ""

(* ---------------------------------------------------------- LEVELS layer *)
(* Fractal-layer coverage is DATA: the standard pipeline must exercise every
   level of the fractal, L0 product through LX control. A level no activity
   reaches is a visible gap, exactly like an ontology aspect nobody addressed. *)

let levels_layer () =
  let open Harness_config in
  let blueprint =
    Blueprint.
      [ { id = "product"; target = "hermes"; desired = Parity_algebra.Verified;
          intent = "the whole product reaches parity with the frozen reference";
          requires = [] } ]
  in
  let pipeline = standard_pipeline ~preflight:[] ~blueprint in
  let covered = levels_of pipeline in
  List.iter
    (fun level ->
      check (List.mem level covered)
        ("LEVELS standard pipeline exercises " ^ Fractal_ontology.level_name level) "")
    Fractal_ontology.levels;
  (* Primitive mappings are honest: contracts at L3, preflight at LX, compare
     spans fixture->receipt. *)
  check (levels_of Check_contracts = [ Fractal_ontology.L3_contract ]) "LEVELS contracts at L3" "";
  check (List.mem Fractal_ontology.LX_control (levels_of (Preflight []))) "LEVELS preflight at LX" "";
  check
    (List.mem Fractal_ontology.L6_receipt (levels_of (Compare All))
     && List.mem Fractal_ontology.L4_fixture (levels_of (Compare All)))
    "LEVELS compare spans fixtures to receipts" "";
  (* Report observes; it exercises only the product-level view. *)
  check (levels_of Report = [ Fractal_ontology.L0_product ]) "LEVELS report is the L0 view" ""

(* -------------------------------------------------------------- BDD layer *)

let bdd_layer () =
  let open Harness_config in
  (* Given a blocked resource preflight, when the standard pipeline executes,
     then nothing downstream runs and the verdict is Blocked -- the R13 story as
     configuration. *)
  let driver, calls = counting_driver ~preflight:Parity_algebra.Blocked () in
  let blueprint = [] in
  let verdict, _ = execute driver (standard_pipeline ~preflight:[] ~blueprint) in
  check (verdict = Parity_algebra.Blocked) "BDD blocked preflight blocks the standard pipeline" "";
  check
    (List.for_all (fun c -> c = "preflight") !calls)
    "BDD nothing downstream of the failed gate ran" (String.concat "," !calls);

  (* Given a green preflight, when the pipeline executes, then compare,
     contracts, determinism, reconcile and report all run. *)
  let driver2, calls2 = counting_driver () in
  let _, _ = execute driver2 (standard_pipeline ~preflight:[] ~blueprint) in
  List.iter
    (fun name -> check (List.mem name !calls2) ("BDD standard pipeline runs " ^ name) "")
    [ "preflight"; "compare"; "contracts"; "determinism"; "reconcile"; "report" ]

(* ------------------------------------------------------------- FUZZ layer *)

let fuzz_layer () =
  let open Harness_config in
  Random.init 20260808;
  let random_verdict () = List.nth all_verdicts (Random.int 4) in
  let rec random_activity depth =
    if depth = 0 then
      match Random.int 5 with
      | 0 -> Capture All
      | 1 -> Compare (Slices [ "hermes.a.b" ])
      | 2 -> Check_contracts
      | 3 -> Preflight []
      | _ -> Report
    else
      match Random.int 4 with
      | 0 -> Seq (List.init (Random.int 3) (fun _ -> random_activity (depth - 1)))
      | 1 -> Par (List.init (Random.int 3) (fun _ -> random_activity (depth - 1)))
      | 2 -> Gate (random_activity (depth - 1), random_activity (depth - 1))
      | _ -> Annotate ("why", random_activity (depth - 1))
  in
  let survived = ref 0 in
  for _ = 1 to 300 do
    let activity = random_activity (1 + Random.int 3) in
    let driver, _ =
      counting_driver ~capture:(random_verdict ()) ~compare:(random_verdict ())
        ~preflight:(random_verdict ()) ()
    in
    match
      let steps = plan activity in
      let verdict, trail = execute driver activity in
      (* plan is total; execute never raises; the trail never exceeds the plan
         (gating can only shrink what runs); Annotate transparency holds. *)
      let annotated, _ = execute driver (Annotate ("x", activity)) in
      List.length trail <= List.length steps && annotated = verdict
    with
    | true -> incr survived
    | false -> check false "FUZZ invariants hold on a random activity" ""
    | exception exn -> check false "FUZZ plan/execute raised" (Printexc.to_string exn)
  done;
  check (!survived = 300) "FUZZ 300 random activities survive" (string_of_int !survived)

(* ------------------------------------------------------------ CHAOS layer *)
(* A crashing subsystem must fail CLOSED as that primitive's Blocked verdict --
   an exception proves nothing about the candidate and must not kill the run. *)

let chaos_layer () =
  let open Harness_config in
  let raising =
    { capture = (fun _ -> failwith "capture crashed");
      compare = (fun _ -> Parity_algebra.Verified);
      check_contracts = (fun () -> failwith "gospel crashed");
      check_determinism = (fun () -> Parity_algebra.Verified);
      preflight = (fun _ -> Parity_algebra.Verified);
      reconcile = (fun _ -> Parity_algebra.Verified);
      report = (fun () -> Parity_algebra.Verified) }
  in
  (match execute raising (Seq [ Capture All; Compare All; Check_contracts ]) with
  | verdict, trail ->
      check (verdict = Parity_algebra.Blocked) "CHAOS a crashing driver blocks, never verifies" "";
      check (List.length trail = 3) "CHAOS the rest of the pipeline still ran" "";
      check
        (List.exists (fun o -> o.verdict = Parity_algebra.Verified) trail)
        "CHAOS healthy primitives still verified" ""
  | exception exn ->
      check false "CHAOS execute must not propagate a driver crash" (Printexc.to_string exn));
  (* A crashing gate CONDITION is a failed gate: the guarded activity never runs. *)
  let ran_b = ref false in
  let raising_gate =
    { raising with
      compare = (fun _ -> ran_b := true; Parity_algebra.Verified) }
  in
  (match execute raising_gate (Gate (Capture All, Compare All)) with
  | verdict, _ ->
      check (verdict = Parity_algebra.Blocked) "CHAOS a crashed gate condition blocks" "";
      check (not !ran_b) "CHAOS the guarded activity did not run after the crash" ""
  | exception exn ->
      check false "CHAOS gate crash must not propagate" (Printexc.to_string exn))

let () =
  print_endline "harness config suite";
  List.iter
    (fun (name, layer) -> layer (); Printf.printf "  %-12s done\n" name)
    [ ("algebra", algebra_layer); ("plan", plan_layer); ("behaviour", behaviour_layer);
      ("end-to-end", end_to_end_layer); ("levels", levels_layer); ("bdd", bdd_layer);
      ("fuzz", fuzz_layer); ("chaos", chaos_layer) ];
  Printf.printf "\npassed: %d   failed: %d\n" !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_harness_config" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_harness_config ]);
  exit (Suite_telemetry.exit_code self)
