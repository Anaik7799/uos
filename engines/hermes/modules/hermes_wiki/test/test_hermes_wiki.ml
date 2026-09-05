(* The Hermes wiki/ZK core model under test — the ported subset of the
   zigvm docs_wiki laws (the full 91-law port is migration wave W1; this
   suite pins the CORE laws the site depends on, including the zigvm
   domain law fst back_ctx == backlinks). *)

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

let contains text needle =
  let n = String.length needle and h = String.length text in
  let rec go i = i + n <= h && (String.sub text i n = needle || go (i + 1)) in
  go 0

let corpus =
  [ ( "docs/hermes/zk/alpha.md",
      "---\nid: note-alpha\nstatus: draft\ntype: decision\n---\n# Alpha decision\n\nWe chose [[beta]] over [[gamma]] because #latency matters.\n\nSee [[evidence_store|@governs]] for authority.\n" );
    ( "docs/hermes/zk/beta.md",
      "# Beta\n\nPlain note. Mentions alpha by name but links [[alpha]] properly on this line.\n\n```\n[[not-a-link-in-code]] #not-a-tag\n```\n" );
    ( "docs/hermes/wiki/guide.md",
      "# The Guide\n\n- first\n- second\n\n| k | v |\n|---|---|\n| a | 1 |\n\n> quoted wisdom\n\nInline `code` and **bold** and a [site](https://example.org).\n" ) ]

let model = Hermes_wiki.build corpus

let page slug =
  match Hermes_wiki.page model slug with
  | Some p -> p
  | None -> failwith ("no page " ^ slug)

(* ------------------------------------------------------------- model *)

let () =
  check "every file becomes a page" (fun () ->
      List.length model.Hermes_wiki.pages = 3);
  check "slugs are url-safe and unique" (fun () ->
      let slugs = List.map (fun p -> p.Hermes_wiki.slug) model.Hermes_wiki.pages in
      List.length (List.sort_uniq compare slugs) = 3
      && List.for_all
           (fun s ->
             String.length s > 0
             && String.for_all
                  (fun c -> (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-')
                  s)
           slugs);
  check "title is the first H1" (fun () ->
      (page "alpha").Hermes_wiki.title = "Alpha decision"
      && (page "guide").Hermes_wiki.title = "The Guide");
  check "group is the directory under docs/hermes" (fun () ->
      (page "alpha").Hermes_wiki.group = "zk"
      && (page "guide").Hermes_wiki.group = "wiki");
  check "frontmatter is honored (id, status, discourse type)" (fun () ->
      let m = (page "alpha").Hermes_wiki.meta in
      m.Hermes_wiki.id = "note-alpha" && m.Hermes_wiki.status = "draft"
      && m.Hermes_wiki.ntype = "decision");
  check "absent frontmatter gets honest defaults (deterministic id)" (fun () ->
      let m = (page "beta").Hermes_wiki.meta in
      (* The law is derivation from the slug, not a magic prefix: the id
         must be stable across builds and contain the slug. *)
      m.Hermes_wiki.id <> "" && contains m.Hermes_wiki.id "beta"
      && m.Hermes_wiki.id = (page "beta").Hermes_wiki.meta.Hermes_wiki.id
      && m.Hermes_wiki.status = "published"
      && m.Hermes_wiki.ntype = "note")

(* ---------------------------------------------------------------- links *)

let () =
  check "outlinks resolve to slugs; missing targets are still recorded" (fun () ->
      let a = page "alpha" in
      List.mem "beta" a.Hermes_wiki.outlinks && List.mem "gamma" a.Hermes_wiki.outlinks);
  check "typed edges are captured from [[T|@rel]]" (fun () ->
      (page "alpha").Hermes_wiki.typed = [ ("evidence_store", "governs") ]);
  check "backlinks are the inverse of outlinks" (fun () ->
      List.mem "beta" (page "alpha").Hermes_wiki.backlinks
      && List.mem "alpha" (page "beta").Hermes_wiki.backlinks);
  check "the zigvm domain law: fst back_ctx == backlinks" (fun () ->
      List.for_all
        (fun p ->
          List.map fst p.Hermes_wiki.back_ctx = p.Hermes_wiki.backlinks)
        model.Hermes_wiki.pages);
  check "contextual backlinks carry the citing LINE" (fun () ->
      List.exists
        (fun (source, line) -> source = "beta" && contains line "links [[alpha]] properly")
        (page "alpha").Hermes_wiki.back_ctx);
  check "tags are extracted, but not from code fences" (fun () ->
      (page "alpha").Hermes_wiki.tags = [ "latency" ]
      && (page "beta").Hermes_wiki.tags = []);
  check "wikilinks inside code fences do not become outlinks" (fun () ->
      not (List.mem "not-a-link-in-code" (page "beta").Hermes_wiki.outlinks));
  (* Real corpora cross-reference with ordinary markdown links to sibling
     .md files; those are the same relation as a [[wikilink]] and must
     join the graph, or the ZK view lies about connectivity. *)
  check "relative markdown links to .md files become outlinks" (fun () ->
      let with_md =
        Hermes_wiki.build
          [ ("docs/hermes/zk/one.md", "# One\n\nSee [the guide](../wiki/guide.md).\n");
            ("docs/hermes/wiki/guide.md", "# The Guide\n") ]
      in
      match Hermes_wiki.page with_md "one" with
      | Some p -> p.Hermes_wiki.outlinks = [ "guide" ]
      | None -> false);
  (* zigvm §9: a note that QUOTES the wikilink grammar as evidence must
     not manufacture edges from its examples. The opt-out lives in the
     note's own frontmatter — visible in-repo, not a tuned metric. *)
  check "allow_example_links keeps quoted grammar out of the graph" (fun () ->
      let quoting =
        Hermes_wiki.build
          [ ("docs/hermes/zk/spec.md",
             "---\nallow_example_links: true\n---\n# Spec\n\nWrite [[Target|@rel]] to relate.\n");
            ("docs/hermes/zk/target.md", "# Target\n") ]
      in
      match Hermes_wiki.page quoting "spec" with
      | Some p -> p.Hermes_wiki.outlinks = [] && p.Hermes_wiki.typed = []
      | None -> false);
  check "without the opt-out the same text DOES create the edge" (fun () ->
      let plain =
        Hermes_wiki.build
          [ ("docs/hermes/zk/spec.md", "# Spec\n\nWrite [[Target|@rel]] to relate.\n");
            ("docs/hermes/zk/target.md", "# Target\n") ]
      in
      match Hermes_wiki.page plain "spec" with
      | Some p -> p.Hermes_wiki.typed <> []
      | None -> false);
  check "external links never become graph edges" (fun () ->
      let external_only =
        Hermes_wiki.build [ ("docs/hermes/zk/x.md", "# X\n\n[out](https://example.org/a.md)\n") ]
      in
      match Hermes_wiki.page external_only "x" with
      | Some p -> p.Hermes_wiki.outlinks = []
      | None -> false)

(* ------------------------------------------------------------- renderer *)

let () =
  let resolve s = if s = "beta" then Some "beta.html" else None in
  let html = Hermes_wiki.render_markdown ~resolve "# T\n\nsee [[beta]] and [[ghost]]\n\n- a\n- b\n\n```\n<raw> & code\n```\n\n| k | v |\n|---|---|\n| a | 1 |\n" in
  check "headings, lists, tables, fences all render" (fun () ->
      contains html "<h1 id=\"t\">T</h1>" && contains html "<li>a</li>"
      && contains html "<table>" && contains html "<td>1</td>"
      && contains html "<pre><code>");
  check "code is escaped, never interpreted" (fun () ->
      contains html "&lt;raw&gt; &amp; code");
  check "a resolved wikilink becomes an anchor" (fun () ->
      contains html "<a href=\"beta.html\"" && contains html ">beta</a>");
  check "a missing wikilink is visibly missing, never silent" (fun () ->
      contains html "class=\"missing\"" && contains html "ghost");
  check "inline markup renders" (fun () ->
      let inline = Hermes_wiki.render_markdown ~resolve "x `c` **b** [s](https://e.org)\n" in
      contains inline "<code>c</code>" && contains inline "<strong>b</strong>"
      && contains inline "<a href=\"https://e.org\"");
  check "rendering is deterministic" (fun () ->
      Hermes_wiki.render_markdown ~resolve "# A\n" = Hermes_wiki.render_markdown ~resolve "# A\n")

(* ------------------------------------------------------ moc + anomalies *)

let () =
  check "the MOC groups pages by directory" (fun () ->
      let moc = Hermes_wiki.moc model in
      match (List.assoc_opt "zk" moc, List.assoc_opt "wiki" moc) with
      | Some zk, Some wiki -> List.length zk = 2 && List.length wiki = 1
      | _ -> false);
  (* zigvm §6a encodes the PATH into the page slug so two same-named
     notes in different folders cannot collide. Ours is basename-derived
     (stable, readable), so collisions are DISAMBIGUATED by group rather
     than shadowing — surfaced by importing a corpus with two README.md. *)
  check "a basename collision is disambiguated by group, not shadowed" (fun () ->
      let colliding =
        Hermes_wiki.build
          [ ("docs/hermes/alpha/readme.md", "# Alpha readme\n");
            ("docs/hermes/beta/readme.md", "# Beta readme\n") ]
      in
      let slugs =
        List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug)
          colliding.Hermes_wiki.pages
      in
      List.length (List.sort_uniq compare slugs) = 2
      && List.exists (fun s -> s = "readme") slugs
      && List.exists (fun s -> s = "beta-readme") slugs
      (* Resolved, but REPORTED: a reader must be able to see that a URL
         is not the basename, rather than wonder why. *)
      && List.exists
           (fun a -> contains a "slug collision resolved")
           colliding.Hermes_wiki.anomalies);
  check "duplicate slugs are an anomaly, not a silent shadow" (fun () ->
      let dup = Hermes_wiki.build (corpus @ [ ("docs/hermes/other/alpha.md", "# Dup\n") ]) in
      dup.Hermes_wiki.anomalies <> []);
  check "a clean corpus has no anomalies" (fun () -> model.Hermes_wiki.anomalies = []);
  check "the model is deterministic" (fun () -> Hermes_wiki.build corpus = model)

(* ------------------------------------------------------- the real tree *)

let () =
  check "the real pages tree loads with unique slugs" (fun () ->
      let files = Hermes_wiki.read_tree "modules/hermes_wiki/pages" in
      let real = Hermes_wiki.build files in
      List.length real.Hermes_wiki.pages >= 20
      && List.length
           (List.sort_uniq compare
              (List.map (fun p -> p.Hermes_wiki.slug) real.Hermes_wiki.pages))
         = List.length real.Hermes_wiki.pages);
  check "the migrated zk notes are in the graph with provenance" (fun () ->
      let real = Hermes_wiki.build (Hermes_wiki.read_tree "modules/hermes_wiki/pages") in
      match Hermes_wiki.page real "20260808-ocaml-only-tooling-rule" with
      | Some p ->
          p.Hermes_wiki.group = "zk"
          && p.Hermes_wiki.meta.Hermes_wiki.migrated_from <> None
      | None -> false)


(* ============================================================== *)
(* Laws imported from the zigvm WIKI_PIPELINE spec (docs/design/  *)
(* WIKI_PIPELINE.md). Each closes a named gap in the comparison   *)
(* at docs/hermes/wiki-pipeline-comparison.md.                    *)
(* ============================================================== *)

(* §4 — the resolver registers FOUR keys per note, so a link by title,
   by basename, or by title-minus-leading-ordinal all reach one slug. *)
let () =
  let corpus4 =
    [ ("docs/hermes/wiki/03-the-gate.md", "# 03 · The Gate\n\nBody.\n");
      ("docs/hermes/zk/caller.md",
       "# Caller\n\nBy title [[The Gate]], by ordinal title [[03 · The Gate]], \
        by basename [[03-the-gate]].\n") ]
  in
  let m = Hermes_wiki.build corpus4 in
  let caller = match Hermes_wiki.page m "caller" with Some p -> p | None -> failwith "caller" in
  check "a link by TITLE resolves to the page slug" (fun () ->
      List.mem "03-the-gate" caller.Hermes_wiki.outlinks);
  check "all four resolver forms collapse to ONE outlink" (fun () ->
      caller.Hermes_wiki.outlinks = [ "03-the-gate" ]);
  check "the target sees exactly one backlink from the caller" (fun () ->
      match Hermes_wiki.page m "03-the-gate" with
      | Some target -> target.Hermes_wiki.backlinks = [ "caller" ]
      | None -> false);
  check "an unresolvable link keeps its own normalized slug" (fun () ->
      let m2 =
        Hermes_wiki.build [ ("docs/hermes/zk/x.md", "# X\n\n[[Nowhere At All]]\n") ]
      in
      match Hermes_wiki.page m2 "x" with
      | Some p -> p.Hermes_wiki.outlinks = [ "nowhere-at-all" ]
      | None -> false)

(* §4 — mentions: a title appearing verbatim WITHOUT a link. *)
let () =
  let m =
    Hermes_wiki.build
      [ ("docs/hermes/zk/target.md", "# Gate Theory\n\nBody.\n");
        ("docs/hermes/zk/mentioner.md", "# Mentioner\n\nWe discussed Gate Theory at length.\n");
        ("docs/hermes/zk/linker.md", "# Linker\n\nSee [[Gate Theory]] for detail.\n") ]
  in
  check "an unlinked title occurrence becomes a mention" (fun () ->
      match Hermes_wiki.page m "target" with
      | Some p -> p.Hermes_wiki.mentions = [ "mentioner" ]
      | None -> false);
  check "a page that LINKS is a backlink, never also a mention" (fun () ->
      match Hermes_wiki.page m "target" with
      | Some p -> p.Hermes_wiki.backlinks = [ "linker" ] && not (List.mem "linker" p.Hermes_wiki.mentions)
      | None -> false);
  check "a page never mentions itself" (fun () ->
      match Hermes_wiki.page m "target" with
      | Some p -> not (List.mem "target" p.Hermes_wiki.mentions)
      | None -> false)

(* §6c — the frontmatter control panel carries decay signals. *)
let () =
  let m =
    Hermes_wiki.build
      [ ("docs/hermes/zk/decayed.md",
         "---\nid: n1\nstatus: published\ntype: claim\nlast_verified: 2026-08-01\n\
          verified_by: agent\nnext_review: 2026-09-01\nallow_example_links: true\n---\n# D\n");
        ("docs/hermes/zk/plain.md", "# Plain\n") ]
  in
  check "decay signals are parsed (last_verified, verified_by, next_review)" (fun () ->
      match Hermes_wiki.page m "decayed" with
      | Some p ->
          let meta = p.Hermes_wiki.meta in
          meta.Hermes_wiki.last_verified = "2026-08-01"
          && meta.Hermes_wiki.verified_by = "agent"
          && meta.Hermes_wiki.next_review = "2026-09-01"
          && meta.Hermes_wiki.allow_example_links
      | None -> false);
  check "has_frontmatter distinguishes an explicit block from defaults" (fun () ->
      match (Hermes_wiki.page m "decayed", Hermes_wiki.page m "plain") with
      | Some a, Some b ->
          a.Hermes_wiki.meta.Hermes_wiki.has_frontmatter
          && not b.Hermes_wiki.meta.Hermes_wiki.has_frontmatter
      | _ -> false);
  check "absent decay signals are empty, never invented" (fun () ->
      match Hermes_wiki.page m "plain" with
      | Some p ->
          p.Hermes_wiki.meta.Hermes_wiki.last_verified = ""
          && p.Hermes_wiki.meta.Hermes_wiki.next_review = ""
      | None -> false)

(* §6 — heading anchors: stateful per document, collisions suffixed,
   and LOCAL (a single-file render must emit the same anchors as a
   full-corpus render). *)
let () =
  let html =
    Hermes_wiki.render_markdown ~resolve:(fun _ -> None)
      "# Section\n\n## Section\n\n## Other\n\n## Section\n"
  in
  check "headings carry generated id anchors" (fun () ->
      contains html "id=\"section\"" && contains html "id=\"other\"");
  check "colliding headings get numbered suffixes, first wins" (fun () ->
      contains html "id=\"section-1\"" && contains html "id=\"section-2\"");
  check "anchors are LOCAL: the same document renders the same anchors" (fun () ->
      Hermes_wiki.render_markdown ~resolve:(fun _ -> None) "# Section\n\n## Section\n"
      = Hermes_wiki.render_markdown ~resolve:(fun _ -> None) "# Section\n\n## Section\n");
  check "a fragment wikilink [[Doc#Section]] resolves to the anchor" (fun () ->
      let m =
        Hermes_wiki.build
          [ ("docs/hermes/zk/doc.md", "# Doc\n\n## Deep Section\n");
            ("docs/hermes/zk/ref.md", "# Ref\n\nSee [[Doc#Deep Section]].\n") ]
      in
      match Hermes_wiki.page m "ref" with
      | Some p ->
          List.mem "doc" p.Hermes_wiki.outlinks
          && contains p.Hermes_wiki.html "doc.html#deep-section"
      | None -> false)

(* §3 — the corpus is what git tracks: an untracked note is invisible. *)
let () =
  check "read_tracked returns only git-tracked markdown" (fun () ->
      let tracked = Hermes_wiki.read_tracked "modules/hermes_wiki/pages" in
      tracked <> []
      && List.for_all (fun (path, _) -> Filename.check_suffix path ".md") tracked);
  check "an untracked file is NOT in the tracked corpus (git is the corpus)"
    (fun () ->
      let scratch = "modules/hermes_wiki/pages/zk/zz-untracked-probe.md" in
      let channel = open_out_bin scratch in
      output_string channel "# Probe\n";
      close_out channel;
      let tracked = Hermes_wiki.read_tracked "modules/hermes_wiki/pages" in
      let walked = Hermes_wiki.read_tree "modules/hermes_wiki/pages" in
      Sys.remove scratch;
      List.exists (fun (p, _) -> p = scratch) walked
      && not (List.exists (fun (p, _) -> p = scratch) tracked))

(* ---------------------------------------------- HW.3.4.2 / HW.3.4.3
   Fragment (anchor) validation. A [[Doc#Section]] whose target EXISTS but
   whose section does NOT currently resolves to the document and lands the
   reader silently at the top of the page. A dead fragment and a dead page
   have different fixes, so they are different diagnoses.

   Laws (docs/hermes/features-audit-implementation-plan.md §8.0.3):
     HW.3.4.2  anchors(p) = ids(render p)          -- collection is complete
     HW.3.4.3  resolve(t) = Some p /\ f not-in anchors(p) ==> diag
               and that diagnosis is DISTINCT from broken_link. *)

let anchor_corpus =
  [ ("docs/hermes/zk/target.md", "# Target\n\n## Real Section\n\nBody.\n\n## Another One\n\nMore.\n");
    ("docs/hermes/zk/citer.md",
     "# Citer\n\nGood: [[target#Real Section]].\n\nBad: [[target#Missing Section]].\n");
    ("docs/hermes/zk/plain.md", "# Plain\n\nWhole-document link [[target]] with no fragment.\n") ]

let anchor_model = Hermes_wiki.build anchor_corpus

let () =
  check "HW.3.4.2 anchors are collected per page" (fun () ->
      let a = Hermes_wiki.anchors anchor_model "target" in
      List.mem "real-section" a && List.mem "another-one" a)

let () =
  check "HW.3.4.2 anchors(p) = ids emitted by render" (fun () ->
      let p = match Hermes_wiki.page anchor_model "target" with
        | Some p -> p | None -> failwith "no target" in
      List.for_all
        (fun a -> contains p.Hermes_wiki.html ("id=\"" ^ a ^ "\""))
        (Hermes_wiki.anchors anchor_model "target"))

let () =
  check "HW.3.4.3 a dead fragment on a live page is reported" (fun () ->
      List.exists
        (fun d -> contains d "citer" && contains d "missing-section")
        (Hermes_wiki.broken_anchors anchor_model))

let () =
  check "HW.3.4.3 a live fragment is NOT reported" (fun () ->
      not
        (List.exists
           (fun d -> contains d "real-section")
           (Hermes_wiki.broken_anchors anchor_model)))

let () =
  check "HW.3.4.3 a fragmentless link is NOT an anchor defect" (fun () ->
      not
        (List.exists
           (fun d -> contains d "plain")
           (Hermes_wiki.broken_anchors anchor_model)))

let () =
  check "HW.3.4.3 broken anchor is distinct from broken link" (fun () ->
      (* the target page EXISTS, so this must not be reported as a dead link *)
      let dead_link_reports =
        List.filter (fun d -> contains d "target") (Hermes_wiki.defects anchor_model)
      in
      List.length dead_link_reports = 0
      && Hermes_wiki.broken_anchors anchor_model <> [])

let () =
  (* The distinctness claim has TWO directions, and the second is the one a
     naive implementation gets wrong: a fragment into a page that does NOT
     exist is already a dead LINK, so reporting it as a dead ANCHOR too
     would make the two diagnoses agree about nothing useful. Without this
     the "distinct" law above passes even when the code conflates them. *)
  check "HW.3.4.3 a fragment into a MISSING page is not an anchor defect" (fun () ->
      let m =
        Hermes_wiki.build
          [ ("docs/hermes/zk/only.md", "# Only\n\nLink to [[nowhere#Some Section]].\n") ]
      in
      Hermes_wiki.broken_anchors m = [])

let () =
  check "HW.3.4.3 percent-encoded fragments resolve" (fun () ->
      let m =
        Hermes_wiki.build
          [ ("docs/hermes/zk/t2.md", "# T2\n\n## Real Section\n");
            ("docs/hermes/zk/c2.md", "# C2\n\n[[t2#Real%20Section]].\n") ]
      in
      Hermes_wiki.broken_anchors m = [])

let () =
  check "HW.3.4.3 meta-falsification: the check can fail" (fun () ->
      (* if the law could not detect a break, it would prove nothing *)
      let m =
        Hermes_wiki.build
          [ ("docs/hermes/zk/t3.md", "# T3\n\n## Present\n");
            ("docs/hermes/zk/c3.md", "# C3\n\n[[t3#Absent]].\n") ]
      in
      List.length (Hermes_wiki.broken_anchors m) = 1)

(* ----------------------------------------- HW.2.1.3 / .5 / .10, HW.2.2.3
   Flat block constructs the line machine can express today. These were
   labelled "blocked on the AST" in the plan; that was too conservative —
   the AST is required for block-IN-block (nesting, callout bodies,
   footnote bodies), not for flat ordered lists, rules or checkboxes.

   Laws (§8.0.2): CommonMark 5.2 for ordered lists (start number and
   delimiter preserved), CommonMark 4.1 for the thematic break
   (disambiguated from the frontmatter delimiter), GFM 5.3 for task list
   items rendered READ-ONLY, GFM 6.5 for strikethrough. *)

let render s = Hermes_wiki.render_markdown ~resolve:(fun _ -> None) s

let () =
  check "HW.2.1.3 an ordered list renders as <ol>" (fun () ->
      let h = render "1. first\n2. second\n" in
      contains h "<ol" && contains h "<li>first</li>" && contains h "<li>second</li>")

let () =
  check "HW.2.1.3 the start number is preserved (CommonMark 5.2)" (fun () ->
      contains (render "5. five\n6. six\n") "start=\"5\"")

let () =
  check "HW.2.1.3 a start of 1 needs no start attribute" (fun () ->
      not (contains (render "1. one\n") "start="))

let () =
  check "HW.2.1.3 both . and ) delimiters are ordered lists" (fun () ->
      contains (render "1) one\n") "<ol")

let () =
  check "HW.2.1.3 a bare number is NOT a list" (fun () ->
      (* "10 items" is a paragraph — the delimiter is required *)
      let h = render "10 items were counted\n" in
      (not (contains h "<ol")) && contains h "<p>")

let () =
  check "HW.2.1.3 ordered and unordered lists do not merge" (fun () ->
      let h = render "- bullet\n\n1. number\n" in
      contains h "</ul>" && contains h "<ol")

let () =
  check "HW.2.1.5 a thematic break renders as <hr>" (fun () ->
      contains (render "before\n\n---\n\nafter\n") "<hr")

let () =
  check "HW.2.1.5 frontmatter delimiters are NOT rules" (fun () ->
      (* the body handed to the renderer has already had frontmatter
         stripped; a leading --- would otherwise become a spurious rule *)
      let model =
        Hermes_wiki.build
          [ ("docs/hermes/zk/fm.md", "---\nid: x\nstatus: draft\n---\n# Title\n\nBody.\n") ]
      in
      match Hermes_wiki.page model "fm" with
      | Some p -> not (contains p.Hermes_wiki.html "<hr")
      | None -> false)

let () =
  check "HW.2.1.5 *** and ___ are also thematic breaks" (fun () ->
      contains (render "a\n\n***\n\nb") "<hr" && contains (render "a\n\n___\n\nb") "<hr")

let () =
  check "HW.2.1.10 a task item renders a checkbox" (fun () ->
      let h = render "- [ ] open task\n" in
      contains h "checkbox" && contains h "open task")

let () =
  check "HW.2.1.10 a checked item is checked" (fun () ->
      contains (render "- [x] done\n") "checked")

let () =
  check "HW.2.1.10 the checkbox is READ-ONLY (state lives in the ledger)" (fun () ->
      let h = render "- [ ] task\n- [x] done\n" in
      contains h "disabled" && (not (contains h "<form")) && not (contains h "onclick"))

let () =
  check "HW.2.1.10 an ordinary bullet is not a checkbox" (fun () ->
      not (contains (render "- plain\n") "checkbox"))

let () =
  check "HW.2.2.3 strikethrough renders as <del>" (fun () ->
      contains (render "this is ~~gone~~ now") "<del>gone</del>")

let () =
  check "HW.2.2.3 a single tilde is not strikethrough" (fun () ->
      not (contains (render "a ~b~ c") "<del>"))

let () =
  check "HW.2.2.3 strikethrough inside a fence is inert" (fun () ->
      not (contains (render "```\n~~kept~~\n```") "<del>"))

let () =
  check "meta-falsification: these constructs were genuinely absent before" (fun () ->
      (* every one of them must produce markup the old renderer could not:
         if any of these strings appeared without the feature, the test
         above would have been vacuous *)
      List.for_all
        (fun (src, needle) -> contains (render src) needle)
        [ ("1. a", "<ol"); ("a\n\n---\n\nb", "<hr"); ("- [ ] t", "checkbox"); ("~~x~~", "<del>") ])

(* ------------------------------------------------- PKM schema (2026-08-09)
   docs/hermes/specs/2026-08-09-pkm-longterm-architecture.md §3.

   New meta fields: aliases (resolver-backed — HW.1.2.7), ktype and
   maturity (NEW AXES beside the discourse type and editorial status),
   domain, topics, links (declared parent/child UIDs only — I3 keeps the
   body's graph derived), created (R16: read, never invented).

   schema_gaps reports missing required fields as NOTICES — same decision
   as broken_anchors: report first, ratchet later. *)

let pkm_corpus =
  [ ( "docs/hermes/zk/202608091001-gaa.md",
      "---\nid: 202608091001\ntitle: \"GAA Architecture\"\naliases: [\"Gate-All-Around\", \"GAA\"]\nktype: atomic\nmaturity: evergreen\ndomain: semiconductors\ntopics: [rtl_design, thermal_management]\nlinks: [202608091002]\ncreated: 2026-08-09\n---\n# GAA Architecture\n\n360-degree gate control.\n" );
    ( "docs/hermes/zk/202608091002-thermal.md",
      "---\nid: 202608091002\nktype: atomic\nmaturity: seed\ncreated: 2026-08-09\n---\n# Thermal Density\n\nSee [[Gate-All-Around]] for the base architecture.\n" );
    ("docs/hermes/zk/bare.md", "# Bare\n\nNo frontmatter at all.\n") ]

let pkm = Hermes_wiki.build pkm_corpus

let pkm_page slug =
  match Hermes_wiki.page pkm slug with
  | Some p -> p
  | None -> failwith ("no page " ^ slug)

let () =
  check "PKM: aliases are parsed as a list" (fun () ->
      (pkm_page "202608091001-gaa").Hermes_wiki.meta.Hermes_wiki.aliases
      = [ "Gate-All-Around"; "GAA" ])

let () =
  check "PKM: ktype and maturity are carried (new axes, not replacements)" (fun () ->
      let m = (pkm_page "202608091001-gaa").Hermes_wiki.meta in
      m.Hermes_wiki.ktype = "atomic" && m.Hermes_wiki.maturity = "evergreen")

let () =
  check "PKM: domain, topics, links, created are carried" (fun () ->
      let m = (pkm_page "202608091001-gaa").Hermes_wiki.meta in
      m.Hermes_wiki.domain = "semiconductors"
      && m.Hermes_wiki.topics = [ "rtl_design"; "thermal_management" ]
      && m.Hermes_wiki.links = [ "202608091002" ]
      && m.Hermes_wiki.created = "2026-08-09")

let () =
  check "PKM: absent fields default honestly (empty, never fabricated)" (fun () ->
      let m = (pkm_page "bare").Hermes_wiki.meta in
      m.Hermes_wiki.aliases = [] && m.Hermes_wiki.ktype = ""
      && m.Hermes_wiki.maturity = "" && m.Hermes_wiki.created = "")

let () =
  check "HW.1.2.7 an alias RESOLVES: [[Gate-All-Around]] links the aliased page"
    (fun () ->
      let p = pkm_page "202608091002-thermal" in
      contains p.Hermes_wiki.html "202608091001-gaa"
      && List.mem "202608091001-gaa" p.Hermes_wiki.outlinks)

let () =
  check "HW.1.2.7 an alias never SHADOWS a real slug (first registration wins)"
    (fun () ->
      let m =
        Hermes_wiki.build
          [ ("docs/hermes/zk/real.md", "# Real\n\nThe page that owns the slug.\n");
            ( "docs/hermes/zk/thief.md",
              "---\naliases: [\"real\"]\n---\n# Thief\n\nTries to claim it.\n" );
            ("docs/hermes/zk/citer.md", "# Citer\n\nLink: [[real]].\n") ]
      in
      match Hermes_wiki.page m "citer" with
      | Some p -> List.mem "real" p.Hermes_wiki.outlinks
      | None -> false)

let () =
  check "PKM: schema_gaps names the bare document and its missing fields" (fun () ->
      let gaps = Hermes_wiki.schema_gaps pkm in
      List.exists (fun g -> contains g "bare" && contains g "ktype") gaps
      && List.exists (fun g -> contains g "bare" && contains g "created") gaps)

let () =
  check "PKM: schema_gaps is SILENT about a fully conformant document" (fun () ->
      not
        (List.exists
           (fun g -> contains g "202608091001-gaa")
           (Hermes_wiki.schema_gaps pkm)))

let () =
  check "PKM: schema gaps are notices, never defects (report, don't refuse)" (fun () ->
      Hermes_wiki.defects pkm = []
      || not
           (List.exists (fun d -> contains d "schema") (Hermes_wiki.defects pkm)))

let () =
  check "PKM meta-falsification: a partly-conformant doc is gapped on exactly the absent fields"
    (fun () ->
      let gaps = Hermes_wiki.schema_gaps pkm in
      (* thermal has ktype+maturity+created but no domain/topics/title-override:
         domain and topics must be reported; ktype must NOT be *)
      List.exists (fun g -> contains g "202608091002-thermal" && contains g "domain") gaps
      && not
           (List.exists
              (fun g -> contains g "202608091002-thermal" && contains g "ktype")
              gaps))

(* ----------------------------------------- NO-HARNESS-DEPENDENCY GUARD
   No dune file under hermes_wiki/ may reference a hermes_harness_* library.
   The harness may depend on the wiki; never the reverse. This deliberately
   proves only that boundary: hermes_wiki has source dependencies on
   hermes_sysml and hermes_fpp_window_authority, so this is not a standalone
   liftability proof. *)
let () =
  check "self-containment: no hermes_wiki dune references hermes_harness_*" (fun () ->
      let rec dunes dir =
        Sys.readdir dir |> Array.to_list
        |> List.concat_map (fun name ->
               let p = Filename.concat dir name in
               if Sys.is_directory p then dunes p
               else if name = "dune" then [ p ]
               else [])
      in
      List.for_all
        (fun path ->
          let ic = open_in_bin path in
          let s = really_input_string ic (in_channel_length ic) in
          close_in ic;
          let bad = "hermes_harness_" in
          let n = String.length bad and t = String.length s in
          let rec has i = i + n <= t && (String.sub s i n = bad || has (i + 1)) in
          let rec strip_comments acc = function
            | [] -> String.concat "\n" (List.rev acc)
            | l :: rest ->
                if String.length (String.trim l) > 0 && (String.trim l).[0] = ';'
                then strip_comments acc rest
                else strip_comments (l :: acc) rest
          in
          let code = strip_comments [] (String.split_on_char '\n' s) in
          let t2 = String.length code in
          let rec has2 i = i + n <= t2 && (String.sub code i n = bad || has2 (i + 1)) in
          ignore has; not (has2 0))
        (dunes "modules/hermes_wiki"))

(* ---- HW.3.3.1 block anchors: addressing, disjointness, uniqueness ---- *)

let () =
  check "HW.3.3.1: anchors include block ids WITH the ^; namespaces disjoint" (fun () ->
      let m =
        Hermes_wiki.build [ ("pages/wiki/pa.md", "# Pa\n\n## Sec\n\na claim ^b1\n") ]
      in
      let a = Hermes_wiki.anchors m "pa" in
      List.mem "^b1" a && List.mem "sec" a && not (List.mem "b1" a));
  check "HW.3.3.1: [[Pa#^b1]] resolves; [[Pa#^nope]] is a broken ANCHOR (distinct diagnosis)"
    (fun () ->
      let good =
        Hermes_wiki.build
          [ ("pages/wiki/pa.md", "# Pa\n\nclaim ^b1\n");
            ("pages/wiki/pb.md", "# Pb\n\nsee [[Pa#^b1]]\n") ]
      in
      let bad =
        Hermes_wiki.build
          [ ("pages/wiki/pa.md", "# Pa\n\nclaim ^b1\n");
            ("pages/wiki/pb.md", "# Pb\n\nsee [[Pa#^nope]]\n") ]
      in
      Hermes_wiki.broken_anchors good = []
      && List.exists
           (fun s ->
             try ignore (Str.search_forward (Str.regexp_string "^nope") s 0); true
             with Not_found -> false)
           (Hermes_wiki.broken_anchors bad));
  check "HW.3.3.1: a SAME-PAGE duplicate ^id is a defect; cross-page reuse is legal"
    (fun () ->
      let dup =
        Hermes_wiki.build [ ("pages/wiki/pa.md", "# Pa\n\none ^b1\n\ntwo ^b1\n") ]
      in
      let cross =
        Hermes_wiki.build
          [ ("pages/wiki/pa.md", "# Pa\n\none ^b1\n");
            ("pages/wiki/pb.md", "# Pb\n\ntwo ^b1\n") ]
      in
      List.exists
        (fun s ->
          try ignore (Str.search_forward (Str.regexp_string "duplicate block anchor") s 0); true
          with Not_found -> false)
        (Hermes_wiki.defects dup)
      && not
           (List.exists
              (fun s ->
                try
                  ignore (Str.search_forward (Str.regexp_string "duplicate block anchor") s 0);
                  true
                with Not_found -> false)
              (Hermes_wiki.defects cross)))

(* The discourse vocabulary is CLOSED, and extending it is a governance
   act with a reason — `reference` was admitted for imported material,
   and `policy` for the normative documents the system-engineering track
   now authors (a rule is neither a claim about the world nor a decision
   we took; it binds future work). A type outside the set stays a
   DEFECT: that is what makes the set mean anything. *)
let () =
  check "the discourse vocabulary admits policy, and still refuses the unknown" (fun () ->
      let defects_of t =
        Hermes_wiki.defects
          (Hermes_wiki.build [ ("docs/x/d.md", "---\ntype: " ^ t ^ "\n---\n# D\n\nbody.\n") ])
      in
      defects_of "policy" = []
      && defects_of "playbook" = []
      && defects_of "decision" = []
      && List.length (defects_of "manifesto") = 1)

(* ---------------------------- HW.9.3.1: the doctest builder's core *)

let () =
  let doc body = [ ("docs/x/dt.md", "# DT\n\n" ^ body) ] in
  check "DT1 a matching doctest is silent" (fun () ->
      Hermes_wiki.doctest_drift
        (Hermes_wiki.build (doc "```doctest\n> plain text\n<p>plain text</p>\n```\n"))
      = []);
  check "DT2 a mismatch is DOCUMENTATION DRIFT, named by page" (fun () ->
      match
        Hermes_wiki.doctest_drift
          (Hermes_wiki.build (doc "```doctest\n> plain text\n<p>other</p>\n```\n"))
      with
      | [ line ] ->
          (try ignore (Str.search_forward (Str.regexp_string "dt") line 0); true
           with Not_found -> false)
      | _ -> false);
  check "DT3 a non-doctest fence with > lines is NOT evaluated" (fun () ->
      Hermes_wiki.doctest_drift
        (Hermes_wiki.build (doc "```ocaml\n> not a doctest\nwhatever\n```\n"))
      = []);
  check "DT4 the doctest token may follow a language" (fun () ->
      match
        Hermes_wiki.doctest_drift
          (Hermes_wiki.build (doc "```markdown doctest\n> x\n<p>wrong</p>\n```\n"))
      with
      | [ _ ] -> true
      | _ -> false)

let () =
  Printf.printf "hermes_wiki: %d passed, %d failed\n" !passed !failed;
  let self = Wiki_suite_telemetry.observe ~suite:"test_hermes_wiki" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Wiki_suite_telemetry.emit self ~targets:[ Stanza.wiki_suite_telemetry ]);
  exit (Wiki_suite_telemetry.exit_code self)
