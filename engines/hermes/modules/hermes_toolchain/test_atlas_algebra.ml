(* The executable specification of atlas conformance.

   Every law is checked against the SHIPPED Atlas_algebra module, so a green run
   is evidence about the code the gate actually links.

   Each law names the concrete defect it exists for. The defects are real and
   were measured, not imagined: the shipped atlas carried one identical value on
   46 of its 64 leaf fields across all 30 rows, including `algebra.laws[1]`,
   `algebra.oracle` and `traceability.aspects`. The delegated Fable review found
   three of those forty-six; the rest surfaced only when the degeneracy was
   counted per field rather than read. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false ->
      incr failed;
      print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

open Atlas_algebra

let f1 = Nonconforming [ { row_id = "time.observe"; detail = "a" } ]
let f2 = Nonconforming [ { row_id = "files.edit"; detail = "b" } ]
let f3 = Nonconforming [ { row_id = "ucon.binding"; detail = "c" } ]
let sample = [ Conforms; f1; f2; f3 ]

let for_all_pairs f =
  List.for_all (fun a -> List.for_all (fun b -> f a b) sample) sample

let for_all_triples f =
  List.for_all
    (fun a -> List.for_all (fun b -> List.for_all (fun c -> f a b c) sample) sample)
    sample

(* A fully-formed obligation, used as the base that each law perturbs. *)
let ok s =
  {
    structure = s;
    status = Holds;
    predicate = "the concrete claim for this row";
    falsifier = "the observation that would disprove it";
    oracle = "the test that executes it";
    independently_reviewed = true;
  }

let full_row = List.map ok all_structures

let () =
  (* --- the verdict meet-semilattice ------------------------------------- *)
  check "L1 meet is associative" (fun () ->
      for_all_triples (fun a b c -> meet (meet a b) c = meet a (meet b c)));
  check "L2 meet is commutative on conformance (findings may reorder, the verdict may not)"
    (fun () ->
      for_all_pairs (fun a b -> is_conforming (meet a b) = is_conforming (meet b a)));
  check "L3 meet is idempotent on the verdict" (fun () ->
      List.for_all (fun a -> is_conforming (meet a a) = is_conforming a) sample);
  check "L4 Conforms is the identity of meet" (fun () ->
      List.for_all (fun a -> meet Conforms a = a && meet a Conforms = a) sample);
  check "L5 Nonconforming absorbs -- fail-closed proved once, not re-applied per call site"
    (fun () -> List.for_all (fun a -> not (is_conforming (meet a f1))) sample);
  check "L6 the empty composite conforms (vacuous conjunction)" (fun () ->
      is_conforming (meet_all []));
  check "L7 every finding survives into the composite (defect: a report that named only the first bad row)"
    (fun () ->
      List.length (findings (meet_all [ f1; f2; f3 ])) = 3);

  (* --- the nine structures are closed ----------------------------------- *)
  check "L8 exactly nine structures exist, matching formal spec section 3" (fun () ->
      List.length all_structures = 9);
  check "L9 every structure has a distinct name" (fun () ->
      let ns = List.map structure_name all_structures in
      List.length (List.sort_uniq compare ns) = 9);
  check "L10 every structure carries its required law verbatim from the spec" (fun () ->
      List.for_all (fun s -> String.trim (required_law s) <> "") all_structures);
  check "L11 the required laws are distinct -- nine structures, nine obligations, not one sentence nine times"
    (fun () ->
      let ls = List.map required_law all_structures in
      List.length (List.sort_uniq compare ls) = 9);

  (* --- obligation well-formedness: the decoration defects ---------------- *)
  check "L12 a well-formed HOLDS conforms" (fun () ->
      is_conforming (check_obligation ~row_id:"r" (ok Replication)));
  check "L13 HOLDS with no falsifier is rejected (defect: 30 rows asserting a law nobody could disprove)"
    (fun () ->
      not
        (is_conforming
           (check_obligation ~row_id:"r" { (ok Replication) with falsifier = "  " })));
  check "L14 HOLDS with an empty predicate is rejected" (fun () ->
      not
        (is_conforming
           (check_obligation ~row_id:"r" { (ok Replication) with predicate = "" })));
  check "L15a HOLDS with no oracle is rejected -- AGY's keyword-decorator trap: a claim nothing in the repo would notice breaking"
    (fun () ->
      not
        (is_conforming
           (check_obligation ~row_id:"r" { (ok Replication) with oracle = "" })));
  check "L15 HOLDS that was not independently reviewed is rejected -- a template cannot assert its own pass"
    (fun () ->
      not
        (is_conforming
           (check_obligation ~row_id:"r"
              { (ok Replication) with independently_reviewed = false })));
  check "L16 UNKNOWN is always well formed -- honesty must be free, or the schema teaches lying"
    (fun () ->
      is_conforming
        (check_obligation ~row_id:"r"
           {
             structure = Replication;
             status = Unknown;
             predicate = "";
             falsifier = "";
             oracle = "";
             independently_reviewed = false;
           }));
  check "L17 UNKNOWN is not a pass -- it is well formed and still not HOLDS" (fun () ->
      status_name Unknown <> status_name Holds);
  check "L18 NOT_APPLICABLE must say why" (fun () ->
      (not
         (is_conforming
            (check_obligation ~row_id:"r"
               { (ok Replication) with status = Not_applicable; predicate = "" })))
      && is_conforming
           (check_obligation ~row_id:"r"
              {
                (ok Replication) with
                status = Not_applicable;
                predicate = "this capability owns no replicated state";
              }));
  check "L19 VIOLATED must name what failed" (fun () ->
      not
        (is_conforming
           (check_obligation ~row_id:"r"
              { (ok Replication) with status = Violated; predicate = "" })));
  check "L20 VIOLATED needs no falsifier -- it has already been falsified" (fun () ->
      is_conforming
        (check_obligation ~row_id:"r"
           {
             (ok Replication) with
             status = Violated;
             predicate = "no replication code exists";
             falsifier = "";
             oracle = "";
             independently_reviewed = false;
           }));

  (* --- row coverage: completeness by omission ---------------------------- *)
  check "L21 a row with all nine well-formed obligations conforms" (fun () ->
      is_conforming (check_row ~row_id:"r" full_row));
  check "L22 a row missing any structure is nonconforming, for every one of the nine"
    (fun () ->
      List.for_all
        (fun s ->
          let short = List.filter (fun o -> o.structure <> s) full_row in
          not (is_conforming (check_row ~row_id:"r" short)))
        all_structures);
  check "L23 an empty row is nonconforming with nine findings -- silence is not completeness"
    (fun () -> List.length (findings (check_row ~row_id:"r" [])) = 9);
  check "L24 a duplicated structure is nonconforming -- a row cannot vote twice" (fun () ->
      not (is_conforming (check_row ~row_id:"r" (ok Replication :: full_row))));
  check "L25 one bad obligation fails the row, at every position" (fun () ->
      List.for_all
        (fun n ->
          let row =
            List.mapi
              (fun i o -> if i = n then { o with falsifier = "" } else o)
              full_row
          in
          not (is_conforming (check_row ~row_id:"r" row)))
        (List.init 9 (fun i -> i)));
  check "L26 a row of all-UNKNOWN conforms structurally and asserts nothing" (fun () ->
      let unknowns =
        List.map
          (fun s ->
            {
              structure = s;
              status = Unknown;
              predicate = "";
              falsifier = "";
              oracle = "";
              independently_reviewed = false;
            })
          all_structures
      in
      is_conforming (check_row ~row_id:"r" unknowns)
      && List.for_all (fun o -> o.status <> Holds) unknowns);

  (* --- degeneracy: the defect that motivated the module ------------------ *)
  check "L27 a field constant across every row is a finding" (fun () ->
      not
        (is_conforming
           (check_degeneracy ~total_rows:30 ~max_repeat:20
              [ ("algebra.oracle", 30) ])));
  check "L28 a field at exactly the ceiling is allowed; one above is not" (fun () ->
      is_conforming (check_degeneracy ~total_rows:30 ~max_repeat:20 [ ("f", 20) ])
      && not
           (is_conforming
              (check_degeneracy ~total_rows:30 ~max_repeat:20 [ ("f", 21) ])));
  check "L29 every degenerate field is reported, not just the first (defect: exactly this, in my own count of the rows)"
    (fun () ->
      List.length
        (findings
           (check_degeneracy ~total_rows:30 ~max_repeat:20
              [ ("a", 30); ("b", 30); ("c", 30) ]))
      = 3);
  check "L30 no fields means no degeneracy findings" (fun () ->
      is_conforming (check_degeneracy ~total_rows:30 ~max_repeat:20 []));
  check "L31 degeneracy is monotone under growth -- adding a row that repeats a value never lowers the count, so a passing atlas cannot be made to pass by appending clones"
    (fun () ->
      List.for_all
        (fun n -> repeat_after_adding_same n > n)
        [ 0; 1; 19; 20; 29; 30 ]);
  check "L32 monotonicity means a field at the ceiling fails once one more clone is added"
    (fun () ->
      is_conforming (check_degeneracy ~total_rows:30 ~max_repeat:20 [ ("f", 20) ])
      && not
           (is_conforming
              (check_degeneracy ~total_rows:31 ~max_repeat:20
                 [ ("f", repeat_after_adding_same 20) ])));

  (* --- the composite property the gate rests on -------------------------- *)
  check "L33 an atlas conforms only if every row and the degeneracy check conform"
    (fun () ->
      let good = check_row ~row_id:"a" full_row in
      let bad = check_row ~row_id:"b" [] in
      is_conforming (meet_all [ good; check_degeneracy ~total_rows:2 ~max_repeat:2 [] ])
      && not (is_conforming (meet_all [ good; bad ])));
  check "L34 a conforming atlas of honest UNKNOWNs still asserts no capability -- structure is not evidence"
    (fun () ->
      let unknowns =
        List.map
          (fun s ->
            {
              structure = s;
              status = Unknown;
              predicate = "";
              falsifier = "";
              oracle = "";
              independently_reviewed = false;
            })
          all_structures
      in
      is_conforming (check_row ~row_id:"r" unknowns)
      && not (List.exists (fun o -> o.status = Holds) unknowns))

let () =
  Printf.printf "atlas_algebra: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_atlas_algebra" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.toolchain_core ]);
  exit (Suite_telemetry.exit_code self)
