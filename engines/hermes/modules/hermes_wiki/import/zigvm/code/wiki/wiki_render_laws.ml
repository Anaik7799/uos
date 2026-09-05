(* Rendering laws for the wiki — the SHELL (`nav_aside`/`page_frame`), the
   zkquery console, the graph page, and the system-memory page.

   WHY THIS IS A LIBRARY AND NOT A TEST EXECUTABLE. These laws lived in
   `test_wiki_shell.ml`, a standalone `(executable …)` that nothing ever ran:
   not `dune runtest` (it is not a `(test …)`), not the canonical gate, not
   `--verify-formal`. So an escaping regression would have been caught by
   nobody. A law that never runs is the same defect as a law that cannot
   fail, wearing better clothes.

   As a library module the laws have ONE definition and TWO callers: the
   standalone `test_wiki_shell.exe` for the dev loop, and `typed_html_laws`
   inside the harness gate. Gate and dev loop therefore cannot disagree —
   the same convention `route_laws` / `web_laws` / `channel_laws` already
   follow.

   `run ()` returns each law's name and verdict rather than printing or
   exiting, so each caller decides what a failure means. *)

module W = Docs_wiki

let contains hay needle =
  let nl = String.length needle and hl = String.length hay in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl > 0 && go 0

let count_sub hay needle =
  let nl = String.length needle and hl = String.length hay in
  let n = ref 0 in
  for i = 0 to hl - nl do
    if String.sub hay i nl = needle then incr n
  done;
  !n

(* Hostile in EVERY position the data can occupy. A fixture that is hostile in
   only some fields lets a mutant survive in the others — that is how MUT-SLO-2
   and MUT-QUERY-1 first came back "equivalent" when they were not. *)
let evil = "<script>alert(1)</script>\"&'"

let meta : W.meta =
  { id = "x"; status = "published"; last_verified = ""; verified_by = ""; next_review = "";
    ntype = "note"; has_frontmatter = false; allow_example_links = false }

let page ~slug ~title ~group : W.page =
  { path = "docs/x.md"; slug; title; group; html = ""; outlinks = []; backlinks = [];
    tags = []; mentions = []; back_ctx = []; typed = []; raw = ""; meta }

let pages =
  [ page ~slug:"good" ~title:"Good Note" ~group:"harness-wiki";
    page ~slug:evil ~title:evil ~group:evil ]

(* Every field of the memory page comes from OUTSIDE the program — commit
   subjects from git, slice names/verdicts/notes/OODA content/baselines from
   SQLite — so every field is hostile here. *)
let memory_fixture : W.memory =
  { head = evil;
    commits = [ ("deadbeef", evil) ];
    cycles = [ (evil, evil, evil, evil) ];
    frontier = [ (evil, evil, 42) ];
    ooda = [ (evil, evil, evil) ];
    baselines = [ (evil, evil) ] }

let run () : (string * bool) list =
  let out = ref [] in
  let check name ok = out := (name, ok) :: !out in

  (* ---- the shell ---------------------------------------------------------
     Every wiki page passes through it, so a slip here affects the whole wiki
     rather than one view. Titles, slugs and group names come from
     frontmatter and filenames: DATA, not literals. *)
  let nav = W.nav_html ~cur:"good" pages in
  check "LAW NAV-ESCAPING: hostile title/slug/group cannot inject markup"
    ((not (contains nav "<script>alert")) && contains nav "&lt;script&gt;alert");
  (* Non-vacuity: the hostile page must be RENDERED, escaped, not dropped. *)
  check "GUARD NON-VACUOUS: the hostile page appears in the nav, escaped"
    (contains nav "&lt;script&gt;alert" && contains nav "Good Note");
  check "LAW NAV-CURRENT: exactly the current slug carries the cur class"
    (count_sub nav "class=\"cur\"" = 1);

  let body = "<p>rendered by the markdown layer</p>" in
  let frame = W.page_frame ~title:evil ~cur:"good" ~pages ~body in
  (* Standards mode, so the grid layout lays out. A quirks-mode regression
     once collapsed the content pane entirely. *)
  check "LAW FRAME-WELL-FORMED: standards-mode doctype and a closed document"
    (String.length frame > 15
    && String.sub frame 0 15 = "<!DOCTYPE html>"
    && contains frame "</html>");
  (* <base href="/docs/"> so relative links resolve whether the URL is /docs
     or /docs/<slug>.html. Without it the index's links resolved at the ROOT
     and 404'd. *)
  check "LAW FRAME-BASE: the document carries base href=\"/docs/\""
    (contains frame "<base href=\"/docs/\"");
  check "LAW FRAME-TITLE-ESCAPED: a hostile page title cannot escape <title>"
    (contains frame "&lt;script&gt;alert" && not (contains frame "<title><script>"));
  (* The documented limit, asserted so nobody mistakes the shell's guarantee
     for the page's: a string body is only as safe as its own escaping. *)
  check "LAW BODY-SEAM: the pre-rendered body is embedded verbatim, not escaped"
    (contains frame body);

  (* ---- the zkquery console ------------------------------------------------
     `q` is a GET PARAMETER, so it is the most directly attacker-controlled
     string in the module. It reaches the page twice — a form `value=`
     attribute and, on a parse failure, an error message. Attribute context is
     the sharper of the two: breaking out of `value="…"` needs no `<` at all. *)
  let hostile_q = "\" autofocus onfocus=alert(1) x=\"" in
  let qp = W.render_query_page pages hostile_q in
  (* Two earlier attempts at this law were both too clever and both PASSED
     while a mutant injected: first a disjunction satisfied by any `&quot;`
     anywhere on the page, then an attribute reader that returned "" when the
     value itself began with a quote. The unambiguous statement needs no
     parsing at all — if the payload appears VERBATIM, it was not escaped. *)
  check "LAW QUERY-ATTR-ESCAPING: the hostile query never appears verbatim"
    (not (contains qp hostile_q));
  check "GUARD NON-VACUOUS: the query is echoed into the form, escaped"
    (contains qp "onfocus=alert(1)" && contains qp "&quot;");
  let qerr = W.render_query_page pages "from <script>alert(1)</script>" in
  check "LAW QUERY-ERROR-ESCAPING: a parse-error message cannot inject markup"
    (not (contains qerr "<script>alert"));

  (* ---- the graph page -----------------------------------------------------
     Renders every note's title and slug three times over — hubs table, edge
     list, orphan chips — so one missed escape appears in triplicate. The
     fixture's hostile page is an orphan, which puts it in the chip list. *)
  let gp = W.render_graph pages in
  check "LAW GRAPH-ESCAPING: hostile titles cannot inject through hubs/edges/orphans"
    ((not (contains gp "<script>alert")) && contains gp "&lt;script&gt;alert");
  check "GUARD NON-VACUOUS: the graph page lists the notes it is escaping"
    (contains gp "Good Note" && contains gp "Zettelkasten graph");

  (* ---- the system-memory page --------------------------------------------
     The widest external-data surface in the module: git subjects and five
     SQLite tables, previously escaped at twenty separate call sites. *)
  let mp = W.render_memory ~pages memory_fixture in
  check "LAW MEMORY-ESCAPING: git and SQLite text cannot inject markup"
    ((not (contains mp "<script>alert")) && contains mp "&lt;script&gt;alert");
  (* Non-vacuity, stated per SECTION: a page that rendered only its heading
     would satisfy the law above. Every section must be present, and the
     criticality — the one non-string field — must reach the table. *)
  check "GUARD NON-VACUOUS: all five memory sections render their hostile rows"
    (contains mp "Recent commits" && contains mp "Closed cycles"
    && contains mp "Frontier" && contains mp "Decisions"
    && contains mp "Accepted baselines" && contains mp "deadbeef"
    && contains mp "<td>42</td>");
  (* The four optional sections are CONDITIONAL on having rows; "Closed
     cycles" is unconditional and states its own zero. Rendering an empty
     section is not cosmetic here — an empty Frontier heading claims the
     backlog was consulted and found empty, which is a different fact from
     "not consulted". *)
  let empty = W.render_memory ~pages W.empty_memory in
  check "LAW MEMORY-SECTIONS-CONDITIONAL: empty sources render no section heading"
    ((not (contains empty "Recent commits")) && (not (contains empty "Frontier"))
    && (not (contains empty "Decisions")) && (not (contains empty "Accepted baselines"))
    && contains empty "Closed cycles");
  (* The page is built as ELEMENTS and handed to `page_frame_elts`, so it
     carries no `Unsafe.data` seam of its own — but a caller could still hand
     it a broken frame. Pin the frame invariants for this page too. *)
  (* ---- the authoring forms and metadata fragments -------------------------
     The edit form is the one place the wiki writes note content back INTO an
     element rather than reading it out, so it is where double-escaping shows
     up: TyXML escapes textarea content itself, and keeping the old `esc_s`
     would render `&amp;lt;` where the note has `<`. Converting means DELETING
     the escaper, not carrying it across — and that is a silent corruption,
     not a crash, so it needs its own law. *)
  (* Hostile in the META fields too. The first version of this fixture reused
     the benign `meta` above, so `LAW META-ESCAPING` failed on its own
     non-vacuity clause — there was nothing to escape. A fixture that is
     hostile in only some fields is how a mutant survives in the others. *)
  let hostile_meta : W.meta =
    { id = evil; status = evil; last_verified = evil; verified_by = evil;
      next_review = evil; ntype = evil; has_frontmatter = false;
      allow_example_links = false }
  in
  let authored : W.page =
    { (page ~slug:evil ~title:evil ~group:evil) with
      path = "docs/zk/" ^ evil;
      raw = "# Heading\n\nbody text with <angle> and & ampersand\n\n#tag";
      tags = [ evil ];
      meta = hostile_meta }
  in
  let ef = W.render_edit_form ~pages authored in
  check "LAW EDIT-NO-DOUBLE-ESCAPE: note content is escaped exactly once"
    (contains ef "&lt;angle&gt;" && (not (contains ef "&amp;lt;"))
    && contains ef "&amp; ampersand" && not (contains ef "&amp;amp;"));
  check "LAW EDIT-ESCAPING: hostile title, path and tags cannot inject markup"
    ((not (contains ef "<script>alert")) && contains ef "&lt;script&gt;alert");
  (* Non-vacuity: the body must actually reach the textarea. A form that
     dropped it would satisfy both laws above. *)
  check "GUARD NON-VACUOUS: the edit form is pre-filled with the note body"
    (contains ef "body text with" && contains ef "Save changes");

  (* The new-note form documents its filename shape with `<id>` and `<slug>`
     as literal TEXT. As a string literal those had to be hand-written as
     entities; typed, they cannot silently become empty elements. *)
  let nf = W.render_new_form pages in
  check "LAW FORM-PLACEHOLDER-TEXT: the filename shape renders as visible text"
    (contains nf "docs/zk/&lt;id&gt;-&lt;slug&gt;.md" && not (contains nf "<id>"));

  (* The metadata panel builds a class from the note's own `status` and a
     custom `data-review` attribute — both concatenation sites before. *)
  let mpanel = W.render_meta_panel authored in
  check "LAW META-ESCAPING: status, type and id cannot inject through the panel"
    ((not (contains mpanel "<script>alert")) && contains mpanel "&lt;script&gt;alert");
  let card = W.zettel_card authored in
  check "LAW CARD-ESCAPING: a hostile slug cannot inject through the zettel card"
    ((not (contains card "<script>alert")) && contains card "&lt;script&gt;alert");
  check "GUARD NON-VACUOUS: the card still reports its counts"
    (contains card "words" && contains card "linked");

  (* ---- the report pages ---------------------------------------------------
     Tags, the index, and the two harness-fed report pages. Their rows arrive
     from SQLite as raw tuples, so every field is hostile here for the same
     reason the memory page's are. *)
  (* `authored` carries a hostile TAG; the base fixture has none, and the first
     version of this law used it — so the page correctly rendered its empty
     state and the non-vacuity clause was false. The page was right and the
     fixture was wrong, which is the same shape as the META fixture above. *)
  let tp = W.render_tags (pages @ [ authored ]) in
  check "LAW TAGS-ESCAPING: a hostile tag or note title cannot inject markup"
    ((not (contains tp "<script>alert")) && contains tp "&lt;script&gt;alert");
  check "GUARD NON-VACUOUS: the tags page renders its chips"
    (contains tp "Tags" && contains tp "zk-chips");

  let ip = W.render_index pages in
  check "LAW INDEX-ESCAPING: hostile titles, groups and paths cannot inject markup"
    ((not (contains ip "<script>alert")) && contains ip "&lt;script&gt;alert");
  check "GUARD NON-VACUOUS: the index renders its cards and its heading"
    (contains ip "zigvm documentation" && contains ip "idx-card");

  let smt =
    W.render_smt_page pages
      ~rows:[ (evil, evil, evil, evil, evil, evil, evil, evil, evil) ]
  in
  check "LAW SMT-ESCAPING: solver-evidence rows cannot inject markup"
    ((not (contains smt "<script>alert")) && contains smt "&lt;script&gt;alert");
  (* The verdict drives a CLASS, and anything that is not exactly "green" must
     read red — a hostile verdict must not be able to render as passing. *)
  check "LAW SMT-VERDICT-CLASS: a verdict that is not green renders red"
    (contains smt "v-red" && not (contains smt "v-green"));

  let env =
    W.render_envelope_page pages ~muda:evil
      ~rows:[ (evil, evil, evil, evil, evil, evil) ]
  in
  check "LAW ENVELOPE-ESCAPING: envelope history rows cannot inject markup"
    ((not (contains env "<script>alert")) && contains env "&lt;script&gt;alert");
  check "GUARD NON-VACUOUS: the envelope page renders its KPI line and table"
    (contains env "kpi" && contains env "top RPN");

  check "LAW CHIP-ESCAPING: the note chip escapes an unknown slug used as its label"
    (let c = W.chip_of pages evil in
     (not (contains c "<script>alert")) && contains c "&lt;script&gt;alert");

  (* ---- the NOTE page ------------------------------------------------------
     The page a reader actually opens, and the widest fan-in in the module:
     title, group, path, tags, backlink context lines, mention slugs, community
     name and grounded standing all reach it. It keeps TWO named seams — the
     streaming markdown renderer's output and the zkquery console — so the law
     states the guarantee for everything else and does not overclaim. *)
  let np = W.render_page ~pages:(pages @ [ authored ]) authored in
  check "LAW NOTE-PAGE-ESCAPING: title, group, path and tags cannot inject markup"
    ((not (contains np "<script>alert")) && contains np "&lt;script&gt;alert");
  check "GUARD NON-VACUOUS: the note page renders its furniture"
    (contains np "zk-pos" && contains np "Linked references"
    && contains np "crumb" && contains np "zk-tags");
  check "LAW NOTE-PAGE-FRAME: the note page is a standards-mode framed document"
    (String.length np > 15
    && String.sub np 0 15 = "<!DOCTYPE html>"
    && contains np "<base href=\"/docs/\"" && contains np "</html>");

  (* ---- the anomalies and currency pages ----------------------------------
     Both render corpus-derived text through the shared chip; the anomalies
     page also renders discourse-type and lifecycle strings straight from
     frontmatter, which is the hostile surface here. *)
  let ap = W.render_anomalies_page (pages @ [ authored ]) in
  check "LAW ANOMALIES-ESCAPING: corpus-derived slugs and rel-text cannot inject markup"
    ((not (contains ap "<script>alert")) && contains ap "&lt;script&gt;alert");
  check "GUARD NON-VACUOUS: the anomalies page renders its sections"
    (contains ap "Knowledge anomalies" && contains ap "zk-sec");
  let cp = W.render_currency (pages @ [ authored ]) ~vec_counts:[ (evil, 3) ] ~audit:evil in
  check "LAW CURRENCY-ESCAPING: vector keys and the audit stamp cannot inject markup"
    ((not (contains cp "<script>alert")) && contains cp "&lt;script&gt;alert");
  check "GUARD NON-VACUOUS: the currency page renders its vitals"
    (contains cp "Vitals" && contains cp "Reference coverage");

  (* ---- the timeline ------------------------------------------------------
     The only page with an inline SVG built from data: commit hashes reach an
     `href`, a `class`, and a `<title>` tooltip inside the sparkline. SVG has
     its own content model, and a payload that escapes there escapes into the
     document. *)
  let tl =
    W.render_timeline (pages @ [ authored ])
      ~rows:[ (evil, evil, evil, "2026-01-01", "", "") ]
      ~sel:evil
  in
  check "LAW TIMELINE-ESCAPING: commit hashes cannot inject through the SVG or the chips"
    ((not (contains tl "<script>alert")) && contains tl "&lt;script&gt;alert");
  check "GUARD NON-VACUOUS: the timeline renders its sparkline and sections"
    (contains tl "tl-spark" && contains tl "edges alive" && contains tl "Churn hotspots");
  (* Totality: no rows is a legitimate state, not an error, and must still
     render a framed page rather than an empty string. *)
  check "LAW TIMELINE-TOTALITY: an empty history still renders a framed page"
    (let empty_tl = W.render_timeline pages ~rows:[] ~sel:"" in
     String.length empty_tl > 15
     && String.sub empty_tl 0 15 = "<!DOCTYPE html>"
     && contains empty_tl "No mined history");

  (* ---- the JSON data islands ---------------------------------------------
     Two pages embed a JSON payload inside a script element and read it back
     with JSON.parse. That is a different context from element content: HTML
     tokenizes script content before JavaScript sees it, so a slug or title
     containing an end-script tag would close the element and become markup.
     The payload goes through `Json_embed`, so it cannot. *)
  let rp = W.render_random (pages @ [ authored ]) in
  check "LAW RANDOM-ISLAND-INERT: a hostile slug cannot close the data island"
    (let after =
       (* everything from the data island onwards *)
       match String.index_opt rp '{' with Some _ -> rp | None -> rp
     in
     (not (contains after "</script>alert")) && contains rp "zk-all");
  check "GUARD NON-VACUOUS: the island carries the slugs, escaped"
    (contains rp "\\u003c" && contains rp "Serendipity");
  (* THE DISCRIMINATING LAW, and it exists because a mutant taught me the
     previous one did not discriminate. Reverting the island to this module's
     local `jesc` SURVIVED every escaping check — correctly, because `jesc`
     already escapes the left angle bracket, so there was never an injection
     here (unlike agent_workers' `je`, which had none of that). What `jesc` does
     do is FLATTEN a newline, tab or control character to a SPACE, silently
     altering the value. That is the difference the typed encoder actually
     makes, so that is what the law states. *)
  let ctrl_page =
    W.render_random
      [ page ~slug:"a\nb\tc" ~title:"ctrl" ~group:"g" ]
  in
  check "LAW ISLAND-FIDELITY: a control character is escaped, not flattened to a space"
    (contains ctrl_page "a\\nb\\tc" && not (contains ctrl_page "\"a b c\""));
  let gp2 = W.render_graph (pages @ [ authored ]) in
  check "LAW GRAPH-ISLAND-INERT: a hostile title cannot close the graph data island"
    (contains gp2 "fg-data" && contains gp2 "\\u003c"
    && not (contains gp2 "</script>alert"));

  check "LAW MEMORY-FRAME: the memory page is a standards-mode framed document"
    (String.length mp > 15
    && String.sub mp 0 15 = "<!DOCTYPE html>"
    && contains mp "<base href=\"/docs/\"" && contains mp "</html>");

  List.rev !out
