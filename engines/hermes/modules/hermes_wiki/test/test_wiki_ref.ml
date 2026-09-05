(* HW.3.7.1 typed cross-reference roles — the law `kind(resolve_k(x)) = k`
   (mirror: zigvm note_ref.ml; the role semantics are Sphinx §5.3).

   Laws:
     G*  the ONE payload grammar (closed role set, ! opt-out, total)
     R*  kind-scoped resolution — wrong kind is a FAILURE, not a fallback
     E*  the engine surface: render + outlinks observe the same grammar *)

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

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

open Wiki_ref

(* ------------------------------------------------------------ grammar *)

let () =
  check "G1 untyped payload is an Any reference" (fun () ->
      parse "X" = { kind = Any; target = "X"; display = None; rel = None; suppress = false });
  check "G2 doc: role" (fun () ->
      let r = parse "doc:Evidence store" in
      r.kind = Doc && r.target = "Evidence store" && not r.suppress);
  check "G3 term: role" (fun () ->
      let r = parse "term:parity" in
      r.kind = Term && r.target = "parity");
  check "G4 role set is CLOSED: unknown prefix is a plain target" (fun () ->
      let r = parse "re: subject" in
      r.kind = Any && r.target = "re: subject");
  check "G5 ! suppresses (HW.3.7.6)" (fun () ->
      let r = parse "!X" in
      r.suppress && r.kind = Any && r.target = "X");
  check "G6 ! composes with a role" (fun () ->
      let r = parse "!term:parity" in
      r.suppress && r.kind = Term && r.target = "parity");
  check "G7 display alias kept by the grammar" (fun () ->
      (parse "doc:X|shown").display = Some "shown");
  check "G8 @rel is the discourse dimension, exactly as before" (fun () ->
      let r = parse "X|@supports" in
      r.rel = Some "supports" && r.display = None);
  check "G9 fragment stays inside the target" (fun () ->
      let r = parse "doc:X#sec-one" in
      r.kind = Doc && r.target = "X#sec-one");
  check "G10 a role with an empty target is not a role" (fun () ->
      let r = parse "term:" in
      r.kind = Any && r.target = "term:");
  check "G11 trim matches split_payload exactly" (fun () ->
      (parse "  X  ").target = "X" && (parse " doc: X ").target = "X");
  check "G12 round-trip on canonical forms" (fun () ->
      to_wiki (parse "doc:X|shown") = "[[doc:X|shown]]"
      && to_wiki (parse "X") = "[[X]]"
      && to_wiki (parse "!term:parity") = "[[!term:parity]]"
      && to_wiki (parse "X|@supports") = "[[X|@supports]]");
  check "G13 role prefixes are lowercase-only (closed set)" (fun () ->
      let r = parse "Doc:X" in
      r.kind = Any && r.target = "Doc:X");
  check "G14 a bare ! is a plain target" (fun () ->
      let r = parse "!" in
      (not r.suppress) && r.target = "!");
  check "G15 rest-after-| that is not @rel never becomes rel (split_payload compat)"
    (fun () ->
      let r = parse "X| @rel" in
      r.rel = None && r.display = Some " @rel")

(* --------------------------------------------------------- resolution *)

let sp =
  {
    docs =
      [ ("parity", "parity-doc"); ("the-gate", "gate03"); ("gate03", "gate03") ];
    terms = [ ("parity", ("glossary", "parity")) ];
  }

let () =
  check "R1 KIND LAW: kind(resolve_k(x)) = k, both kinds" (fun () ->
      List.for_all (fun c -> c.ckind = Doc) (resolve sp Doc "parity")
      && List.for_all (fun c -> c.ckind = Term) (resolve sp Term "parity")
      && resolve sp Doc "parity" <> []
      && resolve sp Term "parity" <> []);
  check "R2 wrong kind is a FAILURE, not a fallback" (fun () ->
      (* the-gate is a doc; as a term it must NOT resolve *)
      resolve sp Term "the-gate" = []);
  check "R3 doc candidates dedup by slug across resolver keys" (fun () ->
      match (resolve sp Doc "the-gate", resolve sp Doc "gate03") with
      | [ a ], [ b ] -> a.cslug = "gate03" && b.cslug = "gate03"
      | _ -> false);
  check "R4 Any is the union across kinds — one name in two spaces = TWO candidates"
    (fun () ->
      match resolve sp Any "parity" with
      | [ a; b ] -> a.ckind = Doc && b.ckind = Term && b.canchor = Some "parity"
      | _ -> false);
  check "R5 unknown key resolves to nothing in every kind" (fun () ->
      resolve sp Doc "nope" = [] && resolve sp Term "nope" = [] && resolve sp Any "nope" = [])

(* ----------------------------------------------------- engine surface *)

let fixture body = [ ("docs/hermes/zk/probe-a.md", body); ("docs/hermes/zk/probe-b.md", "# Probe B\n\nplain.\n") ]

let page_a body =
  let m = Hermes_wiki.build (fixture body) in
  match Hermes_wiki.page m "probe-a" with Some p -> p | None -> failwith "probe-a missing"

let () =
  check "E1 [[doc:probe-b]] renders as a LINK, role stripped from the text" (fun () ->
      let p = page_a "# Probe A\n\nSee [[doc:probe-b]].\n" in
      contains p.html "<a href=\"probe-b.html\" class=\"wikilink\">probe-b</a>");
  check "E2 kind law at the render surface: term:probe-b does NOT resolve to the doc"
    (fun () ->
      let p = page_a "# Probe A\n\nSee [[term:probe-b]].\n" in
      contains p.html "<span class=\"missing\">probe-b</span>"
      && not (contains p.html "href=\"probe-b.html\""));
  check "E3 [[!probe-b]] renders as PLAIN TEXT — no link, no missing-span" (fun () ->
      let p = page_a "# Probe A\n\nAbout [[!probe-b]] only.\n" in
      contains p.html "About probe-b only."
      && (not (contains p.html "<span class=\"missing\">probe-b"))
      && not (contains p.html "href=\"probe-b.html\""));
  check "E4 !r => r not in outlinks (HW.3.7.6 model law)" (fun () ->
      let p = page_a "# Probe A\n\nAbout [[!probe-b]] only.\n" in
      not (List.mem "probe-b" p.outlinks));
  check "E5 typed doc reference IS an outlink edge" (fun () ->
      let p = page_a "# Probe A\n\nSee [[doc:probe-b]].\n" in
      List.mem "probe-b" p.outlinks);
  check "E6 untyped path is byte-unchanged (the pinned-baseline guard)" (fun () ->
      let p = page_a "# Probe A\n\nSee [[probe-b]].\n" in
      contains p.html "<a href=\"probe-b.html\" class=\"wikilink\">probe-b</a>"
      && List.mem "probe-b" p.outlinks)

(* ------------------------------------- HW.3.7.2 ambiguity as an error *)

let build = Hermes_wiki.build

let () =
  check "A1 identity-tier contest is AMBIGUOUS at the use site, both candidates named"
    (fun () ->
      (* two pages titled "The Gate" (distinct slugs after collision
         disambiguation), a third referencing the shared title key *)
      let m =
        build
          [ ("docs/a/gate-one.md", "# The Gate\n\nbody.\n");
            ("docs/b/gate-two.md", "# The Gate\n\nbody.\n");
            ("docs/c/user.md", "# User\n\nSee [[The Gate]].\n") ]
      in
      match Hermes_wiki.ambiguous_refs m with
      | [ line ] ->
          contains line "the-gate" && contains line "user"
          && contains line "gate-one" && contains line "gate-two"
      | _ -> false);
  check "A2 identity + alias on one key is RESOLVED, not ambiguous (HW.1.2.7)"
    (fun () ->
      let m =
        build
          [ ("docs/a/gate.md", "# The Gate\n\nbody.\n");
            ( "docs/b/other.md",
              "---\naliases: [The Gate]\n---\n# Other\n\nbody.\n" );
            ("docs/c/user.md", "# User\n\nSee [[The Gate]].\n") ]
      in
      Hermes_wiki.ambiguous_refs m = []);
  check "A3 two aliases with NO identity claim are ambiguous" (fun () ->
      let m =
        build
          [ ("docs/a/one.md", "---\naliases: [shadow]\n---\n# One\n\nbody.\n");
            ("docs/b/two.md", "---\naliases: [shadow]\n---\n# Two\n\nbody.\n");
            ("docs/c/user.md", "# User\n\nSee [[shadow]].\n") ]
      in
      match Hermes_wiki.ambiguous_refs m with
      | [ line ] -> contains line "shadow" && contains line "one" && contains line "two"
      | _ -> false);
  check "A4 a DEAD reference is not ambiguous — 0 and >1 are distinct verdicts"
    (fun () ->
      let m = build [ ("docs/c/user.md", "# User\n\nSee [[nowhere]].\n") ] in
      Hermes_wiki.ambiguous_refs m = []);
  check "A5 allow_example_links exempts the QUOTING page" (fun () ->
      let m =
        build
          [ ("docs/a/gate-one.md", "# The Gate\n\nbody.\n");
            ("docs/b/gate-two.md", "# The Gate\n\nbody.\n");
            ( "docs/c/spec.md",
              "---\nallow_example_links: true\n---\n# Spec\n\nQuoting [[The Gate]].\n" ) ]
      in
      Hermes_wiki.ambiguous_refs m = []);
  check "A6 a !suppressed reference is never reported ambiguous" (fun () ->
      let m =
        build
          [ ("docs/a/gate-one.md", "# The Gate\n\nbody.\n");
            ("docs/b/gate-two.md", "# The Gate\n\nbody.\n");
            ("docs/c/user.md", "# User\n\nAbout [[!The Gate]] only.\n") ]
      in
      Hermes_wiki.ambiguous_refs m = []);
  check "A8 an ARCHIVED page never contests a living identity key" (fun () ->
      (* the live note and its legacy-archive copy share a name; the
         archive is a weaker claim (HW.1.2.7's tier algebra), so the
         reference is RESOLVED to the living page by construction *)
      let m =
        build
          [ ("docs/a/note.md", "# The Rule\n\nbody.\n");
            ( "docs/legacy/archive-note.md",
              "---\nmaturity: archived\n---\n# The Rule\n\nold copy.\n" );
            ("docs/c/user.md", "# User\n\nSee [[The Rule]].\n") ]
      in
      Hermes_wiki.ambiguous_refs m = []);
  check "A8b two LIVING claimants still contest even when a third is archived"
    (fun () ->
      let m =
        build
          [ ("docs/a/rule-one.md", "# The Rule\n\nbody.\n");
            ("docs/b/rule-two.md", "# The Rule\n\nbody.\n");
            ( "docs/legacy/archive-note.md",
              "---\nmaturity: archived\n---\n# The Rule\n\nold copy.\n" );
            ("docs/c/user.md", "# User\n\nSee [[The Rule]].\n") ]
      in
      match Hermes_wiki.ambiguous_refs m with
      | [ line ] ->
          contains line "rule-one" && contains line "rule-two"
          && not (contains line "archive-note")
      | _ -> false);
  check "A7 output is deterministic and sorted" (fun () ->
      let m =
        build
          [ ("docs/a/gate-one.md", "# The Gate\n\nbody.\n");
            ("docs/b/gate-two.md", "# The Gate\n\nbody.\n");
            ("docs/c/zeta.md", "# Zeta\n\nSee [[The Gate]].\n");
            ("docs/c/alpha.md", "# Alpha\n\nSee [[The Gate]].\n") ]
      in
      let lines = Hermes_wiki.ambiguous_refs m in
      List.length lines = 2 && lines = List.sort compare lines)

(* ---------------------- HW.3.7.3 nitpicky mode + HW.3.7.6 disclosure *)

let () =
  check "N1 an unresolved doc reference FAILS (is counted)" (fun () ->
      let m = build [ ("docs/c/user.md", "# User\n\nSee [[nowhere]].\n") ] in
      match Hermes_wiki.unresolved_refs m with
      | [ line ] -> contains line "nowhere" && contains line "user"
      | _ -> false);
  check "N2 ! is the per-reference opt-out: never unresolved, always DISCLOSED"
    (fun () ->
      let m = build [ ("docs/c/user.md", "# User\n\nAbout [[!nowhere]].\n") ] in
      Hermes_wiki.unresolved_refs m = []
      &&
      match Hermes_wiki.suppressed_refs m with
      | [ line ] -> contains line "nowhere" && contains line "user"
      | _ -> false);
  check "N3 resolving references and exempt pages are silent" (fun () ->
      let m =
        build
          [ ("docs/a/probe-b.md", "# Probe B\n\nplain.\n");
            ("docs/c/user.md", "# User\n\nSee [[probe-b]].\n");
            ( "docs/d/spec.md",
              "---\nallow_example_links: true\n---\n# Spec\n\nQuote [[nowhere]].\n" ) ]
      in
      Hermes_wiki.unresolved_refs m = []);
  check "N4 verdicts stay separate: term refs and dead fragments are NOT unresolved docs"
    (fun () ->
      let m =
        build
          [ ("docs/a/probe-b.md", "# Probe B\n\nplain.\n");
            ( "docs/c/user.md",
              "# User\n\nSee [[term:nowhere]] and [[probe-b#nope]] and [[gone#frag]].\n" ) ]
      in
      (* term:nowhere -> HW.3.7.4's diag; probe-b#nope -> broken_anchors;
         gone#frag -> THIS verdict (the document itself is dead) *)
      match Hermes_wiki.unresolved_refs m with
      | [ line ] -> contains line "gone" && not (contains line "probe-b")
      | _ -> false);
  check "N5 an archived-only target still RESOLVES (weaker tier, not dead)" (fun () ->
      let m =
        build
          [ ( "docs/legacy/old-note.md",
              "---\nmaturity: archived\n---\n# Old Note\n\nold.\n" );
            ("docs/c/user.md", "# User\n\nSee [[Old Note]].\n") ]
      in
      Hermes_wiki.unresolved_refs m = [])

(* ------------------- code is not prose (note_ref mask_code, mirrored) *)

let () =
  check "C1 a backticked [[link]] is CODE: no payload, no edge, no verdict" (fun () ->
      let m = build [ ("docs/c/user.md", "# User\n\nThe `[[nowhere]]` form.\n") ] in
      Hermes_wiki.unresolved_refs m = []
      &&
      match Hermes_wiki.page m "user" with
      | Some p -> not (List.mem "nowhere" p.Hermes_wiki.outlinks)
      | None -> false);
  check "C2 a fenced [[link]] stays inert (the fence walk, unchanged)" (fun () ->
      let m = build [ ("docs/c/user.md", "# User\n\n```\n[[nowhere]]\n```\n") ] in
      Hermes_wiki.unresolved_refs m = []);
  check "C3 a real link beside a backticked example: only the real one is an edge"
    (fun () ->
      let m =
        build
          [ ("docs/a/probe-b.md", "# Probe B\n\nplain.\n");
            ("docs/c/user.md", "# User\n\nSee [[probe-b]] and the `[[nowhere]]` form.\n") ]
      in
      Hermes_wiki.unresolved_refs m = []
      &&
      match Hermes_wiki.page m "user" with
      | Some p ->
          List.mem "probe-b" p.Hermes_wiki.outlinks
          && not (List.mem "nowhere" p.Hermes_wiki.outlinks)
      | None -> false);
  check "C5 the RENDERER agrees: a backticked [[link]] stays literal inside <code>"
    (fun () ->
      let m =
        build
          [ ("docs/a/probe-b.md", "# Probe B\n\nplain.\n");
            ("docs/c/user.md", "# User\n\nThe `[[probe-b]]` form.\n") ]
      in
      match Hermes_wiki.page m "user" with
      | Some p ->
          contains p.Hermes_wiki.html "<code>[[probe-b]]</code>"
          && not (contains p.Hermes_wiki.html "href=\"probe-b.html\"")
      | None -> false);
  check "C4 HONEST LIMIT (recorded): a span crossing a line break still leaks"
    (fun () ->
      (* note_ref's documented bound — per-line pairing contains damage to
         one line; a multi-line span leaks its content. Pinned so the
         limit stays REAL rather than assumed away. *)
      let m =
        build
          [ ( "docs/c/user.md",
              "# User\n\nstart `code [[nowhere]]\nend` of the span.\n" ) ]
      in
      match Hermes_wiki.unresolved_refs m with
      | [ line ] -> contains line "nowhere"
      | _ -> false)

(* ----------------------------------- HW.3.7.4 glossary + [[term:x]] *)

let gloss_fixture =
  [ ( "docs/wiki/glossary.md",
      "---\ntopics: [glossary, vocabulary]\n---\n# Glossary\n\n\
       ## Parity\n\nByte-equality against the frozen reference.\n\n\
       ## Evidence Chain\n\nThe L0-L6 receipt lattice.\n" );
    ("docs/a/parity.md", "# Parity\n\nThe DOC named like the term.\n") ]

let () =
  check "T1 glossary pages define terms: one per level-2 heading, sorted" (fun () ->
      let m = build gloss_fixture in
      Hermes_wiki.glossary_terms m
      = [ ("evidence-chain", ("glossary", "evidence-chain"));
          ("parity", ("glossary", "parity")) ]);
  check "T2 a NON-glossary page's headings define nothing" (fun () ->
      let m = build [ ("docs/a/note.md", "# Note\n\n## Parity\n\nprose.\n") ] in
      Hermes_wiki.glossary_terms m = []);
  check "T3 [[term:parity]] renders as a link INTO the glossary, kind-scoped" (fun () ->
      let m =
        build (gloss_fixture @ [ ("docs/c/user.md", "# User\n\nSee [[term:parity]].\n") ])
      in
      match Hermes_wiki.page m "user" with
      | Some p ->
          contains p.Hermes_wiki.html
            "<a href=\"glossary.html#parity\" class=\"wikilink\">parity</a>"
      | None -> false);
  check "T4 term used and undefined => diag; defined => silent" (fun () ->
      let m =
        build
          (gloss_fixture
          @ [ ("docs/c/user.md", "# User\n\nSee [[term:parity]] and [[term:quirk]].\n") ])
      in
      match Hermes_wiki.term_gaps m with
      | [ line ] -> contains line "quirk" && contains line "user" && not (contains line "parity")
      | _ -> false);
  check "T5 kind separation holds under a live glossary: a term gap is NOT an unresolved doc"
    (fun () ->
      let m =
        build (gloss_fixture @ [ ("docs/c/user.md", "# User\n\nSee [[term:quirk]].\n") ])
      in
      Hermes_wiki.unresolved_refs m = [] && List.length (Hermes_wiki.term_gaps m) = 1);
  check "T6 !term composes: suppressed, disclosed, never a gap" (fun () ->
      let m =
        build (gloss_fixture @ [ ("docs/c/user.md", "# User\n\nAbout [[!term:quirk]].\n") ])
      in
      Hermes_wiki.term_gaps m = [] && List.length (Hermes_wiki.suppressed_refs m) = 1);
  check "T7 term keys normalize: [[term:Evidence Chain]] reaches evidence-chain" (fun () ->
      let m =
        build
          (gloss_fixture @ [ ("docs/c/user.md", "# User\n\nSee [[term:Evidence Chain]].\n") ])
      in
      (match Hermes_wiki.page m "user" with
      | Some p -> contains p.Hermes_wiki.html "glossary.html#evidence-chain"
      | None -> false)
      && Hermes_wiki.term_gaps m = [])

let () =
  check "T8 a non-glossary heading defines NOTHING, in render and in gaps alike"
    (fun () ->
      let m =
        build
          [ ("docs/a/note.md", "# Note\n\n## Quirk\n\nprose.\n");
            ("docs/c/user.md", "# User\n\nSee [[term:quirk]].\n") ]
      in
      (match Hermes_wiki.page m "user" with
      | Some p ->
          contains p.Hermes_wiki.html "<span class=\"missing\">quirk</span>"
          && not (contains p.Hermes_wiki.html "note.html#quirk")
      | None -> false)
      && List.length (Hermes_wiki.term_gaps m) = 1)

(* ------------------------------------ HW.2.7.2 default inline role *)

let () =
  check "D1 IDENTITY under Kind=code: absent default_role changes nothing" (fun () ->
      let m = build [ ("docs/c/user.md", "# User\n\nA `plain span` here.\n") ] in
      match Hermes_wiki.page m "user" with
      | Some p ->
          contains p.Hermes_wiki.html "<code>plain span</code>"
          && p.Hermes_wiki.outlinks = []
      | None -> false);
  check "D2 IDENTITY explicit: default_role: code is byte-identical" (fun () ->
      let body = "# User\n\nA `plain span` here.\n" in
      let with_role = "---\ndefault_role: code\n---\n" ^ body in
      let h m = match Hermes_wiki.page m "user" with Some p -> p.Hermes_wiki.html | None -> "" in
      h (build [ ("docs/c/user.md", body) ]) = h (build [ ("docs/c/user.md", with_role) ]));
  check "D3 default_role: any turns a resolving span into a CHECKED reference"
    (fun () ->
      let m =
        build
          [ ("docs/a/probe-b.md", "# Probe B\n\nplain.\n");
            ("docs/c/user.md", "---\ndefault_role: any\n---\n# User\n\nSee `probe-b` now.\n") ]
      in
      match Hermes_wiki.page m "user" with
      | Some p ->
          contains p.Hermes_wiki.html
            "<a href=\"probe-b.html\" class=\"wikilink\">probe-b</a>"
          && List.mem "probe-b" p.Hermes_wiki.outlinks
      | None -> false);
  check "D4 default_role: any makes an unresolved span FAIL like any reference"
    (fun () ->
      let m =
        build
          [ ("docs/c/user.md", "---\ndefault_role: any\n---\n# User\n\nSee `nowhere` now.\n") ]
      in
      (match Hermes_wiki.page m "user" with
      | Some p -> contains p.Hermes_wiki.html "<span class=\"missing\">nowhere</span>"
      | None -> false)
      && List.length (Hermes_wiki.unresolved_refs m) = 1);
  check "D5 the block layer dominates: fenced code is never a reference" (fun () ->
      let m =
        build
          [ ("docs/c/user.md",
             "---\ndefault_role: any\n---\n# User\n\n```\nnowhere\n```\n") ]
      in
      Hermes_wiki.unresolved_refs m = []);
  check "D6 explicit role dominates on a default_role page" (fun () ->
      let m =
        build
          [ ("docs/a/probe-b.md", "# Probe B\n\nplain.\n");
            ("docs/c/user.md",
             "---\ndefault_role: any\n---\n# User\n\nSee [[doc:probe-b]].\n") ]
      in
      match Hermes_wiki.page m "user" with
      | Some p -> contains p.Hermes_wiki.html "href=\"probe-b.html\""
      | None -> false)

(* ------------------------------------- HW.2.6.3 back-of-book index *)

let () =
  check "X1 an index entry addresses a LOCATION (page + nearest heading)" (fun () ->
      let m =
        build
          [ ( "docs/c/user.md",
              "# User\n\n## Deep Section\n\nprose.\n<!-- index: parity -->\nmore.\n" ) ]
      in
      Hermes_wiki.corpus_index m = [ ("parity", "", "user", "deep-section") ]);
  check "X2 the subterm form: authored at the point of relevance" (fun () ->
      let m =
        build
          [ ("docs/c/user.md", "# User\n\n<!-- index: parity; evidence for -->\nprose.\n") ]
      in
      Hermes_wiki.corpus_index m = [ ("parity", "evidence for", "user", "") ]);
  check "X3 a see-entry whose target EXISTS is legal and listed" (fun () ->
      let m =
        build
          [ ( "docs/c/user.md",
              "# User\n\n<!-- index: parity -->\n<!-- index: see: quirk -> parity -->\np.\n" ) ]
      in
      Hermes_wiki.index_violations m = []
      && List.mem ("quirk", "see: parity", "user", "") (Hermes_wiki.corpus_index m));
  check "X4 a see-target that exists NOWHERE is a violation" (fun () ->
      let m =
        build
          [ ("docs/c/user.md", "# User\n\n<!-- index: see: quirk -> nowhere -->\np.\n") ]
      in
      match Hermes_wiki.index_violations m with
      | [ line ] -> contains line "nowhere" && contains line "user"
      | _ -> false);
  check "X5 a fenced index comment is code, not an entry" (fun () ->
      let m =
        build [ ("docs/c/user.md", "# User\n\n```\n<!-- index: parity -->\n```\np.\n") ]
      in
      Hermes_wiki.corpus_index m = []);
  check "X6 the index is sorted and deduplicated" (fun () ->
      let m =
        build
          [ ("docs/c/zeta.md", "# Zeta\n\n<!-- index: zz -->\n<!-- index: aa -->\np.\n") ]
      in
      let ix = Hermes_wiki.corpus_index m in
      ix = List.sort compare ix && List.length ix = 2)

let () =
  Printf.printf "wiki_ref: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_wiki_ref" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.hermes_wiki_ref ]);
  exit (Wiki_suite_telemetry.exit_code self)
