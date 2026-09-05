(* HW.6.4.1 / HW.6.4.3 / HW.6.3.3 / HW.6.3.4 / HW.6.11.1 / HW.6.6.1 — the
   navigation and search surfaces, across the full functional envelope:

     N*  nominal      each row's claim on a corpus that behaves
     X*  exhaustion   many queries, a wide corpus, a deep tree
     S*  stuck        empty corpus, no fence, unknown commit, no match
     A*  anomaly      shuffled input, cycles, fenced marks, unknown seeds

   The four headline laws, in the order they would hurt most if lost:

     ONE KERNEL, TWO CONSUMERS (HW.6.3.4). The global and personalised
     rankings are the SAME function, and the proof is BYTE equality of a
     hex-float serialisation — two implementations that agreed to six
     decimal places would pass a weaker test and diverge in a month. The
     identity is guarded from vacuity by its companion: a real seed must
     CHANGE the ranking, or "same function" would be satisfied by a
     function that ignores its seeds.

     SUPERSET OF EXACT MATCH (HW.6.4.3). Every exact hit appears in quick
     find, checked over a table of queries rather than one lucky query.

     FENCE BODIES ONLY (HW.6.3.3). Proven as a PAIR of negatives: a term
     living only in prose yields no code hit, and a term living only in a
     fence yields a code hit and no full-text hit.

     as_of(c) = build(checkout c) (HW.6.6.1), witnessed structurally
     against an independently built model, and non-vacuously: two
     commits must produce two different answers. *)

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

(* ------------------------------------------------------------ corpora *)

let p name body = ("pages/wiki/" ^ name ^ ".md", body)

let files =
  [ p "root" "# Root\n\n```toctree\nguide\n```\n";
    p "guide" "# Guide\n\n```toctree\nintro\nadvanced\n```\n";
    p "intro" "# Intro\n\nzebra lives in prose only.\n";
    (* TWO body lines, deliberately: with a one-line fence, a code search
       that required ANY query token instead of ALL of them survives *)
    p "advanced" "# Advanced\n\n```ocaml\nlet quokka = 1\nreturn alpha\n```\n\ncommon word here.\n";
    p "loose" "# Loose\n\nno tree declares me, common word.\n";
    p "todos"
      ("# Todos\n\n.. todo:: ship the gate\n   with a body line\n\n"
      ^ "a sentence saying TODO: fix this is a sentence\n\n"
      ^ "> [!todo] wire the dashboard\n> more detail\n\n"
      ^ "```\n.. todo:: an example, not a use\n```\n\n"
      ^ ".. todo:: ship the gate\n");
    (* LAST in the file list and FIRST by slug, deliberately: a collection
       that walked the model's page order instead of slug order would
       return these two pages the other way round, and with the todos on
       one page only that mutation survives (it did). *)
    p "aa-todo" "# Aa Todo\n\n.. todo:: earlier by slug\n" ]

let m = Hermes_wiki.build files
let toc = Wiki_toc.of_model m
let idx = Wiki_navsearch.build m

let gfiles =
  [ p "aa" "# Aa\n\n[[bb]]\n"; p "bb" "# Bb\n\n[[cc]]\n"; p "cc" "# Cc\n\ntext here\n" ]

let g = Wiki_graph.of_model (Hermes_wiki.build gfiles)

let slugs_of hits = List.map (fun (h : Wiki_navsearch.find_hit) -> h.Wiki_navsearch.slug) hits

let queries =
  [ "intro"; "guide"; "root"; "advanced"; "loose"; "zebra"; "quokka"; "common"; "word";
    "Intro"; "the guide"; "adv"; "gd"; "xyzzy"; ""; "  "; "!!!"; "common word"; "todos";
    "Root"; "ro"; "ce" ]

(* ------------------------------------------------------------ nominal *)

let () =
  check "N1 HW.6.4.1 a breadcrumb is the DECLARED path, root-first, page last" (fun () ->
      Wiki_navsearch.breadcrumb_slugs m toc "intro" = [ "root"; "guide"; "intro" ]);
  check "N2 HW.6.4.1 every crumb RESOLVES: a title and its own url" (fun () ->
      let cs = Wiki_navsearch.breadcrumb m toc "intro" in
      List.length cs = 3
      && List.for_all (fun (c : Wiki_navsearch.crumb) -> c.Wiki_navsearch.title <> "") cs
      && List.for_all
           (fun (c : Wiki_navsearch.crumb) ->
             c.Wiki_navsearch.href = c.Wiki_navsearch.slug ^ ".html")
           cs
      && Wiki_navsearch.breadcrumb_gaps m toc = []);
  check "N3 HW.6.4.1 PREFIX-CLOSED over EVERY placed page, at every depth" (fun () ->
      (* the law in its strong form: the first k crumbs of x are exactly
         the crumbs of the k-th crumb, for every placed x and every k *)
      List.for_all
        (fun s ->
          let cs = Wiki_navsearch.breadcrumb_slugs m toc s in
          cs <> []
          && List.nth cs (List.length cs - 1) = s
          && List.for_all
               (fun k ->
                 let pre = List.filteri (fun i _ -> i < k) cs in
                 Wiki_navsearch.breadcrumb_slugs m toc (List.nth cs (k - 1)) = pre)
               (List.init (List.length cs) (fun i -> i + 1)))
        (Wiki_toc.placed toc));
  check "N4 HW.6.3.3 a term living ONLY IN A FENCE yields a code hit" (fun () ->
      let hs = Wiki_navsearch.code_search idx "quokka" in
      List.length hs = 1
      && (List.hd hs).Wiki_navsearch.slug = "advanced"
      && (List.hd hs).Wiki_navsearch.lang = "ocaml"
      && contains (List.hd hs).Wiki_navsearch.text "quokka"
      (* "fence bodies only", not "fences whose language I approve of": a
         toctree body indexes as code like any other, and a special case
         here would be a second fence grammar in disguise *)
      && Wiki_navsearch.code_slugs idx "guide" = [ "root" ]);
  check "N5 HW.6.3.3 code search uses the SAME tokeniser as full text" (fun () ->
      (* `let quokka = 1` tokenises to let/quokka; the digit run is
         dropped by the length-2 rule in BOTH indexes or the two parts
         of the system disagree about what a word is *)
      Wiki_search.tokens "let quokka = 1" = [ "let"; "quokka" ]
      && Wiki_navsearch.code_slugs idx "let" = [ "advanced" ]
      && Wiki_navsearch.code_search idx "1" = []
      (* EVERY token, not any: `let quokka` share a line and match; `let
         zebra` does not, and zebra is in no fence at all *)
      && List.length (Wiki_navsearch.code_search idx "let quokka") = 1
      && Wiki_navsearch.code_search idx "let zebra" = []
      (* the STATED limit: tokens that straddle a line break do not match *)
      && Wiki_navsearch.code_search idx "quokka alpha" = []
      && List.length (Wiki_navsearch.code_search idx "return alpha") = 1);
  check "N6 HW.6.4.3 quick find ranks an exact slug first and names why" (fun () ->
      match Wiki_navsearch.quick_find idx "intro" with
      | h :: _ -> h.Wiki_navsearch.slug = "intro" && h.Wiki_navsearch.why = "exact slug"
      | [] -> false);
  check "N7 HW.6.4.3 a FUZZY query finds what an exact one cannot" (fun () ->
      (* `adv` is nobody's slug and nobody's word; a prefix finder gets it *)
      Wiki_navsearch.exact_matches idx "adv" = []
      && List.mem "advanced" (slugs_of (Wiki_navsearch.quick_find idx "adv")));
  check "N8 HW.6.3.4 ONE KERNEL: personalised-with-every-seed IS global, BYTE for BYTE"
    (fun () ->
      let uniform = Wiki_navsearch.rank_personal ~seeds:(Wiki_graph.nodes g) g in
      let global = Wiki_navsearch.rank_global g in
      Wiki_navsearch.rank_canonical uniform = Wiki_navsearch.rank_canonical global
      && Wiki_navsearch.rank_canonical (Wiki_navsearch.rank ~seeds:[] g)
         = Wiki_navsearch.rank_canonical global
      (* and the serialisation is HEX, so "equal" means equal doubles *)
      && contains (Wiki_navsearch.rank_canonical global) "0x");
  check "N9 HW.6.3.4 NOT VACUOUS: a real seed CHANGES the ranking" (fun () ->
      let seeded = Wiki_navsearch.rank_personal ~seeds:[ "aa" ] g in
      let global = Wiki_navsearch.rank_global g in
      Wiki_navsearch.rank_canonical seeded <> Wiki_navsearch.rank_canonical global
      && seeded.Wiki_navsearch.seeds_used = [ "aa" ]
      && List.assoc "aa" seeded.Wiki_navsearch.rows > List.assoc "aa" global.Wiki_navsearch.rows);
  check "N10 HW.6.3.4 consumer two: `related` drops the seed and keeps the rest" (fun () ->
      let r = Wiki_navsearch.related g "aa" in
      (not (List.mem_assoc "aa" r.Wiki_navsearch.rows))
      && List.length r.Wiki_navsearch.rows = List.length (Wiki_graph.nodes g) - 1
      && r.Wiki_navsearch.seeds_used = [ "aa" ]);
  check "N11 HW.6.11.1 every MARKED todo is collected, both forms, with its text" (fun () ->
      let ts = Wiki_navsearch.todos m in
      List.length ts = 4
      && List.map (fun (t : Wiki_navsearch.todo) -> t.Wiki_navsearch.form) ts
         = [ Wiki_navsearch.Directive; Wiki_navsearch.Directive; Wiki_navsearch.Callout;
             Wiki_navsearch.Directive ]
      && List.map (fun (t : Wiki_navsearch.todo) -> t.Wiki_navsearch.text) ts
         = [ "earlier by slug"; "ship the gate"; "wire the dashboard"; "ship the gate" ]);
  check "N12 HW.6.11.1 a todo carries its BODY, de-indented" (fun () ->
      let ts = Wiki_navsearch.todos_of m "todos" in
      (List.hd ts).Wiki_navsearch.body = [ "with a body line" ]
      && (List.nth ts 1).Wiki_navsearch.body = [ "more detail" ]
      && (List.nth ts 2).Wiki_navsearch.body = []);
  check "N13 HW.6.6.1 as_of(c) = build(checkout c), witnessed structurally" (fun () ->
      let f1 = [ p "aa" "# Aa\n\nfirst\n" ] in
      let f2 = [ p "aa" "# Aa\n\nsecond\n"; p "bb" "# Bb\n\nnew page\n" ] in
      let h =
        Wiki_navsearch.history_of
          [ { Wiki_navsearch.commit = "c2"; order = 2; files = f2 };
            { Wiki_navsearch.commit = "c1"; order = 1; files = f1 } ]
      in
      Wiki_navsearch.as_of h "c1" = Some (Hermes_wiki.build f1)
      && Wiki_navsearch.as_of h "c2" = Some (Hermes_wiki.build f2)
      (* NOT VACUOUS: two commits, two different answers *)
      && Wiki_navsearch.as_of h "c1" <> Wiki_navsearch.as_of h "c2"
      && Wiki_navsearch.commits h = [ "c1"; "c2" ]);
  check "N14 HW.6.6.1 the index at a commit sees THAT commit's corpus" (fun () ->
      let h =
        Wiki_navsearch.history_of
          [ { Wiki_navsearch.commit = "c1"; order = 1;
              files = [ p "aa" "# Aa\n\n```\nquokka\n```\n" ] };
            { Wiki_navsearch.commit = "c2"; order = 2; files = [ p "aa" "# Aa\n\nplain\n" ] } ]
      in
      match (Wiki_navsearch.index_as_of h "c1", Wiki_navsearch.index_as_of h "c2") with
      | Some i1, Some i2 ->
          Wiki_navsearch.code_slugs i1 "quokka" = [ "aa" ]
          && Wiki_navsearch.code_slugs i2 "quokka" = []
      | _ -> false)

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 HW.6.4.3 SUPERSET OF EXACT MATCH over a TABLE of queries, not one" (fun () ->
      List.for_all
        (fun q ->
          let ex = Wiki_navsearch.exact_matches idx q in
          let qf = slugs_of (Wiki_navsearch.quick_find idx q) in
          List.for_all (fun s -> List.mem s qf) ex)
        queries);
  check "X2 HW.6.4.3 the containment is NOT VACUOUS: some query has real exact hits"
    (fun () ->
      List.exists (fun q -> Wiki_navsearch.exact_matches idx q <> []) queries
      && List.mem "intro" (Wiki_navsearch.exact_matches idx "intro")
      (* a body word nobody's slug carries — the load-bearing disjunct *)
      && Wiki_navsearch.exact_matches idx "zebra" = [ "intro" ]
      && List.mem "intro" (slugs_of (Wiki_navsearch.quick_find idx "zebra")));
  check "X3 quick find is TOTALLY ORDERED: score desc, then slug asc, no ties left" (fun () ->
      List.for_all
        (fun q ->
          let hs = Wiki_navsearch.quick_find idx q in
          let rec ok = function
            | (a : Wiki_navsearch.find_hit) :: (b : Wiki_navsearch.find_hit) :: tl ->
                (a.Wiki_navsearch.score > b.Wiki_navsearch.score
                || (a.Wiki_navsearch.score = b.Wiki_navsearch.score
                   && a.Wiki_navsearch.slug < b.Wiki_navsearch.slug))
                && ok (b :: tl)
            | _ -> true
          in
          ok hs)
        queries);
  check "X4 a WIDE corpus: 60 pages, every one findable by its own slug" (fun () ->
      let wide = List.init 60 (fun i -> p (Printf.sprintf "page%02d" i) "# P\n\nbody text\n") in
      let wi = Wiki_navsearch.build (Hermes_wiki.build wide) in
      List.for_all
        (fun i ->
          let s = Printf.sprintf "page%02d" i in
          match Wiki_navsearch.quick_find wi s with
          | h :: _ -> h.Wiki_navsearch.slug = s
          | [] -> false)
        (List.init 60 (fun i -> i)));
  check "X5 a DEEP tree: a 12-level chain breadcrumbs to 12 crumbs, prefix-closed" (fun () ->
      let n = 12 in
      let deep =
        List.init n (fun i ->
            let body =
              if i = n - 1 then "# D\n\nleaf\n"
              else Printf.sprintf "# D\n\n```toctree\nd%02d\n```\n" (i + 1)
            in
            p (Printf.sprintf "d%02d" i) body)
      in
      let dm = Hermes_wiki.build deep in
      let dt = Wiki_toc.of_model dm in
      let cs = Wiki_navsearch.breadcrumb_slugs dm dt (Printf.sprintf "d%02d" (n - 1)) in
      List.length cs = n
      && List.hd cs = "d00"
      && Wiki_navsearch.breadcrumb_gaps dm dt = []);
  check "X6 rank_mass over EVERY node is 1.0, and the kernel's rows are complete"
    (fun () ->
      let r = Wiki_navsearch.rank_global g in
      let mass = Wiki_navsearch.rank_mass r (Wiki_graph.nodes g) in
      abs_float (mass -. 1.0) < 1e-6
      && List.length r.Wiki_navsearch.rows = List.length (Wiki_graph.nodes g))

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 an EMPTY corpus is a defined value everywhere, never a raise" (fun () ->
      let em = Hermes_wiki.build [] in
      let et = Wiki_toc.of_model em in
      let ei = Wiki_navsearch.build em in
      let eg = Wiki_graph.of_model em in
      Wiki_navsearch.breadcrumb em et "ghost" = []
      && Wiki_navsearch.breadcrumb_gaps em et = []
      && Wiki_navsearch.quick_find ei "anything" = []
      && Wiki_navsearch.code_search ei "anything" = []
      && Wiki_navsearch.todos em = []
      && (Wiki_navsearch.rank_global eg).Wiki_navsearch.rows = []
      && Wiki_navsearch.rank_mass (Wiki_navsearch.rank_global eg) [ "ghost" ] = 0.0);
  check "S2 an UNPLACED page breadcrumbs to ITSELF — never [], which would deny it"
    (fun () ->
      Wiki_navsearch.breadcrumb_slugs m toc "loose" = [ "loose" ]
      && List.mem "loose" (Wiki_toc.unplaced m toc));
  check "S3 a slug naming NO page breadcrumbs to [] — which says exactly that" (fun () ->
      Wiki_navsearch.breadcrumb_slugs m toc "ghost" = []
      && Wiki_navsearch.breadcrumb m toc "ghost" = []);
  check "S4 a page with NO FENCE contributes no code posting" (fun () ->
      Wiki_navsearch.code_slugs idx "zebra" = []
      && not (List.mem "intro" (Wiki_navsearch.code_slugs idx "prose")));
  check "S5 a query matching NOTHING is [] everywhere, in both surfaces" (fun () ->
      Wiki_navsearch.quick_find idx "xyzzyplugh" = []
      && Wiki_navsearch.code_search idx "xyzzyplugh" = []
      && Wiki_navsearch.exact_matches idx "xyzzyplugh" = []);
  check "S6 an EMPTY or all-punctuation query matches NOTHING, never everything" (fun () ->
      List.for_all
        (fun q ->
          Wiki_navsearch.quick_find idx q = [] && Wiki_navsearch.exact_matches idx q = [])
        [ ""; "   "; "!!!"; "***"; "\t" ]);
  check "S7 an UNKNOWN commit is None — distinct from Some [], an empty revision"
    (fun () ->
      let h =
        Wiki_navsearch.history_of [ { Wiki_navsearch.commit = "c0"; order = 0; files = [] } ]
      in
      Wiki_navsearch.checkout h "nope" = None
      && Wiki_navsearch.as_of h "nope" = None
      && Wiki_navsearch.index_as_of h "nope" = None
      && Wiki_navsearch.checkout h "c0" = Some []
      && Wiki_navsearch.as_of h "c0" <> None);
  check "S8 an EMPTY history answers nothing and says so" (fun () ->
      let h = Wiki_navsearch.history_of [] in
      Wiki_navsearch.commits h = []
      && Wiki_navsearch.duplicate_commits h = []
      && Wiki_navsearch.as_of h "c1" = None);
  check "S9 a page with no title still yields a crumb, never an exception" (fun () ->
      let bm = Hermes_wiki.build [ p "bare" "" ] in
      let bt = Wiki_toc.of_model bm in
      match Wiki_navsearch.breadcrumb bm bt "bare" with
      | [ c ] -> c.Wiki_navsearch.slug = "bare" && c.Wiki_navsearch.href = "bare.html"
      | _ -> false)

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 DETERMINISM: a SHUFFLED corpus builds a BYTE-IDENTICAL index" (fun () ->
      let shuffled = List.rev files in
      let other = List.tl files @ [ List.hd files ] in
      let c = Wiki_navsearch.canonical idx in
      c = Wiki_navsearch.canonical (Wiki_navsearch.build (Hermes_wiki.build shuffled))
      && c = Wiki_navsearch.canonical (Wiki_navsearch.build (Hermes_wiki.build other))
      && Wiki_navsearch.digest idx
         = Wiki_navsearch.digest (Wiki_navsearch.build (Hermes_wiki.build shuffled)));
  check "A2 DETERMINISM: a shuffled corpus ranks BYTE-IDENTICALLY (last bit included)"
    (fun () ->
      let g2 = Wiki_graph.of_model (Hermes_wiki.build (List.rev gfiles)) in
      Wiki_navsearch.rank_canonical (Wiki_navsearch.rank_global g)
      = Wiki_navsearch.rank_canonical (Wiki_navsearch.rank_global g2)
      && Wiki_navsearch.rank_canonical (Wiki_navsearch.rank_personal ~seeds:[ "cc" ] g)
         = Wiki_navsearch.rank_canonical (Wiki_navsearch.rank_personal ~seeds:[ "cc" ] g2));
  check "A3 DETERMINISM: rank_mass is a function of the SET, not of the listing"
    (fun () ->
      let r = Wiki_navsearch.rank_global g in
      let a = [ "aa"; "bb"; "cc" ] and b = [ "cc"; "aa"; "bb" ] and c = [ "bb"; "cc"; "aa"; "bb" ] in
      (* float equality, deliberately: an order-dependent sum differs in
         the last bit and that is exactly what must not happen *)
      Wiki_navsearch.rank_mass r a = Wiki_navsearch.rank_mass r b
      && Wiki_navsearch.rank_mass r a = Wiki_navsearch.rank_mass r c);
  check "A4 DETERMINISM: shuffled input yields the same todos, in SLUG then LINE order"
    (fun () ->
      let ts = Wiki_navsearch.todos m in
      let keys = List.map (fun (t : Wiki_navsearch.todo) -> (t.Wiki_navsearch.slug, t.Wiki_navsearch.line)) ts in
      ts = Wiki_navsearch.todos (Hermes_wiki.build (List.rev files))
      && ts = Wiki_navsearch.todos (Hermes_wiki.build (List.tl files @ [ List.hd files ]))
      (* the collection SPANS pages, and the span is ordered — with todos
         on one page only, a model-order walk is indistinguishable *)
      && List.length (List.sort_uniq compare (List.map fst keys)) > 1
      && keys = List.sort compare keys);
  check "A5 HW.6.3.3 the NEGATIVE: a term only in PROSE yields NO code hit" (fun () ->
      (* zebra is in intro's prose and nowhere else. Full text finds it;
         code search must not — the two indexes PARTITION the document *)
      Wiki_search.search (Wiki_navsearch.search_index idx) "zebra" = [ ("intro", 1) ]
      && Wiki_navsearch.code_search idx "zebra" = []);
  check "A6 HW.6.3.3 the DUAL negative: a term only in a FENCE yields no full-text hit"
    (fun () ->
      Wiki_search.search (Wiki_navsearch.search_index idx) "quokka" = []
      && Wiki_navsearch.code_slugs idx "quokka" = [ "advanced" ]);
  check "A7 HW.6.11.1 a todo inside a FENCE is an example, not a use" (fun () ->
      not
        (List.exists
           (fun (t : Wiki_navsearch.todo) -> contains t.Wiki_navsearch.text "an example")
           (Wiki_navsearch.todos m)));
  check "A8 HW.6.11.1 a bare TODO: in prose is PROSE — the mark is the grammar" (fun () ->
      not
        (List.exists
           (fun (t : Wiki_navsearch.todo) -> contains t.Wiki_navsearch.text "fix this")
           (Wiki_navsearch.todos m)));
  check "A9 HW.6.11.1 EVERY MARKED TODO ONCE: identical text twice is two todos, keyed by line"
    (fun () ->
      let ts = Wiki_navsearch.todos_of m "todos" in
      let same =
        List.filter (fun (t : Wiki_navsearch.todo) -> t.Wiki_navsearch.text = "ship the gate") ts
      in
      List.length same = 2
      && (match same with [ a; b ] -> a.Wiki_navsearch.line <> b.Wiki_navsearch.line | _ -> false)
      && List.length (List.sort_uniq compare (List.map (fun (t : Wiki_navsearch.todo) -> (t.Wiki_navsearch.slug, t.Wiki_navsearch.line)) ts))
         = List.length ts);
  check "A10 HW.6.11.1 an INDENTED marker is not at column zero and is not a use" (fun () ->
      let im = Hermes_wiki.build [ p "ind" "# I\n\n   .. todo:: indented\n\nplain\n" ] in
      Wiki_navsearch.todos im = []);
  check "A11 HW.6.3.4 an UNKNOWN seed LEAVES A MARK instead of degrading silently"
    (fun () ->
      let r = Wiki_navsearch.rank_personal ~seeds:[ "ghost"; "aa"; "ghost" ] g in
      r.Wiki_navsearch.seeds_unknown = [ "ghost" ]
      && r.Wiki_navsearch.seeds_used = [ "aa" ]);
  check "A12 HW.6.3.4 an ALL-UNKNOWN seeding is refused rows, not silently made global"
    (fun () ->
      let r = Wiki_navsearch.related g "ghost" in
      r.Wiki_navsearch.rows = []
      && r.Wiki_navsearch.seeds_unknown = [ "ghost" ]
      && r.Wiki_navsearch.seeds_used = []);
  check "A13 HW.6.3.4 a DISCONNECTED graph still ranks every node, no NaN, no zero divide"
    (fun () ->
      let dg =
        Wiki_graph.of_model
          (Hermes_wiki.build [ p "x" "# X\n\nalone\n"; p "y" "# Y\n\nalso alone\n" ])
      in
      let r = Wiki_navsearch.rank_global dg in
      List.length r.Wiki_navsearch.rows = 2
      && List.for_all
           (fun (_, v) -> v = v && v > 0.0 && v < 1.0 && Float.is_finite v)
           r.Wiki_navsearch.rows);
  check "A14 HW.6.4.1 a DECLARATION CYCLE terminates and still yields a prefix path"
    (fun () ->
      let cm =
        Hermes_wiki.build
          [ p "ca" "# Ca\n\n```toctree\ncb\n```\n"; p "cb" "# Cb\n\n```toctree\nca\n```\n" ]
      in
      let ct = Wiki_toc.of_model cm in
      let a = Wiki_navsearch.breadcrumb_slugs cm ct "ca" in
      let b = Wiki_navsearch.breadcrumb_slugs cm ct "cb" in
      a <> [] && b <> []
      && List.nth a (List.length a - 1) = "ca"
      && List.nth b (List.length b - 1) = "cb"
      && Wiki_navsearch.breadcrumb_gaps cm ct = []);
  check "A15 HW.6.6.1 a DUPLICATE commit id is reported, never merged, never overwritten"
    (fun () ->
      let h =
        Wiki_navsearch.history_of
          [ { Wiki_navsearch.commit = "c1"; order = 1; files = [ p "aa" "# A\n\nfirst\n" ] };
            { Wiki_navsearch.commit = "c1"; order = 2; files = [ p "aa" "# A\n\nsecond\n" ] } ]
      in
      Wiki_navsearch.duplicate_commits h = [ "c1" ]
      && Wiki_navsearch.commits h = [ "c1" ]
      && Wiki_navsearch.checkout h "c1" = Some [ ("pages/wiki/aa.md", "# A\n\nfirst\n") ]);
  check "A16 HW.6.6.1 the history is INSENSITIVE to the order revisions were listed in"
    (fun () ->
      let r1 = { Wiki_navsearch.commit = "c1"; order = 1; files = [ p "aa" "# A\n\none\n" ] } in
      let r2 = { Wiki_navsearch.commit = "c2"; order = 2; files = [ p "aa" "# A\n\ntwo\n" ] } in
      let r3 = { Wiki_navsearch.commit = "c3"; order = 3; files = [ p "aa" "# A\n\nthree\n" ] } in
      let a = Wiki_navsearch.history_of [ r1; r2; r3 ] in
      let b = Wiki_navsearch.history_of [ r3; r1; r2 ] in
      Wiki_navsearch.commits a = Wiki_navsearch.commits b
      && Wiki_navsearch.checkout a "c2" = Wiki_navsearch.checkout b "c2");
  check "A17 HW.6.6.1 a revision's snapshot is CANONICAL: sorted by path" (fun () ->
      let h =
        Wiki_navsearch.history_of
          [ { Wiki_navsearch.commit = "c";
              order = 0;
              files = [ p "zz" "# Z\n"; p "aa" "# A\n"; p "mm" "# M\n" ] } ]
      in
      match Wiki_navsearch.checkout h "c" with
      | Some fs -> List.map fst fs = List.sort compare (List.map fst fs)
      | None -> false);
  check "A18 TOTAL over pathological queries — no raise, no exception, ever" (fun () ->
      List.for_all
        (fun q ->
          match
            ( Wiki_navsearch.quick_find idx q,
              Wiki_navsearch.code_search idx q,
              Wiki_navsearch.exact_matches idx q )
          with
          | _ -> true)
        [ ""; "\000"; String.make 4000 'a'; "-"; "--"; "a"; "[[]]"; "```"; "\n\n" ]);
  check "A19 TOTAL over pathological page bodies — the scanners never raise" (fun () ->
      List.for_all
        (fun body ->
          let bm = Hermes_wiki.build [ p "path" body ] in
          match (Wiki_navsearch.todos bm, Wiki_navsearch.build bm) with _ -> true)
        [ ""; "```"; "```\n"; ".."; ".. ::"; ".. todo::"; ">"; "> [!todo]"; ">[!todo]";
          String.make 3000 '>'; "\n\n\n" ]);
  check "A20 an unterminated fence still yields code postings, never a crash" (fun () ->
      let um = Hermes_wiki.build [ p "unt" "# U\n\n```ocaml\nquokka here\n" ] in
      let ui = Wiki_navsearch.build um in
      match (Wiki_navsearch.code_slugs ui "quokka", Wiki_navsearch.code_search ui "quokka") with
      | [], [] -> true (* the fence grammar may drop it — both answers are total *)
      | [ "unt" ], _ :: _ -> true
      | _ -> false)

let () =
  check "A21 HW.6.3.3 the PARTITION survives the shapes where the two walks could disagree"
    (fun () ->
      (* Wiki_search walks fences with a flat trim-and-toggle; this index
         walks them with the block carrier. Two implementations, one
         claim — pinned here on the two hostile shapes, so a change to
         either walk surfaces as a failure rather than as a term that is
         findable twice or findable never. *)
      let hostile =
        Hermes_wiki.build
          [ p "quoted" "# Q\n\n> ```\n> secretq\n> ```\n";
            p "listed" "# L\n\n- item\n\n  ```\n  secretl\n  ```\n" ]
      in
      let hi = Wiki_navsearch.build hostile in
      let seen t =
        ( Wiki_search.search (Wiki_navsearch.search_index hi) t <> [],
          Wiki_navsearch.code_search hi t <> [] )
      in
      (* a QUOTED fence: prose to both walks — one home, not none, not two *)
      seen "secretq" = (true, false)
      (* an INDENTED fence in a list: code to both walks *)
      && seen "secretl" = (false, true));
  Printf.printf "wiki_navsearch: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_navsearch" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_navsearch ]);
  exit (Wiki_suite_telemetry.exit_code self)
