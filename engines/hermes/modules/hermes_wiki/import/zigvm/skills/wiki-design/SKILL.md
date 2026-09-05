---
name: wiki-design
description: Use when building or rendering a project wiki (pages, an index, cross-links) — especially the harness/docs wikis rendered by docs_wiki.ml or served at /wiki and /docs. Encodes Notion-style wiki design (clean sidebar nav, callouts, tables, breadcrumbs) and the hard rule that every page is 2-way navigable.
---

# Wiki design — Notion as the reference

A wiki is a **navigable graph of pages**, not a pile of documents. The reference
model is Notion: minimal chrome, a persistent structural sidebar, blocks over
prose walls, and links that go both ways. Apply this whenever you build a wiki
page or a wiki generator (`harness/docs_wiki.ml`, the `/wiki` and `/docs` routes,
`docs/harness-wiki/`).

*Context Update:* Phase 7 of the OCaml scripting program added wiki-focused tooling — `wiki_*` standalone scripts under `scripts/` (e.g. `wiki_typography_scale_enforcer.ml`, `wiki_responsive_css_validator.ml`) plus dune-linked harness modules (e.g. `wiki_content_security_policy_generator.ml`) — all OCaml-only per `docs/OCAML_SCRIPTING_SOP.md`. HONESTY: the phase-7 harness modules are scaffolding stubs (compiled, unwired, no laws); this skill and the live wiki renderer (`harness/docs_wiki.ml`) remain the actual guarantees until stub-promotion slices land.

## The non-negotiable: 2-way navigability

**Every page must be reachable from every other page, and you must always be able
to get back.** Concretely, each page carries:

1. a **persistent sidebar** listing every page (grouped by section) — any → any,
   with the current page highlighted;
2. a **breadcrumb** (`docs / <group> / <file>`) whose segments link upward;
3. **prev / next** links to its neighbours in reading order;
4. a link **back to the index** and to the companion live wiki.

A page that can only be reached, not left, is a dead end — treat it as a bug.

## Notion principles to apply

- **Sidebar is the map.** A single always-present left rail with the full page
  tree, grouped by sub-directory/section, current page marked. Truncate long
  titles with ellipsis, never wrap the rail.
- **Blocks, not walls.** Prefer callouts (💡 tip / ⚠️ warning), tables, and short
  sections to long paragraphs. A page scans top-to-bottom in seconds.
- **Breadcrumbs + backlinks.** Show where you are and where this links from;
  wherever a page references another, make it a real link (bidirectional in
  spirit — the sidebar closes the loop).
- **Quiet chrome, generous whitespace.** One restrained accent, a clean neutral
  ground, a readable measure (~70ch), a clear type scale. The content is the UI.
- **Icons/eyebrows encode structure**, not decoration — a section eyebrow or a
  page group must mean something true about the content.
- **Theme-aware** (light/dark via tokens) and **self-contained** (inline CSS; no
  external fonts/CDNs — the harness serves these under a strict environment).

## In this repo

- `harness/docs_wiki.ml` is the generator: a pure **Model → View** projection.
  The Model is the docs tree (via `git ls-files`), the View is total,
  injection-safe render functions. It emits the sidebar, breadcrumb, and prev/next
  on every page. Extend the renderer, never hand-write per-page HTML.
- Served live at `/docs` (index + `/docs/<slug>`) and `/wiki` (the git+SQLite
  harness wiki) by `--serve`; also `--docs-wiki DIR` writes the static site.
- Keep it integrated: `/wiki ↔ /docs`, and the markdown source under
  `docs/harness-wiki/` stays the durable git-tracked reference.

## Checklist before shipping a wiki page

- [ ] appears in the sidebar, correct group, highlighted when current
- [ ] breadcrumb + prev/next + index link present (2-way nav)
- [ ] callouts/tables used instead of long prose where it helps scanning
- [ ] every cross-reference is a real link; no dead ends
- [ ] theme-aware, self-contained, no external assets
- [ ] passes `--check-lint` as a GENERATED artifact, where every finding is an
      `Error`: doctype first, `lang`, `title`, every element closed, comments
      terminated, no duplicated attribute, no remote runtime asset (including
      CSS `@import` and `@font-face`), no whitespace in a `data:` URI, and any
      emitted table carrying a delimiter row of the header's arity. See
      `docs/design/HTML_ALGEBRA.md` and `docs/design/TABLE_ALGEBRA.md`.

## Current capabilities (post ZK/wiki program, 2026-07-29)

The docs wiki is now a full Zettelkasten + self-model (program of record:
`docs/journal/20260729-1056-zk-wiki-mcp-ai-architecture-recommendations.md`).
When designing pages, use — don't reinvent — the landed machinery:

- Corpus = root rulebooks + `docs/**` + `skills/**` + `proofs/` + `specs/` (all
  note-graph citizens); code reaches search as kind `code`.
- Typed edges `[[T|@supports]]`/`[[T|@opposes]]` (Dung grounded standing),
  discourse `type:` frontmatter, contextual backlinks, `^id` block anchors with
  block-level search vectors and `![[Note#^id]]` transclusion (depth-bounded,
  DAG-checked), live ```zkquery tables, community MoCs (`--zk-moc`), episodic
  per-slice notes (analytics-excluded by the projection law), git-mined
  temporal history (`--zk-temporal`/`--zk-asof`).
- Agent access: the `zk_*` MCP tool family + CLI mirrors; authoring via
  `zk_author_note`/`zk_record_decision` under CTRL-ZK-AUTHOR.
- Operating skill: `skills/zk-knowledge-base/SKILL.md` (query/author/currency
  loop/healing); keep the two skills consistent when either evolves.

## Reference model — Notion feature catalogue (100% coverage matrix, 2026)

Notion is the design reference; this matrix lists its COMPLETE feature surface
and maps each to the zigvm wiki/ZK. Legend: ✓ native · ✓✓ native and stronger ·
◐ partial/analog · ✗ gap (candidate) · — N/A by design (the git/repo/agent
substrate answers it differently). Honesty rule: ✗ never silently becomes ◐.

### Blocks & editing
| Notion | Ours |
|---|---|
| Paragraph text | ✓ markdown |
| Headings 1–3 (+ toggle headings) | ✓ h1–h4 (toggle ✗) |
| Bulleted / numbered lists | ✓ |
| To-do checkboxes | ✗ candidate (`- [ ]` unrendered) |
| Toggle list | ✗ candidate (`<details>` used only for neighborhood) |
| Quote | ✓ blockquote |
| Callout | ✗ candidate (Obsidian `> [!note]` syntax would fit) |
| Divider | ✓ `---` |
| Code block (language, caption) | ✓ fences; ✓✓ live `zkquery` fences EXECUTE |
| Simple table | ✓ pipe tables (head/body) |
| Columns / layout | — single-column by design (readability) |
| Synced blocks | ◐ `![[Note#^id]]` transclusion (source-anchored, DAG-checked — arguably sounder) |
| Template button | — generators live harness-side (MoC/episode/ADR) |
| Table of contents block | ✗ candidate (headings already anchored) |
| Breadcrumb block | ✓ every page |
| Equation (KaTeX inline/block) | ✗ candidate |
| Image / video / audio / file | ✗ (text-first corpus; images unrendered) |
| Bookmark / link preview | ◐ plain links; no preview cards |
| Mentions @page / @date / @person | ◐ `[[page]]`; dates in frontmatter; no people |
| Emoji | ✓ inline unicode |
| Button / automation block | — automations are the autonomic loop + systemd timer (report-only by policy) |

### Pages
| Notion | Ours |
|---|---|
| Nested pages / hierarchy | ✓ directory groups + sidebar |
| Icons & covers | — lean by design |
| Backlinks section | ✓✓ with CITATION CONTEXT (the citing line) |
| Version history | ✓✓ git + `/docs/timeline` as-of queries |
| Trash / restore | ✓ git |
| Page templates | ◐ ADR criteria envelope + generated notes |
| Favorites / recents | — stateless server by design |
| Export (md/html/pdf) | ✓ md IS the source; `--docs-wiki` static html export |
| Import | ✓ files are the corpus |
| Locked pages | ◐ MoC promotion-freeze + git review |
| Page analytics | — no tracking by design |
| Small text / fonts / full width | — one typographic system |
| **Wiki verification (owner + verify + expiry)** | ✓✓ `verified_by`/`last_verified`/`next_review` frontmatter + decay signals + audit — Notion's wiki killer-feature, ours since gap-zk-authoring |

### Databases (Notion's core) → our query-defined model
Notion stores rows; we DERIVE rows from notes — same views, different substrate.
| Notion | Ours |
|---|---|
| Table view | ✓ zkquery tables (embedded + `/docs/query`) |
| Board (kanban) | ◐ the harness strategic board (ledger-backed, different surface) |
| Timeline view | ◐ `/docs/timeline` (bi-temporal git, different semantics) |
| Calendar view | ✗ |
| List / gallery views | ◐ index + groups + MoCs |
| Charts | ◐ graph page + sparklines; no per-query charts (candidate) |
| Property: title/text | ✓ title + frontmatter |
| select / status | ✓ `status`, `type` vocabularies (validated) |
| multi-select | ✓ #tags |
| date | ✓ review/verified stamps |
| person | ◐ `verified_by` (agent/human/harness) |
| number / url / email / phone | ◐ url=links; others unneeded so far |
| formula | ✗ (deliberate: no spreadsheet semantics) |
| **relation** | ✓✓ typed edges `[[T\|@rel]]` — SEMANTIC relations Notion lacks |
| rollup | ◐ MoC aggregations (tags/degree/size) |
| created/edited time+by | ✓ git |
| unique ID | ✓ deterministic UUID |
| Filters / sorts | ✓ zkquery where/sort/limit |
| Grouping / subgroups | ✗ candidate (`group by` in zkquery) |
| Sub-items & dependencies | ◐ kanban deps (ledger) |
| Database templates | ◐ generators |
| **Linked views of a database** | ✓✓ any note embeds any query (queries ARE notes) |
| Database automations | ◐ autonomic loop; report-only by policy |
| Forms | ◐ authoring + ADR forms |
| Verification per row | ✓ per-note frontmatter |

### AI, collaboration, platform
| Notion | Ours |
|---|---|
| Notion AI Q&A over workspace | ◐ deterministic: semantic+block+code search, PPR, grounded semantics — NO LLM in any verdict path (policy §4); LLM = optional MCP agent |
| AI autofill / writing / meeting notes | — out of scope by design |
| Real-time co-editing | — async: git + etag optimistic concurrency (CAST-zk5 covers multi-agent) |
| Comments & discussions | ✗ candidate (natural fit: typed notes `@comments-on`) |
| Notifications / inbox | ◐ `note.*` webhooks (`/api/webhooks`) |
| Permissions / guests / teamspaces | — repo access model |
| Public publish / Notion Sites | ◐ Tailscale serve + static export |
| Search (quick find) | ✓✓ full-text + semantic + block + code + PPR |
| Public API | ✓✓ JSON API + MCP tools (agent-first) |
| Web clipper / Calendar / Mail apps | — out of scope |
| SSO / SCIM / audit log | — git + SQLite ledger IS the audit substrate |
| Offline | ✓ it's a repo |

## Reference model — Obsidian feature catalogue (2026)

| Obsidian | Ours |
|---|---|
| Local-first markdown vault | ✓✓ identical philosophy + law-tested |
| Wikilinks + aliases | ✓ incl. `&`-safe resolution |
| Backlinks pane | ✓✓ with contexts |
| Unlinked mentions | ✓ core parity |
| Tags (nested) | ✓ flat (nested ✗) |
| Properties (frontmatter) | ✓ + validation |
| Graph view / local graph | ✓ global; ◐ local = neighborhood details |
| Canvas | ✗ (the Fractal Atlas is the curated analog) |
| Daily notes | ◐ episodic per-SLICE notes (better unit for this repo) |
| Templates / Templater | ◐ generators |
| Embeds `![[..]]` (note/block/heading) | ✓ note+block (heading-embed ✗) |
| Block refs `^id` | ✓ one addressing scheme end-to-end |
| Callouts | ✗ candidate |
| Footnotes / Mermaid / Math | ✗ candidates |
| Search operators | ◐ zkquery + semantic (no regex UI) |
| Outline/TOC | ✗ candidate |
| Word count | ✓ card |
| Themes / CSS | ✓ dark/light |
| **Bases (2025 core DB)** | ◐ zkquery — the convergent design (journal §7.7) |
| Dataview plugin | ✓ zkquery |
| Graph-analysis plugins | ✓✓ PageRank/PPR/communities/betweenness native |
| Spaced-repetition plugins | ◐ review stamps + churn decay |
| Kanban plugin | ◐ harness board |
| Excalidraw / Zotero / Tasks | ✗ / — / ✗ |
| Sync / Publish (paid) | ✓ git / serve |
| Version history | ✓✓ git + as-of |
| Mobile apps / URI scheme | ◐ browser / ✗ |

### Gap shortlist (candidates, NOT commitments — each needs a demand signal)
callouts (`> [!note]`) · to-do checkboxes · per-page TOC · KaTeX math · mermaid ·
footnotes · image rendering · zkquery `group by` · comments-as-typed-notes ·
heading-level embeds · canvas. Anything promoted becomes a law-carrying slice
per `skills/algebraic-fractal-structures`.

## The feature database (full annotations live in the corpus)

The matrices above are the SUMMARY; the full reference lives as a queryable
feature database — one note per feature (114: Notion incl. the 2026 agent
wave from the live notion.com scrape, + Obsidian), each annotated with **use
cases, look & feel, and navigation cues**, coverage-tagged
(#cov-native/strong/partial/gap/na):

- Index (self-querying via live ```zkquery fences): `docs/features/README.md`
- Concept model: `docs/features/notion-ontology.md` (containment vs REFERENCE)
- Design grammar: `docs/features/notion-design-language.md` (adopted /
  diverged / candidate cues — consult BEFORE any wiki UI change)
- Query it: `--zk-query "from tag:cov-gap sort slug"` (the shortlist),
  `from tag:notion-2026` (the agent-wave convergence: Notion arrived at
  MCP + CLI + agent-audit — the architecture this ZK already runs).

## The feature ALGEBRA (zk-feature-algebra)

Coverage is a typed OCaml carrier (`Cov_gap<Cov_partial<Cov_native<Cov_strong`
chain + `Cov_na` identity) with `cov_join` a JOIN-SEMILATTICE — laws verified
EXHAUSTIVELY (finite carrier: 125 assoc triples, 25 comm pairs). The feature
notes are the INITIAL encoding; `feature_db` parses the FINAL; the AGREEMENT
law (kernel census ≡ zkquery tag count) binds them, and `--selfcheck-wiki`
enforces tag well-formedness on every future feature note. Surfaces:
`--zk-coverage` (JSON) + the Reference-coverage panel on `/docs/currency`
(join = capability, floor = debt per source·area). Site IA:
`docs/features/notion-site-fractal.md` maps notion.com's own organs to ours.
