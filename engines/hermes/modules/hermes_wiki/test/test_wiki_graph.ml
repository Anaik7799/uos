(* HW.4.2.1/2/3 — the graph kernels' laws. Mutants (killers named):
     G-M1 dangling mass dropped     (killed: the Sigma=1 leg)
     G-M2 unstable vertex order     (killed: shuffle-invariance)
     G-M3 community ties to LARGEST (killed: the label law) *)
let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed; print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let mk files = Wiki_graph.of_model (Hermes_wiki.build files)

let pg name links = (Printf.sprintf "pages/wiki/%s.md" name,
                     Printf.sprintf "# %s\n\n%s\n" (String.capitalize_ascii name)
                       (String.concat " " (List.map (fun t -> "[[" ^ t ^ "]]") links)))

let path3 = [ pg "aa" [ "bb" ]; pg "bb" [ "cc" ]; pg "cc" [] ]

let () =
  check "of_model: nodes sorted by slug; edges resolve, dedup, no self-loops" (fun () ->
      let g = mk [ pg "bb" [ "aa"; "aa"; "bb"; "ghost" ]; pg "aa" [] ] in
      Wiki_graph.nodes g = [ "aa"; "bb" ] && Wiki_graph.edge_count g = 1);
  check "of_model: input order cannot matter (shuffle-invariance)" (fun () ->
      let a = mk path3 and b = mk (List.rev path3) in
      Wiki_graph.nodes a = Wiki_graph.nodes b
      && Wiki_graph.pagerank a = Wiki_graph.pagerank b
      && Wiki_graph.betweenness a = Wiki_graph.betweenness b
      && Wiki_graph.communities a = Wiki_graph.communities b)

let () =
  check "pagerank: a probability distribution (Sigma=1) even with dangling nodes"
    (fun () ->
      let g = mk [ pg "aa" [ "bb" ]; pg "bb" []; pg "cc" [ "aa" ] ] in
      let r = Wiki_graph.pagerank g in
      let sum = List.fold_left (fun acc (_, x) -> acc +. x) 0.0 r in
      List.length r = 3 && abs_float (sum -. 1.0) < 1e-6);
  check "pagerank: authority flows — the sink of a path outranks its source" (fun () ->
      let r = Wiki_graph.pagerank (mk path3) in
      let rank s = List.assoc s r in
      rank "cc" > rank "aa");
  check "pagerank: seeds concentrate the teleport" (fun () ->
      let g = mk path3 in
      let seeded = Wiki_graph.pagerank ~seeds:[ "aa" ] g in
      let uniform = Wiki_graph.pagerank g in
      List.assoc "aa" seeded > List.assoc "aa" uniform);
  check "pagerank: deterministic (two runs byte-equal), sorted desc, slug ties" (fun () ->
      let g = mk path3 in
      let r = Wiki_graph.pagerank g in
      r = Wiki_graph.pagerank g
      && (let rec ordered = function
            | (s1, x1) :: ((s2, x2) :: _ as rest) ->
                (x1 > x2 || (x1 = x2 && s1 <= s2)) && ordered rest
            | _ -> true
          in
          ordered r))

let () =
  check "betweenness: Brandes on a directed path — the middle carries the pair"
    (fun () ->
      let b = Wiki_graph.betweenness (mk path3) in
      List.assoc "bb" b = 1.0 && List.assoc "aa" b = 0.0 && List.assoc "cc" b = 0.0);
  check "betweenness: deterministic" (fun () ->
      let g = mk path3 in
      Wiki_graph.betweenness g = Wiki_graph.betweenness g)

let () =
  check "communities: two triangles joined by one bridge split in two" (fun () ->
      let tri a b c = [ pg a [ b; c ]; pg b [ a; c ]; pg c [ a; b ] ] in
      let files =
        tri "aa" "ab" "ac" @ tri "ba" "bb" "bc"
        @ [ ( "pages/wiki/zz.md", "# Zz\n\n[[aa]] [[ba]]\n" ) ]
      in
      let cs = Wiki_graph.communities (mk files) in
      List.length cs >= 2
      && List.mem_assoc "aa" cs
      && (let m = List.assoc "aa" cs in
          List.mem "ab" m && List.mem "ac" m && not (List.mem "bb" m)));
  check "communities: keyed by the SMALLEST member slug, members sorted" (fun () ->
      let cs = Wiki_graph.communities (mk [ pg "bb" [ "aa" ]; pg "aa" [ "bb" ] ]) in
      match cs with
      | [ (label, members) ] -> label = "aa" && members = [ "aa"; "bb" ]
      | _ -> false)

let () =
  check "ecc_from: longest reachable BFS distance; absent node is None" (fun () ->
      let g = mk path3 in
      Wiki_graph.ecc_from g "aa" = Some 2 && Wiki_graph.ecc_from g "cc" = Some 0
      && Wiki_graph.ecc_from g "zz" = None)

let () =
  check "orphans: no-inbound nodes listed sorted; linked nodes are not" (fun () ->
      let g = mk [ pg "aa" [ "bb" ]; pg "bb" []; pg "cc" [] ] in
      Wiki_graph.orphans g = [ "aa"; "cc" ])

let () =
  Printf.printf "wiki_graph: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_graph" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_graph ]);
  exit (Wiki_suite_telemetry.exit_code self)
