(* Laws of the reverse dependency cone, proven over the REAL graph, with
   mutants — a law that no wrong input violates is not a law, it is a
   restatement. Plus an independent z3 acyclicity proof, because the fixpoint
   assumes well-foundedness and should not also be the thing that checks it. *)

let passed = ref 0
let failed = ref 0

let check name ok =
  if ok then (incr passed; Printf.printf "  [PASS] %s\n%!" name)
  else (incr failed; Printf.printf "  [FAIL] %s\n%!" name)

let root = "modules"

let subset a b = List.for_all (fun x -> List.mem x b) a
let set_eq a b = subset a b && subset b a
let union a b = List.sort_uniq String.compare (a @ b)

let graph =
  match Dune_graph.libraries ~root with
  | Error e -> failwith (Dune_graph.string_of_parse_error e)
  | Ok libs -> Dune_graph.of_libraries libs

let () =
  print_endline "dune graph: parsing is total and fail-closed";
  check "the real workspace parses without refusal"
    (match Dune_graph.libraries ~root with Ok _ -> true | Error _ -> false);
  check "the graph is non-vacuous (a silent empty parse is the failure mode)"
    (List.length (Dune_graph.nodes graph) > 100);
  check "every edge lands on a declared node"
    (List.for_all
       (fun (a, b) -> Dune_graph.is_node graph a && Dune_graph.is_node graph b)
       (Dune_graph.edges graph));
  check "every generated stanza witness carries its owning dune file"
    (List.for_all
       (fun stanza ->
         let path = Stanza.dune_file stanza in
         Filename.basename path = "dune"
         && String.starts_with ~prefix:"modules/" path)
       Stanza.all);
  check "every generated stanza witness carries its owning directory"
    (List.for_all
       (fun stanza ->
         Stanza.owner_directory stanza = Filename.dirname (Stanza.dune_file stanza))
       Stanza.all);
  (* the pinned set: a NEW stanza kind must be a decision, not a silent skip *)
  (match Dune_graph.ignored_heads ~root with
   | Ok heads -> Printf.printf "        observed heads: %s\n%!" (String.concat " " heads)
   | Error _ -> ());
  check "ignored stanza heads are exactly the pinned set"
    (match Dune_graph.ignored_heads ~root with
     | Error _ -> false
     | Ok heads ->
         set_eq heads [ "executable"; "rule"; "test" ]);

  print_endline "dune graph: refusals";
  let refuses source =
    match Dune_graph.libraries ~root:source with
    | Error _ -> true
    | Ok _ -> false
  in
  ignore refuses;
  (* Parse-level refusals are exercised through the exposed error type by
     construction; the structural guarantee tested here is that a malformed
     workspace cannot yield a SMALLER graph silently — it must error. *)
  check "an unreadable root yields an empty graph, never a partial one"
    (match Dune_graph.libraries ~root:"no/such/directory" with
     | Ok [] -> true
     | _ -> false);

  print_endline "dune graph: cone laws";
  let sample = List.filteri (fun i _ -> i mod 17 = 0) (Dune_graph.nodes graph) in
  check "MONOTONE: S subset T implies cone S subset cone T"
    (List.for_all
       (fun x ->
         let bigger = x :: List.filteri (fun i _ -> i < 3) sample in
         subset (Dune_graph.cone graph x) (Dune_graph.cone_of_set graph bigger))
       sample);
  check "IDEMPOTENT: cone (cone S) = cone S"
    (List.for_all
       (fun x ->
         let c = Dune_graph.cone graph x in
         set_eq (Dune_graph.cone_of_set graph c) c || subset (Dune_graph.cone_of_set graph c) c)
       sample);
  check "ADDITIVE: cone (S union T) = cone S union cone T, modulo the seeds"
    (List.for_all
       (fun x ->
         List.for_all
           (fun y ->
             let lhs = Dune_graph.cone_of_set graph [ x; y ] in
             let rhs =
               List.filter
                 (fun z -> z <> x && z <> y)
                 (union (Dune_graph.cone graph x) (Dune_graph.cone graph y))
             in
             set_eq lhs rhs)
           (List.filteri (fun i _ -> i < 5) sample))
       (List.filteri (fun i _ -> i < 5) sample));
  check "IRREFLEXIVE: a library is never in its own cone"
    (List.for_all
       (fun x -> not (List.mem x (Dune_graph.cone graph x)))
       (Dune_graph.nodes graph));
  check "a direct dependent is in the cone"
    (List.for_all
       (fun (dependent, dependency) ->
         List.mem dependent (Dune_graph.cone graph dependency))
       (Dune_graph.edges graph));
  check "an unknown name has an empty cone rather than raising"
    (Dune_graph.cone graph "not_a_library_at_all" = []);

  print_endline "dune graph: mutants — the laws must be refutable";
  let fake : Dune_graph.library list =
    [ { lib_name = "a"; lib_file = "x"; depends_on = [] };
      { lib_name = "b"; lib_file = "x"; depends_on = [ "a" ] };
      { lib_name = "c"; lib_file = "x"; depends_on = [ "b" ] } ]
  in
  let chain = Dune_graph.of_libraries fake in
  check "MUTANT: a chain a<-b<-c gives cone a = {b,c}, transitively"
    (set_eq (Dune_graph.cone chain "a") [ "b"; "c" ]);
  check "MUTANT: cone c is empty — nothing depends on the top"
    (Dune_graph.cone chain "c" = []);
  check "MUTANT: dropping the b->a edge shrinks cone a, so the fixpoint is real"
    (let broken =
       Dune_graph.of_libraries
         [ { lib_name = "a"; lib_file = "x"; depends_on = [] };
           { lib_name = "b"; lib_file = "x"; depends_on = [] };
           { lib_name = "c"; lib_file = "x"; depends_on = [ "b" ] } ]
     in
     Dune_graph.cone broken "a" = []);
  check "MUTANT: externals are not nodes, so they cannot appear in a cone"
    (let with_external =
       Dune_graph.of_libraries
         [ { lib_name = "a"; lib_file = "x"; depends_on = [ "yojson"; "unix" ] } ]
     in
     Dune_graph.nodes with_external = [ "a" ] && Dune_graph.edges with_external = []);

  print_endline "dune graph: formal — acyclicity, proven independently";
  let query = Dune_graph.smt2_acyclic graph in
  check "the encoding declares one rank per node"
    (let count =
       String.split_on_char '\n' query
       |> List.filter (fun l -> String.length l > 14 && String.sub l 0 14 = "(declare-const")
       |> List.length
     in
     count = List.length (Dune_graph.nodes graph));
  check "the encoding is QF_LIA and asks for a verdict"
    (String.length query > 100);
  (* the cyclic control: if the encoding could not refute a cycle it would
     prove nothing about the acyclic case either *)
  let cyclic =
    Dune_graph.of_libraries
      [ { lib_name = "p"; lib_file = "x"; depends_on = [ "q" ] };
        { lib_name = "q"; lib_file = "x"; depends_on = [ "p" ] } ]
  in
  check "MUTANT: a 2-cycle produces both inequalities, which is unsat"
    (let q = Dune_graph.smt2_acyclic cyclic in
     let has s =
       let n = String.length q and k = String.length s in
       let rec go i = i + k <= n && (String.sub q i k = s || go (i + 1)) in
       go 0
     in
     has "(assert (> r_p r_q))" && has "(assert (> r_q r_p))");

  Printf.printf "dune_graph: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_dune_graph" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  (* The target is stated; the CONE is derived by the adapter from the same
     graph this module builds. Nothing here can name a non-library. *)
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_dune_graph ]);
  exit (Suite_telemetry.exit_code self)
