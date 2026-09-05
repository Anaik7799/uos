(* HW.4.3.2 / HW.4.1.7 / HW.4.2.4 / HW.4.5.2 / HW.4.6.2 / HW.4.6.3 — the
   remaining graph-analysis rows, across the full functional envelope:

     N*  nominal      the six laws hold on a corpus that behaves
     X*  exhaustion   a large corpus, a dense graph, a term in EVERY
                      document, a shuffled input list
     S*  stuck        empty corpus, single page, no tokens, no links,
                      a disconnected graph, an absent slug
     A*  anomaly      self-loops, duplicate edges, a dead link, a tag
                      that is a string prefix of another, unicode, a
                      negative radius

   The headline law of the module is DETERMINISM: the same corpus built
   from a SHUFFLED input list must produce byte-identical output. A
   ranking that is not a function of the corpus makes every downstream
   pin noise rather than evidence, and a float sum accumulated in a
   different order is exactly how that happens.

   Everything here is REPORT-ONLY (R5): these are shapes of a corpus,
   never defects of an implementation. *)

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

let mk pairs = Hermes_wiki.build pairs
let slugs (m : Hermes_wiki.model) =
  List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug) m.Hermes_wiki.pages
  |> List.sort compare

(* byte identity of a float, not OCaml's [=] — [=] says 0.0 = -0.0 *)
let bits x = Int64.bits_of_float x
let subset a b = List.for_all (fun x -> List.mem x b) a

(* ------------------------------------------------------------ corpora *)

let sim_corpus =
  [ ("pages/wiki/alpha.md", "# Alpha\n\nzebra quark zebra plume\n");
    ("pages/wiki/beta.md", "# Beta\n\nzebra quark plume\n");
    ("pages/wiki/gamma.md", "# Gamma\n\nwidget sprocket\n") ]

let sim = mk sim_corpus
let sv = Wiki_similarity.vectors sim

(* two pages with IDENTICAL bodies: every term is in EVERY document, so
   the idf smoothing is what keeps the vectors non-zero *)
let twins = mk [ ("pages/wiki/twin1.md", "shared words here shared\n");
                 ("pages/wiki/twin2.md", "shared words here shared\n") ]
let tv = Wiki_similarity.vectors twins

let two_cliques =
  mk
    [ ("pages/wiki/a1.md", "# A1\n\n[[a2]] [[a3]]\n");
      ("pages/wiki/a2.md", "# A2\n\n[[a1]] [[a3]]\n");
      ("pages/wiki/a3.md", "# A3\n\n[[a1]] [[a2]]\n");
      ("pages/wiki/b1.md", "# B1\n\n[[b2]] [[b3]]\n");
      ("pages/wiki/b2.md", "# B2\n\n[[b1]] [[b3]]\n");
      ("pages/wiki/b3.md", "# B3\n\n[[b1]] [[b2]]\n") ]

let bridged_corpus =
  [ ("pages/wiki/a1.md", "# A1\n\n[[a2]] [[a3]]\n");
    ("pages/wiki/a2.md", "# A2\n\n[[a1]] [[a3]]\n");
    ("pages/wiki/a3.md", "# A3\n\n[[a1]] [[a2]]\n");
    ("pages/wiki/hub.md", "# Hub\n\n[[a1]] [[b1]]\n");
    ("pages/wiki/b1.md", "# B1\n\n[[b2]] [[b3]]\n");
    ("pages/wiki/b2.md", "# B2\n\n[[b1]] [[b3]]\n");
    ("pages/wiki/b3.md", "# B3\n\n[[b1]] [[b2]]\n") ]

let bridged = mk bridged_corpus

let chain =
  mk
    [ ("pages/wiki/p1.md", "# P1\n\n[[p2]]\n");
      ("pages/wiki/p2.md", "# P2\n\n[[p3]]\n");
      ("pages/wiki/p3.md", "# P3\n\n[[p4]]\n");
      ("pages/wiki/p4.md", "# P4\n\nend\n") ]

let unlinked =
  mk [ ("pages/wiki/u1.md", "# U1\n\nalone\n"); ("pages/wiki/u2.md", "# U2\n\nalone\n");
       ("pages/wiki/u3.md", "# U3\n\nalone\n") ]

let split =
  mk
    [ ("pages/wiki/x1.md", "# X1\n\n[[x2]]\n"); ("pages/wiki/x2.md", "# X2\n\n[[x1]]\n");
      ("pages/wiki/y1.md", "# Y1\n\n[[y2]]\n"); ("pages/wiki/y2.md", "# Y2\n\n[[y1]]\n");
      ("pages/wiki/z1.md", "# Z1\n\nalone\n") ]

(* self-loop, a duplicated link, and a dead link — none may become edges *)
let messy =
  mk
    [ ("pages/wiki/s1.md", "# S1\n\n[[s1]] [[s2]] [[s2]] [[nowhere]]\n");
      ("pages/wiki/s2.md", "# S2\n\n[[s1]]\n") ]

let tagged =
  mk
    [ ("pages/wiki/t1.md", "---\ntopics: [a/b/c, misc]\n---\n\n# T1\n\nbody\n");
      ("pages/wiki/t2.md", "---\ntopics: [a/b]\n---\n\n# T2\n\nbody\n");
      ("pages/wiki/t3.md", "---\ntopics: [ab]\n---\n\n# T3\n\nbody\n");
      ("pages/wiki/t4.md", "---\ntopics: [A/B]\n---\n\n# T4\n\nbody\n") ]

(* X* — a large corpus: 60 pages, a term in EVERY document, and two
   vocabulary clusters so the ranking has real ties to break *)
let big_corpus =
  List.init 60 (fun i ->
      let id = Printf.sprintf "%02d" i in
      let cluster = if i mod 2 = 0 then "evenword" else "oddword" in
      ( Printf.sprintf "pages/wiki/n%s.md" id,
        Printf.sprintf "# N%s\n\ncommonterm %s uniqueterm%s\n" id cluster id ))

let big = mk big_corpus
let bv = Wiki_similarity.vectors big

(* ---------------------------------------------------- N* nominal *)

let () =
  check "N1 tokens MIRRORS Wiki_search: lowercase ascii alnum runs, length >= 2"
    (fun () ->
      Wiki_similarity.tokens "Hello, World! a b12 X" = [ "hello"; "world"; "b12" ]
      && Wiki_similarity.tokens "ab-cd" = [ "ab"; "cd" ]
      && Wiki_similarity.tokens "" = []
      && Wiki_similarity.tokens "A" = []);
  check "N2 FENCES ARE EXCLUDED: a code sample is not prose about the note"
    (fun () ->
      let m = mk [ ("pages/wiki/f1.md", "# F1\n\nprose here\n```\nzetafence zetafence\n```\n") ] in
      let v = Wiki_similarity.vectors m in
      let ts = List.map fst (Wiki_similarity.weights v "f1") in
      List.mem "prose" ts && not (List.mem "zetafence" ts));
  check "N3 a block ANCHOR is an address, not a word" (fun () ->
      let m = mk [ ("pages/wiki/f2.md", "# F2\n\nbeta gamma ^anchorid\n") ] in
      let v = Wiki_similarity.vectors m in
      let ts = List.map fst (Wiki_similarity.weights v "f2") in
      List.mem "beta" ts && List.mem "gamma" ts && not (List.mem "anchorid" ts));
  check "N4 idf(t) = 1 + ln(N / n_t), EXACTLY as the row claims" (fun () ->
      Wiki_similarity.corpus_size sv = 3
      && Wiki_similarity.document_frequency sv "zebra" = 2
      && Wiki_similarity.document_frequency sv "widget" = 1
      && abs_float (Wiki_similarity.idf sv "widget" -. (1.0 +. log 3.0)) < 1e-12
      && abs_float (Wiki_similarity.idf sv "zebra" -. (1.0 +. log 1.5)) < 1e-12);
  check "N5 a term in EVERY document scores idf 1.0 — the +1 is load-bearing"
    (fun () ->
      Wiki_similarity.idf tv "shared" = 1.0
      && Wiki_similarity.idf tv "words" = 1.0
      && Wiki_similarity.weights tv "twin1" <> []);
  check "N6 SYMMETRY: sim(a,b) = sim(b,a), bit for bit, for every pair" (fun () ->
      let ss = slugs sim @ [ "ghost" ] in
      List.for_all
        (fun a ->
          List.for_all
            (fun b ->
              bits (Wiki_similarity.similarity sv a b) = bits (Wiki_similarity.similarity sv b a))
            ss)
        ss);
  check "N7 IDENTITY: a document is maximally similar to itself" (fun () ->
      List.for_all (fun s -> Wiki_similarity.similarity sv s s = 1.0) (slugs sim));
  check "N8 RANGE: every similarity lies in [0, 1] and is never NaN" (fun () ->
      let ss = slugs sim in
      List.for_all
        (fun a ->
          List.for_all
            (fun b ->
              let x = Wiki_similarity.similarity sv a b in
              (not (Float.is_nan x)) && x >= 0.0 && x <= 1.0)
            ss)
        ss);
  check "N9 shared vocabulary outranks none: sim(alpha,beta) > sim(alpha,gamma)"
    (fun () ->
      Wiki_similarity.similarity sv "alpha" "beta" > Wiki_similarity.similarity sv "alpha" "gamma"
      && Wiki_similarity.similarity sv "alpha" "gamma" = 0.0);
  check "N10 related is score DESCENDING with slug-ascending ties" (fun () ->
      let r = Wiki_similarity.related bv "n00" in
      let rec ordered = function
        | (s1, x1) :: ((s2, x2) :: _ as rest) ->
            (x1 > x2 || (x1 = x2 && compare s1 s2 < 0)) && ordered rest
        | [ _ ] | [] -> true
      in
      r <> [] && ordered r);
  check "N11 related EXCLUDES self and drops zero scores" (fun () ->
      let r = Wiki_similarity.related sv "alpha" in
      (not (List.mem_assoc "alpha" r))
      && List.mem_assoc "beta" r
      && (not (List.mem_assoc "gamma" r))
      && List.for_all (fun (_, x) -> x > 0.0) r);
  check "N12 identical bodies COMPUTE a similarity of 1.0 (not the defined case)"
    (fun () -> Wiki_similarity.similarity tv "twin1" "twin2" = 1.0);
  check "N12b every score lands ON the declared 1e-6 grid — a last-bit \
         difference can never reorder a ranking"
    (fun () ->
      let on_grid x = x = Float.round (x *. 1e6) /. 1e6 in
      Wiki_similarity.quantum = 1e-6
      && List.for_all
           (fun (s, x) -> on_grid x && on_grid (Wiki_similarity.similarity bv "n00" s))
           (Wiki_similarity.related bv "n00")
      && List.for_all
           (fun a ->
             List.for_all (fun b -> on_grid (Wiki_similarity.similarity sv a b)) (slugs sim))
           (slugs sim));
  check "N13 tag_ancestors: #a/b/c implies #a/b and #a" (fun () ->
      Wiki_similarity.tag_ancestors "a/b/c" = [ "a"; "a/b"; "a/b/c" ]
      && Wiki_similarity.tag_ancestors "#A/B" = [ "a"; "a/b" ]
      && Wiki_similarity.tag_segments "#a/b/c" = [ "a"; "b"; "c" ]);
  check "N14 REFLEXIVE: every tag covers itself" (fun () ->
      List.for_all
        (fun t -> Wiki_similarity.tag_covers ~parent:t ~child:t)
        [ "a"; "a/b"; "a/b/c"; "ab" ]);
  check "N15 TRANSITIVE: covers a b && covers b c => covers a c" (fun () ->
      Wiki_similarity.tag_covers ~parent:"a" ~child:"a/b"
      && Wiki_similarity.tag_covers ~parent:"a/b" ~child:"a/b/c"
      && Wiki_similarity.tag_covers ~parent:"a" ~child:"a/b/c"
      && not (Wiki_similarity.tag_covers ~parent:"a/b/c" ~child:"a"));
  check "N16 MONOTONE: filtering by #a returns everything tagged #a/b" (fun () ->
      let ma = Wiki_similarity.tag_members tagged "a" in
      let mab = Wiki_similarity.tag_members tagged "a/b" in
      let mabc = Wiki_similarity.tag_members tagged "a/b/c" in
      ma = [ "t1"; "t2"; "t4" ] && subset mab ma && subset mabc mab && mabc = [ "t1" ]);
  check "N17 tag_tree lists the IMPLIED ancestor: a corpus with only #a/b has #a"
    (fun () ->
      let m = mk [ ("pages/wiki/o1.md", "---\ntopics: [deep/nest]\n---\n\n# O1\n\nbody\n") ] in
      let tree = Wiki_similarity.tag_tree m in
      List.assoc_opt "deep" tree = Some [ "o1" ]
      && List.assoc_opt "deep/nest" tree = Some [ "o1" ]);
  check "N18 MIRROR: directed_edges agrees with Wiki_graph.edge_count" (fun () ->
      List.for_all
        (fun m ->
          List.length (Wiki_similarity.directed_edges m)
          = Wiki_graph.edge_count (Wiki_graph.of_model m))
        [ sim; two_cliques; bridged; chain; unlinked; split; messy; big ]);
  check "N19 local radius 0 is the note ALONE, with no edges" (fun () ->
      let l = Wiki_similarity.local_graph chain ~radius:0 "p2" in
      l.Wiki_similarity.center = "p2"
      && l.Wiki_similarity.nodes = [ "p2" ]
      && l.Wiki_similarity.edges = []);
  check "N20 SOUND: every node in the radius-r view is within r hops" (fun () ->
      let d = Wiki_similarity.hops bridged "hub" in
      List.for_all
        (fun r ->
          let l = Wiki_similarity.local_graph bridged ~radius:r "hub" in
          List.for_all
            (fun s -> match List.assoc_opt s d with Some k -> k <= r | None -> false)
            l.Wiki_similarity.nodes)
        [ 0; 1; 2; 3 ]);
  check "N21 COMPLETE: every node within r hops is IN the view" (fun () ->
      let d = Wiki_similarity.hops bridged "hub" in
      List.for_all
        (fun r ->
          let l = Wiki_similarity.local_graph bridged ~radius:r "hub" in
          List.for_all
            (fun (s, k) -> if k <= r then List.mem s l.Wiki_similarity.nodes else true)
            d)
        [ 0; 1; 2; 3 ]);
  check "N22 INDUCED: both endpoints of every view edge are in the view" (fun () ->
      let l = Wiki_similarity.local_graph chain ~radius:2 "p1" in
      l.Wiki_similarity.nodes = [ "p1"; "p2"; "p3" ]
      && l.Wiki_similarity.edges = [ ("p1", "p2"); ("p2", "p3") ]
      && List.for_all
           (fun (u, v) ->
             List.mem u l.Wiki_similarity.nodes && List.mem v l.Wiki_similarity.nodes)
           l.Wiki_similarity.edges);
  check "N23 MONOTONE: nodes(r) is a subset of nodes(r+1)" (fun () ->
      List.for_all
        (fun r ->
          subset
            (Wiki_similarity.local_graph bridged ~radius:r "hub").Wiki_similarity.nodes
            (Wiki_similarity.local_graph bridged ~radius:(r + 1) "hub").Wiki_similarity.nodes)
        [ 0; 1; 2; 3 ]);
  check "N24 GROUNDED: spans are counted over Wiki_graph's OWN communities"
    (fun () ->
      (* recomputed independently from Wiki_graph.communities + edges:
         a fresh clustering would disagree here *)
      let comm =
        List.concat_map
          (fun (k, ms) -> List.map (fun s -> (s, k)) ms)
          (Wiki_graph.communities (Wiki_graph.of_model bridged))
      in
      let nbrs s =
        List.filter_map
          (fun (u, v) -> if u = s then Some v else if v = s then Some u else None)
          (Wiki_similarity.edges bridged)
      in
      List.for_all
        (fun (s, span) ->
          let mine = List.assoc s comm in
          let expect =
            nbrs s |> List.map (fun u -> List.assoc u comm)
            |> List.filter (fun k -> k <> mine)
            |> List.sort_uniq compare |> List.length
          in
          span = expect)
        (Wiki_similarity.structural_holes bridged));
  check "N25 a BROKER spans a hole; an interior node spans none" (fun () ->
      let h = Wiki_similarity.structural_holes bridged in
      List.assoc "hub" h = 1 && List.assoc "b1" h = 1 && List.assoc "a2" h = 0
      && List.assoc "b3" h = 0);
  check "N26 COVER: one entry per page, span descending then slug ascending"
    (fun () ->
      let h = Wiki_similarity.structural_holes bridged in
      let rec ordered = function
        | (s1, x1) :: ((s2, x2) :: _ as rest) ->
            (x1 > x2 || (x1 = x2 && compare s1 s2 < 0)) && ordered rest
        | [ _ ] | [] -> true
      in
      List.length h = List.length bridged.Hermes_wiki.pages
      && List.sort compare (List.map fst h) = slugs bridged
      && ordered h);
  check "N27 the MoC hub is the TOP-DEGREE member, not the first slug" (fun () ->
      let m =
        mk
          [ ("pages/wiki/m1.md", "# M1\n\n[[zed]]\n"); ("pages/wiki/m2.md", "# M2\n\n[[zed]]\n");
            ("pages/wiki/zed.md", "# Zed\n\n[[m1]]\n") ]
      in
      Wiki_similarity.community_mocs m = [ ("zed", [ "m1"; "m2"; "zed" ]) ]);
  check "N28 MoC ties break by SLUG when degrees are equal" (fun () ->
      Wiki_similarity.community_mocs two_cliques
      = [ ("a1", [ "a1"; "a2"; "a3" ]); ("b1", [ "b1"; "b2"; "b3" ]) ]);
  check "N29 MoCs are GROUNDED: membership equals the Wiki_graph community"
    (fun () ->
      let cs = Wiki_graph.communities (Wiki_graph.of_model bridged) in
      List.for_all
        (fun (_, members) -> List.exists (fun (_, ms) -> ms = members) cs)
        (Wiki_similarity.community_mocs bridged));
  check "N30 ROLLUP COVER: the parts sum to the whole" (fun () ->
      let r = Wiki_similarity.rollup_count bridged ~key:(fun p -> p.Hermes_wiki.slug) in
      List.fold_left (fun a (_, n) -> a + n) 0 r = List.length bridged.Hermes_wiki.pages
      && List.length r = List.length bridged.Hermes_wiki.pages);
  check "N31 the BLANK-key bucket is counted, never dropped" (fun () ->
      let key (p : Hermes_wiki.page) = if p.Hermes_wiki.slug = "a1" then "" else "other" in
      let r = Wiki_similarity.rollup_count bridged ~key in
      List.assoc_opt "" r = Some 1
      && List.assoc_opt "other" r = Some 6
      && List.fold_left (fun a (_, n) -> a + n) 0 r = 7);
  check "N32 rollup carries a VALUE, and the value sums too" (fun () ->
      let r =
        Wiki_similarity.rollup bridged
          ~key:(fun p -> String.sub p.Hermes_wiki.slug 0 1)
          ~value:(fun _ -> 10)
      in
      List.fold_left (fun a (_, n) -> a + n) 0 r = 70
      && List.assoc_opt "a" r = Some 30
      && List.assoc_opt "h" r = Some 10);
  check "N33 rollup_communities covers the corpus and keys on the community"
    (fun () ->
      let r = Wiki_similarity.rollup_communities bridged in
      List.fold_left (fun a (_, n) -> a + n) 0 r = List.length bridged.Hermes_wiki.pages
      && List.assoc_opt "a1" r = Some 4
      && List.assoc_opt "b1" r = Some 3)

(* ------------------------------------------------- X* exhaustion *)

let () =
  check "X1 DETERMINISM: a SHUFFLED input list gives byte-identical vectors"
    (fun () ->
      let shuffled =
        (* a fixed, non-trivial permutation: reversed, then rotated *)
        match List.rev big_corpus with [] -> [] | x :: r -> r @ [ x ]
      in
      let a = Wiki_similarity.canonical bv in
      let b = Wiki_similarity.canonical (Wiki_similarity.vectors (mk shuffled)) in
      String.equal a b && String.length a > 0);
  check "X2 DETERMINISM: every similarity is bit-identical under shuffling"
    (fun () ->
      let shuffled = List.rev sim_corpus in
      let v2 = Wiki_similarity.vectors (mk shuffled) in
      let ss = slugs sim in
      List.for_all
        (fun a ->
          List.for_all
            (fun b -> bits (Wiki_similarity.similarity sv a b) = bits (Wiki_similarity.similarity v2 a b))
            ss)
        ss);
  check "X3 DETERMINISM: the ranked related list survives shuffling, in order"
    (fun () ->
      let shuffled = match List.rev big_corpus with [] -> [] | x :: r -> r @ [ x ] in
      let v2 = Wiki_similarity.vectors (mk shuffled) in
      Wiki_similarity.related bv "n07" = Wiki_similarity.related v2 "n07"
      && Wiki_similarity.related bv "n07" <> []);
  check "X4 a large corpus: 60 pages, every ranking total, no NaN anywhere"
    (fun () ->
      Wiki_similarity.corpus_size bv = 60
      && List.for_all
           (fun (_, x) -> (not (Float.is_nan x)) && x > 0.0 && x <= 1.0)
           (Wiki_similarity.related bv "n00")
      && List.length (Wiki_similarity.related bv "n00") = 59);
  check "X5 a term in EVERY document of a large corpus keeps idf at 1.0" (fun () ->
      Wiki_similarity.document_frequency bv "commonterm" = 60
      && Wiki_similarity.idf bv "commonterm" = 1.0);
  check "X6 a DENSE graph: the mirror and the cover laws still hold" (fun () ->
      let n = 12 in
      let dense =
        mk
          (List.init n (fun i ->
               ( Printf.sprintf "pages/wiki/d%02d.md" i,
                 Printf.sprintf "# D%02d\n\n%s\n" i
                   (String.concat " "
                      (List.init n (fun j -> Printf.sprintf "[[d%02d]]" j))) )))
      in
      List.length (Wiki_similarity.directed_edges dense)
      = Wiki_graph.edge_count (Wiki_graph.of_model dense)
      && List.length (Wiki_similarity.edges dense) = n * (n - 1) / 2
      && List.length (Wiki_similarity.structural_holes dense) = n
      && List.fold_left (fun a (_, c) -> a + c) 0 (Wiki_similarity.rollup_communities dense) = n);
  check "X7 a radius beyond the diameter saturates at the component" (fun () ->
      let l = Wiki_similarity.local_graph chain ~radius:99 "p1" in
      l.Wiki_similarity.nodes = [ "p1"; "p2"; "p3"; "p4" ]);
  check "X8 related honours its limit and stays a PREFIX of the full ranking"
    (fun () ->
      let full = Wiki_similarity.related bv "n00" in
      let five = Wiki_similarity.related ~limit:5 bv "n00" in
      List.length five = 5
      && five = List.filteri (fun i _ -> i < 5) full)

(* ------------------------------------------------------ S* stuck *)

let () =
  check "S1 an EMPTY corpus is defined everywhere: no crash, no NaN, no division"
    (fun () ->
      let m = mk [] in
      let v = Wiki_similarity.vectors m in
      Wiki_similarity.corpus_size v = 0
      && Wiki_similarity.idf v "anything" = 0.0
      && Wiki_similarity.similarity v "a" "b" = 0.0
      && Wiki_similarity.related v "a" = []
      && Wiki_similarity.edges m = []
      && Wiki_similarity.degrees m = []
      && Wiki_similarity.structural_holes m = []
      && Wiki_similarity.community_mocs m = []
      && Wiki_similarity.rollup_communities m = []
      && Wiki_similarity.rollup_count m ~key:(fun p -> p.Hermes_wiki.slug) = []
      && Wiki_similarity.tag_tree m = []);
  check "S2 a SINGLE page: similar to itself, related to nothing" (fun () ->
      let m = mk [ ("pages/wiki/only.md", "# Only\n\nsome words\n") ] in
      let v = Wiki_similarity.vectors m in
      Wiki_similarity.similarity v "only" "only" = 1.0
      && Wiki_similarity.related v "only" = []
      && Wiki_similarity.local_graph m ~radius:3 "only" = { Wiki_similarity.center = "only"; nodes = [ "only" ]; edges = [] });
  check "S3 a page with NO TOKENS is similar to nothing, and is not NaN" (fun () ->
      let m = mk [ ("pages/wiki/blank.md", ""); ("pages/wiki/full.md", "# Full\n\nreal words\n") ] in
      let v = Wiki_similarity.vectors m in
      Wiki_similarity.weights v "blank" = []
      && Wiki_similarity.similarity v "blank" "full" = 0.0
      && Wiki_similarity.similarity v "full" "blank" = 0.0
      && Wiki_similarity.similarity v "blank" "blank" = 1.0
      && Wiki_similarity.related v "blank" = []);
  check "S4 an ABSENT slug is answered, not raised" (fun () ->
      Wiki_similarity.similarity sv "ghost" "alpha" = 0.0
      && Wiki_similarity.similarity sv "alpha" "ghost" = 0.0
      && Wiki_similarity.similarity sv "ghost" "ghost" = 0.0
      && Wiki_similarity.related sv "ghost" = []
      && Wiki_similarity.weights sv "ghost" = []
      && Wiki_similarity.hops sim "ghost" = []);
  check "S5 an ABSENT slug yields an EMPTY neighbourhood" (fun () ->
      let l = Wiki_similarity.local_graph chain ~radius:2 "ghost" in
      l.Wiki_similarity.center = "ghost" && l.Wiki_similarity.nodes = []
      && l.Wiki_similarity.edges = []);
  check "S6 an UNLINKED corpus yields NO MoCs — a landmark needs a link"
    (fun () ->
      Wiki_similarity.community_mocs unlinked = []
      && Wiki_similarity.edges unlinked = []
      && List.for_all (fun (_, d) -> d = 0) (Wiki_similarity.degrees unlinked)
      && List.for_all (fun (_, s) -> s = 0) (Wiki_similarity.structural_holes unlinked));
  check "S7 a DISCONNECTED graph: the view is the component, never the corpus"
    (fun () ->
      let l = Wiki_similarity.local_graph split ~radius:99 "x1" in
      l.Wiki_similarity.nodes = [ "x1"; "x2" ]
      && Wiki_similarity.hops split "z1" = [ ("z1", 0) ]
      && (Wiki_similarity.local_graph split ~radius:99 "z1").Wiki_similarity.nodes = [ "z1" ]);
  check "S8 an EMPTY tag covers nothing and has no members" (fun () ->
      (not (Wiki_similarity.tag_covers ~parent:"" ~child:"a"))
      && (not (Wiki_similarity.tag_covers ~parent:"a" ~child:""))
      && (not (Wiki_similarity.tag_covers ~parent:"" ~child:""))
      && Wiki_similarity.tag_members tagged "" = []
      && Wiki_similarity.tag_members tagged "###" = []
      && Wiki_similarity.tag_ancestors "" = []);
  check "S9 an untagged corpus has an empty tag tree" (fun () ->
      Wiki_similarity.tag_tree unlinked = []
      && Wiki_similarity.tag_members unlinked "a" = []);
  check "S10 a rollup over an empty corpus is [], never a fabricated zero bucket"
    (fun () ->
      Wiki_similarity.rollup (mk []) ~key:(fun _ -> "k") ~value:(fun _ -> 1) = []
      && Wiki_similarity.rollup unlinked ~key:(fun _ -> "k") ~value:(fun _ -> 0)
         = [ ("k", 0) ])

(* -------------------------------------------------- A* anomalies *)

let () =
  check "A1 a SELF-LOOP, a DUPLICATE link and a DEAD link are never edges"
    (fun () ->
      Wiki_similarity.directed_edges messy = [ ("s1", "s2"); ("s2", "s1") ]
      && Wiki_similarity.edges messy = [ ("s1", "s2") ]
      && Wiki_similarity.degrees messy = [ ("s1", 1); ("s2", 1) ]
      && List.length (Wiki_similarity.directed_edges messy)
         = Wiki_graph.edge_count (Wiki_graph.of_model messy));
  check "A2 #a does NOT cover #ab — segment-wise, not string prefix" (fun () ->
      (not (Wiki_similarity.tag_covers ~parent:"a" ~child:"ab"))
      && (not (Wiki_similarity.tag_covers ~parent:"a/b" ~child:"a/bc"))
      && (not (List.mem "t3" (Wiki_similarity.tag_members tagged "a")))
      && Wiki_similarity.tag_members tagged "ab" = [ "t3" ]);
  check "A3 tags differing only in CASE or in a leading # are one tag" (fun () ->
      Wiki_similarity.tag_normalise "#A/B" = "a/b"
      && Wiki_similarity.tag_normalise "  #A//B/  " = "a/b"
      && Wiki_similarity.tag_normalise "#" = ""
      && Wiki_similarity.tag_normalise "///" = ""
      && List.mem "t4" (Wiki_similarity.tag_members tagged "a/b"));
  check "A4 a NEGATIVE radius reads as 0 rather than emptying the view" (fun () ->
      (Wiki_similarity.local_graph chain ~radius:(-5) "p2").Wiki_similarity.nodes = [ "p2" ]);
  check "A5 UNICODE does not raise and does not become a token" (fun () ->
      let m = mk [ ("pages/wiki/uni.md", "# Uni\n\nhe\xc3\xa9llo w\xc3\xb6rld abc\n") ] in
      let v = Wiki_similarity.vectors m in
      let ts = List.map fst (Wiki_similarity.weights v "uni") in
      List.mem "abc" ts && List.for_all (fun t -> not (contains t "\xc3")) ts);
  check "A6 a limit of 0 or less returns [], never the whole ranking" (fun () ->
      Wiki_similarity.related ~limit:0 bv "n00" = []
      && Wiki_similarity.related ~limit:(-3) bv "n00" = []);
  check "A7 a page tagged with the SAME tag twice counts once" (fun () ->
      let m = mk [ ("pages/wiki/dup.md", "---\ntopics: [a/b, A/B, a/b]\n---\n\n# Dup\n\nx\n") ] in
      Wiki_similarity.page_tags (Option.get (Hermes_wiki.page m "dup")) = [ "a/b" ]
      && Wiki_similarity.tag_members m "a" = [ "dup" ]);
  check "A8 REPORT-ONLY (R5): every analysis is a pure function of the model"
    (fun () ->
      (* called twice, nothing mutated, identical answers — a monitor
         senses and reports, it never changes what it observes *)
      Wiki_similarity.structural_holes bridged = Wiki_similarity.structural_holes bridged
      && Wiki_similarity.community_mocs bridged = Wiki_similarity.community_mocs bridged
      && Wiki_similarity.canonical (Wiki_similarity.vectors sim) = Wiki_similarity.canonical sv)

let () =
  Printf.printf "wiki_similarity: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_similarity" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_similarity ]);
  exit (Wiki_suite_telemetry.exit_code self)
