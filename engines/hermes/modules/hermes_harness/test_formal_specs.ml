(* The formal specs must prove the real code, and the proof must be falsifiable:
   a deliberately broken law must be REFUTED with a model, or "unsat" means
   nothing. *)

let passed = ref 0
let failures = ref []

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

let () =
  (* Both critical-component specs are proved against the code as it is. *)
  List.iter
    (fun (name, outcome) ->
      match outcome with
      | Formal_specs.Proved -> incr passed
      | Formal_specs.Unavailable reason ->
          check false ("SPEC " ^ name ^ " proved") ("z3 unavailable: " ^ reason)
      | Formal_specs.Refuted model ->
          check false ("SPEC " ^ name ^ " proved") ("counterexample: " ^ model))
    (Formal_specs.verify_all ());

  (* Falsifiability: a spec whose law is deliberately broken must be refuted.
     Assert (negated) that combine is NOT commutative for the real table -- z3
     must find that unsat -- then assert a FALSE table entry and require sat.
     If z3 accepted the false entry as unsat too, the harness would be reading
     the solver wrong, and every "proved" above would be worthless. *)
  let broken_query =
    ";; deliberately inconsistent: the table says combine(V,B)=B AND =V\n\
     (declare-datatype Verdict ((Unmapped) (Blocked) (Verified) (Divergent)))\n\
     (declare-fun combine (Verdict Verdict) Verdict)\n\
     (assert (= (combine Verified Blocked) Blocked))\n\
     (assert (= (combine Verified Blocked) Verified))\n\
     (check-sat)\n"
  in
  (match Formal_specs.run_query broken_query with
  | Formal_specs.Proved -> incr passed  (* unsat: contradiction correctly detected *)
  | Formal_specs.Refuted _ -> check false "SPEC contradiction detected as unsat" "got sat"
  | Formal_specs.Unavailable reason -> check false "SPEC contradiction check ran" reason);

  let satisfiable_query =
    ";; satisfiable on purpose: an unconstrained function\n\
     (declare-datatype Verdict ((Unmapped) (Blocked)))\n\
     (declare-fun f (Verdict) Verdict)\n\
     (declare-const v Verdict)\n\
     (assert (= (f v) v))\n\
     (check-sat)\n"
  in
  (match Formal_specs.run_query satisfiable_query with
  | Formal_specs.Refuted _ -> incr passed  (* sat, with a model: reader works *)
  | Formal_specs.Proved -> check false "SPEC satisfiable query reads as sat" "got unsat"
  | Formal_specs.Unavailable reason -> check false "SPEC satisfiable check ran" reason);

  (* A missing solver is Unavailable, never Proved: absence must not verify. *)
  Unix.putenv "HERMES_Z3" "/nonexistent/z3";
  (match Formal_specs.run_query "(check-sat)\n" with
  | Formal_specs.Unavailable _ -> incr passed
  | other -> check false "SPEC missing solver is unavailable" (Formal_specs.describe other));
  Unix.putenv "HERMES_Z3" "";

  (* The emitted tables cover the whole domain: 16 combine entries, 4 credit
     entries, 7 classification pairs. An incomplete table would let z3 pick
     convenient values for the gaps and "prove" anything. *)
  let algebra = Formal_specs.algebra_spec () in
  let count needle text =
    let rec loop from acc =
      match String.index_from_opt text from needle.[0] with
      | None -> acc
      | Some i ->
          if i + String.length needle <= String.length text
             && String.sub text i (String.length needle) = needle
          then loop (i + 1) (acc + 1)
          else loop (i + 1) acc
    in
    loop 0 0
  in
  check (count "(assert (= (combine " algebra = 16)
    "SPEC combine table is total" (string_of_int (count "(assert (= (combine " algebra));
  check (count "(assert (= (grants_credit " algebra = 4)
    "SPEC credit table is total" "";
  let diagnostic = Formal_specs.diagnostic_spec () in
  check (count "(assert (= (origin_of " diagnostic = 7)
    "SPEC classification table is total" "";
  (* The Gate table covers the whole 4x4 domain, emitted from the real
     Harness_config.gate_verdict -- not a restatement. *)
  let gate = Formal_specs.gate_spec () in
  check (count "(assert (= (gate " gate = 16)
    "SPEC gate table is total" (string_of_int (count "(assert (= (gate " gate));

  Printf.printf "passed: %d   failed: %d\n" !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_formal_specs" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_formal_specs ]);
  exit (Suite_telemetry.exit_code self)
