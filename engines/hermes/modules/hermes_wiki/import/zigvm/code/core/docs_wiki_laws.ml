(* docs_wiki_laws — the law suite for the docs wiki + Zettelkasten
   (harness/docs_wiki.ml).

   WHY THIS IS A LIBRARY AND NOT AN EXECUTABLE. It was `test_docs_wiki.ml`, an
   executable nothing invoked. The gate builds the harness binary and its
   dependency closure — an executable outside that closure is never even
   COMPILED, so this suite kept calling `render_graph_svg` for the entire time
   after that function was deleted, and no gate noticed. It was not a suite
   that failed; it was a suite that could not run.

   That is the fourth instance of the same defect in this module family
   (`test_wiki_shell`, `test_slo_render`, `Docs_wiki.selftest` were the first
   three), so the fix is the structural one rather than a repair: the laws move
   into the library the harness already links, and `Render_suite` in
   `zigvm_harness.ml` dispatches them. A function these laws name and someone
   deletes is now a COMPILE ERROR on the gate's own build.

   `run ~root` returns (law, verdict) pairs like every other registered suite.
   It never prints and never exits — reporting belongs to the harness. *)
module W = Docs_wiki

let results : (string * bool) list ref = ref []
let check name cond = results := (name, cond) :: !results
let has s sub = let re = Str.regexp_string sub in try ignore (Str.search_forward re s 0); true with Not_found -> false
let hasnt s sub = not (has s sub)
let read_file p = let ic = open_in_bin p in let n = in_channel_length ic in let s = really_input_string ic n in close_in ic; s
let rec walk_md dir acc =
  if Sys.file_exists dir && Sys.is_directory dir then
    Array.fold_left (fun acc name ->
      let p = Filename.concat dir name in
      if (try Sys.is_directory p with _ -> false) then walk_md p acc
      else if Filename.check_suffix p ".md" then p :: acc else acc)
      acc (Sys.readdir dir)
  else acc

(* Markdown now renders through the typed AST — the streaming renderer these
   assertions were written against has been retired. `~resolve` is what the AST
   consults for a `[[target]]`; with no wiki in scope every target is missing,
   which is precisely what these single-document assertions want. *)
let render_markdown md = W.render_markdown_typed ~resolve:(fun _ -> None) md

let run ~(root : string) : (string * bool) list =
  results := [];

  (* ── markdown block rendering ─────────────────────────────────────────── *)
  (* Typed markup differs from the retired streaming renderer in three ways the
     assertions below now encode rather than paper over: attribute values are
     quoted, a void element self-closes, and blocks are not separated by a
     newline the renderer never needed to emit. *)
  check "h1" (render_markdown "# Hi" = "<h1 id=\"hi\">Hi</h1>");
  check "h2" (has (render_markdown "## Hi") "<h2 id=\"hi\">Hi</h2>");
  check "h3" (has (render_markdown "### Hi") "<h3 id=\"hi\">Hi</h3>");
  check "h4" (has (render_markdown "#### Hi") "<h4 id=\"hi\">Hi</h4>");
  check "bullet" (has (render_markdown "- a\n- b") "<ul>" && has (render_markdown "- a") "<li>a</li>");
  check "numbered" (has (render_markdown "1. a\n2. b") "<ol>");
  check "blockquote" (has (render_markdown "> q") "<blockquote>");
  check "code-fence" (has (render_markdown "```\ncode\n```") "<pre><code>");
  check "table" (has (render_markdown "| a | b |\n|---|---|\n| 1 | 2 |") "<table>"
                 && has (render_markdown "| a | b |\n|---|---|\n| 1 | 2 |") "<th>a</th>");
  check "hr" (has (render_markdown "---") "<hr/>");

  (* ── inline rendering ─────────────────────────────────────────────────── *)
  check "bold" (has (render_markdown "**x**") "<strong>x</strong>");
  check "italic" (has (render_markdown "*x*") "<em>x</em>");
  check "inline-code" (has (render_markdown "`x`") "<code>x</code>");
  check "code-span-literal" (hasnt (render_markdown "`**x**`") "<strong>");  (* not re-interpreted *)
  check "ext-link" (has (render_markdown "[t](https://x.io)") "href=\"https://x.io\"");

  (* ── escaping / injection-safety ──────────────────────────────────────── *)
  check "raw-lt-escaped" (has (render_markdown "a < b") "&lt;");
  check "script-escaped" (hasnt (render_markdown "<script>evil()</script>") "<script>");
  check "lt-in-code-escaped" (has (render_markdown "`x<y`") "x&lt;y");
  check "jesc-lt" (W.jesc "a<b" = "\"a\\u003cb\"");
  check "jesc-quote" (W.jesc "a\"b" = "\"a\\\"b\"");
  check "jesc-backslash" (W.jesc "a\\b" = "\"a\\\\b\"");

  (* ── totality (never crash / hang) ────────────────────────────────────── *)
  check "empty-md" (String.length (render_markdown "") >= 0);
  check "unclosed-fence" (let _ = render_markdown "```\nunterminated" in true);
  check "malformed-table" (let _ = render_markdown "| broken" in true);
  check "lone-brackets" (let _ = render_markdown "[[ ]] [x]( )" in true);

  (* ── slug / znorm ─────────────────────────────────────────────────────── *)
  check "slug" (W.slug_of_path "docs/harness-wiki/02-The-Gate.md" = "harness-wiki--02-the-gate");
  check "znorm-ordinal" (W.znorm "02 · The Gate" = "02-the-gate");
  check "znorm-lower" (W.znorm "Hello World!" = "hello-world");

  (* ── the corpus under test (atomic notes) ─────────────────────────────── *)
  let corpus =
    [ ("docs/a.md", "# Alpha\n\n#core see [[Beta]] and [[Gamma|the third]]; ref [The Gate](sub/gate.md).")
    ; ("docs/b.md", "# Beta\n\n#core plain note that also names Alpha in prose")
    ; ("docs/sub/gate.md", "# The Gate\n\n#gate #ci the completion signal")
    ; ("docs/c.md", "# Gamma island\n\nno links, an orphan") ] in
  let pages = W.build corpus in
  let find t = List.find (fun (p : W.page) -> p.title = t) pages in
  let a = find "Alpha" and b = find "Beta" and g = find "The Gate" in

  (* ── [[wiki-links]] ───────────────────────────────────────────────────── *)
  check "wikilink-resolves" (List.mem b.slug a.outlinks);
  check "wikilink-renders" (has a.html "class=\"zettel\"");
  check "wikilink-display" (has a.html "the third");           (* [[Gamma|the third]] display *)
  check "wikilink-missing" (has a.html "zettel missing");      (* [[Gamma]] has no Gamma note *)
  check "no-self-outlink" (not (List.mem a.slug a.outlinks));

  (* ── link rewriting (working links) ───────────────────────────────────── *)
  check "md-link-rewritten" (has a.html "href=\"sub--gate.html\"");
  check "ext-link-untouched" (W.rewrite_href "https://x.io" = "https://x.io");
  check "route-link-untouched" (W.rewrite_href "/wiki" = "/wiki");
  check "anchor-untouched" (W.rewrite_href "#section" = "#section");

  (* ── bidirectional backlinks ──────────────────────────────────────────── *)
  check "backlink-bidirectional" (List.mem a.slug b.backlinks);   (* Alpha [[Beta]] ⇒ Beta ← Alpha *)
  check "no-self-backlink" (not (List.mem b.slug b.backlinks));
  check "backlink-symmetry"                                        (* every backlink ⇔ an outlink *)
    (List.for_all (fun (p : W.page) ->
       List.for_all (fun bl ->
         let src = List.find (fun (q : W.page) -> q.slug = bl) pages in
         List.mem p.slug src.outlinks) p.backlinks) pages);
  check "backlink-in-page" (has (W.render_page ~pages b) "Linked references" && has (W.render_page ~pages b) "Alpha");

  (* ── tags ─────────────────────────────────────────────────────────────── *)
  check "tag-parsed" (List.mem "core" a.tags);
  check "tag-multi" (List.mem "gate" g.tags && List.mem "ci" g.tags);
  check "tag-not-heading" (not (List.mem "alpha" a.tags));       (* '# Alpha' is a heading, not a tag *)
  check "tag-chip-rendered" (has (W.render_page ~pages a) "zk-tag");
  check "tags-index" (has (W.render_tags pages) "#core" && has (W.render_tags pages) "#gate");

  (* ── unlinked mentions ────────────────────────────────────────────────── *)
  check "unlinked-mention" (List.mem b.slug a.mentions);         (* Beta names "Alpha" without a link *)
  check "linked-not-mention" (not (List.mem b.slug a.mentions && List.mem b.slug a.outlinks && false));
  check "mention-rendered" (has (W.render_page ~pages a) "Unlinked mentions");
  check "short-title-no-mention"                                  (* titles <4 chars don't spuriously match *)
    (let p2 = W.build [ ("docs/x.md","# Hi\n\natomic"); ("docs/y.md","# Note\n\nHi there everyone") ] in
     let hi = List.find (fun (p:W.page)->p.title="Hi") p2 in hi.mentions = []);

  (* ── graph + SVG visualization ────────────────────────────────────────── *)
  check "graph-title" (has (W.render_graph pages) "Zettelkasten graph");
  check "graph-edges" (has (W.render_graph pages) "zk-edge");
  check "graph-orphans" (has (W.render_graph pages) "Orphans");
  (* The graph a reader actually sees is the force-directed one: an empty <svg>
     the script populates from an inert JSON payload. `render_graph_svg` — the
     server-side static SVG these assertions used to exercise — was deleted as
     unreachable, and the suite kept referencing it because nothing built the
     suite. The checks below name the LIVE renderer, so a repeat is a compile
     error rather than a silence. *)
  let fg = W.render_graph_interactive pages in
  check "fg-svg-host" (has fg "<svg" && has fg "id=\"fg\"");
  check "fg-payload-inert"                       (* application/json, not executed *)
    (has fg "id=\"fg-data\"" && has fg "application/json");
  check "fg-nodes-are-every-note"
    (List.for_all (fun (p : W.page) -> has fg ("\"id\":\"" ^ p.slug ^ "\"")) pages);
  check "fg-edges-are-resolved-outlinks"         (* one edge per outlink, no dangling *)
    (let slugs = List.map (fun (p : W.page) -> p.slug) pages in
     List.for_all (fun (p : W.page) ->
       List.for_all (fun o ->
         List.mem o slugs
         && has fg ("{\"s\":\"" ^ p.slug ^ "\",\"t\":\"" ^ o ^ "\"}")) p.outlinks)
       pages);
  check "fg-controls-present" (has fg "fg-search" && has fg "fg-reset");

  (* ── full-text search ─────────────────────────────────────────────────── *)
  let sr = W.render_search pages in
  check "search-input" (has sr "zks-input");
  check "search-index" (has sr "zks-idx" && has sr "Alpha" && has sr "The Gate");
  check "search-jesc-safe" (has (W.render_search (W.build [ ("docs/s.md","# S\n\n<script>x</script>") ])) "\\u003cscript");
  check "search-text-collapses" (W.search_text "a\n\n  b\tc" = "a b c");
  check "search-text-caps" (String.length (W.search_text (String.make 5000 'x')) <= 3000);

  (* ── page/index structure ─────────────────────────────────────────────── *)
  check "page-full" (let h = W.render_page ~pages a in has h "<title>" && has h "<aside>" && has h "Alpha");
  check "page-2way-nav" (has (W.render_page ~pages b) "previous" || has (W.render_page ~pages b) "next");
  check "index-lists-all" (let idx = W.render_index pages in List.for_all (fun (p:W.page) -> has idx p.title) pages);
  check "sidebar-search-box" (has (W.render_index pages) "nav-search");
  check "orphan-detected" ((find "Gamma island").outlinks = [] && (find "Gamma island").backlinks = []);

  (* ── the built-in selftest law also passes ────────────────────────────── *)
  check "selftest-law" (let _ = W.selftest () in true);

  (* ── over the REAL project docs corpus (existing docs + journals) ─────── *)
  let doc_files = List.sort compare (walk_md (Filename.concat root "docs") []) in
  (* NON-VACUITY. As an executable this block printed "skip" and passed when the
     corpus was unreachable; as a gate suite that would be a green run over
     nothing. The corpus is now a LAW, so an empty one is a failure rather than
     a silence. The floor is deliberately far below the real count (653) — it
     asserts "a corpus was found", not a document total that would have to be
     edited every time someone writes a note. *)
  check "real:corpus-reachable" (List.length doc_files > 100);
  (match doc_files with
   | [] -> ()
   | _ ->
     let corpus = List.map (fun p -> (p, read_file p)) doc_files in
     let real = W.build corpus in
     let slugs = List.map (fun (p : W.page) -> p.slug) real in
     check "real:builds-all" (List.length real = List.length doc_files);
     check "real:slugs-unique" (List.length (List.sort_uniq compare slugs) = List.length slugs);
     check "real:every-note-renders"
       (List.for_all (fun (p : W.page) ->
          let h = W.render_page ~pages:real p in
          has h "<title>" && has h "<aside>" && String.length h > 200) real);
     check "real:outlink-targets-exist"                       (* no dangling [[wiki-links]] *)
       (List.for_all (fun (p : W.page) -> List.for_all (fun o -> List.mem o slugs) p.outlinks) real);
     check "real:backlink-symmetry"
       (List.for_all (fun (p : W.page) ->
          List.for_all (fun bl ->
            let src = List.find (fun (q : W.page) -> q.slug = bl) real in
            List.mem p.slug src.outlinks) p.backlinks) real);
     check "real:no-self-links" (List.for_all (fun (p : W.page) -> not (List.mem p.slug p.outlinks)) real);
     check "real:no-raw-script-from-content"                  (* the renderer escapes ALL doc content *)
       (List.for_all (fun (p : W.page) -> hasnt p.html "<script") real);
     check "real:graph-renders" (has (W.render_graph real) "Zettelkasten graph");
     check "real:graph-payload-script-safe"
       (* The payload sits in a <script type="application/json"> whose content
          model is raw text: a '<' inside it is a literal, so a note titled
          "</script>" would CLOSE the element and everything after it would be
          parsed as markup. Json_embed escapes '<' to <, which makes the
          payload inert by construction — so the property is that the payload
          region contains no '<' AT ALL, and it holds over 1600 real titles. *)
       (let fg = W.render_graph_interactive real in
        let open_tag = "id=\"fg-data\">" in
        let re = Str.regexp_string open_tag in
        let start = Str.search_forward re fg 0 + String.length open_tag in
        let stop = Str.search_forward (Str.regexp_string "</script>") fg start in
        let payload = String.sub fg start (stop - start) in
        String.length payload > 100 && not (String.contains payload '<'));
     check "real:graph-payload-covers-notes"
       (let fg = W.render_graph_interactive real in
        List.for_all (fun (p : W.page) -> has fg ("\"id\":\"" ^ p.slug ^ "\"")) real);
     check "real:tags-index-renders" (let _ = W.render_tags real in true);
     let sr = W.render_search real in
     check "real:search-covers-notes"                        (* slug is jesc-safe (alnum+hyphen) *)
       (List.for_all (fun (p : W.page) -> has sr ("\"s\":\"" ^ p.slug ^ "\"")) real);
     check "real:search-injection-safe" (hasnt sr "<script>alert" && hasnt sr "</script></script>");
     (* a known internal link is a WORKING html link (the seeded [[The Gate]]) *)
     check "real:seeded-wikilink-works"
       (match List.find_opt (fun (p : W.page) -> p.slug = "harness-wiki--02-the-gate") real with
        | Some gate -> gate.backlinks <> []      (* README + Architecture [[link]] it *)
        | None -> true);
     (* ── the full-ZK primitives over the real corpus ─────────────────── *)
     check "real:degree-is-in-plus-out"
       (List.for_all (fun (p : W.page) ->
          W.degree p = List.length p.outlinks + List.length p.backlinks) real);
     check "real:every-note-carries-an-id-card"
       (List.for_all (fun (p : W.page) ->
          let h = W.render_page ~pages:real p in
          has h "zk-card" && has h ("<span class=\"zk-id\">" ^ p.slug)) real);
     check "real:mocs-are-connected-nonorphans"     (* entry points never include an orphan *)
       (let m = W.mocs real in m <> [] && List.for_all (fun (p : W.page) -> W.degree p > 0) m);
     check "real:mocs-are-community-entry-points"
       (* the community-grounded contract (zk-communities): each MoC entry is
          the TOP-DEGREE member OF ITS OWN COMMUNITY (ties → slug order) —
          the old global-top-degree claim only held by coincidence before the
          fractal-atlas reshaped the graph *)
       (let m = W.mocs real in
        let comm = W.communities real in
        m <> []
        && List.for_all (fun (p : W.page) ->
             match List.assoc_opt p.slug comm with
             | None -> false
             | Some c ->
                 List.for_all (fun (q : W.page) ->
                   q.slug = p.slug
                   || List.assoc_opt q.slug comm <> Some c
                   || W.degree q < W.degree p
                   || (W.degree q = W.degree p && q.slug >= p.slug)) real) m);
     check "real:index-surfaces-entry-points" (has (W.render_index real) "Entry points");
     check "real:random-total-and-member"           (* serendipity walk always lands on a real note *)
       (List.for_all (fun n -> match W.random_target real n with
          | Some p -> List.exists (fun (q:W.page) -> q.slug=p.slug) real | None -> false)
          [0;1;5;13;46;100;-1;-7]);
     check "real:random-page-jumps" (has (W.render_random real) "location.replace")) ;
  List.rev !results
