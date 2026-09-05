let passed = ref 0
let failures = ref []

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

let () =
  (* UNIT: a hand-built acyclic graph is proved acyclic. *)
  (match
     Dependency_smt.check ~capabilities:[ "a.x"; "a.y"; "a.z" ]
       ~dependencies:[ ("a.y", "a.x"); ("a.z", "a.y") ]
   with
  | Dependency_smt.Acyclic -> incr passed
  | Dependency_smt.Solver_missing _ ->
      check false "UNIT acyclic chain" "z3 missing"
  | other -> check false "UNIT acyclic chain" (Dependency_smt.describe other));

  (* UNIT: a cycle is proved impossible to order. This is the case the DFS test
     cannot reach, because the catalog is acyclic by construction. *)
  (match
     Dependency_smt.check ~capabilities:[ "a.x"; "a.y" ]
       ~dependencies:[ ("a.y", "a.x"); ("a.x", "a.y") ]
   with
  | Dependency_smt.Cyclic -> incr passed
  | other -> check false "UNIT cycle detected" (Dependency_smt.describe other));

  (* UNIT: a self-edge is a cycle. *)
  (match
     Dependency_smt.check ~capabilities:[ "a.x" ] ~dependencies:[ ("a.x", "a.x") ]
   with
  | Dependency_smt.Cyclic -> incr passed
  | other -> check false "UNIT self edge is cyclic" (Dependency_smt.describe other));

  (* UNIT: no edges is trivially orderable. *)
  (match Dependency_smt.check ~capabilities:[ "a.x" ] ~dependencies:[] with
  | Dependency_smt.Acyclic -> incr passed
  | other -> check false "UNIT edgeless graph" (Dependency_smt.describe other));

  (* UNIT: a missing solver is reported, never silently treated as a proof. *)
  Unix.putenv "HERMES_Z3" "/nonexistent/z3";
  (match Dependency_smt.check ~capabilities:[ "a.x" ] ~dependencies:[] with
  | Dependency_smt.Solver_missing _ -> incr passed
  | other -> check false "UNIT missing solver is not a proof" (Dependency_smt.describe other));
  Unix.putenv "HERMES_Z3" "";

  (* UNIT: every outcome describes itself distinctly. *)
  let descriptions =
    List.map Dependency_smt.describe
      [ Dependency_smt.Acyclic; Dependency_smt.Cyclic;
        Dependency_smt.Solver_missing "p"; Dependency_smt.Solver_failed "r" ]
  in
  check
    (List.length (List.sort_uniq compare descriptions) = 4)
    "UNIT outcomes are distinct" "";

  (* FEATURE: the real catalog admits a build order, proved independently of
     the depth-first traversal that produces it. *)
  let outcome, nodes, edges = Dependency_smt.check_catalog () in
  (match outcome with
  | Dependency_smt.Acyclic ->
      incr passed;
      Printf.printf "z3 proved the catalog orderable: %d slices, %d edges\n" nodes edges
  | Dependency_smt.Solver_missing path ->
      check false "FEATURE catalog orderable" ("z3 missing at " ^ path)
  | other -> check false "FEATURE catalog orderable" (Dependency_smt.describe other));

  (* CROSS-CHECK: z3 and the traversal must agree. Agreement is evidence only
     because the two share no code. *)
  (match (outcome, Capability_catalog.topological_order ()) with
  | Dependency_smt.Acyclic, Ok order ->
      check
        (List.length order = List.length Capability_catalog.all)
        "CROSS traversal orders every slice" "";
      incr passed
  | Dependency_smt.Cyclic, Error _ -> incr passed
  | Dependency_smt.Acyclic, Error message ->
      check false "CROSS z3 and traversal agree" ("z3 sat but traversal failed: " ^ message)
  | Dependency_smt.Cyclic, Ok _ ->
      check false "CROSS z3 and traversal agree" "z3 unsat but traversal succeeded"
  | _ -> ());

  Printf.printf "passed: %d   failed: %d\n" !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_dependency_smt" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_dependency_smt ]);
  exit (Suite_telemetry.exit_code self)
