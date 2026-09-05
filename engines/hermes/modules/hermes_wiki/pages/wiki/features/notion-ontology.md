---
id: hermes-imported-notion-ontology
status: published
type: reference
generated: false
allow_example_links: true
migrated_from: zigvm/docs/features/notion-ontology.md
status: published
last_verified: 2026-07-29
verified_by: agent
---
# Notion ontology — the concept model

The concept hierarchy underlying every Notion feature (derived from the product
surface + the live notion.com scrape), each concept mapped to this system's
carrier. The deep claim: **Notion's ontology is containment; ours is
reference** — Notion nests things, the Zettelkasten links them.
#feature-db #ontology

## The content axis

- **Workspace** → ours: the repo (one team, one history)
  - **Teamspace** → directory groups (`docs/`, `skills/`, `proofs/`, `specs/`)
    - **Page** (the universal container; a page is also a block) → the NOTE
      (atomic, frontmatter-typed, graph-cited)
      - **Block** (the universal unit: ~30 types; everything is a block) →
        markdown constructs + the `^id`-anchored CHUNK (our block is
        *addressable* — links, embeds, vectors, search hits share the id)
      - **Sub-page** → nested paths
- **Property** (typed metadata on database pages) → frontmatter keys +
  vocabularies (status/type) + tags
- **Relation/Rollup** → typed edges `[[T|@rel]]` + MoC aggregations — ours
  carry SEMANTICS (supports/opposes feed grounded reasoning)

## The database axis

- **Database** = schema + row-pages → ours: a QUERY over notes (zkquery) —
  no stored tables, rows are derived
  - **Source** (one dataset) → the corpus itself
  - **View** (table/board/timeline/calendar/list/gallery/chart/form) → query
    renderings: tables (fences + console), board (strategic), timeline
    (git-temporal), MoCs
  - **Filter/Sort/Group** → `where`/`sort` (+ `group by` = recorded gap)
  - **Automation** → the autonomic loop + timer (report-only BY POLICY)

## The intelligence axis (Notion 2026)

- **Workspace AI** (Q&A with citations) → deterministic retrieval: semantic +
  block + code search, PPR, grounded standing — citations are LINKS by
  construction
- **Agents / Workers** (resident actors) → the harness itself: audit loop,
  currency timer, episodic self-documentation
- **Custom Agents + MCP connections** → the `zk_*` MCP family (CONVERGENCE:
  they arrived at our architecture)
- **Notion CLI** → the `--zk-*` CLI mirrors (ours are the Zero-Trust
  evidence path, not a convenience)
- **Agent audit log** → git + SQLite ledger + episodic notes (audit as
  SUBSTRATE)

## The collaboration axis

- **Members/Guests/Groups · Permissions · Comments · Notifications** →
  repo-access model · etag concurrency + CAST-zk5 multi-agent protocol ·
  (comments = recorded gap, natural as `@comments-on` typed notes) ·
  `note.*` webhooks

## The trust axis

- **Wiki verification (owner + verify + expiry)** → `verified_by` /
  `last_verified` / `next_review` + decay + audit — the one Notion concept we
  had FIRST, extended with mechanized staleness

Part of the [[Feature database — Notion & Obsidian coverage]].
