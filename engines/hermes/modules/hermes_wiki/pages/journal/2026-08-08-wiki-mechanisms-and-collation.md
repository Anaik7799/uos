---
id: hermes-journal-wiki-mechanisms-collation
status: published
type: note
allow_example_links: true
ktype: atomic
maturity: incubating
domain: journal
created: 2026-08-08
---
# Journal: zigvm wiki/ZK mechanisms, and collating 146 documents (2026-08-08)

## Prompts (verbatim, in order)

> what mechanisms are im place to add slugs , create ZK links and html
> links for navigation and zk semantic links and corelation- all the slug
> and elemt typoes should eb adeed to the wiki pages

> check what mechanisms are im place in zigvm to add slugs , create ZK
> links and html links for navigation and zk semantic links and
> corelation- all the slug and elemt typoes should eb adeed to the wiki
> pages. what is being used for css in zigvm, what learnings were there
> from docusaurs , table algebra , algebra for wiki, zk, css , table and
> any other wik and zk artifacts

> check what mechanisms are im place in zigvm to add slugs , create ZK
> links and html links for navigation and zk semantic links and
> corelation- all the slug and elemt typoes should eb adeed to the wiki
> pages. what is being used for css in zigvm, what learnings were there
> from docusaurs , table algebra , algebra for wiki, zk, css , table and
> any other wik and zk artifacts- save all the prompts and learnigs in a
> journal doc . get all files from zigvm/docs/bonsai , zigvm/docs/features,
> journal folder related to notion, obsidian, docusaurus , infonodus.
> table, html, web based algebra. collate all docs into
> ./harness/hermes_wiki/pages/wiki folder

(Earlier prompts in this arc are recorded in
`2026-08-08-web-surface.md`; the F Prime and formal-coverage arcs are in
their own journals.)

## What was surfaced on the pages

Typed `[[T|@rel]]` edges were captured by the model and **never
rendered** — a relation nobody can see is a relation nobody can use.
Note pages now carry Identity (page slug, stable id, discourse type,
status, group, source path, migrated-from), Sections (a ToC from heading
anchors, built with the SAME stateful slugger the renderer uses so ids
and links cannot disagree), Semantic links outgoing AND incoming, and
Correlated notes ranked by shared tags.

`allow_example_links` is now honored rather than merely parsed. It
caught a real phantom edge: this journal's predecessor quoted the
`[[T|@rel]]` grammar and had manufactured an edge to a note called "t".

## What the survey found

Full write-up: `docs/hermes/wiki-mechanisms-survey.md`. The load-bearing
findings:

- **Slugs are four namespaces, not one** (page identity, anchor,
  file/authoring, resolver keys), each with its own alphabet and
  guarantee. We have three; the file namespace is genuinely n/a because
  Hermes never writes notes. **Block anchors `^id`** remain the cleanest
  thing we lack.
- **Correlation** is where zigvm is decisively ahead: pagerank, vector
  similarity, communities, inferred links, and grounded standing over a
  discourse graph whose anomalies are *structural* — a claim with no
  supporting edge, an undecided node with an attacker, a transclusion
  cycle.
- **CSS is generated, never written**: `tokens.css` carries
  `GENERATED from figma_design.ml — do not hand-edit`, every property
  annotated with its source token path, with a dark-mode rebinding and a
  print stylesheet.
- **The algebras** exist because heuristics failed loudly.
  `TABLE_ALGEBRA`: a pipe counter cannot tell a table from a paragraph
  containing pipes — 43 findings of which 5 were real. `HTML_ALGEBRA`:
  *"bytes are not markup"*. `WEB_ALGEBRA_MAP` states the principle — a
  capability copied feature-by-feature arrives as conventions; one
  identified as a monoid arrives with its laws attached, and the laws
  are the part that survives a refactor.
- **The Docusaurus learning is one type fact**: no block constructor
  contains a block, so the carrier is depth-2 rather than a recursive
  functor — and that single fact explains nested-list flattening,
  admonitions, `<details>` and tabs. Our line machine is shallower
  still, so the fix is the AST shape, not more cases in the loop.

## The collation

146 documents imported into `hermes_wiki/pages/wiki/`, each with
provenance frontmatter naming its zigvm source path:

| Destination | Count | Source |
|---|---|---|
| `bonsai/` | 9 | `docs/bonsai/` — Bonsai algebra/guide/ontology/SOP, Phoenix, Ocsigen and LiveView comparisons |
| `algebras/` | 5 | `docs/design/` — TABLE, HTML, ROUTE, WEB_ALGEBRA_MAP, WIKI_PIPELINE |
| `imported-journals/` | 14 | `docs/journal/` — infranodus, zk/wiki architecture, lint algebra, docusaurus gap analysis |
| `features/` | 118 | `docs/features/` — 87 notion, 30 obsidian, README |

The corpus went from 22 to 168 documents and the site from 94 to **241
pages**.

## Three defects the import exposed

The enlarged corpus did what a real corpus does — it broke assumptions
the small one never tested.

1. **Slug collision.** Two `README.md` files. Our page slug is
   basename-derived where zigvm encodes the path (§6a), so they
   collided. Fixed by deterministic **group-qualified disambiguation**
   (first occurrence in corpus order keeps the bare slug) — and the
   resolution is REPORTED, never silent, so a reader can see why a URL
   is not the basename.
2. **Discourse vocabulary too small.** The imports are genuinely
   `reference` material — neither a claim nor a decision of ours.
   Mislabelling 146 documents to fit a five-item list would have been
   worse than extending the list, so `reference` joined the vocabulary.
3. **Notices were refusing the build.** `render_site` refused on ANY
   anomaly, so a *correctly handled* collision blocked the whole site.
   Anomalies now split by consequence: **defects** refuse, **notices**
   print. Refusing on a notice is not strictness, it is a false alarm.

## Numbers

hermes_wiki 46/0 · battery 76 suites / 0 failing · corpus 168 documents ·
site 241 pages, live over the tailscale FQDN.
