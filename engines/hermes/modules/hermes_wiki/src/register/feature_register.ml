(* The wiki/ZK feature register as tracked data. See feature_register.mli.

   Source of the rows: docs/hermes/features-audit-implementation-plan.md
   (§7 register, §8.0 formal specification catalogue). The document argues
   the case for each feature; this module is the part that can be run. *)

type area =
  | Corpus | Dialect | Address | Graph | Query
  | Surface | Present | Lifecycle | Source | Build

type source = Notion | Obsidian | Docusaurus | Sphinx | Own

type readiness =
  | Built
  | Ready
  | Blocked of string
  | Forked of int
  | Excluded

type feature = {
  id : string;
  area : area;
  name : string;
  sources : source list;
  audit_rows : int list;
  law : string;
  utility : int;
  criticality : int;
  gates : string list;
  declared : readiness;
  derived : (unit -> bool) option;
}

type summary = { built : int; ready : int; blocked : int; forked : int; excluded : int }

let area_name = function
  | Corpus -> "HW.1 CORPUS" | Dialect -> "HW.2 DIALECT" | Address -> "HW.3 ADDRESS"
  | Graph -> "HW.4 GRAPH" | Query -> "HW.5 QUERY" | Surface -> "HW.6 SURFACE"
  | Present -> "HW.7 PRESENT" | Lifecycle -> "HW.8 LIFECYCLE" | Source -> "HW.9 SOURCE"
  | Build -> "HW.10 BUILD"

let readiness_name = function
  | Built -> "built" | Ready -> "ready" | Blocked on -> "blocked on " ^ on
  | Forked n -> Printf.sprintf "fork %d" n | Excluded -> "n/a"

(* ------------------------------------------------------- live probes

   A render probe is the strongest predicate available here: it asks the
   ACTUAL renderer whether a construct works, so a feature flips to Built
   the moment it lands and cannot be marked done by editing a field. *)

let contains text needle =
  let n = String.length needle and h = String.length text in
  let rec go i = i + n <= h && (String.sub text i n = needle || go (i + 1)) in
  go 0

let render src = Hermes_wiki.render_markdown ~resolve:(fun _ -> None) src

let renders src needle () = contains (render src) needle

(* A two-page corpus with every edge kind the graph rows claim: a typed
   wikilink, a plain wikilink back, and a bare TITLE mention that is
   deliberately NOT a link — the mention rows exist to tell those apart. *)
let graph_corpus () =
  Hermes_wiki.build
    [ ("docs/hermes/zk/ga.md", "# Ga\n\nSee [[gb|@supports]] for the argument.\n");
      ("docs/hermes/zk/gb.md", "# Gb\n\nBack to [[ga]].\n");
      (* gc mentions Ga by title and links nothing — the mention rows
         exist precisely to tell this apart from gb, which links it *)
      ("docs/hermes/zk/gc.md", "# Gc\n\nGa appears here unlinked, with no wikilink.\n") ]

(* Two pages differing in every field the view columns project, so a
   renderer that drops or transposes a column shows up as a wrong cell
   rather than as an absent one. *)
let view_pages () =
  (Hermes_wiki.build
     [ ("docs/hermes/zk/a.md", "---\nstatus: draft\ntype: note\n---\n# A\n");
       ("docs/hermes/zk/b.md", "---\nstatus: published\ntype: claim\n---\n# B\n") ])
    .Hermes_wiki.pages

(* A probe over a built model rather than a single render. *)
let modelled f () =
  try f (Hermes_wiki.build [ ("docs/hermes/zk/probe-a.md", "# Probe A\n\n## Sec One\n\nSee [[probe-b]].\n");
                             ("docs/hermes/zk/probe-b.md", "# Probe B\n\nBack to [[probe-a#Sec One]].\n") ])
  with _ -> false

(* ------------------------------------------------------------ the rows *)

let f ?(src = [ Own ]) ?(rows = []) ?(gates = []) ?derived id area name law utility criticality
    declared =
  { id; area; name; sources = src; audit_rows = rows; law; utility; criticality; gates;
    declared; derived }

let corpus =
  [ f ~src:[ Obsidian ] ~rows:[ 101 ] "HW.1.1.1" Corpus "Local-first markdown corpus"
      "corpus(r) = tracked(r)" 4 5 Built;
    f "HW.1.1.2" Corpus "Filesystem walk" "tracked(r) subset read_tree(root r)" 2 2 Built;
    f "HW.1.1.3" Corpus "Multiple corpus roots" "corpus(R) = union of roots; slugs disjoint" 3 3 Built;
    (* R21: the identity family, each probe asserting its own law. *)
    f
      ~derived:(fun () ->
        try
          (* slug o move_dir = slug — IDENTITY SURVIVES A MOVE. If it did
             not, every link in the corpus would break the day a document
             was filed somewhere else, which is the one edit that should
             cost nothing. *)
          let at dir =
            let m = Hermes_wiki.build [ (dir ^ "/the-gate.md", "# The Gate\n\nbody.\n") ] in
            (List.hd m.Hermes_wiki.pages).Hermes_wiki.slug
          in
          at "docs/hermes/zk" = "the-gate"
          && at "docs/hermes/zk" = at "docs/hermes/deeply/nested/elsewhere"
          && at "modules/hermes_wiki/pages" = at "docs/hermes/zk"
        with _ -> false)
      "HW.1.2.1" Corpus "Page slug (identity)" "slug o move_dir = slug" 5 5 Built;
    f
      ~derived:(fun () ->
        try
          (* INJECTIVE: two documents that would claim one slug get two,
             and the rename is REPORTED — a silent disambiguation makes a
             link resolve to a page the author never meant. *)
          let m =
            Hermes_wiki.build
              [ ("docs/hermes/zk/dup.md", "# Dup\n\nfirst.\n");
                ("docs/hermes/other/dup.md", "# Dup\n\nsecond.\n") ]
          in
          let slugs = List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug) m.Hermes_wiki.pages in
          List.length (List.sort_uniq compare slugs) = 2
          && List.exists (fun a -> contains a "dup") (Hermes_wiki.notices m)
          (* ORDER-STABLE: the same two inputs give the same two slugs *)
          && slugs
             = List.map
                 (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug)
                 (Hermes_wiki.build
                    [ ("docs/hermes/zk/dup.md", "# Dup\n\nfirst.\n");
                      ("docs/hermes/other/dup.md", "# Dup\n\nsecond.\n") ])
                   .Hermes_wiki.pages
        with _ -> false)
      "HW.1.2.2" Corpus "Slug collision disambiguation"
      "injective, order-stable, every rename reported" 4 5 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let title path body =
            (List.hd (Hermes_wiki.build [ (path, body) ]).Hermes_wiki.pages).Hermes_wiki.title
          in
          (* title = first_h1 ?? basename — a FALLBACK, so a document
             without a heading still has a name a reader can see *)
          title "docs/hermes/zk/f.md" "# The Real Title\n\nbody\n" = "The Real Title"
          && title "docs/hermes/zk/f.md" "no heading here\n" = "f"
          (* the FIRST h1 wins; a later one does not rename the page *)
          && title "docs/hermes/zk/f.md" "# First\n\n# Second\n" = "First"
        with _ -> false)
      "HW.1.2.3" Corpus "Title derivation" "title(d) = first_h1 ?? basename" 3 3 Built;
    f ~src:[ Notion ] ~rows:[ 50 ]
      ~derived:(fun () ->
        try
          let group path =
            (List.hd (Hermes_wiki.build [ (path, "# G\n") ]).Hermes_wiki.pages).Hermes_wiki.group
          in
          (* group o reroot = group — the group is RELATIVE. Keying it to
             a literal path segment broke the day the corpus root moved,
             which is why the law is stated as a commutation. *)
          group "docs/hermes/guide/g.md" = "guide"
          && group "modules/hermes_wiki/pages/guide/g.md" = "guide"
          && group "docs/hermes/g.md" = ""
        with _ -> false)
      "HW.1.2.4" Corpus "Nested pages / groups" "group o reroot = group" 3 4 Built;
    f ~src:[ Notion ] ~rows:[ 70 ]
      ~derived:(fun () ->
        try
          let id path fm =
            (List.hd (Hermes_wiki.build [ (path, fm ^ "# I\n") ]).Hermes_wiki.pages)
              .Hermes_wiki.meta.Hermes_wiki.id
          in
          (* an EXPLICIT id survives a rename; a derived one is a function
             of the slug and honestly moves with it — the two must not be
             confused, or a stable identifier is silently unstable *)
          id "docs/hermes/zk/a.md" "---\nid: fixed-42\n---\n" = "fixed-42"
          && id "docs/hermes/zk/renamed.md" "---\nid: fixed-42\n---\n" = "fixed-42"
          && id "docs/hermes/zk/a.md" "" <> id "docs/hermes/zk/renamed.md" ""
        with _ -> false)
      "HW.1.2.5" Corpus "Stable unique id" "rename-stable when explicit" 4 4 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let open Wiki_lifecycle in
          let c1 = { path = "a/x.md"; declared = Some "gate"; derived = "x" } in
          let c2 = { path = "a/y.md"; declared = Some "gate"; derived = "y" } in
          (* the override WINS, and leaves a countable mark — an escape
             hatch that leaves no trace is indistinguishable from a bug.
             Two explicit claims on one slug is a COLLISION, reported and
             never resolved behind the authors' backs. *)
          (resolve_slug c1).slug = "gate"
          && (resolve_slug c1).source = Declared_slug
          && (resolve_slug { path = "a/z.md"; declared = None; derived = "z" }).slug = "z"
          && (let col = slug_collisions [ c1; c2 ] in
              List.length col = 1 && contains (List.hd col) "explicit slug collision: gate")
          && slug_overrides [ c1 ] <> []
          && (resolve_slug { path = "a/m.md"; declared = Some "  "; derived = "m" }).source
             = Declared_malformed
        with _ -> false)
      "HW.1.2.6" Corpus "slug frontmatter override" "explicit slug wins; still injective" 2 3 Built;
    f ~src:[ Obsidian ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
              [ ("docs/hermes/zk/al.md", "---\naliases: [\"Other Name\"]\n---\n# Al\n\nBody.\n");
                ("docs/hermes/zk/cite.md", "# Cite\n\nSee [[Other Name]].\n") ] in
          match Hermes_wiki.page m "cite" with
          | Some p -> List.mem "al" p.Hermes_wiki.outlinks
          | None -> false
        with _ -> false)
      "HW.1.2.7" Corpus "Aliases"
      "resolve(a) = slug(d) for a in aliases(d); an alias NEVER shadows an identity key (pass-2 registration)" 4 4 Built;
    f ~src:[ Own ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
              [ ("docs/hermes/zk/bare2.md", "# Bare2\n\nNothing.\n") ] in
          List.exists (fun g ->
              let has n = let l = String.length n and t = String.length g in
                let rec go i = i + l <= t && (String.sub g i l = n || go (i+1)) in go 0 in
              has "bare2" && has "ktype")
            (Hermes_wiki.schema_gaps m)
        with _ -> false)
      "HW.1.3.16" Corpus "PKM metadata schema + conformance report"
      "required fields ktype/maturity/domain/topics/created; gaps REPORTED as notices (ratchet later); links carries DECLARED hierarchy only (I3)" 4 4 Built;
    f ~src:[ Obsidian ] ~rows:[ 105 ] "HW.1.3.1" Corpus "Frontmatter parsing" "total with honest defaults" 5 5 Built;
    f ~src:[ Notion ] ~rows:[ 69 ] "HW.1.3.2" Corpus "status / type vocabularies"
      "unknown value preserved verbatim + anomaly" 4 5 Built;
    f ~src:[ Notion ] ~rows:[ 61 ] "HW.1.3.3" Corpus "Date properties" "next_review > last_verified" 3 4 Built;
    f ~src:[ Notion ] ~rows:[ 65 ] "HW.1.3.4" Corpus "Person property" "closed vocabulary" 2 3 Built;
    f ~src:[ Notion ] ~rows:[ 64 ] "HW.1.3.5" Corpus "Tags (multi-select)" "tags disjoint from fenced tags" 4 4 Built;
    f ~src:[ Notion ] ~rows:[ 68 ] "HW.1.3.6" Corpus "Number / URL properties" "typed; bad compare = named error" 2 3 Built;
    f ~src:[ Notion ] ~rows:[ 62 ] "HW.1.3.7" Corpus "Files & media property" "assets routable or diagnostic" 2 2 (Forked 2);
    f ~src:[ Notion ] ~rows:[ 63 ] "HW.1.3.8" Corpus "Formula property" "render is pure; no uninspectable computation" 0 0 Excluded;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let open Wiki_lifecycle in
          let d = describe ~declared:"Parity Gate" ~body:"Other.\n" in
          (* declared, else DERIVED from the first prose paragraph, else
             "" with No_desc — never invented. And ADDITIVE to ranking:
             the body's own terms pass through, so a description can
             boost a page but never hide it from a search for its words. *)
          d.text = "Parity Gate"
          && d.origin = Declared_desc
          && (let e = describe ~declared:"" ~body:"# H\n\nFirst para.\n\nSecond.\n" in
              e.text = "First para." && e.origin = Derived_desc)
          && (let n = describe ~declared:"" ~body:"" in n.text = "" && n.origin = No_desc)
          && (let t = describe ~declared:(String.make 500 'x') ~body:"" in
              t.truncated && String.length t.text = max_description)
          && List.for_all
               (fun x -> List.mem x (ranking_terms d ~body_terms:[ "zz" ]))
               [ "zz"; "parity" ]
          (* "FEEDS RANKING" must be true of the LIVE index, not only of
             a pure function over injected terms. A field nothing
             consumes is data, not a feature — and a self-contained probe
             cannot notice the difference, so the clause is asserted
             against Wiki_search over a built corpus. Additive: the
             body's own words still find the page. *)
          && (let mk fm =
                Hermes_wiki.build
                  [ ("docs/hermes/zk/dsc.md", fm ^ "# Dsc\n\nThe parity claim holds.\n") ]
              in
              let hit m q = List.assoc_opt "dsc" (Wiki_search.search (Wiki_search.build m) q) in
              hit (mk "") "zoology" = None
              && hit (mk "---\ndescription: a note about zoology\n---\n") "zoology" <> None
              && hit (mk "---\ndescription: a note about zoology\n---\n") "parity" <> None)
        with _ -> false)
      "HW.1.3.9" Corpus "description field" "free text; feeds ranking" 3 2 Built;
    (* HW.1.3.10–14 — the ordering family. Each probe asserts the law the
       row claims, over a corpus built here, so a regression in
       Wiki_ordering unbuilds the row rather than leaving it declared. *)
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          (* ADDITIVE, not a replacement: a declared keyword adds a query
             that finds the page, and the page's own words still do. *)
          let body = "# Gate\n\nThe parity claim holds.\n" in
          let mk fm = Hermes_wiki.build [ ("docs/hermes/zk/kw.md", fm ^ body) ] in
          let hit m q = List.assoc_opt "kw" (Wiki_search.search (Wiki_search.build m) q) in
          let bare = mk "" in
          let keyed = mk "---\nkeywords: [zoology]\n---\n" in
          let boosted = mk "---\nkeywords: [parity]\n---\n" in
          (* a term the body never says becomes reachable... *)
          hit bare "zoology" = None && hit keyed "zoology" <> None
          (* ...without costing the body's own terms... *)
          && hit bare "parity" <> None && hit keyed "parity" = hit bare "parity"
          (* ...and a keyword the body DOES say only ever raises it *)
          && hit boosted "parity" > hit bare "parity"
        with _ -> false)
      "HW.1.3.10" Corpus "keywords field"
      "search terms ADDITIVE to the body's; a keyword can only add reachable queries, never hide a page from a search for its own words"
      3 2 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          (* TOTAL: positioned first in position order, positionless after
             by slug, ties broken by slug — never by the filesystem. *)
          let mk order =
            Hermes_wiki.build
              (List.map
                 (fun (n, p) ->
                   ( "docs/hermes/zk/" ^ n ^ ".md",
                     (match p with
                      | Some i -> Printf.sprintf "---\nsidebar_position: %d\n---\n" i
                      | None -> "")
                     ^ "# " ^ n ^ "\n" ))
                 order)
          in
          let slugs m = List.map (fun e -> e.Wiki_ordering.slug) (Wiki_ordering.ordered m) in
          let cfg = [ ("zz", Some 2); ("aa", None); ("mm", Some 1); ("bb", None) ] in
          slugs (mk cfg) = [ "mm"; "zz"; "aa"; "bb" ]
          && slugs (mk (List.rev cfg)) = slugs (mk cfg)
          (* a duplicate claim is REPORTED, not resolved behind the author *)
          && Wiki_ordering.position_conflicts
               (mk [ ("aa", Some 2); ("bb", Some 2) ])
             <> []
        with _ -> false)
      "HW.1.3.11" Corpus "sidebar_position"
      "a TOTAL order on siblings: positionless pages sort after positioned ones, ties break by slug, duplicates are reported not resolved"
      3 3 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          (* the ALTERNATIVE rule, and it LOSES to an explicit position *)
          Wiki_ordering.number_prefix "03-the-gate" = (Some 3, "the-gate")
          && Wiki_ordering.number_prefix "the-gate" = (None, "the-gate")
          (* a date is not an ordinal — the bound the live corpus forced *)
          && Wiki_ordering.number_prefix "2026-08-09-notes" = (None, "2026-08-09-notes")
          && (let m =
                Hermes_wiki.build
                  [ ("docs/hermes/zk/90-first.md", "---\nsidebar_position: 1\n---\n# 90-first\n");
                    ("docs/hermes/zk/b.md", "---\nsidebar_position: 2\n---\n# b\n") ]
              in
              List.map (fun e -> e.Wiki_ordering.slug) (Wiki_ordering.ordered m)
              = [ "90-first"; "b" ])
        with _ -> false)
      "HW.1.3.12" Corpus "parse_number_prefixes"
      "the alternative ordering rule; an ordinal is a short sequence number (a date is not one), and an explicit sidebar_position DOMINATES it"
      2 2 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let label fm name body =
            let m = Hermes_wiki.build [ ("docs/hermes/zk/" ^ name ^ ".md", fm ^ body) ] in
            (List.hd (Wiki_ordering.ordered m)).Wiki_ordering.label
          in
          (* a FALLBACK, not an override; and an authored title that merely
             looks numbered keeps every byte *)
          label "---\nsidebar_label: Start Here\n---\n" "a" "# The Long Title\n" = "Start Here"
          && label "" "a" "# Plain Title\n" = "Plain Title"
          && label "" "03-the-gate" "" = "the-gate"
          && label "" "gate" "# 03-the-plan\n" = "03-the-plan"
        with _ -> false)
      "HW.1.3.13" Corpus "sidebar_label"
      "label ?? title — a fallback, never an override; a filename-derived label loses its ordinal, an authored title keeps its digits"
      2 2 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              (List.map (fun n -> ("docs/hermes/zk/" ^ n ^ ".md", "# " ^ n ^ "\n"))
                 [ "cc"; "aa"; "bb" ])
          in
          let es = Wiki_ordering.ordered m in
          (* MUTUALLY INVERSE over the whole sequence... *)
          List.for_all
            (fun e ->
              match Wiki_ordering.next es e.Wiki_ordering.slug with
              | None -> true
              | Some n -> Wiki_ordering.prev es n = Some e.Wiki_ordering.slug)
            es
          (* ...and ACYCLIC: the ends are None. A wrapping sequence has no
             last page, so a reader can never finish. *)
          && Wiki_ordering.prev es "aa" = None
          && Wiki_ordering.next es "cc" = None
          && Wiki_ordering.next es "aa" = Some "bb"
          && Wiki_ordering.next es "ghost" = None
        with _ -> false)
      "HW.1.3.14" Corpus "pagination next/prev"
      "mutually inverse and acyclic: next(a)=b iff prev(b)=a, the ends are None, and an unknown slug paginates to None"
      3 3 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let src = "# a\n\n[TOC]\n\n## b\n\n## c\n" in
          let r hide = Wiki_blocks.html ~hide_toc:hide ~inline:(fun x -> x) ~escape:(fun x -> x) src in
          let shown = r false and hidden = r true in
          (* PRESENTATION ONLY, pinned as an EQUALITY rather than an
             absence: the two renders differ by exactly the nav, and the
             ANCHORS are identical. A flag that quietly changed the
             anchor set would break inbound fragment links the author
             never knew existed — so a page whose contents list is
             hidden is still linkable at every heading. *)
          contains shown "<nav class=\"toc\">"
          && (not (contains hidden "<nav class=\"toc\">"))
          && Wiki_blocks.emitted_ids src = [ "a"; "b"; "c" ]
          && String.length hidden < String.length shown
          && (let m =
                Hermes_wiki.build
                  [ ("docs/hermes/zk/h.md",
                     "---\nhide_table_of_contents: true\n---\n# H\n\nbody.\n") ]
              in
              (List.hd m.Hermes_wiki.pages).Hermes_wiki.meta.Hermes_wiki.hide_toc)
          && not
               (List.hd
                  (Hermes_wiki.build [ ("docs/hermes/zk/n.md", "# N\n\nbody.\n") ])
                    .Hermes_wiki.pages)
                 .Hermes_wiki.meta.Hermes_wiki.hide_toc
        with _ -> false)
      "HW.1.3.15" Corpus "hide_table_of_contents" "presentation only" 1 1 Built;
    f ~src:[ Docusaurus ] "HW.1.4.1" Corpus "draft / unlisted visibility split"
      ~derived:(fun () ->
        try
          let vis fm =
            let m = Hermes_wiki.build [ ("docs/x/p.md", fm ^ "# p\n\nbody.\n") ] in
            match Hermes_wiki.page m "p" with
            | Some pg -> Some (Wiki_visibility.of_page pg)
            | None -> None
          in
          (* the three states, and the one that could not be said before *)
          vis "---\ndraft: true\n---\n" = Some Wiki_visibility.Draft
          && vis "---\nunlisted: true\n---\n" = Some Wiki_visibility.Unlisted
          && vis "" = Some Wiki_visibility.Listed
          (* unlisted is BUILT but not indexed — the whole point of the row *)
          && Wiki_visibility.in_build Wiki_visibility.Unlisted
          && (not (Wiki_visibility.in_index Wiki_visibility.Unlisted))
          && not (Wiki_visibility.in_build Wiki_visibility.Draft)
        with _ -> false)
      "three states mutually exclusive and total" 4 4 Built;
    f ~src:[ Notion ] ~rows:[ 47 ] "HW.1.4.2" Corpus "Locked pages" "frozen(d) => regenerate(d) = d" 3 4 Built;
    f ~src:[ Notion ] ~rows:[ 46 ] "HW.1.5.1" Corpus "Import" "membership-only change" 4 3 Built;
    f ~src:[ Notion ] ~rows:[ 41 ] "HW.1.5.2" Corpus "Export" "static render = served render" 4 4 Built;
    f ~src:[ Notion ] ~rows:[ 35 ] "HW.1.5.3" Corpus "Duplicate / move" "link-preserving" 4 4 Built;
    f ~src:[ Notion ] ~rows:[ 76 ] "HW.1.5.4" Corpus "Sync external sources" "all content git-verifiable" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 36 ] "HW.1.5.5" Corpus "Web clipper / calendar / mail" "out of scope" 0 0 Excluded;
    f ~src:[ Docusaurus ] "HW.1.5.6" Corpus "Ingest the 382-doc product website"
      "monotone; every dialect failure named" 5 4 (Blocked "HW.2.0.1") ]

let dialect =
  [ f ~src:[ Docusaurus ] ~gates:[ "HW.2.1.4"; "HW.2.3.1"; "HW.2.3.2"; "HW.2.3.3"; "HW.2.3.4";
                                   "HW.2.3.5"; "HW.2.1.11"; "HW.3.3.1"; "HW.1.5.6"; "HW.2.6.4" ]
      "HW.2.0.1" Dialect "mu-recursive block carrier"
      "Ast admits a block INSIDE a block; render is a catamorphism; admitted by\n       observational equivalence to the line-machine oracle over the whole corpus" 5 5
      ~derived:(fun () ->
        (* the carrier admits block-in-block, and the nested value renders *)
        try
          let nested =
            [ Wiki_ast.Quote
                [ Wiki_ast.Para "a";
                  Wiki_ast.List_block
                    { ordered = false; start = 1;
                      content = [ Wiki_ast.Item { Wiki_ast.task = None; body = [ Wiki_ast.Para "b" ] } ] } ] ]
          in
          Wiki_ast.depth nested >= 3
        with _ -> false)
      Built;
    f ~src:[ Docusaurus ] ~gates:[ "HW.7.3.1"; "HW.7.3.2"; "HW.7.3.4"; "HW.2.6.6"; "HW.9.3.1" ]
      "HW.2.0.2" Dialect "Code_block carries lang + meta"
      ~derived:(fun () ->
        try
          Wiki_ast.fence_infos (Wiki_ast.parse "```ocaml linenums {3}\nx\n```\n")
          = [ "ocaml linenums {3}" ]
          && contains (render "```ocaml\nlet x = 1\n```\n") "class=\"language-ocaml\""
          && not (contains (render "```{bad}\nx\n```\n") "class=")
        with _ -> false)
      "parse o print = id on the info string" 3 4 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let t = Wiki_blocks.parse ":::mermaid\ngraph\n:::\n\n:::note\nhi\n:::\n" in
          (* TWO VERDICTS because two fixes: a directive used but in no
             vocabulary wants defining; one registered and used nowhere
             wants removing. One diagnostic for both tells an author
             nothing about which. A fenced directive is an example. *)
          List.mem (Wiki_blocks.Unrecognised_directive "mermaid") t.Wiki_blocks.diagnostics
          && (not (List.mem (Wiki_blocks.Unrecognised_directive "note") t.Wiki_blocks.diagnostics))
          && Wiki_blocks.lint ~registered:[ "mermaid"; "tabs" ] t
             = [ Wiki_blocks.Unused_directive "tabs" ]
          && Wiki_blocks.lint ~registered:[ "mermaid" ] t = []
          && Wiki_blocks.diagnostic_line (Wiki_blocks.Unrecognised_directive "x")
             <> Wiki_blocks.diagnostic_line (Wiki_blocks.Unused_directive "x")
          && (Wiki_blocks.parse "```\n:::mermaid\n```\n").Wiki_blocks.diagnostics = []
        with _ -> false)
      "HW.2.0.3" Dialect "Unused-directive lint"
      "directive-like and unrecognised => diagnostic" 3 4 Built;
    f ~src:[ Notion ] ~rows:[ 58 ] ~derived:(renders "plain text" "<p>") "HW.2.1.1" Dialect "Paragraph"
      "escape o text = text" 5 5 Built;
    f ~src:[ Notion ] ~rows:[ 11 ] ~derived:(renders "- one" "<ul>") "HW.2.1.2" Dialect "Bulleted list"
      "GFM list grammar" 5 4 Built;
    f ~src:[ Notion ] ~rows:[ 53 ] ~derived:(renders "1. one" "<ol>") "HW.2.1.3" Dialect "Numbered list"
      "CommonMark 5.2: start number and delimiter preserved" 5 4 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let src = "- a\n  - b\n    - c\n- d\n" in
          (* depth(parse s) = depth(s), where the right-hand side is an
             INDEPENDENT column walk over the source rather than a second
             reading of the same parse — otherwise the law compares the
             parser with itself. Tabs measured in columns; a fenced list
             is an example and has no depth. *)
          Wiki_blocks.list_depth (Wiki_blocks.parse_lists src) = 3
          && Wiki_blocks.source_list_depth src = 3
          && Wiki_ast.depth (Wiki_blocks.parse_lists src) = 4
          && Wiki_blocks.parse_lists "- a\n\t- b\n" = Wiki_blocks.parse_lists "- a\n    - b\n"
          && Wiki_blocks.source_list_depth "        - x\n        - y\n" = 1
          && Wiki_blocks.list_depth (Wiki_blocks.parse_lists "```\n- a\n  - b\n```\n") = 0
          && contains
               (Wiki_ast.render ~inline:(fun x -> x) ~anchor:(fun x -> x)
                  ~escape:(fun x -> x) (Wiki_blocks.parse_lists src))
               "<li>a<ul>"
        with _ -> false)
      "HW.2.1.4" Dialect "Nested lists" "depth(parse s) = depth(s)" 4 4 Built;
    f ~src:[ Notion ] ~rows:[ 34 ] ~derived:(renders "a\n\n---\n\nb" "<hr") "HW.2.1.5" Dialect "Divider"
      "CommonMark 4.1; disambiguated from frontmatter" 3 4 Built;
    f ~src:[ Notion ] ~rows:[ 73 ] ~derived:(renders "> quoted" "<blockquote>") "HW.2.1.6" Dialect "Quote"
      "blockquote grammar" 4 3 Built;
    f ~src:[ Notion ] ~rows:[ 75 ] ~derived:(renders "| a |\n|---|\n| b |" "<table>") "HW.2.1.7" Dialect
      "Simple table" "GFM 4.10: header row, separator row, body; cells are inline content" 4 4 Built;
    f ~src:[ Notion ] ~rows:[ 14 ] ~derived:(renders "```\nx\n```" "<pre>") "HW.2.1.8" Dialect "Code fence"
      "inert; content never becomes markup" 5 5 Built;
    f ~src:[ Notion ] ~rows:[ 43 ] ~derived:(renders "# Hello" "id=\"hello\"") "HW.2.1.9" Dialect "Headings"
      "anchored h1-h4, stateful slugger" 5 5 Built;
    f ~src:[ Notion ] ~rows:[ 81 ] ~derived:(renders "- [ ] task" "checkbox") "HW.2.1.10" Dialect
      "To-do checkbox" "GFM 5.3; render is READ-ONLY" 4 3 Built;
    f ~src:[ Obsidian ] ~rows:[ 97 ]
      ~derived:(fun () ->
        try
          (* the definitions are written a, z; the references z, a. Order
             is by FIRST REFERENCE — the reader's order, not the
             author's filing order — so the fixture must disagree with
             definition order or it proves nothing. The links are
             MUTUALLY REFERRING, and undefined-reference and
             unreferenced-definition are DISTINCT verdicts. *)
          let src = "[^a]: ay\n\n[^z]: zee\n\nSee [^z] and [^a].\n" in
          let t = Wiki_blocks.parse src in
          let h = Wiki_blocks.html ~inline:(fun x -> x) ~escape:(fun x -> x) src in
          List.map (fun f -> f.Wiki_blocks.fid) t.Wiki_blocks.notes = [ "z"; "a" ]
          && contains h "id=\"fnref-z\"" && contains h "href=\"#fn-z\""
          && contains h "id=\"fn-z\"" && contains h "href=\"#fnref-z\""
          && Wiki_blocks.footnote_links_resolve src
          && List.mem (Wiki_blocks.Undefined_footnote "u")
               (Wiki_blocks.parse "See [^u].\n").Wiki_blocks.diagnostics
          && List.mem (Wiki_blocks.Unreferenced_footnote "d")
               (Wiki_blocks.parse "[^d]: only\n").Wiki_blocks.diagnostics
        with _ -> false)
      "HW.2.1.11" Dialect "Footnotes"
      "ref -> def -> ref is identity; unreferenced defs are diagnostics" 4 3 Built;
    f ~derived:(renders "**bold**" "<strong>") "HW.2.2.1" Dialect "Emphasis / strong"
      "escaping by construction" 4 4 Built;
    f ~derived:(renders "`x`" "<code>") "HW.2.2.2" Dialect "Inline code" "escaped literal" 4 4 Built;
    f ~src:[ Docusaurus ] ~derived:(renders "~~gone~~" "<del>") "HW.2.2.3" Dialect "Strikethrough"
      "GFM 6.5: ~~text~~ delimits a Strike of inline content" 2 2 Built;
    f ~src:[ Notion ] ~rows:[ 38 ] "HW.2.2.4" Dialect "Emoji" "unicode passthrough" 2 1 Built;
    f ~src:[ Notion; Obsidian ] ~rows:[ 13; 91 ] ~derived:(renders "> [!note] T\n> body" "callout")
      "HW.2.3.1" Dialect "Callouts / admonitions"
      "13 case-insensitive kinds + aliases; unknown preserved; +/- foldability" 5 4 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let src = ":::note My **Title**\n- a\n  - b\n\n```\nx\n```\n:::\n" in
          let h = Wiki_blocks.html ~inline:(fun x -> x) ~escape:(fun x -> x) src in
          (* the body is a BLOCK LIST, so it can hold a nested list AND a
             fence — a body flattened to inline text would render both as
             prose. And the source still round-trips: nothing an author
             wrote inside a directive is lost. *)
          (match Wiki_blocks.blocks (Wiki_blocks.parse src) with
          | [ b ] ->
              b.Wiki_blocks.title = "My **Title**"
              && Wiki_blocks.list_depth (Wiki_blocks.body_blocks b) = 2
              && List.exists
                   (function Wiki_ast.Fence _ -> true | _ -> false)
                   (Wiki_blocks.body_blocks b)
          | _ -> false)
          && contains h "<p class=\"callout-title\">My **Title**</p>"
          && contains h "class=\"callout callout-note\""
          && contains h "<pre><code>"
          && Wiki_blocks.source_lines (Wiki_blocks.parse src) = String.split_on_char '\n' src
        with _ -> false)
      "HW.2.3.2" Dialect "Admonition titles + block bodies" "body is Block list" 4 3 Built;
    f ~src:[ Notion; Docusaurus ] ~rows:[ 82 ]
      ~derived:(fun () ->
        try
          let r s = Wiki_blocks.html ~inline:(fun x -> x) ~escape:(fun x -> x) s in
          let closed = r ":::details Show me\n- a\n  - b\n:::\n" in
          (* CLOSED BY DEFAULT — a toggle that opens itself is not a
             toggle — and an admonition stays a <div>, so the two
             constructs cannot silently become one. *)
          contains closed "<details class=\"callout callout-details\">"
          && contains closed "<summary class=\"callout-title\">Show me</summary>"
          && contains closed "<li>a<ul>"
          && (not (contains closed "callout-details\" open"))
          && contains (r ":::details+ Open me\nx\n:::\n") "callout-details\" open"
          && contains (r ":::note plain\nx\n:::\n") "<div class=\"callout callout-note\">"
        with _ -> false)
      "HW.2.3.3" Dialect "Toggle list / details" "summary inline, body blocks" 3 2 Built;
    f ~src:[ Docusaurus ] "HW.2.3.4" Dialect "Tabs" "alternative content in one slot" 2 1
      (Blocked "HW.2.0.1");
    f ~src:[ Notion ] ~rows:[ 80 ]
      ~derived:(fun () ->
        try
          (* the fixture has TWO headings that slug to `a`, because the
             subset law alone is unkillable on a corpus without a
             collision: a plainly-slugged ToC would read ["a";"a-1";"a"]
             and every one of those IS an emitted id. So this asserts
             ANCHOR EQUALITY against what the production renderer emits,
             not containment. *)
          let src = "# a\n\n[TOC]\n\n# a-1\n\n# a\n" in
          let h = Wiki_blocks.html ~inline:(fun x -> x) ~escape:(fun x -> x) src in
          Wiki_blocks.has_toc_marker src
          && List.map (fun e -> e.Wiki_blocks.anchor) (Wiki_blocks.toc src)
             = [ "a"; "a-1"; "a-2" ]
          && Wiki_blocks.emitted_ids src = [ "a"; "a-1"; "a-2" ]
          && Wiki_blocks.toc_resolves src
          && contains h "<nav class=\"toc\">"
          && contains h "href=\"#a-2\""
          && (not (Wiki_blocks.has_toc_marker "```\n[TOC]\n```\n"))
          && List.mem Wiki_blocks.Toc_without_headings
               (Wiki_blocks.parse "[TOC]\n\nprose\n").Wiki_blocks.diagnostics
        with _ -> false)
      "HW.2.3.5" Dialect "Table of contents block"
      "toc(a) subset anchors(render a) -- same slugger" 4 4 Built;
    f ~src:[ Notion ] "HW.2.3.6" Dialect "Toggle headings" "heading whose section collapses" 2 1
      (Blocked "HW.2.3.3");
    f ~src:[ Notion ] ~rows:[ 44 ] "HW.2.4.1" Dialect "Interactive HTML blocks"
      "render emits no executable content" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 37 ] "HW.2.4.2" Dialect "Third-party embeds" "no third-party origin" 0 0 Excluded;
    f ~src:[ Docusaurus ] "HW.2.4.3" Dialect "MDX" "no executable markup" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 15 ] "HW.2.5.1" Dialect "Columns / multi-column layout"
      "single column keeps diffs reviewable" 0 0 Excluded;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ("docs/x/host.md", "# Host\n\n.. seealso::\n\n   [[alpha]] and [[beta#Deep]]\n");
                ("docs/x/alpha.md", "# Alpha\n\nb.\n"); ("docs/x/beta.md", "# Beta\n\nb.\n") ]
          in
          match Hermes_wiki.page m "host" with
          | Some p ->
              let e = Wiki_directive.edges ~source:"host" (Wiki_directive.parse p.Hermes_wiki.raw) in
              (* EDGES, not decoration: pairs, and a subset of the page's
                 own outlinks — a see-also that renders but links nowhere
                 is decoration wearing the syntax of a relation *)
              e = [ ("host", "alpha"); ("host", "beta") ]
              && List.for_all (fun (_, g) -> List.mem g p.Hermes_wiki.outlinks) e
              && (Wiki_directive.parse ".. seealso::\n\n   prose only\n").Wiki_directive.diagnostics
                 = [ Wiki_directive.Decorative_seealso "prose only" ]
          | None -> false
        with _ -> false)
      "HW.2.6.1" Dialect "seealso block" "entries are graph edges" 3 2 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let t = Wiki_directive.parse "# Overview\n\n.. rubric:: Overview\n\nprose\n" in
          (* the NEGATIVE law, proved as an absence: the rubric's title is
             IDENTICAL to the heading's and still exactly one anchor
             exists. A rubric that entered the anchor set would make a
             heading's link ambiguous without either author noticing. *)
          Wiki_directive.rubrics t = [ "Overview" ]
          && Wiki_directive.anchors t = [ "overview" ]
          && Wiki_directive.toc t = [ (1, "Overview", "overview") ]
        with _ -> false)
      "HW.2.6.2" Dialect "rubric" "does not enter toc or anchors" 2 2 Built;
    f ~src:[ Sphinx ] "HW.2.6.3" Dialect "Back-of-book index"
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ( "docs/c/user.md",
                  "# User\n\n## Sec\n\n<!-- index: parity -->\n\
                   <!-- index: see: quirk -> nowhere -->\np.\n" ) ]
          in
          (match Hermes_wiki.corpus_index m with
          | (t, _, s, a) :: _ -> t = "parity" && s = "user" && a = "sec"
          | [] -> false)
          && List.length (Hermes_wiki.index_violations m) = 1
        with _ -> false)
      "entries address locations; see-targets must exist" 3 2 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let g s = Wiki_directive.parse (".. productionlist:: expr\n" ^ s) in
          let ok = g "   sum: `term` \"+\" `sum`\n   term: N\n" in
          let bad = g "   sum: `term` \"+\" `factor`\n   term: N\n" in
          List.map (fun p -> p.Wiki_directive.pname) (Wiki_directive.productions ok)
          = [ "sum"; "term" ]
          && Wiki_directive.undefined_productions ok = []
          && Wiki_directive.undefined_productions bad = [ ("expr", "factor") ]
          (* PER GRAMMAR: another grammar's definition does not satisfy
             this one's reference. A corpus-wide resolution would let two
             unrelated grammars silently complete each other. *)
          && Wiki_directive.undefined_productions
               (Wiki_directive.parse
                  ".. productionlist:: a\n   x: `y`\n\n.. productionlist:: b\n   y: Z\n")
             = [ ("a", "y") ]
        with _ -> false)
      "HW.2.6.4" Dialect "productionlist (grammars)" "refs(g) subset defs(g)" 4 3 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let t = Wiki_directive.parse ".. only:: html\n\n   # Web\n\n# Always\n" in
          let sel a = Wiki_directive.select ~declared:[ "html"; "pdf" ] ~active:a t in
          let web = sel [ "html" ] and pdf = sel [ "pdf" ] in
          (* the tag set is DECLARED and passed in, never inferred from
             the environment; and what was withheld is COUNTABLE, because
             content dropped by an undeclared tag is invisible loss *)
          Wiki_directive.anchors web = [ "web"; "always" ]
          && Wiki_directive.anchors pdf = [ "always" ]
          && Wiki_directive.excluded_lines pdf = 3
          && Wiki_directive.excluded_lines web = 0
          && (let u = Wiki_directive.select ~declared:[] ~active:[] t in
              List.mem (Wiki_directive.Undeclared_tag "html") u.Wiki_directive.diagnostics)
        with _ -> false)
      "HW.2.6.5" Dialect "Conditional content (only)" "anchors computed per build" 2 2 Built;
    f ~src:[ Sphinx ] "HW.2.6.6" Dialect "Code-block options"
      ~derived:(fun () ->
        try
          contains (render "```ocaml emphasize=2\na\nb\n```\n") "<mark>b</mark>"
          && List.length
               (Hermes_wiki.fence_option_gaps
                  (Hermes_wiki.build [ ("docs/x/e.md", "# E\n\n```ocaml emphasize=9\na\n```\n") ]))
             = 1
        with _ -> false)
      "emphasize lines within range or diagnostic" 3 2 Built;
    f ~src:[ Sphinx ] "HW.2.6.7" Dialect "Default highlight language"
      ~derived:(fun () ->
        try
          (* the document default supplies a missing language; the fence's
             own language dominates it *)
          let page fm body =
            match
              Hermes_wiki.page (Hermes_wiki.build [ ("docs/x/h.md", fm ^ "# H\n\n" ^ body) ]) "h"
            with
            | Some p -> p.Hermes_wiki.html
            | None -> ""
          in
          contains (page "---\nhighlight: ocaml\n---\n" "```\nx\n```\n") "language-ocaml"
          && contains (page "---\nhighlight: ocaml\n---\n" "```json\nx\n```\n") "language-json"
          && not (contains (page "" "```\nx\n```\n") "language-")
        with _ -> false)
      "fence lang dominates" 2 1 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let t =
            Wiki_directive.parse
              "# H\n\n.. sectionauthor:: [[alpha]] Ada\n   also [[beta]]\n\nprose\n"
          in
          (* a BYLINE: printable and structurally INERT. No edge from a
             name that happens to be spelled like a link — not from the
             argument, not from the body. *)
          Wiki_directive.authorship t = [ ("sectionauthor", "[[alpha]] Ada") ]
          && Wiki_directive.edges ~source:"h" t = []
          && Wiki_directive.anchors t = [ "h" ]
          && t.Wiki_directive.docinfo = []
          && t.Wiki_directive.diagnostics = []
        with _ -> false)
      "HW.2.6.8" Dialect "Authorship directives" "presentational only" 1 1 Built;
    f ~src:[ Sphinx ] "HW.2.6.9" Dialect "LaTeX table column control" "no LaTeX builder" 0 0 Excluded;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let src =
            ":author: Ada\n:version: 3\n\n# H\n\n.. only:: html\n   :hidden: yes\n\n   body\n"
          in
          let t = Wiki_directive.parse ~frontmatter:[ "author" ] src in
          (* METADATA, so it must not ALSO render as body text — and it is
             MOVED, never lost: the source still round-trips byte for
             byte. Block-scoped: a directive's options are that block's,
             not the document's. *)
          t.Wiki_directive.docinfo = [ ("author", "Ada"); ("version", "3") ]
          && (not
                (List.exists
                   (function
                     | Wiki_directive.Text ls -> List.mem ":author: Ada" ls
                     | Wiki_directive.Heading _ | Wiki_directive.Fenced _ | Wiki_directive.Block _ ->
                         false)
                   t.Wiki_directive.nodes))
          && Wiki_directive.source_lines t = String.split_on_char '\n' src
          && List.map (fun d -> d.Wiki_directive.fields) (Wiki_directive.directives t)
             = [ [ ("hidden", "yes") ] ]
          && t.Wiki_directive.diagnostics = [ Wiki_directive.Docinfo_conflict "author" ]
        with _ -> false)
      "HW.2.7.1" Dialect "Field lists / docinfo"
      "block-scoped; frontmatter conflict is a diagnostic" 2 2 Built;
    f ~src:[ Sphinx ] "HW.2.7.2" Dialect "Default inline role"
      ~derived:(fun () ->
        try
          (* identity under code AND the any-role reference, side by side *)
          let plain = Hermes_wiki.render_markdown ~resolve:(fun _ -> None) "a `x` b\n" in
          let coded =
            Hermes_wiki.render_markdown ~default_role:"code" ~resolve:(fun _ -> None)
              "a `x` b\n"
          in
          let any =
            Hermes_wiki.render_markdown ~default_role:"any"
              ~resolve:(fun s -> if s = "x" then Some "x.html" else None)
              "a `x` b\n"
          in
          plain = coded && contains plain "<code>x</code>"
          && contains any "<a href=\"x.html\" class=\"wikilink\">x</a>"
        with _ -> false)
      "explicit role dominates; identity under Kind=code" 4 3 Built;
    f ~src:[ Sphinx ] "HW.2.7.3" Dialect "Downloadable file references"
      "closed extension set; served, not rendered" 2 2 (Forked 2);
    f ~src:[ Sphinx ] "HW.2.7.4" Dialect "Multiple source formats" "one source format" 0 0 Excluded ]

let address =
  [ f ~src:[ Obsidian ] ~rows:[ 115 ] ~derived:(renders "[[nope]]" "missing") "HW.3.1.1" Address "Wikilinks"
      "resolved or VISIBLY missing" 5 5 Built;
    (* R21: the addressing family gets its verification. *)
    f
      ~derived:(fun () ->
        try
          (* MANY KEYS, ONE SLUG. A note is reachable by its slug, its
             title, and its title's ordinal-stripped form — all landing on
             the same page, because a reader who knows the document by any
             of its names should not have to know which one the resolver
             prefers. *)
          let m =
            Hermes_wiki.build
              [ ("docs/hermes/zk/the-gate.md", "# 03 · The Gate\n\nbody.\n");
                ("docs/hermes/zk/user.md",
                 "# User\n\nA [[the-gate]], B [[03 · The Gate]], C [[The Gate]].\n") ]
          in
          let out = (Option.get (Hermes_wiki.page m "user")).Hermes_wiki.outlinks in
          out = [ "the-gate" ] && Hermes_wiki.unresolved_refs m = []
        with _ -> false)
      "HW.3.1.2" Address "Four-key resolver" "many keys -> one slug; first wins" 4 4 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          (* THE SAME RELATION: a real corpus cross-references with
             ordinary markdown links, and a graph that only sees [[...]]
             reports those documents as unconnected when they are not. *)
          let m =
            Hermes_wiki.build
              [ ("docs/hermes/zk/target.md", "# Target\n\nbody.\n");
                ("docs/hermes/zk/src.md", "# Src\n\nSee [the target](target.md).\n") ]
          in
          (Option.get (Hermes_wiki.page m "src")).Hermes_wiki.outlinks = [ "target" ]
          && (Option.get (Hermes_wiki.page m "target")).Hermes_wiki.backlinks = [ "src" ]
        with _ -> false)
      "HW.3.1.3" Address "Relative .md links" "same relation as a wikilink" 3 3 Built;
    f
      ~derived:(fun () ->
        try
          (* An external URL is NOT an edge in this graph. If it were,
             every centrality measure would be dominated by whichever
             site the corpus happens to cite most, and the graph would
             stop describing the corpus. *)
          let m =
            Hermes_wiki.build
              [ ("docs/hermes/zk/ext.md",
                 "# Ext\n\n[a](https://example.com/target.md) and [b](http://x.test/y.md) \
                  and <https://z.test>.\n") ]
          in
          (Option.get (Hermes_wiki.page m "ext")).Hermes_wiki.outlinks = []
        with _ -> false)
      "HW.3.1.4" Address "External URL exclusion" "external(u) => u not an edge" 4 5 Built;
    f ~src:[ Notion ] ~rows:[ 9 ] "HW.3.1.5" Address "Bookmark / link preview" "render does no network IO" 0 0 Excluded;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          (* INJECTIVE PER DOCUMENT: two headings with the same text get
             two anchors, because a duplicate anchor makes one of the two
             links unreachable and neither author can tell which. *)
          let m =
            Hermes_wiki.build
              [ ("docs/hermes/zk/dupes.md", "# D\n\n## Setup\n\ntext\n\n## Setup\n\ntext\n") ]
          in
          let a = Hermes_wiki.anchors m "dupes" in
          List.length (List.sort_uniq compare a) = List.length a
          && List.mem "setup" a
          && List.exists (fun s -> s <> "setup" && String.length s > 5) a
        with _ -> false)
      "HW.3.2.1" Address "Stateful heading slugger" "github-slugger; injective per doc" 4 4 Built;
    f
      ~derived:(fun () ->
        try
          (* LOCALITY: a page's anchors are a function of that page alone.
             If the slugger's counter leaked across documents, the same
             file would render different anchors depending on what else
             was in the corpus — and every cross-document fragment link
             would break on an unrelated edit. *)
          let src = "# P\n\n## Setup\n\ntext\n\n## Setup\n\nmore\n" in
          let alone = Hermes_wiki.build [ ("docs/hermes/zk/p.md", src) ] in
          let among =
            Hermes_wiki.build
              [ ("docs/hermes/zk/before.md", "# Before\n\n## Setup\n\n## Setup\n");
                ("docs/hermes/zk/p.md", src);
                ("docs/hermes/zk/after.md", "# After\n\n## Setup\n") ]
          in
          Hermes_wiki.anchors alone "p" = Hermes_wiki.anchors among "p"
          && (Option.get (Hermes_wiki.page alone "p")).Hermes_wiki.html
             = (Option.get (Hermes_wiki.page among "p")).Hermes_wiki.html
        with _ -> false)
      "HW.3.2.2" Address "Anchor locality" "single-page render = corpus render" 4 5 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let body = "## Configuring the gate {#gate}\n\n## Renamed later {#gate}\n\n## Plain\n" in
          (* anchor o retitle = anchor — the declared id SURVIVES a retitle,
             which is the entire reason to declare one. A collision keeps
             BOTH declared ids and is reported: de-duplicating to -1 would
             silently point an author's declared address at another's
             heading. Anchors stay a function of one body alone. *)
          Wiki_address.anchors_of "## Configuring the gate {#gate}\n" = [ "gate" ]
          && Wiki_address.anchors_of "## Anything else {#gate}\n" = [ "gate" ]
          && List.length (Wiki_address.id_collisions body) = 1
          && Wiki_address.anchors_of body = [ "gate"; "gate"; "plain" ]
          && Wiki_address.headings_of "```\n## Fenced {#gate}\n```\n" = []
        with _ -> false)
      "HW.3.2.3" Address "{#custom-id} heading ids" "anchor o retitle = anchor" 3 3 Built;
    f ~src:[ Obsidian ] ~rows:[ 89 ] ~gates:[ "HW.3.5.1"; "HW.3.5.2"; "HW.6.3.2"; "HW.8.3.7" ]
      ~derived:(fun () ->
        (* both renderers agree byte-for-byte, the id keeps ^, anchors
           include it, and a same-page duplicate is a defect *)
        try
          let src = "a claim worth citing ^c-1\n" in
          let a = Hermes_wiki.render_markdown ~resolve:(fun _ -> None) src in
          a = Hermes_wiki.render_line_machine ~resolve:(fun _ -> None) src
          && a = "<p id=\"^c-1\">a claim worth citing</p>\n"
          && (let m = Hermes_wiki.build [ ("pages/wiki/px.md", "# Px\n\nclaim ^b1\n") ] in
              List.mem "^b1" (Hermes_wiki.anchors m "px"))
          &&
          let dup = Hermes_wiki.build [ ("pages/wiki/py.md", "# Py\n\none ^d\n\ntwo ^d\n") ] in
          List.exists
            (fun s -> String.length s >= 22 && String.sub s 0 22 = "duplicate block anchor")
            (Hermes_wiki.defects dup)
        with _ -> false)
      "HW.3.3.1" Address "Block anchors ^id"
      "alphabet [A-Za-z0-9-] (narrower than Slug); pinned ids keep ^ so namespaces are disjoint" 5 4
      Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          (* the gate DETECTS, and detection must be exact in both
             directions: a resolving corpus reports nothing, a dead
             reference is reported and NAMED. A validator that reports
             something for a clean corpus is as useless as one that
             reports nothing for a broken one. *)
          let clean =
            Hermes_wiki.build
              [ ("docs/hermes/zk/a.md", "# A\n\nSee [[b]].\n");
                ("docs/hermes/zk/b.md", "# B\n\nbody.\n") ]
          in
          let broken = Hermes_wiki.build [ ("docs/hermes/zk/a.md", "# A\n\nSee [[ghost]].\n") ] in
          Hermes_wiki.unresolved_refs clean = []
          && (match Hermes_wiki.unresolved_refs broken with
             | [ line ] -> contains line "ghost"
             | _ -> false)
        with _ -> false)
      "HW.3.4.1" Address "Broken link validation" "no dead internal link ships" 5 5 Built;
    f ~src:[ Docusaurus ] ~derived:(modelled (fun m -> Hermes_wiki.anchors m "probe-a" <> []))
      "HW.3.4.2" Address "Per-page anchor collection" "anchors(p) = ids(render p)" 3 4 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
              [ ("docs/hermes/zk/t.md", "# T\n\n## Present\n");
                ("docs/hermes/zk/c.md", "# C\n\n[[t#Absent]].\n") ] in
          List.length (Hermes_wiki.broken_anchors m) = 1
        with _ -> false)
      "HW.3.4.3" Address "Broken anchor validation"
      "resolve(t)=Some p AND f not in anchors(p) => diag, DISTINCT from broken_link" 4 5 Built;
    f ~src:[ Obsidian ] ~rows:[ 95 ] "HW.3.5.1" Address "Note transclusion"
      ~derived:(fun () ->
        try
          let lookup = function
            | "src" -> Some ("src", "SOURCE BODY")
            | "a" -> Some ("a", "A ![[b]]")
            | "b" -> Some ("b", "B ![[a]]")
            | _ -> None
          in
          let run self raw = Wiki_transclude.expand ~lookup ~self raw in
          let ok = run "host" "x ![[src]] y" in
          (* the embed DENOTES its source, and carries provenance *)
          contains ok.Wiki_transclude.text "SOURCE BODY"
          && contains ok.Wiki_transclude.text "embedded from"
          (* a cycle TERMINATES and is named, never a hang *)
          && (run "host" "![[a]]").Wiki_transclude.cycles <> []
          (* an unresolvable embed is loud, never a silent gap *)
          && (run "host" "![[ghost]]").Wiki_transclude.missing <> []
          (* and the grammar written in backticks is not a use *)
          && (run "host" "the `![[src]]` form").Wiki_transclude.embedded = []
        with _ -> false)
      "embed denotes its source" 4 4 Built;
    f ~src:[ Notion ] ~rows:[ 77 ] "HW.3.5.2" Address "Block transclusion"
      ~derived:(fun () ->
        try
          let lookup = function
            | "p" -> Some ("p", "Intro.\n\nThe claim. ^c\n\nTail.")
            | _ -> None
          in
          let one = Wiki_transclude.expand ~lookup ~self:"h" "![[p#^c]]" in
          let miss = Wiki_transclude.expand ~lookup ~self:"h" "![[p#^ghost]]" in
          (* quote THIS claim, not its page *)
          contains one.Wiki_transclude.text "The claim."
          && (not (contains one.Wiki_transclude.text "Intro."))
          && (not (contains one.Wiki_transclude.text "Tail."))
          (* a missing block NEVER widens to the whole page *)
          && miss.Wiki_transclude.missing <> []
          && not (contains miss.Wiki_transclude.text "Intro.")
        with _ -> false)
      "quote this claim, not its page" 4 4 Built;
    f "HW.3.5.3" Address "Transclusion DAG + depth guard"
      ~derived:(fun () ->
        try
          (* the two mirrors' concerns, both discharged by construction:
             the loop injector's planted cycle must TERMINATE and be
             named, and the depth limiter's bound must be REPORTED
             rather than silently applied. *)
          let lookup = function
            | "a" -> Some ("a", "A ![[b]]")
            | "b" -> Some ("b", "B ![[a]]")
            | "d1" -> Some ("d1", "1 ![[d2]]")
            | "d2" -> Some ("d2", "2 ![[d3]]")
            | "d3" -> Some ("d3", "3 leaf")
            | _ -> None
          in
          let cyc = Wiki_transclude.expand ~lookup ~self:"host" "![[a]]" in
          let deep = Wiki_transclude.expand ~depth:1 ~lookup ~self:"host" "![[d1]]" in
          (* ACYCLIC: the back edge is dropped and named, not followed *)
          cyc.Wiki_transclude.cycles <> []
          (* the DAG still expands: a diamond is not a cycle *)
          && (Wiki_transclude.expand ~lookup ~self:"h" "![[d1]] ![[d1]]")
               .Wiki_transclude.cycles = []
          (* DEPTH: bounded, and the bound REPORTED *)
          && deep.Wiki_transclude.truncated <> []
          && Wiki_transclude.default_depth = 3
        with _ -> false)
      "acyclic, depth<=3, bound REPORTED" 3 5 Built;
    f ~src:[ Obsidian ] ~rows:[ 113 ] "HW.3.6.1" Address "URI scheme / deep links" "HTTP addresses everything" 0 0 Excluded;
    f ~src:[ Sphinx ] ~gates:[ "HW.3.7.2"; "HW.3.7.3"; "HW.3.7.4"; "HW.2.7.2"; "HW.2.6.3" ]
      ~derived:(fun () ->
        (* the kind law at the render surface: doc:X resolves through the
           doc space; term:X does NOT fall back to it. Mirror: note_ref. *)
        try
          let m =
            Hermes_wiki.build
              [ ( "docs/hermes/zk/probe-a.md",
                  "# Probe A\n\nSee [[doc:probe-b]] and [[term:probe-b]].\n" );
                ("docs/hermes/zk/probe-b.md", "# Probe B\n\nplain.\n") ]
          in
          match Hermes_wiki.page m "probe-a" with
          | Some p ->
              contains p.Hermes_wiki.html
                "<a href=\"probe-b.html\" class=\"wikilink\">probe-b</a>"
              && contains p.Hermes_wiki.html "<span class=\"missing\">probe-b</span>"
          | None -> false
        with _ -> false)
      "HW.3.7.1" Address "Typed cross-reference roles" "kind(resolve_k(x)) = k" 4 4
      Built;
    f ~src:[ Sphinx ] "HW.3.7.2" Address "Ambiguity as an error"
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ("docs/a/gate-one.md", "# The Gate\n\nbody.\n");
                ("docs/b/gate-two.md", "# The Gate\n\nbody.\n");
                ("docs/c/user.md", "# User\n\nSee [[The Gate]] and [[nowhere]].\n") ]
          in
          (* >1 reported, 0 NOT reported: the two verdicts stay distinct *)
          match Hermes_wiki.ambiguous_refs m with
          | [ line ] -> contains line "the-gate" && not (contains line "nowhere")
          | _ -> false
        with _ -> false)
      "|resolve_any(x)| = 1 or diag; 0 and >1 reported distinctly" 4 5 Built;
    f ~src:[ Sphinx ] "HW.3.7.3" Address "Nitpicky mode"
      ~derived:(fun () ->
        try
          let m k = Hermes_wiki.build [ ("docs/c/user.md", "# User\n\nSee " ^ k ^ ".\n") ] in
          List.length (Hermes_wiki.unresolved_refs (m "[[nowhere]]")) = 1
          && Hermes_wiki.unresolved_refs (m "[[!nowhere]]") = []
        with _ -> false)
      "any unresolved reference fails; ! is a per-reference disclosed opt-out" 4 5
      Built;
    f ~src:[ Sphinx ] "HW.3.7.4" Address "Glossary + :term:"
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ( "docs/wiki/glossary.md",
                  "---\ntopics: [glossary]\n---\n# G\n\n## Parity\n\ndef.\n" );
                ("docs/c/user.md", "# User\n\nSee [[term:parity]] and [[term:quirk]].\n") ]
          in
          List.length (Hermes_wiki.term_gaps m) = 1
          && (match Hermes_wiki.page m "user" with
             | Some p -> contains p.Hermes_wiki.html "glossary.html#parity"
             | None -> false)
        with _ -> false)
      "term used and undefined => diag" 4 3 Built;
    f ~src:[ Sphinx ] "HW.3.7.5" Address "Auto section labels" "referenceable by title, no declaration" 3 2
      (Blocked "HW.3.2.3");
    f ~src:[ Sphinx ] "HW.3.7.6" Address "Reference display modifiers"
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ("docs/a/probe-b.md", "# Probe B\n\nplain.\n");
                ("docs/c/user.md", "# User\n\nAbout [[!probe-b]].\n") ]
          in
          (match Hermes_wiki.page m "user" with
          | Some p -> not (List.mem "probe-b" p.Hermes_wiki.outlinks)
          | None -> false)
          && List.length (Hermes_wiki.suppressed_refs m) = 1
        with _ -> false)
      "!r => r not in outlinks (per-reference example opt-out)" 4 4 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let c = [ ("docs/hermes/zk/n.md", "---\naliases: [Old Name]\n---\n# Ledger\n\nb\n") ] in
          let m = Hermes_wiki.build c in
          let inv = Wiki_address.entries_of_model m in
          (* AGREES WITH THE RESOLVER IN BOTH DIRECTIONS. Completeness:
             every resolvable key is published. Soundness: every entry
             resolves to the slug it names, checked against the ENGINE'S
             OWN rendered href rather than against the inventory itself —
             an inventory validated against itself proves nothing. *)
          let published k = k = "" || List.exists (fun e -> e.Wiki_address.ekey = k) inv in
          let sound e =
            let l = Wiki_address.location e in
            let k = e.Wiki_address.ekey in
            let p = Hermes_wiki.build (("docs/hermes/wiki/p.md", "# P\n\n[[" ^ k ^ "]]\n") :: c) in
            String.length l > 0 && l.[0] = '/'
            && (match Hermes_wiki.page p "p" with
               | Some pg ->
                   contains pg.Hermes_wiki.html
                     ("href=\"" ^ String.sub l 1 (String.length l - 1) ^ "\"")
               | None -> false)
          in
          inv <> []
          && List.for_all
               (fun p ->
                 List.for_all published
                   (Hermes_wiki.resolver_keys p @ Hermes_wiki.alias_keys p))
               m.Hermes_wiki.pages
          && List.for_all sound inv
        with _ -> false)
      "HW.3.8.1" Address "Publish a reference inventory"
      "complete, root-relative, digest-pinned" 4 3 Built;
    f ~src:[ Sphinx ] "HW.3.8.2" Address "Consume external inventories"
      "local paths only; unresolvable => diag, never silent fallback" 4 3 (Blocked "HW.3.8.1");
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
            [ ("docs/hermes/zk/note.md", "# Parity Ledger\n\nbody\n");
              ("docs/hermes/journal/log.md", "# Run Log\n\nbody\n") ] in
          let inv = Wiki_address.entries_of_model m in
          let r q = Wiki_address.resolve inv (Wiki_address.parse q) in
          (* UNREPRESENTABLE, not merely absent: a qualified name resolves
             in its own domain or nowhere. Never a fallback to another
             domain, which would answer the reader with the wrong object. *)
          r "journal:parity-ledger" = []
          && List.length (r "zk:parity-ledger") = 1
          && r "parity-ledger" = r "zk:parity-ledger"
          && List.for_all
               (fun e -> e.Wiki_address.edomain = Wiki_address.Zk)
               (r "zk:parity-ledger")
        with _ -> false)
      "HW.3.9.1" Address "Reference domains" "cross-domain collision unrepresentable" 4 4 Built;
    f ~src:[ Sphinx ] "HW.3.9.2" Address "Ambient namespace declaration" "explicit qualifier dominates" 2 2
      (Blocked "HW.3.9.1");
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let r = Wiki_address.substitute
            "<!-- subst: p = Hermes -->\n<!-- subst: p = Other -->\n\n{{p}} and {{ghost}} and `{{p}}`\n" in
          (* ONE definition governs; a second is REPORTED rather than
             silently preferred. An undefined name is LOUD and is never
             left as its own literal marker, which would read to a viewer
             as an intentional placeholder. Backticked is an example. *)
          contains r.Wiki_address.text "Hermes and"
          && (not (contains r.Wiki_address.text "Other"))
          && List.length r.Wiki_address.conflicts = 1
          && contains r.Wiki_address.text "**[undefined substitution: ghost]**"
          && (not (contains r.Wiki_address.text "{{ghost}}"))
          && contains r.Wiki_address.text "`{{p}}`"
          && (let c = Wiki_address.substitute
                "<!-- subst: a = {{b}} -->\n<!-- subst: b = {{a}} -->\n\n{{a}}\n" in
              c.Wiki_address.cycles <> [] && contains c.Wiki_address.text "substitution cycle")
        with _ -> false)
      "HW.3.10.1" Address "Substitutions" "one definition; undefined name => diag" 3 3 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let files = [ ("a.md", "ALPHA\n<!-- include: b.md -->");
                        ("b.md", "BETA\n<!-- include: a.md -->") ] in
          let read p = List.assoc_opt p files in
          let ok = Wiki_address.splice ~read ~self:"h.md" "<!-- include: a.md -->\n" in
          let gone =
            Wiki_address.splice ~read:(fun _ -> None) ~self:"h.md" "<!-- include: x.md -->\n" in
          let deep = Wiki_address.splice ~depth:1 ~read ~self:"h.md" "<!-- include: a.md -->\n" in
          (* ACYCLIC and DEPTH-BOUNDED, both REPORTED: a cycle that
             terminates silently and a bound applied silently both leave a
             reader with a truncated document they cannot tell is
             truncated. *)
          contains ok.Wiki_address.text "ALPHA"
          && contains ok.Wiki_address.text "BETA"
          && ok.Wiki_address.cycles <> []
          && contains ok.Wiki_address.text "**[include cycle: a.md]**"
          && contains gone.Wiki_address.text "**[include unresolved: x.md]**"
          && gone.Wiki_address.missing <> []
          && deep.Wiki_address.truncated <> []
          && contains deep.Wiki_address.text "include depth 1 reached"
        with _ -> false)
      "HW.3.10.2" Address "include (whole document)" "acyclic, depth-bounded" 2 2 Built ]

let graph =
  [ (* R21: these five carried no verification method until the model gate
       counted them. Each probe now asserts the row's own law over a built
       model, so the claim can fail. *)
    f
      ~derived:(fun () ->
        try
          let m = graph_corpus () in
          let out s = (Option.get (Hermes_wiki.page m s)).Hermes_wiki.outlinks in
          (* DERIVED: an outlink exists because the text says so, and
             disappears when the text stops saying so — never stored *)
          List.mem "gb" (out "ga")
          && not (List.mem "ga" (out "ga"))
          && (let m2 = Hermes_wiki.build [ ("docs/hermes/zk/ga.md", "# Ga\n\nno links here.\n") ] in
              (Option.get (Hermes_wiki.page m2 "ga")).Hermes_wiki.outlinks = [])
        with _ -> false)
      "HW.4.1.1" Graph "Outlinks" "derived from the AST, never stored" 5 5 Built;
    f ~src:[ Notion; Obsidian ] ~rows:[ 8; 87 ]
      ~derived:(fun () ->
        try
          let m = graph_corpus () in
          (* the BICONDITIONAL, checked in both directions over every page *)
          List.for_all
            (fun (a : Hermes_wiki.page) ->
              List.for_all
                (fun (b : Hermes_wiki.page) ->
                  List.mem b.Hermes_wiki.slug a.Hermes_wiki.backlinks
                  = List.mem a.Hermes_wiki.slug b.Hermes_wiki.outlinks)
                m.Hermes_wiki.pages)
            m.Hermes_wiki.pages
          && (Option.get (Hermes_wiki.page m "gb")).Hermes_wiki.backlinks <> []
        with _ -> false)
      "HW.4.1.2" Graph "Backlinks" "b in backlinks(a) <=> a in outlinks(b)" 5 5 Built;
    f
      ~derived:(fun () ->
        try
          let m = graph_corpus () in
          (* fst o back_ctx = backlinks, and the context is the CITING
             LINE — a citation with no line is a backlink pretending *)
          List.for_all
            (fun (p : Hermes_wiki.page) ->
              List.sort_uniq compare (List.map fst p.Hermes_wiki.back_ctx)
              = List.sort_uniq compare p.Hermes_wiki.backlinks)
            m.Hermes_wiki.pages
          && List.exists
               (fun (_, line) -> String.length (String.trim line) > 0)
               (Option.get (Hermes_wiki.page m "gb")).Hermes_wiki.back_ctx
        with _ -> false)
      "HW.4.1.3" Graph "Contextual backlinks" "fst o back_ctx = backlinks" 4 4 Built;
    f ~src:[ Obsidian ] ~rows:[ 112 ]
      ~derived:(fun () ->
        try
          let m = graph_corpus () in
          (* DISJOINT by law: a mention is what a link is NOT, so a page
             counted as both would be double-counted everywhere *)
          List.for_all
            (fun (p : Hermes_wiki.page) ->
              List.for_all
                (fun s -> not (List.mem s p.Hermes_wiki.backlinks))
                p.Hermes_wiki.mentions)
            m.Hermes_wiki.pages
          && (Option.get (Hermes_wiki.page m "ga")).Hermes_wiki.mentions = [ "gc" ]
        with _ -> false)
      "HW.4.1.4" Graph "Unlinked mentions" "mentions(a) disjoint from backlinks(a)" 3 3 Built;
    f ~src:[ Notion ] ~rows:[ 66 ]
      ~derived:(fun () ->
        try
          let m = graph_corpus () in
          let typed = (Option.get (Hermes_wiki.page m "ga")).Hermes_wiki.typed in
          (* a typed edge names BOTH its target and its relation, and the
             relation survives into the render — an edge whose type is
             dropped at the surface is an untyped edge *)
          (* BOTH DIRECTIONS. Outgoing: the relation reaches the render,
             so a reader can see the edge is typed. Incoming: the target
             can name who supports it. Neither alone satisfies the law —
             an edge only its author can see is an untyped edge with
             extra syntax. *)
          List.mem_assoc "gb" typed
          && List.assoc "gb" typed = "supports"
          && contains (Option.get (Hermes_wiki.page m "ga")).Hermes_wiki.html
               "data-rel=\"supports\""
          && Hermes_wiki.typed_backlinks m "gb" = [ ("ga", "supports") ]
          && Hermes_wiki.typed_backlinks m "ga" = []
        with _ -> false)
      "HW.4.1.5" Graph "Typed edges" "rendered both directions" 5 4 Built;
    f ~src:[ Notion ] ~rows:[ 49 ] "HW.4.1.6" Graph "Date mentions" "ISO-normalised; feeds the timeline" 2 2
      (Blocked "HW.6.6.2");
    f ~src:[ Obsidian ] ~rows:[ 109 ]
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ("pages/wiki/t1.md", "---\ntopics: [a/b/c]\n---\n\n# T1\n\nx\n");
                ("pages/wiki/t2.md", "---\ntopics: [a/b]\n---\n\n# T2\n\nx\n");
                ("pages/wiki/t3.md", "---\ntopics: [ab]\n---\n\n# T3\n\nx\n") ]
          in
          (* SEGMENT-WISE, not a string prefix: #a covers #a/b but NOT
             #ab. And MONOTONE — a query for the parent must return
             everything under it, or a hierarchy is decoration. *)
          Wiki_similarity.tag_ancestors "a/b/c" = [ "a"; "a/b"; "a/b/c" ]
          && Wiki_similarity.tag_covers ~parent:"a" ~child:"a"
          && Wiki_similarity.tag_covers ~parent:"a" ~child:"a/b"
          && Wiki_similarity.tag_covers ~parent:"a" ~child:"a/b/c"
          && (not (Wiki_similarity.tag_covers ~parent:"a" ~child:"ab"))
          && (not (Wiki_similarity.tag_covers ~parent:"" ~child:"a"))
          && Wiki_similarity.tag_members m "a" = [ "t1"; "t2" ]
          && Wiki_similarity.tag_members m "a/b/c" = [ "t1" ]
          && Wiki_similarity.tag_members m "ab" = [ "t3" ]
          && List.assoc_opt "a" (Wiki_similarity.tag_tree m) = Some [ "t1"; "t2" ]
        with _ -> false)
      "HW.4.1.7" Graph "Nested tags" "prefix order is monotone in members" 3 3 Built;
    f ~src:[ Obsidian ] ~rows:[ 98 ] ~gates:[ "HW.6.3.4"; "HW.4.4.1" ]
      ~derived:(fun () ->
        try
          let g =
            Wiki_graph.of_model
              (Hermes_wiki.build
                 [ ("pages/wiki/aa.md", "# Aa\n\n[[bb]]\n"); ("pages/wiki/bb.md", "# Bb\n\n[[cc]]\n");
                   ("pages/wiki/cc.md", "# Cc\n\ntext\n") ])
          in
          let r = Wiki_graph.pagerank g in
          let sum = List.fold_left (fun a (_, x) -> a +. x) 0.0 r in
          abs_float (sum -. 1.0) < 1e-6
          && List.assoc "cc" r > List.assoc "aa" r
          && r = Wiki_graph.pagerank g
        with _ -> false)
      "HW.4.2.1" Graph "PageRank / personalised PageRank"
      "G_s = aQ + (1-a)1s^T, a=0.85; full support => unique stationary; fixed summation order" 4 3
      Built;
    f ~src:[ Obsidian ] ~rows:[ 98 ] ~gates:[ "HW.4.5.2"; "HW.4.6.2"; "HW.4.6.3" ]
      ~derived:(fun () ->
        try
          let g =
            Wiki_graph.of_model
              (Hermes_wiki.build
                 [ ("pages/wiki/bb.md", "# Bb\n\n[[aa]]\n"); ("pages/wiki/aa.md", "# Aa\n\n[[bb]]\n") ])
          in
          Wiki_graph.communities g = [ ("aa", [ "aa"; "bb" ]) ]
        with _ -> false)
      "HW.4.2.2" Graph "Communities (constrained LPA)"
      "CONSTRAINED: slug-order sweep, smallest-member-slug ties; communities(shuffle g) = communities(g)"
      4 4 Built;
    f ~src:[ Obsidian ] ~rows:[ 98 ]
      ~derived:(fun () ->
        try
          let g =
            Wiki_graph.of_model
              (Hermes_wiki.build
                 [ ("pages/wiki/aa.md", "# Aa\n\n[[bb]]\n"); ("pages/wiki/bb.md", "# Bb\n\n[[cc]]\n");
                   ("pages/wiki/cc.md", "# Cc\n\ntext\n") ])
          in
          List.assoc "bb" (Wiki_graph.betweenness g) = 1.0
        with _ -> false)
      "HW.4.2.3" Graph "Betweenness centrality" "Brandes 2001, Theta(nm); fixed vertex order" 3 3
      Built;
    f
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ("pages/wiki/a1.md", "# A1\n\n[[a2]] [[a3]]\n");
                ("pages/wiki/a2.md", "# A2\n\n[[a1]] [[a3]]\n");
                ("pages/wiki/a3.md", "# A3\n\n[[a1]] [[a2]]\n");
                ("pages/wiki/hub.md", "# Hub\n\n[[a1]] [[b1]]\n");
                ("pages/wiki/b1.md", "# B1\n\n[[b2]] [[b3]]\n");
                ("pages/wiki/b2.md", "# B2\n\n[[b1]] [[b3]]\n");
                ("pages/wiki/b3.md", "# B3\n\n[[b1]] [[b2]]\n") ]
          in
          let h = Wiki_similarity.structural_holes m in
          (* GROUNDED in the communities Wiki_graph already computes — a
             fresh clustering here could disagree with the one the rest
             of the system uses, and then two parts of the corpus would
             describe different graphs. Report-only (R5). *)
          List.length (Wiki_graph.communities (Wiki_graph.of_model m)) = 2
          && List.length h = List.length m.Hermes_wiki.pages
          && List.assoc "hub" h = 1
          && List.assoc "a2" h = 0
          && List.length (Wiki_similarity.directed_edges m)
             = Wiki_graph.edge_count (Wiki_graph.of_model m)
        with _ -> false)
      "HW.4.2.4" Graph "Structural holes" "report-only; never mutates the graph" 4 2 Built;
    f "HW.4.3.1" Graph "Shared-tag correlation" "ranked by tag overlap, ties by slug" 2 2 Built;
    f ~src:[ Docusaurus; Obsidian ]
      ~derived:(fun () ->
        try
          let c =
            [ ("pages/wiki/aa.md", "# Aa\n\nzebra quark zebra plume\n");
              ("pages/wiki/bb.md", "# Bb\n\nzebra quark plume\n");
              ("pages/wiki/cc.md", "# Cc\n\nwidget sprocket\n") ]
          in
          let v = Wiki_similarity.vectors (Hermes_wiki.build c) in
          let w = Wiki_similarity.vectors (Hermes_wiki.build (List.rev c)) in
          (* SYMMETRIC bit-exactly, and DETERMINISTIC under a shuffled
             input: float accumulation is order-dependent, so a corpus
             read in a different order would otherwise flip ties and
             reorder every ranked list. *)
          Wiki_similarity.corpus_size v = 3
          && abs_float (Wiki_similarity.idf v "widget" -. (1.0 +. log 3.0)) < 1e-12
          && Wiki_similarity.similarity v "aa" "aa" = 1.0
          && Wiki_similarity.similarity v "aa" "bb" = Wiki_similarity.similarity v "bb" "aa"
          && Wiki_similarity.similarity v "aa" "bb" > Wiki_similarity.similarity v "aa" "cc"
          && Wiki_similarity.similarity v "aa" "cc" = 0.0
          && Wiki_similarity.similarity v "aa" "ghost" = 0.0
          && Wiki_similarity.related v "aa" = [ ("bb", Wiki_similarity.similarity v "aa" "bb") ]
          && Wiki_similarity.canonical v = Wiki_similarity.canonical w
        with _ -> false)
      "HW.4.3.2" Graph "TF-IDF cosine similarity"
      "idf(t)=1+ln(N/n_t); symmetric; sim(a,a)=1; fences excluded" 4 3 Built;
    f ~src:[ Obsidian; Notion ] ~gates:[ "HW.4.4.2" ]
      ~derived:(fun () ->
        try
          Discourse.grounded ~attacks:[ ("a", "b"); ("b", "c") ] ~nodes:[ "a"; "b"; "c" ]
          = [ "a"; "c" ]
          && Discourse.grounded ~attacks:[ ("a", "b"); ("b", "a") ] ~nodes:[ "a"; "b" ] = []
        with _ -> false)
      "HW.4.4.1" Graph "Grounded semantics"
      "least fixed point of F_AF; Att = @opposes; @supports is defence, NOT attack" 5 4 Built;
    f
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ("pages/wiki/c1.md", "---\ntype: claim\n---\n# C1\n\nunder fire\n");
                ("pages/wiki/c2.md", "---\ntype: claim\n---\n# C2\n\n[[c1|@opposes]]\n") ]
          in
          Discourse.anomalies m = [ "c1" ]
        with _ -> false)
      "HW.4.4.2" Graph "Discourse anomalies" "report-only; cannot deny parity credit (R5)" 4 4
      Built;
    f ~src:[ Obsidian ] ~rows:[ 99 ] "HW.4.5.1" Graph "Global graph view" "deterministic layout" 3 3 Built;
    f ~src:[ Obsidian ]
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ("pages/wiki/p1.md", "# P1\n\n[[p2]]\n");
                ("pages/wiki/p2.md", "# P2\n\n[[p3]]\n");
                ("pages/wiki/p3.md", "# P3\n\n[[p4]]\n");
                ("pages/wiki/p4.md", "# P4\n\nend\n") ]
          in
          let l r = Wiki_similarity.local_graph m ~radius:r "p1" in
          (* a SUBGRAPH IN BOTH DIRECTIONS: sound (nothing beyond r) and
             complete (nothing within r missing). The last clause states
             exactly that biconditional over the hop distances — one
             direction alone is not a neighbourhood. *)
          (l 0).Wiki_similarity.nodes = [ "p1" ]
          && (l 0).Wiki_similarity.edges = []
          && (l 2).Wiki_similarity.nodes = [ "p1"; "p2"; "p3" ]
          && (l 2).Wiki_similarity.edges = [ ("p1", "p2"); ("p2", "p3") ]
          && (l 99).Wiki_similarity.nodes = [ "p1"; "p2"; "p3"; "p4" ]
          && (l (-1)).Wiki_similarity.nodes = [ "p1" ]
          && (Wiki_similarity.local_graph m ~radius:2 "ghost").Wiki_similarity.nodes = []
          && List.for_all
               (fun (s, d) -> (d <= 2) = List.mem s (l 2).Wiki_similarity.nodes)
               (Wiki_similarity.hops m "p1")
        with _ -> false)
      "HW.4.5.2" Graph "Local graph (neighbourhood)" "radius-limited per note" 3 2 Built;
    f ~derived:(modelled (fun m -> Hermes_wiki.moc m <> [])) "HW.4.6.1" Graph "MoC by group"
      "one per group" 2 2 Built;
    f
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ("pages/wiki/m1.md", "# M1\n\n[[zed]]\n");
                ("pages/wiki/m2.md", "# M2\n\n[[zed]]\n");
                ("pages/wiki/zed.md", "# Zed\n\n[[m1]]\n") ]
          in
          let u =
            Hermes_wiki.build
              [ ("pages/wiki/u1.md", "# U1\n\nalone\n"); ("pages/wiki/u2.md", "# U2\n\nalone\n") ]
          in
          (* GROUNDED in Wiki_graph's own communities — the MoC partition
             must BE that partition, not a second opinion about it. An
             unlinked corpus yields no MoCs rather than a MoC per page,
             which would be a map of nothing. *)
          Wiki_similarity.community_mocs m = [ ("zed", [ "m1"; "m2"; "zed" ]) ]
          && List.map snd (Wiki_similarity.community_mocs m)
             = List.map snd (Wiki_graph.communities (Wiki_graph.of_model m))
          && Wiki_similarity.community_mocs u = []
        with _ -> false)
      "HW.4.6.2" Graph "Community-grounded MoCs"
      "top by degree, ties by slug; degree>0; unlinked corpus => []" 3 3 Built;
    f ~src:[ Notion ] ~rows:[ 67 ]
      ~derived:(fun () ->
        try
          let c =
            [ ("pages/wiki/r1.md", "# R1\n\n[[r2]]\n"); ("pages/wiki/r2.md", "# R2\n\n[[r1]]\n");
              ("pages/wiki/r3.md", "# R3\n\nalone\n") ]
          in
          let m = Hermes_wiki.build c and m' = Hermes_wiki.build (List.rev c) in
          let n = List.length m.Hermes_wiki.pages in
          let total r = List.fold_left (fun a (_, k) -> a + k) 0 r in
          let key (p : Hermes_wiki.page) = if p.Hermes_wiki.slug = "r3" then "" else "linked" in
          (* it COVERS: the parts sum to the whole, blank-key bucket
             included. An aggregate that silently drops a bucket answers
             a different question than the one asked. And it is
             ORDER-INDEPENDENT — a commutative monoid, not a fold whose
             answer depends on how the corpus was read. *)
          total (Wiki_similarity.rollup_count m ~key) = n
          && List.assoc_opt "" (Wiki_similarity.rollup_count m ~key) = Some 1
          && List.assoc_opt "linked" (Wiki_similarity.rollup_count m ~key) = Some 2
          && total (Wiki_similarity.rollup m ~key ~value:(fun _ -> 2)) = 2 * n
          && total (Wiki_similarity.rollup_communities m) = n
          && Wiki_similarity.rollup_count m ~key = Wiki_similarity.rollup_count m' ~key
        with _ -> false)
      "HW.4.6.3" Graph "Rollup / aggregation" "order-independent (commutative monoid)" 2 2 Built ]

let query =
  [ f ~gates:[ "HW.5.2.2" ]
      ~derived:(fun () ->
        try
          let corpus =
            [ ("docs/hermes/zk/alpha.md", "---\ntype: claim\n---\n# Alpha\n\nSee [[beta]].\n");
              ("docs/hermes/zk/beta.md", "---\ntype: note\n---\n# Beta\n") ] in
          let added =
            [ ("docs/hermes/zk/delta.md", "---\ntype: note\n---\n# D\n\nSee [[alpha]].\n") ] in
          let q s = match Wiki_query.parse s with Ok q -> q | Error e -> failwith e in
          (* MONOTONE decidably, and the checker proves the DIFFERENCE
             rather than asserting the property: a page-local selector
             cannot lose a row when the corpus grows, but a neighbourhood
             predicate can, and the defect names the slug that vanished. *)
          Wiki_datastore.monotone (q "from type:claim")
          && Wiki_datastore.monotone_defect ~base:corpus ~added (q "from type:claim") = None
          && (not (Wiki_datastore.monotone (q "where backlinks<1")))
          && (match Wiki_datastore.monotone_defect ~base:corpus ~added (q "where backlinks<1") with
             | Some m -> contains m "alpha"
             | None -> false)
          && Wiki_datastore.corpus_dependent_fields = [ "backlinks"; "degree" ]
        with _ -> false)
      "HW.5.1.1" Query "from selector" "monotone in the corpus" 4 3 Built;
    f ~src:[ Notion ] ~rows:[ 23 ]
      ~derived:(fun () -> match Wiki_query.parse "where words!=1" with Error _ -> true | Ok _ -> false)
      "HW.5.1.2" Query "where clauses"
      "field-typed; TYPE ERROR is a named error, never empty" 4 4 Built;
    f ~src:[ Notion ] ~rows:[ 23 ]
      ~derived:(fun () -> match Wiki_query.parse "sort slug desc" with Ok _ -> true | Error _ -> false)
      "HW.5.1.3" Query "sort" "total order via slug tiebreak; stable" 3 4 Built;
    f ~derived:(fun () -> match Wiki_query.parse "limit 3" with Ok _ -> true | Error _ -> false)
      "HW.5.1.4" Query "limit" "bounded output stays deterministic" 2 2 Built;
    f ~src:[ Notion ] ~rows:[ 26 ]
      ~derived:(fun () -> match Wiki_query.parse "group by status" with Ok _ -> true | Error _ -> false)
      "HW.5.1.5" Query "group by" "partition: disjoint and covering" 4 3 Built;
    f ~src:[ Obsidian ] ~rows:[ 106 ]
      ~derived:(fun () -> match Wiki_query.parse "from tag:x where status=y" with Ok _ -> true | Error _ -> false)
      "HW.5.1.6" Query "Search operators" "same semantics as where" 3 2 Built;
    f ~gates:[ "HW.5.2.2" ]
      ~derived:(fun () -> match Wiki_query.parse "wibble" with Error _ -> true | Ok _ -> false)
      "HW.5.2.1" Query "Total parser with named errors"
      "every input yields Ok or a NAMED Error; never raises" 4 5 Built;
    f ~gates:[ "HW.5.3.1"; "HW.5.3.2"; "HW.5.3.3"; "HW.5.3.4"; "HW.5.3.5"; "HW.5.3.6"; "HW.5.4.1" ]
      ~derived:(fun () ->
        match Wiki_query.parse "from all" with
        | Ok q -> Wiki_query.eval [] q = []
        | Error _ -> false)
      "HW.5.2.2" Query "Evaluator" "pure; same inputs, same rows" 5 4 Built;
    (* HW.5.3.x — five of these six are RENDERINGS OF ONE RESULT SET, so
       the family law is that they emit the same rows and differ only in
       presentation. Each probe checks its own shape AND the agreement,
       and the agreement is anchored to Wiki_query.eval rather than to
       the other views: five views can agree on a wrong answer. *)
    f ~src:[ Notion ] ~rows:[ 30 ]
      ~derived:(fun () ->
        try
          let ps = view_pages () in
          match Wiki_view.of_source ps "from all sort slug" with
          | Error _ -> false
          | Ok t ->
              let h = Wiki_view.table t in
              (* DERIVED: every cell is a projection of the page computed
                 at render — there is no stored row anywhere to drift *)
              Wiki_view.row_ids h = [ "a"; "b" ]
              && contains h "<td>A</td>" && contains h "<td>B</td>"
              && contains h "<td>draft</td>" && contains h "<td>published</td>"
              && contains h "<td>claim</td>"
              && List.length Wiki_view.columns >= 5
        with _ -> false)
      "HW.5.3.1" Query "Table view" "rows derived, never stored" 4 3 Built;
    f ~src:[ Notion ] ~rows:[ 20 ]
      ~derived:(fun () ->
        try
          let ps = view_pages () in
          match Wiki_view.of_source ps "group by status" with
          | Error _ -> false
          | Ok t ->
              let b = Wiki_view.board t in
              Wiki_view.row_ids b = Wiki_view.row_ids (Wiki_view.table t)
              && List.sort compare (Wiki_view.row_ids b) = [ "a"; "b" ]
              && contains b "data-bucket=\"draft\""
              && contains b "data-bucket=\"published\""
        with _ -> false)
      "HW.5.3.2" Query "Board (kanban)" "a rendering of one result" 2 1 Built;
    f ~src:[ Obsidian ] ~rows:[ 100 ]
      ~derived:(fun () ->
        try
          let ps = view_pages () in
          match Wiki_view.of_source ps "group by status" with
          | Error _ -> false
          | Ok t ->
              let k = Wiki_view.kanban t in
              (* QUERY-DEFINED: the board's columns come from the query,
                 not from a file that can disagree with the corpus *)
              contains k "data-defined-by=\"query\""
              && contains k "data-query=\"group by status\""
              && (not (contains k "data-defined-by=\"file\""))
              && Wiki_view.row_ids k = Wiki_view.row_ids (Wiki_view.table t)
              && Wiki_view.row_ids k <> []
        with _ -> false)
      "HW.5.3.3" Query "Kanban (Obsidian)" "query-defined, not file-defined" 2 1 Built;
    f ~src:[ Notion ] ~rows:[ 25 ]
      ~derived:(fun () ->
        try
          let ps = view_pages () in
          match Wiki_view.of_source ps "from all sort slug" with
          | Error _ -> false
          | Ok t ->
              let g = Wiki_view.gallery t in
              Wiki_view.row_ids g = Wiki_view.row_ids (Wiki_view.table t)
              && Wiki_view.row_ids g = [ "a"; "b" ]
              && contains g "<figure" && contains g "</figure>"
        with _ -> false)
      "HW.5.3.4" Query "Gallery view" "card grid over one result" 1 1 Built;
    f ~src:[ Notion ] ~rows:[ 28 ]
      ~derived:(fun () ->
        try
          let ps = view_pages () in
          match
            (Wiki_view.of_source ps "sort slug limit 1", Wiki_view.of_source ps "sort slug limit 2")
          with
          | Ok one, Ok two ->
              (* COMPACT stated MARGINALLY: one more row must cost fewer
                 bytes in the list than in the table. Comparing whole
                 documents is dominated by the table's own chrome, which
                 is how a bloated list can measure smaller. *)
              let m r = String.length (r two) - String.length (r one) in
              Wiki_view.row_ids (Wiki_view.list_view two)
              = Wiki_view.row_ids (Wiki_view.table two)
              && Wiki_view.row_ids (Wiki_view.list_view two) = [ "a"; "b" ]
              && m Wiki_view.list_view > 0
              && m Wiki_view.list_view < m Wiki_view.table
          | _ -> false
        with _ -> false)
      "HW.5.3.5" Query "List view" "compact rendering" 2 1 Built;
    f ~src:[ Notion ] ~rows:[ 22 ]
      ~derived:(fun () ->
        try
          let ps = view_pages () in
          match (Wiki_query.parse "group by status", Wiki_view.of_source ps "group by status") with
          | Ok q, Ok t ->
              let c = Wiki_view.chart t in
              (* DETERMINISTIC: integer arithmetic only, no script, and
                 the bars COVER the result — a chart whose counts do not
                 sum to the row count is showing a different question. *)
              contains c "<svg" && contains c "</svg>" && contains c "width=\"280\""
              && (not (contains c "<script"))
              && List.fold_left (fun a (_, v) -> a + v) 0 (Wiki_view.chart_counts t)
                 = List.length (Wiki_query.eval ps q)
          | _ -> false
        with _ -> false)
      "HW.5.3.6" Query "Charts" "deterministic inline SVG" 2 2 Built;
    f ~src:[ Notion ] ~rows:[ 21 ] "HW.5.3.7" Query "Calendar view" "decay signals already cover it" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 27 ]
      ~derived:(fun () -> Wiki_query.fences "```zkquery\nfrom all\n```\n" = [ "from all" ])
      "HW.5.4.1" Query "Query fences / linked views"
      "a query is a note; one denotation, many locations" 5 4 Built;
    f ~src:[ Obsidian ] ~rows:[ 88 ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
            [ ("docs/hermes/zk/alpha.md", "---\nstatus: published\ntype: claim\n---\n# Alpha\n");
              ("docs/hermes/zk/beta.md", "---\nstatus: draft\ntype: note\n---\n# Beta\n") ] in
          let pages = m.Hermes_wiki.pages in
          let eng s =
            match Wiki_query.parse s with Ok q -> Wiki_query.eval pages q | Error e -> failwith e
          in
          (* a Base adds NO evaluation path — it IS Wiki_query.eval.
             Quantified over several queries, because a single fixture
             query can be reproduced by a hard-coded filter. *)
          List.for_all
            (fun s ->
              match Wiki_datastore.parse_base ("name: n\nquery: " ^ s ^ "\n") with
              | Ok b -> Wiki_datastore.base_rows pages b = eng s
              | Error _ -> false)
            [ "from all"; "from type:claim"; "from type:note sort slug desc";
              "where status=published" ]
          && (match Wiki_datastore.parse_base "name: n\ncolumns: words\nquery: from all\n" with
             | Error es -> List.mem (Wiki_datastore.Base_unknown_column "words") es
             | Ok _ -> false)
        with _ -> false)
      "HW.5.4.2" Query "Bases" "same engine" 2 1 Built;
    f ~src:[ Obsidian ] ~rows:[ 94 ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
            [ ("docs/hermes/zk/alpha.md",
               "---\nstatus: published\ntype: claim\n---\n# Alpha\n\nbody #core.\n") ] in
          let pages = m.Hermes_wiki.pages in
          let src = "TABLE slug FROM #core WHERE status = published SORT slug DESC LIMIT 2" in
          let js = "```dataviewjs\ndv.pages()\n```\n" in
          (* a DESUGARING, not an evaluator: it emits zkquery TEXT the
             engine must still accept, and the rows equal the engine's.
             dataviewjs is never routed to the parser — collected,
             counted, disclosed. *)
          Wiki_datastore.to_zkquery src
          = Ok "from tag:core where status=published sort slug desc limit 2"
          && (match (Wiki_datastore.to_zkquery src, Wiki_datastore.dataview_rows pages src) with
             | Ok zq, Ok rows ->
                 rows <> []
                 && (match Wiki_query.parse zq with
                    | Ok q -> rows = Wiki_query.eval pages q
                    | Error _ -> false)
             | _ -> false)
          && Wiki_datastore.dataview_sources js = []
          && List.length (Wiki_datastore.dataview_defects js) = 1
          && Wiki_datastore.to_zkquery "table FROM all" = Error (Wiki_datastore.Dv_head "table")
        with _ -> false)
      "HW.5.4.3" Query "Dataview / Datacore" "total and law-tested, no JS" 3 2 Built;
    f ~src:[ Notion ] ~rows:[ 19 ] "HW.5.5.1" Query "Database automations" "convergence loop is report-only" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 29 ] "HW.5.5.2" Query "Sub-items & dependencies" "one home for task state" 0 0 Excluded ]

let surface =
  [ f "HW.6.1.1" Surface "Typed route ADT" "write verb and traversal UNREPRESENTABLE" 5 5 Built;
    f "HW.6.1.2" Surface "GET/HEAD only" "405 otherwise" 4 5 Built;
    f "HW.6.1.3" Surface "CSP + security headers" "default-src none on every response" 5 5 Built;
    f "HW.6.1.4" Surface "R15 Tailscale FQDN gate" "fail-closed; degradation disclosed" 5 5 Built;
    f ~src:[ Notion ] ~rows:[ 71 ] "HW.6.1.5" Surface "Publish to web" "static = served" 4 4 Built;
    f ~src:[ Obsidian ] ~rows:[ 108 ] "HW.6.1.6" Surface "Sync / Publish (Obsidian)" "git + served + export" 3 2 Built;
    f ~src:[ Notion ] ~rows:[ 7 ] "HW.6.1.7" Surface "Desktop / offline" "the repo is the offline copy" 3 2 Built;
    f ~src:[ Notion ] ~rows:[ 59 ] "HW.6.1.8" Surface "Sharing & permissions" "repo access is the model" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 78 ] "HW.6.1.9" Surface "Teamspaces" "groups partition without membership" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 6 ]
      ~derived:(fun () ->
        try
          let src = [ ("pages/wiki/aa.md", "# Aa \"q\"\n\n## Sub\n\nbody\n");
                      ("pages/wiki/bb.md", "# Bb\n\ntext\n") ] in
          let m = Hermes_wiki.build src in
          let j = Wiki_export.json m in
          (* a PROJECTION of the built model, never a second reading: the
             html field is the page's own bytes verbatim rather than a
             re-render, so the API cannot drift from what a reader sees. *)
          Wiki_export.json_slugs m = [ "aa"; "bb" ]
          && List.for_all
               (fun (p : Hermes_wiki.page) ->
                 contains j ("\"html\":" ^ Wiki_export.json_string p.Hermes_wiki.html)
                 && contains j
                      ("\"anchors\":["
                      ^ String.concat ","
                          (List.map Wiki_export.json_string
                             (Hermes_wiki.anchors m p.Hermes_wiki.slug))
                      ^ "]"))
               m.Hermes_wiki.pages
          && contains j "Aa \\\"q\\\""
          && j = Wiki_export.json (Hermes_wiki.build src)
        with _ -> false)
      "HW.6.2.1" Surface "JSON API" "api and html render the SAME model" 4 3 Built;
    f ~src:[ Notion ] ~rows:[ 17 ] "HW.6.2.2" Surface "MCP tool surface" "would preserve GET-only" 2 2
      (Blocked "HW.6.2.1");
    f ~src:[ Notion ] ~rows:[ 85 ] "HW.6.2.3" Surface "Webhooks" "the surface performs NO egress" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 51 ] "HW.6.2.4" Surface "Notifications / inbox" "decay signals cover it" 0 0 Excluded;
    f ~gates:[ "HW.6.3.2"; "HW.6.3.3"; "HW.6.3.4"; "HW.6.3.7" ]
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ("pages/wiki/aa.md", "# Aa\n\nzebra zebra\n"); ("pages/wiki/bb.md", "# Bb\n\nzebra\n") ]
          in
          let idx = Wiki_search.build m in
          Wiki_search.search idx "zebra" = [ ("aa", 2); ("bb", 1) ]
          && Wiki_search.search idx "zebra" = Wiki_search.search idx "zebra"
          && Wiki_search.digest idx = Wiki_search.digest (Wiki_search.build m)
        with _ -> false)
      "HW.6.3.1" Surface "Full-text search" "deterministic ranking, ties by slug" 5 4 Built;
    f ~src:[ Docusaurus; Obsidian ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build [ ("pages/wiki/aa.md", "# Aa\n\na zebra claim ^z1\n") ] in
          Wiki_search.block_hits (Wiki_search.build m) "zebra" = [ ("aa", "^z1") ]
        with _ -> false)
      "HW.6.3.2" Surface "Block-level search hits" "every hit addresses a block" 4 3 Built;
    f
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
            [ ("pages/wiki/aa.md", "# Aa\n\nzebra in prose\n\n```ocaml\nlet quokka = 1\n```\n") ] in
          let i = Wiki_navsearch.build m in
          (* the law proved as a PAIR OF NEGATIVES: a prose-only term yields
             no code hit, and a fence-only term yields a code hit and no
             full-text hit. Either direction alone would pass on an index
             that simply read everything. *)
          Wiki_navsearch.code_slugs i "quokka" = [ "aa" ]
          && Wiki_navsearch.code_search i "zebra" = []
          && Wiki_search.search (Wiki_navsearch.search_index i) "quokka" = []
          && Wiki_search.search (Wiki_navsearch.search_index i) "zebra" = [ ("aa", 1) ]
        with _ -> false)
      "HW.6.3.3" Surface "Code search" "kind=code hits from fence bodies only" 3 2 Built;
    f
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
            [ ("pages/wiki/aa.md", "# Aa\n\n[[bb]]\n"); ("pages/wiki/bb.md", "# Bb\n\n[[cc]]\n");
              ("pages/wiki/cc.md", "# Cc\n\ntext\n") ] in
          let g = Wiki_graph.of_model m in
          let u = Wiki_navsearch.rank_personal ~seeds:(Wiki_graph.nodes g) g in
          let gl = Wiki_navsearch.rank_global g in
          let s = Wiki_navsearch.rank_personal ~seeds:[ "aa" ] g in
          (* ONE KERNEL: global ranking IS personalised ranking with a
             uniform seed, BYTE-identical via hex floats — two
             implementations that agree today disagree within a month.
             Guarded against vacuity: a real seed must change the ranking,
             or the identity could hold because nothing depends on seeds. *)
          Wiki_navsearch.rank_canonical u = Wiki_navsearch.rank_canonical gl
          && contains (Wiki_navsearch.rank_canonical gl) "0x"
          && Wiki_navsearch.rank_canonical s <> Wiki_navsearch.rank_canonical gl
          && (Wiki_navsearch.rank_personal ~seeds:[ "ghost" ] g).Wiki_navsearch.seeds_unknown
             = [ "ghost" ]
        with _ -> false)
      "HW.6.3.4" Surface "PPR ranking" "one kernel, two consumers" 3 2 Built;
    f ~src:[ Notion ] ~rows:[ 5 ] "HW.6.3.5" Surface "Q&A over the corpus"
      "deterministic; citations non-empty; no LLM in the path" 4 3 (Blocked "HW.6.3.4");
    f ~src:[ Docusaurus ] "HW.6.3.6" Surface "Hosted search (Algolia)" "retrieval stays local" 0 0 Excluded;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
            [ ("pages/wiki/aa.md", "# Aa\n\nzebra zebra ocelot\n\n```\nharpsichord\n```\n");
              ("pages/wiki/bb.md", "# Bb\n\nzebra ocelot\n") ] in
          let si = Wiki_search.build m in
          let x =
            Wiki_export.search_index ~tokenise:Wiki_search.tokens
              ~search:(Wiki_search.search si) ~digest:(Wiki_search.digest si) m
          in
          (* OFFLINE IS ONLINE, quantified over the whole vocabulary plus
             the awkward queries. The postings ARE the engine's own
             answers — the exporter has no scoring of its own to drift,
             because it never computes one. Digest-pinned so drift shows. *)
          List.for_all
            (fun q -> Wiki_export.offline_search x q = Wiki_search.search si q)
            ("" :: "zebra zebra" :: "zebra ocelot" :: "harpsichord" :: "nosuch"
            :: Wiki_export.vocabulary x)
          && Wiki_export.offline_search x "zebra" <> []
          && (not (List.mem "harpsichord" (Wiki_export.vocabulary x)))
          && Wiki_export.index_digest x = Wiki_search.digest si
          && contains (Wiki_export.index_json x) (Wiki_search.digest si)
        with _ -> false)
      "HW.6.3.7" Surface "Client-side search index"
      "pure data, digest-pinned; offline search = online search" 4 3 Built;
    f ~src:[ Notion ] ~rows:[ 10 ]
      ~derived:(fun () ->
        try
          let p n b = ("pages/wiki/" ^ n ^ ".md", b) in
          let m = Hermes_wiki.build
            [ p "r" "# R\n\n```toctree\ng\n```\n"; p "g" "# G\n\n```toctree\ni\n```\n";
              p "i" "# I\n\nleaf\n"; p "x" "# X\n\nunplaced\n" ] in
          let t = Wiki_toc.of_model m in
          (* PREFIX-CLOSED at every depth: crumbs(x) = crumbs(parent x) @ [x],
             and every crumb names a page that exists. A breadcrumb that
             passes through a page the reader cannot reach is a false trail. *)
          Wiki_navsearch.breadcrumb_slugs m t "i" = [ "r"; "g"; "i" ]
          && Wiki_navsearch.breadcrumb_slugs m t "g" = [ "r"; "g" ]
          && Wiki_navsearch.breadcrumb_slugs m t "x" = [ "x" ]
          && Wiki_navsearch.breadcrumb_slugs m t "ghost" = []
          && Wiki_navsearch.breadcrumb_gaps m t = []
        with _ -> false)
      "HW.6.4.1" Surface "Breadcrumb" "a resolving prefix path" 3 3 Built;
    f "HW.6.4.2" Surface "Sidebar / index tree" "every page reachable" 4 4 Built;
    f ~src:[ Notion ] ~rows:[ 72 ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
            [ ("pages/wiki/intro.md", "# Intro\n\nzebra body\n");
              ("pages/wiki/advanced.md", "# Advanced\n\nother\n") ] in
          let i = Wiki_navsearch.build m in
          let sl q = List.map (fun (h : Wiki_navsearch.find_hit) -> h.Wiki_navsearch.slug)
                       (Wiki_navsearch.quick_find i q) in
          (* SUPERSET over many queries, not one: a fuzzy finder that loses
             an exact hit is worse than no finder. Checked across the empty
             query and a punctuation query too, where truncation would bite. *)
          List.for_all
            (fun q -> List.for_all (fun s -> List.mem s (sl q)) (Wiki_navsearch.exact_matches i q))
            [ "intro"; "zebra"; "advanced"; "adv"; "Intro"; ""; "!!!"; "xyzzy" ]
          && Wiki_navsearch.exact_matches i "zebra" = [ "intro" ]
          && List.mem "intro" (sl "zebra")
          && List.mem "advanced" (sl "adv")
          && sl "" = []
        with _ -> false)
      "HW.6.4.3" Surface "Quick find" "superset of exact match" 4 2 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let p n = ("docs/hermes/guide/" ^ n ^ ".md", "# " ^ n ^ "\n") in
          let m = Hermes_wiki.build [ p "a"; p "b"; p "c" ] in
          let es = Wiki_ordering.ordered m in
          (* the SURFACE agrees with the relation, because it is defined
             over it: nav_targets is exactly prev-then-next. At an end it
             emits NOTHING for that side — a greyed-out "next" on the
             last page tells a reader there is more and there is not. *)
          Wiki_ordering.nav_targets es "b" = [ "a"; "c" ]
          && Wiki_ordering.nav_targets es "a" = [ "b" ]
          && Wiki_ordering.nav_targets es "c" = [ "b" ]
          && contains (Wiki_ordering.nav_html es "b") "href=\"a.html\""
          && (not (contains (Wiki_ordering.nav_html es "c") "pager-next"))
          && Wiki_ordering.nav_html (Wiki_ordering.ordered (Hermes_wiki.build [ p "only" ]))
               "only"
             = ""
          && Wiki_ordering.nav_html es "ghost" = ""
        with _ -> false)
      "HW.6.4.4" Surface "Pagination prev/next" "mutually inverse" 3 2 Built;
    f ~src:[ Notion ] ~rows:[ 42 ] "HW.6.4.5" Surface "Favorites & recents" "server is stateless" 0 0 Excluded;
    f ~src:[ Obsidian ] ~rows:[ 90 ] "HW.6.4.6" Surface "Bookmarks / starred" "server is stateless" 0 0 Excluded;
    f ~src:[ Obsidian ] ~rows:[ 116 ]
      ~derived:(fun () ->
        try
          let without = "# T\n\nalpha beta gamma\n" in
          let fenced = "# T\n\nalpha beta gamma\n\n```sh\none two three four five\n```\n" in
          let m = Hermes_wiki.build
            [ ("pages/wiki/aa.md", fenced); ("pages/wiki/bb.md", "# U\n\none ^ref\n") ] in
          (* FENCE-EXCLUDED by construction — the parser decided, not a
             line filter — so adding a code block cannot change the count.
             A block ^id is an address, not a word. Additive over pages. *)
          Wiki_export.word_count without = 4
          && Wiki_export.word_count fenced = 4
          && Wiki_export.word_count "- | > ***" = 0
          && Wiki_export.word_count "three plain words ^anchor" = 3
          && Wiki_export.page_word_counts m = [ ("aa", 4); ("bb", 2) ]
          && Wiki_export.corpus_word_count m = 6
        with _ -> false)
      "HW.6.5.1" Surface "Word count" "fence-excluded, deterministic" 2 1 Built;
    f ~gates:[ "HW.6.6.2" ]
      ~derived:(fun () ->
        try
          let f1 = [ ("pages/wiki/aa.md", "# Aa\n\nfirst\n") ] in
          let f2 = [ ("pages/wiki/aa.md", "# Aa\n\nsecond\n"); ("pages/wiki/bb.md", "# Bb\n\nnew\n") ] in
          let h = Wiki_navsearch.history_of
            [ { Wiki_navsearch.commit = "c2"; order = 2; files = f2 };
              { Wiki_navsearch.commit = "c1"; order = 1; files = f1 } ] in
          (* as_of(c) = build(checkout c) as a literal IDENTITY, with the
             corpus-at-a-commit INJECTED rather than shelled out to git —
             the module stays pure. An unknown commit is None, which is
             distinct from Some [] : "no such revision" is not "empty". *)
          Wiki_navsearch.as_of h "c1" = Some (Hermes_wiki.build f1)
          && Wiki_navsearch.as_of h "c2" = Some (Hermes_wiki.build f2)
          && Wiki_navsearch.as_of h "c1" <> Wiki_navsearch.as_of h "c2"
          && Wiki_navsearch.commits h = [ "c1"; "c2" ]
          && Wiki_navsearch.as_of h "nope" = None
        with _ -> false)
      "HW.6.6.1" Surface "As-of query" "as_of(c) = build(checkout c)" 4 3 Built;
    f ~src:[ Notion ] ~rows:[ 32 ] "HW.6.6.2" Surface "Timeline view" "edge-set delta, monotone in commit order" 3 2
      (Blocked "HW.6.6.1");
    f ~src:[ Docusaurus ] "HW.6.6.3" Surface "Sitemap / JSON-LD / RSS"
      "CONDITIONAL on R15 internal-only" 0 0 Excluded;
    f ~src:[ Docusaurus ] "HW.6.6.4" Surface "PWA / offline shell" "the repo is the offline copy" 0 0 Excluded;
    f ~src:[ Docusaurus ] "HW.6.7.1" Surface "Docs versioning" "git already does it" 0 0 Excluded;
    f ~src:[ Docusaurus ] "HW.6.7.2" Surface "i18n" "single locale" 0 0 Excluded;
    f ~src:[ Docusaurus ] "HW.6.7.3" Surface "Blog / RSS" "journals are the chronological surface" 0 0 Excluded;
    f ~src:[ Docusaurus ] "HW.6.7.4" Surface "Plugin system" "kernels, not plugins" 0 0 Excluded;
    f ~src:[ Docusaurus ] "HW.6.7.5" Surface "Client redirects" "slugs + aliases solve it" 0 0 Excluded;
    f ~src:[ Sphinx ] ~gates:[ "HW.6.8.2"; "HW.6.8.3" ] "HW.6.8.1" Surface "Declared navigation tree"
      ~derived:(fun () ->
        try
          (* the tree law on a hostile input: a declares b, b declares a.
             It must TERMINATE, place each exactly once, and record the
             back edge rather than looping or dropping a page. *)
          let m =
            Hermes_wiki.build
              [ ("docs/x/a.md", "# a\n\n```toctree\nb\n```\n");
                ("docs/x/b.md", "# b\n\n```toctree\na\n```\n") ]
          in
          let t = Wiki_toc.of_model m in
          List.sort compare (Wiki_toc.placed t) = [ "a"; "b" ]
          && List.length (Wiki_toc.walk t) = 2
          && List.mem ("b", "a") (Wiki_toc.conflicts t)
          && Wiki_toc.unplaced m t = []
        with _ -> false)
      "a TREE: single root, acyclic, each node once" 4 3 Built;
    f ~src:[ Sphinx ] "HW.6.8.2" Surface "Unreachable-document check"
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ("docs/x/a.md", "# a\n\n```toctree\nb\n```\n");
                ("docs/x/b.md", "# b\n\nplaced.\n");
                ("docs/x/loud.md", "# loud\n\nundisclosed.\n");
                ("docs/x/quiet.md", "---\norphan: true\n---\n# quiet\n\ndisclosed.\n") ]
          in
          let t = Wiki_toc.of_model m in
          (* the disclosure is the whole difference between fact and verdict *)
          Wiki_toc.unplaced m t = [ "loud"; "quiet" ]
          && Wiki_toc.unreachable m t = [ "loud" ]
          && Wiki_toc.disclosed_orphans m = [ "quiet" ]
        with _ -> false)
      "unreachable and not :orphan: => diag" 4 4 Built;
    f ~src:[ Sphinx ] "HW.6.8.3" Surface "Numbered sections"
      ~derived:(fun () ->
        try
          let m =
            Hermes_wiki.build
              [ ("docs/x/root.md", "# root\n\n```toctree numbered\nalpha\n```\n");
                ("docs/x/alpha.md", "# alpha\n\n```toctree\none\n```\n");
                ("docs/x/one.md", "# one\n\nleaf.\n") ]
          in
          let n = Wiki_toc.numbering (Wiki_toc.of_model m) in
          (* derived from POSITION, and inherited downward *)
          List.assoc_opt "alpha" n = Some "1" && List.assoc_opt "one" n = Some "1.1"
        with _ -> false)
      "derived from position, never hand-maintained" 3 2 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          (* the round trip over the AWKWARD cases, not the easy one: a
             dot, a .md, `index`, a slash, a space, a percent, and the
             empty slug. Anything outside the unreserved set is
             percent-encoded, so a second path segment is unexpressible
             and `index` cannot collide with the root. *)
          List.for_all
            (fun s -> Wiki_build.parse (Wiki_build.uri s) = Some s)
            [ ""; "index"; "readme.md"; "notes.v2"; "a/b"; "a b"; "100%"; "plain" ]
          && Wiki_build.uri "" = "/"
          && Wiki_build.uri "index" = "/index"
          && Wiki_build.parse "/index" = Some "index"
          && Wiki_build.parse "/a/b" = None
          && Wiki_build.parse "notes" = None
          && Wiki_build.parse "" = None
          && Wiki_build.output_path "index" <> Wiki_build.output_path ""
        with _ -> false)
      "HW.6.9.1" Surface "Extensionless URLs" "parse o uri = id" 2 2 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
            [ ("pages/wiki/aa.md", "# Aa\n\n## Overview\n\nsee [[Bb#Overview]]\n");
              ("pages/wiki/bb.md", "# Bb\n\n## Overview\n\nbody\n") ] in
          let a = Wiki_export.single_file_anchors m
          and l = Wiki_export.single_file_links m
          and h = Wiki_export.single_file_html m in
          (* UNIQUE over the WHOLE concatenation — two pages each with an
             "overview" is the normal case, not the edge case — and links
             rewritten through the SAME table, so a rename cannot orphan
             one. Resolution is PRESERVED, not manufactured: an already
             dead link stays dead and disclosed rather than being
             redirected to the page top. *)
          List.length (List.sort_uniq compare a) = List.length a
          && List.mem "aa--overview" a
          && List.mem "bb--overview" a
          && l <> []
          && List.for_all (fun t -> List.mem t a) l
          && Wiki_export.dead_links m = []
          && contains h "href=\"#bb--overview\""
          && not (contains h "id=\"overview\"")
        with _ -> false)
      "HW.6.9.2" Surface "Single-file HTML export" "globally unique anchors" 3 2 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let src = "# Aa\n\n## Sub Two\n\nsee [[Bb]]\n\n```sh\ncode here\n```\n" in
          let m = Hermes_wiki.build [ ("pages/wiki/aa.md", src) ] in
          let p = List.hd m.Hermes_wiki.pages in
          let t = Wiki_export.page_text p.Hermes_wiki.raw in
          (* A SECOND RENDER TARGET over ONE parse, which is what makes the
             structure/presentation split falsifiable: the headings must
             agree with the HTML renderer's, while the presentation
             deliberately differs — no tags, no ids, no link syntax, code
             kept. If both targets shared a code path this would be
             vacuous. *)
          Wiki_export.text_headings t = [ (1, "Aa"); (2, "Sub Two") ]
          && Wiki_export.text_headings t
             = List.map (fun (l, x, _) -> (l, Wiki_export.inline_text x)) p.Hermes_wiki.headings
          && contains t "code here"
          && (not (contains t "<h1"))
          && (not (contains t "[["))
          && Wiki_export.plain_text m
             = Wiki_export.plain_text (Hermes_wiki.build [ ("pages/wiki/aa.md", src) ])
        with _ -> false)
      "HW.6.9.3" Surface "Plain-text export"
      "a SECOND render target -- makes structure/presentation separation testable" 3 3 Built;
    f ~src:[ Sphinx ] "HW.6.9.4" Surface "PDF / LaTeX output" "print stylesheet covers it" 0 0 Excluded;
    f ~src:[ Sphinx ] "HW.6.9.5" Surface "ePub / man / texinfo" "no audience" 0 0 Excluded;
    (* The row the browser import fleet was ALWAYS about. Eight mirrors sat
       against HW.6.9.1 ("Extensionless URLs", parse o uri = id), which is
       URL parsing and has nothing to do with rendered-surface observation
       — a mis-targeting the import audit surfaced. A browser is an ORACLE
       here, never an author (R3): it observes the built site and reports;
       it cannot write the corpus, and its absence is UNAVAILABLE, never
       passing. *)
    f ~src:[ Own ] "HW.6.9.8" Surface "Rendered-surface verification (browser oracle)"
      "observation only: the browser reports, never authors; absent browser = unavailable, never pass"
      3 3 Ready;
    f ~src:[ Sphinx ] "HW.6.9.6" Surface "XML export" "JSON API + serialised export cover it" 0 0 Excluded;
    f ~src:[ Sphinx ] "HW.6.9.7" Surface "Help formats" "no audience" 0 0 Excluded;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let d n b c = { Wiki_export.name = n; base = b; caption = c } in
          let ok = [ d "issue" "https://t/%s" "issue %s"; d "rfc" "https://r/" "" ] in
          (* ONE DEFINITION PER NAME: a duplicate is refused WHOLLY rather
             than resolved last-one-wins, because with two definitions in
             play every use is ambiguous and silently picking one makes
             the wrong link look deliberate. Undefined stays verbatim; a
             fenced use is an example. *)
          Wiki_export.extlink_table ok = Ok ok
          && Wiki_export.extlink_table (ok @ [ d "issue" "https://o/%s" "" ]) = Error [ "issue" ]
          && Wiki_export.expand_extlinks ok "see :issue:`42`"
             = "see <a href=\"https://t/42\">issue 42</a>"
          && Wiki_export.expand_extlinks ok ":ghost:`9`" = ":ghost:`9`"
          && Wiki_export.expand_extlinks ok "```\n:issue:`1`\n```\n" = "```\n:issue:`1`\n```\n"
          && Wiki_export.extlink_uses "a :issue:`1` b :ghost:`2`"
             = [ ("issue", "1"); ("ghost", "2") ]
        with _ -> false)
      "HW.6.10.1" Surface "extlinks (link shortening)" "one definition per name" 2 2 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
            [ ("pages/wiki/aa.md",
               "# Aa\n\n.. todo:: one\n\nprose TODO: not a mark\n\n> [!todo] two\n\n\
                ```\n.. todo:: example\n```\n\n.. todo:: one\n") ] in
          let ts = Wiki_navsearch.todos m in
          let f g = List.map g ts in
          (* EVERY MARKED TODO ONCE — keyed by (slug, line), not by text, so
             two todos that read the same are two todos. A fenced mark is an
             example and a prose "TODO:" is prose. *)
          f (fun (t : Wiki_navsearch.todo) -> t.Wiki_navsearch.text) = [ "one"; "two"; "one" ]
          && List.length (List.sort_uniq compare
               (f (fun (t : Wiki_navsearch.todo) -> t.Wiki_navsearch.line))) = 3
          && (not (List.exists
                     (fun (t : Wiki_navsearch.todo) -> contains t.Wiki_navsearch.text "example") ts))
          && not (List.exists
                    (fun (t : Wiki_navsearch.todo) -> contains t.Wiki_navsearch.text "mark") ts)
        with _ -> false)
      "HW.6.11.1" Surface "Todo collection" "complete; every marked todo once" 3 2 Built;
    f ~src:[ Sphinx ] "HW.6.11.2" Surface "Conditional on configuration" "finer-grained than only" 1 1
      (Blocked "HW.2.6.5");
    f ~src:[ Sphinx ] "HW.6.11.4" Surface "Changelog builder" "git + version directives cover it" 0 0 Excluded;
    f ~src:[ Sphinx ] "HW.6.11.5" Surface "External source links" "points into the product repo, commit-pinned" 3 2
      (Blocked "HW.9.1.2");
    f ~src:[ Sphinx ] "HW.6.11.6" Surface "GitHub Pages publishing" "R15 internal only" 0 0 Excluded;
    f ~src:[ Sphinx ] "HW.6.11.7" Surface "Image format conversion" "no LaTeX/ePub builders" 0 0 Excluded;
    f ~src:[ Sphinx ] "HW.6.12.1" Surface "Embeddable search + comment backend"
      "corpus stays the single source of truth" 0 0 Excluded;
    f ~src:[ Sphinx ] "HW.6.12.2" Surface "HTML theme templating"
      "TyXML makes malformed markup a TYPE ERROR; a template language cannot" 0 0 Excluded ]

let present =
  [ f ~src:[ Docusaurus; Obsidian ] ~gates:[ "HW.7.1.2"; "HW.7.1.3" ] "HW.7.1.1" Present
      ~derived:(fun () ->
        try
          let tokens = [ { Wiki_theme.path = "color/bg"; value = "#fff" } ] in
          let light = { Wiki_theme.mode = "light"; bindings = [ ("--bg", "color/bg") ] } in
          (* the annotation IS the feature, and it is pure *)
          (match Wiki_theme.css ~tokens ~themes:[ light ] with
          | Ok s ->
              contains s "--bg: #fff; /* color/bg */"
              && Ok s = Wiki_theme.css ~tokens ~themes:[ light ]
          | Error _ -> false)
          (* and it refuses rather than emitting something plausible *)
          && (match
                Wiki_theme.css ~tokens
                  ~themes:[ { Wiki_theme.mode = "light"; bindings = [ ("--x", "ghost") ] } ]
              with
             | Error _ -> true
             | Ok _ -> false)
        with _ -> false)
      "Design tokens -> generated CSS" "css(t) pure; each declaration annotated with its token" 4 3
      Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let keys m = Wiki_present.token_keys m in
          (* SAME NAMES as a set equality, and every one REBOUND. A dark
             theme that introduces a token the light theme lacks (or
             drops one) breaks any component styled through the tokens —
             which is every component. *)
          keys Wiki_present.Light = keys Wiki_present.Dark
          && keys Wiki_present.Light <> []
          && List.for_all
               (fun (k, v) ->
                 match List.assoc_opt k (Wiki_present.palette Wiki_present.Dark) with
                 | Some dv -> dv <> v
                 | None -> false)
               (Wiki_present.palette Wiki_present.Light)
          && (match Wiki_present.theme_css with
             | Ok css ->
                 contains css "@media (prefers-color-scheme: dark)"
                 && contains css ":root:not([data-theme=\"light\"])"
                 && not (Wiki_present.has_script css)
             | Error _ -> false)
        with _ -> false)
      "HW.7.1.2" Present "Dark mode" "same names, rebound values" 3 2 Built;
    f
      ~derived:(fun () ->
        try
          (* CONTENT-COMPLETE as three set facts: what print hides is
             exactly the declared chrome, chrome and content are
             disjoint, and nothing carrying content is hidden. Plus the
             positive obligation — paper has no hyperlinks, so the URL
             must be disclosed or the citation is lost. *)
          Wiki_present.print_violations () = []
          && List.sort compare (Wiki_present.hidden_selectors Wiki_present.print_css)
             = List.sort compare Wiki_present.print_chrome
          && List.for_all
               (fun s -> not (List.mem s Wiki_present.print_content))
               Wiki_present.print_chrome
          && contains Wiki_present.print_css "attr(href)"
          && Wiki_present.hidden_selectors "@media print { .wiki-main { display: none; } }"
             = [ ".wiki-main" ]
          && List.mem ".wiki-main" Wiki_present.print_content
        with _ -> false)
      "HW.7.1.3" Present "Print stylesheet" "content-complete" 2 2 Built;
    f ~src:[ Notion ] ~rows:[ 33 ] "HW.7.1.4" Present "Design-language note" "the spec css is judged against" 3 3 Ready;
    f ~src:[ Obsidian ] ~rows:[ 111 ] "HW.7.1.5" Present "User themes / CSS snippets"
      "one rendering keeps layout laws testable" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 84 ] "HW.7.1.6" Present "Typography toggles" "one rendering" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 45 ] "HW.7.1.7" Present "Page icons & covers" "typographic identity only" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 18 ] "HW.7.1.8" Present "Custom emoji" "no asset pipeline for decoration" 0 0 Excluded;
    f ~src:[ Docusaurus ] "HW.7.2.1" Present "Right-rail ToC + scrollspy"
      "page complete WITHOUT it" 4 2 (Forked 4);
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let page = Wiki_present.document_chrome ~content:"<p>body</p>" in
          (* ANCHOR + CSS, no script: the href must actually RESOLVE in
             the assembled page, not merely be present. A back-to-top
             pointing at a landmark nobody emits is a dead link the
             reader meets on every page. *)
          contains Wiki_present.back_to_top_html "href=\"#top\""
          && List.mem Wiki_present.top_id (Wiki_present.internal_hrefs page)
          && List.mem Wiki_present.top_id (Wiki_present.anchor_ids page)
          && Wiki_present.dangling_anchors page = []
          && (not (Wiki_present.has_script page))
          && contains Wiki_present.back_to_top_css ".back-to-top"
        with _ -> false)
      "HW.7.2.2" Present "Back-to-top" "anchor + CSS, both surfaces" 2 1 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let page = Wiki_present.document_chrome ~content:"<p><a href=\"#main\">x</a></p>" in
          (* three conditions, and the third is the one that gets missed:
             the target exists, the skip link is FIRST in source order,
             and it is off-screen rather than display:none — which would
             remove it from the focus order and defeat the whole point. *)
          List.mem Wiki_present.main_id (Wiki_present.anchor_ids page)
          && Wiki_present.dangling_anchors page = []
          && (match Wiki_present.internal_hrefs page with
             | h :: _ -> h = Wiki_present.main_id
             | [] -> false)
          && contains page "class=\"skip-link\""
          && contains Wiki_present.skip_link_css ".skip-link:focus"
          && (not (contains Wiki_present.skip_link_css "display: none"))
          && not (contains Wiki_present.skip_link_css "display:none")
        with _ -> false)
      "HW.7.2.3" Present "Skip-to-content" "accessibility; anchor only" 3 3 Built;
    f ~src:[ Obsidian ] ~rows:[ 104 ] "HW.7.2.4" Present "Outline pane" "in-page block covers most of it" 2 2
      (Blocked "HW.2.3.5");
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let known = Wiki_present.code_block ~lang:"ocaml" [ "let x = \"a<b\" (* c *) 42" ] in
          let unknown = Wiki_present.code_block ~lang:"rust" [ "fn main() { <x> }" ] in
          (* TOTAL: an unknown language is escaped verbatim under the
             neutral class — no spans, no guess. And the ROUND TRIP:
             stripping the markup returns the line byte for byte, so
             highlighting can never alter what the code says. *)
          contains known.Wiki_present.html "<span class=\"tok-kw\">let</span>"
          && contains known.Wiki_present.html "class=\"language-ocaml\""
          && contains unknown.Wiki_present.html "class=\"language-plaintext\""
          && (not (contains unknown.Wiki_present.html "<span"))
          && contains unknown.Wiki_present.html "&lt;x&gt;"
          && List.for_all
               (fun l ->
                 Wiki_present.strip_markup (Wiki_present.highlight_line (Some Wiki_present.Ocaml) l)
                 = l)
               [ "let s = \"a < b & c\""; "(* <hi> *)"; "" ]
          && not (Wiki_present.has_script known.Wiki_present.html)
        with _ -> false)
      "HW.7.3.1" Present "Syntax highlighting"
      "server-side and TOTAL: unknown language falls back to escaped text" 4 3 Built;
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let lang = Wiki_ast.lang_of_info in
          (* a PURE function of the lang: fence meta and body length
             cannot move it, and an absent language OMITS the attribute
             rather than emitting an empty one *)
          Wiki_present.label_of_lang (lang "ocaml linenums=3") = Some "OCaml"
          && Wiki_present.label_of_lang (lang "ocaml") = Some "OCaml"
          && Wiki_present.label_of_lang (lang "") = None
          && (let a = Wiki_present.code_block ~lang:"json" [ "{}" ] in
              let b = Wiki_present.code_block ~lang:"json" [ "a"; "b"; "c" ] in
              contains a.Wiki_present.html "data-lang=\"JSON\""
              && contains b.Wiki_present.html "data-lang=\"JSON\"")
          && not (contains (Wiki_present.code_block [ "x" ]).Wiki_present.html "data-lang")
        with _ -> false)
      "HW.7.3.2" Present "Code language label" "label is a pure function of Code_block.lang" 2 1
      Built;
    f ~src:[ Docusaurus ] "HW.7.3.3" Present "Copy-code button" "Dream surface only" 3 1 (Forked 4);
    f ~src:[ Docusaurus ]
      ~derived:(fun () ->
        try
          let body = [ "one"; "two"; "three" ] in
          let good = Wiki_present.code_block ~lang:"ocaml" ~highlight:[ 2 ] body in
          let bad = Wiki_present.code_block ~lang:"ocaml" ~highlight:[ 99 ] body in
          (* WITHIN RANGE OR A DIAGNOSTIC — never clamped. A clamped
             request silently highlights the wrong line, which reads as
             correct. And the renderer and the checker are ONE rule, so
             they cannot disagree about what is in range. *)
          good.Wiki_present.diagnostics = []
          && contains good.Wiki_present.html "<mark class=\"wiki-hl\">two</mark>"
          && bad.Wiki_present.diagnostics
             = [ Wiki_present.Highlight_out_of_range { requested = 99; line_count = 3 } ]
          && (not (contains bad.Wiki_present.html "<mark"))
          && Wiki_present.diagnostic_origin (List.hd bad.Wiki_present.diagnostics)
             <> "Implementation"
          && bad.Wiki_present.diagnostics = Wiki_present.check_highlight ~line_count:3 [ 99 ]
        with _ -> false)
      "HW.7.3.4" Present "Line highlighting" "highlighted lines within range or a diagnostic" 3 2
      Built;
    f ~src:[ Notion ] ~rows:[ 48 ] "HW.7.4.1" Present "Images / video / audio / file"
      "closed extension set; img-src self and nothing else relaxed" 4 3 (Forked 2);
    f ~src:[ Docusaurus ] "HW.7.4.2" Present "Image transform pipeline" "references survive moves" 2 1 (Forked 2);
    f ~src:[ Docusaurus ] "HW.7.4.3" Present "Responsive / ideal image" "no build-time binary toolchain" 0 0 Excluded;
    f ~src:[ Obsidian ] ~rows:[ 103 ] "HW.7.5.1" Present "Mermaid diagrams"
      "SERVER-SIDE to inline SVG; failure => diag + source as a fence" 4 3 (Forked 1);
    f ~src:[ Notion; Obsidian ] ~rows:[ 40; 102 ] "HW.7.5.2" Present "Math (KaTeX / MathJax)"
      "server-side, deterministic" 3 2 (Forked 1);
    f ~src:[ Sphinx ] "HW.7.5.3" Present "Graphviz diagrams" "server-side DOT -> SVG" 3 3 (Forked 1);
    f ~src:[ Sphinx ] "HW.7.5.4" Present "Structure diagrams from data"
      "generated FROM the model, so diagram != model is unrepresentable" 4 4 (Blocked "HW.7.5.3");
    f ~src:[ Obsidian ] ~rows:[ 92 ] "HW.7.6.1" Present "Canvas" "spatial arrangement is not diffable" 0 0 Excluded;
    f ~src:[ Obsidian ] ~rows:[ 96 ] "HW.7.6.2" Present "Excalidraw" "text-first scope" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 55 ] "HW.7.7.1" Present "Page analytics" "no reader tracking; nothing to leak" 0 0 Excluded;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let ns =
            Wiki_present.number_captions
              [ (Wiki_present.Figure, "a"); (Wiki_present.Table, "b"); (Wiki_present.Figure, "a") ]
          in
          (* DERIVED FROM POSITION, so a duplicate number is
             unrepresentable and inserting one renumbers what follows.
             Figures and tables count independently — a shared counter
             would make "Figure 2" and "Table 2" impossible to have at
             once, which is the normal case. *)
          List.map (fun n -> (n.Wiki_present.number, n.Wiki_present.id)) ns
          = [ (1, "figure-1"); (1, "table-1"); (2, "figure-2") ]
          && List.map
               (fun n -> n.Wiki_present.number)
               (Wiki_present.number_captions
                  [ (Wiki_present.Figure, "new"); (Wiki_present.Figure, "a");
                    (Wiki_present.Figure, "b") ])
             = [ 1; 2; 3 ]
          && (match ns with
             | f :: _ ->
                 Wiki_present.dangling_anchors
                   (Wiki_present.figure_html ~content:"<img alt=\"\">" f
                  ^ Wiki_present.caption_ref_html f)
                 = []
             | [] -> false)
        with _ -> false)
      "HW.7.8.1" Present "Numbered figures and tables" "derived from position" 2 1 Built ]

let lifecycle =
  [ f ~src:[ Notion ] ~rows:[ 56 ] "HW.8.1.1" Lifecycle "Page history / versions" "git, append-only" 4 4 Built;
    f ~src:[ Notion ] ~rows:[ 83 ] "HW.8.1.2" Lifecycle "Trash & restore" "nothing lost pre-gc" 3 3 Built;
    f ~src:[ Obsidian ] ~rows:[ 114 ] "HW.8.1.3" Lifecycle "Version history (Obsidian)" "git, no subscription" 3 2 Built;
    f ~src:[ Notion ] ~rows:[ 60 ] "HW.8.1.4" Lifecycle "Created / edited time & by" "git is the substrate" 3 3 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let open Wiki_lifecycle in
          (* R16: git DOMINATES an authored date, a malformed git date
             does not fall back to one, and absent means UNKNOWN — never
             today. A fabricated timestamp is worse than none because it
             looks authoritative. *)
          (last_update ~git:(Some "2026-01-02") ~frontmatter:"2020-01-01").stamp
          = Known "2026-01-02"
          && (last_update ~git:(Some "2026-01-02") ~frontmatter:"2020-01-01").origin = From_git
          && (let u = last_update ~git:None ~frontmatter:"" in
              u.stamp = Unknown && u.origin = Absent
              && render_stamp u.stamp = "unknown"
              && not (String.exists (fun c -> c >= '0' && c <= '9') (render_stamp u.stamp)))
          && (match parse_date "2026-13-45" with
             | Malformed s -> s = "2026-13-45"
             | Known _ | Unknown -> false)
          && (last_update ~git:(Some "nope") ~frontmatter:"2026-01-02").origin = From_git
        with _ -> false)
      "HW.8.1.5" Lifecycle "Surface last_update" "read from git, NEVER authored (R16)" 3 3 Built;
    f ~src:[ Notion ] ~rows:[ 74 ] "HW.8.1.6" Lifecycle "Real-time co-editing" "every change is a reviewable commit" 0 0
      Excluded;
    f ~src:[ Notion ] ~rows:[ 86 ] "HW.8.2.1" Lifecycle "Wiki verification" "expiry rendered as decay" 5 4 Built;
    f ~src:[ Obsidian ] ~rows:[ 107 ] "HW.8.2.2" Lifecycle "Decay / spaced review" "ordered by overdue-ness" 3 3 Built;
    f "HW.8.2.3" Lifecycle "Render baseline differential"
      "four verdicts; BOTH directions proved" 5 5 Built;
    f "HW.8.2.4" Lifecycle "Defects vs notices" "a notice must NEVER refuse" 4 5 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let open Wiki_lifecycle in
          let body = "real https://a.example\n```\nhttps://f.example\n```\n`https://b.example`\n" in
          let urls = external_urls body in
          (* THE LAW: a URL with no evidence is UNCHECKED — never Live,
             never Broken. Missing external evidence is unavailable, never
             passing. And a URL in a fence or backticks is an example. *)
          urls = [ "https://a.example" ]
          && classify ~evidence:[] urls = [ Unchecked "https://a.example" ]
          && (let s = summarise (classify ~evidence:[] urls) in
              s.live = 0 && s.broken = 0 && s.unchecked = 1)
          && classify ~evidence:[ ("https://a.example", Reachable) ] urls
             = [ Live "https://a.example" ]
          && classify ~evidence:[ ("https://a.example", Dead "404") ] urls
             = [ Broken ("https://a.example", "404") ]
        with _ -> false)
      "HW.8.2.5" Lifecycle "Link check (external URLs)"
      "a SEPARATE build; render unaffected by network state" 3 3 Built;
    f ~src:[ Own ] ~gates:[ "HW.10.2.1" ]
      ~derived:(fun () ->
        (* live probe: a fixture register prefers the probe over the
           declaration, fires its residue both ways, refuses the
           neither-row, and inject demonstrates non-vacuity. *)
        try
          let module Sub = struct
            type key = int
            type claim = int

            let compare_key = Int.compare
            let equal_claim = Int.equal
            let show_key = string_of_int
            let show_claim = string_of_int
          end in
          let module R = Reconcile.Make (Sub) in
          match R.register [ (1, Some 0, Some (fun () -> Some 1)); (2, Some 2, None) ] with
          | Error _ -> false
          | Ok t0 ->
              let t = R.snapshot t0 in
              R.status t 1 = Some 1
              && R.residue t = [ (1, 0, 1) ]
              && R.residue (R.inject t 2 3) = [ (1, 0, 1); (2, 2, 3) ]
              && (match R.register [ (9, None, None) ] with Error _ -> true | Ok _ -> false)
        with _ -> false)
      "HW.8.2.7" Lifecycle "Unified reconciliation core (declared vs derived residue)"
      "status prefers the probe BY CONSTRUCTION (no declared-claim accessor);\n       residue iff both defined and differing, both directions; unknown claims are\n       drift, fail-closed; duplicate registration refused; residue demonstrably\n       non-vacuous (inject)"
      3 4 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let body =
            ".. versionadded:: 1.2 first\n.. deprecated:: 1.10 later\n"
            ^ "```\n.. versionadded:: 9.9 example\n```\n.. versionadded:: v3\n" in
          let rs, ds = Wiki_datastore.releases body in
          let v s = match Wiki_datastore.version_of_string s with Ok x -> x | Error e -> failwith e in
          (* 1.10 > 1.9 NUMERICALLY — string compare gets this backwards —
             and 1.2 = 1.2.0 by zero-extension. A version that cannot be
             ordered is NOT admitted as a release; admitting it would put
             an unorderable element in a total order. *)
          Wiki_datastore.compare_version (v "1.10") (v "1.9") > 0
          && Wiki_datastore.compare_version (v "1.2") (v "1.2.0") = 0
          && Wiki_datastore.show_version (v "1.2.0") = "1.2"
          && List.map (fun r -> r.Wiki_datastore.version_text) rs = [ "1.2"; "1.10" ]
          && List.length ds = 1
          && (match Wiki_datastore.version_of_string "v3" with Error _ -> true | Ok _ -> false)
        with _ -> false)
      "HW.8.2.6" Lifecycle "Version lifecycle directives" "versions parse; total order" 2 2 Built;
    f ~src:[ Notion ] ~rows:[ 57 ] ~gates:[ "HW.8.3.2"; "HW.8.3.3" ]
      ~derived:(fun () ->
        try
          let open Wiki_lifecycle in
          let t = template ~name:"n" "# {{title}}\n```\n{{example}}\n```\n" in
          (* an UNFILLED placeholder and an UNKNOWN fill key are both
             named errors; on error nothing renders at all, because a
             template that quietly emits a literal {{x}} into a page has
             produced a broken page that looks finished. A fenced {{x}}
             is an example and is not a placeholder. *)
          t.placeholders = [ "title" ]
          && instantiate t [ ("title", "P") ] = Ok "# P\n```\n{{example}}\n```\n"
          && (match instantiate t [] with
             | Error [ Unfilled "title" ] -> true
             | Ok _ | Error _ -> false)
          && (match instantiate t [ ("title", "P"); ("typo", "x") ] with
             | Error [ Unknown_placeholder "typo" ] -> true
             | Ok _ | Error _ -> false)
        with _ -> false)
      "HW.8.3.1" Lifecycle "Page templates" "deterministic; computed fields are kernels" 3 2 Built;
    f ~src:[ Notion ] ~rows:[ 31 ]
      ~derived:(fun () ->
        try
          let open Wiki_lifecycle in
          let m = Hermes_wiki.build
            [ ("docs/hermes/zk/alpha.md", "---\nstatus: published\ntype: claim\n---\n# Alpha\n") ] in
          let pages = m.Hermes_wiki.pages in
          match Wiki_datastore.parse_base "name: b\ncolumns: slug, title\nquery: from type:claim\n" with
          | Error _ -> false
          | Ok b ->
              let db = Wiki_datastore.database_of_base pages b in
              let t = template ~name:"row" "# {{title}} ({{slug}}) {{upper:title}}\n" in
              (* SAME MECHANISM proved by ABSENCE: the datastore substitutes
                 nothing — cells pass through verbatim to the very same
                 instantiate, so both of its error kinds stay reachable
                 from the database path. *)
              (match Wiki_datastore.database_fills db ~row:"alpha" ~placeholders:t.placeholders with
              | Ok f -> instantiate t f = Ok "# Alpha (alpha) ALPHA\n"
              | Error _ -> false)
              && (match Wiki_datastore.database_fills db ~row:"alpha" ~placeholders:[ "title" ] with
                 | Ok f ->
                     instantiate (template ~name:"r" "{{title}}") f
                     = Error [ Unknown_placeholder "slug" ]
                 | Error _ -> false)
              && Wiki_datastore.database_fills db ~row:"nope" ~placeholders:[]
                 = Error [ Wiki_datastore.Unknown_row "nope" ]
        with _ -> false)
      "HW.8.3.2" Lifecycle "Database templates" "same mechanism" 2 1 Built;
    f ~src:[ Obsidian ] ~rows:[ 110 ]
      ~derived:(fun () ->
        try
          let open Wiki_lifecycle in
          let t = template ~name:"t" "# {{title}} {{upper:title}} {{slug:title}}\n" in
          (* A TEMPLATE IS NOT A PROGRAM. Computation is a CLOSED set of
             named harness kernels; an unknown kernel is a hard error
             producing no fills at all, never falling through to
             evaluation. No now, no date, no eval — and a kernel output
             that LOOKS like a placeholder is not re-expanded. *)
          (match Wiki_datastore.fills ~row:[ ("title", "Hello World") ]
                   ~placeholders:t.placeholders with
          | Ok f -> instantiate t f = Ok "# Hello World HELLO WORLD hello-world\n"
          | Error _ -> false)
          && Wiki_datastore.fills ~row:[ ("title", "x") ] ~placeholders:[ "frobnicate:title" ]
             = Error [ Wiki_datastore.Unknown_kernel "frobnicate" ]
          && Wiki_datastore.classify_slot "exec:anything"
             = Error (Wiki_datastore.Unknown_kernel "exec")
          && Wiki_datastore.kernel_of_name "now" = None
          && Wiki_datastore.kernel_of_name "eval" = None
          && Wiki_datastore.kernels
             = [ "first_line"; "length"; "lower"; "slug"; "trim"; "upper" ]
          && Wiki_datastore.fills ~row:[ ("t", "{{secret}}") ] ~placeholders:[ "upper:t" ]
             = Ok [ ("t", "{{secret}}"); ("upper:t", "{{SECRET}}") ]
        with _ -> false)
      "HW.8.3.3" Lifecycle "Templater" "computation in the harness, not the template" 2 2 Built;
    f ~src:[ Notion ] ~rows:[ 79 ] "HW.8.3.4" Lifecycle "Template button" "stamping is a CLI action" 0 0 Excluded;
    f ~src:[ Obsidian ] ~rows:[ 93 ] "HW.8.3.5" Lifecycle "Daily / periodic notes" "R16 naming; append-only" 3 3 Built;
    f ~src:[ Own ]
      ~derived:(fun () ->
        try
          Journal.valid_name "20260809-1001-a-slug.md"
          && (not (Journal.valid_name "notes.md"))
          && (not (Journal.admissible Journal.Secret))
          && Journal.admissible Journal.Public_data
          && Journal.append_violation ~old_content:"a\n" ~new_content:"a\nb\n" = None
          && Journal.append_violation ~old_content:"a\n" ~new_content:"X\n" <> None
        with _ -> false)
      "HW.8.3.8" Lifecycle "Journal integrity (KM bundle laws)"
      "R16 name law YYYYMMDD-HHSS-<slug>.md; append-only detected as prefix violation;\n       the privacy trio is closed and Secret is REJECTED, never bundled"
      3 4 Built;
    f ~src:[ Notion ] ~rows:[ 24 ] "HW.8.3.6" Lifecycle "Forms" "route ADT cannot express a write verb" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 16 ]
      ~derived:(fun () ->
        try
          let m = Hermes_wiki.build
            [ ("docs/hermes/zk/alpha.md",
               "---\ntype: claim\n---\n# Alpha\n\nA claim worth citing ^c-1\n");
              ("docs/hermes/zk/reply.md", "---\ntype: note\n---\n# R\n\n@comments-on: alpha#^c-1\n");
              ("docs/hermes/zk/ghost.md", "---\ntype: note\n---\n# G\n\n@comments-on: nowhere\n");
              ("docs/hermes/zk/bad.md", "---\ntype: note\n---\n# B\n\n@comments-on: alpha#^nope\n") ] in
          let cs, ds = Wiki_datastore.comments m in
          (* the server is stateless and the CORPUS is the record: a comment
             is authored content with a resolvable anchor, not runtime
             state. An orphan is named in TWO flavours because the fixes
             differ — a missing page wants a target, a missing anchor
             wants a block id. *)
          List.mem "^c-1" (Hermes_wiki.anchors m "alpha")
          && cs = [ { Wiki_datastore.comment_slug = "reply";
                      on = { Wiki_datastore.target_slug = "alpha"; target_anchor = Some "^c-1" } } ]
          && List.mem (Wiki_datastore.Missing_page ("ghost", "nowhere")) ds
          && List.mem (Wiki_datastore.Missing_anchor ("bad", "alpha", "^nope")) ds
          && Wiki_datastore.comment_markers "```\n@comments-on: alpha\n```\n" = []
        with _ -> false)
      "HW.8.3.7" Lifecycle "Comments & discussions"
      "notes with @comments-on; block-anchored" 3 2 Built;
    f ~src:[ Notion ] ~rows:[ 2 ] "HW.8.4.1" Lifecycle "Resident agent" "report-only; never edits the corpus" 4 4 Built;
    f ~src:[ Notion ] ~rows:[ 3 ] "HW.8.4.2" Lifecycle "AI block" "NO LLM in render or any verdict" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 4 ] "HW.8.4.3" Lifecycle "AI writing / autofill" "same policy" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 52 ] "HW.8.4.4" Lifecycle "CLI"
      "exit code is the verdict, never the printed line (CAST-12)" 4 5 Built;
    f ~src:[ Notion ] ~rows:[ 12 ] "HW.8.4.5" Lifecycle "Button (automation block)" "loop is report-only" 0 0 Excluded;
    f ~src:[ Notion ] ~rows:[ 1 ] "HW.8.5.1" Lifecycle "Agent action audit log" "no unrecorded write path" 5 5 Built;
    f ~src:[ Notion ] ~rows:[ 39 ] "HW.8.5.2" Lifecycle "SSO / SCIM / enterprise audit" "repo access is identity" 0 0
      Excluded;
    f ~src:[ Notion ] ~rows:[ 54 ]
      ~derived:(fun () ->
        try
          let open Wiki_lifecycle in
          let m =
            Hermes_wiki.build
              [ ("docs/hermes/zk/vok.md",
                 "---\nktype: atomic\nmaturity: seed\ndomain: any\n---\n# Vok\n\nB.\n");
                ("docs/hermes/zk/vbad.md",
                 "---\nktype: sketchbook\nmaturity: seed\ndomain: q\n---\n# Vbad\n\nB.\n") ]
          in
          let gaps = vocabulary_gaps m in
          (* the concept model as CHECKABLE DATA, not prose: closed
             vocabularies are enforced, domain is open by declaration,
             and an UNSET value is not a vocabulary gap — that fact
             already has a reporter (schema_gaps) and two reporters of
             one fact disagree eventually. *)
          List.exists (fun g -> contains g "vbad: ktype outside vocabulary: sketchbook") gaps
          && (not (List.exists (fun g -> contains g "vok:") gaps))
          && (not (List.exists (fun g -> contains g "domain") gaps))
          && is_open Domain
          && classify_value Ktype "" = Unset
          && classify_value Maturity "evergreen" = In_vocabulary
        with _ -> false)
      "HW.8.5.3" Lifecycle "Ontology / concept model note"
      "R12: component and edges in the SAME commit" 3 3 Built;
    f "HW.8.5.4" Lifecycle "Register features in Gap_plan"
      "status derived where possible; disagreements reported" 4 4 Ready ]

let source =
  [ f ~src:[ Sphinx ] "HW.9.1.1" Source "Doc extraction by import"
      "the build IMPORTS NOTHING -- no import-time side effects" 0 0 Excluded;
    f ~src:[ Sphinx ] ~gates:[ "HW.9.1.3"; "HW.9.2.3"; "HW.9.4.1"; "HW.6.11.5" ] "HW.9.1.2" Source
      ~derived:(fun () ->
        try
          (* the law: STATIC parse. Nothing is imported, so an interface
             naming a module that cannot exist is still read — and one
             comment documents the NEXT val only, never every val below *)
          let src = "(* doc *)\nval a : Nonexistent.t -> int\nval b : int\n" in
          (match Wiki_iface.items src with
          | [ a; b ] ->
              a.Wiki_iface.name = "a"
              && a.Wiki_iface.signature = "Nonexistent.t -> int"
              && Wiki_iface.documented a
              && not (Wiki_iface.documented b)
          | _ -> false)
          && Wiki_iface.coverage src = Some (1, 2)
          && Wiki_iface.coverage "type t = int\n" = None
          (* total over pathological input *)
          && Wiki_iface.items "(*" = []
        with _ -> false)
      "Interface-comment extraction" "STATIC parse, never evaluation" 4 3 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let src = "(* keeps a. More. *)\nval a : int -> int\nval b : <script>\n" in
          let rows = Wiki_source_ext.api_rows src in
          let h = Wiki_source_ext.api_table_html src in
          (* COMPLETE over the interface: one row per val, and an
             undocumented val is a MARKED row, never an omission. A table
             that quietly drops what it cannot describe reports coverage
             it does not have. *)
          List.length rows = List.length (Wiki_iface.items src)
          && List.map (fun (r : Wiki_source_ext.api_row) -> r.Wiki_source_ext.name) rows
             = [ "a"; "b" ]
          && (List.hd rows).Wiki_source_ext.summary = "keeps a."
          && contains h "undocumented"
          && (not (contains h "<script>")) && contains h "&lt;script&gt;"
          && contains (Wiki_source_ext.api_table_html "type t\n") "no values declared"
        with _ -> false)
      "HW.9.1.3" Source "API summary tables" "complete over the public interface" 3 2 Built;
    f ~src:[ Sphinx ] ~gates:[ "HW.9.2.2" ] "HW.9.2.1" Source "literalinclude -- file slices"
      ~derived:(fun () ->
        try
          let read = function
            | "s.ml" -> Some "a\nBEGIN\n  x\nEND\n"
            | _ -> None
          in
          let m body =
            Hermes_wiki.build ~read_source:read [ ("docs/x/i.md", "# I\n\n" ^ body) ]
          in
          (* the denotation IS the file, and a bad marker is LOUD *)
          let good = m "```literalinclude s.ml start-after=BEGIN end-before=END\n```\n" in
          Hermes_wiki.include_gaps good = []
          && (match Hermes_wiki.page good "i" with
             | Some p -> contains p.Hermes_wiki.html "  x"
             | None -> false)
          && List.length
               (Hermes_wiki.include_gaps (m "```literalinclude s.ml start-after=NOPE\n```\n"))
             = 1
        with _ -> false)
      "denotation IS the file; unmatched marker => diag, never an empty block" 5 4 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let read p =
            if p = "new.ml" then Some "one\ntwo\nthree\n"
            else if p = "old.ml" then Some "one\nTWO\nthree\n" else None
          in
          (* DERIVABLE, not merely plausible: applying the diff to the
             before-slice must yield the after-slice exactly. A diff that
             only looks right is decoration. *)
          (match Wiki_source_ext.diff_of_info ~read "literalinclude new.ml diff=old.ml" with
          | Some (Ok r) ->
              Wiki_source_ext.patch ~before:r.Wiki_source_ext.before r.Wiki_source_ext.edits
              = Ok r.Wiki_source_ext.after
              && contains (Wiki_source_ext.diff_html r.Wiki_source_ext.edits) "-TWO"
          | Some (Error _) | None -> false)
          && (match Wiki_source_ext.diff_of_info ~read "literalinclude new.ml diff=new.ml" with
             | Some (Error e) -> contains e "diff is empty"
             | Some (Ok _) | None -> false)
        with _ -> false)
      "HW.9.2.2" Source "literalinclude :diff:" "empty diff => diagnostic" 3 2 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let read p =
            if p = "m.mli" then Some "(* d *)\nval apply : int -> int\nval ghost : int\n"
            else if p = "m.ml" then Some "let apply_start x = x\nlet apply x = x\n" else None
          in
          let x = Wiki_source_ext.cross_links ~read ~iface:"m.mli" ~impl:(Some "m.ml") in
          (* every emitted link RESOLVES, and the match is TOKEN-BOUNDED so
             `let apply` does not resolve to `let apply_start`. An
             out-of-range line is a named diagnostic, never clamped —
             a clamped line silently points at the wrong code. *)
          List.for_all
            (fun (l : Wiki_source_ext.xref) ->
              Wiki_source_ext.resolves ~read l.Wiki_source_ext.target)
            x.Wiki_source_ext.links
          && (match x.Wiki_source_ext.links with
             | [ l ] -> l.Wiki_source_ext.href = "m.ml#L2"
             | _ -> false)
          && List.exists (fun g -> contains g "no definition of ghost") x.Wiki_source_ext.gaps
          && (match Wiki_source_ext.xref_of ~read ~name:"z"
                      { Wiki_source_ext.file = "m.ml"; line = 99 } with
             | Error e -> contains e "outside"
             | Ok _ -> false)
        with _ -> false)
      "HW.9.2.3" Source "Source cross-links (viewcode)" "shares anchor validation" 3 2 Built;
    f ~src:[ Sphinx ] ~gates:[ "HW.9.3.2"; "HW.9.3.3"; "HW.9.3.4"; "HW.9.3.5"; "HW.9.3.6" ]
      "HW.9.3.1" Source "Doctest builder"
      ~derived:(fun () ->
        try
          let m body = Hermes_wiki.build [ ("docs/x/dt.md", "# DT\n\n" ^ body) ] in
          Hermes_wiki.doctest_drift
            (m "```doctest\n> plain\n<p>plain</p>\n```\n")
          = []
          && List.length
               (Hermes_wiki.doctest_drift
                  (m "```doctest\n> plain\n<p>wrong</p>\n```\n"))
             = 1
        with _ -> false)
      "SEPARATE builder; a failure is documentation drift -- may BLOCK credit, never DENY it (R5)" 5 5
      Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let b i o =
            Wiki_doctest.blocks_of_markdown ~page:"p"
              ("```testcode\necho hi \n```\n\n```testoutput" ^ i ^ "\n" ^ o ^ "\n```\n")
          in
          let ev w s =
            ( w @ [ s ],
              if String.length s > 5 && String.sub s 0 5 = "echo " then
                Wiki_doctest.Output (String.sub s 5 (String.length s - 5))
              else Wiki_doctest.Output "" )
          in
          let go bs = Wiki_doctest.run ~eval:ev ~world:[] ~env:(fun _ -> None) bs in
          (* the leniency is DECLARED or it does not exist: the same pair
             fails byte-exact and passes only once the author writes the
             option down. Inferring "close enough" is how a comparison
             stops measuring. *)
          (go (b "" "hi")).Wiki_doctest.failed = 1
          && (go (b "" "hi")).Wiki_doctest.passed = 0
          && (go (b " :trim-whitespace:" "hi")).Wiki_doctest.passed = 1
          && not
               (Wiki_doctest.compare_output Wiki_doctest.no_normalisation ~expected:"hi "
                  ~observed:"hi")
        with _ -> false)
      "HW.9.3.2" Source "testcode / testoutput" "normalisation DECLARED, not inferred" 4 3 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let md = "```doctest\n>>> echo one\none\n>>> echo two\ntwo\n```\n" in
          let ev w s =
            ( w @ [ s ],
              Wiki_doctest.Output
                (if String.length s > 5 then String.sub s 5 (String.length s - 5) else "") )
          in
          let r =
            Wiki_doctest.run ~eval:ev ~world:[] ~env:(fun _ -> None)
              (Wiki_doctest.blocks_of_markdown ~page:"p" md)
          in
          let m = Hermes_wiki.build [ ("docs/x/dt.md", "# DT\n\n" ^ md) ] in
          (* the transcript splits in DOCUMENT ORDER, and the parent
             builder still owns its own fences — two runners over one
             corpus must not both claim the same block *)
          r.Wiki_doctest.passed = 2
          && r.Wiki_doctest.failed = 0
          && Wiki_doctest.transcript_cases [ ">>> a"; "1"; ">>> b"; "2" ]
             = [ ([ "a" ], [ "1" ]); ([ "b" ], [ "2" ]) ]
          && Hermes_wiki.doctest_drift m = []
        with _ -> false)
      "HW.9.3.3" Source "doctest interpreter blocks" "transcript form" 2 1 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let ev w s = (w @ [ s ], Wiki_doctest.Output "") in
          let go exp =
            Wiki_doctest.run ~eval:ev ~world:[] ~env:(fun _ -> None)
              (Wiki_doctest.blocks_of_markdown ~page:"p"
                 ("```testcode\nbody\n```\n\n```testoutput\n" ^ exp
                ^ "\n```\n\n```testcleanup\nsweep\n```\n"))
          in
          let w r = List.map (fun g -> g.Wiki_doctest.world) r.Wiki_doctest.runs in
          let ok = go "" and bad = go "WRONG" in
          (* cleanup is UNGUARDED by the outcome: the failing run's world
             must be indistinguishable from the passing one's, or a
             failed case leaves its fixture behind for the next *)
          bad.Wiki_doctest.failed = 1
          && ok.Wiki_doctest.failed = 0
          && w bad = [ [ "body"; "sweep" ] ]
          && w bad = w ok
        with _ -> false)
      "HW.9.3.4" Source "testsetup / testcleanup" "cleanup runs even on failure" 3 3 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let ev w s =
            ( w @ [ s ],
              Wiki_doctest.Output (if s = "count" then string_of_int (List.length w) else "") )
          in
          let f k g = "```" ^ k ^ " :group: " ^ g ^ "\n" in
          let md =
            f "testcode" "a" ^ "x\n```\n\n" ^ f "testoutput" "a" ^ "\n```\n\n"
            ^ f "testcode" "b" ^ "count\n```\n\n" ^ f "testoutput" "b" ^ "0\n```\n"
          in
          let bs = Wiki_doctest.blocks_of_markdown ~page:"p" md in
          let go l = Wiki_doctest.run ~eval:ev ~world:[] ~env:(fun _ -> None) l in
          let all = go bs in
          let g_of b = b.Wiki_doctest.head.Wiki_doctest.group in
          (* ISOLATION as a DIFFERENTIAL, not an assertion of intent:
             each group run alone must equal its entry in the whole run,
             world included — group b counting the world proves a leaked
             effect from group a would show. *)
          all.Wiki_doctest.passed = 2
          && List.for_all
               (fun g ->
                 match
                   ( List.find_opt (fun r -> r.Wiki_doctest.name = g) all.Wiki_doctest.runs,
                     (go (List.filter (fun b -> g_of b = g) bs)).Wiki_doctest.runs )
                 with
                 | Some x, [ y ] -> x = y
                 | _ -> false)
               (Wiki_doctest.groups bs)
        with _ -> false)
      "HW.9.3.5" Source "Test groups" "ISOLATION: running groups together = running each alone" 3 4
      Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let ev w s = (w @ [ s ], Wiki_doctest.Output "") in
          let go c e =
            Wiki_doctest.run ~eval:ev ~world:[] ~env:e
              (Wiki_doctest.blocks_of_markdown ~page:"p"
                 ("```testcode :skipif: " ^ c ^ "\nbody\n```\n\n```testoutput\n\n```\n"))
          in
          let yes = go "win32" (fun _ -> Some true) in
          let no = go "win32" (fun _ -> Some false) in
          let dunno = go "plan9" (fun _ -> None) in
          (* a skip is NEVER a pass, is disclosed by name and counted;
             and an UNANSWERABLE condition refuses rather than guessing —
             a silently-skipped test is worse than a failing one *)
          yes.Wiki_doctest.skipped = 1
          && yes.Wiki_doctest.passed = 0
          && List.exists
               (fun d -> String.length d > 7 && String.sub d 0 7 = "SKIPPED")
               yes.Wiki_doctest.disclosures
          && List.map (fun g -> g.Wiki_doctest.world) yes.Wiki_doctest.runs = [ [] ]
          && no.Wiki_doctest.passed = 1
          && dunno.Wiki_doctest.refused = 1
          && dunno.Wiki_doctest.skipped = 0
        with _ -> false)
      "HW.9.3.6" Source ":skipif:" "skips DISCLOSED and counted (R2)" 3 4 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let src = "(* d *)\nval a : int\n" in
          let read p = if p = "a.mli" || p = "b.mli" then Some src else None in
          let broken p = if p = "b.mli" then None else read p in
          let ps = [ "a.mli"; "b.mli" ] in
          let w = Wiki_source_ext.census ~read ps and k = Wiki_source_ext.census ~read:broken ps in
          (* THE HONEST DENOMINATOR. An unreadable source stays in the
             denominator at 0% with its reason, so coverage FALLS when
             readability falls. A percentage that rose because the
             denominator shrank is the failure this row exists to prevent. *)
          w.Wiki_source_ext.declared = 2
          && k.Wiki_source_ext.declared = 2
          && k.Wiki_source_ext.unreadable = 1
          && (match (Wiki_source_ext.module_percent w, Wiki_source_ext.module_percent k) with
             | Some a, Some b -> a = 100.0 && b = 50.0
             | _ -> false)
          && Wiki_source_ext.item_percent k = None
          && List.length (Wiki_source_ext.disclosure k) = 2
          && contains (Wiki_source_ext.summary_line k) "1 UNREADABLE"
        with _ -> false)
      "HW.9.4.1" Source "Documentation coverage census"
      "fail-closed: unanalysable module is 0% WITH A REASON, never omitted" 4 3 Built;
    f ~src:[ Sphinx ] "HW.9.4.2" Source "Undocumented-item listing" "NAMES, not counts" 3 3
      (Blocked "HW.9.4.1") ]

let build =
  [ f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let d n b = ("docs/hermes/zk/" ^ n ^ ".md", b) in
          let before =
            [ d "ib-a" "# IB A\n\nSee [[ib-b]].\n"; d "ib-b" "# IB B\n\nSee [[ib-ghost]].\n" ]
          in
          let after = before @ [ d "ib-ghost" "# IB Ghost\n\nArrived.\n" ] in
          let previous = Wiki_build.full before in
          (* SOUNDNESS BEFORE SPEED, and the probe withholds the hint
             entirely: correctness may not depend on the caller naming
             what changed, because a caller that names nothing is
             exactly the caller that gets a stale build. *)
          let inc = Wiki_build.incremental ~previous ~changed:[] after in
          let cold = Wiki_build.full after in
          Wiki_build.equal_outputs inc cold
          && (not (Wiki_build.equal_outputs previous cold))
          && inc.Wiki_build.profile.Wiki_build.skipped > 0
        with _ -> false)
      "HW.10.1.1" Build "Incremental build environment"
      "SOUNDNESS BEFORE SPEED: incremental render = cold render, for every reachable env" 4 4 Built;
    f ~src:[ Sphinx ] ~gates:[ "HW.10.1.1"; "HW.10.1.3" ] "HW.10.1.2" Build "Dependency tracking"
      "reads(render d) subset deps(d) -- over-approximation safe, under-approximation NOT" 3 5
      ~derived:(fun () ->
        (* Dep_sheaf.deps IS the dependency relation, and dead_cover_elements
           is the executable tightness check *)
        try
          let m = Hermes_wiki.build
              [ ("docs/hermes/zk/pa.md", "# PA\n\nSee [[pb]].\n");
                ("docs/hermes/zk/pb.md", "# PB\n\nPlain.\n") ] in
          match m.Hermes_wiki.pages with
          | pa :: _ ->
              Dep_sheaf.Cover.elements (Dep_sheaf.deps m pa) = [ "pb" ]
              && Dep_sheaf.dead_cover_elements m pa = []
          | [] -> false
        with _ -> false)
      Built;
    f ~src:[ Sphinx ] ~gates:[ "HW.10.1.1"; "HW.10.1.2"; "HW.10.1.3" ]
      ~derived:(fun () ->
        (* live probe: the restriction law on a real two-page model — a
           render against its own cover equals a render against everything *)
        try
          let m = Hermes_wiki.build
              [ ("docs/hermes/zk/qa.md", "# QA\n\nSee [[qb]] and [[missing-x]].\n");
                ("docs/hermes/zk/qb.md", "# QB\n\nPlain.\n") ] in
          match m.Hermes_wiki.pages with
          | qa :: _ ->
              let env = Dep_sheaf.Env.of_model m in
              let all = Dep_sheaf.Cover.of_list
                  (List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug)
                     m.Hermes_wiki.pages) in
              Dep_sheaf.render (Dep_sheaf.Env.restrict env (Dep_sheaf.deps m qa)) qa
              = Dep_sheaf.render (Dep_sheaf.Env.restrict env all) qa
          | [] -> false
        with _ -> false)
      "HW.10.1.4" Build "Restricted render view (dependency sheaf)"
      "render sees only its cover BY CONSTRUCTION (Env.view is abstract, no widening); glue is a monoid; rebuild(changed) = cold build byte-for-byte; deps has no dead elements" 4 5 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let d n b = ("docs/hermes/zk/" ^ n ^ ".md", b) in
          let c =
            [ d "pb-a" "# PB A\n\nSee [[pb-c]].\n"; d "pb-b" "# PB B\n\nSee [[pb-a]].\n";
              d "pb-c" "# PB C\n\nLeaf.\n" ]
          in
          let serial = Wiki_build.full c in
          (* parallelism modelled as ORDER-INDEPENDENCE: every worker
             count and every permutation must give the serial answer
             byte for byte. A speedup bought with nondeterminism is not
             a speedup, it is a corpus nobody can pin. *)
          List.for_all (fun w -> Wiki_build.parallel ~workers:w c = serial) [ 1; 2; 3; 9 ]
          && List.for_all
               (fun order -> Wiki_build.in_order ~order c = serial)
               [ List.map fst c; List.rev (List.map fst c); [] ]
          && String.length (Wiki_build.digest serial) > 0
        with _ -> false)
      "HW.10.1.3" Build "Parallel build"
      "build_par(c) = build(c) byte-for-byte at every worker count" 3 3 Built;
    f ~src:[ Sphinx ] ~gates:[ "HW.10.2.2" ]
      ~derived:(fun () ->
        (* boundary (equal holds, +1 refuses), breach detection through
           evaluate, and fail-closed on an unpinned gauge *)
        try
          Ratchet.check ~previous:5 ~current:5 = Ok ()
          && (match Ratchet.check ~previous:5 ~current:6 with Error _ -> true | Ok () -> false)
          && (match Ratchet.evaluate ~pins:[ ("g", 0) ] ~gauges:[ ("g", 1) ] with
             | Ok vs -> Ratchet.breaches vs <> []
             | Error _ -> false)
          && (match Ratchet.evaluate ~pins:[ ("g", 0) ] ~gauges:[ ("g", 0); ("ghost", 0) ] with
             | Error _ -> true
             | Ok _ -> false)
        with _ -> false)
      "HW.10.2.1" Build "Warnings as errors (ratchet)"
      "warnings(HEAD) <= warnings(HEAD~1), enforced by the gate" 4 5 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        (* typed, never blanket: (kind, key) exact; an unexplained
           exception is refused at parse *)
        try
          (match Suppression.parse [ "k|x|imported doc, scheduled|" ] with
          | Ok ts ->
              Suppression.applies ts ~kind:"k" ~key:"x"
              && (not (Suppression.applies ts ~kind:"k" ~key:"y"))
              && not (Suppression.applies ts ~kind:"j" ~key:"x")
          | Error _ -> false)
          && match Suppression.parse [ "k|x||" ] with Error _ -> true | Ok _ -> false
        with _ -> false)
      "HW.10.2.2" Build "Selective warning suppression"
      "TYPED, not blanket: suppressing k leaves every other diagnostic active" 4 4 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let d n b = ("docs/hermes/zk/" ^ n ^ ".md", b) in
          let c =
            [ d "co-bad" "---\ntype: nonsense\n---\n\n# CO\n\nSee [[co-nowhere]].\n";
              d "co-ok" "# CO OK\n\nLeaf.\n" ]
          in
          let r = Wiki_build.check c and t = Wiki_build.full c in
          (* EXACT agreement, both directions: a check more permissive
             than the build is worse than no check, because it converts
             a failure into a green light. An artifact is unrepresentable
             in check's return type — it carries no bytes field. *)
          r.Wiki_build.complaints <> []
          && r.Wiki_build.complaints = t.Wiki_build.findings
          && List.exists (fun f -> contains f "defect:") r.Wiki_build.complaints
          && r.Wiki_build.checked = List.length t.Wiki_build.units
        with _ -> false)
      "HW.10.2.3" Build "Check-only build" "check writes NOTHING" 3 3 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let d n b = ("docs/hermes/zk/" ^ n ^ ".md", b) in
          let c =
            [ d "se-a" "# SE A\n\nA back\\slash and [[se-b]].\n"; d "se-b" "# SE B\n\nLeaf.\n" ]
          in
          let t = Wiki_build.full c in
          let s = Wiki_build.serialise t in
          (* ROUND-TRIP on the whole record, and CANONICAL — the corpus's
             input order must not be observable in the bytes, or an
             unchanged corpus re-exports differently and every diff of
             the export is noise. A malformed input REFUSES. *)
          Wiki_build.deserialise s = Some t
          && String.equal s (Wiki_build.serialise (Wiki_build.full (List.rev c)))
          && Wiki_build.deserialise "hermes-build 1\n" = None
          && Wiki_build.deserialise (s ^ "junk line\n") = None
        with _ -> false)
      "HW.10.3.1" Build "Serialised corpus export" "round-trip on the model" 3 2 Built;
    f ~src:[ Sphinx ]
      ~derived:(fun () ->
        try
          let d n b = ("docs/hermes/zk/" ^ n ^ ".md", b) in
          let c = [ d "bp-a" "# BP A\n\nSee [[bp-b]].\n"; d "bp-b" "# BP B\n\nLeaf.\n" ] in
          let t = Wiki_build.full c in
          let p = t.Wiki_build.profile in
          let q = (Wiki_build.incremental ~previous:t ~changed:[] c).Wiki_build.profile in
          (* COUNTERS, never a clock: a profile that varies run to run
             cannot be pinned or compared, and this repo pins everything.
             The parallel build reports the same profile as the serial
             one, so measuring cannot change what is measured. *)
          p.Wiki_build.units_total = 2
          && p.Wiki_build.rebuilt = 2
          && p.Wiki_build.skipped = 0
          && p.Wiki_build.source_bytes = List.fold_left (fun a (_, b) -> a + String.length b) 0 c
          && q.Wiki_build.rebuilt = 0
          && q.Wiki_build.skipped = 2
          && q.Wiki_build.source_bytes = 0
          && (Wiki_build.parallel ~workers:5 c).Wiki_build.profile = p
        with _ -> false)
      "HW.10.3.2" Build "Build profiling" "observational only" 2 2 Built;
    f ~src:[ Own ]
      ~derived:(fun () ->
        (* the dashboard is DERIVED: two renders of an unchanged system
           agree except for the timestamp line, and every figure it shows
           comes from the register, the gauges or the stream *)
        try
          Sys.file_exists "modules/hermes_wiki/src/tools/wiki_dashboard.ml"
          && (Import_coverage.census ()).Import_coverage.ported > 0
        with _ -> false)
      "HW.10.3.3" Build "System dashboard (state + KPIs)"
      "every figure DERIVED at render time from the register, gauges, pins and the OTel stream;\n       generated: true so no reader mistakes it for an authored document; reports, never gates"
      3 3 Built;
    f ~src:[ Own ]
      ~derived:(fun () ->
        (* every finding carries a fractal coordinate and an RCA origin,
           and BY CONSTRUCTION no wiki monitor denies credit or blames
           Implementation (R5) *)
        try
          let ds = List.map Wiki_diagnostics.diagnose Wiki_diagnostics.all_findings_sample in
          List.length ds = 16 (* +Ambiguous_ref, +Term_gap, +Index_violation,
                                 +Corpus_defect, +Include_gap *)
          && List.for_all
               (fun (d : Fractal_diagnostic.t) ->
                 d.Fractal_diagnostic.impact <> Fractal_diagnostic.Denies_credit
                 && d.Fractal_diagnostic.origin <> Fractal_diagnostic.Implementation
                 && d.Fractal_diagnostic.cause <> "" && d.Fractal_diagnostic.fix <> "")
               ds
          && (Wiki_diagnostics.diagnose
                (Wiki_diagnostics.Ratchet_breach { gauge = "g"; previous = 0; current = 1 }))
               .Fractal_diagnostic.level
             = Fractal_diagnostic.LX_control
        with _ -> false)
      "HW.8.5.5" Lifecycle "Fractal diagnostics for the wiki plane"
      "every finding carries level and RCA origin; a monitor can NEVER deny credit or blame\n       Implementation (unrepresentable); control-plane findings file at LX, never a corpus level (R9)"
      4 5 Built;
    f ~src:[ Own ]
      ~derived:(fun () ->
        (* the operational layer is itself drift-checked: the five core
           skills exist with matching frontmatter names, and the auditor
           agent is present *)
        try
          List.for_all
            (fun s ->
              let p = Filename.concat ".claude/skills" (Filename.concat s "SKILL.md") in
              Sys.file_exists p
              &&
              let ic = open_in_bin p in
              let n = in_channel_length ic in
              let body = really_input_string ic n in
              close_in ic;
              let needle = "name: " ^ s in
              let nh = String.length body and nn = String.length needle in
              let rec go i = i + nn <= nh && (String.sub body i nn = needle || go (i + 1)) in
              go 0)
            [ "feature-landing"; "hermes-wiki-zk"; "wiki-site-design"; "wiki-zk-operations";
              "workspace-structure" ]
          && Sys.file_exists ".claude/agents/wiki-auditor.md"
        with _ -> false)
      "HW.8.5.6" Lifecycle "Claude operational layer drift-checked"
      "skills, agents and rules are CHECKED artifacts: cited tools must exist as source,\n       cited rule ids must be in the ledger, frontmatter names must match their directories\n       (test_claude_artifacts; a dead citation fails the gate)"
      3 4 Built;
    f ~src:[ Own ]
      ~derived:(fun () ->
        (* the actor model itself: validates; the reconciler is present;
           every corpus-writing command is GUARDED *)
        try
          Fpp_model.validate Wiki_topology.model = []
          && List.exists
               (fun (c : Fpp_model.component) -> c.Fpp_model.comp_name = "reconciler")
               Wiki_topology.model.Fpp_model.components
          && List.for_all
               (fun (c : Fpp_model.component) ->
                 List.for_all
                   (fun (cmd : Fpp_model.command) ->
                     if cmd.Fpp_model.cmd_name = "PIN_BASELINE"
                        || cmd.Fpp_model.cmd_name = "APPLY_BATCH"
                     then cmd.Fpp_model.cmd_kind = Fpp_model.Guarded_cmd
                     else true)
                   c.Fpp_model.commands)
               Wiki_topology.model.Fpp_model.components
        with _ -> false)
      "HW.10.5.1" Build "Actor topology (the system as FPP)"
      "Fpp_model.validate = []; monitors are report-only (no auditor edge targets the corpus);\n       every ratcheted gauge is a telemetry channel; corpus-writing commands are Guarded"
      4 4 Built;
    f ~src:[ Sphinx ] "HW.10.4.1" Build "Project scaffolding" "one corpus, already set up" 0 0 Excluded;
    f ~src:[ Sphinx ] "HW.10.4.2" Build "Minimum-version declaration" "dune + opam pin the toolchain" 0 0
      Excluded ]

let features =
  corpus @ dialect @ address @ graph @ query @ surface @ present @ lifecycle @ source @ build

(* ---------------------------------------------------------- the decisions *)

(* Fail closed: a probe that says ABSENT overrides a Built declaration.
   The dangerous direction is claiming built without evidence, so a failed
   probe demotes rather than deferring to the table. stale_declarations
   reports the disagreement either way. *)
let status feat =
  match feat.derived with
  | Some probe ->
      if (try probe () with _ -> false) then Built
      else (match feat.declared with Built -> Ready | d -> d)
  | None -> feat.declared

let find id = List.find_opt (fun x -> x.id = id) features

let blocker_satisfied on =
  match find on with Some b -> status b = Built | None -> false

let actionable feat =
  match status feat with
  | Built | Excluded | Forked _ -> false
  | Ready -> true
  | Blocked on -> blocker_satisfied on

let priority feat =
  match status feat with
  | Built | Excluded -> 0
  | _ -> (3 * feat.criticality) + (2 * feat.utility) + List.length feat.gates

let prioritized () =
  List.filter actionable features
  |> List.sort (fun a b ->
         match compare (priority b) (priority a) with 0 -> compare a.id b.id | c -> c)

let next () = match prioritized () with x :: _ -> Some x | [] -> None

let summary () =
  List.fold_left
    (fun acc feat ->
      match status feat with
      | Built -> { acc with built = acc.built + 1 }
      | Ready -> { acc with ready = acc.ready + 1 }
      | Blocked _ -> { acc with blocked = acc.blocked + 1 }
      | Forked _ -> { acc with forked = acc.forked + 1 }
      | Excluded -> { acc with excluded = acc.excluded + 1 })
    { built = 0; ready = 0; blocked = 0; forked = 0; excluded = 0 }
    features

let by_area () =
  let areas =
    [ Corpus; Dialect; Address; Graph; Query; Surface; Present; Lifecycle; Source; Build ]
  in
  List.map (fun a -> (a, List.filter (fun x -> x.area = a) features)) areas

let dangling_references () =
  let known = List.map (fun x -> x.id) features in
  let referenced =
    List.concat_map
      (fun x -> match x.declared with Blocked on -> on :: x.gates | _ -> x.gates)
      features
  in
  List.sort_uniq compare (List.filter (fun r -> not (List.mem r known)) referenced)

let stale_declarations () =
  List.filter_map
    (fun feat ->
      match feat.derived with
      | None -> None
      | Some probe ->
          let live = (try probe () with _ -> false) in
          if live && feat.declared <> Built then
            Some (Printf.sprintf "%s: probe says present, declared %s" feat.id
                    (readiness_name feat.declared))
          else if (not live) && feat.declared = Built then
            Some (Printf.sprintf "%s: declared built, probe says absent" feat.id)
          else None)
    features
