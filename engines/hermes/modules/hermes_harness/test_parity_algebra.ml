(* Battle-testing the parity algebra.

   The laws are the point. An algebra whose laws are only asserted in prose is
   a naming exercise; these are checked exhaustively over the verdict lattice,
   which is small enough that "exhaustive" is literal rather than sampled. *)

let passed = ref 0
let failures = ref []

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

let all =
  [ Parity_algebra.Unmapped; Parity_algebra.Blocked; Parity_algebra.Verified;
    Parity_algebra.Divergent ]

(* ------------------------------------------------------------- UNIT layer *)

let unit_layer () =
  check (List.length (List.sort_uniq compare (List.map Parity_algebra.name all)) = 4)
    "UNIT verdict names are distinct" "";
  check (Parity_algebra.grants_credit Parity_algebra.Verified) "UNIT verified grants credit" "";
  List.iter
    (fun verdict ->
      check
        (not (Parity_algebra.grants_credit verdict))
        ("UNIT " ^ Parity_algebra.name verdict ^ " withholds credit") "")
    [ Parity_algebra.Unmapped; Parity_algebra.Blocked; Parity_algebra.Divergent ];
  check (Parity_algebra.asserts_defect Parity_algebra.Divergent)
    "UNIT divergent asserts a defect" "";
  List.iter
    (fun verdict ->
      check
        (not (Parity_algebra.asserts_defect verdict))
        ("UNIT " ^ Parity_algebra.name verdict ^ " asserts no defect") "")
    [ Parity_algebra.Unmapped; Parity_algebra.Blocked; Parity_algebra.Verified ]

(* --------------------------------------------------------- PROPERTY layer *)
(* Exhaustive over the lattice: 4, 16 and 64 cases, so no sampling. *)

let property_layer () =
  (* Commutative. *)
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          check
            (Parity_algebra.combine a b = Parity_algebra.combine b a)
            "PROPERTY combine is commutative"
            (Parity_algebra.name a ^ "," ^ Parity_algebra.name b))
        all)
    all;

  (* Associative. *)
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          List.iter
            (fun c ->
              check
                (Parity_algebra.combine (Parity_algebra.combine a b) c
                = Parity_algebra.combine a (Parity_algebra.combine b c))
                "PROPERTY combine is associative" "")
            all)
        all)
    all;

  (* Idempotent. *)
  List.iter
    (fun a ->
      check (Parity_algebra.combine a a = a) "PROPERTY combine is idempotent" "")
    all;

  (* Identity. *)
  List.iter
    (fun a ->
      check
        (Parity_algebra.combine Parity_algebra.identity a = a)
        "PROPERTY identity is neutral" (Parity_algebra.name a))
    all;

  (* Divergent absorbs: one proved divergence sinks any amount of agreement. *)
  List.iter
    (fun a ->
      check
        (Parity_algebra.combine Parity_algebra.Divergent a = Parity_algebra.Divergent)
        "PROPERTY divergent absorbs" (Parity_algebra.name a))
    all;

  (* Monotone: adding a child never improves a parent verdict. *)
  List.iter
    (fun existing ->
      List.iter
        (fun added ->
          let before = Parity_algebra.roll_up ~required:true [ existing ] in
          let after = Parity_algebra.roll_up ~required:true [ existing; added ] in
          check
            (Parity_algebra.grants_credit after
            = (Parity_algebra.grants_credit before && Parity_algebra.grants_credit added))
            "PROPERTY roll-up grants credit only when every child does" "")
        all)
    all;

  (* Order independence, which is what makes the join the right structure. *)
  let sample = [ Parity_algebra.Verified; Parity_algebra.Blocked; Parity_algebra.Unmapped ] in
  check
    (Parity_algebra.roll_up ~required:true sample
    = Parity_algebra.roll_up ~required:true (List.rev sample))
    "PROPERTY roll-up is order independent" ""

(* -------------------------------------------------------------- BDD layer *)

let bdd_layer () =
  (* Given a required node with NO children, when rolled up, then it is
     Unmapped -- never Verified. This is the vacuous-truth trap: a fold
     returning the conjunction identity would report an empty catalog fully
     verified, which is how an evidence system reports 100% having proved
     nothing. *)
  check
    (Parity_algebra.roll_up ~required:true [] = Parity_algebra.Unmapped)
    "BDD an empty required node is unmapped, not verified" "";
  check
    (not (Parity_algebra.grants_credit (Parity_algebra.roll_up ~required:true [])))
    "BDD an empty required node grants no credit" "";

  (* Given one blocked child among verified ones, the parent is blocked: a
     family is not verified while any part of it is unproven. *)
  check
    (Parity_algebra.roll_up ~required:true
       [ Parity_algebra.Verified; Parity_algebra.Verified; Parity_algebra.Blocked ]
    = Parity_algebra.Blocked)
    "BDD one blocked child blocks the family" "";

  (* Given a divergence among blocked children, divergence wins: the proved
     defect is the more important fact. *)
  check
    (Parity_algebra.roll_up ~required:true
       [ Parity_algebra.Blocked; Parity_algebra.Divergent ]
    = Parity_algebra.Divergent)
    "BDD divergence outranks blockage" "";

  (* Given every child verified, the family is verified. *)
  check
    (Parity_algebra.roll_up ~required:true
       [ Parity_algebra.Verified; Parity_algebra.Verified ]
    = Parity_algebra.Verified)
    "BDD all verified children verify the family" "";

  (* Given a diagnostic that only blocks credit, it must not become a
     divergence when composed. R5 in algebraic form. *)
  check
    (Parity_algebra.of_diagnostic_impact Fractal_diagnostic.Blocks_credit
    = Parity_algebra.Blocked)
    "BDD blocked credit maps to Blocked, not Divergent" "";
  check
    (Parity_algebra.of_diagnostic_impact Fractal_diagnostic.Denies_credit
    = Parity_algebra.Divergent)
    "BDD denied credit maps to Divergent" ""

(* ---------------------------------------------------------- FEATURE layer *)

let feature_layer () =
  let verdicts =
    [ Parity_algebra.Verified; Parity_algebra.Verified; Parity_algebra.Blocked;
      Parity_algebra.Unmapped ]
  in
  let report = Parity_algebra.report ~required:true verdicts in
  check (report.total = 4) "FEATURE report counts children" "";
  check (report.verified = 2) "FEATURE report counts verified" "";
  check (report.blocked = 1) "FEATURE report counts blocked" "";
  check (report.unmapped = 1) "FEATURE report counts unmapped" "";
  check (report.verdict = Parity_algebra.Blocked) "FEATURE report verdict is the roll-up" "";
  check (Parity_algebra.credit_percent report = 50) "FEATURE percent is verified/total" "";

  (* The percentage and the verdict are deliberately independent: 94/95 is not
     verified, and reporting only the percentage is how a project talks itself
     into believing it is nearly done. *)
  let nearly =
    Parity_algebra.report ~required:true
      (Parity_algebra.Blocked :: List.init 94 (fun _ -> Parity_algebra.Verified))
  in
  check (Parity_algebra.credit_percent nearly = 98) "FEATURE nearly-complete percent is high"
    (string_of_int (Parity_algebra.credit_percent nearly));
  check (nearly.verdict <> Parity_algebra.Verified)
    "FEATURE nearly-complete is still not verified" "";
  check
    (String.length (Parity_algebra.render_report nearly) > 0)
    "FEATURE report renders" ""

(* ------------------------------------------------------------- FUZZ layer *)

let fuzz_layer () =
  Random.init 20260808;
  let random () = List.nth all (Random.int 4) in
  let survived = ref 0 in
  for _ = 1 to 2000 do
    let size = Random.int 12 in
    let verdicts = List.init size (fun _ -> random ()) in
    let required = Random.bool () in
    match
      let rolled = Parity_algebra.roll_up ~required verdicts in
      let report = Parity_algebra.report ~required verdicts in
      let percent = Parity_algebra.credit_percent report in
      (* Invariants that must hold for any input whatsoever. *)
      report.verdict = rolled
      && report.verified + report.blocked + report.divergent + report.unmapped
         = report.total
      && percent >= 0 && percent <= 100
      && (not (Parity_algebra.grants_credit rolled)
         || List.for_all (fun v -> v = Parity_algebra.Verified) verdicts)
      && ((not (List.mem Parity_algebra.Divergent verdicts))
         || rolled = Parity_algebra.Divergent)
    with
    | true -> incr survived
    | false -> check false "FUZZ algebra invariants hold" ""
    | exception exn -> check false "FUZZ algebra does not raise" (Printexc.to_string exn)
  done;
  check (!survived = 2000) "FUZZ 2000 random roll-ups hold every invariant"
    (string_of_int !survived)

(* ------------------------------------------------------------ CHAOS layer *)

let chaos_layer () =
  (* A very large level must not overflow the percentage or blow the stack. *)
  let huge = List.init 100_000 (fun index ->
      if index = 0 then Parity_algebra.Blocked else Parity_algebra.Verified)
  in
  let report = Parity_algebra.report ~required:true huge in
  check (report.total = 100_000) "CHAOS 100k children counted" "";
  check (report.verdict = Parity_algebra.Blocked) "CHAOS one blocked child still blocks" "";
  check
    (Parity_algebra.credit_percent report = 99)
    "CHAOS percent does not overflow" (string_of_int (Parity_algebra.credit_percent report));

  (* All-divergent at scale still reports divergent, not a rounded percentage. *)
  let all_bad = List.init 10_000 (fun _ -> Parity_algebra.Divergent) in
  let bad_report = Parity_algebra.report ~required:true all_bad in
  check (bad_report.verdict = Parity_algebra.Divergent) "CHAOS mass divergence is divergent" "";
  check (Parity_algebra.credit_percent bad_report = 0) "CHAOS mass divergence is 0%" "";

  (* An optional node with no children is vacuously verified, but a required
     one is not -- the distinction must survive the empty case. *)
  check
    (Parity_algebra.roll_up ~required:false [] = Parity_algebra.Verified)
    "CHAOS empty optional node is verified" "";
  check
    (Parity_algebra.roll_up ~required:true [] = Parity_algebra.Unmapped)
    "CHAOS empty required node is unmapped" ""

(* -------------------------------------------------------- STRUCTURE layer *)

let structure_layer () =
  (* Every constructor is exercised by the fixtures above. *)
  check (List.length all = 4) "STRUCTURE every verdict enumerated" "";
  (* Exactly one grants credit, exactly one asserts a defect. Two verdicts do
     neither, and that gap is the whole point of the lattice. *)
  check
    (List.length (List.filter Parity_algebra.grants_credit all) = 1)
    "STRUCTURE exactly one verdict grants credit" "";
  check
    (List.length (List.filter Parity_algebra.asserts_defect all) = 1)
    "STRUCTURE exactly one verdict asserts a defect" "";
  check
    (List.length
       (List.filter
          (fun v ->
            (not (Parity_algebra.grants_credit v)) && not (Parity_algebra.asserts_defect v))
          all)
    = 2)
    "STRUCTURE two verdicts withhold without accusing" ""

let () =
  print_endline "parity algebra suite";
  List.iter
    (fun (name, layer) ->
      layer ();
      Printf.printf "  %-12s done\n" name)
    [ ("unit", unit_layer); ("property", property_layer); ("bdd", bdd_layer);
      ("feature", feature_layer); ("fuzz", fuzz_layer); ("chaos", chaos_layer);
      ("structure", structure_layer) ];
  Printf.printf "\npassed: %d   failed: %d\n" !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_parity_algebra" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_parity_algebra ]);
  exit (Suite_telemetry.exit_code self)
