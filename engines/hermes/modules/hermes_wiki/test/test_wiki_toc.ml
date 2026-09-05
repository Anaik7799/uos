(* HW.6.8.1 — the declared navigation tree. The tree law holds by
   construction (see wiki_toc.mli); these witness it, and each carries
   the mutant that kills it:

     T1 node once      M1  drop the claim before the descent
     T2 acyclic        M2  drop the cycle-breaking seed segment
     T3 first claim    M3  reverse the declaration order
     T4 authored order M4  sort the children
     T5 reversed       M5  drop the reverse in parse_fence
     T6 hidden PLACES  M6  skip hidden entries when building
     T7 options inert  M7  truncate children at maxdepth
     T8 gap is named   M8  drop the gaps line on an unresolved target
     T9 alias last     M9  swap the two resolver passes
     T10 complement    M10 compare unplaced against root children only *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

let page slug body = ("docs/x/" ^ slug ^ ".md", "# " ^ slug ^ "\n\n" ^ body)
let toc ?(opts = "") targets =
  "```toctree" ^ (if opts = "" then "" else " " ^ opts) ^ "\n" ^ String.concat "\n" targets
  ^ "\n```\n"

let build files = Hermes_wiki.build files
let tree files = Wiki_toc.of_model (build files)

(* ------------------------------------------------------- the grammar *)

let () =
  check "G1 a toctree fence parses: targets in SOURCE order, options carried" (fun () ->
      match Wiki_toc.parse_fence "toctree maxdepth=2 caption=Guides hidden numbered"
              [ "zeta"; ""; "# a comment"; "alpha" ]
      with
      | Some [ a; b ] ->
          a.Wiki_toc.target = "zeta" && b.Wiki_toc.target = "alpha"
          && a.Wiki_toc.hidden && a.Wiki_toc.numbered
          && a.Wiki_toc.caption = "Guides"
          && a.Wiki_toc.maxdepth = Some 2
      | _ -> false);
  check "G2 a NON-toctree fence is None (the token is exact)" (fun () ->
      Wiki_toc.parse_fence "ocaml" [ "x" ] = None
      && Wiki_toc.parse_fence "toctrees" [ "x" ] = None);
  check "G3 a malformed option is IGNORED, never raised (total over author input)"
    (fun () ->
      match Wiki_toc.parse_fence "toctree maxdepth=banana maxdepth=0" [ "a" ] with
      | Some [ e ] -> e.Wiki_toc.maxdepth = None
      | _ -> false);
  check "G4 duplicates within ONE fence collapse to the first" (fun () ->
      match Wiki_toc.parse_fence "toctree" [ "a"; "b"; "a" ] with
      | Some es -> List.map (fun e -> e.Wiki_toc.target) es = [ "a"; "b" ]
      | None -> false);
  check "T5 reversed reverses siblings (M5: drop the reverse)" (fun () ->
      match Wiki_toc.parse_fence "toctree reversed" [ "a"; "b" ] with
      | Some es -> List.map (fun e -> e.Wiki_toc.target) es = [ "b"; "a" ]
      | None -> false)

(* --------------------------------------------------------- the laws *)

let () =
  check "T1 EACH NODE ONCE: a diamond places the shared child exactly once" (fun () ->
      let t = tree [ page "a" (toc [ "c" ]); page "b" (toc [ "c" ]); page "c" "leaf.\n" ] in
      List.length (Wiki_toc.walk t) = List.length (Wiki_toc.placed t)
      && List.length (List.filter (fun (s, _, _) -> s = "c") (Wiki_toc.walk t)) = 1);
  check "T2 ACYCLIC and TOTAL: a <-> b terminates, both placed once, back edge recorded"
    (fun () ->
      let t = tree [ page "a" (toc [ "b" ]); page "b" (toc [ "a" ]) ] in
      List.sort compare (Wiki_toc.placed t) = [ "a"; "b" ]
      && List.mem ("b", "a") (Wiki_toc.conflicts t));
  check "T3 FIRST CLAIM WINS, deterministically by slug order" (fun () ->
      let t = tree [ page "a" (toc [ "c" ]); page "b" (toc [ "c" ]); page "c" "leaf.\n" ] in
      Wiki_toc.path_to t "c" = Some [ "a"; "c" ]);
  check "T4 AUTHORED ORDER, not lexicographic (M4: sort the children)" (fun () ->
      let t = tree [ page "a" (toc [ "zeta"; "alpha" ]); page "zeta" "z\n"; page "alpha" "al\n" ] in
      List.map (fun (s, _, _) -> s) (Wiki_toc.walk t) = [ "a"; "zeta"; "alpha" ]);
  check "T6 hidden PLACES, it does not hide (M6: skip hidden entries)" (fun () ->
      let t = tree [ page "a" (toc ~opts:"hidden" [ "b" ]); page "b" "leaf.\n" ] in
      List.mem "b" (Wiki_toc.placed t)
      && (not (List.mem "b" (Wiki_toc.unplaced (build [ page "a" (toc ~opts:"hidden" [ "b" ]); page "b" "leaf.\n" ]) t)))
      && List.exists (fun (s, _, h) -> s = "b" && h) (Wiki_toc.walk t));
  check "T7 RENDERING OPTIONS DO NOT CHANGE STRUCTURE (M7: truncate at maxdepth)"
    (fun () ->
      let mk d =
        tree
          [ page "a" (toc ~opts:("maxdepth=" ^ d) [ "b" ]);
            page "b" (toc [ "c" ]); page "c" "leaf.\n" ]
      in
      Wiki_toc.walk (mk "1") = Wiki_toc.walk (mk "9"));
  check "T8 an UNRESOLVED target is a named gap, never a silent branch" (fun () ->
      let t = tree [ page "a" (toc [ "ghost" ]) ] in
      match Wiki_toc.gaps t with
      | [ line ] -> contains line "ghost" && contains line "a"
      | _ -> false);
  check "T8b a page naming ITSELF is a gap, not a self-edge" (fun () ->
      let t = tree [ page "a" (toc [ "a" ]) ] in
      List.length (Wiki_toc.gaps t) = 1 && Wiki_toc.walk t = [ ("a", 1, false) ]);
  check "T9 the ENGINE's key space, aliases LAST (M9: swap the passes)" (fun () ->
      (* one page's alias equals another page's slug: the slug owner wins *)
      let files =
        [ page "a" (toc [ "beta" ]);
          ("docs/x/beta.md", "# beta\n\nreal.\n");
          ("docs/x/other.md", "---\naliases: [beta]\n---\n# other\n\nimpostor.\n") ]
      in
      Wiki_toc.path_to (Wiki_toc.of_model (build files)) "beta" = Some [ "a"; "beta" ]);
  check "T10 unplaced is the EXACT complement (M10: root children only)" (fun () ->
      let files =
        [ page "a" (toc [ "b" ]); page "b" (toc [ "c" ]); page "c" "leaf.\n";
          page "lonely" "nobody links me.\n" ]
      in
      let m = build files in
      let t = Wiki_toc.of_model m in
      let all = List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug) m.Hermes_wiki.pages in
      List.sort compare (Wiki_toc.placed t @ Wiki_toc.unplaced m t) = List.sort compare all
      && Wiki_toc.unplaced m t = [ "lonely" ]);
  check "T11 INPUT-ORDER INVARIANCE: reversing the file list changes nothing" (fun () ->
      let files =
        [ page "a" (toc [ "b" ]); page "b" "leaf.\n"; page "z" (toc [ "y" ]); page "y" "leaf.\n" ]
      in
      Wiki_toc.walk (Wiki_toc.of_model (build files))
      = Wiki_toc.walk (Wiki_toc.of_model (build (List.rev files))));
  check "T12 path_to agrees with walk's depth, and is None when unplaced" (fun () ->
      let files = [ page "a" (toc [ "b" ]); page "b" (toc [ "c" ]); page "c" "leaf.\n";
                    page "lonely" "x\n" ] in
      let t = Wiki_toc.of_model (build files) in
      List.for_all
        (fun (s, depth, _) ->
          match Wiki_toc.path_to t s with
          | Some p -> List.length p = depth && List.nth_opt p (depth - 1) = Some s
          | None -> false)
        (Wiki_toc.walk t)
      && Wiki_toc.path_to t "lonely" = None);
  check "T13 an empty model yields a childless root, never an exception" (fun () ->
      let t = Wiki_toc.of_model (build []) in
      (Wiki_toc.root t).Wiki_toc.children = [] && Wiki_toc.walk t = []);
  check "T14 a toctree named in PROSE is not a declaration (fence-aware)" (fun () ->
      let t = tree [ page "a" "I would write ```toctree here.\n"; page "b" "leaf.\n" ] in
      Wiki_toc.walk t = [])

(* ------------------------------ HW.6.8.2 unreachable, HW.6.8.3 numbering
     U1 verdict vs fact    MU1 unreachable ignores the disclosure
     U2 hidden PLACES      MU2 hidden entries excluded from placed
     N1 derived numbering  MN1 the counter advances on unnumbered siblings
     N2 inherited          MN2 numbering not inherited downward
     N3 stability          MN3 label built from depth instead of position *)

let () =
  check "U1 the DISCLOSURE is the difference between the fact and the verdict"
    (fun () ->
      let files =
        [ page "a" (toc [ "b" ]); page "b" "leaf.\n";
          page "loud" "nobody places me.\n";
          ("docs/x/quiet.md", "---\norphan: true\n---\n# quiet\n\ndeliberate entry point.\n") ]
      in
      let m = build files in
      let t = Wiki_toc.of_model m in
      (* unplaced is the FACT: both are unplaced *)
      Wiki_toc.unplaced m t = [ "loud"; "quiet" ]
      (* unreachable is the VERDICT: only the undisclosed one *)
      && Wiki_toc.unreachable m t = [ "loud" ]
      (* and the escape hatch is COUNTABLE *)
      && Wiki_toc.disclosed_orphans m = [ "quiet" ]);
  check "U2 a HIDDEN entry is placed, so it is never unreachable" (fun () ->
      let files = [ page "a" (toc ~opts:"hidden" [ "b" ]); page "b" "leaf.\n" ] in
      let m = build files in
      Wiki_toc.unreachable m (Wiki_toc.of_model m) = []);
  check "N1 numbering is DERIVED from position, and only for numbered subtrees"
    (fun () ->
      let files =
        [ page "root" (toc ~opts:"numbered" [ "alpha"; "beta" ]);
          page "alpha" "a\n"; page "beta" "b\n"; page "plain" (toc [ "gamma" ]);
          page "gamma" "g\n" ]
      in
      let n = Wiki_toc.numbering (Wiki_toc.of_model (build files)) in
      List.assoc_opt "alpha" n = Some "1"
      && List.assoc_opt "beta" n = Some "2"
      (* an unnumbered tree is not labelled at all *)
      && List.assoc_opt "gamma" n = None);
  check "N2 numbering is INHERITED downward (a numbered section's subsections are numbered)"
    (fun () ->
      let files =
        [ page "root" (toc ~opts:"numbered" [ "alpha" ]);
          page "alpha" (toc [ "one"; "two" ]); page "one" "1\n"; page "two" "2\n" ]
      in
      let n = Wiki_toc.numbering (Wiki_toc.of_model (build files)) in
      List.assoc_opt "alpha" n = Some "1"
      && List.assoc_opt "one" n = Some "1.1"
      && List.assoc_opt "two" n = Some "1.2");
  check "N3 STABILITY: inserting a sibling renumbers BELOW it and nothing above"
    (fun () ->
      let mk targets =
        Wiki_toc.numbering
          (Wiki_toc.of_model
             (build
                (page "root" (toc ~opts:"numbered" targets)
                :: List.map (fun s -> page s (s ^ "\n")) [ "alpha"; "beta"; "gamma" ])))
      in
      let before = mk [ "alpha"; "gamma" ] in
      let after = mk [ "alpha"; "beta"; "gamma" ] in
      (* alpha keeps its label; gamma moves *)
      List.assoc_opt "alpha" before = List.assoc_opt "alpha" after
      && List.assoc_opt "gamma" before = Some "2"
      && List.assoc_opt "gamma" after = Some "3");
  check "N1b an UNNUMBERED sibling never consumes a number (MN1's real killer)"
    (fun () ->
      (* the unnumbered fence comes FIRST, so a counter that advanced on
         every child would label the numbered one "2" instead of "1".
         Without this ordering the mutant is equivalent — which is why
         the first version of N1 could not kill it. *)
      let files =
        [ ("docs/x/root.md",
           "# root\n\n" ^ toc [ "skipme" ] ^ "\n" ^ toc ~opts:"numbered" [ "counted" ]);
          page "skipme" "s\n"; page "counted" "c\n" ]
      in
      let n = Wiki_toc.numbering (Wiki_toc.of_model (build files)) in
      List.assoc_opt "counted" n = Some "1" && List.assoc_opt "skipme" n = None);
  check "N4 numbering agrees with walk: every labelled slug is placed" (fun () ->
      let files =
        [ page "root" (toc ~opts:"numbered" [ "alpha" ]); page "alpha" "a\n" ]
      in
      let t = Wiki_toc.of_model (build files) in
      let placed = Wiki_toc.placed t in
      List.for_all (fun (s, _) -> List.mem s placed) (Wiki_toc.numbering t))

let () =
  Printf.printf "wiki_toc: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_toc" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_toc ]);
  exit (Wiki_suite_telemetry.exit_code self)
