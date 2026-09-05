(* The Sphinx directive family (HW.2.6.1/2/4/5/8, HW.2.7.1), across the
   full functional envelope:

     N*  nominal      each of the six rows does what its claim says
     X*  exhaustion   a huge document, deep nesting, wide fan-out
     S*  stuck        bare arguments, undecidable conditions, EOF clamps
     A*  anomaly      fences, inline code, unknown directives, the
                      NEGATIVE laws (rubric absent from toc and anchors,
                      docinfo absent from the body, authorship absent
                      from the graph)

   The headline law under all of them: NOTHING THE AUTHOR WROTE IS LOST.
   [source_lines o parse] is the identity on the input's lines, for every
   string — an unknown directive, a half-written condition and a fence
   that never closes all come back byte for byte. Its dual is that
   nothing leaves without a receipt: content a conditional withholds is
   counted, because content dropped silently is invisible loss. *)

open Wiki_directive

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

let doc ls = String.concat "\n" ls
let body_lines t = List.concat_map (function Text ls -> ls | Heading _ | Fenced _ | Block _ -> []) t.nodes
let has_diag t d = List.mem d t.diagnostics
let kinds t = List.map (fun d -> d.kind) (directives t)

(* ------------------------------------------------------------- nominal *)

let seealso_doc =
  doc [ "# Parity"; ""; ".. seealso::"; ""; "   [[alpha]] and [[beta#Section]]"; ""; "after."; "" ]

let () =
  check "N1 HW.2.6.1 seealso entries are GRAPH EDGES, as (source, target) pairs" (fun () ->
      let t = parse seealso_doc in
      edges ~source:"parity" t = [ ("parity", "alpha"); ("parity", "beta") ]);
  check "N1b the fragment is stripped and the target slugified — the SAME normalisation \
         page.outlinks uses, so a seealso edge cannot drift from an outlink" (fun () ->
      let t = parse (doc [ ".. seealso::"; ""; "   [[Some Page#Deep Anchor]]"; "" ]) in
      edges ~source:"h" t = [ ("h", "some-page") ]);
  check "N1c the ONE-LINE form links too — the argument is an entry, so a `.. seealso:: \
         [[alpha]]` is a cross-reference and not decoration" (fun () ->
      let t = parse (doc [ ".. seealso:: [[alpha]]"; ""; "tail"; "" ]) in
      edges ~source:"h" t = [ ("h", "alpha") ] && t.diagnostics = []);
  check "N2 HW.2.6.2 a rubric is parsed and keeps its title" (fun () ->
      let t = parse (doc [ ".. rubric:: Design notes"; ""; "prose"; "" ]) in
      rubrics t = [ "Design notes" ] && kinds t = [ Rubric ]);
  check "N3 HW.2.6.4 a productionlist defines productions and records their refs" (fun () ->
      let t =
        parse
          (doc
             [ ".. productionlist:: expr";
               "   sum: `term` \"+\" `sum`";
               "   term: NUMBER";
               "" ])
      in
      match productions t with
      | [ a; b ] ->
          a.grammar = "expr" && a.pname = "sum" && a.refs = [ "term"; "sum" ]
          && b.pname = "term" && b.refs = []
          && undefined_productions t = []
      | [] | _ :: _ -> false);
  check "N4 HW.2.6.5 parse does NOT evaluate a conditional — its content is undecided \
         until a tag set is named" (fun () ->
      let t = parse (doc [ ".. only:: html"; ""; "   # Web only"; "" ]) in
      kinds t = [ Only ] && anchors t = [] && excluded_lines t = 0);
  check "N4b select against a DECLARED tag set keeps the content and splices it" (fun () ->
      let t = select ~declared:[ "html"; "pdf" ] ~active:[ "html" ]
                (parse (doc [ ".. only:: html"; ""; "   # Web only"; ""; "# Always"; "" ])) in
      anchors t = [ "web-only"; "always" ] && excluded_lines t = 0);
  check "N5 HW.2.6.8 an authorship directive is recognised by role and name" (fun () ->
      let t = parse (doc [ ".. sectionauthor:: Ada Lovelace"; ""; ".. codeauthor:: Grace"; "" ]) in
      authorship t = [ ("sectionauthor", "Ada Lovelace"); ("codeauthor", "Grace") ]);
  check "N6 HW.2.7.1 a leading field list is DOCINFO — metadata, names lowercased" (fun () ->
      let t = parse (doc [ ":Author: Ada"; ":version: 3"; ""; "# H"; ""; "body"; "" ]) in
      t.docinfo = [ ("author", "Ada"); ("version", "3") ] && t.diagnostics = []);
  check "N7 THE PRESERVATION LAW: source_lines o parse is the identity on lines" (fun () ->
      List.for_all
        (fun s -> source_lines (parse s) = String.split_on_char '\n' s)
        [ seealso_doc;
          doc [ ":author: Ada"; ""; "# H"; ""; ".. rubric:: R"; ""; "x"; "" ];
          doc [ "---"; "id: x"; "---"; ""; ".. sidebar:: Unknown"; "   held"; ""; "tail"; "" ];
          doc [ "```"; ".. seealso::"; "```"; "" ];
          "";
          "no directives at all\n" ]);
  check "N8 headings — and only headings — drive the toc and the anchor set" (fun () ->
      let t = parse (doc [ "# One"; ""; "## Two"; ""; "text"; "" ]) in
      toc t = [ (1, "One", "one"); (2, "Two", "two") ] && anchors t = [ "one"; "two" ]);
  check "N9 HW.2.7.1 a field list at the head of a DIRECTIVE body is that block's \
         options — block-scoped, never document metadata" (fun () ->
      let t = parse (doc [ ".. only:: html"; "   :hidden: yes"; ""; "   content"; ""; "tail"; "" ]) in
      t.docinfo = []
      && match directives t with
         | [ d ] -> d.fields = [ ("hidden", "yes") ] && d.body = [ "content" ]
         | [] | _ :: _ -> false);
  check "N10 the INTEGRATION TIE: a seealso's edges are a subset of the page's outlinks \
         (one extraction, mirrored — they cannot drift)" (fun () ->
      let m =
        Hermes_wiki.build
          [ ("docs/x/host.md", "# Host\n\n.. seealso::\n\n   [[alpha]]\n");
            ("docs/x/alpha.md", "# Alpha\n\nbody.\n") ]
      in
      match Hermes_wiki.page m "host" with
      | Some p ->
          let e = edges ~source:p.Hermes_wiki.slug (parse p.Hermes_wiki.raw) in
          e <> [] && List.for_all (fun (_, tgt) -> List.mem tgt p.Hermes_wiki.outlinks) e
      | None -> false);
  check "N11 an unknown name is Unknown, a known one is not — the vocabulary is closed" (fun () ->
      kind_of_name "SeeAlso" = Seealso
      && kind_of_name "moduleauthor" = Authorship "moduleauthor"
      && kind_of_name "seelaso" = Unknown "seelaso"
      && kind_name (Unknown "seelaso") = "seelaso"
      && kind_name Productionlist = "productionlist")

(* --------------------------------------------------------- exhaustion *)

let () =
  check "X1 a large document parses, round-trips and stays total" (fun () ->
      let big =
        doc (List.concat (List.init 500 (fun i ->
                 [ Printf.sprintf "## Section %d" i; ""; ".. rubric:: R"; ""; "prose"; "" ])))
      in
      let t = parse big in
      source_lines t = String.split_on_char '\n' big
      && List.length (toc t) = 500
      && List.length (rubrics t) = 500);
  check "X2 DEEP nesting of conditionals terminates and recurses" (fun () ->
      let rec nest k =
        if k = 0 then [ "# Deep" ]
        else ".. only:: html" :: "" :: List.map (fun l -> "   " ^ l) (nest (k - 1))
      in
      let t0 = parse (doc (nest 12)) in
      let kept = select ~declared:[ "html" ] ~active:[ "html" ] t0 in
      let dropped = select ~declared:[ "html" ] ~active:[] t0 in
      anchors kept = [ "deep" ] && anchors dropped = [] && excluded_lines dropped > 0);
  check "X3 WIDE fan-out: 200 see-also entries all become edges" (fun () ->
      let entries = List.init 200 (fun i -> Printf.sprintf "   - [[note-%03d]]" i) in
      let t = parse (doc ((".. seealso::" :: "" :: entries) @ [ "" ])) in
      List.length (edges ~source:"h" t) = 200)

(* -------------------------------------------------------------- stuck *)

let () =
  check "S1 a rubric written BARE is a diagnostic, and is still preserved" (fun () ->
      let src = doc [ ".. rubric::"; ""; "x"; "" ] in
      let t = parse src in
      has_diag t (Missing_argument "rubric")
      && rubrics t = [ "" ]
      && source_lines t = String.split_on_char '\n' src);
  check "S2 an EMPTY condition is undecidable: excluded, counted, diagnosed, never raised"
    (fun () ->
      let t = select ~declared:[ "html" ] ~active:[ "html" ]
                (parse (doc [ ".. only::"; ""; "   # Hidden"; ""; "tail"; "" ])) in
      has_diag t (Malformed_condition "")
      && anchors t = [] && excluded_lines t = 3
      && List.length t.excluded = 1);
  check "S2b a MALFORMED condition gets the same clamp" (fun () ->
      let t = select ~declared:[ "html" ] ~active:[ "html" ]
                (parse (doc [ ".. only:: html and"; ""; "   # Hidden"; ""; "tail"; "" ])) in
      has_diag t (Malformed_condition "html and") && anchors t = [] && excluded_lines t > 0);
  check "S3 HW.2.6.1's dual: a see-also that LINKS NOWHERE is decoration, and is named"
    (fun () ->
      let t = parse (doc [ ".. seealso::"; ""; "   just prose, no reference at all."; "" ]) in
      edges ~source:"h" t = []
      && has_diag t (Decorative_seealso "just prose, no reference at all."));
  check "S4 HW.2.6.4 refs(g) subset defs(g): a reference with no definition is reported"
    (fun () ->
      let t =
        parse (doc [ ".. productionlist:: expr"; "   sum: `term` \"+\" `factor`"; "   term: N"; "" ])
      in
      undefined_productions t = [ ("expr", "factor") ]
      && has_diag t (Undefined_production ("expr", "factor")));
  check "S4b resolution is PER GRAMMAR — a definition in another grammar does not satisfy it"
    (fun () ->
      let t =
        parse
          (doc
             [ ".. productionlist:: a"; "   x: `y`"; ""; ".. productionlist:: b"; "   y: Z"; "" ])
      in
      undefined_productions t = [ ("a", "y") ]);
  check "S4c blocks SHARING an argument are ONE grammar (Sphinx continuation)" (fun () ->
      let t =
        parse
          (doc
             [ ".. productionlist:: g"; "   x: `y`"; ""; ".. productionlist:: g"; "   y: Z"; "" ])
      in
      undefined_productions t = [] && List.length (productions t) = 2);
  check "S5 an UNTERMINATED directive body clamps to end of input" (fun () ->
      let src = doc [ ".. seealso::"; ""; "   [[alpha]]" ] in
      let t = parse src in
      edges ~source:"h" t = [ ("h", "alpha") ]
      && source_lines t = String.split_on_char '\n' src);
  check "S6 an UNTERMINATED fence stays inert to end of input" (fun () ->
      let src = doc [ "```"; ".. rubric:: X" ] in
      let t = parse src in
      directives t = [] && rubrics t = [] && source_lines t = String.split_on_char '\n' src)

(* ------------------------------------------------------------ anomaly *)

let () =
  check "A1 an UNKNOWN directive is preserved VERBATIM and RECORDED, never dropped" (fun () ->
      let src = doc [ ".. sidebar:: Notes"; ""; "   held content"; ""; "tail"; "" ] in
      let t = parse src in
      kinds t = [ Unknown "sidebar" ]
      && has_diag t (Unknown_directive "sidebar")
      && (match directives t with
          | [ d ] -> d.source = [ ".. sidebar:: Notes"; ""; "   held content" ]
          | [] | _ :: _ -> false)
      && source_lines t = String.split_on_char '\n' src);
  check "A2 CODE IS NOT PROSE: a directive inside a code FENCE is an example, not a use"
    (fun () ->
      (* the same confusion reported 25 phantom embeds in a corpus with none *)
      let t = parse (doc [ "# H"; ""; "```"; ".. seealso::"; ""; "   [[alpha]]"; "```"; "" ]) in
      directives t = [] && edges ~source:"h" t = [] && t.diagnostics = []);
  check "A2b a directive inside INLINE BACKTICKS is an example too" (fun () ->
      let t = parse (doc [ "write `.. rubric:: X` to label a block"; ""; "`.. seealso::` links"; "" ]) in
      directives t = [] && rubrics t = [] && t.diagnostics = []);
  check "A2c an INDENTED copy is body text, not a second directive" (fun () ->
      let t = parse (doc [ ".. sidebar:: outer"; "   .. rubric:: inner"; ""; "tail"; "" ]) in
      kinds t = [ Unknown "sidebar" ] && rubrics t = []);
  check "A3 HW.2.7.1 a docinfo field the FRONTMATTER already declares is a diagnostic \
         — two answers to one question, and the module refuses to pick" (fun () ->
      let t = parse ~frontmatter:[ "author" ] (doc [ ":author: Ada"; ""; "body"; "" ]) in
      has_diag t (Docinfo_conflict "author"));
  check "A3b the conflict is found against a LEADING frontmatter block too" (fun () ->
      let t = parse (doc [ "---"; "author: Bob"; "---"; ":author: Ada"; ""; "body"; "" ]) in
      has_diag t (Docinfo_conflict "author") && t.docinfo = [ ("author", "Ada") ]);
  check "A4 HW.2.7.1 docinfo is METADATA and does NOT also render as body text \
         (double-rendering is the failure to forbid)" (fun () ->
      let src = doc [ ":author: Ada"; ":status: draft"; ""; "# H"; ""; "prose"; "" ] in
      let t = parse src in
      t.docinfo <> []
      && (not (List.exists (fun l -> contains l ":author:") (body_lines t)))
      && (not (List.exists (fun l -> contains l ":status:") (body_lines t)))
      (* moved, not lost *)
      && t.docinfo_source = [ ":author: Ada"; ":status: draft" ]
      && source_lines t = String.split_on_char '\n' src);
  check "A4b a field list that is NOT document-leading stays body text — docinfo is \
         block-scoped, so a mid-document field is prose" (fun () ->
      let t = parse (doc [ "# H"; ""; ":author: Ada"; ""; "prose"; "" ]) in
      t.docinfo = [] && List.exists (fun l -> contains l ":author:") (body_lines t));
  check "A4c an RST inline ROLE at line start is not a field (`:doc:` needs no space)" (fun () ->
      let t = parse (doc [ ":doc:`parity`"; ""; "body"; "" ]) in
      t.docinfo = [] && List.mem ":doc:`parity`" (body_lines t));
  check "A5 HW.2.6.2 THE NEGATIVE LAW: a rubric enters NEITHER the toc NOR the anchors \
         — even when its title is identical to a real heading's" (fun () ->
      let t = parse (doc [ "# Overview"; ""; ".. rubric:: Overview"; ""; "prose"; "" ]) in
      rubrics t = [ "Overview" ]
      && toc t = [ (1, "Overview", "overview") ]
      && anchors t = [ "overview" ]
      && List.length (anchors t) = 1);
  check "A6 HW.2.6.5 an UNDECLARED tag fails CLOSED: false, excluded, counted, diagnosed"
    (fun () ->
      let t = select ~declared:[ "html" ] ~active:[ "html" ]
                (parse (doc [ ".. only:: latex"; ""; "   # Ghost"; ""; "tail"; "" ])) in
      has_diag t (Undeclared_tag "latex")
      && anchors t = []
      && excluded_lines t = 3
      && List.length t.excluded = 1);
  check "A7 HW.2.6.5 ANCHORS ARE COMPUTED PER BUILD: one parse, two tag sets, two \
         different anchor sets" (fun () ->
      let t0 = parse (doc [ ".. only:: html"; ""; "   # Web"; ""; "# Always"; "" ]) in
      let web = select ~declared:[ "html"; "pdf" ] ~active:[ "html" ] t0 in
      let print = select ~declared:[ "html"; "pdf" ] ~active:[ "pdf" ] t0 in
      anchors web = [ "web"; "always" ]
      && anchors print = [ "always" ]
      && anchors web <> anchors print);
  check "A8 HW.2.6.8 authorship is PRESENTATIONAL ONLY: no edge, no anchor, no toc \
         entry, no metadata — not even when its argument looks like a wikilink" (fun () ->
      (* the argument AND an indented body both name a page; neither may
         become an edge, or a byline would be indistinguishable from the
         page's subject matter *)
      let t =
        parse
          (doc
             [ "# H"; "";
               ".. sectionauthor:: [[alpha]] Ada";
               "   also [[beta]]"; "";
               ".. rubric:: [[gamma]]"; "";
               "prose"; "" ])
      in
      authorship t = [ ("sectionauthor", "[[alpha]] Ada") ]
      && edges ~source:"h" t = []
      && anchors t = [ "h" ]
      && toc t = [ (1, "H", "h") ]
      && t.docinfo = []);
  check "A9 NOTHING VANISHES WITHOUT A RECEIPT: every withheld line is in [excluded], \
         verbatim, with the expression that withheld it" (fun () ->
      let t = select ~declared:[ "html"; "draft" ] ~active:[ "html" ]
                (parse (doc [ ".. only:: draft"; ""; "   secret line"; ""; "public"; "" ])) in
      List.exists (fun l -> contains l "public") (body_lines t)
      && (not (List.exists (fun l -> contains l "secret") (body_lines t)))
      && t.excluded = [ ("draft", [ ".. only:: draft"; ""; "   secret line" ]) ]
      && excluded_lines t = 3);
  check "A10 conditionals NEST through select: an inner block excluded inside a kept outer \
         one is still counted" (fun () ->
      let t = select ~declared:[ "html"; "draft" ] ~active:[ "html" ]
                (parse (doc [ ".. only:: html"; "";
                              "   # Kept"; "";
                              "   .. only:: draft"; "";
                              "      # Inner"; ""; "tail"; "" ])) in
      anchors t = [ "kept" ] && excluded_lines t > 0 && List.length t.excluded = 1);
  check "A11 the expression grammar is Sphinx's: and / or / not / parentheses" (fun () ->
      let ev expr act =
        let t = select ~declared:[ "a"; "b"; "c" ] ~active:act
                  (parse (doc [ ".. only:: " ^ expr; ""; "   # Yes"; "" ])) in
        anchors t = [ "yes" ]
      in
      ev "a and b" [ "a"; "b" ]
      && (not (ev "a and b" [ "a" ]))
      && ev "a or b" [ "b" ]
      && ev "not c" [ "a" ]
      && ev "(a or b) and not c" [ "b" ]
      && not (ev "(a or b) and not c" [ "b"; "c" ]));
  check "A12 TOTAL over pathological input — clamps or preserves, never raises" (fun () ->
      List.for_all
        (fun s ->
          let t = parse s in
          let _ = select ~declared:[] ~active:[] t in
          let _ = edges ~source:"h" t and _ = productions t and _ = undefined_productions t in
          let _ = toc t and _ = rubrics t and _ = authorship t in
          source_lines t = String.split_on_char '\n' s)
        [ ""; "."; ".."; ".. "; ".. ::"; ".. ::x"; ":"; "::"; ":::"; ":a:";
          ".. only::"; ".. only:: ("; ".. only:: )"; ".. only:: not"; ".. only:: a b";
          ".. productionlist::"; ".. productionlist:: g\n   : nothing";
          ".. productionlist:: g\n   continued only";
          ".. seealso::\n   `unclosed";
          "---"; "---\n"; "---\nno close";
          "```"; "```\n"; "#"; "#######  deep"; String.make 2000 '.';
          String.make 500 '`'; "\n\n\n" ])

(* -------------------------------------------- P* the register probes

   The six `~derived` bodies for HW.2.6.1/2/4/5/8 and HW.2.7.1, VERBATIM
   as they go into feature_register.ml. They live here so they are
   compiled and run on every build: a register probe that rots is a row
   that claims evidence it no longer has. Fully qualified — they must
   not depend on this file's `open`. *)

let () =
  check "P1 HW.2.6.1 probe (seealso — entries are graph edges)" (fun () ->
      try
        let m =
          Hermes_wiki.build
            [ ("docs/x/host.md", "# Host\n\n.. seealso::\n\n   [[alpha]] and [[beta#Deep]]\n");
              ("docs/x/alpha.md", "# Alpha\n\nb.\n"); ("docs/x/beta.md", "# Beta\n\nb.\n") ]
        in
        match Hermes_wiki.page m "host" with
        | Some p ->
            let e = Wiki_directive.edges ~source:"host" (Wiki_directive.parse p.Hermes_wiki.raw) in
            (* EDGES, not decoration: extractable pairs, and a subset of
               the page's own outlinks — one extraction, mirrored *)
            e = [ ("host", "alpha"); ("host", "beta") ]
            && List.for_all (fun (_, g) -> List.mem g p.Hermes_wiki.outlinks) e
            && (Wiki_directive.parse ".. seealso::\n\n   prose only\n")
                 .Wiki_directive.diagnostics
               = [ Wiki_directive.Decorative_seealso "prose only" ]
        | None -> false
      with _ -> false);
  check "P2 HW.2.6.2 probe (rubric — does not enter toc or anchors)" (fun () ->
      try
        let t = Wiki_directive.parse "# Overview\n\n.. rubric:: Overview\n\nprose\n" in
        (* the NEGATIVE law: the rubric's title is IDENTICAL to the
           heading's, and still exactly one anchor exists *)
        Wiki_directive.rubrics t = [ "Overview" ]
        && Wiki_directive.anchors t = [ "overview" ]
        && Wiki_directive.toc t = [ (1, "Overview", "overview") ]
      with _ -> false);
  check "P3 HW.2.6.4 probe (productionlist — refs(g) subset defs(g))" (fun () ->
      try
        let g s = Wiki_directive.parse (".. productionlist:: expr\n" ^ s) in
        let ok = g "   sum: `term` \"+\" `sum`\n   term: N\n" in
        let bad = g "   sum: `term` \"+\" `factor`\n   term: N\n" in
        List.map (fun p -> p.Wiki_directive.pname) (Wiki_directive.productions ok)
        = [ "sum"; "term" ]
        && Wiki_directive.undefined_productions ok = []
        && Wiki_directive.undefined_productions bad = [ ("expr", "factor") ]
        (* PER GRAMMAR: another grammar's definition does not satisfy it *)
        && Wiki_directive.undefined_productions
             (Wiki_directive.parse
                ".. productionlist:: a\n   x: `y`\n\n.. productionlist:: b\n   y: Z\n")
           = [ ("a", "y") ]
      with _ -> false);
  check "P4 HW.2.6.5 probe (only — anchors computed per build)" (fun () ->
      try
        let t = Wiki_directive.parse ".. only:: html\n\n   # Web\n\n# Always\n" in
        let sel a = Wiki_directive.select ~declared:[ "html"; "pdf" ] ~active:a t in
        let web = sel [ "html" ] and pdf = sel [ "pdf" ] in
        (* the tag set is DECLARED and passed in, never inferred *)
        Wiki_directive.anchors web = [ "web"; "always" ]
        && Wiki_directive.anchors pdf = [ "always" ]
        (* and what it withheld is COUNTABLE — never invisible loss *)
        && Wiki_directive.excluded_lines pdf = 3
        && Wiki_directive.excluded_lines web = 0
        && (let u = Wiki_directive.select ~declared:[] ~active:[] t in
            List.mem (Wiki_directive.Undeclared_tag "html") u.Wiki_directive.diagnostics)
      with _ -> false);
  check "P5 HW.2.6.8 probe (authorship — presentational only)" (fun () ->
      try
        let t =
          Wiki_directive.parse
            "# H\n\n.. sectionauthor:: [[alpha]] Ada\n   also [[beta]]\n\nprose\n"
        in
        (* a BYLINE: printable, and structurally inert — no edge from a
           name that happens to be spelled like a link *)
        Wiki_directive.authorship t = [ ("sectionauthor", "[[alpha]] Ada") ]
        && Wiki_directive.edges ~source:"h" t = []
        && Wiki_directive.anchors t = [ "h" ]
        && t.Wiki_directive.docinfo = []
        && t.Wiki_directive.diagnostics = []
      with _ -> false);
  check "P6 HW.2.7.1 probe (field lists / docinfo — block-scoped, conflict is a diagnostic)"
    (fun () ->
      try
        let src = ":author: Ada\n:version: 3\n\n# H\n\n.. only:: html\n   :hidden: yes\n\n   body\n" in
        let t = Wiki_directive.parse ~frontmatter:[ "author" ] src in
        (* METADATA, so it must not ALSO render as body text *)
        t.Wiki_directive.docinfo = [ ("author", "Ada"); ("version", "3") ]
        && (not
              (List.exists
                 (function
                   | Wiki_directive.Text ls -> List.mem ":author: Ada" ls
                   | Wiki_directive.Heading _ | Wiki_directive.Fenced _ | Wiki_directive.Block _ ->
                       false)
                 t.Wiki_directive.nodes))
        (* moved, never lost *)
        && Wiki_directive.source_lines t = String.split_on_char '\n' src
        (* BLOCK-SCOPED: a directive's options are not document metadata *)
        && List.map (fun d -> d.Wiki_directive.fields) (Wiki_directive.directives t)
           = [ [ ("hidden", "yes") ] ]
        && t.Wiki_directive.diagnostics = [ Wiki_directive.Docinfo_conflict "author" ]
      with _ -> false)

let () =
  Printf.printf "wiki_directive: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_directive" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_directive ]);
  exit (Wiki_suite_telemetry.exit_code self)
