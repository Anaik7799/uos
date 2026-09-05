---
id: hermes-imported-README
status: published
type: reference
generated: false
allow_example_links: true
migrated_from: zigvm/docs/features/README.md
status: published
last_verified: 2026-07-29
verified_by: agent
---
# Feature database — Notion & Obsidian coverage

The FULL reference feature surface of Notion and Obsidian (108 features, 100%%
coverage), one atomic note per feature, each annotated with **use cases, look &
feel, and navigation cues** and classified by coverage tag — a real database in
this system's sense: notes + tags + zkquery. Matrices summary in
[[skills--wiki-design--skill]]; rules in [[skills--zk-knowledge-base--skill]].
#feature-db #zettelkasten

## Query it live

All gaps (the candidate shortlist):

```zkquery
from tag:cov-gap sort slug
```

Where we are STRONGER than the reference:

```zkquery
from tag:cov-strong sort slug
```

Answered differently by the substrate (N/A by design):

```zkquery
from tag:cov-na sort slug
```

## All features

### Notion · 2026 agent wave (from the live notion.com scrape)

- [[notion-agents]] — ◐ Notion Agents / Workers (2026)
- [[notion-custom-agents-mcp]] — ✓✓ Custom Agents + MCP connections (2026)
- [[notion-notion-cli]] — ✓✓ Notion CLI (2026, for devs & coding agents)
- [[notion-html-block]] — — Interactive HTML blocks (2026)
- [[notion-agent-audit]] — ✓✓ Agent action audit log (2026)
- [[notion-sync-connectors]] — ◐ Sync any data source (connectors, Beta 2026)

Also in the database: [[Notion ontology — the concept model]] · [[Notion design language — look, feel, and navigation cues]] · [[Notion site fractal — notion.com's own IA mapped to our surfaces]] · **formal spec**: [[The Knowledge-Systems Algebra — a formal specification of Wiki, ZK, Notion, and Obsidian entities]]

**The algebra**: coverage is a law-verified JOIN-SEMILATTICE (exhaustive: all 125 associativity triples) parsed from these very notes — `--zk-coverage` prints the census/rollup; the currency page renders per-area join (capability) and floor (debt); the agreement law binds this kernel to the zkquery tag path.


### Notion · blocks

- [[notion-paragraph]] — ✓ Paragraph text
- [[notion-headings]] — ✓ Headings 1–3 (+ toggle headings)
- [[notion-bulleted-list]] — ✓ Bulleted list
- [[notion-numbered-list]] — ✓ Numbered list
- [[notion-todo-checkbox]] — ✗ To-do checkbox
- [[notion-toggle-list]] — ✗ Toggle list
- [[notion-quote]] — ✓ Quote
- [[notion-callout]] — ✗ Callout
- [[notion-divider]] — ✓ Divider
- [[notion-code-block]] — ✓✓ Code block
- [[notion-simple-table]] — ✓ Simple table
- [[notion-columns]] — — Columns / layout
- [[notion-synced-block]] — ◐ Synced block
- [[notion-template-button]] — — Template button
- [[notion-toc-block]] — ✗ Table of contents
- [[notion-breadcrumb]] — ✓ Breadcrumb
- [[notion-equation]] — ✗ Equation (KaTeX)
- [[notion-media]] — ✗ Image · video · audio · file
- [[notion-bookmark]] — ◐ Bookmark / link preview
- [[notion-embeds]] — — Embeds (Figma, Maps, PDF, tweets…)
- [[notion-mention]] — ◐ Mentions (@page @person @date)
- [[notion-emoji]] — ✓ Emoji
- [[notion-button-automation]] — — Button (automation block)
- [[notion-ai-block]] — — AI block

### Notion · pages

- [[notion-nested-pages]] — ✓ Nested pages
- [[notion-icons-covers]] — — Page icons & covers
- [[notion-backlinks-panel]] — ✓✓ Backlinks section
- [[notion-page-history]] — ✓✓ Page history / versions
- [[notion-trash-restore]] — ✓ Trash & restore
- [[notion-page-templates]] — ◐ Page templates
- [[notion-favorites]] — — Favorites & recents
- [[notion-export]] — ✓ Export (md/html/pdf/csv)
- [[notion-import]] — ✓ Import
- [[notion-locked-pages]] — ◐ Locked pages
- [[notion-page-analytics]] — — Page analytics
- [[notion-typography]] — — Typography toggles (serif/mono, small, full-width)
- [[notion-wiki-verification]] — ✓✓ Wiki verification (owner · verify · expiry)
- [[notion-duplicate-move]] — ✓ Duplicate / move

### Notion · db

- [[notion-db-table]] — ✓ Database: Table view
- [[notion-db-board]] — ◐ Database: Board (kanban)
- [[notion-db-timeline]] — ◐ Database: Timeline view
- [[notion-db-calendar]] — ✗ Database: Calendar view
- [[notion-db-list]] — ◐ Database: List view
- [[notion-db-gallery]] — ◐ Database: Gallery view
- [[notion-db-chart]] — ◐ Database: Charts
- [[notion-prop-select]] — ✓ Property: Select / Status
- [[notion-prop-multiselect]] — ✓ Property: Multi-select
- [[notion-prop-date]] — ✓ Property: Date
- [[notion-prop-person]] — ◐ Property: Person
- [[notion-prop-files]] — ✗ Property: Files & media
- [[notion-prop-scalar]] — ◐ Property: Number / URL / Email / Phone
- [[notion-prop-formula]] — — Property: Formula
- [[notion-prop-relation]] — ✓✓ Property: Relation
- [[notion-prop-rollup]] — ◐ Property: Rollup
- [[notion-prop-audit]] — ✓ Property: Created/Edited time & by
- [[notion-prop-uid]] — ✓ Property: Unique ID
- [[notion-db-filter-sort]] — ✓ Filters & sorts
- [[notion-db-group]] — ✗ Grouping / sub-groups
- [[notion-db-subitems]] — ◐ Sub-items & dependencies
- [[notion-db-templates]] — ◐ Database templates (+recurring)
- [[notion-db-linked-views]] — ✓✓ Linked views of databases
- [[notion-db-automations]] — ◐ Database automations
- [[notion-db-forms]] — ◐ Forms

### Notion · platform

- [[notion-ai-qna]] — ◐ Notion AI: Q&A over workspace
- [[notion-ai-generation]] — — Notion AI: writing / autofill / translate / meeting notes
- [[notion-realtime-coedit]] — — Real-time co-editing
- [[notion-comments]] — ✗ Comments & discussions
- [[notion-notifications]] — ◐ Notifications / inbox
- [[notion-permissions]] — — Sharing & permissions (guests, groups)
- [[notion-publish-sites]] — ◐ Publish to web / Notion Sites
- [[notion-teamspaces]] — — Teamspaces
- [[notion-quick-find]] — ✓✓ Quick Find (⌘K)
- [[notion-api]] — ✓✓ Public API & integrations
- [[notion-webhooks]] — ✓ Webhooks
- [[notion-apps-offline]] — ◐ Desktop/mobile apps · offline
- [[notion-enterprise]] — — SSO · SCIM · audit log
- [[notion-ecosystem-apps]] — — Web Clipper · Notion Calendar · Notion Mail
- [[notion-custom-emoji]] — ✗ Custom emoji

### Obsidian · vault

- [[obsidian-local-vault]] — ✓✓ Local-first markdown vault
- [[obsidian-wikilinks]] — ✓ Wikilinks + aliases
- [[obsidian-backlinks-obs]] — ✓✓ Backlinks pane
- [[obsidian-unlinked-mentions]] — ✓ Unlinked mentions
- [[obsidian-tags-obs]] — ◐ Tags (nested)
- [[obsidian-properties-obs]] — ✓ Properties (frontmatter UI)
- [[obsidian-graph-view]] — ✓ Graph view (+ local graph)
- [[obsidian-canvas]] — ✗ Canvas
- [[obsidian-daily-notes]] — ◐ Daily notes
- [[obsidian-templates-obs]] — ◐ Templates / Templater
- [[obsidian-embeds-obs]] — ✓ Embeds — note / block / heading transclusion
- [[obsidian-block-refs]] — ✓ Block references `^id`
- [[obsidian-callouts-obs]] — ✗ Callouts (> [!note])
- [[obsidian-footnotes]] — ✗ Footnotes
- [[obsidian-mermaid]] — ✗ Mermaid diagrams
- [[obsidian-math-obs]] — ✗ Math (MathJax)
- [[obsidian-search-operators]] — ◐ Search operators
- [[obsidian-outline]] — ✗ Outline pane
- [[obsidian-bookmarks-obs]] — — Bookmarks / starred
- [[obsidian-word-count]] — ✓ Word count
- [[obsidian-themes]] — ◐ Themes / CSS snippets
- [[obsidian-bases]] — ◐ Bases (2025 core database)
- [[obsidian-sync-publish]] — ✓ Obsidian Sync / Publish (paid)
- [[obsidian-version-history-obs]] — ✓✓ Version history (Sync)
- [[obsidian-uri-mobile]] — ✗ URI scheme · mobile apps

### Obsidian · plugins

- [[obsidian-dataview]] — ✓✓ Dataview / Datacore (plugin)
- [[obsidian-graph-analysis]] — ✓✓ Graph analysis plugins
- [[obsidian-spaced-repetition]] — ◐ Spaced repetition (plugin)
- [[obsidian-kanban-plugin]] — ◐ Kanban (plugin)
- [[obsidian-excalidraw]] — ✗ Excalidraw (plugin)
